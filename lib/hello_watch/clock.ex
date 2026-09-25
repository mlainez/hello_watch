defmodule HelloWatch.Clock do
  @moduledoc "Swipeable clock, network and sensor display. Time defaults to UTC."
  use GenServer

  alias HelloWatch.Clock.{Display, Face, Pages}
  alias HelloWatch.Sensors

  @pages [:clock, :network, :sensors]

  # The hub delivers every event to a single reader, so one stream serves the
  # whole app: charge alone while the face is up, plus the rest on the sensor
  # page. See HelloWatch.Sensors.open/1.
  @idle_stream [:battery]
  @sensor_stream [:battery, :heart, {:accel, 25}, {:gyro, 25}]

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  def toggle, do: send(__MODULE__, :toggle_display)
  def status, do: GenServer.call(__MODULE__, :status)

  @impl true
  def init(opts) do
    display = Keyword.get(opts, :display, Display)

    with {:ok, fd} <- display.open() do
      state = %{
        display: display,
        fd: fd,
        on: true,
        page: 0,
        background: Face.background(),
        time_zone: Keyword.get(opts, :time_zone, "Etc/UTC"),
        last_press: nil,
        sensor_port: nil,
        battery: nil,
        sensors: %{},
        sensor_errors: %{},
        render_timer: nil
      }

      send(self(), :tick)
      {:ok, stream(state, @idle_stream)}
    else
      error -> {:stop, error}
    end
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply,
     %{
       on: state.on,
       page: Enum.at(@pages, state.page),
       time_zone: state.time_zone,
       battery: state.battery
     }, state}
  end

  @impl true
  def handle_info(:tick, state) do
    if state.on, do: draw(state)
    Process.send_after(self(), :tick, 1000 - rem(System.system_time(:millisecond), 1000))
    {:noreply, state}
  end

  def handle_info(:refresh, state) do
    state = %{state | render_timer: nil}
    if state.on, do: draw(state)
    {:noreply, state}
  end

  def handle_info(:toggle_display, state) do
    now = System.monotonic_time(:millisecond)

    if state.last_press == nil or now - state.last_press >= 250 do
      state =
        if state.on do
          state |> leave_page(state.page) |> Map.merge(%{on: false, last_press: now})
        else
          state |> Map.merge(%{on: true, last_press: now}) |> enter_page(state.page)
        end

      if state.on, do: draw(state), else: :ok = state.display.draw(state.fd, Face.black())
      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  def handle_info({:swipe, _direction}, %{on: false} = state), do: {:noreply, state}

  def handle_info({:swipe, direction}, state) when direction in [:left, :right] do
    step = if direction == :left, do: 1, else: -1
    next = Integer.mod(state.page + step, length(@pages))
    state = state |> leave_page(state.page) |> Map.put(:page, next) |> enter_page(next)
    if state.on, do: draw(state)
    {:noreply, state}
  end

  def handle_info({port, _payload} = message, %{sensor_port: port} = state)
      when is_port(port) do
    {:noreply, queue_render(handle_sensor(state, Sensors.decode(port, message)))}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_, state) do
    close_sensors(state.sensor_port)
    state.display.close(state.fd)
  end

  defp enter_page(state, 2), do: stream(state, @sensor_stream)
  defp enter_page(state, _), do: state

  # Drop the last readings on the way out: they would otherwise sit on the page
  # looking live when the stream that produced them is no longer running.
  defp leave_page(state, 2), do: %{stream(state, @idle_stream) | sensors: %{}}
  defp leave_page(state, _), do: state

  defp stream(state, sensors) do
    close_sensors(state.sensor_port)

    case Sensors.open(sensors) do
      {:ok, port} ->
        %{state | sensor_port: port, sensor_errors: %{}}

      {:error, reason} ->
        %{state | sensor_port: nil, sensor_errors: %{stream: inspect(reason)}}
    end
  end

  defp close_sensors(nil), do: :ok

  defp close_sensors(port) do
    if Port.info(port), do: Sensors.close(port)
  end

  defp handle_sensor(state, {:sensor, _port, event} = message) do
    case Sensors.sensor_from_event(event) do
      nil -> state
      sensor -> update_sensor(state, sensor, message)
    end
  end

  defp handle_sensor(state, {:sensor_error, _port, _reason, line}),
    do: put_in(state, [:sensor_errors, :stream], String.trim(line))

  defp handle_sensor(state, {:sensor_exit, _port, status}) do
    %{state | sensor_port: nil}
    |> put_in([:sensor_errors, :stream], "EXIT #{status}")
  end

  defp handle_sensor(state, _message), do: state

  defp update_sensor(state, :battery, {:sensor, _port, event}),
    do: %{state | battery: event["percent"]}

  defp update_sensor(state, sensor, {:sensor, _port, event}) do
    state
    |> put_in([:sensors, sensor], event)
    |> update_in([:sensor_errors], &Map.delete(&1, sensor))
  end

  defp queue_render(%{page: 2, on: true, render_timer: nil} = state),
    do: %{state | render_timer: Process.send_after(self(), :refresh, 200)}

  defp queue_render(state), do: state

  defp draw(%{page: 0} = state) do
    :ok =
      state.display.draw(
        state.fd,
        Face.render(local_time(state), state.background, state.battery)
      )
  end

  defp draw(%{page: 1} = state),
    do: state.display.draw(state.fd, Pages.render("NETWORK", network_lines(), 1))

  defp draw(%{page: 2} = state),
    do: state.display.draw(state.fd, Pages.render("SENSORS", sensor_lines(state), 2))

  defp local_time(state) do
    now = DateTime.utc_now()

    case DateTime.shift_zone(now, state.time_zone) do
      {:ok, local} -> local
      {:error, _reason} -> now
    end
  end

  defp network_lines do
    hostname =
      case :inet.gethostname() do
        {:ok, name} -> to_string(name)
        _ -> "UNKNOWN"
      end

    interfaces =
      case :inet.getifaddrs() do
        {:ok, ifs} ->
          Enum.flat_map(ifs, fn {name, attrs} ->
            addresses =
              attrs
              |> Keyword.get_values(:addr)
              |> Enum.reject(&loopback?/1)
              |> Enum.map(&(:inet.ntoa(&1) |> to_string()))

            if addresses == [],
              do: [],
              else: [to_string(name) <> ":"] ++ Enum.map(addresses, &("  " <> &1))
          end)

        _ ->
          ["INTERFACES UNAVAILABLE"]
      end

    (["HOST " <> hostname] ++ interfaces) |> Enum.take(15)
  end

  defp loopback?({127, _, _, _}), do: true
  defp loopback?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  defp loopback?(_), do: false

  defp sensor_lines(state) do
    heart = state.sensors[:heart] || %{}
    accel = state.sensors[:accel] || %{}
    gyro = state.sensors[:gyro] || %{}

    [
      stream_error(state),
      "HEART RATE",
      "  #{number(heart["value"], 0)} BPM",
      sensor_error(state, :heart),
      "ACCELEROMETER",
      "  X #{number(accel["x"], 4)}",
      "  Y #{number(accel["y"], 4)}",
      "  Z #{number(accel["z"], 4)}",
      sensor_error(state, :accel),
      "GYROSCOPE",
      "  X #{number(gyro["x"], 4)}",
      "  Y #{number(gyro["y"], 4)}",
      "  Z #{number(gyro["z"], 4)}",
      sensor_error(state, :gyro)
    ]
    |> Enum.reject(&(&1 == ""))
  end

  defp stream_error(state) do
    case state.sensor_errors[:stream] do
      nil -> ""
      error -> "STREAM " <> error
    end
  end

  defp sensor_error(state, sensor) do
    case state.sensor_errors[sensor] do
      nil -> ""
      error -> "  " <> error
    end
  end

  defp number(nil, _digits), do: "--"

  defp number(value, digits) when is_number(value),
    do: :erlang.float_to_binary(value / 1, decimals: digits)

  defp number(value, _digits), do: to_string(value)

  # Debug function to inspect state
  def debug_state do
    state = GenServer.call(__MODULE__, :get_full_state)
    %{
      page: state.page,
      sensors: state.sensors,
      sensor_port: state.sensor_port,
      sensor_errors: state.sensor_errors
    }
  end

  def handle_call(:get_full_state, _from, state) do
    {:reply, state, state}
  end
end
