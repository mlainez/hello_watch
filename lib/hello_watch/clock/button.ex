defmodule HelloWatch.Clock.Button do
  @moduledoc "Reads the bottom gpio-keys button (KEY_VOLUMEDOWN, 114)."
  use GenServer

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(opts) do
    path =
      Path.wildcard("/sys/class/input/event*")
      |> Enum.find(fn path ->
        File.read(Path.join(path, "device/name")) == {:ok, "gpio-keys\n"}
      end)

    if path do
      port =
        Port.open(
          {:spawn_executable, System.find_executable("cat")},
          [:binary, :exit_status, args: ["/dev/input/" <> Path.basename(path)]]
        )

      {:ok, %{port: port, buffer: <<>>, target: Keyword.fetch!(opts, :target)}}
    else
      {:stop, :button_not_found}
    end
  end

  # Linux aarch64 input_event: two 64-bit timestamps, type/code/value.
  def decode(
        <<_::binary-size(16), type::little-16, code::little-16, value::little-signed-32,
          rest::binary>>
      ) do
    {events, remainder} = decode(rest)
    {[{type, code, value} | events], remainder}
  end

  def decode(partial), do: {[], partial}

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    {events, buffer} = decode(state.buffer <> data)
    for {1, 114, 1} <- events, do: send(state.target, :toggle_display)
    {:noreply, %{state | buffer: buffer}}
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state),
    do: {:stop, {:input_closed, status}, state}
end
