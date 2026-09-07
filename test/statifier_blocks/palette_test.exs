defmodule StatifierBlocks.PaletteTest do
  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, BlockTypeFixtures, Document, DocumentFixtures, Palette}
  alias StatifierBlocks.BlockTypeFixtures.{Minimal, Toy}

  defmodule Seventh do
    @moduledoc """
    An ordinary block type declaring an `order` in the core `"Structure"`
    group - the group `core_types/0`'s entries sit in. Pure: nothing here
    names LiveView.
    """

    use StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1
    @impl true
    def config_schema(_config), do: []
    @impl true
    def palette_entry, do: %{label: "Seventh", group: "Structure", order: 7}
    @impl true
    def sentence(_config), do: "seventh"
    @impl true
    def emit(%Block{id: id}, _context), do: {:error, {:not_implemented, id}}
  end

  defmodule AlsoSeventh do
    @moduledoc "A second entry declaring the same group and the same order."

    use StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1
    @impl true
    def config_schema(_config), do: []
    @impl true
    def palette_entry, do: %{label: "Also seventh", group: "Structure", order: 7}
    @impl true
    def sentence(_config), do: "also seventh"
    @impl true
    def emit(%Block{id: id}, _context), do: {:error, {:not_implemented, id}}
  end

  defmodule Seventh.Recipe do
    @moduledoc """
    A hand-written module sitting at the name a composite's derived recipe
    would take, but declaring a card of its own. The derived-pair exemption
    reads both halves of the derivation, so this one is still a collision.
    """

    @behaviour StatifierBlocks.Recipe

    @impl true
    def insert(_target, _document), do: {:error, :never}
    @impl true
    def palette_entry, do: %{label: "Not derived", group: "Structure", order: 7}
    @impl true
    def members(_block_id, _document), do: []
  end

  defmodule SignupStep do
    @moduledoc """
    A composite, for the one pair the duplicate-order check admits: its
    `types` entry beside the `SignupStep.Recipe` its declaration derives,
    whose `palette_entry/0` is this module's.
    """

    use StatifierBlocks.Composite,
      name: "myapp.signup_step",
      params: [
        %{key: "invoke_type", type: :string, label: "Call", required?: true, default: ""}
      ],
      sentence: "Call {invoke_type}",
      palette_entry: %{label: "Signup step", group: "Structure", order: 41},
      version: 1

    @impl StatifierBlocks.Composite
    def subtree(params) do
      [
        Block.new("core.invoke",
          id: "call",
          config: %{"invoke_type" => params["invoke_type"], "assign_to" => "", "params" => ""}
        )
      ]
    end
  end

  defmodule SeventhRecipe do
    @moduledoc """
    A recipe declaring the same card as `Seventh` - same label, same group,
    same order - while being no relation of it. The palette browser draws
    types and recipes into one group, so this is a collision even though the
    two names live in two namespaces, and it is what makes card equality
    alone too loose a test for the derived pair.
    """

    @behaviour StatifierBlocks.Recipe

    @impl true
    def insert(_target, _document), do: {:ok, []}
    @impl true
    def palette_entry, do: %{label: "Seventh", group: "Structure", order: 7}
    @impl true
    def members(_block_id, _document), do: []
  end

  @hostile_type_names [
    "",
    "myapp.retired",
    <<0xFF, 0xFE, 0x00>>,
    String.duplicate("a", 10_000)
  ]

  describe "new/0 and new/1" do
    # sabotage: change new/1's default argument from `%{}` to a non-empty
    # map -> new/0's assertion on %Palette{types: %{}} goes red (verified)
    test "new/0 produces an empty palette" do
      assert Palette.new() == %Palette{types: %{}}
    end

    # sabotage: change new/1's body to ignore the argument and always use
    # %{} -> this assertion goes red
    test "new/1 produces a palette carrying the given map" do
      given = %{"toy.budget_check" => Toy}
      assert Palette.new(given) == %Palette{types: given}
    end

    # sabotage: change the defstruct default for :assignability from `nil`
    # to any other value -> this assertion goes red
    test "a bare %Palette{} carries no assignability relation" do
      assert %Palette{}.assignability == nil
    end

    # sabotage: change new/2's default for the :assignability option from
    # `Keyword.get(opts, :assignability)` to a hard-coded module -> this
    # assertion goes red
    test "new/1 (no opts) leaves assignability nil" do
      assert Palette.new(%{"toy.authorize" => Toy}).assignability == nil
    end

    # sabotage: change new/2 to ignore the :assignability key entirely ->
    # this assertion goes red
    test "new/2 carries the :assignability module given in opts" do
      palette = Palette.new(%{"toy.authorize" => Toy}, assignability: MyWideningModule)
      assert palette.assignability == MyWideningModule
    end
  end

  describe "fetch/2" do
    # sabotage: change fetch/2's success clause to return `:ok` instead of
    # `{:ok, module}` -> this assertion goes red
    test "returns {:ok, module} for a name the palette carries" do
      assert Palette.fetch(BlockTypeFixtures.palette(), "toy.budget_check") == {:ok, Toy}
    end

    # sabotage: change the :error branch to `{:error, :unknown_block_type}`
    # (dropping the name) -> this assertion goes red
    test "returns {:error, {:unknown_block_type, name}} for a name it does not carry" do
      assert Palette.fetch(BlockTypeFixtures.palette(), "myapp.retired") ==
               {:error, {:unknown_block_type, "myapp.retired"}}
    end

    # sabotage: drop the name from the :error arm (`{:error,
    # :unknown_block_type}`) -> the pinned-name pattern match on every
    # hostile name below goes red
    test "returns a value and never raises over a table of hostile type names" do
      palette = BlockTypeFixtures.palette()

      for name <- @hostile_type_names do
        assert {:error, {:unknown_block_type, ^name}} = Palette.fetch(palette, name)
      end
    end

    # sabotage: drop the name from the :error arm (`{:error,
    # :unknown_block_type}`) -> the pinned-name pattern match on every
    # hostile name below goes red, isolated to the empty-palette path
    test "returns a value and never raises over an empty palette, for every hostile name" do
      empty = Palette.new()

      for name <- @hostile_type_names do
        assert {:error, {:unknown_block_type, ^name}} = Palette.fetch(empty, name)
      end
    end

    # sabotage: replace the multi-tenant map-per-palette model with a single
    # shared map both palettes read from -> the second palette's fetch would
    # start returning the first palette's module too, and this test's second
    # assertion goes red
    test "two palettes with different modules under the same name resolve independently" do
      palette_a = Palette.new(%{"toy.budget_check" => Toy})
      palette_b = Palette.new(%{"toy.budget_check" => Minimal})

      assert Palette.fetch(palette_a, "toy.budget_check") == {:ok, Toy}
      assert Palette.fetch(palette_b, "toy.budget_check") == {:ok, Minimal}
    end
  end

  describe "resolve/2" do
    # sabotage: change the current-version clause to always rewrite
    # `config` to `%{}` -> `resolved == block` goes red
    test "a block at the current version resolves unchanged" do
      block = Block.new("toy.budget_check", type_version: 2, config: %{"assign_to" => "decision"})

      assert {:ok, Toy, resolved} = Palette.resolve(BlockTypeFixtures.palette(), block)
      assert resolved == block
    end

    # sabotage: change the migration clause to return `{:ok, module,
    # block}` (the unmigrated block) instead of the migrated struct ->
    # `migrated.config["assign_to"]` goes red
    test "a block below the current version migrates its config in memory" do
      block =
        Block.new("toy.budget_check", type_version: 1, config: %{"field" => "risk_decision"})

      assert {:ok, Toy, migrated} = Palette.resolve(BlockTypeFixtures.palette(), block)
      assert migrated.config["assign_to"] == "risk_decision"
      refute Map.has_key?(migrated.config, "field")
    end

    # sabotage: n/a - no mutation of palette.ex can red this test.
    # `resolve/2` is never handed the document, and terms are immutable, so
    # `doc` cannot change under it whatever the function does. It is a
    # regression guard against a future `resolve/2` that takes a document,
    # not a mutation-sensitive assertion. The "never written back" rule is
    # carried by the source scan in the hygiene describe below, which does
    # have a mutation that reds it.
    test "migration is applied in memory only; the source document is untouched" do
      doc = DocumentFixtures.worked_example()

      block =
        Block.new("toy.budget_check", type_version: 1, config: %{"field" => "risk_decision"})

      doc_before = doc
      hash_before = Document.content_hash(doc)

      assert {:ok, Toy, _migrated} = Palette.resolve(BlockTypeFixtures.palette(), block)

      assert doc == doc_before
      assert Document.content_hash(doc) == hash_before
    end

    # sabotage: report `current` instead of `stored` in the too-new arm
    # (`{:error, {:block_type_too_new, block.id, current}}`) -> the pinned
    # 99 goes red. Dropping the `stored > current` guard instead does NOT
    # red this test - the clause still matches a too-new block and returns
    # the same tuple; it reds the migration tests instead
    test "a block newer than the type's current version hard-errors" do
      block = Block.new("toy.budget_check", type_version: 99, config: %{})

      assert Palette.resolve(BlockTypeFixtures.palette(), block) ==
               {:error, {:block_type_too_new, block.id, 99}}
    end

    # sabotage: reorder resolve/2 to check migration before fetch/2 ->
    # this would raise UndefinedFunctionError instead of returning the
    # unknown_block_type tuple
    test "an unknown block type is reported before current_version/0 is ever reached" do
      block = Block.new("myapp.retired", type_version: 1, config: %{})

      assert Palette.resolve(BlockTypeFixtures.palette(), block) ==
               {:error, {:unknown_block_type, "myapp.retired"}}
    end

    # sabotage: change the migrate_config error clause to swallow the
    # reason (`{:error, :migration_failed}` without the block id or
    # reason) -> this assertion goes red
    test "a migrate_config/2 error surfaces as :migration_failed" do
      block = Block.new("toy.erroring_migration", type_version: 1, config: %{})

      assert Palette.resolve(BlockTypeFixtures.palette(), block) ==
               {:error, {:migration_failed, block.id, {:no_migration_from, 1}}}
    end

    # sabotage: drop the `function_exported?/3` guard so a module with no
    # migrate_config/2 raises UndefinedFunctionError instead of returning
    # :no_migration_available
    test "a type with no migrate_config/2 at all reports :no_migration_available" do
      block = Block.new("toy.no_migration", type_version: 1, config: %{})

      assert Palette.resolve(BlockTypeFixtures.palette(), block) ==
               {:error, {:migration_failed, block.id, :no_migration_available}}
    end

    # sabotage: change the unknown-type arm to `{:error, :unknown_block_type}`
    # (dropping the name) -> the pinned-name pattern match below goes red
    test "returns a value and never raises over a table of hostile type names" do
      palette = BlockTypeFixtures.palette()

      for name <- @hostile_type_names do
        block = Block.new(name, type_version: 1, config: %{})

        assert {:error, {:unknown_block_type, ^name}} = Palette.resolve(palette, block)
      end
    end

    # sabotage: make the migration clause raise instead of returning
    # {:error, {:migration_failed, ...}} for a module with no
    # migrate_config/2 -> this loop raises instead of asserting
    test "returns a value and never raises for a type_version: 1 block against every fixture module" do
      palette = BlockTypeFixtures.palette()

      for {type_name, _module} <- BlockTypeFixtures.raw_palette() do
        block = Block.new(type_name, type_version: 1, config: %{})

        assert match?({:ok, _module, _block}, Palette.resolve(palette, block)) or
                 match?({:error, _reason}, Palette.resolve(palette, block))
      end
    end
  end

  describe "new/2 refuses a duplicate order, as from_modules/2 does" do
    # sabotage: drop `refute_duplicate_orders!/2` from new/2 (leaving it in
    # from_modules/2, where it used to live) -> this goes red: the map
    # builder mounts both entries at order 7 and the browser's pick between
    # them is whatever the sort happened to do.
    test "two entries of one group at one order are refused" do
      assert_raise ArgumentError, ~r/both declare order 7/, fn ->
        Palette.new(%{"toy.seventh" => Seventh, "toy.also_seventh" => AlsoSeventh})
      end
    end

    # sabotage: as above -> red. This is the shape `core_types/0`'s own doc
    # demonstrates, and the one that never passes through from_modules/2.
    test "a merge onto core_types/0 colliding with a core entry is refused" do
      assert_raise ArgumentError, ~r/both declare order 7/, fn ->
        Palette.new(Map.merge(Palette.core_types(), %{"toy.seventh" => Seventh}))
      end
    end

    # sabotage: raise a bare message naming neither entry -> red. Both
    # builders must name both entries, because the one a host would have to
    # look for is the one it did not write.
    test "the message is the one from_modules/2 raises, naming both entries" do
      from_new =
        assert_raise ArgumentError, fn ->
          Palette.new(%{"toy.seventh" => Seventh, "toy.also_seventh" => AlsoSeventh})
        end

      from_modules =
        assert_raise ArgumentError, fn ->
          Palette.from_modules([{"toy.seventh", Seventh}, {"toy.also_seventh", AlsoSeventh}])
        end

      assert from_new.message == from_modules.message
      assert from_new.message =~ ~s("toy.seventh")
      assert from_new.message =~ ~s("toy.also_seventh")
      assert from_new.message =~ ~s(group "Structure")
    end

    # sabotage: check only `types` in new/2, dropping the recipes argument
    # -> red. The browser draws types and recipes into one group, so the
    # two maps are checked together here as they are in from_modules/2.
    test "a recipe colliding with a type is refused through the :recipes option" do
      assert_raise ArgumentError, ~r/both declare order 7/, fn ->
        Palette.new(%{"toy.seventh" => Seventh}, recipes: %{"seventh" => SeventhRecipe})
      end
    end

    # sabotage: refuse an entry that declares no `order` -> red on
    # `core/0`, on every fixture palette, and here. `order` is optional and
    # a gap is legal; only the collision is refused.
    test "the core palette, and an entry declaring no order, build unrefused" do
      assert %Palette{} = Palette.core()
      assert %Palette{} = Palette.new(%{"toy.budget_check" => Toy, "toy.minimal" => Minimal})
    end

    # The one admitted pair: a composite beside its OWN derived recipe. The
    # derived recipe's palette_entry/0 IS the block type's, so registering
    # both - which `StatifierBlocks.Composite` documents as a host's choice
    # to show two - is one declaration read twice, not two entries
    # disagreeing about a number.
    #
    # sabotage: dropped the derived_pair?/2 arm from collision?/1 -> red on
    # both builders, and on composite_test.exs's registration test with it.
    test "a composite beside its own derived recipe is admitted, by both builders" do
      assert %Palette{} =
               Palette.new(%{"myapp.signup_step" => SignupStep},
                 recipes: %{"signup_step" => SignupStep.Recipe}
               )

      assert %Palette{} =
               Palette.from_modules([{"myapp.signup_step", SignupStep}],
                 recipes: [{"signup_step", SignupStep.Recipe}]
               )
    end

    # sabotage: identified the pair by palette_entry equality alone -> red,
    # because two unrelated modules declaring one card would then be
    # admitted. The exemption is the composite's own derived recipe, and
    # nothing else at that number.
    test "an unrelated pair at one order is still refused, by both builders" do
      assert_raise ArgumentError, ~r/both declare order 7/, fn ->
        Palette.new(%{"toy.seventh" => Seventh}, recipes: %{"seventh" => SeventhRecipe})
      end

      assert_raise ArgumentError, ~r/both declare order 7/, fn ->
        Palette.from_modules([{"toy.seventh", Seventh}], recipes: [{"seventh", SeventhRecipe}])
      end
    end

    # sabotage: identified the pair by the module name alone
    # (`Module.concat(module, "Recipe")`) -> red. `Seventh.Recipe` sits at
    # the derived name and declares a card of its own, so the name is only
    # half the question.
    test "a module at the derived name that declares its own card is refused" do
      assert_raise ArgumentError, ~r/both declare order 7/, fn ->
        Palette.new(%{"toy.seventh" => Seventh}, recipes: %{"seventh" => Seventh.Recipe})
      end
    end
  end

  describe "hygiene: no global state anywhere in palette.ex" do
    @lib_file "lib/statifier_blocks/palette.ex"

    defp read_file(path) do
      __DIR__ |> Path.join("../../#{path}") |> Path.expand() |> File.read!()
    end

    # sabotage: append a trailing "# Agent" comment line to palette.ex ->
    # this test goes red on the added literal
    test "palette.ex names no global-state mechanism" do
      forbidden =
        ~r/Application\.get_env|:ets\.|Process\.whereis|GenServer|Agent|:persistent_term/

      refute read_file(@lib_file) =~ forbidden
    end

    # sabotage: add a `Document.to_json(block)` call anywhere in
    # palette.ex -> this test goes red. The regex is call-shaped (an open
    # paren) on purpose: the `resolve/2` @doc names `Document.to_json/1`
    # in arity spelling to say it is never called, and prose saying so
    # must not trip the scan that enforces it.
    test "palette.ex never persists: no to_json/1, from_json/1, or file write" do
      forbidden = ~r/to_json\(|from_json\(|File\.write|File\.open|:file\./

      refute read_file(@lib_file) =~ forbidden
    end
  end
end
