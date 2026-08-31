defmodule StatifierBlocks.BlockTypeDefaultsTest.Bare do
  @moduledoc """
  A block type that declares nothing but its emission: the case ADR-0007
  decision 1's defaults exist for.
  """

  use StatifierBlocks.BlockType

  alias StatifierBlocks.Core.Emit

  @impl true
  def emit(_block, context), do: {:ok, Emit.final(context.state_id)}
end

defmodule StatifierBlocks.BlockTypeDefaultsTest.Overriding do
  @moduledoc "The same type with every injected default overridden."

  use StatifierBlocks.BlockType

  alias StatifierBlocks.Core.Emit

  @impl true
  def slots(_config), do: [{"body", :any, "Body"}]

  @impl true
  def config_schema(_config),
    do: [%{key: "note", type: :string, label: "Note", required?: false, default: ""}]

  @impl true
  def validate_config(_config), do: {:error, [{"note", "always refuses"}]}

  @impl true
  def current_version, do: 3

  @impl true
  def io(_config), do: %{kinds: [:step], produces: "myapp.note"}

  @impl true
  def migrate_config(_from, config), do: {:ok, Map.put(config, "migrated", true)}

  @impl true
  def emit(_block, context), do: {:ok, Emit.final(context.state_id)}
end

defmodule StatifierBlocks.BlockTypeDefaultsTest do
  @moduledoc """
  ADR-0007 decision 1: `use StatifierBlocks.BlockType` declares the
  behaviour and injects an overridable answer for every callback a type
  has nothing of its own to say about.

  The behaviour's own contract is `block_type_test.exs`'s; nothing here
  restates it. What is asserted here is that the defaults say what the
  record says they say, that overriding one wins, and that the layer
  changes nothing for a type that does not use it.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.BlockType
  alias StatifierBlocks.BlockTypeDefaultsTest.{Bare, Overriding}
  alias StatifierBlocks.Core.Raise

  describe "the injected defaults (ADR-0007 decision 1)" do
    # Sabotage: made the injected `slots/1` declare a `body` slot - a type
    # that declared no children grows one it never asked for and this goes
    # red (verified).
    test "a type that declares only emit/2 is a conforming block type" do
      assert BlockType in (Bare.module_info(:attributes)[:behaviour] || [])

      assert Bare.slots(%{}) == []
      assert Bare.config_schema(%{}) == []
      assert Bare.validate_config(%{"anything" => 1}) == :ok
      assert Bare.current_version() == 1
    end

    # Sabotage: made the injected `io/1` return `%{kinds: [:step]}` - the
    # default stops being unconstrained and starts asserting a kind the
    # type never declared, taking this red (verified).
    test "the io default is `%{}`, which is exactly what an absent io/1 means" do
      assert Bare.io(%{}) == %{}
    end

    # Sabotage: made the injected `migrate_config/2` answer `{:ok, config}`
    # - an unknown stored version is then reported as already current, and
    # this goes red (verified).
    test "the migration default refuses rather than claiming the config is current" do
      assert Bare.migrate_config(1, %{"a" => 1}) == {:error, {:no_migration_from, 1}}
      assert Bare.migrate_config(7, %{}) == {:error, {:no_migration_from, 7}}
    end

    # Sabotage: added `emit: 2` to the behaviour's `@optional_callbacks` -
    # a type that compiles nothing stops being a compile warning and this
    # goes red (verified).
    test "emit/2 is required, so it cannot be among the defaults" do
      # There is no emission a type can fall back to, so the only `emit/2`
      # a module has is the one it wrote itself. Leaving it out is a
      # compile warning rather than a silently empty chart.
      assert {:emit, 2} in BlockType.behaviour_info(:callbacks)
      refute {:emit, 2} in BlockType.behaviour_info(:optional_callbacks)
      assert function_exported?(Bare, :emit, 2)
    end
  end

  describe "overriding an injected default" do
    # Sabotage: dropped `slots: 1` from the injected `defoverridable` list -
    # `Overriding` then defines `slots/1` twice, the file stops compiling,
    # and every test here goes red (verified).
    test "every injected callback is overridable, and the override wins" do
      assert Overriding.slots(%{}) == [{"body", :any, "Body"}]
      assert [%{key: "note"}] = Overriding.config_schema(%{})
      assert Overriding.validate_config(%{}) == {:error, [{"note", "always refuses"}]}
      assert Overriding.current_version() == 3
      assert Overriding.io(%{}) == %{kinds: [:step], produces: "myapp.note"}
      assert Overriding.migrate_config(2, %{}) == {:ok, %{"migrated" => true}}
    end
  end

  describe "what the layer does not change" do
    # Sabotage: made the injected `current_version/0` answer 2 - a
    # `use`-ing type and a hand-written one stop agreeing about the version
    # a type starts at, and this goes red (verified).
    test "a hand-written type answers exactly as a use-ing one does" do
      assert Bare.slots(%{}) == Raise.slots(%{})
      assert Bare.current_version() == Raise.current_version()
    end

    # Sabotage: injected `outcomes/1` into the defaults - the resolver
    # would then read an injected list rather than amendment A1's default,
    # and a type that declares nothing stops being a one-outcome type,
    # taking this red (verified).
    test "outcomes stays amendment A1's resolver default, not an injected callback" do
      refute function_exported?(Bare, :outcomes, 1)
      assert BlockType.outcomes(Bare, %{}) == [{"done", "Done"}]
    end
  end
end
