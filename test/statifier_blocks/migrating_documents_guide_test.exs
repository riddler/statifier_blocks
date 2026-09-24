defmodule StatifierBlocks.MigratingDocumentsGuideTest do
  @moduledoc """
  The before/after pair `docs/guides/migrating-documents-0.27-to-0.34.md`
  walks through, compiled on the current release.

  The fixtures are four files: a patron-registration document as written for
  0.27 and as moved to declared outcomes, and the data declaration of the
  composite each one uses. Every compiled byte the guide quotes is asserted
  here, so the guide and the compiler cannot drift apart silently.

  A pure test. Nothing here names LiveView, so it compiles and runs headless.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Compiler, Document, Palette}
  alias StatifierBlocks.Composite.Data

  @dir "test/fixtures/documents/migrating_0_27_to_0_34"

  describe "the before document, as written for 0.27" do
    # Sabotage: had `OnEvent.finish_as/1` answer "went_back" for every
    # config - red: the unnamed handler's final moves off `__o_done` (verified).
    test "compiles, and the step after the screen follows it whichever way it finished" do
      assert {:ok, compiled} = compile("before", "screen_before")

      # The composite is its expansion in place: no state of its own.
      refute compiled.scxml =~ ~s(id="s_blk_VERIFY")

      # The next step is chained on the group's completion, which Back reaches
      # too.
      assert compiled.scxml =~
               ~s(<transition event="done.state.s_blk_VERIFY_body" target="s_blk_INTERESTS" type="internal"/>)

      # The Back handler finishes as `done`, as it always has.
      assert compiled.scxml =~
               ~s(<final id="s_blk_VERIFY_back__o_done"><onentry>) <>
                 ~s(<raise event="done.outcome.s_blk_VERIFY_back.done"/></onentry></final>)
    end
  end

  describe "the declaration migrated, the document not yet" do
    # Sabotage: had `OnEvent.outcomes/1` answer the default `done` for a
    # named handler - red: `went_back` is then raisable by nothing and the
    # compile is refused (verified).
    test "compiles to a state of its own, and the document still routes nothing" do
      assert {:ok, compiled} = compile("before", "screen_after")

      assert compiled.scxml =~
               ~s(<final id="s_blk_VERIFY_back__o_went_back"><onentry>) <>
                 ~s(<raise event="done.outcome.s_blk_VERIFY_back.went_back"/></onentry></final>)

      assert compiled.scxml =~
               ~s(<transition event="done.state.s_blk_VERIFY" target="s_blk_INTERESTS" type="internal"/>)
    end

    # Sabotage: had `OnEvent.outcomes/1`'s unnamed arm answer
    # `[{"went_back", "went_back"}]` - red: the unnamed handler then makes the
    # name raisable and the refusal disappears (verified).
    test "declaring the outcomes without naming the handler is refused" do
      row =
        update_in(
          declaration("screen_after"),
          ["subtree", Access.at(0), "slots", "interrupts", Access.at(0), "config"],
          &Map.delete(&1, "finish_as")
        )

      assert {:error, findings} = compile_with("before", row)

      assert [finding] = Enum.filter(findings, &(&1.code == :outcome_not_raisable))
      assert finding.stage == :resolve
      assert finding.reason == {:outcome_not_raisable, "blk_VERIFY", "went_back"}
    end
  end

  describe "the after document" do
    # Sabotage: had `Composite.outcome_slots/3` answer `[]` - red: the composite
    # answers no `on_` slot to route through (verified).
    test "routes each declared outcome through its slot before the composite's final" do
      assert {:ok, compiled} = compile("after", "screen_after")

      assert compiled.scxml =~
               ~s(<transition event="done.outcome.s_blk_VERIFY_back.went_back" target="s_blk_DETAILS" type="internal"/>)

      assert compiled.scxml =~
               ~s(<transition event="done.state.s_blk_DETAILS" target="s_blk_VERIFY__o_went_back" type="internal"/>)

      assert compiled.scxml =~
               ~s(<final id="s_blk_VERIFY__o_went_back"><onentry>) <>
                 ~s(<raise event="done.outcome.s_blk_VERIFY.went_back"/></onentry></final>)

      assert compiled.scxml =~
               ~s(<transition event="done.outcome.s_blk_VERIFY_wait.received" target="s_blk_INTERESTS" type="internal"/>)

      # The empty `on_timed_out` slot reaches its final directly.
      assert compiled.scxml =~
               ~s(<transition event="done.outcome.s_blk_VERIFY_wait.timed_out" target="s_blk_VERIFY__o_timed_out" type="internal"/>)

      # And the enclosing body continues on the composite's completion.
      assert compiled.scxml =~
               ~s(<transition event="done.state.s_blk_VERIFY" target="s_blk_ROOT__o_done" type="internal"/>)
    end

    # Sabotage: had `non_declaring_slot_findings/2` filter out every
    # `:undeclared_slot` - red: neither slot draws its finding
    # (verified).
    test "against a declaration that was not migrated, its slots are refused" do
      assert {:error, findings} = compile("after", "screen_before")

      assert findings |> Enum.filter(&(&1.code == :undeclared_slot)) |> Enum.map(& &1.reason) ==
               [
                 {:undeclared_slot, "blk_VERIFY", "on_received", 1},
                 {:undeclared_slot, "blk_VERIFY", "on_went_back", 1}
               ]
    end
  end

  defp compile(document, declaration), do: compile_with(document, declaration(declaration))

  defp compile_with(document, row) do
    {:ok, state} = Data.declaration(row)
    palette = Palette.new(Map.put(Palette.core_types(), "library.verify_email", {Data, state}))
    {:ok, document} = Document.from_json(File.read!(Path.join(@dir, document <> ".json")))

    Compiler.compile(document, palette)
  end

  defp declaration(name),
    do: @dir |> Path.join(name <> ".json") |> File.read!() |> Jason.decode!()
end
