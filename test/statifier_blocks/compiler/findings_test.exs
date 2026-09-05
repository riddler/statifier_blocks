defmodule StatifierBlocks.Compiler.FindingsTest do
  @moduledoc """
  Decisions 8, 9 and 10: the fault split, the two-registry lint, the
  Structure stage, and the ordering and shape every finding has.

  The document is a card-authorization workflow: authorize, then branch on
  the authorized amount into settle or a hold. It is small enough to read
  in one screen and has the two things these decisions need - an
  `:expression` field an author can get wrong, and an invoke type a host
  can forget to register.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Compiler, Document, Emission, Palette, Provenance}
  alias StatifierBlocks.Compiler.{Context, Finding}
  alias StatifierBlocks.Core.Emit

  defmodule Charge do
    @moduledoc "A host leaf that invokes the card network and waits for the answer."
    @behaviour StatifierBlocks.BlockType

    alias StatifierBlocks.Compiler.Context

    @impl true
    def current_version, do: 1
    @impl true
    def slots(_config), do: []

    @impl true
    def config_schema(_config),
      do: [%{key: "operation", type: :string, label: "Operation", required?: true, default: ""}]

    @impl true
    def validate_config(_config), do: :ok

    @impl true
    def io(_config), do: %{kinds: [:step], produces: "authorization"}

    @impl true
    def emit(%Block{config: config}, %Context{} = context) do
      done = Context.done_id(context)
      {:ok, running} = Context.role_id(context, "running")

      invoke =
        Emission.element("invoke", [
          {"id", running <> ".call"},
          {"type", "cards:" <> Map.get(config, "operation", "authorize")}
        ])

      inner =
        Emit.state(running, nil, [
          invoke,
          Emit.transition(event: "done.invoke." <> running <> ".call", target: done)
        ])

      {:ok, Emit.state(context.state_id, running, [inner, Emit.final(done)])}
    end
  end

  defmodule Ledger do
    @moduledoc "A host leaf that only consumes a settlement, never an authorization."
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
    def io(_config), do: %{kinds: [:step], consumes: "settlement"}

    @impl true
    def emit(_block, context) do
      done = Context.done_id(context)
      {:ok, Emit.state(context.state_id, done, [Emit.final(done)])}
    end
  end

  defmodule Reconciler do
    @moduledoc """
    A host leaf whose `<finalize>` raises an event, which SCXML 6.5.2
    forbids and statifier reports as a warning rather than an error.
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
    def emit(_block, context) do
      done = Context.done_id(context)
      {:ok, running} = Context.role_id(context, "running")

      invoke =
        Emission.element("invoke", [{"id", running <> ".call"}, {"type", "cards:reconcile"}], [
          Emission.element("finalize", [], [
            Emission.element("raise", [{"event", "cards.reconciled"}])
          ])
        ])

      inner =
        Emit.state(running, nil, [
          invoke,
          Emit.transition(event: "done.invoke." <> running <> ".call", target: done)
        ])

      {:ok, Emit.state(context.state_id, running, [inner, Emit.final(done)])}
    end
  end

  defmodule Stray do
    @moduledoc "A host leaf with a bug: it targets a state nobody emits."
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
    def emit(_block, context) do
      done = Context.done_id(context)

      inner =
        Emit.state(done <> "_wait", nil, [
          Emit.transition(event: "cards.settled", target: "s_blk_NOWHERE")
        ])

      {:ok, Emit.state(context.state_id, done <> "_wait", [inner, Emit.final(done)])}
    end
  end

  defp palette(extra \\ %{}) do
    Palette.new(
      Map.merge(
        Map.merge(Palette.core_types(), %{"cards.charge" => Charge}),
        extra
      )
    )
  end

  # authorize -> branch("amount > 5000" -> settle, otherwise -> nothing)
  defp document(condition \\ "amount > 5000") do
    settle = Block.new("cards.charge", id: "blk_SETTLE", config: %{"operation" => "settle"})

    branch =
      Block.new("core.branch",
        id: "blk_BRANCH",
        config: %{"arms" => [%{"slot" => "arm_large", "cond" => condition}]},
        slots: %{"arm_large" => [settle]}
      )

    authorize = Block.new("cards.charge", id: "blk_AUTH", config: %{"operation" => "authorize"})

    Document.new(
      Block.new("core.sequence", id: "blk_ROOT", slots: %{"body" => [authorize, branch]}),
      id: "bdoc_cards"
    )
  end

  describe "decision 8: the two-registry gap" do
    # Sabotage: made `InvokeTypes.types/1` skip `Enum.uniq/1` - red,
    # because the settle type is emitted by two blocks here and the set
    # `Compiled.invoke_types` publishes is a set.
    test "invoke types are published as data whether or not anyone asked" do
      twice =
        Document.new(
          Block.new("core.sequence",
            id: "blk_ROOT",
            slots: %{
              "body" => [
                Block.new("cards.charge", id: "blk_AUTH", config: %{"operation" => "authorize"}),
                Block.new("cards.charge", id: "blk_S1", config: %{"operation" => "settle"}),
                Block.new("cards.charge", id: "blk_S2", config: %{"operation" => "settle"})
              ]
            }
          ),
          id: "bdoc_cards"
        )

      {:ok, compiled} = Compiler.compile(twice, palette())

      assert compiled.invoke_types == ["cards:authorize", "cards:settle"]
      assert compiled.warnings == []
    end

    # Sabotage: made `Compiler.lint/2` read `:known_invoke_types` with
    # `Keyword.get/2` and a `[]` default - red, because an absent option
    # then warns about every type the chart emits.
    test "the lint is off unless the caller supplies a set" do
      {:ok, quiet} = Compiler.compile(document(), palette())
      assert quiet.warnings == []

      {:ok, linted} =
        Compiler.compile(document(), palette(),
          known_invoke_types: MapSet.new(["cards:authorize"])
        )

      assert [%Finding{} = warning] = linted.warnings
      assert warning.code == :no_registered_invoke_handler
      assert warning.block_id == "blk_SETTLE"
      assert warning.message == ~s(no handler registered for invoke type "cards:settle")
    end

    # Sabotage: made `InvokeTypes.warning/2` build the finding with
    # `severity: :error` - red on both assertions, because a missing
    # handler then refuses a publish that decision 8 says must succeed.
    test "a missing handler is a warning and the compile still succeeds" do
      assert {:ok, compiled} =
               Compiler.compile(document(), palette(), known_invoke_types: MapSet.new([]))

      assert Enum.map(compiled.warnings, & &1.severity) == [:warning, :warning]
      assert Enum.map(compiled.warnings, & &1.block_id) == ["blk_AUTH", "blk_SETTLE"]
      assert compiled.scxml != ""
    end

    # Sabotage: made `lint/2` require a MapSet by pattern-matching
    # `%MapSet{}` - red, because a host passing `Map.keys(handlers)`
    # straight through then raises instead of linting.
    test "a plain list of known types is accepted, as a host's Map.keys/1 gives it" do
      {:ok, compiled} =
        Compiler.compile(document(), palette(), known_invoke_types: ["cards:authorize"])

      assert [%Finding{block_id: "blk_SETTLE"}] = compiled.warnings
    end
  end

  describe "decision 9: whose fault is it" do
    # Sabotage: made `Finding.fault/2` return `:package` for a present
    # config key - red, because the author's own typo is then reported as
    # unfixable.
    test "a bad expression is the author's, and it names the field they typed into" do
      assert {:error, [finding]} = Compiler.compile(document("amount > > 5000"), palette())

      assert %Finding{
               stage: :chart,
               block_id: "blk_BRANCH",
               config_key: "arm_large",
               severity: :error,
               fault: :author,
               code: :expression_compile_error
             } = finding

      assert finding.message =~ "amount > > 5000"
      assert finding.path == [{"blk_ROOT", "body", 1}]
    end

    # Sabotage: made `Chart.owner/3` return the root block's owner
    # unconditionally - red, because the finding then lands on the
    # sequence instead of the block whose emission is broken.
    test "a block type's own bug is the package's, and no config key is offered" do
      broken =
        Document.new(
          Block.new("core.sequence",
            id: "blk_ROOT",
            slots: %{"body" => [Block.new("cards.hold", id: "blk_HOLD")]}
          ),
          id: "bdoc_cards"
        )

      assert {:error, [finding]} =
               Compiler.compile(broken, palette(%{"cards.hold" => Stray}))

      assert %Finding{
               stage: :chart,
               block_id: "blk_HOLD",
               config_key: nil,
               severity: :error,
               fault: :package,
               code: :unresolved_target
             } = finding
    end

    # Sabotage: made `Chart.validate/3` discard `machine.warnings` - red,
    # because upstream's own finding then never reaches an author at all.
    test "an upstream warning rides on the artifact, routed to the block that caused it" do
      noisy =
        Document.new(
          Block.new("core.sequence",
            id: "blk_ROOT",
            slots: %{"body" => [Block.new("cards.reconcile", id: "blk_REC")]}
          ),
          id: "bdoc_cards"
        )

      assert {:ok, compiled} =
               Compiler.compile(noisy, palette(%{"cards.reconcile" => Reconciler}))

      assert [%Finding{} = warning] = compiled.warnings

      assert %Finding{
               stage: :chart,
               block_id: "blk_REC",
               severity: :warning,
               fault: :package,
               code: :finalize_forbidden_content
             } = warning

      assert warning.path == [{"blk_ROOT", "body", 0}]
    end
  end

  describe "decision 10: ordered, typed, and always naming a block" do
    # Sabotage: removed the `Structure` clause from the `with` in
    # `compile/3` - red, because the misplaced ledger block then compiles
    # cleanly and the stage is not wired at all.
    test "the Structure stage runs assignability between Config and Emit" do
      misplaced =
        Document.new(
          Block.new("core.sequence",
            id: "blk_ROOT",
            slots: %{
              "body" => [
                Block.new("cards.charge", id: "blk_AUTH", config: %{"operation" => "authorize"}),
                Block.new("cards.ledger", id: "blk_LEDGER")
              ]
            }
          ),
          id: "bdoc_cards"
        )

      assert {:error, [finding]} =
               Compiler.compile(misplaced, palette(%{"cards.ledger" => Ledger}))

      assert %Finding{
               stage: :structure,
               block_id: "blk_LEDGER",
               fault: :author,
               code: :type_mismatch
             } = finding

      assert finding.path == [{"blk_ROOT", "body", 1}]
    end

    # Sabotage: made `assignability_context/1` ignore `:entry_type` and
    # always return `%{}` - red, because the entry type a caller declares
    # then never reaches the relation.
    test "the caller's entry type reaches assignability" do
      consumer =
        Document.new(
          Block.new("core.sequence",
            id: "blk_ROOT",
            slots: %{"body" => [Block.new("cards.ledger", id: "blk_LEDGER")]}
          ),
          id: "bdoc_cards"
        )

      types = palette(%{"cards.ledger" => Ledger})

      assert {:ok, _compiled} = Compiler.compile(consumer, types, entry_type: "settlement")

      assert {:error, [%Finding{code: :type_mismatch}]} =
               Compiler.compile(consumer, types, entry_type: "authorization")
    end

    # Sabotage: made `Compiler.order/2` sort by `&1.block_id` - red,
    # because the findings then come back alphabetically rather than in
    # the order the author reads their document.
    test "findings come back in document order over blocks" do
      two_bad =
        Document.new(
          Block.new("core.sequence",
            id: "blk_ROOT",
            slots: %{
              "body" => [
                Block.new("core.branch",
                  id: "blk_ZZ",
                  config: %{"arms" => [%{"slot" => "arm_a", "cond" => 7}]}
                ),
                Block.new("core.branch",
                  id: "blk_AA",
                  config: %{"arms" => [%{"slot" => "arm_b", "cond" => 7}]}
                )
              ]
            }
          ),
          id: "bdoc_cards"
        )

      assert {:error, findings} = Compiler.compile(two_bad, palette())
      assert Enum.map(findings, & &1.block_id) == ["blk_ZZ", "blk_AA"]
    end

    # Sabotage: made `locate/2` return the finding untouched - red,
    # because an editor then has no path to reveal the block with and has
    # to walk the document itself.
    test "every finding that names a block carries that block's path" do
      assert {:error, findings} = Compiler.compile(document("amount > > 5000"), palette())

      for finding <- findings do
        assert finding.block_id != nil
        assert {:ok, finding.path} == Document.fetch_path(document(), finding.block_id)
      end
    end

    # Sabotage: made `Finding.code/1` return `reason` itself rather than
    # its tag - red, because an editor switching on the code then has to
    # match the whole tuple, ids and all.
    test "code is the stable tag and reason keeps carrying the data" do
      assert {:error, [finding]} = Compiler.compile(document("amount > > 5000"), palette())

      assert finding.code == :expression_compile_error
      assert elem(finding.reason, 0) == :expression_compile_error
      assert elem(finding.reason, 2) == "amount > > 5000"
    end

    # Sabotage: made the Structure stage non-blocking in `compile/3`
    # (`_ = structure_stage(...)`) so the pipeline ran on into Chart - red,
    # because the chart-stage consequence is then reported beside its
    # structural cause, which is exactly the noise decision 10's
    # first-failing-stage rule exists to prevent.
    test "the first failing stage reports, and later stages do not run" do
      both_wrong =
        Document.new(
          Block.new("core.sequence",
            id: "blk_ROOT",
            slots: %{
              "body" => [
                Block.new("cards.charge", id: "blk_AUTH", config: %{"operation" => "authorize"}),
                Block.new("cards.ledger", id: "blk_LEDGER"),
                Block.new("cards.hold", id: "blk_HOLD")
              ]
            }
          ),
          id: "bdoc_cards"
        )

      assert {:error, findings} =
               Compiler.compile(
                 both_wrong,
                 palette(%{"cards.ledger" => Ledger, "cards.hold" => Stray})
               )

      assert Enum.map(findings, & &1.stage) |> Enum.uniq() == [:structure]
    end
  end

  describe "decision 9's last refinement: the sub-expression span" do
    # Sabotage: dropped `unescape/1` from `Chart.value_offset/3` (returned
    # the raw slice's byte size) - red, because the two `&gt;` ahead of the
    # failure then push the offset from 9 to 12 and the caret lands in the
    # middle of an entity reference rather than on the author's second `>`.
    test "the offsets are into the author's value, not into the generated bytes" do
      condition = "amount > > 5000"

      assert {:error, [finding]} = Compiler.compile(document(condition), palette())

      assert %Finding{
               block_id: "blk_BRANCH",
               config_key: "arm_large",
               code: :expression_compile_error,
               config_value_span: {start, stop}
             } = finding

      # The second `>`, which is what predicator refused - and the value it
      # is an offset into reaches the document as `amount &gt; &gt; 5000`,
      # so a generated-byte offset would be 12 here rather than 9.
      assert {start, stop} == {9, 10}
      assert binary_part(condition, start, stop - start) == ">"

      # `&` is the character the unescape has to undo last, since it is the
      # one the serializer escapes first.
      ampersand = "flags & & 1"

      assert {:error, [%Finding{config_value_span: {6, 7}}]} =
               Compiler.compile(document(ampersand), palette())

      assert binary_part(ampersand, 6, 1) == "&"
    end

    # Sabotage: made `Chart.config_value_span/3`'s no-config-key clause
    # return the owning location's whole extent rather than `nil` - red,
    # because "nothing to underline" then reads as "underline all of it"
    # for a finding whose bytes the author never typed.
    test "a finding the author cannot fix carries no span into a value they never typed" do
      broken =
        Document.new(
          Block.new("core.sequence",
            id: "blk_ROOT",
            slots: %{"body" => [Block.new("cards.hold", id: "blk_HOLD")]}
          ),
          id: "bdoc_cards"
        )

      assert {:error, [finding]} = Compiler.compile(broken, palette(%{"cards.hold" => Stray}))

      assert %Finding{fault: :package, config_key: nil, config_value_span: nil} = finding
    end

    # Sabotage: annotated `delay` with `attribute_from_config/3` in
    # `Core.Wait.emit/2` - red, because the normalised delay then claims
    # to be the author's own bytes, and an offset into it would be an
    # offset into a duration this package rewrote.
    test "an attribute whose bytes were normalised is not annotated at all" do
      waiting =
        Document.new(
          Block.new("core.sequence",
            id: "blk_ROOT",
            slots: %{
              "body" => [
                Block.new("core.wait", id: "blk_WAIT", config: %{"duration" => "30m1h"})
              ]
            }
          ),
          id: "bdoc_cards"
        )

      assert {:ok, compiled} = Compiler.compile(waiting, palette())

      # The author stored `30m1h`; the document carries the normalised
      # `1h30m`, which is the whole reason decision 9 attributes only
      # verbatim attributes.
      assert {delay_start, _length} = :binary.match(compiled.scxml, ~s(delay="))
      value_offset = delay_start + byte_size(~s(delay="))

      refute compiled.scxml =~ "30m1h"
      assert {:ok, owner} = Provenance.owner_at(compiled.provenance, value_offset)
      assert owner.block_id == "blk_WAIT"
      assert owner.config_key == nil
    end
  end
end
