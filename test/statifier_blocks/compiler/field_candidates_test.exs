defmodule StatifierBlocks.Compiler.FieldCandidatesTest do
  @moduledoc """
  The `:field_candidates` lint: the compile-side half of the candidate feed
  ADR-0011 names beside `{:path, opts}`'s two keys.

  It is `:known_invoke_types`' shape and `:known_invoke_types`' reasoning.
  Which values exist is a property of the deployment a document runs in, so
  a list handed to a compile is one deployment's belief and never a rule
  about the document: the strongest claim the evidence supports is a
  warning, and `validate_config/1` remains the only authority on a value.

  A pure test. Nothing here names LiveView - the lint runs in the compiler,
  which is where a host publishing without an editor meets it.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Compiler, Document, Palette}
  alias StatifierBlocks.Compiler.Finding

  @key {"core.subchart", "chart"}

  defp document(chart \\ "bdoc_CHILD") do
    Document.new(
      Block.new("core.sequence",
        id: "blk_ROOT",
        slots: %{
          "body" => [
            Block.new("core.subchart",
              id: "blk_ELIG",
              config: %{"chart" => chart, "outcomes" => "approved"},
              slots: %{"on_approved" => [], "on_error" => []}
            )
          ]
        }
      ),
      id: "bdoc_signup"
    )
  end

  defp compile!(opts) do
    {:ok, compiled} = Compiler.compile(document(), Palette.core(), opts)
    compiled
  end

  describe "a closed list" do
    # sabotage: made `candidate_finding/3` accept any value by dropping the
    # `Enum.any?/2` guard -> no warning is produced and this goes red
    # (verified).
    test "a value it does not offer is a warning naming the block and the field" do
      compiled = compile!(field_candidates: %{@key => [{"bdoc_OTHER", "Some other chart"}]})

      assert [%Finding{} = warning] = compiled.warnings
      assert warning.severity == :warning
      assert warning.block_id == "blk_ELIG"
      assert warning.config_key == "chart"
      assert warning.fault == :author
      assert warning.message =~ "bdoc_CHILD"
    end

    # sabotage: as above - the offered value warns too and this goes red
    # (verified).
    test "a value it offers says nothing" do
      compiled =
        compile!(
          field_candidates: %{@key => [{"bdoc_CHILD", "The child"}, {"bdoc_OTHER", "Other"}]}
        )

      assert compiled.warnings == []
    end

    # The lint reports; it never refuses. A host that compiles in one
    # deployment and runs in another would otherwise be unable to publish.
    #
    # sabotage: built the finding with `severity: :error` and returned it
    # from a stage -> the compile fails and this goes red (verified).
    test "the compile still succeeds and the chart is still emitted" do
      compiled = compile!(field_candidates: %{@key => [{"bdoc_OTHER", "Other"}]})

      assert compiled.scxml =~ "<scxml"
    end
  end

  describe "when nothing is claimed" do
    # sabotage: read the option with `Keyword.get/3` and a `%{}` default,
    # then linted every field -> an absent option starts warning and this
    # goes red (verified).
    test "the lint is off unless the caller supplies a map" do
      assert compile!([]).warnings == []
      assert compile!(field_candidates: %{}).warnings == []
    end

    # sabotage: dropped the `is_list(choices)` guard -> an open list is
    # linted as though it were closed and this goes red (verified). An open
    # list's whole claim is that these are values and not the values.
    test "an open list reports nothing at all" do
      compiled = compile!(field_candidates: %{@key => {:open, [{"bdoc_OTHER", "Other"}]}})

      assert compiled.warnings == []
    end

    # sabotage: keyed the lookup on the field key alone -> the `chart` field
    # of every type is linted against one list and this goes red (verified).
    test "a field the map does not name is not looked at" do
      compiled = compile!(field_candidates: %{{"host.step", "chart"} => [{"x", "X"}]})

      assert compiled.warnings == []
    end

    # sabotage: dropped the `value != ""` guard -> an unset field warns
    # about the empty string, which is `validate_config/1`'s finding to
    # make and not this one's (verified).
    test "an unset value is validate_config's business, not the lint's" do
      {:ok, compiled} =
        Compiler.compile(
          Document.new(
            Block.new("core.sequence",
              id: "blk_ROOT",
              slots: %{
                "body" => [
                  Block.new("core.subchart",
                    id: "blk_ELIG",
                    config: %{"chart" => "bdoc_CHILD", "outcomes" => "approved"},
                    slots: %{"on_approved" => [], "on_error" => []}
                  )
                ]
              }
            ),
            id: "bdoc_signup"
          ),
          Palette.core(),
          field_candidates: %{{"core.subchart", "assign_to"} => [{"eligibility", "Eligibility"}]}
        )

      assert compiled.warnings == []
    end
  end
end
