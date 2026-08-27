defmodule StatifierBlocks.PaletteTest do
  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, BlockTypeFixtures, Document, DocumentFixtures, Palette}
  alias StatifierBlocks.BlockTypeFixtures.{Minimal, Toy}

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
