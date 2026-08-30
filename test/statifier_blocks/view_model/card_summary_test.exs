defmodule StatifierBlocks.ViewModel.CardSummaryTest do
  @moduledoc """
  ADR-0002 amendment H5, consumption side: the card's second line when
  nobody has named the block.

  `card_face_test.exs` covers the other arm - a renamed card keeps the type
  label - and that arm is asserted here too, because the value of this seam
  is that the two do not collide. The whole file runs with LiveView absent
  from the dependency tree, the same split the card face is asserted under:
  the line is derived from a declared callback, never from a type name, so
  the markup test beside it only has to check placement.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Document, Palette, ViewModel}

  defmodule NamedAndSummarising do
    @moduledoc """
    A host type that both names its instances and summarises them, which is
    the only shape that tells the two subtitle arms apart.
    """

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
    def palette_entry, do: %{label: "Intake"}

    @impl true
    def summary(_config), do: ["from the type"]
  end

  defp root(type, module, config) do
    document = Document.new(Block.new(type, id: "blk_1", config: config), id: "doc_1")
    palette = Palette.new(%{type => module})

    ViewModel.build(document, palette, []).root
  end

  defp core(type, module, config), do: root(type, module, config)

  defp unresolved(type, config) do
    document = Document.new(Block.new(type, id: "blk_1", config: config), id: "doc_1")

    ViewModel.build(document, Palette.new(%{}), []).root
  end

  describe "the Node carries the summary" do
    # sabotage: dropped `summary:` from the resolved build site - the field
    # keeps its `[]` default, every core card loses its second line, and
    # nothing else in the view model changes, which is exactly the silent
    # regression this asserts against.
    test "a resolved node reads its type's declaration" do
      assert core("core.wait", StatifierBlocks.Core.Wait, %{"duration" => "30s"}).summary ==
               ["timer 30s"]

      assert core("core.parallel", StatifierBlocks.Core.Parallel, %{
               "lanes" => ["fraud_review", "balance_check"]
             }).summary == ["fraud_review", "balance_check"]
    end

    # sabotage: gave `Node`'s `summary` a `nil` default instead of `[]` -
    # `subtitle/1`'s empty-list clause stops matching on an unresolvable card
    # and the join clause is handed a nil.
    test "an unresolvable node has none, because there is no type to ask" do
      node = unresolved("host.missing", %{"duration" => "30s"})

      assert {:unresolvable, _reason} = node.status
      assert node.summary == []
      assert ViewModel.subtitle(node) == nil
    end
  end

  describe "subtitle/1 picks the line by whose words the title is" do
    # sabotage: made the summary clause come first - a renamed card then says
    # its summary and never its type, and the one fact a renamed card cannot
    # get anywhere else on the canvas is gone.
    test "a named block keeps the type label, summary or not" do
      node = root("host.both", NamedAndSummarising, %{"label" => "Collect the details"})

      assert ViewModel.title(node) == "Collect the details"
      assert node.summary == ["from the type"]
      assert ViewModel.subtitle(node) == "Intake"
    end

    # sabotage: kept `subtitle/1`'s old `def subtitle(%Node{}), do: nil`
    # catch-all ahead of the summary clauses - the whole core vocabulary is
    # back to a one-line card and every assert in this describe block reads
    # nil.
    test "an unnamed block draws its summary" do
      node = root("host.both", NamedAndSummarising, %{})

      assert ViewModel.title(node) == "Intake"
      assert ViewModel.subtitle(node) == "from the type"
    end

    # sabotage: replaced the `", "` join with `Enum.at(chips, 0)` - a
    # two-chip line silently loses its second half, which reads as a
    # correctly rendered card rather than as a missing one.
    test "a chip list joins into one line until the card grows chip markup" do
      node =
        core("core.on_event", StatifierBlocks.Core.OnEvent, %{
          "outcome" => "abandon",
          "event" => "fraud.aborted"
        })

      assert node.summary == ["Abandon", "fraud.aborted"]
      assert ViewModel.subtitle(node) == "Abandon, fraud.aborted"
    end

    # The three spike lines this bead exists to reproduce, read off the view
    # model rather than off a screenshot.
    # sabotage: any of the three core `summary/1` bodies - each line here
    # names one type, so a regression in one does not hide behind the others.
    test "the three spike second lines" do
      assert core("core.parallel", StatifierBlocks.Core.Parallel, %{
               "lanes" => ["fraud_review", "balance_check"]
             })
             |> ViewModel.subtitle() == "fraud_review, balance_check"

      assert core("core.wait", StatifierBlocks.Core.Wait, %{"duration" => "30s"})
             |> ViewModel.subtitle() == "timer 30s"

      assert core("core.on_event", StatifierBlocks.Core.OnEvent, %{
               "outcome" => "abandon",
               "event" => "fraud.aborted"
             })
             |> ViewModel.subtitle() == "Abandon, fraud.aborted"
    end

    # sabotage: dropped the empty-list clause - a silent type's card draws an
    # empty second line, which is chrome with nothing in it rather than no
    # chrome.
    test "a silent core type still draws no second line" do
      node = core("core.sequence", StatifierBlocks.Core.Sequence, %{})

      assert node.summary == []
      assert ViewModel.subtitle(node) == nil
    end
  end
end
