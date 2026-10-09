defmodule HelloWatch.Clock.Display do
  @moduledoc false

  # Frames are rendered as packed 454x454 BGR888. The framebuffer is either
  # SimpleDRM's (24 bpp, packed rows) or the MSM driver's fbdev emulation,
  # which pads rows to 32 pixels and usually picks XRGB8888.
  @size 454
  @row_bytes @size * 3
  @sysfs "/sys/class/graphics/fb0/"

  def open do
    with {:ok, [width, height]} <- dimensions(),
         true <- width == @size and height >= @size,
         {:ok, bpp} <- integer_attribute("bits_per_pixel"),
         true <- bpp in [24, 32],
         {:ok, stride} <- integer_attribute("stride"),
         true <- stride >= @size * div(bpp, 8),
         {:ok, fd} <- :file.open(~c"/dev/fb0", [:raw, :binary, :read, :write]) do
      unbind_fbcon()
      {:ok, %{fd: fd, bpp: bpp, stride: stride}}
    else
      other -> {:error, {:unsupported_framebuffer, other}}
    end
  end

  def draw(%{fd: fd, bpp: bpp, stride: stride}, frame),
    do: :file.pwrite(fd, 0, encode(frame, bpp, stride))

  # Blanking lets the DRM driver switch off the display pipeline and put the
  # panel to sleep; SimpleDRM cannot, so a failure here is not an error.
  def blank(_display), do: set_blank("4")
  def unblank(_display), do: set_blank("0")

  def close(%{fd: fd}), do: :file.close(fd)

  @doc false
  def encode(frame, 24, stride) when stride == @row_bytes, do: frame

  def encode(frame, 24, stride) do
    pad = :binary.copy(<<0>>, stride - @row_bytes)
    for row <- 0..(@size - 1), do: [binary_part(frame, row * @row_bytes, @row_bytes), pad]
  end

  def encode(frame, 32, stride) do
    pad = :binary.copy(<<0>>, stride - @size * 4)

    for row <- 0..(@size - 1) do
      line = binary_part(frame, row * @row_bytes, @row_bytes)
      [for(<<pixel::binary-3 <- line>>, into: <<>>, do: <<pixel::binary, 0>>), pad]
    end
  end

  defp set_blank(value) do
    _ = File.write(@sysfs <> "blank", value)
    :ok
  end

  # Stop the kernel console from painting over the clock.
  defp unbind_fbcon do
    for path <- Path.wildcard("/sys/class/vtconsole/vtcon*") do
      case File.read(Path.join(path, "name")) do
        {:ok, name} ->
          if String.contains?(name, "frame buffer"),
            do: File.write(Path.join(path, "bind"), "0")

        _ ->
          :ok
      end
    end
  end

  defp dimensions do
    with {:ok, value} <- attribute("virtual_size") do
      {:ok, value |> String.split(",") |> Enum.map(&String.to_integer/1)}
    end
  end

  defp integer_attribute(name) do
    with {:ok, value} <- attribute(name), do: {:ok, String.to_integer(value)}
  end

  defp attribute(name) do
    case File.read(@sysfs <> name) do
      {:ok, value} -> {:ok, String.trim(value)}
      error -> error
    end
  end
end
