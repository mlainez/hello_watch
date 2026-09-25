defmodule HelloWatch.WiFiTest do
  use ExUnit.Case, async: true

  setup do
    root = Path.join(System.tmp_dir!(), "hello-watch-wifi-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  for host <- [0, 1] do
    test "derives the same MAC from eMMC on mmc#{host}", %{root: root} do
      card = Path.join(root, "mmc#{unquote(host)}/mmc#{unquote(host)}:0001")
      File.mkdir_p!(card)
      File.write!(Path.join(card, "type"), "MMC\n")
      File.write!(Path.join(card, "cid"), "001122334455667788990018FBA14800\n")
      assert HelloWatch.WiFi.stable_mac(root) == "02:18:fb:a1:48:00"
    end
  end

  test "ignores an SD card when selecting eMMC", %{root: root} do
    for {host, type, cid} <- [
          {0, "SD", "11111111111111111111111111111111"},
          {1, "MMC", "001122334455667788990018fba14800"}
        ] do
      card = Path.join(root, "mmc#{host}/mmc#{host}:0001")
      File.mkdir_p!(card)
      File.write!(Path.join(card, "type"), type <> "\n")
      File.write!(Path.join(card, "cid"), cid <> "\n")
    end

    assert HelloWatch.WiFi.stable_mac(root) == "02:18:fb:a1:48:00"
  end
end
