defmodule HelloWatchTest do
  use ExUnit.Case
  doctest HelloWatch

  test "greets the world" do
    assert HelloWatch.hello() == :world
  end
end
