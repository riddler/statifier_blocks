defmodule StatifierBlocks.Compiler.AttributionTest do
  @moduledoc """
  The three rules `StatifierBlocks.Compiler.Attribution` applies, and the
  one thing it refuses (ADR-0004 decision 5).
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Compiler, Document, Emission, Palette, Provenance}
  alias StatifierBlocks.Compiler.{Attribution, Context, Finding}
  alias StatifierBlocks.Core.Emit

  defp known(ids), do: MapSet.new(ids)

  # Sabotage: made `own_owner/3`'s `nil`-hint clause return
  # `Provenance.owner(nil)` - red, because an unhinted element then has no
  # block at all.
  test "an unhinted element belongs to the block that emitted it" do
    emission = Emission.element("state", [{"id", "s_blk_A"}], [Emission.element("onentry")])

    assert {:ok, stamped} = Attribution.stamp(emission, "blk_A", known(["blk_A"]))
    assert stamped.owner == Provenance.owner("blk_A")
    assert [%Emission{owner: owner}] = stamped.children
    assert owner == Provenance.owner("blk_A")
  end

  # Sabotage: removed the `block_id == owner.block_id` guard from
  # `Attribution.role/2` - red, because an element attributed to a child
  # then steals the role encoded in the id it happens to carry.
  test "a role is taken only from a state id this owner's block minted" do
    emission =
      Emission.element("state", [{"id", "s_blk_A"}], [
        Emission.element("state", [{"id", "s_blk_A__pick"}], [
          Emission.element("transition", [{"target", "s_blk_B"}])
        ]),
        Emission.attributed_to(Emission.element("state", [{"id", "s_blk_A__pick"}]), "blk_B")
      ])

    assert {:ok, stamped} = Attribution.stamp(emission, "blk_A", known(["blk_A", "blk_B"]))
    assert [pick, borrowed] = stamped.children

    assert pick.owner == Provenance.owner("blk_A", role: "pick")
    assert [inherited] = pick.children
    assert inherited.owner == Provenance.owner("blk_A", role: "pick")
    assert borrowed.owner == Provenance.owner("blk_B")
  end

  # Sabotage: made `from_config/2` set `block_id` to the key rather than
  # leaving it nil - red, because the element is then attributed to a
  # block that does not exist.
  test "a config key set on an element reaches its whole subtree" do
    emission =
      Emission.element("state", [{"id", "s_blk_A"}], [
        Emission.from_config(Emission.element("send", [{"event", "cards.hold"}]), "timeout")
      ])

    assert {:ok, stamped} = Attribution.stamp(emission, "blk_A", known(["blk_A"]))
    assert [send] = stamped.children
    assert send.owner == Provenance.owner("blk_A", config_key: "timeout")
  end

  # Sabotage: dropped the `MapSet.member?/2` guard from `own_owner/3` -
  # red, because an owner naming a block the document does not contain is
  # then written into a map whose whole purpose is resolving.
  test "attributing an element to a block that is not here is refused" do
    emission =
      Emission.element("state", [{"id", "s_blk_A"}], [
        Emission.attributed_to(
          Emission.element("transition", [{"target", "s_blk_A"}]),
          "blk_GONE"
        )
      ])

    assert Attribution.stamp(emission, "blk_A", known(["blk_A"])) ==
             {:error, {:unknown_attribution, "blk_GONE"}}
  end

  defmodule Liar do
    @moduledoc "A host leaf that attributes an element to a block it never had."
    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1
    @impl true
    def slots(_config), do: []
    @impl true
    def config_schema(_config), do: []
    @impl true
    def validate_config(_config), do: :ok

    @impl true
    def emit(_block, context) do
      done = Context.done_id(context)

      transition =
        Emission.attributed_to(Emit.transition(target: done), "blk_SOMEONE_ELSE")

      {:ok, Emit.state(context.state_id, done, [transition, Emit.final(done)])}
    end
  end

  # Sabotage: made `Compiler.attribute/3` return `{:ok, emission}` on the
  # error arm - red, because the compile then succeeds and ships a map
  # naming a block nothing can resolve.
  test "a block type that lies about attribution fails the compile as an Emit finding" do
    document =
      Document.new(
        Block.new("core.sequence",
          id: "blk_ROOT",
          slots: %{"body" => [Block.new("cards.liar", id: "blk_LIAR")]}
        ),
        id: "bdoc_cards"
      )

    palette = Palette.new(Map.put(Palette.core_types(), "cards.liar", Liar))

    assert {:error, [finding]} = Compiler.compile(document, palette)

    assert %Finding{
             stage: :emit,
             block_id: "blk_LIAR",
             fault: :package,
             code: :unknown_attribution
           } = finding
  end

  # Sabotage: removed the `List.keymember?/3` guard from
  # `attribute_from_config/3` - red, because a key is then recorded for an
  # attribute the element never wrote, and no span will ever carry it.
  test "a config key for an absent attribute is dropped rather than recorded" do
    plain = Emit.transition(target: "s_blk_A__done")

    assert Emission.attribute_from_config(plain, "cond", "arm_large") == plain

    assert Emission.attribute_from_config(plain, "target", "next").attribute_owners ==
             [{"target", "next"}]
  end
end
