defmodule StatifierBlocks.IdTest do
  use ExUnit.Case, async: true

  alias StatifierBlocks.Id

  @crockford_alphabet ~c"0123456789abcdefghjkmnpqrstvwxyz"

  # sabotage: change "blk_" <> uxid() to "blok_" <> uxid() -> red
  test "block/0 returns a blk_-prefixed 26-character Crockford body" do
    id = Id.block()

    assert "blk_" <> body = id
    assert String.length(body) == 26
    assert String.to_charlist(body) |> Enum.all?(&(&1 in @crockford_alphabet))
  end

  # sabotage: change "bdoc_" <> uxid() to "doc_" <> uxid() -> red
  test "document/0 returns a bdoc_-prefixed 26-character Crockford body" do
    id = Id.document()

    assert "bdoc_" <> body = id
    assert String.length(body) == 26
    assert String.to_charlist(body) |> Enum.all?(&(&1 in @crockford_alphabet))
  end

  # sabotage: hardcode a fixed 80-bit entropy value instead of
  # :crypto.strong_rand_bytes(10) -> red (two calls would collide)
  test "two calls to block/0 differ" do
    refute Id.block() == Id.block()
  end

  # sabotage: put the entropy bytes before the timestamp instead of after
  # (`<<:crypto.strong_rand_bytes(10)::binary, System.os_time(:millisecond)::48>>`)
  # -> red (lexicographic order is now dominated by random bytes, not mint time)
  test "ids minted in increasing milliseconds sort lexicographically in that order" do
    first = Id.block()
    Process.sleep(2)
    second = Id.block()
    Process.sleep(2)
    third = Id.block()

    assert Enum.sort([third, first, second]) == [first, second, third]
  end
end
