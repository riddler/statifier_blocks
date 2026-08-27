defmodule StatifierBlocks.AssignabilityTest do
  @moduledoc """
  Phase 1: the four structural primitives ADR-0003 decision 5 defaults and
  decision 3 defines. `check/5`, `valid_targets/4`, `validate/3`,
  `inbound_type/4` and `assignable?/3` are later phases and are not
  exercised here.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.Assignability
  alias StatifierBlocks.BlockTypeFixtures.Minimal

  defmodule Step do
    @moduledoc "A leaf block tagged `:step`, nothing else."

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
    def io(_config), do: %{kinds: [:step]}
    @impl true
    def emit(_block, _context), do: {:error, :not_implemented}
  end

  defmodule Handler do
    @moduledoc "A leaf block tagged `:interrupt_handler`, nothing else."

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
    def io(_config), do: %{kinds: [:interrupt_handler]}
    @impl true
    def emit(_block, _context), do: {:error, :not_implemented}
  end

  defmodule Group do
    @moduledoc """
    A container with two slots: `"body"` accepts `:step` only, `"interrupts"`
    accepts `:interrupt_handler` only - the two-kind palette Phase 1's test
    exercises both directions over.
    """

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1
    @impl true
    def slots(_config), do: [{"body", :any, "Body"}, {"interrupts", :any, "Interrupts"}]
    @impl true
    def config_schema(_config), do: []
    @impl true
    def validate_config(_config), do: :ok

    @impl true
    def io(_config),
      do: %{
        kinds: [:step],
        slot_accepts: %{"body" => [:step], "interrupts" => [:interrupt_handler]}
      }

    @impl true
    def emit(_block, _context), do: {:error, :not_implemented}
  end

  defmodule Anything do
    @moduledoc "A container whose slot declares no `:slot_accepts` entry."

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1
    @impl true
    def slots(_config), do: [{"body", :any, "Body"}]
    @impl true
    def config_schema(_config), do: []
    @impl true
    def validate_config(_config), do: :ok
    @impl true
    def io(_config), do: %{kinds: [:step]}
    @impl true
    def emit(_block, _context), do: {:error, :not_implemented}
  end

  describe "the four defaults, for a module with no io/1" do
    # sabotage: change io/2's else branch from `%{}` to a non-empty map ->
    # this assertion goes red
    test "io/2 is %{} when io/1 is absent" do
      assert Assignability.io(Minimal, %{}) == %{}
    end

    # sabotage: change kinds/2's default from `[:step]` to `[]` -> this
    # assertion goes red
    test "kinds/2 defaults to [:step] when io/1 is absent" do
      assert Assignability.kinds(Minimal, %{}) == [:step]
    end

    # sabotage: change slot_accepts/3's default from `:any` to `[]` -> this
    # assertion goes red
    test "slot_accepts/3 defaults to :any when io/1 is absent" do
      assert Assignability.slot_accepts(Minimal, %{}, "body") == :any
    end

    # sabotage: n/a directly - this is the composition of the two defaults
    # above (kinds/2 [:step], slot_accepts/3 :any), and either sabotage
    # above already reds it. Recorded to pin the composed behaviour.
    test "admits?/3 admits an unconstrained child into an unconstrained slot" do
      assert Assignability.admits?({Minimal, %{}}, "body", {Minimal, %{}})
    end
  end

  describe "the :any arm" do
    # sabotage: change admits?/3's :any clause to `_ -> false` -> this
    # assertion goes red
    test "a slot with no :slot_accepts entry admits any kind" do
      assert Assignability.admits?({Anything, %{}}, "body", {Handler, %{}})
      assert Assignability.admits?({Anything, %{}}, "body", {Step, %{}})
    end
  end

  describe "the intersection arm" do
    # sabotage: change admits?/3's intersection clause from `Enum.any?` to
    # always `true` -> this assertion goes red
    test "a step is refused by a slot that accepts only interrupt handlers" do
      refute Assignability.admits?({Group, %{}}, "interrupts", {Step, %{}})
    end

    # sabotage: change admits?/3's intersection clause from `Enum.any?` to
    # always `false` -> this assertion goes red
    test "an interrupt handler is admitted by a slot that accepts it" do
      assert Assignability.admits?({Group, %{}}, "interrupts", {Handler, %{}})
    end
  end

  describe "both directions of a two-kind palette" do
    # sabotage: swap the "body" and "interrupts" entries in Group.io/1's
    # slot_accepts map -> both assertions below go red, each in the
    # direction that now admits the wrong kind
    test "a step goes in body and not interrupts; a handler goes the other way" do
      assert Assignability.admits?({Group, %{}}, "body", {Step, %{}})
      refute Assignability.admits?({Group, %{}}, "body", {Handler, %{}})
      assert Assignability.admits?({Group, %{}}, "interrupts", {Handler, %{}})
      refute Assignability.admits?({Group, %{}}, "interrupts", {Step, %{}})
    end
  end
end
