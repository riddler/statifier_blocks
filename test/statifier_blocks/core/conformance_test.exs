defmodule StatifierBlocks.Core.ConformanceTest do
  @moduledoc """
  The shared behaviour conformance test the bead's first acceptance
  criterion asks for: one body of assertions, generated once per entry in
  `StatifierBlocks.Palette.core_types/0`, so a core type added later is
  covered the moment it appears in the registry and a type that drifts from
  ADR-0002 decision 10's contract fails under its own name.

  It checks the *shapes* the records fix - callback presence, the closed
  arity set (ADR-0002 decision 6), the closed field-type set (decision 7),
  ADR-0003 decision 2's `io/1` keys, ADR-0005 decision 10's
  `palette_entry/0` keys - and it checks that every callback is total for
  config `validate_config/1` rejects. What a particular type *means* is its
  own test's business, in `core_types_test.exs`.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Assignability, Block, CoreFixtures, Emission}
  alias StatifierBlocks.Compiler.Context

  @arities [:any, :at_least_one, :exactly_one, :zero_or_one]
  @io_keys [:kinds, :consumes, :produces, :slot_accepts]
  @entry_keys [:label, :group, :description, :icon, :keywords, :order, :layout, :slot_style]
  @bundle_keys [:scenarios, :events, :datasets, :expressions]

  # Config no core type should accept as-is and none may raise on.
  @junk [
    %{},
    %{"arms" => "not a list"},
    %{"arms" => [%{"slot" => "nope"}, "wat", nil]},
    %{"lanes" => 5},
    %{"lanes" => ["Bad Name", "capture", "capture"]},
    %{"duration" => 30},
    %{"history" => "sideways"},
    %{"event" => "", "outcome" => "explode"}
  ]

  for {type_name, module} <- CoreFixtures.core_modules() do
    describe "#{type_name} conformance:" do
      @module module
      @valid CoreFixtures.valid_config(module)

      # Sabotage: dropped `@behaviour StatifierBlocks.BlockType` from the
      # module - the callback set is still exported, so this went red only
      # once `behaviour_info` was asserted, which is the point of asserting it.
      test "declares the behaviour and answers the five required callbacks" do
        assert StatifierBlocks.BlockType in (@module.module_info(:attributes)[:behaviour] || [])

        assert is_integer(@module.current_version()) and @module.current_version() > 0
        assert is_list(@module.slots(@valid))
        assert is_list(@module.config_schema(@valid))
        assert @module.validate_config(@valid) == :ok
      end

      # Sabotage: changed a slot arity to `:one_or_more` - red on the arity
      # membership assert.
      test "slots/1 declares well-formed slots with closed-set arities" do
        slots = @module.slots(@valid)
        names = Enum.map(slots, fn {name, _arity, _label} -> name end)

        assert names == Enum.uniq(names)

        for {name, arity, label} <- slots do
          assert is_binary(name) and name != ""
          assert arity in @arities
          assert is_binary(label) and label != ""
        end
      end

      # Sabotage: gave a field `type: :float` - red on the field-type check.
      test "config_schema/1 declares well-formed fields with closed-set types" do
        fields = @module.config_schema(@valid)

        for field <- fields do
          assert %{key: key, type: type, label: label, required?: required, default: _} = field
          assert is_binary(key) and key != ""
          assert is_binary(label) and label != ""
          assert is_boolean(required)
          assert field_type?(type), "#{inspect(type)} is not one of the seven field types"
        end

        keys = Enum.map(fields, & &1.key)
        assert keys == Enum.uniq(keys)
      end

      # Sabotage: made `Branch.arms/1` return every arm unfiltered, so
      # `slots/1` raised on the junk arm list - red here, which is exactly
      # the stability rule ADR-0002 decision 6 states.
      test "every callback is total for config validate_config/1 rejects" do
        for config <- @junk do
          assert is_list(@module.slots(config))
          assert is_list(@module.config_schema(config))
          assert is_map(Assignability.io(@module, config))

          case CoreFixtures.validate(@module, config) do
            :ok ->
              :ok

            {:error, findings} ->
              refute Enum.empty?(findings)

              for {key, message} <- findings do
                assert is_binary(key) and is_binary(message) and message != ""
              end
          end
        end
      end

      # Sabotage: added `consumes: :record` (an atom, not a type expression)
      # to a core `io/1` - red on the produces/consumes shape assert.
      test "io/1 returns only ADR-0003 decision 2's keys, over declared slots" do
        io = Assignability.io(@module, @valid)
        declared = MapSet.new(@module.slots(@valid), fn {name, _a, _l} -> name end)

        assert Enum.all?(Map.keys(io), &(&1 in @io_keys))
        assert Enum.all?(Map.get(io, :kinds, [:step]), &is_atom/1)
        assert Map.get(io, :kinds, [:step]) != []
        assert type_expr?(Map.get(io, :consumes, :unknown))
        assert produces?(Map.get(io, :produces, :unknown), declared)

        for {slot, accepts} <- Map.get(io, :slot_accepts, %{}) do
          assert MapSet.member?(declared, slot), "#{slot} is accepted but not declared"
          assert accepts == :any or (is_list(accepts) and Enum.all?(accepts, &is_atom/1))
        end
      end

      # Sabotage: renamed a `palette_entry/0` key to `:title` - red on the
      # key-set assert, which is what keeps ADR-0005 decision 10's defaults
      # meaningful.
      test "palette_entry/0 returns only ADR-0005 decision 10's keys" do
        entry = @module.palette_entry()
        declared = MapSet.new(@module.slots(@valid), fn {name, _a, _l} -> name end)

        assert Enum.all?(Map.keys(entry), &(&1 in @entry_keys))
        assert is_binary(entry.label) and entry.label != ""
        assert Map.get(entry, :layout, :stack) in [:stack, :columns]
        assert is_list(Map.get(entry, :keywords, []))
        assert is_integer(Map.get(entry, :order, 0))

        for {slot, style} <- Map.get(entry, :slot_style, %{}) do
          assert MapSet.member?(declared, slot)
          assert style in [:primary, :secondary]
        end
      end

      # Sabotage: returned a string-keyed bundle from `Branch.fixtures/0` -
      # red on the atom-key assert. PROVISIONAL, see ADR-0002 decision 9:
      # the amendment pinning these keys (PR #13) is not accepted, so this
      # assertion is the intended target rather than a settled contract.
      test "fixtures/0, when present, is an atom-keyed bundle (PROVISIONAL)" do
        case CoreFixtures.fixtures(@module) do
          :none ->
            :ok

          {:ok, bundle} ->
            assert is_map(bundle) and bundle != %{}
            assert Enum.all?(Map.keys(bundle), &(&1 in @bundle_keys))
        end
      end

      # Sabotage: made `current_version/0` read the system clock - red here,
      # which is the only mechanical check this package has on ADR-0002
      # decision 4's purity rule.
      test "callbacks are pure: two calls agree" do
        assert @module.current_version() == @module.current_version()
        assert @module.slots(@valid) == @module.slots(@valid)
        assert @module.config_schema(@valid) == @module.config_schema(@valid)
        assert @module.validate_config(@valid) == @module.validate_config(@valid)
        assert Assignability.io(@module, @valid) == Assignability.io(@module, @valid)
        assert @module.palette_entry() == @module.palette_entry()
      end

      # Sabotage: made Core.Emit.ordered/2 return a bare Emission rather
      # than {:ok, emission} - red here for every container type, which is
      # what "answers in the contract's shape" is worth checking (verified).
      test "emit/2 answers in ADR-0004 decision 4's shape for a config this type accepts" do
        block = Block.new("core.example", id: "blk_EMIT", config: @valid)
        context = Context.new("blk_EMIT", "bdoc_CONF")

        assert {:ok, %Emission{name: name}} = @module.emit(block, context)
        assert name in ["state", "parallel"]
      end

      # `emit/2` is a pure total function of its arguments, so it has to
      # answer for a config `validate_config/1` would reject rather than
      # raising on it - the compiler's Config stage makes that arm
      # unreachable in practice, never impossible.
      #
      # Sabotage: made Core.OnEvent.emit/2 read `outcome` unchecked - red
      # here, since a raise is not an answer (verified).
      test "emit/2 answers rather than raising for a config this type rejects" do
        block = Block.new("core.example", id: "blk_EMIT", config: %{"nonsense" => true})
        context = Context.new("blk_EMIT", "bdoc_CONF")

        assert match?({:ok, %Emission{}}, @module.emit(block, context)) or
                 match?({:error, _reason}, @module.emit(block, context))
      end
    end
  end

  defp field_type?(type) when type in [:string, :integer, :boolean, :expression, :duration],
    do: true

  defp field_type?({:select, options}) when is_list(options) and options != [],
    do: Enum.all?(options, fn {value, label} -> is_binary(value) and is_binary(label) end)

  defp field_type?({:list, inner}), do: field_type?(inner)
  defp field_type?(_type), do: false

  defp type_expr?(:unknown), do: true
  defp type_expr?(expr), do: is_binary(expr) and expr != ""

  defp produces?({:passthrough, slot}, declared), do: MapSet.member?(declared, slot)
  defp produces?(produces, _declared), do: type_expr?(produces)
end
