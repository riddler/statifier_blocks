defmodule StatifierBlocks.ValidationTest do
  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Document, Validation}

  describe "validate/1 on a well-formed document" do
    # sabotage: change `validate_unique_ids/1`'s final case clause to always
    # return {:error, :bogus} -> red
    test "returns :ok for a document built by Block.new/2 and Document.new/2" do
      grandchild = Block.new("myapp.notify", id: "blk_grandchild")

      child =
        Block.new("core.sequence",
          id: "blk_child",
          config: %{"name" => "Example", "count" => 3, "flag" => true, "note" => nil},
          slots: %{"body" => [grandchild]}
        )

      root =
        Block.new("core.branch",
          id: "blk_root",
          slots: %{"arm_qualified" => [child], "otherwise" => []}
        )

      document = Document.new(root, id: "bdoc_root", metadata: %{"name" => "Example"})

      assert Document.validate(document) == :ok
      assert Validation.validate(document) == :ok
    end
  end

  describe "schema_version" do
    # sabotage: change `check_schema_version(1)` to accept any integer -> red
    test "rejects an unsupported version" do
      document = Document.new(Block.new("core.sequence"))
      document = %{document | schema_version: 2}

      assert Document.validate(document) == {:error, {:unsupported_schema_version, 2}}
    end

    # sabotage: drop the `check_schema_version(version) when is_integer(version)
    # and version > 0` clause -> the malformed-envelope arm below fires for
    # a valid-but-unsupported version too, collapsing two distinguishable
    # causes into one -> red
    test "reports a non-positive-integer schema_version as malformed, not unsupported" do
      document = Document.new(Block.new("core.sequence"))
      document = %{document | schema_version: "1"}

      assert {:error, {:malformed_envelope, {:schema_version, :not_a_pos_integer, "1"}}} =
               Document.validate(document)
    end
  end

  describe "envelope shape" do
    # sabotage: change `non_empty_utf8?("")` to return `true` -> red
    test "rejects an empty document id" do
      document = Document.new(Block.new("core.sequence"))
      document = %{document | id: ""}

      assert Document.validate(document) ==
               {:error, {:malformed_envelope, {:id, :not_a_non_empty_string}}}
    end

    # sabotage: change `check_revision/1`'s guard from `revision >= 0` to
    # `revision >= -1` -> red
    test "rejects a negative revision" do
      document = Document.new(Block.new("core.sequence"))
      document = %{document | revision: -1}

      assert Document.validate(document) ==
               {:error, {:malformed_envelope, {:revision, :not_a_non_neg_integer}}}
    end

    # sabotage: change `check_metadata/1` to skip the canonical_json_object
    # call and always return :ok -> red
    test "rejects a metadata that is not a map" do
      document = Document.new(Block.new("core.sequence"))
      document = %{document | metadata: "not-a-map"}

      assert Document.validate(document) ==
               {:error, {:malformed_envelope, {:metadata, :not_a_canonical_json_object}}}
    end

    # sabotage: change `check_root/1`'s first clause to `defp check_root(_),
    # do: :ok` -> red
    test "rejects a root that is not a %Block{}" do
      document = Document.new(Block.new("core.sequence"))
      document = %{document | root: %{"not" => "a block"}}

      assert {:error, {:malformed_envelope, {:root, :not_a_block, _}}} =
               Document.validate(document)
    end
  end

  describe "per-block shape" do
    # sabotage: change `check_block_id/2` to always return :ok -> red
    test "rejects a block with a non-binary id, reporting id as nil" do
      root = %{Block.new("core.sequence", id: "blk_root") | id: 123}
      document = Document.new(root)

      assert Document.validate(document) ==
               {:error, {:malformed_block, nil, {:id, :not_a_non_empty_string}}}
    end

    # sabotage: change `check_type/2` to accept an empty string -> red
    test "rejects a block with an empty type, reporting the block's own valid id" do
      root = %{Block.new("core.sequence", id: "blk_root") | type: ""}
      document = Document.new(root)

      assert Document.validate(document) ==
               {:error, {:malformed_block, "blk_root", {:type, :not_a_non_empty_string}}}
    end

    # sabotage: change `check_type_version/2`'s guard to `type_version >= 0`
    # (accepting 0) -> red
    test "rejects a zero type_version" do
      root = %{Block.new("core.sequence", id: "blk_root") | type_version: 0}
      document = Document.new(root)

      assert Document.validate(document) ==
               {:error, {:malformed_block, "blk_root", {:type_version, :not_a_pos_integer}}}
    end

    # sabotage: change `check_config/2` to always return :ok -> red
    test "rejects a config that is not a map" do
      root = %{Block.new("core.sequence", id: "blk_root") | config: [1, 2, 3]}
      document = Document.new(root)

      assert Document.validate(document) ==
               {:error, {:malformed_block, "blk_root", {:config, :not_a_canonical_json_object}}}
    end

    # sabotage: change `check_slots/2`'s non-map clause to
    # `defp check_slots(reported_id, _slots), do: :ok` -> red
    test "rejects a slots that is not a map" do
      root = %{Block.new("core.sequence", id: "blk_root") | slots: "not-a-map"}
      document = Document.new(root)

      assert Document.validate(document) ==
               {:error, {:malformed_block, "blk_root", {:slots, :not_a_map, "not-a-map"}}}
    end

    # sabotage: change `check_slot/2` to skip the slot-name check and jump
    # straight to the children check -> red
    test "rejects a slot whose name is not a non-empty string" do
      child = Block.new("myapp.notify")

      root =
        Block.new("core.sequence", id: "blk_root", slots: %{"body" => [child]})

      root = %{root | slots: %{123 => [child]}}
      document = Document.new(root)

      assert Document.validate(document) ==
               {:error, {:malformed_block, "blk_root", {:slots, {:slot_name, 123}}}}
    end

    # sabotage: change `check_slot/2`'s children check from `Enum.all?` to
    # `Enum.any?` -> red
    test "rejects a slot whose value is not a list of blocks" do
      root = Block.new("core.sequence", id: "blk_root", slots: %{"body" => [%{}]})
      document = Document.new(root)

      assert Document.validate(document) ==
               {:error, {:malformed_block, "blk_root", {:slots, {"body", :not_a_block_list}}}}
    end
  end

  describe "duplicate ids" do
    # sabotage: change `validate_unique_ids/1` to use a plain list with
    # `++` instead of `MapSet.member?/2`'s membership check, always
    # returning :cont -> red
    test "reports a duplicate id found deep in the tree" do
      leaf_a = Block.new("myapp.notify", id: "blk_dup")
      leaf_b = Block.new("myapp.notify", id: "blk_dup")

      grandchild_holder =
        Block.new("core.sequence", id: "blk_holder", slots: %{"body" => [leaf_a]})

      root =
        Block.new("core.branch",
          id: "blk_root",
          slots: %{
            "arm_qualified" => [grandchild_holder],
            "otherwise" => [leaf_b]
          }
        )

      document = Document.new(root)

      assert Document.validate(document) == {:error, {:duplicate_block_id, "blk_dup"}}
    end
  end

  describe "no-floats (decision 6)" do
    # sabotage: delete the `defp canonical_json_check(value, path) when
    # is_float(value)` clause, letting the catch-all `{:not_json, value}`
    # arm handle floats too -> red
    test "rejects a float at the top level of config, naming :float not :not_json" do
      root = Block.new("core.sequence", id: "blk_root", config: %{"ratio" => 0.5})
      document = Document.new(root)

      assert Document.validate(document) ==
               {:error, {:malformed_block, "blk_root", {:config, {:float, ["ratio"]}}}}
    end

    # sabotage: change the list clause of `canonical_json_check/2` to check
    # `is_integer(item)` before recursing instead of recursing unconditionally
    # (silently allowing a float packed after an integer) -> red
    test "rejects a float nested inside a list, with the list index in the path" do
      root =
        Block.new("core.sequence",
          id: "blk_root",
          config: %{"weights" => [1, 2.5, 3]}
        )

      document = Document.new(root)

      assert Document.validate(document) ==
               {:error, {:malformed_block, "blk_root", {:config, {:float, ["weights", 1]}}}}
    end

    # sabotage: in `check_metadata/1`, swap `canonical_json_object(metadata)`
    # for a call that always returns :ok -> red
    test "rejects a float inside document metadata" do
      document = Document.new(Block.new("core.sequence"), metadata: %{"score" => 1.5})

      assert Document.validate(document) ==
               {:error, {:malformed_envelope, {:metadata, {:float, ["score"]}}}}
    end
  end

  describe "totality over hostile terms" do
    hostile_terms = [
      {"a tuple", {1, 2}},
      {"a pid-free struct", Range.new(1, 2)},
      {"an atom", :some_atom},
      {"a non-UTF-8 binary", <<255, 255>>}
    ]

    # sabotage: remove the catch-all `defp canonical_json_check(value, _path),
    # do: {:error, {:not_json, value}}` clause -> FunctionClauseError instead
    # of a returned value -> red
    for {label, term} <- hostile_terms do
      test "returns an error rather than raising for #{label} inside config" do
        term = unquote(Macro.escape(term))
        root = Block.new("core.sequence", id: "blk_root", config: %{"value" => term})
        document = Document.new(root)

        assert {:error, {:malformed_block, "blk_root", {:config, _reason}}} =
                 Document.validate(document)
      end
    end
  end
end
