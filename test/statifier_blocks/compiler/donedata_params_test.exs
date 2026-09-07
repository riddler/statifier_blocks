defmodule StatifierBlocks.Compiler.DonedataParamsTest do
  @moduledoc """
  ADR-0013 decision 3, which widens ADR-0004's C1: compiling with
  `child_use: true`, each top-level `<final>` carries the `outcome` param,
  then the reserved run-status param on a failure-classed outcome, then
  one `<param>` per entry of the root block type's `donedata_type/1`, in
  declaration order.

  The ordering is the decision: the declared fields go after **both**
  compiler-minted params, so a root type that declares nothing compiles to
  the bytes it compiled to before the callback existed and a
  failure-classed final does not have its two existing params reordered.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Compiler, Document, Palette}
  alias StatifierBlocks.Compiler.Context
  alias StatifierBlocks.Core.Emit

  defmodule Chunk do
    @moduledoc """
    `myapp:settlement_chunk`: the root of a child chart that settles one
    chunk of a day's captures, answers `done` or `failed_chunk`, and
    declares the counts it reports.
    """

    use StatifierBlocks.BlockType

    @impl true
    def outcomes(_config), do: [{"done", "Settled"}, {"failed_chunk", "Failed"}]

    @impl true
    def failure_outcomes(_config), do: ["failed_chunk"]

    @impl true
    def donedata_type(_config) do
      [
        %{name: "settled_count", path: "chunk.settled", type: :integer},
        %{name: "failed_count", path: "chunk.failed", type: :integer}
      ]
    end

    @impl true
    def emit(%Block{}, context) do
      with {:ok, settling} <- Context.role_id(context, "settling"),
           {:ok, done} <- Context.outcome_id(context, "done"),
           {:ok, failed} <- Context.outcome_id(context, "failed_chunk") do
        inner =
          Emit.state(settling, nil, [
            Emit.transition(event: "myapp.settled", target: done),
            Emit.transition(event: "myapp.chunk_failed", target: failed)
          ])

        {:ok,
         Emit.state(context.state_id, settling, [inner, Emit.final(done), Emit.final(failed)])}
      end
    end
  end

  defmodule Flat do
    @moduledoc """
    The same chunk, reading two roots the compile declares, so a run can
    be observed end to end rather than argued about.
    """

    use StatifierBlocks.BlockType

    @impl true
    def donedata_type(_config) do
      [
        %{name: "settled_count", path: "settled", type: :integer},
        %{name: "failed_count", path: "failed", type: :integer}
      ]
    end

    @impl true
    def emit(%Block{}, context) do
      with {:ok, done} <- Context.outcome_id(context, "done") do
        {:ok, Emit.state(context.state_id, done, [Emit.final(done)])}
      end
    end
  end

  defmodule MintsOutcome do
    @moduledoc "A host type declaring the one name C1 already mints."

    use StatifierBlocks.BlockType

    @impl true
    def donedata_type(_config), do: [%{name: "outcome", path: "settled", type: :string}]

    @impl true
    def emit(%Block{}, context) do
      with {:ok, done} <- Context.outcome_id(context, "done") do
        {:ok, Emit.state(context.state_id, done, [Emit.final(done)])}
      end
    end
  end

  defmodule MintsRunStatus do
    @moduledoc "A host type declaring the failure seam's reserved key."

    use StatifierBlocks.BlockType

    @impl true
    def donedata_type(_config),
      do: [%{name: "statifier_persistence:run_status", path: "settled", type: :string}]

    @impl true
    def emit(%Block{}, context) do
      with {:ok, done} <- Context.outcome_id(context, "done") do
        {:ok, Emit.state(context.state_id, done, [Emit.final(done)])}
      end
    end
  end

  defmodule MintsShouting do
    @moduledoc "A host type declaring a name that is not an identifier."

    use StatifierBlocks.BlockType

    @impl true
    def donedata_type(_config), do: [%{name: "Settled Count", path: "settled", type: :integer}]

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
          Map.merge(Palette.core_types(), %{
            "myapp:settlement_chunk" => Chunk,
            "myapp:flat_chunk" => Flat,
            "myapp:mints_outcome" => MintsOutcome,
            "myapp:mints_run_status" => MintsRunStatus,
            "myapp:mints_shouting" => MintsShouting
          })
        )
    }
  end

  describe "with child_use: true (decision 3)" do
    # The whole decision in one byte-exact run: the compiler's param
    # first, then the declared ones in declaration order.
    #
    # sabotage: put the declared params before the `outcome` param - the
    # completed final's bytes move for every document that declares
    # anything, and this goes red (verified)
    test "the declared fields follow the outcome param, in declaration order", ctx do
      assert compile!(ctx, "myapp:settlement_chunk", child_use: true).scxml =~
               ~s(<final id="s_blk_ROOT__child_done"><donedata>) <>
                 ~s(<param expr="'done'" name="outcome"/>) <>
                 ~s(<param expr="chunk.settled" name="settled_count"/>) <>
                 ~s(<param expr="chunk.failed" name="failed_count"/>) <>
                 ~s(</donedata></final>)
    end

    # sabotage: emitted the declared params between the two compiler-minted
    # ones - the reserved run-status param moves on every failure-classed
    # final, which is the byte a durable stepper reads, and this goes red
    # (verified)
    test "on a failure-classed outcome they follow the reserved run-status param too", ctx do
      assert compile!(ctx, "myapp:settlement_chunk", child_use: true).scxml =~
               ~s(<final id="s_blk_ROOT__child_failed_chunk"><donedata>) <>
                 ~s(<param expr="'failed_chunk'" name="outcome"/>) <>
                 ~s(<param expr="'failed'" name="statifier_persistence:run_status"/>) <>
                 ~s(<param expr="chunk.settled" name="settled_count"/>) <>
                 ~s(<param expr="chunk.failed" name="failed_count"/>) <>
                 ~s(</donedata></final>)
    end

    # The declaration produces a value at all because the path is emitted
    # as the `expr` unquoted: the child reads its own datamodel on the way
    # out, and that is what crosses the invoke boundary.
    #
    # sabotage: quoted the path the way the outcome param is quoted - the
    # child reports the path as a string rather than the value at it, and
    # this goes red (verified)
    test "the chart the engine reads back reports the declared fields", ctx do
      compiled =
        compile!(ctx, "myapp:flat_chunk",
          child_use: true,
          declare: [{"settled", "7"}, {"failed", "1"}]
        )

      {:ok, machine} = Statifier.compile(compiled.scxml)
      {machine_state, effects} = Statifier.initialize(machine)

      assert machine_state.status == :done
      assert %Statifier.Effect.Done{donedata: donedata} = Keyword.fetch!(effects, :done)
      assert donedata == %{"outcome" => "done", "settled_count" => 7, "failed_count" => 1}
    end

    # ADR-0013's byte-stability clause, asserted rather than argued: a
    # root type declaring nothing is where every `core.*` type is, and its
    # finals carry exactly the two params they carried before the callback
    # existed.
    #
    # sabotage: defaulted the resolver to one field rather than `[]` -
    # every document compiled for child use gains a param it never
    # declared and this goes red (verified)
    test "a root that declares nothing compiles to the finals it always compiled to", ctx do
      root = Block.new("core.sequence", id: "blk_SEQ")

      {:ok, compiled} =
        Compiler.compile(Document.new(root, id: "bdoc_CHILD"), ctx.palette, child_use: true)

      assert compiled.scxml =~
               ~s(<final id="s_blk_SEQ__child_done"><donedata>) <>
                 ~s(<param expr="'done'" name="outcome"/></donedata></final>)
    end
  end

  describe "without child_use" do
    # ADR-0004's 2026-08-29 note, unchanged by the widening: a `terminate`
    # final carries no `<donedata>` at all, so there is no boundary for a
    # declared field to cross.
    #
    # sabotage: computed the declared params before the `donedata?` test -
    # a `terminate` document emits fields the note says it does not, and
    # this goes red (verified)
    test "terminate finals carry no declared field", ctx do
      scxml = compile!(ctx, "myapp:settlement_chunk", terminate: true).scxml

      refute scxml =~ "settled_count"
      assert scxml =~ ~s(<final id="s_blk_ROOT__root_done"/>)
    end

    test "a plain compile emits no top-level final at all", ctx do
      scxml = compile!(ctx, "myapp:settlement_chunk", []).scxml

      refute scxml =~ "donedata"
      refute scxml =~ "settled_count"
    end
  end

  describe "the two names a declaration may not mint (decision 2)" do
    # sabotage: dropped the reserved-name refusal - the declared param
    # shadows the outcome param a parent routes on, silently, and this
    # goes red (verified)
    test "a field named outcome is refused against the root block", ctx do
      assert {:error, [finding]} = compile(ctx, "myapp:mints_outcome", child_use: true)
      assert finding.stage == :emit
      assert finding.code == :invalid_donedata_field
      assert finding.block_id == "blk_ROOT"
      assert finding.message =~ "outcome"
    end

    test "a field named for the reserved run-status key is refused too", ctx do
      assert {:error, [finding]} = compile(ctx, "myapp:mints_run_status", child_use: true)
      assert finding.code == :invalid_donedata_field
    end

    # The record fixes the name as a bare lowercase identifier, the shape
    # every other `<param>` name this package mints has.
    #
    # sabotage: accepted any binary name - the compiler mints a `<param>`
    # whose name is not one, and this goes red (verified)
    test "a name outside the identifier shape is the same refusal", ctx do
      assert {:error, [finding]} = compile(ctx, "myapp:mints_shouting", child_use: true)
      assert finding.code == :invalid_donedata_field
    end

    # It refuses where the collision can shadow something, which is the
    # compile that emits the declared params at all.
    test "the refusal is a child_use refusal, not a refusal of the type", ctx do
      assert {:ok, _compiled} = compile(ctx, "myapp:mints_outcome", terminate: true)
    end
  end

  defp compile(ctx, type, opts) do
    root = Block.new(type, id: "blk_ROOT")

    Compiler.compile(Document.new(root, id: "bdoc_CHUNK"), ctx.palette, opts)
  end

  defp compile!(ctx, type, opts) do
    {:ok, compiled} = compile(ctx, type, opts)
    compiled
  end
end
