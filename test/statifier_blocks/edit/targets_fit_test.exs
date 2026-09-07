defmodule StatifierBlocks.Edit.TargetsFitTest do
  @moduledoc """
  `Edit.Targets.accepted_types/4` and `probe/2`: which palette entries fit a
  target, asked once rather than once per surface.

  The defect this reader closes is a disagreement between two views of one
  question. A surface that filters a palette by building the candidate with
  `Palette.new_block/2` alone and asking `droppable_slots_for/4` gets a
  different answer, for any type whose `palette_entry/0` declares a
  `default_config` that affects what the block reads, than the canvas's own
  drag stamp does - and neither answer looks wrong from where it is written.
  `StatifierBlocks.InsertProbeFixtures` is exactly such a type, a document
  holding the slot that separates the two, and the datamodel both resolve
  through.

  A pure test. Nothing here names LiveView, so it compiles and runs headless.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.Edit.Targets

  alias StatifierBlocks.{
    Assignability,
    Block,
    Document,
    InsertProbeFixtures,
    Palette
  }

  defmodule Plain do
    @moduledoc "A leaf that declares no palette entry at all."

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1
    @impl true
    def slots(_config), do: []
    @impl true
    def config_schema(_config),
      do: [%{key: "label", type: :string, label: "Label", required?: false, default: ""}]

    @impl true
    def validate_config(_config), do: :ok
    @impl true
    def io(_config), do: %{kinds: [:step]}
    @impl true
    def emit(%Block{id: id}, _context), do: {:error, {:not_implemented, id}}
  end

  defmodule Compact do
    @moduledoc """
    A composite of the amendment's own worked shape, small enough to sit
    in a palette beside the core vocabulary: one param, one member.
    """

    use StatifierBlocks.Composite,
      name: "myapp.compact_call",
      params: [
        %{key: "invoke_type", type: :string, label: "Call", required?: true, default: ""}
      ],
      sentence: "Call {invoke_type}",
      palette_entry: %{label: "Compact call", group: "Structure", order: 40},
      version: 1

    alias StatifierBlocks.Block

    @impl StatifierBlocks.Composite
    def subtree(params) do
      [
        Block.new("core.invoke",
          id: "call",
          config: %{
            "invoke_type" => params["invoke_type"],
            "assign_to" => "",
            "params" => ""
          }
        )
      ]
    end
  end

  defp composite_palette do
    palette = InsertProbeFixtures.palette()
    %{palette | types: Map.put(palette.types, "myapp.compact_call", Compact)}
  end

  defp fixture do
    {InsertProbeFixtures.document(), InsertProbeFixtures.palette(),
     %{datamodel: InsertProbeFixtures.datamodel()}}
  end

  # Every `{parent_id, slot}` the document declares, which is what the reader
  # is asked about one at a time.
  defp targets(document, palette) do
    for block <- Document.blocks(document),
        {:ok, module, resolved} = Palette.resolve(palette, block),
        {slot, _arity, _label} <- module.slots(resolved.config),
        do: {block.id, slot}
  end

  # The filter a surface writes when it does not know about the probe: the
  # unconfigured block, and nothing else.
  defp naive_fit(document, palette, {parent_id, slot}, ctx, type) do
    case Palette.new_block(palette, type) do
      {:ok, block} ->
        {parent_id, slot} in Targets.droppable_slots_for(document, palette, block, ctx)

      :error ->
        false
    end
  end

  describe "the two views that disagreed (sb-ezat)" do
    # Sabotage: `probe/2` merging `default_config` under the schema defaults
    # rather than over them - the empty path wins, the read goes silent, and
    # the reader starts answering what the naive filter answers.
    test "the reader refuses a type at a slot the naive filter admits" do
      {document, palette, ctx} = fixture()
      target = {"blk_GRP", "body"}

      assert naive_fit(document, palette, target, ctx, "cards.settle_final"),
             "the premise: an unconfigured probe declares no read, so the slot takes it"

      refute "cards.settle_final" in Targets.accepted_types(document, palette, target, ctx),
             "and the reader, probing with the entry's default_config, does not"
    end

    # Sabotage: `accepted_types/4` filtering on `Palette.new_block/2` instead
    # of `probe/2` - the two sides stop agreeing at `blk_GRP`'s body.
    test "the reader and the drag view agree at every target of the document" do
      {document, palette, ctx} = fixture()
      types = Map.keys(palette.types)

      for target <- targets(document, palette) do
        accepted = Targets.accepted_types(document, palette, target, ctx)

        dragged =
          for type <- types,
              {:ok, block} = Targets.probe(palette, type),
              target in Targets.droppable_slots_for(document, palette, block, ctx),
              into: MapSet.new(),
              do: type

        assert accepted == dragged, "the two views disagree at #{inspect(target)}"
      end
    end

    # Sabotage: `accepted_types/4` reading the parent id and the slot in the
    # other order - the target names nothing and every set comes back empty.
    test "the target's index is not part of the question" do
      {document, palette, ctx} = fixture()

      assert Targets.accepted_types(document, palette, {"blk_ROOT", "body"}, ctx) != MapSet.new()
      assert Targets.accepted_types(document, palette, {"blk_ROOT", "nope"}, ctx) == MapSet.new()
    end
  end

  describe "probe/2" do
    # Sabotage: `probe/2` returning `new_block/2`'s block unchanged - the
    # declared path never reaches the config and this goes red.
    test "merges the entry's default_config over the schema defaults" do
      palette = InsertProbeFixtures.palette()

      assert {:ok, %Block{config: config}} = Targets.probe(palette, "cards.settle_final")
      assert config["subject"] == "cards.current_txn"

      assert {:ok, %Block{config: bare}} = Palette.new_block(palette, "cards.settle_final")
      assert bare["subject"] == ""
    end

    # Sabotage: `entry_default_config/1` dropping its `function_exported?/3`
    # check - a type with no `palette_entry/0` raises instead of probing as
    # its own schema declares.
    test "a type declaring no palette entry probes as new_block/2 built it" do
      palette = %{
        InsertProbeFixtures.palette()
        | types: Map.put(InsertProbeFixtures.palette().types, "myapp.plain", Plain)
      }

      assert {:ok, %Block{config: probed}} = Targets.probe(palette, "myapp.plain")
      assert {:ok, %Block{config: bare}} = Palette.new_block(palette, "myapp.plain")
      assert probed == bare
    end

    # Sabotage: `probe/2` answering `{:ok, block}` for an unknown type.
    test "an unknown type is :error" do
      assert Targets.probe(InsertProbeFixtures.palette(), "cards.nope") == :error
    end
  end

  describe "a composite is a type entry and fits through the same reader" do
    # Sabotage: `probe/2` asking `BlockType.default_config/1` of the module
    # rather than of its entry - a composite's derived entry is a map and
    # this stops answering a config at all.
    test "the composite's palette_entry/0 defaults build a block with no findings" do
      palette = composite_palette()

      assert {:ok, %Block{type: "myapp.compact_call", config: config}} =
               Targets.probe(palette, "myapp.compact_call")

      assert Compact.validate_config(config) == :ok
    end

    # Sabotage: `accepted_types/4` walking `palette.recipes` rather than
    # `palette.types` - the composite, which is a type entry, disappears.
    test "the reader offers it at a slot that takes a step" do
      palette = composite_palette()
      document = InsertProbeFixtures.document()
      ctx = %{datamodel: InsertProbeFixtures.datamodel()}

      assert "myapp.compact_call" in Targets.accepted_types(
               document,
               palette,
               {"blk_ROOT", "body"},
               ctx
             )
    end
  end

  describe "Assignability.context/1" do
    # Sabotage: the `nil` clause answering `%{datamodel: nil}` - the
    # environment then reads a datamodel key holding nothing.
    test "a host with no datamodel yields the empty context" do
      assert Assignability.context(%{datamodel: nil}) == %{}
    end

    # Sabotage: the second clause carrying the whole map through - every
    # other assign the caller happens to hold becomes context.
    test "a host's datamodel is the only key it carries" do
      datamodel = InsertProbeFixtures.datamodel()

      assert Assignability.context(%{datamodel: datamodel, selected_id: "blk_ROOT"}) ==
               %{datamodel: datamodel}
    end
  end
end
