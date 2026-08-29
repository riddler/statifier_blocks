defmodule StatifierBlocks.BlockTypeTest do
  use ExUnit.Case, async: true

  alias StatifierBlocks.BlockType

  alias StatifierBlocks.BlockTypeFixtures.{
    Minimal,
    Outcomes,
    PathFixtures,
    StringKeyedFixtures,
    Toy
  }

  defmodule BadShape do
    @moduledoc """
    An `outcomes/1` that answers with neither a `{name, label}` pair nor a
    binary name. Not a full `StatifierBlocks.BlockType`: it exists only to
    show `outcome_names/2` staying total over a return value the spec does
    not describe.
    """

    @doc "A deliberately malformed outcome declaration."
    @spec outcomes(map()) :: [term()]
    def outcomes(_config), do: ["done", :error]
  end

  @closed_slot_arities [:any, :at_least_one, :exactly_one, :zero_or_one]
  @closed_field_types [:string, :integer, :boolean, :expression, :duration]

  describe "behaviour_info/1" do
    # sabotage: drop `@callback current_version() :: pos_integer()` from
    # block_type.ex -> the callbacks list drops {:current_version, 0} -> red
    test "callbacks/1 is exactly the ten declared callbacks" do
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
                 palette_entry: 0,
                 outcomes: 1
               )

      assert length(callbacks) == 10
    end

    # sabotage: add `migrate_config: 2` to the `@optional_callbacks` list
    # without `fixtures: 0` -> the set no longer matches -> red
    test "optional_callbacks/1 is exactly the five optional callbacks" do
      optional = BlockType.behaviour_info(:optional_callbacks)

      assert MapSet.new(optional) ==
               MapSet.new(io: 1, migrate_config: 2, fixtures: 0, palette_entry: 0, outcomes: 1)

      assert length(optional) == 5
    end
  end

  describe "Toy exercises every one of the nine callbacks it implements" do
    # sabotage: change Toy's fallback `slots/1` clause to return the review
    # slot too -> the `Toy.slots(%{}) == []` assertion goes red
    test "slots/1 returns the review slot only when review_above is present" do
      assert Toy.slots(%{"review_above" => 50}) == [
               {"review", :at_least_one, "If the amount is above the ceiling"}
             ]

      assert Toy.slots(%{}) == []
    end

    # sabotage: change Toy's `review_fields(_)` fallback to return the
    # review_above field unconditionally -> the base_keys assertion goes red
    test "config_schema/1 adds the review_above field only when configured" do
      base_keys = Toy.config_schema(%{}) |> Enum.map(& &1.key)
      assert base_keys == ["policy", "assign_to"]

      with_review_keys = Toy.config_schema(%{"review_above" => 50}) |> Enum.map(& &1.key)
      assert with_review_keys == ["policy", "assign_to", "review_above"]
    end

    # sabotage: drop "standard_v3" from Toy's `check_policy/2` accepted list ->
    # the valid config gains a "policy" finding and :ok goes red
    test "validate_config/1 returns :ok for a valid config" do
      assert Toy.validate_config(%{"policy" => "standard_v3", "assign_to" => "decision"}) == :ok
    end

    # sabotage: widen Toy's `check_ceiling/2` bound guard from `n in 0..100`
    # to any integer -> the "review_above" finding disappears -> red
    test "validate_config/1 returns findings for an invalid config" do
      assert {:error, findings} =
               Toy.validate_config(%{
                 "policy" => "not_a_policy",
                 "assign_to" => "Not Valid",
                 "review_above" => 500
               })

      assert {"policy", _} = List.keyfind(findings, "policy", 0)
      assert {"assign_to", _} = List.keyfind(findings, "assign_to", 0)
      assert {"review_above", _} = List.keyfind(findings, "review_above", 0)
    end

    # sabotage: change Toy's `current_version/0` to 3 -> red
    test "current_version/0 is 2" do
      assert Toy.current_version() == 2
    end

    # sabotage: drop `context` from Toy's emit/2 marker tuple, leaving
    # `{:ok, {:emitted, id}}` -> red
    test "emit/2 returns a marker tuple carrying the block id and context" do
      block = %StatifierBlocks.Block{id: "blk_1", type: "toy.budget_check"}
      assert Toy.emit(block, :some_context) == {:ok, {:emitted, "blk_1", :some_context}}
    end

    # sabotage: change Toy's `io/1` to return empty consumes/produces
    # lists -> red
    test "io/1 declares consumed and produced terms" do
      assert Toy.io(%{}) == %{consumes: ["myapp.transaction"], produces: ["decision"]}
    end

    # sabotage: have Toy's `migrate_config(1, _)` put the value back under
    # "field" instead of "assign_to" -> red
    test "migrate_config/2 renames field to assign_to from version 1" do
      assert Toy.migrate_config(1, %{"field" => "risk_decision"}) ==
               {:ok, %{"assign_to" => "risk_decision"}}
    end

    # sabotage: drop the source version from Toy's catch-all migrate_config
    # error, leaving a bare `{:error, :no_migration_from}` -> red
    test "migrate_config/2 errors for an unknown source version" do
      assert Toy.migrate_config(3, %{}) == {:error, {:no_migration_from, 3}}
    end

    # sabotage: spell Toy's `datasets:` bundle key as `"datasets" =>` ->
    # `Map.has_key?(bundle, :datasets)` goes red
    test "fixtures/0 returns an atom-keyed bundle" do
      bundle = Toy.fixtures()
      assert Map.has_key?(bundle, :datasets)
      assert Map.has_key?(bundle, :expressions)
    end

    # sabotage: change Toy's `palette_entry/0` label to any other string
    # -> red
    test "palette_entry/0 returns presentation metadata" do
      assert Toy.palette_entry() == %{label: "Budget check", group: "Authorization"}
    end
  end

  describe "Minimal implements only the five required callbacks" do
    setup do
      Code.ensure_loaded!(Minimal)
      :ok
    end

    # sabotage: delete Minimal's `emit/2` clause -> the module stops
    # exporting it and this test goes red (the missing @impl also trips
    # warnings-as-errors, which is red by another road)
    test "the five required callbacks are exported" do
      assert function_exported?(Minimal, :slots, 1)
      assert function_exported?(Minimal, :config_schema, 1)
      assert function_exported?(Minimal, :validate_config, 1)
      assert function_exported?(Minimal, :current_version, 0)
      assert function_exported?(Minimal, :emit, 2)
    end

    # sabotage: give Minimal an `io/1` clause -> the first refute goes red
    test "the four optional callbacks are absent" do
      refute function_exported?(Minimal, :io, 1)
      refute function_exported?(Minimal, :migrate_config, 2)
      refute function_exported?(Minimal, :fixtures, 0)
      refute function_exported?(Minimal, :palette_entry, 0)
    end
  end

  describe "outcomes/2 (ADR-0002 amendment A1)" do
    # sabotage: changed the resolver's default arm to `[]` -> a type that
    # declares nothing gets no outcomes at all, and the summary that is
    # supposed to be "always non-empty" empties out (verified red)
    test "a type declaring no outcomes/1 has exactly one, done" do
      assert BlockType.outcomes(Minimal, %{}) == [{"done", "Done"}]
      assert BlockType.outcomes(Toy, %{"policy" => "standard_v3"}) == [{"done", "Done"}]
    end

    # sabotage: sorted the resolver's return with `Enum.sort/1` ->
    # "abandoned" leads and both asserts go red, which is the byte
    # determinism ADR-0004 decision 6 reads out of this order (verified)
    test "a type declaring several gets them in declaration order, never sorted" do
      assert BlockType.outcomes(Outcomes, %{}) == [
               {"done", "Done"},
               {"error", "Failed"},
               {"abandoned", "Given up"}
             ]

      assert BlockType.outcome_names(Outcomes, %{}) == ["done", "error", "abandoned"]
    end

    # sabotage: made `outcome_name/1`'s catch-all return the term unchanged
    # -> the declarations come back as `["done", :error]`, a non-binary the
    # `:invalid_outcome` finding's message could not interpolate, and this
    # goes red (verified)
    test "a declaration outside the pair shape comes back as text, not a crash" do
      assert BlockType.outcome_names(BadShape, %{}) == [~s("done"), ":error"]
    end
  end

  describe "closed sets" do
    # sabotage: change Toy's review slot arity from `:at_least_one` to an
    # invented `:one_or_more` -> red
    test "every slot_decl arity Toy returns is drawn from the closed set" do
      for config <- [%{}, %{"review_above" => 50}] do
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

    # sabotage: change the review_above field's `type: :integer` to an
    # invented `type: :money` -> red
    test "every field_decl type Toy returns is drawn from the closed set" do
      for config <- [%{}, %{"review_above" => 50}] do
        for field <- Toy.config_schema(config) do
          assert closed_field_type?(field.type)
        end
      end
    end

    # sabotage: change `closed_field_type?/1`'s catch-all clause to return
    # true -> both refutes go red
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
        %{"policy" => "standard_v3", "assign_to" => "decision"},
        %{"policy" => "corporate_v1", "assign_to" => "risk_decision", "review_above" => 40}
      ]

      for config <- accepted_configs do
        assert Toy.validate_config(config) == :ok
        assert is_list(Toy.slots(config))
      end
    end
  end

  describe "fixtures/0 spellings" do
    # sabotage: spell Toy's `datasets:` bundle key as `"datasets" =>` ->
    # the bundle mixes key kinds and the all-atoms assertion goes red
    test "Toy's fixtures/0 is atom-keyed only" do
      bundle = Toy.fixtures()
      assert Enum.all?(Map.keys(bundle), &is_atom/1)
      refute Enum.any?(Map.keys(bundle), &is_binary/1)
    end

    # sabotage: spell StringKeyedFixtures' bundle `%{"version" => 1,
    # datasets: %{}}` (one atom key, shorthand last so it still parses) ->
    # the all-strings assertion goes red
    test "StringKeyedFixtures.fixtures/0 is string-keyed only" do
      bundle = StringKeyedFixtures.fixtures()
      assert Enum.all?(Map.keys(bundle), &is_binary/1)
      refute Enum.any?(Map.keys(bundle), &is_atom/1)
    end

    # sabotage: have PathFixtures.fixtures/0 return a map instead of the
    # path binary -> red
    test "PathFixtures.fixtures/0 is a binary path" do
      assert is_binary(PathFixtures.fixtures())
    end

    # sabotage: spell Toy's `datasets:` bundle key as `"datasets" =>` ->
    # that bundle is neither all-atom nor all-string and this goes red
    test "no constructible bundle mixes atom and string top-level keys" do
      for bundle <- [Toy.fixtures(), StringKeyedFixtures.fixtures()] do
        keys = Map.keys(bundle)
        all_atoms = Enum.all?(keys, &is_atom/1)
        all_strings = Enum.all?(keys, &is_binary/1)
        assert all_atoms or all_strings
      end
    end
  end

  describe "decision 7's value_path" do
    # sabotage: `value_path/1` matching `%{value_path: path}` rather than a
    # non-empty list - an empty declared path addresses the whole config, and
    # a form control would then overwrite every key the block carries.
    test "a declaration without a usable value_path addresses its own key" do
      assert BlockType.value_path(%{key: "label"}) == ["label"]
      assert BlockType.value_path(%{key: "label", value_path: []}) == ["label"]

      assert BlockType.value_path(%{key: "arm_b", value_path: ["arms", 0, "cond"]}) ==
               ["arms", 0, "cond"]
    end

    # sabotage: drop `fetch_value/2`'s catch-all clause - a config an author is
    # halfway through typing raises instead of rendering at its default.
    test "fetch_value/2 is total, and a path that does not resolve is :error" do
      config = %{"arms" => [%{"slot" => "arm_b", "cond" => "x"}]}

      assert BlockType.fetch_value(config, ["arms", 0, "cond"]) == {:ok, "x"}
      assert BlockType.fetch_value(config, []) == {:ok, config}

      for missing <- [
            ["arms", 0, "absent"],
            ["arms", 9, "cond"],
            ["arms", "not_an_index"],
            ["arms", -1, "cond"],
            ["absent", 0],
            ["arms", 0, "cond", "deeper"]
          ] do
        assert BlockType.fetch_value(config, missing) == :error
      end
    end

    # sabotage: make `put_value/3`'s last-segment map clause require the key to
    # exist - an arm with no condition yet could never be given one.
    test "put_value/3 writes the last segment whether or not it was there" do
      assert BlockType.put_value(%{"arms" => [%{"slot" => "arm_b"}]}, ["arms", 0, "cond"], "y") ==
               %{"arms" => [%{"slot" => "arm_b", "cond" => "y"}]}
    end

    # sabotage: have `put_value/3` create the intermediate structure it did not
    # find - a form control invents a shape the block type never wrote.
    test "put_value/3 leaves a config a path does not reach alone" do
      config = %{"arms" => [%{"cond" => "x"}], "other" => 1}

      for unreachable <- [["arms", 5, "cond"], ["absent", "deeper"], ["other", "deeper"]] do
        assert BlockType.put_value(config, unreachable, "y") == config
      end
    end

    # sabotage: change `put_value(_target, [], value)` to return `_target` -
    # the recursion bottoms out on the old value, so a path ending at a list
    # index writes the element back unchanged.
    test "put_value/3 replaces a whole list element when the path ends at one" do
      config = %{"arms" => [%{"cond" => "x"}, %{"cond" => "y"}]}

      assert BlockType.put_value(config, ["arms", 1], "z") ==
               %{"arms" => [%{"cond" => "x"}, "z"]}
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

    # sabotage: spell the `statifier-ui` mention in block_type.ex's
    # fixtures/0 @doc with an underscore -> red
    test "block_type.ex never mentions statifier_ui" do
      refute read_files(@lib_files) =~ "statifier_ui"
    end

    # sabotage: add an `Application.get_env(:statifier_blocks, :x)` mention
    # anywhere in block_type.ex -> red
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

    # sabotage: put a bead id back into a block_type.ex @doc, as ADR-0002's
    # own sketch spells it -> red
    test "lib/ carries no bead ids or pull-request numbers" do
      forbidden = ~r/\bs(b|t|ui|p|ob)-[a-z0-9]{3,4}\b|PR #[0-9]/

      refute read_files(@lib_files) =~ forbidden
    end
  end
end
