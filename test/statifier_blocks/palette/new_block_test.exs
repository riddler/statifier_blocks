defmodule StatifierBlocks.Palette.NewBlockTest do
  @moduledoc """
  `Palette.new_block/2`: what "insert this type" means as a value.

  This was the editor's own private helper until sb-zjyv moved it here. The
  behaviour is unchanged and deliberately so - the config is the type's
  `config_schema/1` defaults and nothing else, and the stored `type_version`
  is the module's `current_version/0`. A palette entry's `:default_config` is
  a separate declaration and is not merged in; that is the editor's insert
  probe, and sb-3mv1 is where whether an insert should adopt it is asked.

  Pure: no editor, no LiveView, so no `Code.ensure_loaded?` guard.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, InsertProbeFixtures, Palette}
  alias StatifierBlocks.BlockTypeFixtures.Toy

  doctest StatifierBlocks.Palette, only: [new_block: 2]

  describe "new_block/2" do
    # sabotage: drop the `type_version:` option from `new_block/2`'s
    # `Block.new/2` call -> the type_version assertion goes red (the block
    # would carry Block.new's own default instead of the module's current)
    test "builds a block of the named type at the module's current version" do
      palette = Palette.new(%{"toy.budget_check" => Toy})

      assert {:ok, %Block{} = block} = Palette.new_block(palette, "toy.budget_check")
      assert block.type == "toy.budget_check"
      assert block.type_version == Toy.current_version()
    end

    # sabotage: build the config from `%{}` instead of folding the schema's
    # `default:` values -> this goes red
    test "the config is the schema's defaults, key by key" do
      palette = Palette.new(%{"toy.budget_check" => Toy})

      expected =
        %{}
        |> Toy.config_schema()
        |> Map.new(fn %{key: key, default: default} -> {key, default} end)

      assert {:ok, block} = Palette.new_block(palette, "toy.budget_check")
      assert block.config == expected
    end

    # sabotage: make the unknown arm raise or return `{:error, _}` instead of
    # `:error` -> this goes red. `fetch/2`'s totality is the reason.
    test "a type_name no entry carries is :error, never a raise" do
      palette = Palette.new(%{"toy.budget_check" => Toy})

      assert Palette.new_block(palette, "toy.absent") == :error
      assert Palette.new_block(Palette.new(), "toy.budget_check") == :error
    end

    # sabotage: mint the id outside `Block.new/2` (a constant, say) -> this
    # goes red. Two inserts of one type are two blocks, not one twice.
    test "each call mints its own id" do
      palette = Palette.new(%{"toy.budget_check" => Toy})

      assert {:ok, one} = Palette.new_block(palette, "toy.budget_check")
      assert {:ok, two} = Palette.new_block(palette, "toy.budget_check")
      refute one.id == two.id
    end

    # sabotage: merge `BlockType.default_config(module.palette_entry())` into
    # the config here -> this goes red. That merge is the editor's insert
    # probe (sb-1c7g) and an open design question for the insert (sb-3mv1),
    # not this function's behaviour today.
    test "a palette entry's :default_config is not merged in" do
      palette = InsertProbeFixtures.palette()
      module = InsertProbeFixtures.SettleFinal

      schema_defaults =
        %{}
        |> module.config_schema()
        |> Map.new(fn %{key: key, default: default} -> {key, default} end)

      assert {:ok, block} = Palette.new_block(palette, "cards.settle_final")
      assert block.config == schema_defaults
      assert block.config != Map.merge(schema_defaults, module.palette_entry().default_config)
    end
  end
end
