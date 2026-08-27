defmodule StatifierBlocks.PaletteTest do
  use ExUnit.Case, async: true

  alias StatifierBlocks.BlockTypeFixtures
  alias StatifierBlocks.BlockTypeFixtures.{Minimal, Toy}
  alias StatifierBlocks.Palette

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
      given = %{"toy.score" => Toy}
      assert Palette.new(given) == %Palette{types: given}
    end
  end

  describe "fetch/2" do
    # sabotage: change fetch/2's success clause to return `:ok` instead of
    # `{:ok, module}` -> this assertion goes red
    test "returns {:ok, module} for a name the palette carries" do
      assert Palette.fetch(BlockTypeFixtures.palette(), "toy.score") == {:ok, Toy}
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
      palette_a = Palette.new(%{"toy.score" => Toy})
      palette_b = Palette.new(%{"toy.score" => Minimal})

      assert Palette.fetch(palette_a, "toy.score") == {:ok, Toy}
      assert Palette.fetch(palette_b, "toy.score") == {:ok, Minimal}
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
  end
end
