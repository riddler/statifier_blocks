defmodule StatifierBlocks.ViewModel.OutcomeMetadataTest do
  @moduledoc """
  ADR-0005 decision 10's `slot_outcome_key` (proposed there as 10f), from the
  declaration through to the two places a consumer reads it.

  The load-bearing assertion is the negative one, and it is decision 10's
  whole reason for existing: a canvas that wants to draw an abandon
  differently from a resume gets the answer from `Slot.outcome_key` and
  `Node.outcome`, never from the fact that `core.on_event` is the type with
  an `outcome` config key. A host type declaring the same thing gets the same
  answer, and a host type declaring it wrongly gets the ordinary uniform
  rendering rather than a broken one (ADR-0002 amendment B3).
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, BlockType, Document, Palette, ViewModel}
  alias StatifierBlocks.ViewModel.{Node, Slot}

  defmodule MalformedRail do
    @moduledoc """
    A host container whose `slot_outcome_key` is a string where a map
    belongs - the shape a host gets wrong first, having read the sibling
    `slot_style` as "one value for the whole entry".
    """

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1

    @impl true
    def slots(_config),
      do: [{"body", :any, "Body"}, {"interrupts", :any, "Rules"}]

    @impl true
    def config_schema(_config), do: []

    @impl true
    def validate_config(_config), do: :ok

    @impl true
    def emit(%Block{id: id}, _context), do: {:ok, {:emitted, id}}

    @impl true
    def palette_entry,
      do: %{label: "Malformed rail", slot_outcome_key: "outcome"}
  end

  defp palette, do: Palette.new(Map.put(Palette.core_types(), "toy.rail", MalformedRail))

  defp rule(id, outcome) do
    Block.new("core.on_event",
      id: id,
      config: %{"event" => "payment.cancelled", "outcome" => outcome}
    )
  end

  defp step(id) do
    Block.new("core.wait", id: id, config: %{"duration" => "1s"})
  end

  # A card-processing group: one step in `body`, one interrupt rule in
  # `interrupts`. `type` chooses which container declares the rail.
  defp document_with(type, rule_block) do
    root =
      Block.new(type,
        id: "blk_GROUP",
        config: %{"history" => "shallow"},
        slots: %{"body" => [step("blk_STEP")], "interrupts" => [rule_block]}
      )

    Document.new(root, id: "bdoc_CARD", revision: 1)
  end

  defp build(document), do: ViewModel.build(document, palette(), [])

  defp slot(%ViewModel{root: %Node{slots: slots}}, name) do
    Enum.find(slots, fn %Slot{name: slot_name} -> slot_name == name end)
  end

  describe "BlockType.slot_outcome_key/2" do
    # Sabotage: drop the `Regex.match?/2` clause from `slot_outcome_key/2` -
    # the "refuses a key outside the outcome-name alphabet" test goes red.
    test "returns the declared key for a declared slot, and nil for any other" do
      entry = %{slot_outcome_key: %{"interrupts" => "outcome"}}

      assert BlockType.slot_outcome_key(entry, "interrupts") == "outcome"
      assert BlockType.slot_outcome_key(entry, "body") == nil
    end

    # Sabotage: replace the `is_map(declared)` guard with `declared` - a
    # string declaration reaches `Map.get/3` and raises instead of degrading.
    test "refuses a declaration that is not a map" do
      assert BlockType.slot_outcome_key(%{slot_outcome_key: "outcome"}, "interrupts") == nil
      assert BlockType.slot_outcome_key(%{slot_outcome_key: nil}, "interrupts") == nil
      assert BlockType.slot_outcome_key(%{}, "interrupts") == nil
    end

    # Sabotage: as above - `slot_outcome_key/2`'s `is_binary(key)` guard
    # removed lets an atom or a list through as a config key.
    test "refuses a key that is not a string" do
      assert BlockType.slot_outcome_key(
               %{slot_outcome_key: %{"interrupts" => :outcome}},
               "interrupts"
             ) ==
               nil

      assert BlockType.slot_outcome_key(
               %{slot_outcome_key: %{"interrupts" => ["outcome"]}},
               "interrupts"
             ) ==
               nil
    end

    # Sabotage: drop the `Regex.match?/2` clause - "Outcome", " outcome" and
    # "" all come back as keys no config will ever hold.
    test "refuses a key outside the outcome-name alphabet" do
      for key <- ["Outcome", " outcome", "outcome key", "", "9outcome", "outcome!"] do
        assert BlockType.slot_outcome_key(%{slot_outcome_key: %{"i" => key}}, "i") == nil
      end
    end

    # Sabotage: delete the catch-all `slot_outcome_key(_entry, _slot_name)`
    # clause - a non-map entry raises FunctionClauseError instead of nil.
    test "is total over a non-map entry and a non-string slot name" do
      assert BlockType.slot_outcome_key(nil, "interrupts") == nil
      assert BlockType.slot_outcome_key("entry", "interrupts") == nil
      assert BlockType.slot_outcome_key(%{slot_outcome_key: %{"i" => "outcome"}}, :i) == nil
    end
  end

  describe "BlockType.outcome_name/2" do
    # Sabotage: have `outcome_name/2` return `Map.get(config, key)` directly -
    # the refusal tests below all go red.
    test "reads the outcome the config holds at the declared key" do
      assert BlockType.outcome_name(%{"outcome" => "abandon"}, "outcome") == "abandon"
      assert BlockType.outcome_name(%{"outcome" => "resume"}, "outcome") == "resume"
    end

    # Sabotage: same mutation - a nil key becomes `Map.get(config, nil)`,
    # which is nil by luck rather than by contract, and a config that
    # happened to carry a `nil` key would leak through it.
    test "nil for no declaration, for a key the config does not hold, and for a non-map config" do
      assert BlockType.outcome_name(%{"outcome" => "abandon"}, nil) == nil
      assert BlockType.outcome_name(%{}, "outcome") == nil
      assert BlockType.outcome_name(nil, "outcome") == nil
    end

    # Sabotage: drop `outcome_name/2`'s `Regex.match?/2` check - a sentence
    # or a number reaches a consumer as though it were a routable outcome.
    test "refuses a value that is not a well-formed outcome name" do
      for value <- ["Abandon", "give up", "", 1, nil, ["abandon"]] do
        assert BlockType.outcome_name(%{"outcome" => value}, "outcome") == nil
      end
    end
  end

  describe "d10 10f: the declaration reaching the view model" do
    # Sabotage: return `{Map.get(entry.slot_style, name, :primary), nil}` from
    # `slot_presentation/2` - the declared key never reaches the slot.
    test "core.group's interrupts slot carries the declared key; body carries none" do
      vm = build(document_with("core.group", rule("blk_RULE", "abandon")))

      assert slot(vm, "interrupts").outcome_key == "outcome"
      assert slot(vm, "body").outcome_key == nil
    end

    # Sabotage: as above - `core.resumable_group` declares the same thing for
    # the same reason and loses it the same way.
    test "core.resumable_group declares the same key" do
      vm = build(document_with("core.resumable_group", rule("blk_RULE", "resume")))

      assert slot(vm, "interrupts").outcome_key == "outcome"
    end

    # Sabotage: have `build_child/3` return `build_node(block, ctx)` without
    # the `outcome` update - every rule reads as no declared outcome and the
    # canvas is back to routing abandon and resume identically.
    test "a rule in the rail carries its own outcome; a step in the body carries none" do
      vm = build(document_with("core.group", rule("blk_RULE", "abandon")))

      assert [%Node{block_id: "blk_RULE", outcome: "abandon"}] = slot(vm, "interrupts").children
      assert [%Node{block_id: "blk_STEP", outcome: nil}] = slot(vm, "body").children
    end

    # Sabotage: same mutation - `resume` and `abandon` become the same
    # picture, which is the exact loss 10f was raised about.
    test "resume and abandon are distinguishable without reading a type name" do
      abandon = build(document_with("core.group", rule("blk_RULE", "abandon")))
      resume = build(document_with("core.group", rule("blk_RULE", "resume")))

      [%Node{outcome: abandon_outcome}] = slot(abandon, "interrupts").children
      [%Node{outcome: resume_outcome}] = slot(resume, "interrupts").children

      assert abandon_outcome != resume_outcome
    end
  end

  describe "d10 10f: a malformed declaration degrades to the ordinary card" do
    # Sabotage: replace `BlockType.slot_outcome_key/2` in
    # `slot_presentation/2` with `Map.get(entry.slot_outcome_key, name)` -
    # building this document raises instead of rendering.
    test "a host declaring a string where a map belongs still renders, with no outcome" do
      vm = build(document_with("toy.rail", rule("blk_RULE", "abandon")))

      assert slot(vm, "interrupts").outcome_key == nil
      assert [%Node{block_id: "blk_RULE", outcome: nil}] = slot(vm, "interrupts").children
    end

    # Sabotage: drop `outcome_name/2`'s `Regex.match?/2` check - "Abandon"
    # reaches the node as an outcome no consumer has a route for, and the
    # `:config` finding that says the config is wrong is the only signal left.
    test "a rule whose config holds no well-formed outcome carries none, and still reports it" do
      vm = build(document_with("core.group", rule("blk_RULE", "Abandon")))

      assert [%Node{outcome: nil}] = slot(vm, "interrupts").children
      assert Enum.any?(vm.findings, &(&1.anchor == {:config, "blk_RULE", "outcome"}))
    end
  end
end
