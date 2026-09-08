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
    CardProcessingFixtures,
    Document,
    InsertProbeFixtures,
    Palette
  }

  defmodule Counted do
    @moduledoc """
    A leaf that counts the times its `io/1` is asked, so a test can say how
    many `Assignability.check/5` calls a reader made about it.

    `check/5` consults a candidate's `io/1` a fixed number of times - kind
    admission, then the read signatures - and nothing else in this module's
    path does, so the count divided by that fixture is the number of checks.
    """

    @behaviour StatifierBlocks.BlockType

    @counter :sb_h5xq_io_calls

    @doc "Zero the counter and answer what it held."
    def reset do
      Process.put(@counter, 0)
      :ok
    end

    @doc "The count since the last `reset/0`."
    def calls, do: Process.get(@counter, 0)

    @impl true
    def current_version, do: 1
    @impl true
    def slots(_config), do: []
    @impl true
    def config_schema(_config), do: []
    @impl true
    def validate_config(_config), do: :ok

    @impl true
    def io(_config) do
      Process.put(@counter, Process.get(@counter, 0) + 1)
      %{kinds: [:step]}
    end

    @impl true
    def emit(%Block{id: id}, _context), do: {:error, {:not_implemented, id}}
  end

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

  # Four card-processing documents, including one whose only step already
  # fails its own read - the shape that separates a check at a slot's first
  # gap from a check at its append gap.
  defp card_documents do
    open = CardProcessingFixtures.open()

    [
      {"an empty root", CardProcessingFixtures.document([])},
      {"the entry block alone", CardProcessingFixtures.document([open])},
      {"entry and settle", CardProcessingFixtures.document([open, settle()])},
      {"settle with no entry", CardProcessingFixtures.document([settle()])},
      {"a branch beside the entry",
       CardProcessingFixtures.document([
         open,
         CardProcessingFixtures.branch("blk_BR", [{"a", []}, {"b", [settle("blk_S2")]}])
       ])}
    ]
  end

  defp settle(id \\ "blk_S"), do: CardProcessingFixtures.settle(id)

  # A document whose `core.invoke` holds `children` in its `zero_or_one`
  # `on_error` slot - rule 3's shape.
  defp invoke_document(children) do
    call =
      Block.new("core.invoke",
        id: "blk_CALL",
        config: %{"invoke_type" => "myapp:authorize", "assign_to" => "", "params" => ""},
        slots: %{"on_error" => children}
      )

    CardProcessingFixtures.document([CardProcessingFixtures.open(), call])
  end

  # The card palette with three names for one counting type, so a candidate
  # list of three is three candidates rather than three copies of one.
  defp counted_palette do
    palette = CardProcessingFixtures.palette()

    types =
      Enum.reduce(["myapp.counted_a", "myapp.counted_b", "myapp.counted_c"], palette.types, fn
        name, acc -> Map.put(acc, name, Counted)
      end)

    %{palette | types: types}
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

  describe "admits_at?/5 and accepted_types_at/5, the per-target pair" do
    # Sabotage: `admits_at?/5` dropping its `append_gap/3` guard and checking
    # at index 0 - the settle-only document's whole palette goes dark,
    # because the block already first in the slot fails its own read.
    test "the pair and the sweep answer the same set at every target of the card fixtures" do
      palette = CardProcessingFixtures.palette()
      ctx = CardProcessingFixtures.ctx()

      for {label, document} <- card_documents(),
          target <- targets(document, palette) do
        sweep = Targets.accepted_types(document, palette, target, ctx)

        assert Targets.accepted_types_at(document, palette, target, nil, ctx) == sweep,
               "#{label}: the per-target reader and the sweep disagree at #{inspect(target)}"

        for type <- Map.keys(palette.types) do
          assert Targets.admits_at?(document, palette, target, type, ctx) ==
                   MapSet.member?(sweep, type),
                 "#{label}: #{type} at #{inspect(target)}"
        end
      end
    end

    # Sabotage: `accepted_types_at/5` ignoring `candidates` and walking
    # `palette.types` - the shortlist stops bounding the answer.
    test "a candidate list is paid for instead of the palette" do
      palette = CardProcessingFixtures.palette()
      ctx = CardProcessingFixtures.ctx()
      document = CardProcessingFixtures.document([CardProcessingFixtures.open()])
      target = {"blk_ROOT", "body"}

      shortlist = ["cards.settle", "core.assign"]

      assert Targets.accepted_types_at(document, palette, target, shortlist, ctx) ==
               MapSet.intersection(
                 Targets.accepted_types(document, palette, target, ctx),
                 MapSet.new(shortlist)
               )

      assert Targets.accepted_types_at(document, palette, target, [], ctx) == MapSet.new()

      assert Targets.accepted_types_at(document, palette, target, ["cards.nope"], ctx) ==
               MapSet.new()
    end

    # Sabotage: `admits_at?/5` skipping the `declares_slot?/3` clause - a
    # slot the parent never declared starts answering the check's verdict.
    test "an unknown type, a parent that names nothing and an undeclared slot are all false" do
      palette = CardProcessingFixtures.palette()
      ctx = CardProcessingFixtures.ctx()
      document = CardProcessingFixtures.document([CardProcessingFixtures.open()])

      refute Targets.admits_at?(document, palette, {"blk_ROOT", "body"}, "cards.nope", ctx)
      refute Targets.admits_at?(document, palette, {"blk_NOPE", "body"}, "cards.settle", ctx)
      refute Targets.admits_at?(document, palette, {"blk_ROOT", "nope"}, "cards.settle", ctx)
    end

    # Sabotage: `append_gap/3` dropping its `full?/4` clause - the occupied
    # `zero_or_one` slot starts admitting a second child.
    test "rule 3 refuses an occupied zero_or_one slot" do
      palette = CardProcessingFixtures.palette()
      ctx = CardProcessingFixtures.ctx()

      empty = invoke_document([])
      occupied = invoke_document([CardProcessingFixtures.assign("blk_IN", "cards.settlement")])
      target = {"blk_CALL", "on_error"}

      assert Targets.admits_at?(empty, palette, target, "core.assign", ctx)
      refute Targets.admits_at?(occupied, palette, target, "core.assign", ctx)
    end

    # Sabotage: `accepted_types_at/5` calling `accepted_types/4` and taking
    # the intersection - the answer is unchanged and the call count is not.
    test "one check/5 per candidate, where the sweep pays one per gap of the document" do
      palette = counted_palette()
      ctx = CardProcessingFixtures.ctx()

      document =
        CardProcessingFixtures.document([
          CardProcessingFixtures.open(),
          CardProcessingFixtures.settle("blk_S"),
          CardProcessingFixtures.assign("blk_A", "cards.settlement")
        ])

      target = {"blk_ROOT", "body"}
      {:ok, probe} = Targets.probe(palette, "myapp.counted_a")

      Counted.reset()
      Assignability.check(palette, document, {"blk_ROOT", "body", 3}, probe, ctx)
      per_check = Counted.calls()
      assert per_check > 0, "the premise: check/5 asks the candidate's io/1"

      Counted.reset()
      assert Targets.admits_at?(document, palette, target, "myapp.counted_a", ctx)
      assert Counted.calls() == per_check

      Counted.reset()

      assert Targets.accepted_types_at(
               document,
               palette,
               target,
               ["myapp.counted_a", "myapp.counted_b", "myapp.counted_c"],
               ctx
             ) == MapSet.new(["myapp.counted_a", "myapp.counted_b", "myapp.counted_c"])

      assert Counted.calls() == 3 * per_check

      Counted.reset()
      Targets.accepted_types(document, palette, target, ctx)
      sweep_calls = Counted.calls()

      assert sweep_calls > 3 * per_check,
             "the sweep asks the whole document per candidate; #{sweep_calls} is not more than one check each"
    end

    # Sabotage: `admits_at?/5` building the candidate with
    # `Palette.new_block/2` instead of `probe/2` - the declared path never
    # reaches the config, the read goes silent, and the slot admits it.
    test "the probe's default_config decides the answer, and the sweep's gap 0 does not" do
      document = InsertProbeFixtures.document()
      palette = InsertProbeFixtures.palette()
      ctx = %{datamodel: InsertProbeFixtures.datamodel()}

      refute Targets.admits_at?(
               document,
               palette,
               {"blk_ROOT", "body"},
               "cards.settle_final",
               ctx
             ),
             "appending the configured step after the entry block reads a record that is not Settled"

      assert naive_fit(document, palette, {"blk_ROOT", "body"}, ctx, "cards.settle_final"),
             "the premise: the unconfigured block declares no read and is admitted"

      assert "cards.settle_final" in Targets.accepted_types(
               document,
               palette,
               {"blk_ROOT", "body"},
               ctx
             ),
             "and the sweep accepts the slot because its gap 0 sits ahead of that write"

      refute Targets.admits_at?(document, palette, {"blk_GRP", "body"}, "cards.settle_final", ctx)

      refute "cards.settle_final" in Targets.accepted_types(
               document,
               palette,
               {"blk_GRP", "body"},
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
