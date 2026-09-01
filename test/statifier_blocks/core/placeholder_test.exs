defmodule StatifierBlocks.Core.PlaceholderTest do
  @moduledoc """
  What `core.placeholder` *means* (ADR-0002's amendment of 2026-08-31,
  section G10; ADR-0003's, section A3; ADR-0004's, section D5).

  The `:placeholder_block` warning is the compiler's and is tested there.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Assignability, Block, Emission}
  alias StatifierBlocks.Compiler.Context
  alias StatifierBlocks.Core.Placeholder

  describe "the declarations" do
    # Sabotage: gave `slots/1` a `"body"` slot - red here. A marker with a
    # slot is a container, and a gap an author can fill in place is not the
    # thing G10 describes.
    test "a leaf with one prose field" do
      assert Placeholder.slots(%{}) == []
      assert Placeholder.current_version() == 1

      assert [%{key: "note", type: :string, required?: false, default: ""} = field] =
               Placeholder.config_schema(%{})

      assert field.label == "What goes here"
    end

    # Sabotage: made `io/1` return `%{kinds: [:step], produces: "myapp.x"}`
    # - red here, and a gap that named what it produced would refuse its own
    # neighbours, which is A3's whole argument.
    test "io/1 is decision 5's permissive default, taken in full" do
      assert Assignability.io(Placeholder, %{}) == %{}
      assert Assignability.kinds(Placeholder, %{}) == [:step]
    end

    # Sabotage: made `validate_config/1` refuse an empty note - red here.
    # An unexplained gap is still a gap, and refusing one makes the marker
    # more expensive to place than leaving the hole unmarked (G10b).
    test "an absent or empty note is accepted; a non-string note is not" do
      assert Placeholder.validate_config(%{}) == :ok
      assert Placeholder.validate_config(%{"note" => ""}) == :ok
      assert Placeholder.validate_config(%{"note" => "the refund arm"}) == :ok

      assert {:error, [{"note", message}]} = Placeholder.validate_config(%{"note" => 7})
      assert message != ""
    end

    # Sabotage: added `icon: "bars-3"` - not red, which is why the absence
    # is asserted rather than left implied: the icon seam draws no tile for
    # a nameless entry, and a gap drawing no glyph is the intended reading.
    test "no icon is declared" do
      entry = Placeholder.palette_entry()

      refute Map.has_key?(entry, :icon)
      assert entry.label == "Placeholder"
    end
  end

  describe "the emission" do
    # Sabotage: added an `<onentry><log/></onentry>` to the emitted state -
    # red on the child count. A marker that announced itself into the chart
    # would be one the author had to remember to remove (D5).
    test "one compound state whose initial is a single final, and nothing else" do
      block = Block.new("core.placeholder", id: "blk_GAP", config: %{"note" => "the refund arm"})
      context = Context.new("blk_GAP", "bdoc_T")

      assert {:ok, %Emission{name: "state", attributes: attributes, children: children}} =
               Placeholder.emit(block, context)

      assert [%Emission{name: "final", attributes: final_attributes}] = children
      assert {"initial", initial} = List.keyfind(attributes, "initial", 0)
      assert {"id", ^initial} = List.keyfind(final_attributes, "id", 0)
    end
  end
end
