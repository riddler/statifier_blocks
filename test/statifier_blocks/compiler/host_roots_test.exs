defmodule StatifierBlocks.Compiler.HostRootsTest do
  @moduledoc """
  The `:declare` compile option: a host declaring `<data>` roots for a root
  document (ADR-0004's 2026-08-29 host-declared-roots note).
  """

  use ExUnit.Case, async: true

  alias Statifier.Effect.Trace.EventDequeued

  alias StatifierBlocks.{
    Block,
    Compiler,
    CoreFixtures,
    Document,
    DocumentFixtures,
    Palette,
    Provenance
  }

  alias StatifierBlocks.Compiler.{DeclaredRoots, Finding, StateId}
  alias StatifierBlocks.Core.Config

  describe "the emitted <datamodel>" do
    # sabotage: dropped the `prepend/2` call from `emit_stage/3` -> the
    # host's roots never reach the hoist, no `<datamodel>` is emitted and
    # this goes red on the whole element (verified; it takes eight of the
    # tests below with it)
    test "holds the host's roots, in the order the option lists them" do
      assert scxml(declare: [{"targets", nil}, {"parked", "false"}]) =~
               ~s(<datamodel><data id="targets"/><data expr="false" id="parked"/></datamodel>)
    end

    # sabotage: reversed the option list in `DeclaredRoots.declarations/1`
    # (returned the accumulator without the final `Enum.reverse/1`) -> the
    # roots came out back to front and this goes red (verified)
    test "keeps declaration order rather than sorting the ids" do
      assert scxml(declare: [{"zeta", nil}, {"alpha", nil}]) =~
               ~s(<datamodel><data id="zeta"/><data id="alpha"/></datamodel>)
    end

    # sabotage: made `prepend/2` append rather than prepend
    # (`children ++ roots`) -> the loop's own roots came first and this
    # goes red (verified)
    test "leads the block-declared roots a foreach contributes" do
      scxml = loop_scxml(declare: [{"steps", "['email', 'profile']"}])

      assert scxml =~
               ~s(<datamodel><data expr="['email', 'profile']" id="steps"/>) <>
                 ~s(<data expr="0" id="s_blk_F__i"/><data id="s_blk_F__items"/>) <>
                 ~s(<data id="step"/></datamodel>)
    end

    # sabotage: replaced `declarations(nil)`'s `{:ok, []}` with a one-root
    # list -> a document declaring nothing grew a `<datamodel>` and this
    # goes red on both halves (verified)
    test "an absent or empty option emits no <datamodel> at all" do
      refute scxml([]) =~ "<datamodel>"
      refute scxml(declare: []) =~ "<datamodel>"
    end
  end

  describe "byte identity for a document that declares nothing" do
    # sabotage: gave `declarations(nil)` one root of its own -> a
    # document compiled with no option grew a `<datamodel>` the same
    # document compiled with `declare: []` does not have, and this goes
    # red on both fixtures (verified)
    test "the option absent and the option empty compile to identical bytes" do
      # Both shipped fixtures declare their own roots since sb-vjeg, and
      # this describe is about a document that declares *nothing at all* -
      # so the document key comes off before the comparison, leaving the
      # `:declare` option as the only surface in play, which is what this
      # file is about.
      for declared <- [DocumentFixtures.worked_example(), DocumentFixtures.signup_wizard()] do
        document = %{declared | datamodel: []}
        {:ok, plain} = Compiler.compile(document, CoreFixtures.palette())
        {:ok, empty} = Compiler.compile(document, CoreFixtures.palette(), declare: [])

        assert plain.scxml == empty.scxml
        refute plain.scxml =~ "<datamodel>"
      end
    end
  end

  describe "provenance (decision 5)" do
    setup do
      {:ok, compiled} = compile(declare: [{"targets", nil}])
      %{compiled: compiled}
    end

    # sabotage: dropped the `Enum.map/2` that stamps the owner in
    # `host_roots/2`, leaving `owner: nil` -> the serializer records no
    # span for the root's bytes, the map stops being total and this goes
    # red on `owner_at/2` (verified)
    test "a host-declared root's bytes are owned by the root block", %{compiled: compiled} do
      offset = :binary.match(compiled.scxml, ~s(<data id="targets"/>)) |> elem(0)

      assert {:ok, owner} = Provenance.owner_at(compiled.provenance, offset)
      assert owner.block_id == "blk_ROOT"
      assert owner.role == ":declare"
      assert owner.config_key == nil
    end

    # sabotage: spelled `@host_role` `"declare"` -> `StateId.role?/1`
    # accepts it, so the name the compile option mints stops being
    # distinguishable from one a block mints out of a state id, and this
    # goes red (verified)
    test "the role is not one a block could mint from a state id", %{compiled: compiled} do
      offset = :binary.match(compiled.scxml, ~s(<data id="targets"/>)) |> elem(0)
      {:ok, owner} = Provenance.owner_at(compiled.provenance, offset)

      refute StateId.role?(owner.role)
    end

    # sabotage: stamped the `<datamodel>` wrapper with `@host_role` too
    # -> the wrapper stopped reading as scaffolding the root block owns
    # for `<scxml>`'s reason and this goes red (verified)
    test "the wrapper keeps the root block with no role", %{compiled: compiled} do
      offset = :binary.match(compiled.scxml, "<datamodel>") |> elem(0)

      assert {:ok, %{block_id: "blk_ROOT", role: nil}} =
               Provenance.owner_at(compiled.provenance, offset)
    end

    # sabotage: relaxed `Serializer.record_state/2`'s `unstate_id/1`
    # guard to `is_binary(id)` -> a host root's id landed in the state map
    # a running configuration is looked up in, and this goes red
    # (verified)
    test "a host root's id is not a generated state id", %{compiled: compiled} do
      assert Provenance.owner_of_state(compiled.provenance, "targets") == :error
    end
  end

  describe "refusing the option itself" do
    # sabotage: dropped the `Regex.match?(@identifier, id)` clause from
    # `verdict/2` -> every one of these compiled and this goes red
    # (verified)
    test "an id that is not a bare lowercase identifier is refused" do
      for id <- ["Targets", "my.targets", "my targets", "_targets", "", "1st"] do
        assert {:error, [%Finding{} = finding]} = compile(declare: [{id, nil}])
        assert finding.stage == :emit
        assert finding.code == :invalid_declaration
        assert finding.block_id == "blk_ROOT"
        assert finding.fault == :package
      end
    end

    # The rule is copied rather than shared (see `DeclaredRoots`), so it
    # is asserted against the original rather than trusted.
    # sabotage: loosened `DeclaredRoots`'s `@identifier` to
    # `~r/\A[a-z_][a-z0-9_]*\z/` -> the option accepted `_targets`, which
    # `core.invoke` refuses for `assign_to`, and this goes red (verified)
    test "the option's id rule is core.invoke's assign_to rule" do
      for id <- ["targets", "a1", "a_b", "Targets", "my.targets", "_targets", "1st", ""] do
        accepted? = match?({:ok, [_root]}, DeclaredRoots.declarations([{id, nil}]))

        assert accepted? == Config.identifier?(id), id
      end
    end

    # sabotage: widened `verdict/2`'s head to `{id, expr}` with no guard
    # on `expr` -> a non-string expr reached `Emission.element/3` and this
    # goes red (verified)
    test "an entry that is not a well-formed {id, expr} pair is refused" do
      for entry <- ["targets", {"targets"}, {"targets", ""}, {"targets", 1}, {:targets, nil}] do
        assert {:error, [%Finding{code: :invalid_declaration}]} = compile(declare: [entry])
      end
    end

    # sabotage: returned `{:ok, []}` from `declarations/1`'s catch-all
    # clause instead of a finding -> a `:declare` value that is not a list
    # compiled silently and this goes red (verified)
    test "an option value that is not a list is refused" do
      assert {:error, [%Finding{code: :invalid_declaration}]} =
               compile(declare: %{"targets" => nil})
    end

    # sabotage: dropped the `MapSet.member?(seen, id)` clause from
    # `verdict/2` -> the second declaration silently won and this goes red
    # (verified)
    test "an id the option declares twice is refused" do
      assert {:error, [%Finding{} = finding]} =
               compile(declare: [{"targets", nil}, {"targets", "'a'"}])

      assert finding.code == :duplicate_declaration
      assert finding.reason == {:duplicate_declaration, "targets"}
      assert finding.block_id == "blk_ROOT"
    end

    # sabotage: returned only the first refusal from `declarations/1` ->
    # a host fixing its call saw one bad entry at a time and this goes red
    # (verified)
    test "every bad entry is reported, not just the first" do
      assert {:error, [_first, _second, _third]} =
               compile(declare: [{"Targets", nil}, {"parked", 1}, {"ok", nil}, {"ok", nil}])
    end
  end

  describe "collision with a block-declared root (F6)" do
    # sabotage: made `prepend/2` append -> the loop's own root entered
    # the walk's scope first, so the collision was reported against the
    # *host's* declaration instead, losing the `config_key` that makes it
    # the author's, and this goes red (verified)
    test "a loop binding the host's name is :duplicate_binding against the loop" do
      assert {:error, [%Finding{} = finding]} = loop_compile(declare: [{"step", nil}])

      assert finding.stage == :emit
      assert finding.code == :duplicate_binding
      assert finding.reason == {:duplicate_binding, "blk_F", "step"}
      assert finding.block_id == "blk_F"
      assert finding.config_key == "item_as"
      assert finding.fault == :author
    end

    # sabotage: dropped the `prepend/2` call from `emit_stage/3` -> a
    # host root a loop does not bind never reached the chart at all, and
    # this goes red (verified)
    test "a host root a loop does not bind is not a collision" do
      assert loop_scxml(declare: [{"steps", "[]"}]) =~ ~s(<data expr="[]" id="steps"/>)
    end
  end

  describe "the sensitive-path refusal still runs (option :datamodel)" do
    # sabotage: dropped the `prepend/2` call from `emit_stage/3` -> the
    # root never reached the emission the pass walks, the leak compiled
    # clean, and this goes red (verified)
    test "a host-declared root's expr is a datamodel position like any other" do
      assert {:error, [%Finding{} = finding]} =
               compile(
                 declare: [{"leak", "secret.token"}],
                 datamodel: %{sensitive: ["secret.token"]}
               )

      assert finding.code == :sensitive_path_read
      assert finding.reason == {:sensitive_path_read, "secret.token"}
      assert finding.block_id == "blk_ROOT"
      assert finding.config_key == nil
      assert finding.fault == :package
    end

    # sabotage: dropped the `prepend/2` call from `emit_stage/3` -> the
    # root is not in the chart to be clean about, and this goes red on the
    # emitted bytes (verified)
    test "a root that reads nothing sensitive compiles, and is still emitted" do
      assert {:ok, compiled} =
               compile(
                 declare: [{"targets", nil}],
                 datamodel: %{sensitive: ["secret.token"]}
               )

      assert compiled.scxml =~ ~s(<datamodel><data id="targets"/></datamodel>)
    end
  end

  describe "the runtime, through the resolved statifier" do
    # THE POINT OF THE BEAD. A host-declared location is assigned to and
    # read in a guard, and neither raises.
    # sabotage: dropped the `prepend/2` call from `emit_stage/3` -> the
    # roots are gone, the assign and the guard both raise, and this goes
    # red on the `error.execution` half (verified)
    test "an assign to a host-declared location and a guard reading it both run clean" do
      {:ok, compiled} = compile(declare: [{"targets", nil}, {"parked", "false"}])

      refute "error.execution" in dequeued(compiled.scxml)
      assert "done.outcome.s_blk_P.done" in dequeued(compiled.scxml)
    end

    # THE GAP, PINNED. The same document without the declaration is what a
    # production host hit: two `error.execution` raises, and the guarded
    # arm never runs.
    # sabotage: none possible from `lib/` - this asserts the engine
    # behaviour the option exists to work around, and it goes red the day
    # the compiler starts declaring these roots on its own (which is the
    # regression it is here to catch)
    test "the same document without the declaration raises error.execution" do
      {:ok, compiled} = compile([])
      events = dequeued(compiled.scxml)

      assert Enum.count(events, &(&1 == "error.execution")) == 2
      refute "done.outcome.s_blk_P.done" in events
    end
  end

  # -- the plumbing ----------------------------------------------------------

  # A sequence that assigns a root and then guards on it: the two
  # positions a host's seeded value has to reach.
  defp document do
    Document.new(
      Block.new("core.sequence",
        id: "blk_ROOT",
        slots: %{
          "body" => [
            Block.new("core.assign",
              id: "blk_SET",
              config: %{"path" => "targets", "value" => "'a'"}
            ),
            Block.new("core.branch",
              id: "blk_B",
              config: %{"arms" => [%{"slot" => "arm_seen", "cond" => "targets == 'a'"}]},
              slots: %{
                "arm_seen" => [
                  Block.new("core.assign",
                    id: "blk_P",
                    config: %{"path" => "parked", "value" => "true"}
                  )
                ],
                "otherwise" => []
              }
            )
          ]
        }
      ),
      id: "bdoc_HOST"
    )
  end

  # A loop over a list the host declares, which is the shape the foreach
  # amendment left with nowhere to put the source list.
  defp loop_document do
    Document.new(
      Block.new("core.foreach",
        id: "blk_F",
        config: %{"items" => "steps", "item_as" => "step"},
        slots: %{
          "body" => [
            Block.new("core.raise", id: "blk_R", config: %{"event" => "seen"})
          ]
        }
      ),
      id: "bdoc_LOOP"
    )
  end

  defp compile(opts), do: Compiler.compile(document(), Palette.new(Palette.core_types()), opts)

  defp loop_compile(opts),
    do: Compiler.compile(loop_document(), Palette.new(Palette.core_types()), opts)

  defp scxml(opts) do
    {:ok, compiled} = compile(opts)
    compiled.scxml
  end

  defp loop_scxml(opts) do
    {:ok, compiled} = loop_compile(opts)
    compiled.scxml
  end

  # The internal events one initialization dequeues, in order. Platform
  # errors are internal events rather than effects, so the trace is where
  # `error.execution` is observable without adding a catching transition
  # the document under test does not otherwise have.
  defp dequeued(scxml) do
    {:ok, machine} = Statifier.compile(scxml)
    {_machine_state, effects} = Statifier.initialize(machine, trace: true)

    for {:trace, %EventDequeued{event: event}} <- effects, do: event.name
  end
end
