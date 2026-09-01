defmodule StatifierBlocks.Core.DraftsTest do
  @moduledoc """
  What `core.drafts` *means*, as `core_types_test.exs` owns meaning and
  `conformance_test.exs` owns shape (ADR-0002's amendment of 2026-08-31,
  section G9; ADR-0003's, section A1).

  The compiler's side of the shelf - the elision, the byte identity, the
  two Structure errors and the `:draft_blocks_present` warning - is not
  here. It lives in `test/statifier_blocks/shelf_test.exs` and
  `test/statifier_blocks/compiler/drafts_test.exs`, because none of it is a
  property of this module.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Assignability, Block, Emission}
  alias StatifierBlocks.Compiler.Context
  alias StatifierBlocks.Core.Drafts

  describe "the declarations that make a shelf a shelf" do
    # Sabotage: renamed the slot to `"drafts"` - red here, and red in the
    # compiler once the elision looks for `"body"` on the shelf.
    test "one slot, body, holding any number" do
      assert Drafts.slots(%{}) == [{"body", :any, "Drafts"}]
      assert Drafts.config_schema(%{}) == []
      assert Drafts.validate_config(%{"anything" => 1}) == :ok
      assert Drafts.current_version() == 1
    end

    # Sabotage: added `:step` to `kinds` - red here, and red across
    # placement_test, which is G9b's argument that a shelf that were also a
    # step would be admitted by every `[:step]` slot in every host palette.
    test "kinds is exactly [:draft_shelf], and body accepts anything" do
      io = Assignability.io(Drafts, %{})

      assert io == %{kinds: [:draft_shelf], slot_accepts: %{"body" => :any}}
      refute Map.has_key?(io, :consumes)
      refute Map.has_key?(io, :produces)
    end

    # Sabotage: declared `slot_style: %{"body" => :primary}` - red here,
    # and the tray would render as an ordinary body flow with connectors,
    # which is the one bad rendering 10u exists to prevent.
    test "the body slot declares the tray style" do
      entry = Drafts.palette_entry()

      assert entry.slot_style == %{"body" => :tray}
      assert entry.label == "Drafts"
    end

    # Sabotage: gave `outcomes/1` an explicit `[{"done", "Done"}]` - not
    # red, which is the point: nothing asks, so the absence is what is
    # asserted rather than the value.
    test "no outcomes are declared, because nothing sequences a shelf" do
      refute function_exported?(Drafts, :outcomes, 1)
    end
  end

  describe "the emission the compiler never asks for" do
    # Sabotage: made `emit/2` return `{:error, :never_called}` - red here.
    # The refusal reads well and buys nothing: D1 is held up by the
    # compiler's elision, and a refusal here would only make this one type
    # an exemption from the shape every other core type answers in.
    test "answers with the smallest inert state" do
      block = Block.new("core.drafts", id: "blk_SHELF")
      context = Context.new("blk_SHELF", "bdoc_T")

      assert {:ok, %Emission{name: "state"} = emission} = Drafts.emit(block, context)
      assert Enum.any?(emission.children, &match?(%Emission{name: "final"}, &1))
    end
  end
end
