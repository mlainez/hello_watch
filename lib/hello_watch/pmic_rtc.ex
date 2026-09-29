defmodule HelloWatch.PmicRtc do
  @moduledoc """
  NervesTime real-time clock backed by the PM660 PMIC RTC.

  The PMIC counter keeps running while the watch is off, but Linux is not
  allowed to write it: the rtc-pm8xxx driver has neither `allow-set-time` nor
  an offset store on this board, so `/sys/class/rtc/rtc0/since_epoch` always
  reports the raw counter. Like Qualcomm's `time_daemon` on Wear OS, this
  module keeps `utc - raw` in a file on the persistent data partition and adds
  it back on boot.

  The file also records the raw counter at the time it was written. A counter
  lower than that means the PMIC lost power (battery fully drained), so the
  saved offset no longer applies and the clock reports `:unset`.
  """

  if Code.ensure_loaded?(NervesTime.RealTimeClock) do
    @behaviour NervesTime.RealTimeClock
  end

  require Logger

  @default_rtc_path "/sys/class/rtc/rtc0/since_epoch"
  @default_offset_file ".pmic_rtc_offset"
  @unix_epoch ~N[1970-01-01 00:00:00]

  # NervesTime calls set_time/2 on every NTP update (about every 11 minutes);
  # only drift beyond this is worth a write to flash.
  @rewrite_threshold_s 2

  defstruct [:rtc_path, :offset_file, :offset, :saved_raw]

  @doc false
  def init(args) do
    state = %__MODULE__{
      rtc_path: Keyword.get(args, :rtc_path, @default_rtc_path),
      offset_file:
        Keyword.get(args, :offset_file, @default_offset_file) |> Path.expand(System.user_home()),
      offset: nil,
      saved_raw: nil
    }

    case read_raw(state) do
      {:ok, _raw} -> {:ok, load_offset(state)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc false
  def terminate(_state), do: :ok

  @doc false
  def get_time(%{offset: nil} = state), do: {:unset, state}

  def get_time(state) do
    case read_raw(state) do
      {:ok, raw} when raw >= state.saved_raw ->
        {:ok, NaiveDateTime.add(@unix_epoch, raw + state.offset, :second), state}

      {:ok, raw} ->
        Logger.warning(
          "[PmicRtc] RTC counter went backwards (#{raw} < #{state.saved_raw}); ignoring saved offset"
        )

        {:unset, state}

      {:error, _reason} ->
        {:unset, state}
    end
  end

  @doc false
  def set_time(state, %NaiveDateTime{} = now) do
    with {:ok, raw} <- read_raw(state),
         offset = NaiveDateTime.diff(now, @unix_epoch, :second) - raw,
         true <- needs_write?(state, offset, raw),
         :ok <- write_offset(state.offset_file, offset, raw) do
      %{state | offset: offset, saved_raw: raw}
    else
      false ->
        state

      {:error, reason} ->
        Logger.warning("[PmicRtc] Cannot save RTC offset: #{inspect(reason)}")
        state
    end
  end

  defp needs_write?(%{offset: nil}, _offset, _raw), do: true

  defp needs_write?(state, offset, raw) do
    raw < state.saved_raw or abs(offset - state.offset) >= @rewrite_threshold_s
  end

  defp write_offset(path, offset, raw) do
    tmp = path <> ".tmp"

    with :ok <- File.write(tmp, "#{offset} #{raw}\n", [:sync]) do
      File.rename(tmp, path)
    end
  end

  defp read_raw(state) do
    with {:ok, contents} <- File.read(state.rtc_path),
         {raw, _} <- Integer.parse(contents) do
      {:ok, raw}
    else
      {:error, reason} -> {:error, reason}
      :error -> {:error, :invalid_rtc_value}
    end
  end

  defp load_offset(state) do
    with {:ok, contents} <- File.read(state.offset_file),
         [offset, raw] <- String.split(contents),
         {offset, ""} <- Integer.parse(offset),
         {raw, ""} <- Integer.parse(raw) do
      %{state | offset: offset, saved_raw: raw}
    else
      _ -> state
    end
  end
end
