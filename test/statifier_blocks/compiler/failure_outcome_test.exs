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
  alias StatifierBlocks.Core.{Invoke, Map, Subchart}

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

    # ADR-0002's amendment of 2026-09-06, section 1: `core.invoke` had
    # been minting an `error` outcome final while declaring no `outcomes/1`
    # at all, so the resolver answered the default single `done` and one of
    # the two events it raised was in no summary.
    #
    # sabotage: deleted `core.invoke`'s `outcomes/1` -> the resolver falls
    # back to the default `[{"done", "Done"}]` and this goes red (verified)
    test "core.invoke declares the pair it has always emitted, and classes error" do
      config = %{"invoke_type" => "myapp:authorize"}

      assert BlockType.outcomes(Invoke, config) == [{"done", "Done"}, {"error", "Error"}]
      assert BlockType.outcome_names(Invoke, config) == ["done", "error"]
      assert BlockType.failure_outcomes(Invoke, config) == ["error"]
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

  describe "a failure-classed final with its slot empty (section 2)" do
    # Section 2, the three types at once. The final is emitted whether or
    # not the slot is occupied, because the class is read off the final:
    # the only thing that raises `done.outcome.<state id>.<outcome>` - the
    # event the root catch selects - is that final's own `onentry`.
    #
    # sabotage: restored the `nil` clauses on `core.invoke`'s
    # `failure_transition/1` and `error_final/1` -> the invoke row goes
    # red and the class has no final to be read off (verified)
    test "each of the three emits it, and routes the failure straight into it", ctx do
      for {id, block} <- [
            {"blk_INV",
             Block.new("core.invoke",
               id: "blk_INV",
               config: %{"invoke_type" => "myapp:authorize"}
             )},
            {"blk_MAP", Block.new("core.map", id: "blk_MAP", config: @map_config)},
            {"blk_SUB",
             Block.new("core.subchart",
               id: "blk_SUB",
               config: %{"chart" => "bdoc_CHILD", "outcomes" => "approved"}
             )}
          ] do
        {:ok, compiled} =
          Compiler.compile(Document.new(block, id: "bdoc_ROOT"), ctx.palette, [])

        assert compiled.scxml =~
                 ~s(<transition event="error.communication.invoke" target="s_#{id}__o_error"/>),
               "#{id} did not route its failure into its own error final"

        assert compiled.scxml =~
                 ~s(<final id="s_#{id}__o_error"><onentry>) <>
                   ~s(<raise event="done.outcome.s_#{id}.error"/></onentry></final>),
               "#{id} did not emit its error final with the slot empty"

        assert {:ok, _machine} = Statifier.compile(compiled.scxml)
      end
    end
  end

  describe "the nested-to-root propagation rule (section 4)" do
    # The chunk shape the amendment is written for: a `core.sequence`
    # around one `core.invoke`, `on_error` empty. Before this bead the
    # chart could not reach a failure-classed final by any authoring.
    #
    # The transition and the final are asserted byte for byte, and the
    # reserved key and value are spelled out rather than read off this
    # package's own attribute, for this file's moduledoc reason.
    # sabotage: skipped the propagation when the collected set was
    # non-empty -> the chunk chart compiles as it did at 0.21.0 and this
    # goes red (verified)
    test "under terminate, one catch transition and one shared failed final", ctx do
      compiled = compile_chunk!(ctx, terminate: true)

      assert compiled.scxml =~
               ~s(<transition event="done.outcome.s_blk_INV.error" target="s_blk_SEQ__root_failed"/>)

      assert compiled.scxml =~
               ~s(<final id="s_blk_SEQ__root_failed"><donedata>) <>
                 @tag_param <> ~s(</donedata></final>)
    end

    # Section 4 step 3: under `:child_use` the `outcome` param rides
    # beside the reserved one, valued `error` rather than the nested
    # block's own outcome name, because `error` is the one word a parent
    # reading through `core.subchart` is guaranteed to have a route for.
    #
    # sabotage: reported the collected outcome name instead of `error` ->
    # a name from inside the child chart enters the parent's branch
    # vocabulary and this goes red (verified)
    test "under child_use, the outcome param says error", ctx do
      compiled = compile_chunk!(ctx, child_use: true)

      assert compiled.scxml =~
               ~s(<final id="s_blk_SEQ__child_failed"><donedata>) <>
                 ~s(<param expr="'error'" name="outcome"/>) <>
                 @tag_param <> ~s(</donedata></final>)
    end

    # Attribution splits: the transition is a fact about the failing
    # block, the shared final about the root (ADR-0004 decision 5 and
    # `Emit.chain/2`'s rule). The provenance map stays total over both.
    #
    # sabotage: stamped the catch transition to the root block -> "what
    # happens after the authorize step fails" stops pointing at the
    # authorize step and this goes red on the first assert (verified)
    test "the transition belongs to the failing block, the final to the root", ctx do
      compiled = compile_chunk!(ctx, terminate: true)

      {offset, _length} =
        :binary.match(
          compiled.scxml,
          ~s(<transition event="done.outcome.s_blk_INV.error" target="s_blk_SEQ__root_failed"/>)
        )

      assert {:ok, transition_owner} = Provenance.owner_at(compiled.provenance, offset)
      assert transition_owner.block_id == "blk_INV"

      assert {:ok, final_owner} =
               Provenance.owner_of_state(compiled.provenance, "s_blk_SEQ__root_failed")

      assert final_owner.block_id == "blk_SEQ"
      assert final_owner.role == "root_failed"
    end

    # The whole mechanism, run: entering the invoke's error final raises
    # the outcome event, the internal queue is FIFO so it is selected
    # before `done.state.s_blk_INV`, the root's transition exits the root
    # state, and the sequence never takes its step.
    #
    # sabotage: emitted the catch transition as internal -> the root state
    # is not left, the sibling final is never entered, and this goes red
    # on the status assert (verified)
    test "a failed call ends the run in the failed final, carrying the reserved key", ctx do
      compiled = compile_chunk!(ctx, terminate: true)

      assert {:ok, machine} = Statifier.compile(compiled.scxml)
      {machine_state, _effects} = Statifier.initialize(machine)

      {:ok, finished, effects} =
        Statifier.send_event(machine_state, "error.communication.invoke.blk_INV")

      assert finished.status == :done
      assert [done: %Statifier.Effect.Done{donedata: donedata}] = effects
      assert donedata == %{"statifier_persistence:run_status" => "failed"}
    end

    # Section 4's definition of handling is a property of the failing
    # block, not of the container above it: an occupied `on_error` is the
    # author saying what going on means, and nothing reaches the root.
    #
    # sabotage: read the slot off the container instead of the failing
    # block -> the handled document gains a catch transition and this goes
    # red (verified)
    test "an occupied on_error handles it, and nothing reaches the root", ctx do
      root =
        Block.new("core.sequence",
          id: "blk_SEQ",
          slots: %{
            "body" => [
              Block.new("core.invoke",
                id: "blk_INV",
                config: %{"invoke_type" => "myapp:authorize"},
                slots: %{"on_error" => [Block.new("core.sequence", id: "blk_ERR")]}
              )
            ]
          }
        )

      {:ok, compiled} =
        Compiler.compile(Document.new(root, id: "bdoc_CHUNK"), ctx.palette, terminate: true)

      refute compiled.scxml =~ "root_failed"
      refute compiled.scxml =~ "statifier_persistence"
    end

    # Step 2: a document with no unhandled failure-classed outcome below
    # its root compiles to the bytes it compiled to today. The corpus test
    # pins that over five documents; this pins the reason.
    #
    # sabotage: emitted the shared final for an empty collected set -> a
    # document with no failure at all gains a final it can never enter and
    # this goes red (verified)
    test "a document with no classed outcome below the root emits nothing", ctx do
      root =
        Block.new("core.sequence",
          id: "blk_SEQ",
          slots: %{
            "body" => [Block.new("core.wait", id: "blk_WAIT", config: %{"duration" => "1s"})]
          }
        )

      {:ok, compiled} =
        Compiler.compile(Document.new(root, id: "bdoc_PLAIN"), ctx.palette, terminate: true)

      refute compiled.scxml =~ "failed"
    end

    # The bead's own criterion for the other two types, and the ADR-0009
    # Note's sentence about where a nested `core.map`'s `error` now goes:
    # neither half alone reaches a nested batch or a nested child chart -
    # section 2 makes the block raise the outcome event in the empty case
    # at all, and section 4 catches it on the root.
    #
    # sabotage: filtered the collected set to `core.invoke` -> the batch
    # and the child chart stop reaching the document's ending and this
    # goes red on both rows (verified)
    test "a nested core.map and core.subchart with an empty on_error reach the root too", ctx do
      for {id, block} <- [
            {"blk_MAP", Block.new("core.map", id: "blk_MAP", config: @map_config)},
            {"blk_SUB",
             Block.new("core.subchart",
               id: "blk_SUB",
               config: %{"chart" => "bdoc_CHILD", "outcomes" => "approved"}
             )}
          ] do
        root = Block.new("core.sequence", id: "blk_SEQ", slots: %{"body" => [block]})

        {:ok, compiled} =
          Compiler.compile(Document.new(root, id: "bdoc_NESTED"), ctx.palette, terminate: true)

        assert compiled.scxml =~
                 ~s(<transition event="done.outcome.s_#{id}.error" ) <>
                   ~s(target="s_blk_SEQ__root_failed"/>),
               "#{id} below the root did not reach the shared failed final"

        assert compiled.scxml =~
                 ~s(<final id="s_blk_SEQ__root_failed"><donedata>) <>
                   @tag_param <> ~s(</donedata></final>)

        assert {:ok, _machine} = Statifier.compile(compiled.scxml)
      end
    end

    # "The root block itself is untouched": the walk starts below it, and
    # the completion finals it already emits for its own outcomes are
    # unchanged, including when its own `on_<outcome>` slot is occupied.
    # At the root the outcome *is* the document's answer.
    #
    # sabotage: started the walk at the root instead of below it -> a root
    # `core.invoke` with an empty `on_error` is caught twice, once by its
    # own `root_error` completion final and once by the shared one, and
    # this goes red (verified)
    test "the root block's own failure-classed outcome is not caught again", ctx do
      root =
        Block.new("core.invoke", id: "blk_INV", config: %{"invoke_type" => "myapp:authorize"})

      {:ok, compiled} =
        Compiler.compile(Document.new(root, id: "bdoc_ROOT"), ctx.palette, terminate: true)

      refute compiled.scxml =~ "root_failed"

      assert compiled.scxml =~
               ~s(<final id="s_blk_INV__root_error"><donedata>) <>
                 @tag_param <> ~s(</donedata></final>)
    end

    # Nothing at all outside the two options: the rule is gated exactly
    # where the root completion finals are.
    #
    # sabotage: ran the propagation outside the `cond` -> a plain compile
    # grows top-level bytes and this goes red (verified)
    test "a plain compile is untouched", ctx do
      compiled = compile_chunk!(ctx, [])

      refute compiled.scxml =~ "failed"
      refute compiled.scxml =~ "statifier_persistence"
    end

    # One shared final however many pairs there are, and one transition
    # per pair in document pre-order - which is what keeps the added bytes
    # proportional to "does this document have any unhandled failure at
    # all" rather than to the number of blocks in it.
    #
    # sabotage: minted one final per pair -> two `root_failed` ids collide
    # in the emitted bytes and this goes red on the count (verified)
    test "two unhandled failures share one final and keep document order", ctx do
      root =
        Block.new("core.sequence",
          id: "blk_SEQ",
          slots: %{
            "body" => [
              Block.new("core.invoke", id: "blk_A", config: %{"invoke_type" => "myapp:authorize"}),
              Block.new("core.invoke", id: "blk_B", config: %{"invoke_type" => "myapp:capture"})
            ]
          }
        )

      {:ok, compiled} =
        Compiler.compile(Document.new(root, id: "bdoc_TWO"), ctx.palette, terminate: true)

      assert compiled.scxml
             |> String.split(~s(<final id="s_blk_SEQ__root_failed">))
             |> length() == 2

      first =
        :binary.match(compiled.scxml, ~s(<transition event="done.outcome.s_blk_A.error"))
        |> elem(0)

      second =
        :binary.match(compiled.scxml, ~s(<transition event="done.outcome.s_blk_B.error"))
        |> elem(0)

      assert first < second
    end
  end

  # `on_error` is occupied here so the root-level assertions above read
  # the occupied shape, whose bytes ADR-0002's amendment of 2026-09-06
  # section 2 leaves exactly as they were. The empty-slot shape that
  # amendment adds is asserted in its own describe block above, and the
  # chunk-shaped document below reaches it below the root.
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

  # The reference embedder's chunk shape: a `core.sequence` around one
  # `core.invoke` whose `on_error` is empty. The amendment's whole
  # motivation is that this document could not reach a failure-classed
  # final by any authoring before this bead.
  defp compile_chunk!(ctx, opts) do
    root =
      Block.new("core.sequence",
        id: "blk_SEQ",
        slots: %{
          "body" => [
            Block.new("core.invoke", id: "blk_INV", config: %{"invoke_type" => "myapp:authorize"})
          ]
        }
      )

    {:ok, compiled} = Compiler.compile(Document.new(root, id: "bdoc_CHUNK"), ctx.palette, opts)

    compiled
  end
end
