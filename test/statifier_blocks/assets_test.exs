defmodule StatifierBlocks.AssetsTest do
  @moduledoc """
  ADR-0005 decisions 1, 7 and 14, held against the files rather than against
  reviewer memory.

  Deliberately **not** tagged `:liveview`. Everything here reads a file off
  disk, so it runs in the headless tree too - which is where it matters most,
  because the headless tree is the one that proves the package ships without
  Phoenix, and `assets/` is the part of the package that a `files:` list is
  easiest to forget.
  """

  use ExUnit.Case, async: true

  @hook_source "assets/js/statifier_blocks.js"

  describe "the single hook (decision 7)" do
    # Sabotage: adding a second `export const SomethingElse = { mounted() ... }`
    # to the hook source - `hooks` becomes two names and this goes red with
    # the record's own sentence.
    test "exactly one hook is exported, and it is StatifierBlocksDrag" do
      hooks =
        @hook_source
        |> File.read!()
        |> then(&Regex.scan(~r/^export const (\w+) = \{/m, &1))
        |> Enum.map(fn [_all, name] -> name end)

      assert hooks == ["StatifierBlocksDrag"], """
      ADR-0005 decision 7: exactly one JavaScript hook, and adding a second
      requires amending the record. A second hook is the signal that some
      behaviour has started living on the client, which is the thing this
      design is arranged to prevent - so amend `docs/adr/0005-liveview-editor.md`
      first, then this test.

      Found: #{inspect(hooks)}
      """
    end

    # Sabotage: adding `import { something } from "phoenix"` to the hook - the
    # source-delivery model sui-ADR-0009 permits for a self-contained hook no
    # longer applies and this goes red.
    test "the hook is self-contained, which is what lets it ship as source" do
      source = File.read!(@hook_source)

      refute source =~ ~r/^\s*import\s/m,
             "sui-ADR-0009 bans colocated and source-shipped hooks that pull dependencies; " <>
               "StatifierBlocksDrag qualifies only because it imports nothing"
    end

    # Sabotage: having the hook call `this.el.appendChild(...)` - a hook that
    # patches the tree fights LiveView for ownership of the same elements.
    test "the hook never mutates the block tree in the DOM" do
      source = File.read!(@hook_source)

      for mutator <- ~w(appendChild insertBefore removeChild replaceChild innerHTML outerHTML) do
        refute source =~ mutator,
               "decision 7: the server re-renders after every command, so a hook that moved " <>
                 "nodes itself would be fighting LiveView's DOM patching (#{mutator})"
      end
    end

    test "it reads the DOM contract the components stamp" do
      source = File.read!(@hook_source)

      for attribute <- ~w(blockId parentId slot index data-drop data-block-id) do
        assert source =~ attribute
      end
    end
  end

  describe "packaging (decision 1)" do
    # Sabotage: dropping "assets" from `files:` in mix.exs - source that ships
    # as source is only public API if it is actually in the hex tarball, and
    # the record calls this out because the sibling repo has it wrong.
    test "assets is in the hex package's files list" do
      files = Mix.Project.config() |> Keyword.fetch!(:package) |> Keyword.fetch!(:files)

      assert "assets" in files, """
      ADR-0005 decision 1: `assets` must appear in the `files:` list. The hook
      and the stylesheet ship as source (sui-ADR-0009), and source that is not
      in the tarball is not public API however carefully it is versioned.
      """
    end

    test "the files the package promises are actually there" do
      assert File.regular?(@hook_source)
      assert File.regular?("assets/css/statifier_blocks.css")
      assert File.regular?("assets/package.json")
    end

    # Sabotage: pointing `main` in assets/package.json at a path that does not
    # exist - a host's `file:../deps/statifier_blocks` import then resolves to
    # nothing, which no Elixir test would otherwise notice.
    test "assets/package.json's entry points resolve" do
      package = "assets/package.json" |> File.read!() |> Jason.decode!()

      assert File.regular?(Path.join("assets", package["main"]))

      for {_name, path} <- package["exports"] do
        assert File.regular?(Path.join("assets", path))
      end
    end
  end
end
