defmodule StatifierBlocks.AssetsTest do
  @moduledoc """
  ADR-0005 decisions 1, 7 and 14 - and decision 7's 2026-08-29 amendment,
  "a second hook that only measures" - held against the files rather than
  against reviewer memory.

  Deliberately **not** tagged `:liveview`. Everything here reads a file off
  disk, so it runs in the headless tree too - which is where it matters most,
  because the headless tree is the one that proves the package ships without
  Phoenix, and `assets/` is the part of the package that a `files:` list is
  easiest to forget.
  """

  use ExUnit.Case, async: true

  @hook_source "assets/js/statifier_blocks.js"
  @measure_source "assets/js/statifier_blocks_measure.js"

  # Every file in `assets/js/`, so a third hook cannot arrive by arriving in a
  # third file the scan below was never told about.
  @sources [@hook_source, @measure_source]

  describe "the two hooks, and no more (decision 7, as amended 2026-08-29)" do
    # Sabotage: adding a third `export const SomethingElse = { mounted() ... }`
    # to either source - `hooks/0` returns three names and this goes red with
    # the record's own sentence.
    test "exactly the two hooks the record names are exported" do
      assert hooks() == ["StatifierBlocksDrag", "StatifierBlocksMeasure"], """
      ADR-0005 decision 7 shipped exactly one JavaScript hook and made a second
      one an amendment. The 2026-08-29 amendment made it, and admits exactly
      one: `StatifierBlocksMeasure`, whose whole contract is measurement. A
      THIRD hook, or a hook that pushes anything but geometry or a command,
      is still a thing this record does not have - so amend
      `docs/adr/0005-liveview-editor.md` first, then this test.

      Found: #{inspect(hooks())}
      """
    end

    # The corroborator: a scan over a hard-coded file list says nothing about
    # a file that is not on it.
    # Sabotage: dropping either source from `@sources` - the check above goes
    # quiet about a whole file and this notices.
    test "the scan covers every file in assets/js" do
      assert Enum.sort(Path.wildcard("assets/js/*.js")) == Enum.sort(@sources)
    end
  end

  describe "the measurement hook's whole contract (amendment clause 7a)" do
    # 7a: "it pushes that geometry to the server, and that push is the only
    # thing it sends".
    # Sabotage: adding a second `this.pushEventTo(this.el, "select", ...)` to
    # the measure hook - it has started reporting an author's intent, which is
    # the thing 7b says it can never do, and this goes red.
    test "it makes exactly one push, and that push is the measurement" do
      source = File.read!(@measure_source)
      pushes = Regex.scan(~r/\bpushEvent(?:To)?\s*\(/, source)

      assert length(pushes) == 1, """
      Amendment clause 7a: the geometry push is the ONLY thing this hook
      sends. A second push is either a command - which 7a forbids outright -
      or a second kind of measurement, which is a wire question the record
      left to `sb-k7r` rather than to a quiet addition.

      Found #{length(pushes)} pushes.
      """

      assert source =~ ~s(this.pushEventTo(this.el, "measure", {)
    end

    # 7a: "it issues no commands. It does not push an author intent of any
    # kind." Decision 2's closed command set, named, so this fails on the
    # exact thing it is about rather than on a count.
    # Sabotage: having the measure hook push `"drop"` - decision 2's command
    # set has acquired a second source and this goes red naming it.
    test "it issues none of the editor's commands" do
      source = File.read!(@measure_source)

      for command <- ~w(dragstart dragend drop select remove undo redo config-change) do
        refute source =~ ~s("#{command}"),
               "clause 7a: the measurement hook issues no commands, and #{command} is one"
      end
    end

    # 7a: "it never mutates the DOM. It writes no node, no attribute, no
    # style, and no class; it does not draw the connectors it makes drawable."
    # Sabotage: having the hook draw the paths itself with `appendChild` - the
    # geometry stops being computed on the server (7b.2) and this goes red.
    test "it writes no node, no attribute, no style and no class" do
      source = File.read!(@measure_source)

      writers =
        ~w(appendChild insertBefore removeChild replaceChild insertAdjacentHTML) ++
          ~w(innerHTML outerHTML textContent setAttribute removeAttribute classList)

      for writer <- writers do
        refute source =~ writer,
               "clause 7a: this hook reads boxes and pushes them, it does not draw (#{writer})"
      end

      refute source =~ ~r/\.style\b/,
             "clause 7a: the hook writes no style - the server renders the overlay"
    end

    # 7c: what may be observed is the geometry of a server-stamped anchor plus
    # the stage's own extent, and nothing else. The DOM contract it reads is
    # decision 7's, extended by exactly one attribute.
    # Sabotage: having the hook read `data-block-id` and compose its own key -
    # the key stops being opaque, a block id containing the separator splits
    # wrong on the server, and this goes red.
    test "it reads one stamped attribute and composes no key of its own" do
      source = File.read!(@measure_source)

      assert source =~ "data-sb-anchor"

      for attribute <- ~w(data-block-id data-slot data-parent-id data-index data-drop) do
        refute source =~ attribute,
               "clause 7c: the anchor key is opaque to the hook, so it needs no other part " <>
                 "of the DOM contract (#{attribute})"
      end
    end

    # Sabotage: adding `import { something } from "phoenix"` - the
    # source-delivery model sui-ADR-0009 permits for a self-contained hook no
    # longer applies, exactly as it would not for the drag hook.
    test "it is self-contained, which is what lets it ship as source" do
      refute File.read!(@measure_source) =~ ~r/^\s*import\s/m,
             "sui-ADR-0009 bans source-shipped hooks that pull dependencies"
    end

    # The amendment's consequence: "`assets/` acquires a second entry point,
    # with the versioned-public-API obligations sui-ADR-0009 already places on
    # the first."
    # Sabotage: dropping the `./measure` export from assets/package.json - a
    # host's `import { StatifierBlocksMeasure } from "statifier_blocks/measure"`
    # resolves to nothing, which no other test would notice.
    test "the second entry point is a named export a host can import" do
      package = "assets/package.json" |> File.read!() |> Jason.decode!()

      assert package["exports"]["./measure"] == "./js/statifier_blocks_measure.js"
      assert "js/statifier_blocks_measure.js" in package["files"]
      assert File.read!(@measure_source) =~ "export const StatifierBlocksMeasure = {"
    end
  end

  describe "the command hook (decision 7)" do
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
      assert File.regular?(@measure_source)
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

  # Every hook exported by every file in `assets/js/`, in file order and then
  # source order. Read off the files rather than off a list here: a list here
  # is the thing that would silently need updating and would not get it.
  defp hooks do
    Enum.flat_map(@sources, fn source ->
      ~r/^export const (\w+) = \{/m
      |> Regex.scan(File.read!(source))
      |> Enum.map(fn [_all, name] -> name end)
    end)
  end
end
