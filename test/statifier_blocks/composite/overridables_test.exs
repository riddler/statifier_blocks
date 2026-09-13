defmodule StatifierBlocks.Composite.OverridablesTest do
  @moduledoc """
  Pins the set of callbacks a `use StatifierBlocks.Composite` module may
  override (`sb-rhb8`).

  Two `defoverridable` lines and two moduledocs used to state that set, and
  they disagreed. The set is not directly readable at runtime - `defoverridable`
  leaves no introspectable trace once the module is compiled - so it is pinned
  the way a caller experiences it: write a `def` for the callback in a
  composite, and ask which answer comes back. An **overridable** callback
  answers the module's own `def`, because the generated one was replaced. A
  callback that is **not** overridable answers the generated one, because the
  module's `def` only added a clause after it.

  The set has two sources, and the test covers both:

    * `StatifierBlocks.Composite.__using__/1`'s own `defoverridable` re-marks
      `sentence/1`, `summary/1` and `palette_entry/0`, which the macro
      redefines.
    * `StatifierBlocks.BlockType.__using__/1`'s `defoverridable` still covers
      `validate_config/1` and `migrate_config/2`, which the composite macro
      never redefines. Dropping either from `BlockType` would silently take a
      composite's ability to override it, which is what makes them worth
      pinning here rather than only in the `BlockType` tests.

  A pure test. Nothing here names LiveView, so it compiles and runs headless.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.Block

  # -- the composite that overrides every overridable --------------------

  defmodule Overrides do
    @moduledoc """
    One composite overriding all five. Each answer is distinctive enough that
    no derivation could produce it by accident.
    """

    use StatifierBlocks.Composite,
      name: "myapp.overrides_everything",
      params: [
        %{key: "invoke_type", type: :string, label: "Call", required?: true, default: ""}
      ],
      sentence: "Call {invoke_type}",
      palette_entry: %{label: "Derived label", group: "Structure", order: 40},
      version: 1

    @impl StatifierBlocks.Composite
    def subtree(params) do
      [
        Block.new("core.invoke",
          id: "call",
          config: %{"invoke_type" => params["invoke_type"], "assign_to" => "", "params" => ""}
        )
      ]
    end

    @impl StatifierBlocks.BlockType
    def sentence(_config), do: "overridden sentence"

    @impl StatifierBlocks.BlockType
    def summary(_config), do: ["overridden chip"]

    @impl StatifierBlocks.BlockType
    def palette_entry, do: %{label: "Overridden label"}

    @impl StatifierBlocks.BlockType
    def validate_config(_config),
      do: {:error, [%{path: ["invoke_type"], message: "overridden refusal"}]}

    @impl StatifierBlocks.BlockType
    def migrate_config(_from, config), do: {:ok, Map.put(config, "migrated", "overridden")}
  end

  @config %{"invoke_type" => "myapp:capture"}

  describe "the callbacks a composite may override" do
    test "sentence/1 answers the module's own def, not the rendered template" do
      assert Overrides.sentence(@config) == "overridden sentence"
    end

    test "summary/1 answers the module's own def, not the derived chips" do
      assert Overrides.summary(@config) == ["overridden chip"]
    end

    test "palette_entry/0 answers the module's own def, not the declaration" do
      assert Overrides.palette_entry() == %{label: "Overridden label"}
    end

    test "validate_config/1 answers the module's own def, not ADR-0007's :ok" do
      assert {:error, [%{message: "overridden refusal"}]} = Overrides.validate_config(@config)
    end

    test "migrate_config/2 answers the module's own def, not ADR-0007's refusal" do
      assert {:ok, %{"migrated" => "overridden"}} = Overrides.migrate_config(1, @config)
    end
  end

  # -- the callbacks a composite may NOT override -------------------------

  describe "the callbacks a composite may not override" do
    test "config_schema/1 keeps the declaration's params" do
      assert [%{key: "invoke_type"}] = shadow(:config_schema, 1, [%{}])
    end

    test "slots/1 keeps the derived pass-through slots" do
      assert shadow(:slots, 1, [%{}]) == []
    end

    test "current_version/0 keeps the declaration's version" do
      assert shadow(:current_version, 0, []) == 1
    end

    test "io/1 keeps the union over the expanded members" do
      assert %{kinds: _kinds} = shadow(:io, 1, [@config])
    end

    test "outcomes/1 keeps the derived outcome list" do
      assert [_ | _] = shadow(:outcomes, 1, [@config])
    end

    test "emit/2 keeps the generated clause, which raises" do
      block = Block.new("myapp.shadow_emit_2", id: "blk_shadow", config: @config)

      assert_raise RuntimeError, ~r/was reached for block/, fn ->
        shadow(:emit, 2, [block, %{}])
      end
    end
  end

  # Compiles a composite that writes its own `def name/arity` beside the
  # generated one and applies it. A non-overridable callback answers the
  # generated clause; `:shadowed` would mean the module's `def` won.
  #
  # The compile is quoted rather than written out because redefining a
  # function the module has already defined and not marked overridable is a
  # compiler warning, and a warning in `test/` is a gate failure.
  # `Code.with_diagnostics/1` collects it instead of printing it, which is
  # what keeps the gate green over a file whose whole point is that warning.
  defp shadow(name, arity, args) do
    module = Module.concat([__MODULE__, :"Shadow#{Macro.camelize(to_string(name))}#{arity}"])
    shadow_args = Enum.map(1..arity//1, fn i -> Macro.var(:"arg#{i}", __MODULE__) end)

    body =
      quote do
        defmodule unquote(module) do
          @moduledoc false

          use StatifierBlocks.Composite,
            name: unquote("myapp.shadow_#{name}_#{arity}"),
            params: [
              %{key: "invoke_type", type: :string, label: "Call", required?: true, default: ""}
            ],
            palette_entry: %{label: "Shadow"},
            version: 1

          @impl StatifierBlocks.Composite
          def subtree(params) do
            [
              StatifierBlocks.Block.new("core.invoke",
                id: "call",
                config: %{
                  "invoke_type" => params["invoke_type"],
                  "assign_to" => "",
                  "params" => ""
                }
              )
            ]
          end

          def unquote(name)(unquote_splicing(shadow_args)), do: :shadowed
        end
      end

    Code.with_diagnostics(fn -> Code.compile_quoted(body) end)

    apply(module, name, args)
  end
end
