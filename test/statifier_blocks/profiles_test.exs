defmodule StatifierBlocks.ProfilesTest do
  @moduledoc """
  The shell's half of the `profile` assign, asserted with LiveView absent.

  ADR-0005's 2026-09-07 profile amendment decides two things this module can
  answer without a socket: which of the package's tabs a list leaves, and what
  happens to a list member the package cannot resolve. Both are decisions with
  return values, so both belong in the headless tree beside the rest of
  `StatifierBlocks.Shell` - which is why the mount-level claims (no palette, no
  drag hook, values instead of controls) are in
  `StatifierBlocks.Editor.ProfileTest` and nothing here needs a render.

  Deliberately **not** tagged `:liveview`.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.Shell

  describe "the tab lists a profile leaves" do
    test ":all is every tab, in the package's order" do
      assert Shell.drawer_tabs(:all) == Shell.drawer_tabs()
      assert Shell.inspector_tabs(:all) == Shell.inspector_tabs()
    end

    test "a list naming one tab leaves one" do
      assert Shell.drawer_tabs([:findings]) == [:findings]
      assert Shell.inspector_tabs([:findings]) == [:findings]
    end

    test "the order is the package's, not the profile's" do
      assert Shell.drawer_tabs([:source, :tables]) == [:tables, :source]
      assert Shell.inspector_tabs([:fixtures, :config]) == [:config, :fixtures]
    end

    test "a list naming nothing leaves nothing" do
      assert Shell.drawer_tabs([]) == []
      assert Shell.inspector_tabs([]) == []
    end
  end

  describe "an id the package does not know" do
    test "is dropped rather than raised" do
      assert Shell.drawer_tabs([:findings, :nope]) == [:findings]
      assert Shell.inspector_tabs([:findings, :nope]) == [:findings]
    end

    test "leaves the ids beside it" do
      assert Shell.drawer_tabs([:nope, :tables, :also_nope, :source]) == [:tables, :source]
    end

    test "a host tab id is not one of the package's" do
      # Host ids stay strings the whole way through, so a profile naming one
      # matches nothing here: the filter for those runs in `drawer_view/1`,
      # where the host's descriptors are.
      assert Shell.drawer_tabs(["runs"]) == []
    end
  end

  describe "drawer_view/1 with a profile" do
    test "draws only the package tabs the profile lists" do
      view = Shell.drawer_view(%{profile: [:findings, :source]})

      assert Enum.map(view.tabs, & &1.id) == [:findings, :source]
    end

    test "no profile draws all six, as it always did" do
      assert Enum.map(Shell.drawer_view(%{}).tabs, & &1.id) == Shell.drawer_tabs()
    end

    test "filters the host's own tabs by the same list" do
      hosts = [%{id: "runs", title: "Runs", count: 2}, %{id: "jobs", title: "Jobs", count: 0}]

      view = Shell.drawer_view(%{host_tabs: hosts, profile: [:findings, "jobs"]})

      assert Enum.map(view.tabs, & &1.id) == [:findings, "jobs"]
    end

    test "a host tab the profile does not name is dropped, and an unknown id is too" do
      hosts = [%{id: "runs", title: "Runs", count: 2}]

      view = Shell.drawer_view(%{host_tabs: hosts, profile: [:tables, "nope"]})

      assert Enum.map(view.tabs, & &1.id) == [:tables]
    end

    test "a strip the profile left empty renders with no tabs and no active one" do
      view = Shell.drawer_view(%{profile: []})

      assert view.tabs == []
      assert view.tab == nil
      assert view.count == 0
      assert view.title == ""
    end

    test "the resting tab is the first the profile left, not :tables" do
      view = Shell.drawer_view(%{profile: [:source, :declarations]})

      assert view.tab == :declarations
    end
  end
end
