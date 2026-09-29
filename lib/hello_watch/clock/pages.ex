defmodule HelloWatch.Clock.Pages do
  @moduledoc false
  alias HelloWatch.Clock.{Font, Raster}

  @size 454
  @background {5, 12, 18}
  @white {224, 234, 242}
  @muted {105, 130, 145}
  @accent {64, 210, 190}

  # The panel is round: at the title's row the visible span is only about
  # x 87..366, and the body rows reach the edge near x 49, so the title is
  # centred and the body is inset past the curve.
  @title_y 48
  @title_scale 3
  @body_x 60

  # The circular fill never changes, so it is computed once at compile time
  # rather than rebuilt on every render; only the sparse text/dots overlay
  # below is computed per frame and patched onto a copy of this.
  @base_frame (fn ->
                 center = div(@size, 2)
                 {r, g, b} = @background
                 fill = <<b, g, r>>
                 black = <<0, 0, 0>>

                 for y <- 0..(@size - 1), x <- 0..(@size - 1), into: <<>> do
                   if (x - center) * (x - center) + (y - center) * (y - center) <=
                        center * center,
                      do: fill,
                      else: black
                 end
               end).()

  def render(title, lines, page) do
    pixels = text(%{}, centered_x(title, @title_scale), @title_y, title, @title_scale, @accent)

    pixels =
      lines
      |> Enum.take(15)
      |> Enum.with_index()
      |> Enum.reduce(pixels, fn {line, index}, acc ->
        text(acc, @body_x, 94 + index * 20, String.slice(to_string(line), 0, 28), 2, @white)
      end)
      |> page_dots(page)

    Raster.patch(@base_frame, pixels)
  end

  # Glyphs are 5 columns wide on a 6-column advance.
  defp centered_x(value, scale) do
    width = String.length(to_string(value)) * 6 * scale - scale
    div(@size - width, 2)
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
end
