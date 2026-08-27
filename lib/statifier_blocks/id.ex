defmodule StatifierBlocks.Id do
  @moduledoc """
  Mints block and document ids: `"blk_" <> uxid` and `"bdoc_" <> uxid`,
  following the family's identifier convention (st-ADR-0008, as amended to
  drop the `uxid` dependency and mint inline -
  `statifier-ex/lib/statifier/machine_state.ex:571-585`).

  Ids are opaque to this layer and to everything downstream of it
  (ADR-0001 decision 3): nothing here or elsewhere parses one back apart,
  and no code should come to depend on the prefix or body being anything
  other than an opaque, sortable-by-mint-time string.
  """

  # Crockford base32's alphabet in `Base.hex_encode32/2`'s symbol order, so a
  # 32-entry character translation is exact and order-preserving. Crockford
  # over a fixed-width big-endian bit string keeps lexicographic order, which
  # is what makes an id sort by creation millisecond.
  @hex32_alphabet ~c"0123456789abcdefghijklmnopqrstuv"
  @crockford_alphabet ~c"0123456789abcdefghjkmnpqrstvwxyz"
  @hex32_to_crockford Map.new(Enum.zip(@hex32_alphabet, @crockford_alphabet))

  @doc "Mints a fresh `blk_`-prefixed block id."
  @spec block() :: StatifierBlocks.Block.id()
  def block, do: "blk_" <> uxid()

  @doc "Mints a fresh `bdoc_`-prefixed document id."
  @spec document() :: StatifierBlocks.Document.id()
  def document, do: "bdoc_" <> uxid()

  # st-ADR-0008: 48-bit millisecond timestamp, then 80 bits of entropy.
  @spec uxid() :: String.t()
  defp uxid do
    <<System.os_time(:millisecond)::48, :crypto.strong_rand_bytes(10)::binary>>
    |> Base.hex_encode32(case: :lower, padding: false)
    |> String.to_charlist()
    |> Enum.map(&Map.fetch!(@hex32_to_crockford, &1))
    |> List.to_string()
  end
end
