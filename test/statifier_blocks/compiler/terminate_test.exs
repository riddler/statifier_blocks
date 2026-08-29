defmodule StatifierBlocks.Compiler.TerminateTest do
  @moduledoc """
  ADR-0004's 2026-08-29 root-termination note: a document compiled as a
  **root document that finishes** emits one top-level `<final>` per
  root-block outcome, reached from `done.outcome.<root state id>.<outcome>`
  and carrying no `<donedata>`.

  The gap it closes is observable and pinned here in both directions: a
  root block's own outcome finals are children of the root compound state,
  so completing the root block raises `done.outcome` internally and the
  session never enters a top-level `<final>`. Without the option the run
  stays active forever, which is what leaves a durable run uncompleted;
  with it the session reaches `:done`.

  The child-chart half is `StatifierBlocks.Compiler.ChildUseTest`, and the
  two options are mutually exclusive - a chart is compiled either for use
  as a child or as a root that finishes.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Compiler, CoreFixtures, Document, Palette, Provenance}
  alias StatifierBlocks.Compiler.Context
  alias StatifierBlocks.Core.Emit

  @worked_example "test/fixtures/documents/worked_example.json"
  @signup_wizard "test/fixtures/documents/signup_wizard.json"

  defmodule Eligibility do
    @moduledoc """
    `signup.eligibility`: a host step that waits, and finishes `done` or
    `abandoned` depending on which event arrives.

    A two-outcome root is what makes the added finals worth asserting on,
    and no core type declares a pair of outcomes an author names, so the
    root is a host type here exactly as it would be in a host's palette.
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
    def outcomes(_config), do: [{"done", "Eligible"}, {"abandoned", "Abandoned"}]

    @impl true
    def emit(%Block{}, context) do
      with {:ok, waiting} <- Context.role_id(context, "waiting"),
           {:ok, done} <- Context.outcome_id(context, "done"),
           {:ok, abandoned} <- Context.outcome_id(context, "abandoned") do
        inner =
          Emit.state(waiting, nil, [
            Emit.transition(event: "signup.eligible", target: done),
            Emit.transition(event: "signup.abandoned", target: abandoned)
          ])

        {:ok,
         Emit.state(context.state_id, waiting, [inner, Emit.final(done), Emit.final(abandoned)])}
      end
    end
  end

  setup do
    %{
      palette:
        Palette.new(Map.merge(Palette.core_types(), %{"signup.eligibility" => Eligibility}))
    }
  end

  describe "without the option" do
    # sabotage: defaulted `:terminate` to `true` -> every document gains
    # top-level finals it never asked for and this goes red (verified)
    test "the emission is exactly what it was", ctx do
      assert compile!(ctx, []).scxml == compile!(ctx, terminate: false).scxml
      refute compile!(ctx, []).scxml =~ "__root_"
    end

    # The worked examples are the whole `core.*` vocabulary between them
    # (`StatifierBlocks.DocumentFixtures`), so byte-identity here is the
    # claim that the option changes nothing for a document that does not
    # pass it, not just for this file's two-outcome root.
    #
    # sabotage: defaulted `:terminate` to `true` -> both worked examples
    # gain top-level finals they never asked for and this goes red
    # (verified)
    test "every worked example compiles to the bytes it did before the option existed" do
      for path <- [@worked_example, @signup_wizard] do
        assert compile_fixture!(path, []).scxml == compile_fixture!(path, terminate: false).scxml
        refute compile_fixture!(path, []).scxml =~ "__root_"
      end
    end
  end

  describe "with terminate: true" do
    setup ctx do
      %{compiled: compile!(ctx, terminate: true)}
    end

    # sabotage: emitted the final with the child-use `<donedata>` -> the
    # root document reports an invoke-flavoured payload nobody asked for
    # and this goes red (verified)
    test "one bare top-level <final> per root-block outcome, with no donedata", %{
      compiled: compiled
    } do
      assert compiled.scxml =~ ~s(<final id="s_blk_ELIG__root_done"/>)
      assert compiled.scxml =~ ~s(<final id="s_blk_ELIG__root_abandoned"/>)
      refute compiled.scxml =~ "donedata"
    end

    # sabotage: wrote the transitions as siblings of the root state rather
    # than on it -> `<scxml>` carries a `<transition>` the engine refuses,
    # the compile fails, and this goes red (verified)
    test "the transitions sit on the root block's own state", %{compiled: compiled} do
      assert compiled.scxml =~
               ~s(<transition event="done.outcome.s_blk_ELIG.done" ) <>
                 ~s(target="s_blk_ELIG__root_done"/>) <>
                 ~s(<transition event="done.outcome.s_blk_ELIG.abandoned" ) <>
                 ~s(target="s_blk_ELIG__root_abandoned"/>) <>
                 ~s(</state><final id="s_blk_ELIG__root_done"/>)
    end

    # sabotage: minted the added finals in the reserved `o_` namespace ->
    # they collide with the root block's own outcome finals, which are
    # unchanged by this option, and this goes red (verified)
    test "the root block's own outcome finals are untouched", %{compiled: compiled} do
      assert compiled.scxml =~
               ~s(<final id="s_blk_ELIG__o_done"><onentry>) <>
                 ~s(<raise event="done.outcome.s_blk_ELIG.done"/></onentry></final>)
    end

    # sabotage: skipped `Attribution.stamp/3` on the added elements -> the
    # finals and transitions are unowned, the provenance map is no longer
    # total, and this goes red (verified)
    test "every added state is owned by the root block, in its root_ role", %{compiled: compiled} do
      assert {:ok, owner} =
               Provenance.owner_of_state(compiled.provenance, "s_blk_ELIG__root_abandoned")

      assert owner.block_id == "blk_ELIG"
      assert owner.role == "root_abandoned"
    end
  end

  describe "the gap, run through the engine" do
    # This is the bead's whole point, observed rather than argued, and
    # both directions are asserted so the option is pinned to the
    # behaviour rather than to the bytes.
    # sabotage: made `completion_finals/4` return the emission unchanged
    # -> the run never reaches a top-level final and this goes red
    # (verified)
    test "a root document compiled with terminate: true reaches :done, with no done data", ctx do
      compiled = compile!(ctx, terminate: true)

      {:ok, machine} = Statifier.compile(compiled.scxml)
      {machine_state, _effects} = Statifier.initialize(machine)

      {:ok, finished, effects} = Statifier.send_event(machine_state, "signup.abandoned")

      assert finished.status == :done
      # `:undefined` is how the engine spells "this final carried no
      # `<donedata>`" - the child-use half gets `%{"outcome" => ...}` here,
      # and a root document deliberately gets nothing.
      assert [done: %Statifier.Effect.Done{donedata: :undefined}] = effects
    end

    # The gap itself, pinned: the same document without the option runs
    # the same event to the same place and never completes, which is what
    # leaves a durable run active forever.
    # sabotage: defaulted `:terminate` to `true` -> the option stops being
    # what makes the difference, the run completes anyway, and this goes
    # red (verified)
    test "the same document without the option does not reach :done", ctx do
      compiled = compile!(ctx, [])

      {:ok, machine} = Statifier.compile(compiled.scxml)
      {machine_state, _effects} = Statifier.initialize(machine)

      {:ok, finished, _effects} = Statifier.send_event(machine_state, "signup.abandoned")

      refute finished.status == :done
    end
  end

  describe "a single-outcome root" do
    # sabotage: emitted a final only for a root declaring more than one
    # outcome -> a plain sequence root never terminates and this goes red
    # (verified)
    test "still terminates, so an ordinary document finishes too", ctx do
      root = Block.new("core.sequence", id: "blk_SEQ")

      {:ok, compiled} =
        Compiler.compile(Document.new(root, id: "bdoc_ROOT"), ctx.palette, terminate: true)

      assert compiled.scxml =~ ~s(<final id="s_blk_SEQ__root_done"/>)
      assert {:ok, _machine} = Statifier.compile(compiled.scxml)
    end
  end

  describe "both options together" do
    # sabotage: dropped `chart_use_stage/2` from the `compile/3` chain ->
    # the compile succeeds and emits two transitions on the same
    # `done.outcome` event, document order deciding which final a run
    # reaches, and this goes red (verified)
    test "are refused with an :emit finding rather than silently resolved", ctx do
      root = Block.new("core.sequence", id: "blk_SEQ")

      assert {:error, [finding]} =
               Compiler.compile(Document.new(root, id: "bdoc_ROOT"), ctx.palette,
                 child_use: true,
                 terminate: true
               )

      assert finding.stage == :emit
      assert finding.code == :conflicting_chart_use
      assert finding.block_id == "blk_SEQ"
      assert finding.severity == :error
      assert finding.message =~ "either for use as a child"
    end
  end

  defp compile!(ctx, opts) do
    root = Block.new("signup.eligibility", id: "blk_ELIG")

    {:ok, compiled} =
      Compiler.compile(Document.new(root, id: "bdoc_ROOT"), ctx.palette, opts)

    compiled
  end

  defp compile_fixture!(path, opts) do
    {:ok, document} = Document.from_json(File.read!(path))
    {:ok, compiled} = Compiler.compile(document, CoreFixtures.palette(), opts)
    compiled
  end
end
