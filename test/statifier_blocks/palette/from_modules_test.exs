defmodule StatifierBlocks.Palette.FromModulesTest do
  @moduledoc """
  The registration API a host uses to contribute its own block types:
  an ordered, explicit list handed in where the editor is mounted.

  The properties under test are the ones that make it a registration
  surface rather than a second spelling of `Palette.new/2` - the core
  vocabulary as an opt-in base, declaration order deciding a collision,
  and a malformed entry refused loudly at mount rather than quietly
  dropped. The negative space matters as much: the result is a plain
  value, so nothing is registered anywhere a second palette could see it.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{AssignabilityFixtures, BlockTypeFixtures, Palette}

  @host BlockTypeFixtures.Minimal

  defmodule Seventh do
    @moduledoc "A palette entry declaring `order: 7` in the Structure group."
    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1
    @impl true
    def slots(_config), do: []
    @impl true
    def config_schema(_config), do: []
    @impl true
    def validate_config(_config), do: :ok
    @impl true
    def io(_config), do: %{kinds: [:step]}
    @impl true
    def emit(%StatifierBlocks.Block{id: id}, _context), do: {:error, {:not_implemented, id}}
    @impl true
    def palette_entry, do: %{label: "Seventh", group: "Structure", order: 7}
  end

  defmodule SeventhElsewhere do
    @moduledoc "The same number in a different group, which is not a collision."
    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1
    @impl true
    def slots(_config), do: []
    @impl true
    def config_schema(_config), do: []
    @impl true
    def validate_config(_config), do: :ok
    @impl true
    def io(_config), do: %{kinds: [:step]}
    @impl true
    def emit(%StatifierBlocks.Block{id: id}, _context), do: {:error, {:not_implemented, id}}
    @impl true
    def palette_entry, do: %{label: "Seventh", group: "Authorization", order: 7}
  end

  defmodule Unordered do
    @moduledoc "A palette entry declaring a group but no order."
    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1
    @impl true
    def slots(_config), do: []
    @impl true
    def config_schema(_config), do: []
    @impl true
    def validate_config(_config), do: :ok
    @impl true
    def io(_config), do: %{kinds: [:step]}
    @impl true
    def emit(%StatifierBlocks.Block{id: id}, _context), do: {:error, {:not_implemented, id}}
    @impl true
    def palette_entry, do: %{label: "Unordered", group: "Structure"}
  end

  describe "from_modules/2" do
    # Sabotage: had `from_modules/2` ignore its list and return
    # `new(base, opts)` - red here (verified).
    test "registers each entry under the name it carries" do
      palette = Palette.from_modules([{"myapp.risk_hold", @host}])

      assert Palette.fetch(palette, "myapp.risk_hold") == {:ok, @host}
      assert palette.types == %{"myapp.risk_hold" => @host}
    end

    # Sabotage: made `:core` default to `true` - red on the empty-palette
    # assert, which is what keeps the core vocabulary opt-in (verified).
    test "the core vocabulary is opt-in, not the default base" do
      without = Palette.from_modules([{"myapp.risk_hold", @host}])
      with_core = Palette.from_modules([{"myapp.risk_hold", @host}], core: true)

      assert Palette.fetch(without, "core.sequence") ==
               {:error, {:unknown_block_type, "core.sequence"}}

      assert {:ok, _module} = Palette.fetch(with_core, "core.sequence")
      assert Palette.fetch(with_core, "myapp.risk_hold") == {:ok, @host}
      assert map_size(with_core.types) == map_size(Palette.core_types()) + 1
    end

    # Sabotage: reduced the list with `Map.put_new/3` instead of
    # `Map.put/3` - red on both rows, since a host's deliberate override
    # would then lose to the base it was written after (verified).
    test "later entries win, over the core base and over each other" do
      palette =
        Palette.from_modules(
          [
            {"core.wait", @host},
            {"myapp.risk_hold", StatifierBlocks.Core.Wait},
            {"myapp.risk_hold", @host}
          ],
          core: true
        )

      assert Palette.fetch(palette, "core.wait") == {:ok, @host}
      assert Palette.fetch(palette, "myapp.risk_hold") == {:ok, @host}
    end

    # Sabotage: dropped the `opts` pass-through to `new/2` - red here
    # (verified).
    test "passes :assignability through to new/2" do
      palette = Palette.from_modules([], assignability: AssignabilityFixtures.Widens)

      assert palette.assignability == AssignabilityFixtures.Widens
      assert Palette.from_modules([]).assignability == nil
    end

    # Sabotage: replaced the raising `register/2` clause with one that
    # returned `types` unchanged - red here, and a palette silently missing
    # a type the host believes it registered is the failure this refuses
    # (verified).
    test "refuses a malformed entry at mount rather than dropping it" do
      for entry <- [@host, {@host, "myapp.risk_hold"}, {"myapp.risk_hold"}, {"", @host}, nil] do
        assert_raise ArgumentError, fn -> Palette.from_modules([entry]) end
      end
    end

    # Sabotage: made `from_modules/2` call `Code.ensure_loaded!/1` on each
    # module - red here, since a palette is a value that may name a module
    # compiled later and every consumer already carries the unresolvable
    # case (verified). The duplicate-`order` check added 2026-09-07 does
    # reach a module it can already load, and skips one it cannot, which is
    # what keeps this property true.
    test "does not resolve a module it cannot load, or assert the behaviour" do
      never_compiled = Module.concat([:MyApp, :NotCompiledYet])
      palette = Palette.from_modules([{"myapp.not_compiled_yet", never_compiled}])

      assert Palette.fetch(palette, "myapp.not_compiled_yet") == {:ok, never_compiled}
    end

    # Sabotage: had `from_modules/2` stash its result in the process
    # dictionary and read it back on the next call - red here, which is the
    # mechanical half of "no global registry" (verified).
    test "registers nothing anywhere a second palette can see" do
      first = Palette.from_modules([{"myapp.risk_hold", @host}])
      second = Palette.from_modules([{"myapp.settle", @host}])

      assert Palette.fetch(second, "myapp.risk_hold") ==
               {:error, {:unknown_block_type, "myapp.risk_hold"}}

      assert Palette.fetch(first, "myapp.settle") ==
               {:error, {:unknown_block_type, "myapp.settle"}}
    end

    # Sabotage: had `from_modules([], core: true)` return `new(%{})` - red
    # here (verified).
    test "an empty list is the empty palette, or the core one" do
      assert Palette.from_modules([]).types == %{}
      assert Palette.from_modules([], core: true).types == Palette.core_types()
    end
  end

  describe "from_modules/2 and a duplicate order" do
    # Sabotage: dropped the `refute_duplicate_orders!/2` call from
    # `from_modules/2` - red here (verified). ADR-0005 decision 10 sorts a
    # browser group by `order`, so two entries claiming one number leave
    # their relative position to whatever the sort happened to do.
    test "refuses two entries of one group declaring the same order" do
      error =
        assert_raise(ArgumentError, fn ->
          Palette.from_modules([{"myapp.seventh", Seventh}], core: true)
        end)

      assert error.message =~ "Structure"
      assert error.message =~ "7"
    end

    # Sabotage: had the message name only the entry being registered - red
    # on the "core.invoke" row, which is the half a host cannot find on its
    # own, since it did not write it.
    test "the message names both entries, by name and module" do
      error =
        assert_raise(ArgumentError, fn ->
          Palette.from_modules(
            [{"myapp.seventh", Seventh}, {"myapp.also_seventh", SeventhElsewhere}],
            recipes: [{"myapp.third", Seventh}]
          )
        end)

      assert error.message =~ ~s("myapp.seventh")
      assert error.message =~ ~s("myapp.third")
      assert error.message =~ inspect(Seventh)
    end

    # Sabotage: keyed the grouping on `order` alone rather than on
    # `{group, order}` - red here, and a palette a host legitimately built
    # would stop mounting (verified).
    test "the same number in two different groups is not a collision" do
      palette = Palette.from_modules([{"myapp.elsewhere", SeventhElsewhere}], core: true)

      assert Palette.fetch(palette, "myapp.elsewhere") == {:ok, SeventhElsewhere}
    end

    # Sabotage: made `ordered_entry/1` answer `[{group, nil, ...}]` for an
    # entry with no `order` - two such entries would then collide on `nil`
    # and this goes red. `order` is an optional key on `palette_entry/0`.
    test "an entry declaring no order, and one whose module is not compiled, are skipped" do
      never_compiled = Module.concat([:MyApp, :NotCompiledYetEither])

      palette =
        Palette.from_modules(
          [
            {"myapp.unordered", Unordered},
            {"myapp.also_unordered", Unordered},
            {"myapp.absent", never_compiled}
          ],
          core: true
        )

      assert Palette.fetch(palette, "myapp.absent") == {:ok, never_compiled}
    end

    # Sabotage: restored `order: 7` on `StatifierBlocks.Core.DeadlineRecipe`
    # (it collided with `core.invoke` until 2026-09-07) - red here and on
    # every `core: true` test above, which is how the collision is kept gone
    # rather than merely fixed once.
    test "the core vocabulary declares no duplicate order within a group" do
      entries =
        Palette.core_types()
        |> Map.merge(Palette.core_recipes())
        |> Enum.map(fn {name, module} -> {module.palette_entry(), name} end)
        |> Enum.filter(fn {entry, _name} -> Map.has_key?(entry, :order) end)
        |> Enum.map(fn {entry, name} -> {{entry.group, entry.order}, name} end)

      assert entries != []
      assert length(Enum.uniq_by(entries, &elem(&1, 0))) == length(entries)
    end
  end
end
