defmodule HelloWatch.Clock.Raster do
  @moduledoc "Encodes and patches sparse RGB888 pixel overlays onto a frame."

  @doc "An encoded size*size RGB888 frame filled with one color."
  def solid(size, {r, g, b}), do: :binary.copy(<<b, g, r>>, size * size)

  @doc """
  Overwrites `frame` with the pixels in `overlay`, a sparse
  `%{pixel_index => {r, g, b}}` map. Unpatched runs are copied from `frame`
  as whole slices rather than pixel by pixel, so cost scales with the number
  of overlay entries rather than the frame's full size - the point of
  keeping `overlay` sparse instead of building a full pixel map every frame.
  """
  def patch(frame, overlay) when map_size(overlay) == 0, do: frame

  def patch(frame, overlay) do
    {chunks, last_offset} =
      overlay
      |> Map.keys()
      |> Enum.sort()
      |> Enum.reduce({[], 0}, fn index, {chunks, prev_end} ->
        offset = index * 3
        {r, g, b} = overlay[index]
        gap = binary_part(frame, prev_end, offset - prev_end)
        {[<<b, g, r>>, gap | chunks], offset + 3}
      end)

    tail = binary_part(frame, last_offset, byte_size(frame) - last_offset)
    [tail | chunks] |> Enum.reverse() |> IO.iodata_to_binary()
  end
end
