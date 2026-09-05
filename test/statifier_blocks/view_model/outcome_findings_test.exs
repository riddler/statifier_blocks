defmodule StatifierBlocks.ViewModel.OutcomeFindingsTest do
  @moduledoc """
  `ViewModel.outcome_findings/3` (sb-r4w7): the disagreement between what a
  `core.subchart` declares in `outcomes` and what the host says the chart it
  names actually finishes with.

  The load-bearing assertion is the quiet one. A host that has said nothing
  about a chart has not disagreed with anything, so the pass must produce
  nothing at all - and the same is true of a host that hands over an entry
  with nothing in it, because an empty list is the absence of knowledge and
  not the claim that a chart has no finals. Everything else here is a
  variation on which direction the disagreement runs in.

  Pure by construction: nothing here names LiveView, and per this package's
  headless rule it therefore carries no wrapper - it is one of the runs that
  proves the finding is derivable with Phoenix off the path.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Document, Finding, Palette, ViewModel}

  defp document(config) do
    Document.new(
      Block.new("core.group",
        id: "blk_root",
        slots: %{"body" => [Block.new("core.subchart", id: "blk_credit", config: config)]}
      ),
      id: "doc_purchase"
    )
  end

  defp findings(config, chart_outcomes) do
    ViewModel.outcome_findings(document(config), Palette.core(), chart_outcomes)
  end

  defp config(outcomes), do: %{"chart" => "bdoc_CREDIT", "outcomes" => outcomes}

  describe "agreement, and everything that counts as one" do
    # Sabotage: `unmatched = declared -- finals` -> `declared` -> 8 failures
    # across this file, this one first (verified). Agreement has to be silent
    # or the finding is noise on every correctly authored subchart.
    test "the declared list and the chart's finals matching says nothing" do
      assert findings(config("approved\ndeclined"), %{
               "bdoc_CREDIT" => ["approved", "declined"]
             }) == []
    end

    test "order is not disagreement" do
      assert findings(config("approved\ndeclined"), %{
               "bdoc_CREDIT" => ["declined", "approved"]
             }) == []
    end

    test "an author who declared nothing agrees with a chart that finishes done" do
      assert findings(config(""), %{"bdoc_CREDIT" => ["done"]}) == []
    end

    # ADR-0068's failure outcome is an event, not a `<final>` the child
    # reports, so `child_outcomes/1` is what is compared and not
    # `outcome_names/1`. Sabotage: comparing `outcome_names/1` instead -> 5
    # failures, this one among them (verified), each on a chart that is in
    # fact declared correctly.
    test "the appended error outcome is not expected of the chart" do
      assert findings(config("approved"), %{"bdoc_CREDIT" => ["approved"]}) == []
    end

    test "an author who declares error themselves is compared on it" do
      assert findings(config("approved\nerror"), %{
               "bdoc_CREDIT" => ["approved", "error"]
             }) == []
    end
  end

  describe "unknown is not disagreement" do
    test "a chart the map does not name produces nothing" do
      assert findings(config("approved"), %{"bdoc_OTHER" => ["denied"]}) == []
    end

    # Sabotage: accepting `[]` as knowledge (`finals when is_list(finals)` in
    # place of the `[_first | _rest]` guard) -> 1 failure, here (verified). An
    # empty entry is a host that has not answered, and a finding here would
    # tell every author their outcomes are wrong the moment the host wires the
    # assign up with a partially populated map.
    test "an entry holding an empty list produces nothing" do
      assert findings(config("approved"), %{"bdoc_CREDIT" => []}) == []
    end

    test "the default empty assign produces nothing" do
      assert findings(config("approved"), %{}) == []
    end

    test "a value that is not a list produces nothing" do
      assert findings(config("approved"), %{"bdoc_CREDIT" => "approved"}) == []
    end

    test "a chart_outcomes that is not a map produces nothing" do
      assert findings(config("approved"), nil) == []
    end
  end

  describe "the disagreement" do
    test "a declared outcome absent from the finals is reported" do
      assert [%Finding{} = finding] =
               findings(config("approved\ndenied"), %{"bdoc_CREDIT" => ["approved"]})

      assert finding.anchor == {:config, "blk_credit", "outcomes"}
      assert finding.source == :lint
      assert finding.severity == :warning
      assert finding.message =~ "bdoc_CREDIT does not finish with \"denied\""
    end

    # The other direction is a disagreement too: the child raises a final the
    # parent never routes, so it falls to the unconditioned default arm rather
    # than to the path the author would have written for it.
    test "a final the author did not declare is reported" do
      assert [%Finding{message: message}] =
               findings(config("approved"), %{"bdoc_CREDIT" => ["approved", "denied"]})

      assert message =~ "bdoc_CREDIT also finishes with \"denied\""
      refute message =~ "does not finish with"
    end

    # Sabotage: emitting one finding per name rather than one per block -> 2
    # failures, this one among them (verified). One field, one observation;
    # four findings under one input is the same sentence read four times.
    test "both directions are one finding on one field" do
      assert [%Finding{message: message}] =
               findings(config("approved\ndenied"), %{
                 "bdoc_CREDIT" => ["approved", "abandoned"]
               })

      assert message =~ "does not finish with \"denied\""
      assert message =~ "also finishes with \"abandoned\""
    end

    test "an author who declared nothing is compared on the default done" do
      assert [%Finding{message: message}] =
               findings(config(""), %{"bdoc_CREDIT" => ["approved", "denied"]})

      assert message =~ "does not finish with \"done\""
    end

    # The whole point of the `:warning`: the document still compiles, and a
    # consumer gating on findings gates on `:error`.
    test "it changes no verdict" do
      document = document(config("approved\ndenied"))

      disagreements =
        ViewModel.outcome_findings(document, Palette.core(), %{
          "bdoc_CREDIT" => ["approved"]
        })

      %ViewModel{findings: findings} =
        ViewModel.build(document, Palette.core(), disagreements)

      refute Enum.any?(findings, &(&1.severity == :error))
    end
  end

  describe "what it is not asked about" do
    test "a block of another type is never compared" do
      document =
        Document.new(
          Block.new("core.group",
            id: "blk_root",
            slots: %{
              "body" => [
                Block.new("core.invoke",
                  id: "blk_call",
                  config: %{"invoke_type" => "bdoc_CREDIT"}
                )
              ]
            }
          ),
          id: "doc_purchase"
        )

      assert ViewModel.outcome_findings(document, Palette.core(), %{
               "bdoc_CREDIT" => ["approved"]
             }) == []
    end

    test "a subchart with no chart named yet is never compared" do
      assert findings(%{"outcomes" => "approved"}, %{"bdoc_CREDIT" => ["approved", "x"]}) == []
    end

    test "an unresolvable block is skipped rather than raising" do
      document =
        Document.new(
          Block.new("core.group",
            id: "blk_root",
            slots: %{"body" => [Block.new("host.unknown", id: "blk_x")]}
          ),
          id: "doc_purchase"
        )

      assert ViewModel.outcome_findings(document, Palette.core(), %{
               "bdoc_CREDIT" => ["approved"]
             }) == []
    end
  end
end
