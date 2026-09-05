defmodule StatifierBlocks.Compiler.ResumableDeadlineTest do
  @moduledoc """
  ADR-0010's Note of 2026-09-02 (the operator's `RQ-026-6` ruling, option
  (c)): a delayed `core.send` at the head of a `core.resumable_group`'s
  `body`, with a `resume` handler on that group's `interrupts` rail, is an
  **advisory** and not a refusal.

  The suite is written condition by condition, because the acceptance
  criterion is a conjunction: the finding fires on exactly that shape, and
  mutating any single one of its conditions - the group's type, the send's
  delay, the send's position, the handler's outcome - has to silence it.

  Thirteen mutations were run one at a time, and every one of them went
  red; the note above each test names the mutation that catches it. In
  `StatifierBlocks.Compiler`: drop the `module == ResumableGroup` guard;
  drop the `resumes?/1` conjunct; drop the `armed_head?/1` conjunct; make
  `delayed?/1` true for any binary; make `delayed?/1` true for an absent
  key; accept any `outcome`; relax `armed_head?/1` from the head to
  anywhere in the body; drop the recursive descent; emit one warning per
  resume handler rather than one per group; turn the advisory into a
  refusal; flip its severity to `:error`; and warn on every block rather
  than on the offending group. In `StatifierBlocks.Core.Send`: relax the
  `delay` validation to accept anything.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Compiler, Document, Finding, Palette}

  @code :deadline_lost_on_resume

  defp send_block(id, delay),
    do: Block.new("core.send", id: id, config: %{"event" => "order.expired", "delay" => delay})

  defp step(id), do: Block.new("core.wait", id: id, config: %{"duration" => "1h"})

  defp handler(id, outcome),
    do:
      Block.new("core.on_event",
        id: id,
        config: %{"event" => "order.paused", "outcome" => outcome}
      )

  defp group(type, id, body, interrupts) do
    config = if type == "core.resumable_group", do: %{"history" => "shallow"}, else: %{}

    Block.new(type,
      id: id,
      config: config,
      slots: %{"body" => body, "interrupts" => interrupts}
    )
  end

  defp document(children) do
    Document.new(Block.new("core.sequence", id: "blk_ROOT", slots: %{"body" => children}),
      id: "bdoc_D"
    )
  end

  defp warnings(document) do
    assert {:ok, compiled} = Compiler.compile(document, Palette.core())
    compiled.warnings
  end

  defp advisories(document) do
    document
    |> warnings()
    |> Enum.filter(&(&1.code == @code))
  end

  # The shape the ruling names, and the baseline every silence test below
  # is one mutation away from.
  defp offending_document(opts \\ []) do
    type = Keyword.get(opts, :type, "core.resumable_group")
    delay = Keyword.get(opts, :delay, "2h")
    outcome = Keyword.get(opts, :outcome, "resume")
    body = Keyword.get(opts, :body, [send_block("blk_SND", delay), step("blk_STEP")])

    document([group(type, "blk_GRP", body, [handler("blk_ON", outcome)])])
  end

  describe "the advisory fires on the ruled shape" do
    # Sabotage: dropped the recursive descent from `deadline_warnings/1` -
    # red, since the group is a child of the root rather than the root.
    test "one warning, anchored on the group, at :warning and never an error" do
      assert [finding] = advisories(offending_document())

      assert finding.code == @code
      assert finding.reason == {@code, "blk_GRP"}
      assert finding.stage == :emit
      assert finding.block_id == "blk_GRP"
      assert finding.severity == :warning
      assert finding.fault == :author
      assert finding.config_key == nil
    end

    # The ruling is "an advisory, not a refusal", and it "does not change
    # the compiled bytes". A compile that failed, or a chart that lost the
    # deadline the author wrote, would each be the ruling's opposite.
    # Sabotage: turned the advisory into a refusal, so a document carrying
    # it no longer compiled - red.
    test "the document still compiles, and the deadline is still in the chart" do
      assert {:ok, compiled} = Compiler.compile(offending_document(), Palette.core())

      assert compiled.scxml =~ ~s(delay="2h")
      assert compiled.scxml =~ ~s(event="order.expired")
    end

    # Sabotage: dropped the recursive descent - red. The ruling names a
    # consequence and two escapes, and all three are asserted here so a
    # rewrite cannot drop the half the author needs.
    test "the message states the consequence and both escapes" do
      assert [finding] = advisories(offending_document())

      assert finding.message =~ "after the first resume the group runs on with no deadline"
      assert finding.message =~ "Arm the deadline outside the group"
      assert finding.message =~ "use a core.group"
    end

    # D4's loudness reasoning: a longer rail is not a worse document.
    # Sabotage: emitted one warning per resume handler rather than one per
    # group - red.
    test "one warning per group, however many resume handlers the rail carries" do
      document =
        document([
          group(
            "core.resumable_group",
            "blk_GRP",
            [send_block("blk_SND", "2h")],
            [handler("blk_ON1", "resume"), handler("blk_ON2", "resume")]
          )
        ])

      assert [_one] = advisories(document)
    end

    # The walk is recursive, not a scan of the root's children.
    # Sabotage: dropped the recursive descent - red.
    test "a nested group is found" do
      inner =
        group("core.resumable_group", "blk_INNER", [send_block("blk_SND", "2h")], [
          handler("blk_ON", "resume")
        ])

      document =
        document([Block.new("core.sequence", id: "blk_SEQ", slots: %{"body" => [inner]})])

      assert [finding] = advisories(document)
      assert finding.block_id == "blk_INNER"
    end
  end

  describe "sabotage: mutating any single condition silences it" do
    # The ruling's own first silence: decision 3's behaviour 1, where the
    # deadline survives the resume.
    # Sabotage: dropped the `module == ResumableGroup` guard - red.
    test "a core.group with the same body and the same rail is silent" do
      assert [] == advisories(offending_document(type: "core.group"))
    end

    # The ruling's own second silence: the abandon path's lifetime is
    # correct for free.
    # Sabotage: made `resumes?/1` accept any `outcome` - red. Dropping the
    # `resumes?/1` conjunct altogether is red here too.
    test "a rail with no resume handler is silent" do
      assert [] == advisories(offending_document(outcome: "abandon"))
    end

    # Sabotage: dropped the `resumes?/1` conjunct - red.
    test "an empty interrupts rail is silent" do
      document =
        document([group("core.resumable_group", "blk_GRP", [send_block("blk_SND", "2h")], [])])

      assert [] == advisories(document)
    end

    # An undelayed send is not a deadline at all - it fires in the same
    # macrostep and there is nothing armed to lose.
    # Sabotage: made `delayed?/1` true for any binary - red.
    test "a send with no delay is silent" do
      assert [] == advisories(offending_document(delay: ""))
    end

    # Not a silence this pass has to produce: `core.send`'s own
    # `validate_config/1` refuses a delay that is neither empty nor a
    # duration, and the Config stage stops the pipeline before any warning
    # is collected. Asserted so a later relaxation there is caught here.
    # Sabotage: relaxed that validation to accept anything - red, which is
    # the whole reason this test is worth its line.
    test "a delay that is not a duration never reaches the advisory at all" do
      document = offending_document(delay: "   ")

      assert {:error, [finding]} = Compiler.compile(document, Palette.core())
      assert finding.stage == :config
      assert finding.config_key == "delay"
    end

    # Sabotage: made `delayed?/1`'s catch-all clause true, so an absent
    # `delay` key counted as a deadline - red.
    test "a send with no delay key at all is silent" do
      bare = Block.new("core.send", id: "blk_SND", config: %{"event" => "order.expired"})

      assert [] == advisories(offending_document(body: [bare]))
    end

    # Decision 1's convention is "first block of the group's body slot",
    # and the advisory reads the head for exactly that reason.
    # Sabotage: relaxed `armed_head?/1` from the head to anywhere in the
    # body - red.
    test "a delayed send that is not the head of the body is silent" do
      body = [step("blk_STEP"), send_block("blk_SND", "2h")]

      assert [] == advisories(offending_document(body: body))
    end

    # Sabotage: dropped the `armed_head?/1` conjunct - red.
    test "an empty body is silent" do
      document =
        document([
          group("core.resumable_group", "blk_GRP", [], [handler("blk_ON", "resume")])
        ])

      assert [] == advisories(document)
    end

    # The pair has to share a group. A deadline armed outside is the first
    # of the two escapes the message names, so it had better be silent.
    # Sabotage: dropped the `armed_head?/1` conjunct - red.
    test "a delayed send outside the group is silent - it is escape one" do
      document =
        document([
          send_block("blk_SND", "2h"),
          group("core.resumable_group", "blk_GRP", [step("blk_STEP")], [
            handler("blk_ON", "resume")
          ])
        ])

      assert [] == advisories(document)
    end

    # Sabotage: emitted the warning on every block rather than on the
    # offending group - red.
    test "a document with neither half is silent" do
      assert [] == advisories(document([step("blk_STEP")]))
    end
  end

  describe "it reaches the ADR-0005 findings layer as an advisory" do
    # The bead's other half: the ruling says "the ADR-0005 findings layer
    # raises an advisory", so the compiler finding has to survive the
    # adaptation into the presentation shape and land in the advisory
    # chrome rather than the error family. No code in
    # `StatifierBlocks.Finding` changed for this - decision 11's rule 2
    # (a finding that is not an error is `:lint`) already gets it right by
    # construction, and this test is what says so.
    # Sabotage: flipped the compiler finding's severity to `:error`, which
    # takes it out of decision 11's rule 2 and maps it to `:compile` - red.
    test "it adapts to a :lint finding anchored on the group, in the info/warning chrome" do
      assert [compiler_finding] = advisories(offending_document())
      assert {[finding], []} = Finding.from_compiler_all([compiler_finding])

      assert finding.source == :lint
      assert finding.severity == :warning
      assert finding.anchor == {:block, "blk_GRP"}
      assert finding.message == compiler_finding.message
      assert Finding.severity_class(finding) == "sb-finding--warning"
    end
  end
end
