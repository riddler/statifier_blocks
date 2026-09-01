defmodule StatifierBlocks.ShelfTest do
  @moduledoc """
  The two placement facts `io/1` cannot carry (ADR-0002's amendment of
  2026-08-31, section G12; ADR-0004's, section D3; campaign-024 ruling
  R-b), checked at the module that owns them and again through
  `Compiler.compile/3`, which is where they reach an author.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Assignability, Block, Compiler, Document, Palette, Shelf}

  defp shelf(id, children \\ []),
    do: Block.new("core.drafts", id: id, slots: %{"body" => children})

  defp step(id), do: Block.new("core.wait", id: id, config: %{"duration" => "PT1H"})

  defp document(body) do
    Document.new(Block.new("core.sequence", id: "blk_ROOT", slots: %{"body" => body}),
      id: "bdoc_SHELF"
    )
  end

  describe "identity" do
    # Sabotage: made `shelf_type?/1` match "core.draft" - red here, and red
    # on every placement and elision test downstream of it.
    test "the two type names, by the string a document stores" do
      assert Shelf.drafts_type() == "core.drafts"
      assert Shelf.placeholder_type() == "core.placeholder"

      assert Shelf.shelf?(shelf("blk_S"))
      refute Shelf.shelf?(step("blk_W"))
      assert Shelf.marker?(Block.new("core.placeholder", id: "blk_P"))
      refute Shelf.marker?(step("blk_W"))
      refute Shelf.shelf_type?("core.sequence")
      refute Shelf.marker_type?("core.sequence")
    end

    # Sabotage: made `shelves/1` read `document.root.slots` directly rather
    # than walking - red here, because a shelf nested in a group is exactly
    # the case the misplacement rule exists to catch and would go unseen.
    test "shelves/1 finds one at any depth, in document order" do
      nested =
        document([
          shelf("blk_FIRST"),
          Block.new("core.group", id: "blk_G", slots: %{"body" => [shelf("blk_NESTED")]})
        ])

      assert Enum.map(Shelf.shelves(nested), & &1.id) == ["blk_FIRST", "blk_NESTED"]
      assert Shelf.shelves(document([step("blk_W")])) == []
    end
  end

  describe "validate/1" do
    # Sabotage: dropped the `@root_slot` match from `at_root_body?/2`, so
    # any direct child of the root counted - red here, since the whole
    # point of G12a is a position, not a parent type.
    test "a shelf directly in the root's body is well placed" do
      assert Shelf.validate(document([step("blk_W"), shelf("blk_S")])) == :ok
    end

    # Sabotage: made `at_root_body?/2` always true - red on both arms.
    test "a shelf anywhere else is misplaced" do
      nested =
        document([Block.new("core.group", id: "blk_G", slots: %{"body" => [shelf("blk_S")]})])

      assert {:error, [{:drafts_block_misplaced, "blk_S"}]} = Shelf.validate(nested)

      root_shelf = Document.new(shelf("blk_ROOT"), id: "bdoc_SHELF")
      assert {:error, [{:drafts_block_misplaced, "blk_ROOT"}]} = Shelf.validate(root_shelf)

      # A second slot on the root itself. The rule is a position - the root's
      # `body` - and not "a child of the root", which is the half a parent-id
      # test alone would get wrong.
      assert {:error, [{:drafts_block_misplaced, "blk_S"}]} =
               Shelf.validate(group_root_with_shelf_in_interrupts())
    end

    defp group_root_with_shelf_in_interrupts do
      Document.new(
        Block.new("core.group",
          id: "blk_ROOT",
          slots: %{"body" => [step("blk_W")], "interrupts" => [shelf("blk_S")]}
        ),
        id: "bdoc_SHELF"
      )
    end

    # Sabotage: named the first shelf instead of the second (`index == 0`
    # flipped) - red here on the id, which is the whole of D3's argument
    # that a finding on the block the author means to keep asks them to fix
    # the wrong one.
    test "the second shelf is named, and the first is not" do
      two = document([shelf("blk_FIRST"), shelf("blk_SECOND")])

      assert {:error, [{:duplicate_drafts_block, "blk_SECOND"}]} = Shelf.validate(two)
    end

    # Sabotage: made `block_findings/2` return the first non-empty list
    # rather than concatenating - red here, and one of two independent
    # facts about the same block would go unreported.
    test "a second shelf that is also nested carries both codes" do
      both =
        document([
          shelf("blk_FIRST"),
          Block.new("core.group", id: "blk_G", slots: %{"body" => [shelf("blk_SECOND")]})
        ])

      assert {:error, findings} = Shelf.validate(both)

      assert findings == [
               {:drafts_block_misplaced, "blk_SECOND"},
               {:duplicate_drafts_block, "blk_SECOND"}
             ]
    end
  end

  describe "the admission half of the depth rule" do
    # Sabotage: dropped the `shelf_at_root_body?/4` arm from
    # `kind_admission_finding/5` - red here, and an author could never place
    # a shelf at all: the root declares `slot_accepts` `[:step]` like every
    # other container, so decision 3's intersection refuses a
    # `:draft_shelf` at the one position G12a admits it.
    test "the root's body admits a shelf that every declaration refuses" do
      root_body = document([step("blk_W")])
      candidate = shelf("blk_S")

      assert Assignability.check(
               Palette.core(),
               root_body,
               {"blk_ROOT", "body", 1},
               candidate,
               %{}
             ) ==
               :ok

      assert {"blk_ROOT", "body", 1} in Assignability.valid_targets(
               Palette.core(),
               root_body,
               candidate,
               %{}
             )
    end

    # Sabotage: made `Shelf.root_body?/3` ignore its `slot` argument - red
    # here, since a group's body is not the root's body and an `interrupts`
    # slot is not either.
    test "no other position admits one" do
      nested =
        document([Block.new("core.group", id: "blk_G", slots: %{"body" => [step("blk_W")]})])

      assert {:error, [{:kind_not_admitted, "blk_S", "blk_G", "body", [:draft_shelf], [:step]}]} =
               Assignability.check(
                 Palette.core(),
                 nested,
                 {"blk_G", "body", 0},
                 shelf("blk_S"),
                 %{}
               )

      # The root's other slot, for the same reason `validate/1` checks it:
      # the admission is a position, not a parent.
      root_interrupts =
        Document.new(
          Block.new("core.group", id: "blk_ROOT", slots: %{"body" => [], "interrupts" => []}),
          id: "bdoc_SHELF"
        )

      assert {:error, [{:kind_not_admitted, "blk_S", "blk_ROOT", "interrupts", _kinds, _accepts}]} =
               Assignability.check(
                 Palette.core(),
                 root_interrupts,
                 {"blk_ROOT", "interrupts", 0},
                 shelf("blk_S"),
                 %{}
               )
    end
  end

  describe "through the compiler's Structure stage" do
    # A misplaced shelf inside a core container is named twice, by two
    # different rules: the ordinary kind intersection refuses it (G9b), and
    # the depth rule names it (D3). They are siblings rather than one being
    # a consequence of the other - the kind refusal is silent for an untyped
    # host container, which is the case G12 says the depth rule alone can
    # decide - so decision 10's "every finding within a stage is reported"
    # reports both.
    #
    # Sabotage: dropped `shelf_findings` from the concatenation in
    # `structure_stage/3` - red here on the missing two codes, which is the
    # wiring rather than the rule.
    test "both codes arrive as author-faulted structure errors on the block" do
      both =
        document([
          shelf("blk_FIRST"),
          Block.new("core.group", id: "blk_G", slots: %{"body" => [shelf("blk_SECOND")]})
        ])

      assert {:error, findings} = Compiler.compile(both, Palette.core())

      for finding <- findings do
        assert finding.stage == :structure
        assert finding.severity == :error
        assert finding.fault == :author
        assert finding.block_id == "blk_SECOND"
        assert finding.config_key == nil
        assert finding.message != ""
      end

      assert Enum.sort(Enum.map(findings, & &1.code)) == [
               :drafts_block_misplaced,
               :duplicate_drafts_block,
               :kind_not_admitted
             ]
    end

    # Sabotage: made `Shelf.validate/1` return `:ok` unconditionally - red
    # here, because a well-placed shelf and a misplaced one would compile
    # alike.
    test "a well-placed shelf refuses nothing" do
      assert {:ok, _compiled} =
               Compiler.compile(document([step("blk_W"), shelf("blk_S")]), Palette.core())
    end
  end
end
