defmodule StatifierBlocksTest do
  use ExUnit.Case, async: true

  doctest StatifierBlocks

  test "the package scaffold compiles and the root module is loadable" do
    assert Code.ensure_loaded?(StatifierBlocks)
  end
end
