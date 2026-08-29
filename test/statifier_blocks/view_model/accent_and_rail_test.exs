defmodule StatifierBlocks.ViewModel.AccentAndRailTest do
  @moduledoc """
  The three presentation derivations the campaign-012 spike proved and this
  package graduated: the per-block-type accent token (ADR-0005 decision 14's
  `accent_token`, consumption side), the rail partition, and the boundary box
  derived from it (amendment 10c as amended by 10h).

  All three are pure functions of metadata already on the view model, so they
  are asserted here with LiveView absent from the dependency tree - which is
  the same split decision 5 makes for drop-target validity and the reason the
  markup tests beside them have so little left to check.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.ViewModel

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
