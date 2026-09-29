defmodule HelloWatch.PmicRtcTest do
  use ExUnit.Case, async: true

  alias HelloWatch.PmicRtc

  @moduletag :capture_log

  setup do
    root = Path.join(System.tmp_dir!(), "hello-watch-rtc-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    rtc = Path.join(root, "since_epoch")
    opts = [rtc_path: rtc, offset_file: Path.join(root, "offset")]
    %{rtc: rtc, opts: opts}
  end

  defp set_raw(rtc, raw), do: File.write!(rtc, "#{raw}\n")

  test "fails to initialize without an RTC", %{opts: opts} do
    assert {:error, :enoent} = PmicRtc.init(opts)
  end

  test "is unset until a time has been saved", %{rtc: rtc, opts: opts} do
    set_raw(rtc, 1000)
    {:ok, state} = PmicRtc.init(opts)
    assert {:unset, _} = PmicRtc.get_time(state)
  end

  test "restores the time after a power cycle", %{rtc: rtc, opts: opts} do
    set_raw(rtc, 1000)
    {:ok, state} = PmicRtc.init(opts)
    PmicRtc.set_time(state, ~N[2026-09-28 12:00:00])

    set_raw(rtc, 1000 + 86_400)
    {:ok, state} = PmicRtc.init(opts)
    assert {:ok, ~N[2026-09-29 12:00:00], _} = PmicRtc.get_time(state)
  end

  test "skips writes for small drift", %{rtc: rtc, opts: opts} do
    set_raw(rtc, 1000)
    {:ok, state} = PmicRtc.init(opts)
    state = PmicRtc.set_time(state, ~N[2026-09-28 12:00:00])
    saved = File.read!(opts[:offset_file])

    set_raw(rtc, 1660)
    state = PmicRtc.set_time(state, ~N[2026-09-28 12:11:01])
    assert File.read!(opts[:offset_file]) == saved

    PmicRtc.set_time(state, ~N[2026-09-28 12:11:05])
    refute File.read!(opts[:offset_file]) == saved
  end

  test "ignores the saved offset after the counter resets", %{rtc: rtc, opts: opts} do
    set_raw(rtc, 50_000)
    {:ok, state} = PmicRtc.init(opts)
    PmicRtc.set_time(state, ~N[2026-09-28 12:00:00])

    set_raw(rtc, 10)
    {:ok, state} = PmicRtc.init(opts)
    assert {:unset, _} = PmicRtc.get_time(state)
  end
end
