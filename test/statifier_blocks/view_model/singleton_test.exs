defmodule StatifierBlocks.ViewModel.SingletonTest do
  @moduledoc """
  ADR-0005's 2026-09-05 amendment, clauses 10z and 11o: a palette entry may
  declare how many of its type a document holds, and `ViewModel.build/3`
  answers a document that does not with one `:config` finding anchored at
  the root.

  Every case here is a pure view-model assertion - no LiveView module is
  named, so the file carries no `Code.ensure_loaded?/1` wrapper and compiles
  in the headless tree unchanged.

  Each test names the palette it builds against rather than sharing one,
  because the declarations live in the palette: a suite-wide palette holding
  both a `:head` type and an `:anywhere` type would make every document in
  it violate something, and every assertion would be about the other type's
  finding.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Document, Palette, ViewModel}

  doctest StatifierBlocks.BlockType, only: [singleton: 1]

  defmodule Root do
    @moduledoc """
    A two-slot root, so "the root's first slot" is a question this suite can
    ask rather than one the shape answers by accident. `"steps"` is declared
    first and `"aside"` second; sorted, they come out the other way round,
    which is what catches a reader of `Map.keys/1`.
    """

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1

    @impl true
    def slots(_config), do: [{"steps", :many, "Steps"}, {"aside", :many, "Aside"}]

    @impl true
    def config_schema(_config), do: []

    @impl true
    def validate_config(_config), do: :ok

    @impl true
    def emit(%Block{id: id}, _context), do: {:ok, {:emitted, id}}

    @impl true
    def palette_entry, do: %{label: "Flow"}
  end

  defmodule SlotlessRoot do
    @moduledoc "A root that declares no slots, for the fallback arm."

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
    def emit(%Block{id: id}, _context), do: {:ok, {:emitted, id}}

    @impl true
    def palette_entry, do: %{label: "Bare"}
  end

  defmodule Start do
    @moduledoc "A type a host wants exactly one of, at the top."

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1

    @impl true
    def slots(_config), do: [{"kids", :many, "Kids"}]

    @impl true
    def config_schema(_config), do: []

    @impl true
    def validate_config(_config), do: :ok

    @impl true
    def emit(%Block{id: id}, _context), do: {:ok, {:emitted, id}}

    @impl true
    def palette_entry, do: %{label: "Start here", singleton: :head}
  end

  defmodule Settle do
    @moduledoc "A type a host wants exactly one of, anywhere."

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
    def emit(%Block{id: id}, _context), do: {:ok, {:emitted, id}}

    @impl true
    def palette_entry, do: %{label: "Settlement", singleton: :anywhere}
  end

  defmodule Step do
    @moduledoc "An ordinary type, declaring no cardinality at all."

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1

    @impl true
    def slots(_config), do: [{"kids", :many, "Kids"}]

    @impl true
    def config_schema(_config), do: []

    @impl true
    def validate_config(_config), do: :ok

    @impl true
    def emit(%Block{id: id}, _context), do: {:ok, {:emitted, id}}

    @impl true
    def palette_entry, do: %{label: "Step"}
  end

  defmodule Malformed do
    @moduledoc "A type whose `singleton` is not one this package can read."

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
    def emit(%Block{id: id}, _context), do: {:ok, {:emitted, id}}

    @impl true
    def palette_entry, do: %{label: "Confused", singleton: "head"}
  end

  @roots %{"test.root" => Root, "test.slotless_root" => SlotlessRoot, "test.step" => Step}

  @head_palette Palette.new(Map.put(@roots, "test.start", Start))
  @anywhere_palette Palette.new(Map.put(@roots, "test.settle", Settle))
  @plain_palette Palette.new(@roots)

  defp block(type, id), do: Block.new(type, id: id)

  defp document(slots, root_type \\ "test.root") do
    root_type
    |> Block.new(id: "blk_root", slots: slots)
    |> Document.new(id: "bdoc_1")
  end

  # The clause-11o findings and nothing else: `:config` at the root anchor.
  # A `validate_config/1` finding is anchored `{:config, id, key}` and a
  # resolution failure carries a different source, so neither reaches here.
  defp document_findings(document, palette) do
    document
    |> ViewModel.build(palette, [])
    |> Map.fetch!(:findings)
    |> Enum.filter(&(&1.source == :config and &1.anchor == {:block, "blk_root"}))
  end

  describe "a type declaring singleton: :head" do
    # sabotage: in `head_of_root/2`, read `first_carried_slot/1` instead of
    # the first declared slot -> red, the head is measured against "aside".
    test "one at the head of the root's first declared slot draws nothing" do
      document =
        document(%{
          "steps" => [block("test.start", "blk_a"), block("test.step", "blk_b")],
          "aside" => [block("test.step", "blk_c")]
        })

      assert document_findings(document, @head_palette) == []
    end

    # sabotage: in `singleton_finding/6`, return `[]` from the empty arm ->
    # red, a document holding none of a declared type says nothing.
    test "none at all draws one finding naming the label" do
      document = document(%{"steps" => [block("test.step", "blk_b")]})

      assert [finding] = document_findings(document, @head_palette)
      assert finding.source == :config
      assert finding.severity == :error
      assert finding.anchor == {:block, "blk_root"}
      assert finding.message == "this document needs a Start here, and holds none"
    end

    # sabotage: map the surplus arm over `many` instead of returning one
    # finding -> red, three blocks draw three copies of one sentence.
    test "three draw exactly one finding naming the count, not one per block" do
      document =
        document(%{
          "steps" => [block("test.start", "blk_a"), block("test.start", "blk_b")],
          "aside" => [block("test.start", "blk_c")]
        })

      assert [finding] = document_findings(document, @head_palette)

      assert finding.message ==
               "this document holds 3 Start here blocks, and may hold exactly one"
    end

    # sabotage: drop `singleton_findings/2` from `derived_findings/3` ->
    # red, the producer is gone and no arrangement is ever wrong.
    test "one in the wrong position names the slot and the position" do
      document =
        document(%{"steps" => [block("test.step", "blk_b"), block("test.start", "blk_a")]})

      assert [finding] = document_findings(document, @head_palette)

      assert finding.message ==
               ~s(a Start here belongs first in the root's "steps" slot, ) <>
                 ~s(and this document's is at position 2 of the root's "steps" slot)
    end

    # sabotage: in `head_of_root/2`, read `first_carried_slot/1` instead of
    # the first declared slot -> red, "aside" sorts first and passes.
    test "the first DECLARED slot is the rule, not the alphabetically first one" do
      document =
        document(%{
          "aside" => [block("test.start", "blk_a")],
          "steps" => [block("test.step", "blk_b")]
        })

      assert [finding] = document_findings(document, @head_palette)

      assert finding.message ==
               ~s(a Start here belongs first in the root's "steps" slot, ) <>
                 ~s(and this document's is at position 1 of the root's "aside" slot)
    end

    # sabotage: in `where_is/2`, drop the `parent_id == root.id` test and
    # always say "the root's" -> red, a nested block reads as a root child.
    test "one deeper in the tree is named as another block's slot" do
      nested =
        Block.new("test.step", id: "blk_b", slots: %{"kids" => [block("test.start", "blk_a")]})

      document = document(%{"steps" => [nested]})

      assert [finding] = document_findings(document, @head_palette)
      assert finding.message =~ ~s(at position 1 of another block's "kids" slot)
    end

    # sabotage: drop `|| first_carried_slot(root)` from `head_of_root/2` ->
    # red, a slotless root names no slot and the message loses it.
    test "a root declaring no slots falls back to the slot name it carries" do
      document =
        document(
          %{"leftovers" => [block("test.step", "blk_b"), block("test.start", "blk_a")]},
          "test.slotless_root"
        )

      assert [finding] = document_findings(document, @head_palette)
      assert finding.message =~ ~s(belongs first in the root's "leftovers" slot)
    end
  end

  describe "a type declaring singleton: :anywhere" do
    # sabotage: have the `:anywhere` clause of `misplaced_finding/6` fall
    # through to the `:head` one -> red, position starts counting.
    test "one anywhere draws nothing, whatever its position" do
      document =
        document(%{"steps" => [block("test.step", "blk_b"), block("test.settle", "blk_s")]})

      assert document_findings(document, @anywhere_palette) == []
    end

    # sabotage: in `singleton_finding/6`, return `[]` from the empty arm ->
    # red, `:anywhere` loses the count half of its claim.
    test "none draws the same shape of finding :head does" do
      document = document(%{"steps" => [block("test.step", "blk_b")]})

      assert [finding] = document_findings(document, @anywhere_palette)
      assert finding.message == "this document needs a Settlement, and holds none"
    end

    # sabotage: map the surplus arm over `many` instead of returning one
    # finding -> red, two blocks draw two copies of one sentence.
    test "two draw one finding naming the count" do
      document =
        document(%{
          "steps" => [block("test.settle", "blk_s"), block("test.settle", "blk_t")]
        })

      assert [finding] = document_findings(document, @anywhere_palette)

      assert finding.message ==
               "this document holds 2 Settlement blocks, and may hold exactly one"
    end
  end

  describe "an entry declaring nothing" do
    # sabotage: read a `nil` declaration as `:anywhere` in
    # `singleton_findings/2` -> red, every type in the palette is counted.
    test "an unconstrained palette derives no document finding at any count" do
      for slots <- [
            %{},
            %{"steps" => [block("test.step", "blk_b")]},
            %{"steps" => [block("test.step", "blk_b"), block("test.step", "blk_c")]}
          ] do
        assert document_findings(document(slots), @plain_palette) == []
      end
    end

    # sabotage: widen `BlockType.singleton/1`'s guard to accept any
    # non-nil value -> red, the string "head" starts constraining.
    test "a singleton this package cannot read is absence, not an error" do
      palette = Palette.new(Map.put(@roots, "test.confused", Malformed))

      assert document_findings(document(%{}), palette) == []
    end
  end

  # sabotage: sort `singleton_findings/2` by `:desc` -> red, the two
  # findings arrive in the other order.
  test "findings are ordered by type name, so two builds of one document agree" do
    palette =
      Palette.new(Map.merge(@roots, %{"test.settle" => Settle, "test.start" => Start}))

    assert [settle, start] = document_findings(document(%{}), palette)
    assert settle.message =~ "Settlement"
    assert start.message =~ "Start here"
  end

  # sabotage: anchor the finding at the offending block instead of the
  # root -> red, clause 11o's routing row stops being the one used.
  test "the finding routes onto the root node's chrome, not into orphans" do
    document = document(%{"steps" => [block("test.step", "blk_b")]})
    view_model = ViewModel.build(document, @head_palette, [])

    assert view_model.orphan_findings == []
    assert Enum.any?(view_model.root.findings, &(&1.message =~ "needs a Start here"))
  end
end
