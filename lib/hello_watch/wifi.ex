defmodule HelloWatch.WiFi do
  @moduledoc false

  require Logger

  @interface "wlan0"
  # VintageNetWiFi calls this before starting wpa_supplicant. Supplying the
  # address through VintageNet also makes it emit mac_addr=0 and
  # preassoc_mac_addr=0, so the supplicant cannot replace it while scanning.
  def stable_mac(sysfs_root \\ "/sys/class/mmc_host") do
    # Probe order changes between kernels; select the MMC card, not mmc0.
    cid_path =
      sysfs_root
      |> Path.join("mmc*/mmc*:*/cid")
      |> Path.wildcard()
      |> Enum.find(fn path ->
        case File.read(Path.join(Path.dirname(path), "type")) do
          {:ok, type} -> String.trim(type) == "MMC"
          _ -> false
        end
      end)

    with cid_path when is_binary(cid_path) <- cid_path,
         {:ok, cid} <- File.read(cid_path),
         true <- Regex.match?(~r/\A[0-9a-fA-F]{32}\z/, String.trim(cid)),
         suffix when byte_size(suffix) == 10 <- cid |> String.trim() |> String.slice(-10, 10) do
      octets = for <<octet::binary-size(2) <- suffix>>, do: String.downcase(octet)
      Enum.join(["02" | octets], ":")
    else
      reason ->
        Logger.warning(
          "Could not derive the Wi-Fi MAC address from the eMMC CID: #{inspect(reason)}"
        )

        current_mac()
    end
  end

  defp current_mac do
    case File.read("/sys/class/net/#{@interface}/address") do
      {:ok, mac} -> String.trim(mac)
      _ -> "02:00:00:00:00:01"
    end
  end
end
