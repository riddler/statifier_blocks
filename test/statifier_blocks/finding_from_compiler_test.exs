defmodule StatifierBlocks.FindingFromCompilerTest do
  @moduledoc """
  `StatifierBlocks.Finding.from_compiler/2` and `from_compiler_all/2`
  (sb-kmk): the mechanical anchor rule, the by-rule (never by-`code`)
  source mapping, the pass-through severity, and the partition that never
  drops a finding.

  Most of this is property-style rather than example-based, in the house
  sense this repo already uses (see
  `test/statifier_blocks/edit_property_test.exs`): not StreamData, but
  deterministic exhaustive enumeration over a constructed cross-product,
  with the invariant that has to hold over every point of it written down
  before the loop. Here the cross-product is every
  `{stage, severity, block_id?, config_key?}` combination the adapter's
  rules are defined over - small and fully enumerable, so there is no
  reason to sample it when every point can be checked.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Compiler, Document, Emission, Finding, Palette, ViewModel}
  alias StatifierBlocks.Compiler.Finding, as: CompilerFinding

  @stages [:document, :resolve, :config, :structure, :emit, :chart]
  @severities [:error, :warning]
  @stage_source %{config: :config, resolve: :resolution, structure: :assignability}

  defp compiler_finding(stage, severity, block_id, config_key) do
    CompilerFinding.new(stage, {:reason_for, stage}, "message for #{stage}",
      block_id: block_id,
      config_key: config_key,
      severity: severity
    )
  end

  describe "the exhaustive cross-product property" do
    # Sabotage: made `anchor_from_compiler/1`'s `block_id: nil` clause
    # return `{:ok, {:block, nil}}` instead of refusing - red on the
    # "every block-less input refuses" assertion below, across every
    # stage/severity/config_key combination that has no block id.
    test "every combination is {:ok,_} or {:error,_}, never raises, and honors every invariant" do
      for stage <- @stages,
          severity <- @severities,
          block_id <- [nil, "blk_X"],
          config_key <- [nil, "operation"] do
        finding = compiler_finding(stage, severity, block_id, config_key)

        result = Finding.from_compiler(finding)

        case block_id do
          nil ->
            assert {:error, {:unanchorable, ^finding}} = result

          "blk_X" ->
            case result do
              {:ok, %Finding{} = adapted} ->
                assert adapted.severity == finding.severity
                assert adapted.message == finding.message
                assert same_block?(adapted.anchor, "blk_X")
                assert adapted.source in [:config, :arity, :assignability, :resolution, :lint]

                if severity != :error do
                  assert adapted.source == :lint
                end

              {:error, {:no_presentation_source, ^finding}} ->
                # Only reachable for an anchored, `:error`-severity finding
                # whose stage names no source (rule 4) - assert that is
                # exactly the case here, so a wrongly-refused combination
                # cannot slip through as "any error is fine".
                assert severity == :error
                assert stage not in Map.keys(@stage_source)
            end
        end
      end
    end

    defp same_block?({:block, id}, id), do: true
    defp same_block?({:config, id, _key}, id), do: true
    defp same_block?(_anchor, _id), do: false
  end

  describe "unknown codes map by rule, never by code" do
    # Sabotage: made `source_by_rule/1`'s stage `case` add a
    # `:undeclared_slot`-specific clause reading `finding.code` - red,
    # because an invented code that happens to share a stage with a known
    # one then diverges from it instead of mapping identically.
    test "an invented code maps identically to a known one at the same stage/severity/anchor" do
      known =
        CompilerFinding.new(:structure, :type_mismatch, "known",
          block_id: "blk_X",
          config_key: "operation",
          severity: :error,
          code: :type_mismatch
        )

      for {code, reason} <- [
            {:undeclared_slot, :undeclared_slot},
            {:slot_arity, {:slot_arity, "then", 2}},
            {:a_code_that_does_not_exist_yet, :a_code_that_does_not_exist_yet}
          ] do
        unknown =
          CompilerFinding.new(:structure, reason, "unknown",
            block_id: "blk_X",
            config_key: "operation",
            severity: :error,
            code: code
          )

        assert {:ok, %Finding{source: known_source, anchor: known_anchor}} =
                 Finding.from_compiler(known)

        assert {:ok, %Finding{source: unknown_source, anchor: unknown_anchor}} =
                 Finding.from_compiler(unknown)

        assert known_source == unknown_source
        assert known_anchor == unknown_anchor
      end
    end
  end

  describe ":info is representable without an adapter edit" do
    # Sabotage: made the severity field on the adapted struct hard-code
    # `:error` instead of passing `finding.severity` through - red, because
    # an `:info` compiler finding then adapts to `severity: :error` instead
    # of surviving the trip.
    #
    # No producer emits `:info` today (`Compiler.Finding`'s own type still
    # declares `:error | :warning`); this proves the 2026-08-29 amendment's
    # 11b ("only `:lint` may produce `:info`") is already satisfied by
    # severity pass-through composed with source rule 2, ahead of any
    # producer existing.
    test "a :info-severity finding adapts to severity: :info, source: :lint" do
      finding = %CompilerFinding{
        stage: :chart,
        block_id: "blk_X",
        config_key: nil,
        reason: :advisory,
        message: "advisory note",
        severity: :info
      }

      assert {:ok, %Finding{severity: :info, source: :lint, anchor: {:block, "blk_X"}}} =
               Finding.from_compiler(finding)
    end
  end

  describe "from_compiler_all/2 partitions and drops nothing" do
    # Sabotage: made `from_compiler_all/2` build the ok list with
    # `Enum.reduce` but forgot to reverse it before returning - red,
    # because the adapted list then comes back in the reverse of input
    # order instead of matching it.
    test "every input finding lands in exactly one of ok or refused, in order" do
      findings = [
        compiler_finding(:config, :error, "blk_A", "x"),
        compiler_finding(:document, :error, nil, nil),
        compiler_finding(:resolve, :error, "blk_B", nil),
        compiler_finding(:emit, :error, "blk_C", nil),
        compiler_finding(:structure, :warning, "blk_D", "y")
      ]

      {ok, refused} = Finding.from_compiler_all(findings)

      assert length(ok) + length(refused) == length(findings)

      assert Enum.map(ok, & &1.anchor) == [
               {:config, "blk_A", "x"},
               {:block, "blk_B"},
               # blk_D carries a config_key, so its anchor is still
               # {:config, ...} even though its :warning severity routes
               # its source to :lint by rule 2 (checked next).
               {:config, "blk_D", "y"}
             ]

      assert Enum.map(ok, & &1.source) == [:config, :resolution, :lint]

      assert Enum.map(refused, fn {f, _reason} -> f.stage end) == [:document, :emit]

      assert Enum.map(refused, fn {_f, reason} -> reason end) == [
               {:unanchorable, Enum.at(findings, 1)},
               {:no_presentation_source, Enum.at(findings, 3)}
             ]
    end
  end

  describe "end-to-end wiring: compile, adapt the invoke-type lint, feed ViewModel.build/3" do
    defmodule Charge do
      @moduledoc "A host leaf that invokes the card network with a configured operation."
      @behaviour StatifierBlocks.BlockType

      alias StatifierBlocks.Compiler.Context
      alias StatifierBlocks.Core.Emit

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
      def io(_config), do: %{kinds: [:step]}

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

    # Sabotage: made `from_compiler_all/1`'s severity pass-through hard-code
    # `severity: :error` (same mutation as the :info test, exercised here
    # through the real compile -> adapt -> ViewModel.build/3 path) - red,
    # because the routed finding then carries `severity: :error` instead of
    # the lint's actual `:warning`.
    test "the invoke-type lint routes onto the emitting block's node findings" do
      authorize = Block.new("cards.charge", id: "blk_AUTH", config: %{"operation" => "authorize"})

      document =
        Document.new(
          Block.new("core.sequence", id: "blk_ROOT", slots: %{"body" => [authorize]}),
          id: "bdoc_cards"
        )

      palette = Palette.new(Map.merge(Palette.core_types(), %{"cards.charge" => Charge}))

      assert {:ok, compiled} =
               Compiler.compile(document, palette, known_invoke_types: MapSet.new([]))

      assert [%CompilerFinding{code: :no_registered_invoke_handler}] = compiled.warnings

      {lint_findings, refused} = Finding.from_compiler_all(compiled.warnings)
      assert refused == []

      assert [%Finding{severity: :warning, source: :lint, anchor: {:block, "blk_AUTH"}}] =
               lint_findings

      view_model = ViewModel.build(document, palette, lint_findings)

      auth_node =
        Enum.find(
          view_model.root.slots |> hd() |> Map.get(:children),
          &(&1.block_id == "blk_AUTH")
        )

      assert [%Finding{severity: :warning, source: :lint}] = auth_node.findings
    end
  end
end
