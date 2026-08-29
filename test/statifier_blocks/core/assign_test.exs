defmodule StatifierBlocks.Core.AssignTest do
  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Compiler, Document, Palette, Provenance}
  alias StatifierBlocks.Compiler.Context
  alias StatifierBlocks.Core.Assign

  describe "validate_config/1" do
    # sabotage: inverted `check_value/2`'s condition -> a good literal was
    # rejected, taking this red (verified)
    test "accepts a well-formed path and value" do
      assert Assign.validate_config(%{"path" => "review.parked", "value" => "false"}) == :ok
    end

    # sabotage: dropped the `check_path/2` clause from the `|>` pipeline in
    # `validate_config/1` -> the bad `path` configs below went green, taking
    # this red (verified). A second, narrower sabotage on the carriage-return
    # case alone: reverted `check_path/2` to
    # `String.contains?(path, [" ", "\t", "\n"])` -> the tab case still
    # went red on its own (that spelling already named "\t"), but the
    # carriage-return assertion went green, since "\r" was never in that
    # three-character list - taking this red (verified)
    test "rejects everything a datamodel path cannot be" do
      assert {:error, [{"path", _}]} =
               Assign.validate_config(%{"path" => "", "value" => "false"})

      assert {:error, [{"path", _}]} =
               Assign.validate_config(%{"path" => "review parked", "value" => "false"})

      assert {:error, [{"path", _}]} =
               Assign.validate_config(%{"path" => "review\rparked", "value" => "false"})

      assert {:error, [{"path", _}]} =
               Assign.validate_config(%{"path" => "review\tparked", "value" => "false"})

      assert {:error, [{"path", _}]} = Assign.validate_config(%{"path" => 1, "value" => "false"})
      assert {:error, [{"path", _}]} = Assign.validate_config(%{"value" => "false"})
    end

    # sabotage: dropped the `check_value/2` clause from the `|>` pipeline in
    # `validate_config/1` -> an empty `value` went green, taking this red
    # (verified)
    test "rejects an empty value, since an empty literal is spelled with quotes" do
      assert {:error, [{"value", _}]} =
               Assign.validate_config(%{"path" => "review.parked", "value" => ""})

      assert {:error, [{"value", _}]} = Assign.validate_config(%{"path" => "review.parked"})
    end

    # sabotage: swapped `check_path/2` and `check_value/2` in the pipeline
    # -> `Config.verdict/1` reversed them into `[value, path]` and the
    # ordered pattern went red, which is this assertion earning its keep:
    # the finding order is the order the editor renders (verified)
    test "reports both findings when both fields are bad" do
      assert {:error, [{"path", _}, {"value", _}]} = Assign.validate_config(%{})
    end
  end

  describe "leaf-ness" do
    # sabotage: gave `slots/1` a `body` slot -> red, since an assign is a
    # leaf (verified)
    test "declares no slots and one step kind" do
      assert Assign.slots(%{"path" => "review.parked", "value" => "false"}) == []
      assert Assign.io(%{}) == %{kinds: [:step]}
    end
  end

  # sabotage: swapped the two fields in `config_schema/1` -> red, because
  # the declared order is the order the form renders them in (verified)
  test "config_schema/1 declares path then value, both required strings" do
    assert Assign.config_schema(%{}) == [
             %{key: "path", type: :string, label: "Write to", required?: true, default: ""},
             %{key: "value", type: :string, label: "This literal", required?: true, default: ""}
           ]
  end

  describe "compiled SCXML" do
    # sabotage: swapped `location` and `expr` in the `Emission.element/3` call
    # -> the value written to the datamodel came from the wrong config field,
    # and the `expr="false" location="review.parked"` assertion went red
    # (verified)
    test "emits <assign> inside <onentry>, expr before location, in a compound state" do
      root =
        Block.new("core.assign",
          id: "blk_ASN",
          config: %{"path" => "review.parked", "value" => "false"}
        )

      scxml = compile!(root).scxml

      assert scxml =~ ~s(<state id="s_blk_ASN" initial="s_blk_ASN__done">)
      assert scxml =~ ~s(<onentry><assign expr="false" location="review.parked"/></onentry>)
      assert scxml =~ ~s(<final id="s_blk_ASN__done"/>)
    end
  end

  describe "end to end" do
    # sabotage: dropped `Emit.final(done)` from the children `emit/2` passes
    # to `Emit.state/3` -> the block never reaches a `<final>`, `done.state`
    # is never raised, and `Statifier.initialize/2` leaves the block's own
    # state active instead, taking this red (verified)
    test "the chart compiles and initializes, and the block completes" do
      root =
        Block.new("core.assign",
          id: "blk_ASN",
          config: %{"path" => "review.parked", "value" => "false"}
        )

      {:ok, machine} = Statifier.compile(compile!(root).scxml)
      {machine_state, _effects} = Statifier.initialize(machine)

      assert MapSet.member?(Statifier.active_leaf_states(machine_state), "s_blk_ASN__done")
    end
  end

  describe "emit/2" do
    # sabotage: made `path/1` fall through to `{:ok, path}` unconditionally
    # -> emit/2 answered {:ok, ...} for a config validate_config/1 rejects,
    # taking this red (verified)
    test "refuses a config it cannot compile rather than emitting nonsense" do
      block = Block.new("core.assign", id: "blk_ASN", config: %{"path" => "", "value" => ""})

      assert {:error, [{"path", _message}]} =
               Assign.emit(block, Context.new("blk_ASN", "bdoc_T"))
    end
  end

  describe "provenance" do
    # sabotage: dropped the `Emission.attribute_from_config/3` call on
    # `location` -> the path value's span carried no config key, taking this
    # red (verified)
    test "location is attributed to the block and the path field" do
      root =
        Block.new("core.assign",
          id: "blk_ASN",
          config: %{"path" => "review.parked", "value" => "false"}
        )

      compiled = compile!(root)

      {offset, _length} = :binary.match(compiled.scxml, "review.parked")

      assert {:ok, %{block_id: "blk_ASN", config_key: "path"}} =
               Provenance.owner_at(compiled.provenance, offset)
    end

    # sabotage: dropped the `Emission.attribute_from_config/3` call on `expr`
    # -> the value's span carried no config key, taking this red (verified)
    test "expr is attributed to the block and the value field" do
      root =
        Block.new("core.assign",
          id: "blk_ASN",
          config: %{"path" => "review.parked", "value" => "false"}
        )

      compiled = compile!(root)

      {offset, _length} = :binary.match(compiled.scxml, ~s(expr="false"))
      # step past `expr="` to the value's own span
      {offset, _length} = :binary.match(compiled.scxml, "false", scope: {offset, 20})

      assert {:ok, %{block_id: "blk_ASN", config_key: "value"}} =
               Provenance.owner_at(compiled.provenance, offset)
    end
  end

  defp compile!(root) do
    {:ok, compiled} = Compiler.compile(Document.new(root, id: "bdoc_T"), Palette.core())
    compiled
  end
end
