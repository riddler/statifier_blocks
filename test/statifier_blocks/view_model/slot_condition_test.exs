defmodule StatifierBlocks.ViewModel.SlotConditionTest do
  @moduledoc """
  `ViewModel.Slot.condition`: the source text of the condition a slot is
  subject to, derived from the container's own `:expression` field keyed by
  that slot's name (`sb-5p2`, campaign 016).

  The load-bearing assertion is the same negative the rest of this directory
  carries. A canvas that wants to show what picks between a branch's arms
  reads one string off the slot; it never reads a type name, and it never
  reaches into `config["arms"][i]["cond"]` itself. A host type that keys an
  `:expression` field by one of its own slot names gets the same string in
  the same place, which is the only reason the derivation is allowed to sit
  in this module at all.

  The other half is what does NOT produce one. A chip on the canvas claims a
  condition exists, so the blank, absent and ill-typed cases have to reach
  `nil` rather than `""` - an author mid-edit already has a finding against
  the arm, and a blank chip beside it says the same thing twice and says it
  blank.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Document, Palette, ViewModel}

  defmodule Guarded do
    @moduledoc """
    A host container that guards one of its slots - `core.branch`'s shape,
    under a name no core vocabulary knows. Its `value_path` deliberately does
    NOT match its key, because that split is the whole of ADR-0002 decision
    7's 2026-08-27 amendment and a derivation that ignored the path would
    still pass against a type where the two agreed.
    """

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1

    @impl true
    def slots(_config), do: [{"when_hot", :any, "When hot"}, {"otherwise", :any, "Otherwise"}]

    @impl true
    def config_schema(_config),
      do: [
        %{
          key: "when_hot",
          type: :expression,
          label: "When hot",
          required?: true,
          default: "",
          value_path: ["guard"]
        }
      ]

    @impl true
    def validate_config(_config), do: :ok

    @impl true
    def emit(%Block{id: id}, _context), do: {:ok, {:emitted, id}}

    @impl true
    def palette_entry, do: %{label: "Guarded"}
  end

  defmodule Described do
    @moduledoc """
    A container with a `:string` field keyed by one of its slot names. It is
    what separates "the container declared a CONDITION for this slot" from
    "the container declared a field that happens to share the slot's name" -
    a derivation reading the key alone would put a description in the chip.
    """

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1

    @impl true
    def slots(_config), do: [{"body", :any, "Body"}]

    @impl true
    def config_schema(_config),
      do: [%{key: "body", type: :string, label: "Body", required?: false, default: ""}]

    @impl true
    def validate_config(_config), do: :ok

    @impl true
    def emit(%Block{id: id}, _context), do: {:ok, {:emitted, id}}

    @impl true
    def palette_entry, do: %{label: "Described"}
  end

  defp palette do
    Palette.new(
      Map.merge(Palette.core_types(), %{
        "toy.guarded" => Guarded,
        "toy.described" => Described
      })
    )
  end

  defp slots(block) do
    document = Document.new(block, id: "doc_condition")

    document
    |> ViewModel.build(palette(), [])
    |> Map.fetch!(:root)
    |> Map.fetch!(:slots)
    |> Map.new(&{&1.name, &1.condition})
  end

  defp branch(arms) do
    Block.new("core.branch", id: "blk_branch", config: %{"arms" => arms})
  end

  describe "the condition a slot is subject to" do
    # Sabotage: reading `config[decl.key]` instead of `value_at/3` through the
    # declared `value_path` - a `core.branch` arm's condition lives at
    # `["arms", i, "cond"]` and the key addresses the FIELD, so every arm
    # comes back `nil` and the canvas loses every chip.
    test "a branch arm carries its own arm's expression" do
      conditions =
        slots(
          branch([
            %{"slot" => "arm_review", "cond" => "amount > 500"},
            %{"slot" => "arm_declined", "cond" => "risk_band == 'high'"}
          ])
        )

      assert conditions["arm_review"] == "amount > 500"
      assert conditions["arm_declined"] == "risk_band == 'high'"
    end

    # `otherwise` is the arm subject to no condition, and it is declared by
    # the same `slots/1` call as the guarded ones.
    # Sabotage: defaulting a missing key to `""` rather than dropping it -
    # `otherwise` grows an empty chip that reads as a condition evaluating to
    # nothing.
    test "otherwise is subject to none" do
      conditions = slots(branch([%{"slot" => "arm_review", "cond" => "amount > 500"}]))

      assert conditions["otherwise"] == nil
    end

    # Sabotage: dropping the `source != ""` clause - an arm an author has
    # started and not written a condition for shows a blank chip beside the
    # finding that already says the condition is missing.
    test "an arm whose condition is blank, absent or not a string carries none" do
      conditions =
        slots(
          branch([
            %{"slot" => "arm_blank", "cond" => ""},
            %{"slot" => "arm_absent"},
            %{"slot" => "arm_number", "cond" => 42}
          ])
        )

      assert conditions["arm_blank"] == nil
      assert conditions["arm_absent"] == nil
      assert conditions["arm_number"] == nil
    end

    # The point of the whole derivation: a declaration, never a type name.
    # Sabotage: matching on `block.type == "core.branch"` before reading the
    # schema - a host type with the identical declaration loses its chip, and
    # ADR-0005's rule about the editor is broken one layer below the editor.
    test "a host type keying an expression by its slot name gets the same" do
      conditions =
        slots(
          Block.new("toy.guarded", id: "blk_guarded", config: %{"guard" => "temperature > 90"})
        )

      assert conditions["when_hot"] == "temperature > 90"
      assert conditions["otherwise"] == nil
    end

    # Sabotage: dropping the `&(&1.type == :expression)` filter - a `:string`
    # field that happens to share a slot's name is rendered on the canvas as
    # the condition that slot is subject to, which is a sentence the document
    # never said.
    test "a field that shares a slot's name but is not an expression is not one" do
      conditions =
        slots(Block.new("toy.described", id: "blk_described", config: %{"body" => "the body"}))

      assert conditions["body"] == nil
    end

    # An undeclared slot has no field to be keyed by, and an unresolvable
    # block has no schema at all - both reach the default rather than a crash.
    # Sabotage: making `condition` an `@enforce_keys` field - both paths build
    # a `Slot` without it and the view model stops building at all.
    test "a raw slot on an unresolvable block carries none" do
      conditions =
        slots(
          Block.new("toy.absent",
            id: "blk_absent",
            slots: %{
              "after" => [Block.new("core.wait", id: "blk_w", config: %{"duration" => "PT1S"})]
            }
          )
        )

      assert conditions["after"] == nil
    end
  end
end
