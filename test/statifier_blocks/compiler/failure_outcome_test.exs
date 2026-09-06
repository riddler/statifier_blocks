defmodule StatifierBlocks.Compiler.FailureOutcomeTest do
  @moduledoc """
  The campaign-033 failure seam, block half (`sb-napt`, mirrored with
  `sp-n8g`): a block type may class one of the outcomes it already
  declares as **failure**, and the compiler emits a reserved `<donedata>`
  `<param>` on that outcome's top-level `<final>` under `:child_use` and
  under `:terminate` alike.

  The key and its one permitted value are `statifier_persistence`'s, fixed
  by that package's ADR-0008 amendment of 2026-09-06, and they are asserted
  here **byte for byte** rather than through a constant: the whole point of
  the seam is that two packages agree on one string, and a test that read
  this package's own attribute would agree with itself whatever the string
  became.

  What the class does *not* change is asserted just as hard. The outcome
  sets of `core.map` and `core.subchart` are the ones their records fix,
  routing is unchanged, and a type that does not export
  `failure_outcomes/1` compiles to the bytes it compiled to before the
  callback existed.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, BlockType, Compiler, Document, Palette, Provenance}
  alias StatifierBlocks.Core.{Map, Subchart}

  @tag_param ~s(<param expr="'failed'" name="statifier_persistence:run_status"/>)

  @map_config %{
    "items" => "signup.invitees",
    "chart" => "bdoc_CHILD",
    "item_as" => "invitee",
    "collect" => "answers"
  }

  defmodule Plain do
    @moduledoc """
    A host type with two outcomes and no `failure_outcomes/1` - the
    "before the callback existed" case, which has to keep compiling to the
    bytes it compiled to.
    """

    @behaviour StatifierBlocks.BlockType

    alias StatifierBlocks.Compiler.Context
    alias StatifierBlocks.Core.Emit

    @impl true
    def current_version, do: 1

    @impl true
    def slots(_config), do: []

    @impl true
    def config_schema(_config), do: []

    @impl true
    def validate_config(_config), do: :ok

    @impl true
    def outcomes(_config), do: [{"done", "Done"}, {"declined", "Declined"}]

    @impl true
    def emit(%Block{}, context) do
      with {:ok, done} <- Context.outcome_id(context, "done"),
           {:ok, declined} <- Context.outcome_id(context, "declined") do
        {:ok, Emit.state(context.state_id, done, [Emit.final(done), Emit.final(declined)])}
      end
    end
  end

  defmodule Nonsense do
    @moduledoc """
    A host type whose `failure_outcomes/1` returns something the spec does
    not describe. The resolver is total over it, for `outcome_names/2`'s
    reason: nonsense compiles to the bytes it compiled to, it does not
    crash the compiler.
    """

    @behaviour StatifierBlocks.BlockType

    alias StatifierBlocks.Compiler.Context
    alias StatifierBlocks.Core.Emit

    @impl true
    def current_version, do: 1

    @impl true
    def slots(_config), do: []

    @impl true
    def config_schema(_config), do: []

    @impl true
    def validate_config(_config), do: :ok

    @impl true
    def failure_outcomes(_config), do: %{"done" => true}

    @impl true
    def emit(%Block{}, context) do
      with {:ok, done} <- Context.outcome_id(context, "done") do
        {:ok, Emit.state(context.state_id, done, [Emit.final(done)])}
      end
    end
  end

  setup do
    %{
      palette:
        Palette.new(
          Elixir.Map.merge(Palette.core_types(), %{
            "signup.plain" => Plain,
            "signup.nonsense" => Nonsense
          })
        )
    }
  end

  describe "the declaration surface" do
    # sabotage: returned `[]` from the `failure_outcomes/1` resolver's
    # present-callback branch -> `core.map` classes nothing and this goes
    # red (verified)
    test "core.map and core.subchart class their error outcome, and nothing else" do
      assert BlockType.failure_outcomes(Map, @map_config) == ["error"]
      assert BlockType.failure_outcomes(Subchart, %{"chart" => "bdoc_CHILD"}) == ["error"]
    end

    # The class is a second axis, not a third outcome: ADR-0009 decision 4
    # fixes `core.map` at two outcomes and this asserts the fix held.
    # sabotage: added an `{"failed", "Failed"}` outcome to `core.map` ->
    # the fixed set grows and this goes red (verified)
    test "the outcome sets their records fix are unchanged" do
      assert BlockType.outcome_names(Map, @map_config) == ["done", "error"]

      assert BlockType.outcome_names(Subchart, %{
               "chart" => "bdoc_CHILD",
               "outcomes" => "approved\ndeclined"
             }) == ["approved", "declined", "error"]
    end

    # sabotage: dropped the `function_exported?/3` guard from the resolver
    # -> a type without the callback raises instead of defaulting and this
    # goes red (verified)
    test "a type that does not export the callback classes nothing" do
      assert BlockType.failure_outcomes(Plain, %{}) == []
      assert BlockType.failure_outcomes(StatifierBlocks.Core.Sequence, %{}) == []
    end

    # sabotage: returned the callback's value unsanitized -> a host type
    # that declares nonsense reaches the compiler's `in/2` with a map and
    # this goes red (verified)
    test "a malformed declaration classes nothing rather than raising" do
      assert BlockType.failure_outcomes(Nonsense, %{}) == []
    end
  end

  describe "with terminate: true" do
    setup ctx, do: %{compiled: compile_map!(ctx, terminate: true)}

    # The seam itself. The key and the value are `statifier_persistence`'s
    # ADR-0008 amendment of 2026-09-06, spelled out here rather than read
    # off this package's own attribute.
    # sabotage: emitted the reserved param under `:child_use` only -> a
    # terminating root says nothing about having failed and this goes red
    # (verified)
    test "the failure-classed final carries the reserved param, byte for byte", %{
      compiled: compiled
    } do
      assert compiled.scxml =~
               ~s(<final id="s_blk_MAP__root_error"><donedata>) <>
                 @tag_param <> ~s(</donedata></final>)
    end

    # sabotage: classed every outcome rather than the declared ones -> the
    # `done` final gains a payload saying it failed and this goes red
    # (verified)
    test "the outcome that is not failure-classed stays a bare final", %{compiled: compiled} do
      assert compiled.scxml =~ ~s(<final id="s_blk_MAP__root_done"/>)
    end

    # ADR-0004 decision 5: the map is total over the emitted bytes, and
    # the new `<donedata>` span is inside the final the root block owns.
    # sabotage: skipped `Attribution.stamp/3` on the added final -> the
    # span is unowned and this goes red (verified)
    test "the root block owns the failure-classed final, in its root_ role", %{compiled: compiled} do
      assert {:ok, owner} =
               Provenance.owner_of_state(compiled.provenance, "s_blk_MAP__root_error")

      assert owner.block_id == "blk_MAP"
      assert owner.role == "root_error"
    end

    # The state is one claim; the added bytes are another, and decision 5
    # is about the bytes. This resolves the offset of the reserved
    # `<param>` itself through the span map.
    # sabotage: emitted the reserved param outside `Attribution.stamp/3`'s
    # reach -> the offset resolves to `:error` and this goes red
    # (verified)
    test "the reserved param's own bytes resolve to the root block", %{compiled: compiled} do
      {offset, _length} = :binary.match(compiled.scxml, @tag_param)

      assert {:ok, owner} = Provenance.owner_at(compiled.provenance, offset)
      assert owner.block_id == "blk_MAP"
      assert owner.role == "root_error"
    end

    # sabotage: emitted the reserved key with a dot separator -> the
    # engine resolves a `statifier_persistence` submap that is not there
    # and this goes red (verified)
    test "the engine resolves the tag to the flat reserved key", %{compiled: compiled} do
      assert {:ok, machine} = Statifier.compile(compiled.scxml)
      {machine_state, _effects} = Statifier.initialize(machine)

      {:ok, finished, effects} =
        Statifier.send_event(machine_state, "error.communication.invoke.blk_MAP")

      assert finished.status == :done

      assert [done: %Statifier.Effect.Done{donedata: donedata}] = effects
      assert donedata == %{"statifier_persistence:run_status" => "failed"}
    end
  end

  describe "with child_use: true" do
    setup ctx, do: %{compiled: compile_map!(ctx, child_use: true)}

    # The tag rides beside the `outcome` param the child shape already
    # emits, appended rather than replacing it: a parent still learns
    # which outcome the child reached.
    # sabotage: replaced the `outcome` param instead of appending ->
    # the parent loses the outcome name and this goes red (verified)
    test "the failure-classed final carries both params, outcome first", %{compiled: compiled} do
      assert compiled.scxml =~
               ~s(<final id="s_blk_MAP__child_error"><donedata>) <>
                 ~s(<param expr="'error'" name="outcome"/>) <>
                 @tag_param <> ~s(</donedata></final>)
    end

    # sabotage: emitted the reserved param on every child final -> a
    # successful child reports a failed run and this goes red (verified)
    test "the outcome that is not failure-classed is unchanged", %{compiled: compiled} do
      assert compiled.scxml =~
               ~s(<final id="s_blk_MAP__child_done"><donedata>) <>
                 ~s(<param expr="'done'" name="outcome"/></donedata></final>)
    end
  end

  describe "a type that classes nothing" do
    # The additive claim, pinned in bytes: adding the callback changed
    # nothing for a type that does not export it.
    # sabotage: defaulted the resolver to the full outcome list -> every
    # existing type's finals gain the reserved param and this goes red
    # (verified)
    test "compiles to finals with no reserved param at all", ctx do
      root = Block.new("signup.plain", id: "blk_PLAIN")

      {:ok, terminated} =
        Compiler.compile(Document.new(root, id: "bdoc_ROOT"), ctx.palette, terminate: true)

      {:ok, child} =
        Compiler.compile(Document.new(root, id: "bdoc_ROOT"), ctx.palette, child_use: true)

      assert terminated.scxml =~ ~s(<final id="s_blk_PLAIN__root_declined"/>)
      refute terminated.scxml =~ "statifier_persistence"
      refute child.scxml =~ "statifier_persistence"
    end

    # sabotage: dropped the `sanitize_failure_outcomes/1` list branch ->
    # the malformed declaration reaches the emission and this goes red
    # (verified)
    test "a malformed declaration compiles rather than crashing", ctx do
      root = Block.new("signup.nonsense", id: "blk_NON")

      assert {:ok, compiled} =
               Compiler.compile(Document.new(root, id: "bdoc_ROOT"), ctx.palette, terminate: true)

      refute compiled.scxml =~ "statifier_persistence"
    end
  end

  describe "the parent's side" do
    # ADR-0009 decision 4's reading, unchanged: the per-child answers are
    # data in `collect`, and the parent branches on them with an ordinary
    # `core.branch` after the block. The failure class buys the block
    # nothing here, which is the claim.
    # sabotage: dropped the `collect` param from `core.map`'s `<invoke>`
    # -> the compiled document stops naming the location the branch reads
    # and this goes red (verified)
    test "a core.branch reads the collected answers like any datamodel value", ctx do
      root =
        Block.new("core.sequence",
          id: "blk_SEQ",
          slots: %{
            "body" => [
              Block.new("core.map", id: "blk_MAP", config: @map_config),
              Block.new("core.branch",
                id: "blk_BRANCH",
                config: %{"condition" => "answers.length > 0"}
              )
            ]
          }
        )

      assert {:ok, compiled} =
               Compiler.compile(Document.new(root, id: "bdoc_ROOT"), ctx.palette, [])

      assert compiled.scxml =~ "answers"
      assert {:ok, _machine} = Statifier.compile(compiled.scxml)
    end
  end

  # `on_error` is occupied on purpose. `core.map` emits the
  # `error.communication.invoke` route and the `o_error` outcome final
  # only when that slot holds something (`core.invoke`'s rule, unchanged
  # by this bead), so an author who wants a failure-classed root final to
  # be reachable has to wire the slot - and this file asserts a reachable
  # one, not a final nothing can enter.
  defp compile_map!(ctx, opts) do
    root =
      Block.new("core.map",
        id: "blk_MAP",
        config: @map_config,
        slots: %{"on_error" => [Block.new("core.sequence", id: "blk_ERR")]}
      )

    {:ok, compiled} = Compiler.compile(Document.new(root, id: "bdoc_ROOT"), ctx.palette, opts)

    compiled
  end
end
