defmodule HelloWatch.Clock.Pages do
  @moduledoc false
  alias HelloWatch.Clock.Font

  @size 454
  @background {5, 12, 18}
  @white {224, 234, 242}
  @muted {105, 130, 145}
  @accent {64, 210, 190}

  def render(title, lines, page) do
    pixels = text(%{}, 42, 48, title, 3, @accent)

    pixels =
      lines
      |> Enum.take(15)
      |> Enum.with_index()
      |> Enum.reduce(pixels, fn {line, index}, acc ->
        text(acc, 42, 94 + index * 20, String.slice(to_string(line), 0, 30), 2, @white)
      end)
      |> page_dots(page)

    encode(pixels)
  end

  defp text(pixels, x, y, value, scale, color) do
    value
    |> to_string()
    |> String.upcase()
    |> String.to_charlist()
    |> Enum.with_index()
    |> Enum.reduce(pixels, fn {char, index}, acc ->
      glyph(acc, x + index * 6 * scale, y, Font.glyph(char), scale, color)
    end)
  end

  defp glyph(pixels, x, y, rows, scale, color) do
    rows
    |> Enum.with_index()
    |> Enum.reduce(pixels, fn {bits, row}, acc ->
      for col <- 0..4,
          Bitwise.band(bits, Bitwise.bsl(1, 4 - col)) != 0,
          py <- 0..(scale - 1),
          px <- 0..(scale - 1),
          reduce: acc do
        map -> Map.put(map, (y + row * scale + py) * @size + x + col * scale + px, color)
      end
    end)
  end

  defp page_dots(pixels, selected) do
    Enum.reduce(0..2, pixels, fn index, acc ->
      color = if index == selected, do: @accent, else: @muted
      cx = 211 + index * 16

      for y <- 420..425, x <- (cx - 3)..(cx + 3), reduce: acc do
        map ->
          if (x - cx) * (x - cx) + (y - 422) * (y - 422) <= 10,
            do: Map.put(map, y * @size + x, color),
            else: map
      end
    end)
  end

  defp encode(pixels) do
    center = div(@size, 2)

    for i <- 0..(@size * @size - 1), into: <<>> do
      x = rem(i, @size)
      y = div(i, @size)

      default =
        if (x - center) * (x - center) + (y - center) * (y - center) <= center * center,
          do: @background,
          else: {0, 0, 0}

      {r, g, b} = Map.get(pixels, i, default)
      <<b, g, r>>
    end
  end
end
