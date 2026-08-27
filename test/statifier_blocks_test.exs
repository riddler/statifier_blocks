defmodule StatifierBlocksTest do
  use ExUnit.Case, async: true

  doctest StatifierBlocks

  test "the root module is loadable" do
    assert Code.ensure_loaded?(StatifierBlocks)
  end
end
