defmodule StatifierBlocks.ViewModel.CardSummaryTest do
  @moduledoc """
  ADR-0002 amendment H5, consumption side: the card's second line when
  nobody has named the block, and ADR-0005's 2026-08-30 amendment (decision
  10, the summary chip row) for the shape it arrives in - a list of chips
  read through `summary_chips/1`, never a joined string.

  `card_face_test.exs` covers the other arm - a renamed card keeps the type
  label - and that arm is asserted here too, because the value of this seam
  is that the two do not collide. The whole file runs with LiveView absent
  from the dependency tree, the same split the card face is asserted under:
  the line is derived from a declared callback, never from a type name, so
  the markup test beside it only has to check placement.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Document, Palette, ViewModel}

  doctest StatifierBlocks.ViewModel, only: [summary_chips: 1]

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

  defmodule Overlong do
    @moduledoc """
    A host type whose summary is whatever its config says, so one module
    covers every chip the presentation cap refuses.
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
    def palette_entry, do: %{label: "Overlong"}

    @impl true
    def summary(config), do: Map.get(config, "summary")
  end

  defp view_model(type, module, config) do
    document = Document.new(Block.new(type, id: "blk_1", config: config), id: "doc_1")
    palette = Palette.new(%{type => module})

    ViewModel.build(document, palette, [])
  end

  defp root(type, module, config), do: view_model(type, module, config).root

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

    # sabotage: gave `Node`'s `summary` a `nil` default instead of `[]` - an
    # unresolvable card's chip row is handed a nil and the card that has the
    # least to say is the one that stops rendering.
    test "an unresolvable node has none, because there is no type to ask" do
      node = unresolved("host.missing", %{"duration" => "30s"})

      assert {:unresolvable, _reason} = node.status
      assert node.summary == []
      assert ViewModel.subtitle(node) == nil
      assert ViewModel.summary_chips(node) == []
    end
  end

  describe "the second line is picked by whose words the title is" do
    # A card has one second line, so the two arms are exclusive: the named
    # card says its type, and the chips it also declared draw nowhere.
    # Sabotage: dropped `summary_chips/1`'s titled clause - a renamed card
    # draws the type label AND a chip row under it, which is the second line
    # twice and the collision this seam exists to prevent.
    test "a named block keeps the type label, summary or not" do
      node = root("host.both", NamedAndSummarising, %{"label" => "Collect the details"})

      assert ViewModel.title(node) == "Collect the details"
      assert node.summary == ["from the type"]
      assert ViewModel.subtitle(node) == "Intake"
      assert ViewModel.summary_chips(node) == []
    end

    # Sabotage: had `summary_chips/1` read `[]` for every node - the whole
    # core vocabulary is back to a one-line card, and it goes red here rather
    # than only in the markup test beside it.
    test "an unnamed block draws its summary" do
      node = root("host.both", NamedAndSummarising, %{})

      assert ViewModel.title(node) == "Intake"
      assert ViewModel.subtitle(node) == nil
      assert ViewModel.summary_chips(node) == ["from the type"]
    end

    # The chips stay chips: an outcome and an event name are two facts, and
    # the join that used to punctuate them as one phrase is what ADR-0005's
    # amendment replaced.
    # Sabotage: restored `Enum.join(chips, ", ")` in `summary_chips/1` - the
    # row draws one chip reading "Abandon, fraud.aborted", which is the
    # rendering this bead exists to remove and which no markup test would
    # notice.
    test "a chip list stays a list, one element per chip" do
      node =
        core("core.on_event", StatifierBlocks.Core.OnEvent, %{
          "outcome" => "abandon",
          "event" => "fraud.aborted"
        })

      assert node.summary == ["Abandon", "fraud.aborted"]
      assert ViewModel.summary_chips(node) == ["Abandon", "fraud.aborted"]
    end

    # ADR-0002 H6 declares three of its five summaries as a STRING, and
    # `BlockType.summary/2` wraps one into a one-element list - so the
    # one-chip case is a real card and not a degenerate shape nothing
    # produces. `core.branch`'s line is the sharpest of the three: its own
    # words contain a `+`, and it is still one chip.
    # Sabotage: `List.wrap/1` dropped from `BlockType.summary/2` - a string
    # summary becomes a chip of a string, the row draws nothing readable,
    # and three of the five core summaries go with it.
    test "a string summary is the one-chip case" do
      assert core("core.wait", StatifierBlocks.Core.Wait, %{"duration" => "30s"})
             |> ViewModel.summary_chips() == ["timer 30s"]

      assert core("core.send", StatifierBlocks.Core.Send, %{"event" => "order.paid"})
             |> ViewModel.summary_chips() == ["order.paid"]
    end

    # The three spike lines this bead exists to reproduce, read off the view
    # model rather than off a screenshot.
    # sabotage: any of the three core `summary/1` bodies - each line here
    # names one type, so a regression in one does not hide behind the others.
    test "the three spike second lines" do
      assert core("core.parallel", StatifierBlocks.Core.Parallel, %{
               "lanes" => ["fraud_review", "balance_check"]
             })
             |> ViewModel.summary_chips() == ["fraud_review", "balance_check"]

      assert core("core.wait", StatifierBlocks.Core.Wait, %{"duration" => "30s"})
             |> ViewModel.summary_chips() == ["timer 30s"]

      assert core("core.on_event", StatifierBlocks.Core.OnEvent, %{
               "outcome" => "abandon",
               "event" => "fraud.aborted"
             })
             |> ViewModel.summary_chips() == ["Abandon", "fraud.aborted"]
    end

    # Sabotage: had `summary_chips/1` answer `["-"]` for an empty summary -
    # a silent type's card draws chrome with nothing in it rather than no
    # chrome, which is the empty-row case ADR-0005 amendment 10q rules out.
    test "a silent core type still draws no second line" do
      node = core("core.sequence", StatifierBlocks.Core.Sequence, %{})

      assert node.summary == []
      assert ViewModel.subtitle(node) == nil
      assert ViewModel.summary_chips(node) == []
    end
  end

  describe "the cap signals (ADR-0005 decision 10 Note, 2026-08-30)" do
    # Refusing a chip removes the evidence that anything was declared, so
    # this is the finding that says the difference between "declared
    # nothing" and "declared something the cap would not draw".
    # Sabotage: dropped `summary_findings/3` from `derived_findings/2` - the
    # card is byte-for-byte identical either way, so nothing else in the
    # suite notices and the author is back to a blank second line.
    test "an over-cap chip raises one lint warning against its block" do
      vm = view_model("host.overlong", Overlong, %{"summary" => ["waiting for the operators"]})

      assert [finding] = vm.findings
      assert finding.source == :lint
      assert finding.severity == :warning
      assert finding.anchor == {:block, "blk_1"}

      assert finding.message ==
               "summary chip 1 is 25 characters; the cap is 24, so it is not drawn"
    end

    # Sabotage: anchored the finding at `{:config, id, "summary"}` - there is
    # no summary key in any config schema, so the finding routes to a field
    # the form never draws and the block panel never shows it.
    test "the warning routes onto the block, beside the card it explains" do
      vm = view_model("host.overlong", Overlong, %{"summary" => ["waiting for the operators"]})

      assert vm.orphan_findings == []
      assert [%{source: :lint}] = vm.root.findings
      assert vm.root.findings_count == 1
    end

    # Sabotage: emitted one finding per block rather than one per refusal -
    # a two-lane parallel with both lane names too long reports one problem
    # and the author fixes one lane.
    test "one warning per refused chip, and none for the chips that drew" do
      vm =
        view_model("host.overlong", Overlong, %{
          "summary" => ["capture", "waiting for the operators", 7]
        })

      assert vm.root.summary == ["capture"]

      assert Enum.map(vm.findings, & &1.message) == [
               "summary chip 2 is 25 characters; the cap is 24, so it is not drawn",
               "summary chip 3 is not a string, so it is not drawn"
             ]
    end

    # The severity is what keeps this from being a verdict: the document
    # compiles with an undrawn chip exactly as it compiles without one.
    # Sabotage: left `severity:` off the `Finding.new/4` call - it defaults
    # to `:error`, and every document with a long lane name stops reading as
    # compilable to any consumer that gates on findings.
    test "a well-formed summary raises nothing at all" do
      vm = view_model("host.overlong", Overlong, %{"summary" => ["capture", "receipt"]})

      assert vm.findings == []
      assert vm.root.summary == ["capture", "receipt"]
    end

    # Sabotage: called `module.summary/1` directly in `summary_findings/3`
    # instead of going through `BlockType.summary_refusals/2` - an
    # unresolvable block has no module to ask and the whole build raises.
    test "an unresolvable block raises no summary warning" do
      vm =
        ViewModel.build(
          Document.new(Block.new("host.missing", id: "blk_1", config: %{}), id: "doc_1"),
          Palette.new(%{}),
          []
        )

      assert [%{source: :resolution}] = vm.findings
    end
  end
end
