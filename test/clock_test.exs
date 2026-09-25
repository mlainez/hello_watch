defmodule HelloWatch.ClockTest do
  use ExUnit.Case
  alias HelloWatch.Clock
  alias HelloWatch.Clock.{Button, Face, Pages, Touch}

  defmodule FakeDisplay do
    def open, do: {:ok, Application.fetch_env!(:hello_watch, :display_test_owner)}
    def draw(owner, frame), do: send(owner, {:frame, frame}) && :ok
    def close(_), do: :ok
  end

  test "renders a round RGB888 clock with black corners and moving hands" do
    morning = Face.render(~T[03:00:00])
    later = Face.render(~T[03:00:15])
    assert byte_size(morning) == 454 * 454 * 3
    assert binary_part(morning, 0, 3) == <<0, 0, 0>>
    assert binary_part(morning, (227 * 454 + 227) * 3, 3) == <<190, 210, 64>>
    assert morning != later
    assert Face.black() == :binary.copy(<<0>>, byte_size(morning))
  end

  test "fades a frame toward black by a fraction" do
    frame = :binary.copy(<<200>>, 12)
    assert Face.fade(frame, 0) == frame
    assert Face.fade(frame, 1) == :binary.copy(<<0>>, 12)
    assert Face.fade(frame, 0.5) == :binary.copy(<<100>>, 12)
  end

  test "decodes split and batched evdev events without treating repeats as presses" do
    event = fn value -> <<0::128, 1::little-16, 114::little-16, value::little-signed-32>> end
    <<first::binary-size(11), rest::binary>> = event.(1)
    assert {[], ^first} = Button.decode(first)

    assert {[{1, 114, 1}, {1, 114, 2}, {1, 114, 0}], <<>>} =
             Button.decode(first <> rest <> event.(2) <> event.(0))
  end

  test "recognizes horizontal multitouch swipes and ignores vertical movement" do
    events = [
      {3, 57, 4},
      {3, 53, 350},
      {3, 54, 200},
      {0, 0, 0},
      {3, 53, 210},
      {3, 54, 220},
      {3, 57, -1}
    ]

    assert {[:left], %{down: false}} = Touch.gesture(events)

    vertical = [
      {1, 330, 1},
      {3, 53, 200},
      {3, 54, 100},
      {0, 0, 0},
      {3, 53, 220},
      {3, 54, 300},
      {1, 330, 0}
    ]

    assert {[], _state} = Touch.gesture(vertical)
  end

  test "renders a full RGB888 information page" do
    frame = Pages.render("NETWORK", ["WLAN0:", "  192.168.0.57"], 1)
    assert byte_size(frame) == 454 * 454 * 3
    assert binary_part(frame, 0, 3) == <<0, 0, 0>>
    refute frame == Face.black()
  end

  defp drain_frames(last, gap) do
    receive do
      {:frame, frame} -> drain_frames(frame, gap)
    after
      gap -> last
    end
  end

  test "button fades the frame to black, pauses rendering, and wakes with a fresh clock" do
    Application.put_env(:hello_watch, :display_test_owner, self())
    on_exit(fn -> Application.delete_env(:hello_watch, :display_test_owner) end)
    pid = start_supervised!({Clock, display: FakeDisplay})
    assert_receive {:frame, initial}, 2000
    refute initial == Face.black()
    Clock.toggle()
    # Contact bounce right after the real press does not cancel the fade.
    Clock.toggle()
    black = drain_frames(initial, 300)
    assert black == Face.black()
    assert %{on: false} = Clock.status()
    send(pid, :tick)
    refute_receive {:frame, _}, 300
    Clock.toggle()
    awake = drain_frames(black, 300)
    refute awake == black
    assert %{on: true} = Clock.status()
  end

  test "touch wakes a blanked screen and resets the idle timer while it is on" do
    Application.put_env(:hello_watch, :display_test_owner, self())
    on_exit(fn -> Application.delete_env(:hello_watch, :display_test_owner) end)
    pid = start_supervised!({Clock, display: FakeDisplay})
    assert_receive {:frame, initial}, 2000

    Clock.toggle()
    black = drain_frames(initial, 300)
    assert black == Face.black()

    send(pid, :touch)
    awake = drain_frames(black, 300)
    refute awake == black
    assert %{on: true} = Clock.status()
  end

  test "goes dark on its own after being idle" do
    Application.put_env(:hello_watch, :display_test_owner, self())
    on_exit(fn -> Application.delete_env(:hello_watch, :display_test_owner) end)
    pid = start_supervised!({Clock, display: FakeDisplay})
    assert_receive {:frame, initial}, 2000

    send(pid, :screen_timeout)
    black = drain_frames(initial, 300)
    assert black == Face.black()
    assert %{on: false} = Clock.status()
  end
end
