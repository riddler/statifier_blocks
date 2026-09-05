defmodule StatifierBlocks.ViewModel.DoneEventChipTest do
  @moduledoc """
  ADR-0005 decision 10w, 10x and 10y, consumption side: a summary chip
  whose text has the shape of a generated done-event name is drawn as the
  named block's own label and the outcome, with the raw name kept for the
  chip's `title` attribute.

  `block_type/summary_test.exs` pins the translation itself against a
  labels map handed straight in. This file pins the half that map comes
  from - the pre-pass over the whole document - because that is the reader
  dependency the record names as new: the chip pass reads ACROSS the
  document rather than down one block, so a card can only be built once
  every other card's label is known.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Document, Palette, ViewModel}

  doctest StatifierBlocks.ViewModel, only: [summary_chip_titles: 1]

  defmodule Named do
    @moduledoc "A host type an author can give a name of their own."

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1

    @impl true
    def slots(_config), do: []

    @impl true
    def config_schema(_config),
      do: [%{key: "label", type: :string, label: "Name", required?: false, default: ""}]

    @impl true
    def validate_config(_config), do: :ok

    @impl true
    def emit(%Block{id: id}, _context), do: {:ok, {:emitted, id}}

    @impl true
    def palette_entry, do: %{label: "Authorize"}
  end

  defmodule Watching do
    @moduledoc """
    A host type whose card describes its config in terms of a completion
    event some other block raises, which is the shape decision 10w exists
    for.
    """

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
    def palette_entry, do: %{label: "Watch"}

    @impl true
    def summary(config), do: Map.get(config, "summary")
  end

  @palette Palette.new(%{
             "core.sequence" => StatifierBlocks.Core.Sequence,
             "host.named" => Named,
             "host.watching" => Watching
           })

  defp document(summary, named_config) do
    Document.new(
      Block.new("core.sequence",
        id: "blk_ROOT",
        slots: %{
          "body" => [
            Block.new("host.named", id: "blk_AUTH", config: named_config),
            Block.new("host.watching", id: "blk_WATCH", config: %{"summary" => summary})
          ]
        }
      ),
      id: "doc_1"
    )
  end

  defp watcher(summary, named_config \\ %{}) do
    vm = ViewModel.build(document(summary, named_config), @palette, [])
    [_named, watching] = hd(vm.root.slots).children

    {vm, watching}
  end

  # The five characters are the whole point: the author declared an outcome
  # called `error` on a block whose card says `Authorize`, and the card was
  # showing the compiler's spelling of that fact.
  #
  # Sabotage: pass `%{}` for the labels in `build_resolved_node/4` - the
  # chip falls back to the raw name and the card is what it was before this
  # section, which is the whole of what the section changed.
  test "a card names the block the canvas names, not the state id" do
    {_vm, watching} = watcher(["done.outcome.s_blk_AUTH.error"])

    assert ViewModel.summary_chips(watching) == ["Authorize · error"]
    assert ViewModel.summary_chip_titles(watching) == ["done.outcome.s_blk_AUTH.error"]
  end

  # 10w reads the label the named block's own card draws, which is the
  # author's title where they gave one - `ViewModel.title/1`'s first arm,
  # read rather than re-derived.
  #
  # Sabotage: read `palette_entry.label` only - a renamed block is cited on
  # another card under the type's label, so the chip names something that
  # appears nowhere on the canvas.
  test "the label is the author's own where they gave one" do
    {_vm, watching} = watcher(["done.state.s_blk_AUTH"], %{"label" => "Charge"})

    assert ViewModel.summary_chips(watching) == ["Charge · done"]
  end

  # 10x, end to end. The generated name is 29 characters against a cap of
  # 24, so before this section the chip drew nothing AND raised a lint
  # naming a string the author cannot shorten.
  #
  # Sabotage: build the lint findings from `summary_refusals/2` without the
  # labels - the chip draws (the node is built with them) while the card
  # simultaneously warns that it does not, which is the two readings of one
  # callback the shared pass exists to prevent.
  test "the cap lint does not fire for a name no author wrote" do
    {vm, watching} = watcher(["done.outcome.s_blk_AUTH.error"])

    assert vm.findings == []
    assert ViewModel.summary_chips(watching) == ["Authorize · error"]
  end

  # 10o keeps its home: an author who names a block a paragraph is told so,
  # in the vocabulary the lint has always used, about a length that is
  # theirs to fix.
  #
  # Sabotage: exempt every translated chip from the cap - the warning
  # disappears and the card silently drops a chip again.
  test "a translated chip over the cap warns about the author's own label" do
    {vm, watching} =
      watcher(["done.outcome.s_blk_AUTH.error"], %{"label" => "Authorize the payment card"})

    assert ViewModel.summary_chips(watching) == []

    assert Enum.map(vm.findings, & &1.message) == [
             "summary chip 1 is 34 characters; the cap is 24, so it is not drawn"
           ]

    assert [%{source: :lint, severity: :warning}] = vm.findings
  end

  # 10y at the document level: a chip may name a block that was deleted,
  # and a label looked up for a block that is gone is not a label.
  #
  # Sabotage: fall back to the block id - the card draws `blk_GONE · error`,
  # which is the derivation the author never sees dressed up as a label.
  test "a chip naming a block that is not here is left exactly as it is" do
    {_vm, watching} = watcher(["done.state.s_blk_GONE"])

    assert ViewModel.summary_chips(watching) == ["done.state.s_blk_GONE"]
    assert ViewModel.summary_chip_titles(watching) == [nil]
  end

  # A block can cite itself, and a card drawn before its own labels existed
  # would be the failure a single recursive pass would have had. The
  # pre-pass is what makes the order irrelevant.
  #
  # Sabotage: accumulate labels during the walk instead of before it - a
  # block citing a LATER sibling draws the raw name, so the card depends on
  # document order.
  test "the labels do not depend on the order the cards are built in" do
    {_vm, watching} = watcher(["done.state.s_blk_WATCH", "done.state.s_blk_ROOT"])

    assert ViewModel.summary_chips(watching) == ["Watch · done", "Sequence · done"]
  end

  # `summary_chip_titles/1` is realigned against the chips rather than
  # trusted, so a `Node` a host built by hand - a fixture, a doctest - gets
  # one `nil` per chip instead of an empty list a zip would swallow.
  #
  # Sabotage: return `node.summary_titles` directly - every chip on every
  # hand-built node disappears from the card, because the renderer zips the
  # two lists.
  test "a node built without titles still answers one title per chip" do
    node = %ViewModel.Node{
      block_id: "blk_1",
      type: "host.watching",
      type_version: 1,
      status: :ok,
      entry: %{label: "Watch"},
      summary: ["capture", "receipt"]
    }

    assert ViewModel.summary_chip_titles(node) == [nil, nil]
  end
end
