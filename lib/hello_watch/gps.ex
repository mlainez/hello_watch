defmodule HelloWatch.GPS do
  @moduledoc """
  On-demand interface to the watch's stock Broadcom GPS stack.

  Call `start_stream/0`, then `subscribe/0`. Subscribers receive decoded
  `{:gps, event}` maps for locations, NMEA sentences, status and errors.
  GPS remains off until explicitly started.
  """

  use GenServer
  require Logger

  @gpsctl "/usr/bin/gpsctl"

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def start_stream, do: GenServer.call(__MODULE__, :start_stream, 15_000)
  def stop_stream, do: GenServer.call(__MODULE__, :stop_stream)
  def subscribe(pid \\ self()), do: GenServer.call(__MODULE__, {:subscribe, pid})
  def unsubscribe(pid \\ self()), do: GenServer.call(__MODULE__, {:unsubscribe, pid})
  def latest, do: GenServer.call(__MODULE__, :latest)

  @impl true
  def init(_opts) do
    {:ok, %{port: nil, subscribers: MapSet.new(), latest: nil, buffer: ""}}
  end

  @impl true
  def handle_call(:start_stream, _from, %{port: port} = state) when is_port(port) do
    {:reply, :ok, state}
  end

  def handle_call(:start_stream, _from, state) do
    if not File.exists?(@gpsctl) do
      {:reply, {:error, :unsupported}, state}
    else
      try do
        port =
          Port.open({:spawn_executable, @gpsctl}, [
            :binary,
            :exit_status,
            :stderr_to_stdout,
            args: ["stream"]
          ])

        {:reply, :ok, %{state | port: port, buffer: ""}}
      rescue
        error ->
          Logger.error("GPS port open failed: #{inspect(error)}")
          {:reply, {:error, {:port_open_failed, inspect(error)}}, state}
      end
    end
  end

  def handle_call(:stop_stream, _from, state) do
    if is_port(state.port), do: Port.close(state.port)
    _ = System.cmd(@gpsctl, ["stop"], stderr_to_stdout: true)
    {:reply, :ok, %{state | port: nil, buffer: ""}}
  end

  def handle_call({:subscribe, pid}, _from, state) do
    Process.monitor(pid)
    {:reply, :ok, %{state | subscribers: MapSet.put(state.subscribers, pid)}}
  end

  def handle_call({:unsubscribe, pid}, _from, state) do
    {:reply, :ok, %{state | subscribers: MapSet.delete(state.subscribers, pid)}}
  end

  def handle_call(:latest, _from, state), do: {:reply, state.latest, state}

  @impl true
  def handle_info({port, {:data, bytes}}, %{port: port} = state) do
    {lines, buffer} = split_lines(state.buffer <> bytes)
    state = Enum.reduce(lines, %{state | buffer: buffer}, &publish/2)
    {:noreply, state}
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    event = %{"type" => "error", "stage" => "gpsctl", "exit_status" => status}
    {:noreply, publish_event(event, %{state | port: nil, buffer: ""})}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, %{state | subscribers: MapSet.delete(state.subscribers, pid)}}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    if is_port(state.port), do: Port.close(state.port)
    if File.exists?(@gpsctl), do: System.cmd(@gpsctl, ["stop"], stderr_to_stdout: true)
    :ok
  end

  defp split_lines(data) do
    parts = String.split(data, "\n")
    {Enum.drop(parts, -1), List.last(parts) || ""}
  end

  defp publish("", state), do: state

  defp publish(line, state) do
    case Jason.decode(line) do
      {:ok, event} ->
        publish_event(event, state)

      {:error, _} ->
        Logger.debug("GPS helper: #{line}")
        state
    end
  end

  defp publish_event(event, state) do
    Enum.each(state.subscribers, &send(&1, {:gps, event}))
    latest = if event["type"] == "location", do: event, else: state.latest
    %{state | latest: latest}
  end
end
