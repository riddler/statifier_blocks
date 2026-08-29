defmodule StatifierBlocks.SlotValidationTest do
  @moduledoc """
  `StatifierBlocks.SlotValidation` in isolation: the four-arity predicate,
  absence-as-zero, undeclared slot keys, the config-parameterized shrink
  case, unresolvable-type degradation, ordering, and both worked-example
  fixtures staying clean.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, CoreFixtures, Document, DocumentFixtures, Palette, SlotValidation}

  defmodule Leaf do
    @moduledoc "A leaf block type with no slots at all."

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
    def emit(_block, _context), do: {:error, :not_implemented}
  end

  defmodule FourArities do
    @moduledoc """
    One slot per `BlockType.slot_arity/0` value, so a document can carry a
    violation (or a pass) of any of the four in one block.
    """

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1

    @impl true
    def slots(_config),
      do: [
        {"any_slot", :any, "Any"},
        {"at_least_one_slot", :at_least_one, "At least one"},
        {"exactly_one_slot", :exactly_one, "Exactly one"},
        {"zero_or_one_slot", :zero_or_one, "Zero or one"}
      ]

    @impl true
    def config_schema(_config), do: []
    @impl true
    def validate_config(_config), do: :ok
    @impl true
    def emit(_block, _context), do: {:error, :not_implemented}
  end

  defp leaf(id), do: Block.new("test.leaf", id: id)

  defp palette do
    Palette.new(%{
      "test.leaf" => Leaf,
      "test.four_arities" => FourArities,
      "core.branch" => StatifierBlocks.Core.Branch
    })
  end

  describe "arity_satisfied?/2 - the record's four rows" do
    # sabotage: change arity_satisfied?/2's `:any` clause to `false` -> this
    # assertion goes red
    test ":any is satisfied by any count, including zero" do
      assert SlotValidation.arity_satisfied?(:any, 0)
      assert SlotValidation.arity_satisfied?(:any, 1)
      assert SlotValidation.arity_satisfied?(:any, 5)
    end

    # sabotage: change arity_satisfied?/2's `:at_least_one` predicate from
    # `count >= 1` to `count >= 0` -> this assertion goes red
    test ":at_least_one is satisfied only by one or more" do
      refute SlotValidation.arity_satisfied?(:at_least_one, 0)
      assert SlotValidation.arity_satisfied?(:at_least_one, 1)
      assert SlotValidation.arity_satisfied?(:at_least_one, 5)
    end

    # sabotage: change arity_satisfied?/2's `:exactly_one` predicate from
    # `count == 1` to `count >= 1` -> this assertion goes red
    test ":exactly_one is satisfied only by exactly one" do
      refute SlotValidation.arity_satisfied?(:exactly_one, 0)
      assert SlotValidation.arity_satisfied?(:exactly_one, 1)
      refute SlotValidation.arity_satisfied?(:exactly_one, 2)
    end

    # sabotage: change arity_satisfied?/2's `:zero_or_one` predicate from
    # `count <= 1` to `count == 1` -> this assertion goes red
    test ":zero_or_one is satisfied by zero or one, not more" do
      assert SlotValidation.arity_satisfied?(:zero_or_one, 0)
      assert SlotValidation.arity_satisfied?(:zero_or_one, 1)
      refute SlotValidation.arity_satisfied?(:zero_or_one, 2)
    end
  end

  describe "absence-as-zero" do
    # sabotage: change arity_findings/2 to skip a slot key absent from
    # block.slots entirely, rather than treating it as zero children -> this
    # assertion goes red (validate/2 would return :ok)
    test ":at_least_one with an absent slot key is a finding" do
      block = Block.new("test.four_arities", id: "blk_1")
      document = Document.new(block)

      assert {:error, findings} = SlotValidation.validate(palette(), document)

      assert {:slot_arity_violated, "blk_1", "at_least_one_slot", :at_least_one, 0} in findings
    end

    # sabotage: change arity_satisfied?/2's `:zero_or_one` predicate from
    # `count <= 1` to `count == 1` -> this assertion goes red, because
    # absence (count 0) now fails the check it must pass
    test ":zero_or_one with an absent slot key is not a finding" do
      block = Block.new("test.four_arities", id: "blk_1")
      document = Document.new(block)

      assert {:error, findings} = SlotValidation.validate(palette(), document)

      refute Enum.any?(findings, fn
               {:slot_arity_violated, "blk_1", "zero_or_one_slot", _arity, _count} -> true
               _other -> false
             end)
    end
  end

  describe "undeclared slot keys" do
    # sabotage: make undeclared_findings/2 return [] unconditionally -> this
    # assertion goes red
    test "an undeclared slot key on a declared type is :undeclared_slot, carrying the child count" do
      block =
        Block.new("test.leaf",
          id: "blk_1",
          slots: %{"mystery" => [leaf("blk_2"), leaf("blk_3")]}
        )

      document = Document.new(block)

      assert SlotValidation.validate(palette(), document) ==
               {:error, [{:undeclared_slot, "blk_1", "mystery", 2}]}
    end
  end

  describe "the config-parameterized shrink case, written against core.branch" do
    # sabotage: make block_findings/2 call `module.slots(%{})` instead of
    # `module.slots(resolved.config)` -> this assertion goes red, because
    # the declaration list would no longer track the block's own config
    test "the same block validates clean with arms: [arm_a] and undeclared with arms: []" do
      arm_a_child = leaf("blk_child")

      with_arm =
        Block.new("core.branch",
          id: "blk_branch",
          config: %{"arms" => [%{"slot" => "arm_a", "cond" => "true"}]},
          slots: %{"arm_a" => [arm_a_child]}
        )

      without_arm =
        Block.new("core.branch",
          id: "blk_branch",
          config: %{"arms" => []},
          slots: %{"arm_a" => [arm_a_child]}
        )

      assert SlotValidation.validate(palette(), Document.new(with_arm)) == :ok

      assert SlotValidation.validate(palette(), Document.new(without_arm)) ==
               {:error, [{:undeclared_slot, "blk_branch", "arm_a", 1}]}
    end
  end

  describe "unresolvable block types" do
    # sabotage: make block_findings/2's {:error, _reason} clause return a
    # finding (e.g. {:undeclared_slot, block.id, "unknown", 0}) instead of
    # [] -> this assertion goes red
    test "a block whose type is not in the palette contributes nothing, even carrying slot keys" do
      block =
        Block.new("test.unregistered",
          id: "blk_1",
          slots: %{"anything" => [leaf("blk_2")]}
        )

      document = Document.new(block)

      assert SlotValidation.validate(palette(), document) == :ok
    end
  end

  describe "ordering" do
    # sabotage: swap the concatenation in block_findings/2 to
    # `undeclared_findings(...) ++ arity_findings(...)` -> this assertion
    # goes red, because the undeclared finding would then precede the
    # arity finding within blk_1
    test "within one block, arity findings precede undeclared-slot findings" do
      block =
        Block.new("test.four_arities",
          id: "blk_1",
          slots: %{
            "mystery" => [leaf("blk_2")],
            "exactly_one_slot" => [leaf("blk_3")]
          }
        )

      document = Document.new(block)

      assert {:error,
              [
                {:slot_arity_violated, "blk_1", "at_least_one_slot", :at_least_one, 0},
                {:undeclared_slot, "blk_1", "mystery", 1}
              ]} = SlotValidation.validate(palette(), document)
    end

    # sabotage: drop the `Enum.sort/1` from undeclared_findings/2 -> this
    # assertion goes red. A two- or three-key map is not enough to prove
    # this: Erlang keeps a map of 32 keys or fewer in term-sorted flat
    # storage regardless of insertion order, so `Map.keys/1` alone already
    # returns UTF-8 order for a small slots map and the mutation would
    # pass by coincidence. Past 32 keys a map switches to a hash-array
    # representation whose iteration order is not sorted, which is why
    # this test carries 40 slot keys.
    test "undeclared-slot findings are UTF-8-sorted by slot name, past the small-map threshold" do
      names = for n <- 1..40, do: "slot_#{String.pad_leading(Integer.to_string(n), 2, "0")}"

      slots = Map.new(names, &{&1, [leaf("blk_" <> &1)]})

      block = Block.new("test.leaf", id: "blk_1", slots: slots)
      document = Document.new(block)

      assert {:error, findings} = SlotValidation.validate(palette(), document)

      assert findings ==
               names
               |> Enum.sort()
               |> Enum.map(&{:undeclared_slot, "blk_1", &1, 1})
    end

    # sabotage: change validate/2 to walk the document with
    # `Enum.reverse(Document.blocks(document))` -> this assertion goes red
    test "findings from several blocks come back in Document.blocks/1 pre-order" do
      child_a =
        Block.new("test.leaf", id: "blk_child_a", slots: %{"undeclared_a" => [leaf("blk_x")]})

      child_b =
        Block.new("test.leaf", id: "blk_child_b", slots: %{"undeclared_b" => [leaf("blk_y")]})

      root =
        Block.new("test.leaf",
          id: "blk_root",
          slots: %{"body" => [child_a, child_b], "undeclared_root" => [leaf("blk_z")]}
        )

      document = Document.new(root)

      assert {:error, findings} = SlotValidation.validate(palette(), document)

      assert findings == [
               {:undeclared_slot, "blk_root", "body", 2},
               {:undeclared_slot, "blk_root", "undeclared_root", 1},
               {:undeclared_slot, "blk_child_a", "undeclared_a", 1},
               {:undeclared_slot, "blk_child_b", "undeclared_b", 1}
             ]
    end
  end

  describe "the shipped corpus stays clean" do
    # sabotage: make arity_findings/2 report a finding for `:any` slots too
    # (drop the arity_satisfied?/2 gate entirely and always report) -> this
    # assertion goes red against the worked example's real core.* blocks
    test "the ADR-0001 worked example validates :ok against CoreFixtures.palette/0" do
      document = DocumentFixtures.worked_example()

      assert SlotValidation.validate(CoreFixtures.palette(), document) == :ok
    end

    # sabotage: same mutation as above -> this assertion goes red against
    # the signup wizard's real core.* blocks
    test "the signup wizard validates :ok against CoreFixtures.palette/0" do
      document = DocumentFixtures.signup_wizard()

      assert SlotValidation.validate(CoreFixtures.palette(), document) == :ok
    end
  end

  describe ":ok, not {:error, []}" do
    # sabotage: change validate/2's empty-list clause from `:ok` to
    # `{:error, []}` -> this assertion goes red
    test "a clean document returns :ok rather than {:error, []}" do
      document = Document.new(leaf("blk_1"))

      assert SlotValidation.validate(palette(), document) == :ok
    end
  end
end
