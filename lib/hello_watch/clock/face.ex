defmodule HelloWatch.Clock.Face do
  @moduledoc "Software-rendered round analog face for the watch's RGB888 framebuffer."
  alias HelloWatch.Clock.Raster

  @size 454
  @center 227
  @white {224, 234, 242}
  @accent {64, 210, 190}
  @low {236, 96, 96}

  # Charge indicator, drawn below the centre so the hands sweep over it the way
  # they would over a printed subdial.
  @battery_y 330
  @battery_width 46
  @battery_height 20
  @battery_low 15

  # Small "N" mark above centre, same idea as the charge indicator: it sits
  # in the hands' sweep and is drawn once into the cached background rather
  # than every tick.
  @logo_top 118
  @logo_bottom 142
  @logo_left 217
  @logo_right 237

  @doc "An encoded frame with the tick marks and logo, cached once by the caller."
  def background, do: Raster.patch(Raster.solid(@size, {0, 0, 0}), tick_marks() |> nerves_mark())

  defp tick_marks do
    Enum.reduce(0..59, %{}, fn tick, pixels ->
      major = rem(tick, 5) == 0

      line(
        pixels,
        point(tick / 60, if(major, do: 185, else: 197)),
        point(tick / 60, 205),
        if(major, do: 3, else: 1),
        if(major, do: @white, else: {65, 80, 92})
      )
    end)
  end

  defp nerves_mark(pixels) do
    pixels
    |> line({@logo_left, @logo_top}, {@logo_left, @logo_bottom}, 1.5, @accent)
    |> line({@logo_right, @logo_top}, {@logo_right, @logo_bottom}, 1.5, @accent)
    |> line({@logo_left, @logo_top}, {@logo_right, @logo_bottom}, 1.5, @accent)
  end

  # The hands and battery indicator sweep across the whole face, including
  # over the tick marks and logo baked into `background`, so every stroke
  # below blends against that frame's real pixels rather than assuming
  # black - only the small region each stroke actually touches is looked
  # up, so this stays cheap despite not re-encoding all size*size pixels.
  def render(time, background \\ background(), battery \\ nil) do
    seconds = time.second
    minutes = time.minute + seconds / 60
    hours = rem(time.hour, 12) + minutes / 60

    overlay =
      %{}
      |> battery(battery, background)
      |> line(point(hours / 12, -16), point(hours / 12, 112), 6, @white, background)
      |> line(point(minutes / 60, -22), point(minutes / 60, 163), 4, @white, background)
      |> line(point(seconds / 60, -32), point(seconds / 60, 177), 1.5, @accent, background)
      |> line({@center, @center}, {@center, @center}, 7, @accent, background)

    Raster.patch(background, overlay)
  end

  def black, do: Raster.solid(@size, {0, 0, 0})

  @doc "Scales an encoded RGB888 frame toward black; fraction 0 is unchanged, 1 is black."
  def fade(frame, fraction) when fraction <= 0, do: frame
  def fade(frame, fraction) when fraction >= 1, do: :binary.copy(<<0>>, byte_size(frame))

  def fade(frame, fraction) do
    scale = 1 - fraction
    for <<byte <- frame>>, into: <<>>, do: <<round(byte * scale)>>
  end

  defp battery(pixels, nil, _background), do: pixels

  defp battery(pixels, percent, background) when is_number(percent) do
    level = percent |> max(0) |> min(100)
    left = @center - @battery_width / 2
    right = @center + @battery_width / 2
    top = @battery_y - @battery_height / 2
    bottom = @battery_y + @battery_height / 2

    pixels
    |> line({left, top}, {right, top}, 1, @white, background)
    |> line({left, bottom}, {right, bottom}, 1, @white, background)
    |> line({left, top}, {left, bottom}, 1, @white, background)
    |> line({right, top}, {right, bottom}, 1, @white, background)
    |> line({right + 3, @battery_y - 4}, {right + 3, @battery_y + 4}, 2, @white, background)
    |> charge(left, right, level, background)
  end

  defp charge(pixels, left, right, level, background) do
    span = right - left - 8
    width = span * level / 100

    if width < 1 do
      pixels
    else
      line(
        pixels,
        {left + 4, @battery_y},
        {left + 4 + width, @battery_y},
        5,
        if(level <= @battery_low, do: @low, else: @accent),
        background
      )
    end
  end

  defp point(turn, radius) do
    angle = turn * 2 * :math.pi()
    {@center + :math.sin(angle) * radius, @center - :math.cos(angle) * radius}
  end

  defp line(pixels, {ax, ay}, {bx, by}, radius, color, background \\ nil) do
    dx = bx - ax
    dy = by - ay
    length_squared = max(dx * dx + dy * dy, 0.0001)

    for y <- max(0, floor(min(ay, by) - radius))..min(@size - 1, ceil(max(ay, by) + radius)),
        x <- max(0, floor(min(ax, bx) - radius))..min(@size - 1, ceil(max(ax, bx) + radius)),
        reduce: pixels do
      acc ->
        t = min(1, max(0, ((x - ax) * dx + (y - ay) * dy) / length_squared))
        distance = :math.sqrt(:math.pow(x - ax - t * dx, 2) + :math.pow(y - ay - t * dy, 2))
        coverage = min(1, max(0, radius + 0.5 - distance))

        if coverage > 0 do
          index = y * @size + x
          {r, g, b} = color
          {br, bg, bb} = Map.get_lazy(acc, index, fn -> underlying(background, index) end)
          blend = fn c, base -> round(c * coverage + base * (1 - coverage)) end
          Map.put(acc, index, {blend.(r, br), blend.(g, bg), blend.(b, bb)})
        else
          acc
        end
    end
  end

  defp underlying(nil, _index), do: {0, 0, 0}

  defp underlying(background, index) do
    <<b, g, r>> = binary_part(background, index * 3, 3)
    {r, g, b}
  end
end
