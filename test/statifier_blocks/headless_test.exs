defmodule StatifierBlocks.HeadlessTest do
  @moduledoc """
  ADR-0005 decision 1's acceptance property, asserted from inside the suite:
  **the package compiles clean, and the full headless test suite passes, with
  `phoenix_live_view` absent from the dependency tree.**

  A guard that is never exercised without the dependency present is a guard
  that is already broken, which is why the record puts this in CI as its own
  job. This module is the other half of that job: the CI step proves the tree
  resolves and compiles, and these tests prove the tree it resolved is the one
  it was supposed to.

  Both directions are asserted, and that is the point. With the flag set,
  `Phoenix.LiveView` must be genuinely absent *and* `StatifierBlocks.Editor`
  must genuinely not have compiled - a headless job that quietly still had
  LiveView on the path would otherwise pass while proving nothing. Without the
  flag, both must be present, so an ordinary run notices if the guard has
  started excluding the editor by accident.

  Deliberately not tagged `:liveview`: this is the test that has to run in
  both trees.
  """

  use ExUnit.Case, async: true

  @headless System.get_env("STATIFIER_BLOCKS_HEADLESS") in ["1", "true"]

  @guarded [
    StatifierBlocks.Editor,
    StatifierBlocks.Editor.Canvas,
    StatifierBlocks.Editor.BlockNode,
    StatifierBlocks.Editor.Slot,
    StatifierBlocks.Editor.ConfigForm,
    StatifierBlocks.Editor.Field,
    StatifierBlocks.Editor.PaletteBrowser,
    StatifierBlocks.Editor.Findings,
    StatifierBlocks.Editor.Toolbar,
    StatifierBlocks.Editor.Inspector,
    StatifierBlocks.Editor.Drawer
  ]

  @pure [
    StatifierBlocks.Edit,
    StatifierBlocks.Edit.History,
    StatifierBlocks.Edit.Targets,
    StatifierBlocks.Finding,
    StatifierBlocks.Datamodel,
    StatifierBlocks.ViewModel,
    StatifierBlocks.Shell
  ]

  if @headless do
    # Sabotage: removing the `if Code.ensure_loaded?(Phoenix.LiveView)` wrapper
    # from any Editor module - the headless tree then fails to compile at all,
    # which is a louder version of this going red.
    test "with the flag set, LiveView is absent and no Editor module compiled" do
      refute Code.ensure_loaded?(Phoenix.LiveView),
             "STATIFIER_BLOCKS_HEADLESS is set but phoenix_live_view resolved anyway - " <>
               "the headless job is proving nothing"

      for module <- @guarded do
        refute Code.ensure_loaded?(module),
               "#{inspect(module)} compiled without Phoenix, so its guard is not doing its job"
      end
    end
  else
    # Sabotage: guarding a module under `StatifierBlocks.Editor.*` on the wrong
    # condition - it stops compiling in the ordinary tree and this goes red.
    test "with the flag unset, LiveView is present and every Editor module compiled" do
      assert Code.ensure_loaded?(Phoenix.LiveView)

      for module <- @guarded do
        assert Code.ensure_loaded?(module), "#{inspect(module)} did not compile"
      end
    end
  end

  # Sabotage: adding an `alias Phoenix.Component` to `StatifierBlocks.ViewModel`
  # - the namespace boundary decision 1 made load-bearing is broken and this
  # goes red naming the file.
  test "no module outside StatifierBlocks.Editor.* names Phoenix" do
    offenders =
      "lib/**/*.ex"
      |> Path.wildcard()
      |> Enum.reject(&String.starts_with?(&1, "lib/statifier_blocks/editor"))
      |> Enum.filter(fn path -> File.read!(path) =~ ~r/\bPhoenix\b/ end)

    assert offenders == [], """
    ADR-0005 decision 1: `StatifierBlocks.Editor.*` is the only place Phoenix
    may be named, and that includes the pure view model - which is why it is
    not under that namespace. The boundary is load-bearing rather than
    decorative: a Phoenix reference outside it breaks the headless tree.

    Offending files: #{inspect(offenders)}
    """
  end

  # Sabotage: moving `StatifierBlocks.ViewModel` under the Editor namespace -
  # it stops being available to the pure half and this goes red.
  test "the pure half is always available, in either tree" do
    for module <- @pure do
      assert Code.ensure_loaded?(module),
             "#{inspect(module)} is outside the guard by design (decision 13) and must load"
    end
  end
end
