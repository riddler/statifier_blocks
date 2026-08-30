defmodule StatifierBlocks.Compiler.SelfReferenceTest do
  @moduledoc """
  The direct self-reference refusal: a document may not run itself
  (ADR-0004's 2026-08-29 amendment on what `core.subchart`'s `src`
  resolves against).

  A signup wizard throughout: `bdoc_SIGNUP` holds an eligibility step that
  runs another chart, and the refusal is about which chart it names.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Compiler, Document, Emission, Palette}
  alias StatifierBlocks.Compiler.SelfReference

  doctest StatifierBlocks.Compiler.SelfReference

  @document_id "bdoc_SIGNUP"

  describe "the refusal" do
    # sabotage: made `element_findings/2` return [] for every element (the
    # `<invoke>` clause deleted, the catch-all left) -> the self-naming
    # document compiles and this goes red (verified)
    test "a subchart naming the document it sits in is refused" do
      assert [finding] = refuse(subchart(@document_id))

      assert finding.stage == :emit
      assert finding.code == :self_reference
      assert finding.reason == {:self_reference, @document_id}
      assert finding.block_id == "blk_ELIG"
      assert finding.config_key == "chart"
      assert finding.config_value_span == nil
      assert finding.severity == :error
      assert finding.fault == :author
      assert finding.message =~ ~s("#{@document_id}")
      assert finding.message =~ "the document this block is in"
    end

    # sabotage: relaxed the `src` match to `String.starts_with?/2` -> a
    # subchart naming `bdoc_SIGNUP_CHILD` is refused too and this goes red
    # (verified). Only the id itself is a self-reference; a document whose
    # id merely shares a prefix is a different document.
    test "a subchart naming a different document compiles" do
      assert {:ok, compiled} = compile(subchart("bdoc_ELIGIBILITY"))
      assert compiled.scxml =~ ~s(src="bdoc_ELIGIBILITY")

      assert {:ok, _near} = compile(subchart(@document_id <> "_CHILD"))
    end

    # sabotage: dropped the `@element` match from `element_findings/2`'s
    # head, matching `src` on any element -> the non-invoke element below
    # is refused and this goes red (verified).
    test "src on an element that is not an invoke makes no claim" do
      emission = Emission.element("content", [{"src", @document_id}])

      assert SelfReference.check(emission, @document_id) == []
    end

    # sabotage: had `check/2` walk only the top element and not its
    # children -> the nested `<invoke>` is missed and this goes red
    # (verified). A subchart is never at the top of an emission: it sits
    # inside the block's own state, inside the running state.
    test "the walk reaches an invoke nested under other elements" do
      emission =
        Emission.element("state", [], [
          Emission.element("state", [], [
            Emission.element("invoke", [{"src", @document_id}])
          ])
        ])

      assert [finding] = SelfReference.check(emission, @document_id)
      assert finding.reason == {:self_reference, @document_id}
    end
  end

  describe "a subchart nested in the tree" do
    # sabotage: had `check/2` walk only the top element -> the subchart
    # under the sequence is missed and this goes red (verified). A real
    # document never has the subchart at the root.
    test "is refused, and the finding carries its document path" do
      subchart = subchart(@document_id)
      sequence = Block.new("core.sequence", id: "blk_SEQ", slots: %{"body" => [subchart]})

      assert [finding] = refuse(sequence)
      assert finding.block_id == "blk_ELIG"
      assert finding.path == [{"blk_SEQ", "body", 0}]
      assert finding.config_key == "chart"
    end
  end

  describe "presenting the refusal" do
    # sabotage: none available - this test asserts a seam the module
    # documents rather than behaviour it implements, and it is here so a
    # change to `Finding.from_compiler/2`'s derivation cannot silently
    # make the moduledoc's recipe wrong.
    test "needs an explicit source, exactly as the sensitive-path refusal does" do
      findings = refuse(subchart(@document_id))

      # ADR-0005 amendment 11h: the default derivation no longer refuses
      # an unplaceable stage, it calls it `:compile`. The override is
      # still what gets these to `:lint`, which is what the recipe below
      # and this module's moduledoc are about.
      assert {:ok, %StatifierBlocks.Finding{source: :compile}} =
               StatifierBlocks.Finding.from_compiler(hd(findings))

      assert {presentation, []} =
               StatifierBlocks.Finding.from_compiler_all(findings, source: :lint)

      assert [%StatifierBlocks.Finding{anchor: {:config, "blk_ELIG", "chart"}}] = presentation
    end
  end

  describe "what the refusal says about cycles" do
    # sabotage: removed the cycle sentence from the message -> this goes
    # red (verified). The message is where an author is told that the
    # compiler decided the half it can see and the host owns the rest.
    test "the message names cross-document cycles as the host's" do
      assert [finding] = refuse(subchart(@document_id))

      assert finding.message =~ "cycle through two or more"
      assert finding.message =~ "document graph"
    end
  end

  defp subchart(chart),
    do:
      Block.new("core.subchart",
        id: "blk_ELIG",
        config: %{"chart" => chart, "outcomes" => "eligible\nrejected"}
      )

  defp compile(root),
    do: Compiler.compile(Document.new(root, id: @document_id), Palette.core(), [])

  defp refuse(root) do
    assert {:error, findings} = compile(root)
    findings
  end
end
