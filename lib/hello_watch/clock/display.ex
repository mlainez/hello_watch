defmodule HelloWatch.Clock.Display do
  @moduledoc false

  def open do
    with {:ok, "454,454"} <- attribute("virtual_size"),
         {:ok, "24"} <- attribute("bits_per_pixel"),
         {:ok, "1362"} <- attribute("stride"),
         {:ok, fd} <- :file.open(~c"/dev/fb0", [:raw, :binary, :read, :write]) do
      # Stop the kernel console from painting over the clock.
      for path <- Path.wildcard("/sys/class/vtconsole/vtcon*") do
        case File.read(Path.join(path, "name")) do
          {:ok, name} ->
            if String.contains?(name, "frame buffer"),
              do: File.write(Path.join(path, "bind"), "0")

          _ ->
            :ok
        end
      end

      {:ok, fd}
    else
      other -> {:error, {:unsupported_framebuffer, other}}
    end
  end

  def draw(fd, frame), do: :file.pwrite(fd, 0, frame)
  def close(fd), do: :file.close(fd)

  defp attribute(name) do
    case File.read("/sys/class/graphics/fb0/" <> name) do
      {:ok, value} -> {:ok, String.trim(value)}
      error -> error
    end
  end
end
