defmodule StatifierBlocks.BlockTypeTest do
  use ExUnit.Case, async: true

  alias StatifierBlocks.BlockType
  alias StatifierBlocks.BlockTypeFixtures.{Minimal, PathFixtures, StringKeyedFixtures, Toy}

  @closed_slot_arities [:any, :at_least_one, :exactly_one, :zero_or_one]
  @closed_field_types [:string, :integer, :boolean, :expression, :duration]

  describe "behaviour_info/1" do
    # sabotage: drop `@callback current_version() :: pos_integer()` from
    # block_type.ex -> the callbacks list drops {:current_version, 0} -> red
    test "callbacks/1 is exactly the nine declared callbacks" do
      callbacks = BlockType.behaviour_info(:callbacks)

      assert MapSet.new(callbacks) ==
               MapSet.new(
                 slots: 1,
                 config_schema: 1,
                 validate_config: 1,
                 current_version: 0,
                 emit: 2,
                 io: 1,
                 migrate_config: 2,
                 fixtures: 0,
                 palette_entry: 0
               )

      assert length(callbacks) == 9
    end

    # sabotage: add `migrate_config: 2` to the `@optional_callbacks` list
    # without `fixtures: 0` -> the set no longer matches -> red
    test "optional_callbacks/1 is exactly io/1, migrate_config/2, fixtures/0, palette_entry/0" do
      optional = BlockType.behaviour_info(:optional_callbacks)

      assert MapSet.new(optional) ==
               MapSet.new(io: 1, migrate_config: 2, fixtures: 0, palette_entry: 0)

      assert length(optional) == 4
    end
  end

  describe "Toy exercises every one of the nine callbacks" do
    test "slots/1 returns the review slot only when review_below is present" do
      assert Toy.slots(%{"review_below" => 50}) == [
               {"review", :at_least_one, "If the score is below the floor"}
             ]

      assert Toy.slots(%{}) == []
    end

    test "config_schema/1 adds the review_below field only when configured" do
      base_keys = Toy.config_schema(%{}) |> Enum.map(& &1.key)
      assert base_keys == ["model", "assign_to"]

      with_review_keys = Toy.config_schema(%{"review_below" => 50}) |> Enum.map(& &1.key)
      assert with_review_keys == ["model", "assign_to", "review_below"]
    end

    test "validate_config/1 returns :ok for a valid config" do
      assert Toy.validate_config(%{"model" => "lead_v3", "assign_to" => "score"}) == :ok
    end

    test "validate_config/1 returns findings for an invalid config" do
      assert {:error, findings} =
               Toy.validate_config(%{
                 "model" => "not_a_model",
                 "assign_to" => "Not Valid",
                 "review_below" => 500
               })

      assert {"model", _} = List.keyfind(findings, "model", 0)
      assert {"assign_to", _} = List.keyfind(findings, "assign_to", 0)
      assert {"review_below", _} = List.keyfind(findings, "review_below", 0)
    end

    test "current_version/0 is 2" do
      assert Toy.current_version() == 2
    end

    test "emit/2 returns a marker tuple carrying the block id and context" do
      block = %StatifierBlocks.Block{id: "blk_1", type: "toy.score"}
      assert Toy.emit(block, :some_context) == {:ok, {:emitted, "blk_1", :some_context}}
    end

    test "io/1 declares consumed and produced terms" do
      assert Toy.io(%{}) == %{consumes: ["record"], produces: ["score"]}
    end

    test "migrate_config/2 renames field to assign_to from version 1" do
      assert Toy.migrate_config(1, %{"field" => "lead_score"}) ==
               {:ok, %{"assign_to" => "lead_score"}}
    end

    test "migrate_config/2 errors for an unknown source version" do
      assert Toy.migrate_config(3, %{}) == {:error, {:no_migration_from, 3}}
    end

    test "fixtures/0 returns an atom-keyed bundle" do
      bundle = Toy.fixtures()
      assert Map.has_key?(bundle, :datasets)
      assert Map.has_key?(bundle, :expressions)
    end

    test "palette_entry/0 returns presentation metadata" do
      assert Toy.palette_entry() == %{label: "Score record", group: "Enrichment"}
    end
  end

  describe "Minimal implements only the five required callbacks" do
    setup do
      Code.ensure_loaded!(Minimal)
      :ok
    end

    test "the five required callbacks are exported" do
      assert function_exported?(Minimal, :slots, 1)
      assert function_exported?(Minimal, :config_schema, 1)
      assert function_exported?(Minimal, :validate_config, 1)
      assert function_exported?(Minimal, :current_version, 0)
      assert function_exported?(Minimal, :emit, 2)
    end

    test "the four optional callbacks are absent" do
      refute function_exported?(Minimal, :io, 1)
      refute function_exported?(Minimal, :migrate_config, 2)
      refute function_exported?(Minimal, :fixtures, 0)
      refute function_exported?(Minimal, :palette_entry, 0)
    end
  end

  describe "closed sets" do
    test "every slot_decl arity Toy returns is drawn from the closed set" do
      for config <- [%{}, %{"review_below" => 50}] do
        for {_name, arity, _label} <- Toy.slots(config) do
          assert arity in @closed_slot_arities
        end
      end
    end

    # Recursive so {:list, :string} passes and a made-up nested shape does not.
    defp closed_field_type?(type) when type in @closed_field_types, do: true
    defp closed_field_type?({:select, options}) when is_list(options), do: true
    defp closed_field_type?({:list, inner}), do: closed_field_type?(inner)
    defp closed_field_type?(_type), do: false

    test "every field_decl type Toy returns is drawn from the closed set" do
      for config <- [%{}, %{"review_below" => 50}] do
        for field <- Toy.config_schema(config) do
          assert closed_field_type?(field.type)
        end
      end
    end

    test "a non-closed field type is correctly rejected by the recursive check" do
      refute closed_field_type?({:list, {:map, %{}}})
      refute closed_field_type?(:money)
    end
  end

  describe "decision 6 stability rule" do
    # sabotage: change Toy.slots/1's second clause to raise instead of
    # returning [] -> the accepted-but-not-review-configured case goes red
    test "for every config validate_config/1 accepts, slots/1 returns without raising" do
      accepted_configs = [
        %{"model" => "lead_v3", "assign_to" => "score"},
        %{"model" => "account_v1", "assign_to" => "lead_score", "review_below" => 40}
      ]

      for config <- accepted_configs do
        assert Toy.validate_config(config) == :ok
        assert is_list(Toy.slots(config))
      end
    end
  end

  describe "fixtures/0 spellings" do
    test "Toy's fixtures/0 is atom-keyed only" do
      bundle = Toy.fixtures()
      assert Enum.all?(Map.keys(bundle), &is_atom/1)
      refute Enum.any?(Map.keys(bundle), &is_binary/1)
    end

    test "StringKeyedFixtures.fixtures/0 is string-keyed only" do
      bundle = StringKeyedFixtures.fixtures()
      assert Enum.all?(Map.keys(bundle), &is_binary/1)
      refute Enum.any?(Map.keys(bundle), &is_atom/1)
    end

    test "PathFixtures.fixtures/0 is a binary path" do
      assert is_binary(PathFixtures.fixtures())
    end

    test "no constructible bundle mixes atom and string top-level keys" do
      for bundle <- [Toy.fixtures(), StringKeyedFixtures.fixtures()] do
        keys = Map.keys(bundle)
        all_atoms = Enum.all?(keys, &is_atom/1)
        all_strings = Enum.all?(keys, &is_binary/1)
        assert all_atoms or all_strings
      end
    end
  end

  describe "hygiene: no statifier_ui reference, no purity violations, no bead/PR ids" do
    @lib_files ["lib/statifier_blocks/block_type.ex"]
    @lib_and_support_files @lib_files ++ ["test/support/block_type_fixtures.ex"]

    defp read_files(paths) do
      Enum.map_join(paths, "\n", fn path ->
        __DIR__ |> Path.join("../../#{path}") |> Path.expand() |> File.read!()
      end)
    end

    test "block_type.ex never mentions statifier_ui" do
      refute read_files(@lib_files) =~ "statifier_ui"
    end

    test "no purity-violating calls appear in the new lib/test-support files" do
      forbidden = ~r/
        Application\.(get|fetch)_env |
        System\.get_env |
        Process\.(get|put) |
        :rand\. |
        :crypto\. |
        DateTime\. |
        NaiveDateTime\. |
        System\.(os_time|monotonic_time) |
        IO\. |
        File\. |
        :ets\. |
        GenServer |
        Agent\. |
        :persistent_term
      /x

      refute read_files(@lib_and_support_files) =~ forbidden
    end

    test "lib/ carries no bead ids or pull-request numbers" do
      forbidden = ~r/\bs(b|t|ui|p|ob)-[a-z0-9]{3,4}\b|PR #[0-9]/

      refute read_files(@lib_files) =~ forbidden
    end
  end
end
