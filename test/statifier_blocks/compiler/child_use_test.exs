defmodule StatifierBlocks.Compiler.ChildUseTest do
  @moduledoc """
  C1 of ADR-0004's 2026-08-29 amendment: a document compiled **for use as
  a child** emits one top-level `<final>` per root-block outcome, reached
  from `done.outcome.<root state id>.<outcome>` and carrying the outcome
  name as done data.

  That is the half a parent's `core.subchart` cannot supply for itself:
  raised events are internal to the session that raises them, so an
  outcome only crosses an `<invoke>` as data on the completion event
  (SCXML 3.7 and 5.5). The parent half is
  `StatifierBlocks.Core.SubchartTest`.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Compiler, Document, Palette, Provenance}
  alias StatifierBlocks.Compiler.Context
  alias StatifierBlocks.Core.Emit

  defmodule Eligibility do
    @moduledoc """
    `signup.eligibility`: a host step that waits, and finishes `done` or
    `abandoned` depending on which event arrives.

    A two-outcome **root** is what C1 is about, and no core type declares
    a pair of outcomes an author names, so the child document's root is a
    host type here exactly as it would be in a host's own palette.
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
    # sabotage: defaulted `:child_use` to `true` -> every document gains
    # top-level finals it never asked for and this goes red (verified)
    test "the emission is exactly what it was", ctx do
      assert compile!(ctx, []).scxml == compile!(ctx, child_use: false).scxml
      refute compile!(ctx, []).scxml =~ "donedata"
      refute compile!(ctx, []).scxml =~ "__child_"
    end
  end

  describe "with child_use: true (C1)" do
    setup ctx do
      %{compiled: compile!(ctx, child_use: true)}
    end

    # sabotage: minted the top-level final in the reserved `o_` namespace
    # -> `role_id/2` refuses it, no final is emitted, and this goes red
    # (verified)
    test "one top-level <final> per root-block outcome, carrying the outcome as done data", %{
      compiled: compiled
    } do
      assert compiled.scxml =~
               ~s(<final id="s_blk_ELIG__child_done"><donedata>) <>
                 ~s(<param expr="'done'" name="outcome"/></donedata></final>)

      assert compiled.scxml =~
               ~s(<final id="s_blk_ELIG__child_abandoned"><donedata>) <>
                 ~s(<param expr="'abandoned'" name="outcome"/></donedata></final>)
    end

    # sabotage: wrote the transitions as siblings of the root state rather
    # than on it -> `<scxml>` carries a `<transition>` the engine refuses,
    # the compile fails, and this goes red (verified)
    test "the transitions sit on the root block's own state", %{compiled: compiled} do
      # One byte-exact run: both transitions inside the root state, in
      # declaration order, and the finals they target immediately after
      # the state closes.
      assert compiled.scxml =~
               ~s(<transition event="done.outcome.s_blk_ELIG.done" ) <>
                 ~s(target="s_blk_ELIG__child_done"/>) <>
                 ~s(<transition event="done.outcome.s_blk_ELIG.abandoned" ) <>
                 ~s(target="s_blk_ELIG__child_abandoned"/>) <>
                 ~s(</state><final id="s_blk_ELIG__child_done">)
    end

    # sabotage: dropped the root block's own outcome finals from the
    # comparison - they are unchanged by C1, and a compile that moved them
    # would take this red (verified by removing the `<raise>` from
    # `Emit.final/1`)
    test "the root block's own outcome finals are untouched", %{compiled: compiled} do
      assert compiled.scxml =~
               ~s(<final id="s_blk_ELIG__o_done"><onentry>) <>
                 ~s(<raise event="done.outcome.s_blk_ELIG.done"/></onentry></final>)
    end

    # sabotage: skipped `Attribution.stamp/3` on the added elements ->
    # the finals and transitions are unowned, the provenance map is no
    # longer total, and this goes red (verified)
    test "every added state is owned by the root block, in its child_ role", %{compiled: compiled} do
      assert {:ok, owner} =
               Provenance.owner_of_state(compiled.provenance, "s_blk_ELIG__child_abandoned")

      assert owner.block_id == "blk_ELIG"
      assert owner.role == "child_abandoned"
    end

    # This is C1's whole point, observed rather than argued: what the
    # session reports on the way out is the outcome the root block
    # finished with, in the shape a parent's `core.subchart` routes on
    # (`_event.data.outcome`).
    # sabotage: emitted the `<param>` with a bare outcome name rather than
    # a quoted expression -> the child sends the value of a datamodel
    # location that does not exist instead of the outcome, and this goes
    # red (verified)
    test "the run reports the outcome as done data, which is what crosses the boundary", %{
      compiled: compiled
    } do
      {:ok, machine} = Statifier.compile(compiled.scxml)
      {machine_state, _effects} = Statifier.initialize(machine)

      {:ok, finished, effects} = Statifier.send_event(machine_state, "signup.abandoned")

      assert finished.status == :done
      assert [done: %Statifier.Effect.Done{donedata: donedata}] = effects
      assert donedata == %{"outcome" => "abandoned"}
    end
  end

  describe "a single-outcome root" do
    # sabotage: emitted a final only for a root declaring more than one
    # outcome -> a plain document compiled for child use reports nothing
    # at all to its parent and this goes red (verified)
    test "still emits its one final, so a parent's default arm has data to read", ctx do
      root = Block.new("core.sequence", id: "blk_SEQ")

      {:ok, compiled} =
        Compiler.compile(Document.new(root, id: "bdoc_CHILD"), ctx.palette, child_use: true)

      assert compiled.scxml =~
               ~s(<final id="s_blk_SEQ__child_done"><donedata>) <>
                 ~s(<param expr="'done'" name="outcome"/></donedata></final>)

      assert {:ok, _machine} = Statifier.compile(compiled.scxml)
    end
  end

  defp compile!(ctx, opts) do
    root = Block.new("signup.eligibility", id: "blk_ELIG")

    {:ok, compiled} =
      Compiler.compile(Document.new(root, id: "bdoc_CHILD"), ctx.palette, opts)

    compiled
  end
end
