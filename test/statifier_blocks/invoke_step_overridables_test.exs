defmodule StatifierBlocks.InvokeStepOverridablesTest do
  @moduledoc """
  Pins the set of callbacks a `use StatifierBlocks.InvokeStep` module may
  override.

  `defoverridable` leaves no introspectable trace once the module is
  compiled, so a name dropped from the list in
  `StatifierBlocks.InvokeStep.__using__/1` changes nothing a reader of the
  compiled module can see: the host's `def` stops replacing the injected
  clause and quietly becomes a second one after it, and the injected answer
  keeps winning. The moduledoc beside the list is prose, and prose does not
  go red.

  So the set is pinned the way a caller experiences it, which is the shape
  `StatifierBlocks.Composite.OverridablesTest` uses for the composite
  macro: one host writes its own `def` for every name on the list, each
  answering something no derivation could produce by accident, and the test
  asks which answer comes back. An **overridable** callback answers the
  host's own `def`. A callback that is not overridable answers the injected
  one.

  A pure test. Nothing here names LiveView, so it compiles and runs
  headless.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.Block
  alias StatifierBlocks.Compiler.Context

  defmodule Overrides do
    @moduledoc """
    One leaf step overriding all eight names the `use` macro re-marks.
    """

    use StatifierBlocks.InvokeStep,
      invoke_type: "myapp:overridden",
      produces: "myapp.injected",
      palette: %{label: "Injected label", group: "Card processing"}

    def invoke_type, do: "myapp:overridden_by_the_host"

    @impl StatifierBlocks.BlockType
    def config_schema(_config),
      do: [%{key: "overridden", type: :string, label: "Overridden", default: ""}]

    @impl StatifierBlocks.BlockType
    def validate_config(_config),
      do: {:error, [%{path: ["overridden"], message: "overridden refusal"}]}

    @impl StatifierBlocks.BlockType
    def io(_config), do: %{kinds: [:step], produces: "myapp.overridden"}

    @impl StatifierBlocks.BlockType
    def outcomes(_config), do: [{"overridden", "Overridden"}]

    @impl StatifierBlocks.BlockType
    def failure_outcomes(_config), do: ["overridden"]

    @impl StatifierBlocks.BlockType
    def palette_entry, do: %{label: "Overridden label"}

    @impl StatifierBlocks.BlockType
    def emit(%Block{}, _context), do: {:error, [:overridden_emission]}
  end

  @config %{"invoke_type" => "myapp:overridden"}

  # Sabotage for this whole describe block, run once: dropped `outcomes: 1`
  # from `StatifierBlocks.InvokeStep.__using__/1`'s `defoverridable` list -
  # `outcomes/1` below went red answering the injected `[{"done", "Done"},
  # {"error", "Error"}]` while the other seven stayed green (verified). That
  # is the whole drift class: one name missing from the list, one host
  # override silently stops taking effect.
  describe "the callbacks a leaf step may override" do
    test "invoke_type/0 answers the host's own def, not the declared literal" do
      assert Overrides.invoke_type() == "myapp:overridden_by_the_host"
    end

    test "config_schema/1 answers the host's own def, not label + invoke_type" do
      assert Overrides.config_schema(@config) == [
               %{key: "overridden", type: :string, label: "Overridden", default: ""}
             ]
    end

    test "validate_config/1 answers the host's own def, not the injected checks" do
      assert {:error, [%{message: "overridden refusal"}]} = Overrides.validate_config(@config)
    end

    test "io/1 answers the host's own def, not the declared :produces" do
      assert Overrides.io(@config) == %{kinds: [:step], produces: "myapp.overridden"}
    end

    test "outcomes/1 answers the host's own def, not done + error" do
      assert Overrides.outcomes(@config) == [{"overridden", "Overridden"}]
    end

    test "failure_outcomes/1 answers the host's own def, not [\"error\"]" do
      assert Overrides.failure_outcomes(@config) == ["overridden"]
    end

    test "palette_entry/0 answers the host's own def, not the merged defaults" do
      assert Overrides.palette_entry() == %{label: "Overridden label"}
    end

    test "emit/2 answers the host's own def, not the injected emission" do
      block = Block.new("myapp.overridden", id: "blk_ovr", config: @config)

      context = Context.new("blk_ovr", "doc", %{})

      assert Overrides.emit(block, context) ==
               {:error, [:overridden_emission]}
    end
  end
end
