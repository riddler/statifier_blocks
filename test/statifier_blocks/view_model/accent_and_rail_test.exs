defmodule StatifierBlocks.ViewModel.AccentAndRailTest do
  @moduledoc """
  The presentation derivations the campaign-012/013 spike proved and this
  package graduated: the per-block-type accent token (ADR-0005 decision 14's
  `accent_token`, consumption side), the rail partition, the boundary box
  derived from it (amendment 10c as amended by 10h), the exit edge each rail
  leaves by (10h's last row, per the `sb-67s` ruling), and 10i's resolution
  of a style this editor does not know.

  All of them are pure functions of metadata already on the view model, so they
  are asserted here with LiveView absent from the dependency tree - which is
  the same split decision 5 makes for drop-target validity and the reason the
  markup tests beside them have so little left to check.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Document, Palette, ViewModel}

  doctest StatifierBlocks.ViewModel, only: [accent_token: 1]

  defp container(slots) do
    %ViewModel.Node{
      block_id: "blk_1",
      type: "core.group",
      type_version: 1,
      status: :ok,
      slots: slots
    }
  end

  defp slot(name, style) do
    %ViewModel.Slot{name: name, label: name, declared?: true, style: style}
  end

  defmodule Newer do
    @moduledoc """
    A host type declaring a `slot_style` this editor does not have - a host
    built against a newer record, or a typo. 10i's whole subject.
    """

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1

    @impl true
    def slots(_config), do: [{"body", :zero_or_more, "Body"}]

    @impl true
    def config_schema(_config), do: []

    @impl true
    def validate_config(_config), do: :ok

    @impl true
    def emit(%Block{id: id}, _context), do: {:ok, {:emitted, id}}

    @impl true
    def palette_entry, do: %{label: "Charge the card", slot_style: %{"body" => :sidecar}}
  end

  defmodule Malformed do
    @moduledoc "The same defect one level up: a `slot_style` that is not a map."

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1

    @impl true
    def slots(_config), do: [{"body", :zero_or_more, "Body"}]

    @impl true
    def config_schema(_config), do: []

    @impl true
    def validate_config(_config), do: :ok

    @impl true
    def emit(%Block{id: id}, _context), do: {:ok, {:emitted, id}}

    @impl true
    def palette_entry, do: %{label: "Charge the card", slot_style: "secondary"}
  end

  defp built(module, type_name) do
    document =
      Document.new(
        Block.new(type_name,
          id: "blk_root",
          slots: %{"body" => [Block.new(type_name, id: "blk_child")]}
        ),
        id: "doc_1"
      )

    ViewModel.build(document, Palette.new(%{type_name => module}), [])
  end

  describe "accent_token/1 (14d, consumption side)" do
    # Sabotage: dropping the `Regex.match?/2` guard so any declared string is
    # returned - the injection case below is then interpolated straight into a
    # style attribute, and this goes red on it.
    test "an anchored --sb-* name is returned" do
      assert ViewModel.accent_token(%{accent_token: "--sb-accent-invoke"}) == "--sb-accent-invoke"
      assert ViewModel.accent_token(%{accent_token: "--sb-a1"}) == "--sb-a1"
    end

    # Sabotage: the same mutation - without the pattern check every one of
    # these is returned and interpolated into a style attribute.
    test "anything that is not one degrades to no accent" do
      for declared <- [
            "--accent",
            "--sb-",
            "--sb-Accent",
            "--sb-accent-",
            "--sb--accent",
            "red",
            "--sb-x; background: url(x)",
            "--sb-x\n--sb-y",
            :"--sb-atom",
            42,
            nil
          ] do
        assert ViewModel.accent_token(%{accent_token: declared}) == nil,
               "#{inspect(declared)} must degrade to the editor's own accent"
      end
    end

    # Sabotage: making `accent_token/1` raise on an entry without the key -
    # every block type that declares nothing is then unrenderable, which is
    # every block type that exists today.
    test "an entry that declares nothing has no accent, and neither does a non-map" do
      assert ViewModel.accent_token(%{}) == nil
      assert ViewModel.accent_token(%{label: "Wait"}) == nil
      assert ViewModel.accent_token("not an entry") == nil
    end
  end

  describe "the rail partition (10h)" do
    # Sabotage: `rail?/1` answering true only for `:secondary` - a failure slot
    # goes back into the body flow, which is the rendering 10h changed.
    test "both rail styles are rails, and :primary is not" do
      assert ViewModel.rail?(slot("interrupts", :secondary))
      assert ViewModel.rail?(slot("on_error", :failure))
      refute ViewModel.rail?(slot("body", :primary))
    end
  end

  describe "exit_edge/1 (10h's exit row, per the sb-67s ruling)" do
    # Sabotage: `exit_edge/1` answering `:interrupt` for every rail, which is
    # what the spike did before the ruling - a failure rail was then drawn
    # in-band and drawn leaving out-of-band in the same picture.
    test "a failure rail leaves by the ordinary flow edge" do
      assert ViewModel.exit_edge(slot("on_error", :failure)) == :flow
    end

    # Sabotage: `exit_edge/1` answering `:flow` unconditionally - the dashed
    # escape channel disappears from the interrupt rail, and the two rail
    # vocabularies stop being distinguishable at their exits.
    test "an interrupt rail leaves by the escape channel" do
      assert ViewModel.exit_edge(slot("interrupts", :secondary)) == :interrupt
    end

    # Sabotage: making the function partial on rails - every caller then has
    # to re-derive the rail test before it may ask, which is the branch 10h
    # exists to prevent.
    test "a body slot leaves the way its children already do" do
      assert ViewModel.exit_edge(slot("body", :primary)) == :flow
    end
  end

  describe "an unrecognized slot style (10i)" do
    # Sabotage: passing the declared value straight through - the unknown
    # style reaches the markup, `rail?/1` says false about it anyway, and the
    # DOM then carries a style no stylesheet in the package can read.
    test "it resolves to :primary, so the slot is an ordinary body slot" do
      [slot] = built(Newer, "myapp.capture").root.slots

      assert slot.style == :primary
      refute ViewModel.rail?(slot)
      assert length(slot.children) == 1, "10i keeps the children; it does not drop the slot"
    end

    # Sabotage: reading `entry.slot_style` with `Map.get/3` unguarded - a
    # host whose declaration is malformed one level up takes a `BadMapError`
    # out of a render rather than getting the ordinary card, which is the
    # posture ADR-0002's amendment B3 settled for the metadata trio.
    test "a slot_style that is not a map degrades the same way" do
      [slot] = built(Malformed, "myapp.receipt").root.slots

      assert slot.style == :primary
      refute ViewModel.rail?(slot)
    end
  end

  describe "boundary?/1 (10c, as amended by 10h)" do
    # Sabotage: `boundary?/1` reading `:secondary` rather than the partition -
    # a container whose only rail is a failure path loses the edge its rule is
    # attached to, which is 10c's stated reason for the box.
    test "any rail slot makes the container a boundary" do
      assert ViewModel.boundary?(
               container([slot("body", :primary), slot("interrupts", :secondary)])
             )

      assert ViewModel.boundary?(container([slot("body", :primary), slot("on_error", :failure)]))
    end

    # Sabotage: `boundary?/1` answering true unconditionally - a deep document
    # becomes nested rectangles that read as noise, which is the failure 10c
    # names as its reason for deriving the box from metadata.
    test "a container of body slots only is not" do
      refute ViewModel.boundary?(container([slot("body", :primary), slot("otherwise", :primary)]))
      refute ViewModel.boundary?(container([]))
    end
  end
end
