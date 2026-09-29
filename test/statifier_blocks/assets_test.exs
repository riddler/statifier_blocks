defmodule StatifierBlocks.AssetsTest do
  @moduledoc """
  ADR-0005 decisions 1, 7 and 14 - decision 7's 2026-08-29 amendment, "a
  second hook that only measures", and its 2026-09-28 amendment, "one hook
  pushes commands; any number of hooks may only measure or draw" - and
  ADR-0018 (b)'s vendored elkjs, held against the files rather than against
  reviewer memory.

  Deliberately **not** tagged `:liveview`. Everything here reads a file off
  disk, so it runs in the headless tree too - which is where it matters most,
  because the headless tree is the one that proves the package ships without
  Phoenix, and `assets/` is the part of the package that a `files:` list is
  easiest to forget.
  """

  use ExUnit.Case, async: true

  @hook_source "assets/js/statifier_blocks.js"
  @measure_source "assets/js/statifier_blocks_measure.js"
  @map_source "assets/js/statifier_blocks_map.js"
  @stylesheet "assets/css/statifier_blocks.css"
  @elk "assets/vendor/elk.bundled.js"
  @elk_licence "assets/vendor/elkjs-LICENSE.md"
  @vendor_manifest ".claude/firewall-vendor.txt"

  # Every file in `assets/js/`, so a hook cannot arrive by arriving in a file
  # the scan below was never told about.
  @sources [@hook_source, @measure_source, @map_source]

  # The one hook that pushes commands (decision 7, 7e).
  @command_hook "StatifierBlocksDrag"

  # The one event name a measuring hook pushes: the geometry (7a).
  @measurement "measure"

  # Decision 2's commands and every event name the command hook pushes,
  # which is what a second command set would be made of, and the reference
  # host's list event names: a draw-only hook names none of them, because
  # every name it pushes is the host's.
  @command_names ~w(dragstart dragend drop insert-drop insert-dragstart select remove undo
                    redo config-change insert move)
  @list_event_names ~w(select-row insert-open)

  describe "one hook pushes commands; the others only measure or draw (decision 7, 7e)" do
    # Sabotage: having the map hook push `this.pushEvent("select-row", ...)`
    # - a literal it chose, so a hook other than the drag hook has a command
    # set of its own - and this goes red with the record's sentence.
    test "exactly one hook pushes commands, and it is the drag hook" do
      assert command_pushers() == [@command_hook], """
      ADR-0005 decision 7, as amended on 2026-09-28 (7e): one hook pushes
      commands, and it is `StatifierBlocksDrag`; any number of hooks may only
      measure or draw. A hook that pushes a second command set - one that
      sends decision 2's commands or an event name of its own - is a thing
      this record does not have, so amend `docs/adr/0005-liveview-editor.md`
      first, then this test.

      Hooks pushing an event name of their own: #{inspect(command_pushers())}
      """
    end

    # Every other hook is one of the two kinds 7e admits, read off what it
    # pushes: the measurement and nothing else (7a), or only names the host
    # handed it (7f) - never a literal. A hook that is neither fails here
    # even when it pushes nothing the test above counts.
    # Sabotage: adding `this.pushEventTo(this.el, "measure", {})` to the map
    # hook - the measurement is not a name of its own, so the test above
    # stays green, but a hook that both measures and draws is neither kind -
    # and this goes red naming the pushes.
    test "every other hook only measures or draws" do
      for {hook, source} <- hook_sources(), hook != @command_hook do
        text = File.read!(source)

        case kind(text) do
          :measure ->
            :ok

          :draw ->
            for name <- @command_names ++ @list_event_names ++ [@measurement] do
              refute text =~ ~r/["'`]#{Regex.escape(name)}["'`]/, """
              7f: a draw-only hook pushes no event name of its own, so its
              source names none. `#{hook}` (#{source}) spells `#{name}`.
              """
            end

          other ->
            flunk("""
            7e admits a hook that pushes commands (only #{@command_hook}), one
            that only measures, and any number that only draw. `#{hook}`
            (#{source}) is none of these: #{inspect(other)}.
            """)
        end
      end
    end

    # The permitted path, told apart from the forbidden one: a draw-only
    # hook's pushes take their name from the element's data attributes, the
    # host's list event names, and from nothing else.
    # Sabotage: reading both names from `data-select-event` - the insert
    # arms a selection - and this goes red; pushing `this.pushEvent(
    # "select-row", ...)` instead - the test above goes red instead, which is
    # the other half of telling the two apart.
    test "the map hook pushes only the names the host stamped on its element" do
      source = File.read!(@map_source)

      assert kind(source) == :draw
      assert source =~ "select: el.dataset.selectEvent"
      assert source =~ "insert: el.dataset.insertEvent"
      assert [_one] = Regex.scan(~r/\bpushEvent(?:To)?\s*\(/, source)
      assert source =~ "this.pushEvent(gesture.event, gesture.payload)"
    end

    # The classifier the tests above rest on, held against probe sources
    # rather than the shipped hooks: a name the hook spells itself is its
    # own however it is spelled - double quotes, single quotes, a template,
    # or a `const`, `let` or `var` bound to one of them - and `pushEventTo`'s
    # target is never read as the name.
    # Sabotage: narrowing the name match in `push_names/1` back to double
    # quotes alone - the single-quoted, template and binding-held probes
    # read as expressions, so a hook pushing them would pass as draw-only -
    # and this goes red.
    test "a name the hook spells is a literal however it is spelled" do
      for probe <- [
            ~S|this.pushEvent("select-row", {})|,
            ~S|this.pushEvent('select-row', {})|,
            ~S|this.pushEvent(`select-row`, {})|,
            ~S|const name = 'select-row'; this.pushEvent(name, {})|,
            ~S|let name = `select-row`; this.pushEvent(name, {})|,
            ~S|this.pushEventTo(this.el, 'select-row', {})|,
            ~S|this.pushEventTo('#list', `select-row`, {})|
          ] do
        assert push_names(probe) == [{:literal, "select-row"}], probe
        assert pushes_own_name?(probe), probe
        refute kind(probe) == :draw, probe
      end
    end

    # The other direction: a name read from the host's stamped attributes
    # stays an expression, even when a binding holds it on the way.
    # Sabotage: resolving a bare identifier through any `const` binding, not
    # only one bound to a quoted name - the stamped name held in
    # `const name = this.el.dataset.selectEvent` reads as a literal - and
    # this goes red.
    test "a name the host stamped stays the host's, and the hook stays draw-only" do
      for probe <- [
            ~S|const events = {select: this.el.dataset.selectEvent}; this.pushEvent(events.select, {})|,
            ~S|const name = this.el.dataset.selectEvent; this.pushEvent(name, {})|,
            ~S|this.pushEventTo(this.el, this.el.dataset.insertEvent, {})|
          ] do
        assert match?([{:expression, _text}], push_names(probe)), probe
        refute pushes_own_name?(probe), probe
        assert kind(probe) == :draw, probe
      end
    end

    # 7f's rule is that a draw-only hook's pushes come from the names the
    # host stamped, so a hook whose pushes are all expressions but that
    # reads no stamped event name is not draw-only.
    # Sabotage: dropping the stamped-name condition from `kind/1`'s draw
    # clause - a hook pushing a name it computed passes as draw-only - and
    # this goes red.
    test "a hook whose pushes read no stamped name is not draw-only" do
      probe = ~S|const name = pick(); this.pushEvent(name, {})|

      assert [{:expression, "name"}] = push_names(probe)
      assert kind(probe) == {:unstamped, [{:expression, "name"}]}
    end

    # A hook the checks above classify per file must be alone in its file.
    # Sabotage: adding a second `export const SomethingElse = { mounted() ...`
    # to the map hook's file - its pushes would be counted against one name
    # - and this goes red.
    test "each file in assets/js exports at most one hook" do
      for source <- @sources do
        assert length(hooks_in(source)) <= 1, "#{source}: #{inspect(hooks_in(source))}"
      end
    end

    # The defect this guards is the one found in every host seen:
    # registering the drag hook alone leaves the connector layer with no
    # measurements, so the editor renders as stacked rows with no flow lines
    # and nothing anywhere reports an error. A default export carrying both is
    # what makes `hooks: { ...StatifierBlocks }` register both or neither.
    # The Map hook is not in it: it has its own entry point, so a host that
    # never mounts the Map never bundles elkjs.
    # Sabotage: dropping `StatifierBlocksMeasure` from the default export of
    # assets/js/statifier_blocks.js - the one-line registration in the README
    # silently goes back to registering the drag hook alone, and this goes red.
    # Sabotage: adding `StatifierBlocksMap` to it - every host bundles the
    # layout library whether or not it draws a map - and this goes red.
    test "the entry point's default export carries both editor hooks" do
      assert default_export(@hook_source) == ["StatifierBlocksDrag", "StatifierBlocksMeasure"],
             """
             A host registers hooks from the default export
             (`hooks: { ...StatifierBlocks }`, README "Embedding the editor"), so a
             hook missing from it is a hook no host registers. `StatifierBlocksMeasure`
             is what feeds the server the geometry `connector_layer.ex` draws from:
             without it the editor renders stacked rows with no connectors and no
             error to explain them. `StatifierBlocksMap` stays out of it: it
             imports the whole of the vendored elkjs build, and a host pays for
             that only by importing `statifier_blocks/map`.

             Found: #{inspect(default_export(@hook_source))}
             """
    end

    # The README is the page hexdocs shows and the one a host copies from, so
    # the shape it teaches is part of this contract rather than prose beside it.
    # Sabotage: reverting the README to `hooks: { StatifierBlocksDrag }` - the
    # copied snippet registers one hook again and this goes red.
    test "the README teaches the shape that registers both" do
      readme = File.read!("README.md")

      assert readme =~ "import StatifierBlocks from \"statifier_blocks\";"
      assert readme =~ "hooks: { ...StatifierBlocks }"
      assert readme =~ "StatifierBlocksMeasure"
    end

    # The corroborator: a scan over a hard-coded file list says nothing about
    # a file that is not on it.
    # Sabotage: dropping any source from `@sources` - the checks above go
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
    # sui-ADR-0009's bar is DEPENDENCIES, and this file imports none: its one
    # import is the sibling module in this same package, which the entry point
    # needs in order to put both hooks in one default export (sb-f04). A bare
    # specifier - anything not resolved relative to this directory - is a
    # dependency and is what the ban is about, so that is what this checks.
    # The measure hook imports nothing at all and is checked that way above.
    # Sabotage: adding `import { something } from "phoenix"` to the hook - the
    # source-delivery model sui-ADR-0009 permits for a self-contained hook no
    # longer applies and this goes red.
    test "the hook pulls no dependency, which is what lets it ship as source" do
      assert imports(@hook_source) == ["./statifier_blocks_measure.js"], """
      sui-ADR-0009 bans colocated and source-shipped hooks that pull
      dependencies. The entry point qualifies only because every specifier it
      imports is relative to this package - today exactly one, the sibling
      module holding the measurement hook. A bare specifier here is a
      dependency a host would have to install, which is the thing the record
      forbids.

      Found: #{inspect(imports(@hook_source))}
      """
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

    # d5 puts validity on the SLOT, and slots nest. A drop target selected with
    # `closest('[data-drop="ok"]')` walks past the gap's own refused slot to
    # whatever accepting slot contains it, and the drop is then pushed with the
    # refused slot's coordinates - which `Edit.apply/2` applies, because
    # decision 5 has it report arity violations as findings rather than refuse
    # them. So the stamp is the enforcement point, and reading the wrong stamp
    # is a document corruption no ExUnit test reaches: it was found by driving
    # both gestures in a browser (sb-4nep).
    # Sabotage: restoring `gap.closest('[data-drop="ok"]')` in `gapFor` - this
    # goes red naming the selector, which is the thing that was wrong.
    test "a gap's drop target is its own slot's answer, not an ancestor's" do
      source = File.read!(@hook_source)

      refute source =~ ~s|closest('[data-drop="ok"]')|, """
      A refused slot nested inside an accepting one would inherit the
      ancestor's "ok", and every gap in it would become a live drop target
      pushing the refused slot's parent-id, slot and index.

      Ask the gap's nearest `[data-drop]` and compare it, so a refusal is read
      where it was stamped.
      """

      assert source =~ ~s|gap.closest("[data-drop]")|
    end
  end

  describe "the map hook's entry point and its one import (ADR-0018, 7g)" do
    # The bundle cost is the reason for the entry point: a host
    # imports `statifier_blocks/map` to get the hook and the layout library,
    # and nothing else pulls either in.
    # Sabotage: dropping the `./map` export from assets/package.json - a
    # host's `import StatifierBlocksMap from "statifier_blocks/map"` resolves
    # to nothing, which no other test would notice.
    test "the map hook is its own entry point, with its own default export" do
      package = "assets/package.json" |> File.read!() |> Jason.decode!()

      assert package["exports"]["./map"] == "./js/statifier_blocks_map.js"
      assert "js/statifier_blocks_map.js" in package["files"]
      assert File.read!(@map_source) =~ "export const StatifierBlocksMap = {"
      assert default_export(@map_source) == ["StatifierBlocksMap"]
    end

    # The README is where a host copies the registration from, so the shape
    # it teaches for the Map is held to the entry point above.
    # Sabotage: rewriting the README's import as the default export's
    # `import { StatifierBlocksMap } from "statifier_blocks"` - a host
    # copying it bundles no Map hook - and this goes red.
    test "the README teaches the Map hook's own import and its cost" do
      [_before, section] = "README.md" |> File.read!() |> String.split("\n## Mounting the Map\n")
      [section | _rest] = String.split(section, "\n## ")

      assert section =~ ~s(import { StatifierBlocksMap } from "statifier_blocks/map";)
      assert section =~ "hooks: { ...StatifierBlocks, StatifierBlocksMap }"
      assert section =~ "1,606,238 bytes"
    end

    # 1c: the map hook is not "a genuinely self-contained hook with no
    # imports"; its one import is the vendored layout library, by relative
    # path inside this package, and never an npm dependency.
    # Sabotage: importing `elkjs` by its bare package name - a host would
    # have to install it - and this goes red.
    test "its one import is the vendored layout library" do
      assert imports(@map_source) == ["../vendor/elk.bundled.js"]
      assert File.regular?(Path.expand("../vendor/elk.bundled.js", Path.dirname(@map_source)))
    end

    # The bundled build is UMD, which reads `module` and `exports`; in this
    # `"type": "module"` package a `.js` file is an ES module and those are
    # not defined, so Node (and a bundler that honours the field) would load
    # it as a module with no default export. The directory's own
    # package.json says CommonJS, which is what the file is.
    # Sabotage: marking assets/vendor/package.json `"type": "module"` - the
    # layout driver's import of the hook fails in Node with "does not provide
    # an export named 'default'", every layout test goes red, and this goes
    # red on the field.
    test "the vendor directory is read as CommonJS" do
      vendor = "assets/vendor/package.json" |> File.read!() |> Jason.decode!()

      assert vendor == %{"type" => "commonjs"}
      assert "vendor/package.json" in Jason.decode!(File.read!("assets/package.json"))["files"]
    end

    # ADR-0018 (b): elkjs 0.9.3 byte for byte, its licence beside it, and one
    # manifest line whose digest is the file's. The pre-push scan trusts
    # that line to skip the file's line checks, so a file that drifted from
    # the digest must fail here before it fails there.
    # Sabotage: appending one byte to assets/vendor/elk.bundled.js - the
    # digest no longer matches the manifest line and this goes red.
    test "the vendored elkjs matches its manifest line, with its licence beside it" do
      [entry] =
        @vendor_manifest
        |> File.read!()
        |> String.split("\n")
        |> Enum.reject(&(String.trim(&1) == "" or String.starts_with?(&1, "#")))

      assert [@elk, "sha256=" <> digest, "upstream=elkjs@0.9.3", "licence=" <> licence] =
               String.split(entry, " ")

      assert digest == :crypto.hash(:sha256, File.read!(@elk)) |> Base.encode16(case: :lower)
      assert licence == @elk_licence
      assert File.read!(@elk_licence) =~ "Eclipse Public License"

      package = "assets/package.json" |> File.read!() |> Jason.decode!()
      assert "vendor/elk.bundled.js" in package["files"]
      assert "vendor/elkjs-LICENSE.md" in package["files"]

      # The npm manifest ships that file, so its licence names both, as the
      # hex package's `licenses:` does.
      # Sabotage: setting assets/package.json's "license" back to "MIT" -
      # this goes red on the field.
      assert package["license"] == "(MIT AND EPL-2.0)"
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
      assert File.regular?(@map_source)
      assert File.regular?(@elk)
      assert File.regular?(@elk_licence)
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

  describe "the button vocabulary (sb-sl6f)" do
    # The defect: the reset keeps native chrome ON for form controls on
    # purpose, so a button whose class the stylesheet never mentions renders
    # as whatever the host's browser paints. That is invisible to every other
    # test in the suite - the markup is correct, the events fire, and the
    # control simply does not look like one.
    # Sabotage: dropping the `.sb-field__add` rule from the stylesheet - the
    # add control goes back to native chrome and this names it.
    test "every class a button carries has a rule in the stylesheet" do
      unstyled =
        for {class, source} <- button_classes(), not styled?(class), do: {class, source}

      assert unstyled == [], """
      A button whose classes the stylesheet never mentions is painted by the
      browser, not by this package - which is exactly the state sb-sl6f found
      Undo, Redo, the zoom steps, the two fits and a list field's add/remove
      in. Every class below is emitted on a `<button>` and matched by no
      selector in #{@stylesheet}:

      #{Enum.map_join(unstyled, "\n", fn {class, source} -> "  #{class} (#{source})" end)}
      """
    end

    # The vocabulary is a vocabulary only if the plain controls actually speak
    # it. Named rather than derived: "which buttons are quiet ones" is a
    # design ruling, and a rule that derived it from the markup would pass
    # whatever the markup happened to say.
    # Sabotage: removing `sb-button` from the toolbar's class attributes - the
    # toolbar's buttons keep working and stop looking like controls, and this
    # goes red naming them.
    test "the quiet controls wear it" do
      wearing = vocabulary_wearers()

      for class <- ~w(
            sb-toolbar__button sb-toolbar__zoom-step
            sb-field__add sb-field__remove sb-palette__cancel sb-gap__add
          ) do
        assert class in wearing, """
        `#{class}` is one of the controls sb-sl6f put in the button
        vocabulary, and it is not carrying `sb-button`. Either it wears the
        family or the bead's ruling changed; a per-class copy of the family's
        border and hover is the outcome the vocabulary exists to prevent.

        Carrying `sb-button`: #{inspect(Enum.sort(wearing))}
        """
      end
    end

    # A control has to be able to report two things about itself, and the
    # vocabulary is where they are said once. `[disabled]` is the half the
    # bead's acceptance names: Undo and Redo are disabled with an empty
    # history (shell_test), and this is what makes that state visible.
    # Sabotage: deleting the `.sb-button[disabled]` rule - a disabled Undo
    # renders at full strength with a pointer cursor and only a human looking
    # at the screen would know.
    test "it carries the two states a control reports" do
      css = stylesheet()

      assert css =~ ~r/\.sb-button\[disabled\]\s*\{[^}]*opacity:\s*var\(--sb-disabled-opacity\)/,
             "a disabled control has to read as disabled, and `--sb-disabled-opacity` is the " <>
               "token a host reverses that with"

      assert css =~ ~r/\.sb-button\[aria-pressed="true"\]\s*\{[^}]*var\(--sb-accent\)/,
             "Fit width and Fit active are toggles; `aria-pressed` is what says which is on"

      assert css =~ ~r/\.sb-button:hover:not\(\[disabled\]\)\s*\{/,
             "the hover is what separates a control from `sb-toolbar__chip`, which is not one"
    end

    # 14b's reset is `:where()`-wrapped for a reason and the button family is
    # the surface most likely to tempt someone into widening it: styling the
    # bare `button` element would reach every host button inside the editor's
    # subtree, including ones this package did not render.
    # Sabotage: adding `:where(.sb-editor) button { border: ... }` to the
    # reset - the package starts painting controls it does not own and this
    # goes red.
    test "it is a class vocabulary, not a widened element reset" do
      refute stylesheet() =~ ~r/:where\(\.sb-editor\)\s+button\s*\{[^}]*border\s*:/,
             "the reset restores inherited type and nothing else; a button LOOK belongs to a " <>
               "class, so a host's own button inside the editor is left alone"
    end

    # The corroborator: a scan over a hard-coded directory says nothing about
    # a button that lives outside it.
    # Sabotage: moving a `<button>` into a module outside `editor/` - the scan
    # above goes quiet about it and this notices.
    test "the scan covers every button in lib" do
      files_with_buttons =
        "lib/**/*.ex"
        |> Path.wildcard()
        |> Enum.filter(&(File.read!(&1) =~ "<button"))
        |> Enum.sort()

      assert files_with_buttons -- button_sources() == [], """
      A `<button>` outside `lib/statifier_blocks/editor/` is a control the
      scan above never looks at, so it could carry any class at all and no
      test would say so.

      Outside the scan: #{inspect(files_with_buttons -- button_sources())}
      """

      assert files_with_buttons != []
    end
  end

  describe "the palette search and the toolbar's one rule (sb-lti6)" do
    # The defect: the reset kept native chrome ON for form controls, so the
    # search rendered as whatever the host's browser paints - a plain native
    # box as the first thing inside a bordered, rounded surface card. Every
    # other test in the suite is happy with that: the markup is right, the
    # filter works, and only a human looking at the pane would say so.
    #
    # Since the form-control ruling the box is not the search box's alone: the
    # config form's fields were the same defect one pane over, and the two are
    # now one rule. What this test asks is unchanged - does this control
    # declare a box - and it is `declarations_of/1`, not the assertion, that
    # knows the rule may be shared.
    # Sabotage: reverting `.sb-palette__search` to `font: inherit; width: 100%`
    # - the box goes back to native and this names the properties it lost.
    test "the search declares the box the pane's other surfaces have" do
      declarations = declarations_of(".sb-palette__search")

      for property <- ~w(padding background border border-radius) do
        assert Map.has_key?(declarations, property), """
        `.sb-palette__search` sits inside a pane this package draws - a border,
        a radius and a surface of its own - and a control in it that declares
        none of those three is the one element the package left to the
        browser. Missing: #{property}.

        Declared: #{inspect(Map.keys(declarations))}
        """
      end
    end

    # The half that makes the rule above a THEME rather than a look: a host
    # themes this package by setting `--sb-*` and nothing else (decision 14),
    # so a hard-coded `1px solid #ccc` here is a border no host can move.
    # Sabotage: writing `border-radius: 4px` on the search - the box still
    # looks right in the default theme and stops answering to the host, and
    # this goes red naming the literal.
    test "every value in that box is a token, not a literal" do
      literals =
        for {property, value} <- declarations_of(".sb-palette__search"),
            property in ~w(padding color background border border-radius),
            not (value =~ ~r/var\(--sb-/),
            do: "#{property}: #{value}"

      assert literals == [], """
      ADR-0005 decision 14: a host themes this package with `--sb-*` custom
      properties and nothing else. A literal in this rule is a value that
      host cannot reach, and the search would then be the one control in the
      pane that ignores their theme.

      Literals: #{inspect(literals)}
      """
    end

    # The gap "+" joined the family last (sb-lti6), and it is the member most
    # likely to drift back out: its old rule carried `border: none`, which
    # reads as harmless and silently cancels the family on the one control
    # that most needs to look like one - forty-one of them ride the flow edges
    # of a document, and a canvas of borderless glyphs is what the insertion-marker ruling's "the gap
    # IS the insertion marker" is not.
    # Sabotage: putting `border: none` (or the old `background: var(--sb-bg)`)
    # back on `.sb-gap__add` - the resting "+" goes back to a bare glyph while
    # the class enumeration above still passes, and this goes red naming it.
    test "the gap button refines the family instead of restating it" do
      restated =
        for {property, value} <- declarations_of(".sb-gap__add"),
            property in ~w(border background border-radius font cursor),
            do: "#{property}: #{value}"

      assert restated == [], """
      `.sb-gap__add` wears `sb-button`, so the border, the surface, the radius
      and the pointer are the family's to declare. Restating one here is the
      per-class copy the vocabulary exists to prevent, and cancelling one -
      `border: none` - is how the resting "+" stopped reading as a control.

      Restated: #{inspect(restated)}
      """
    end

    # The defect this guards is the one sb-lti6 found: `.sb-toolbar` was
    # declared TWICE - a layout half stranded at the end of the palette
    # section and a chrome half in the toolbar's own - with disjoint
    # properties, so reading either one told you half of what the toolbar
    # does and editing either one moved half of it.
    # Sabotage: splitting the rule back in two - the count goes to two and
    # this goes red before anyone has to notice the halves by reading.
    test "the toolbar is declared exactly once" do
      blocks =
        @stylesheet
        |> File.read!()
        |> StatifierBlocks.ThemeAudit.declaration_blocks()
        |> Enum.filter(&(&1.selector == ".sb-toolbar"))

      assert length(blocks) == 1, """
      Two rules for one selector is how a stylesheet starts disagreeing with
      itself: neither block is wrong, and neither is the whole answer.

      Found #{length(blocks)} `.sb-toolbar` blocks.
      """

      properties = blocks |> hd() |> Map.fetch!(:declarations) |> Enum.map(&elem(&1, 0))

      for property <- ~w(display align-items flex-wrap gap padding border border-radius
                         background) do
        assert property in properties,
               "the merge is a pure move: `#{property}` was in one of the two halves"
      end
    end
  end

  describe "the run marks (the host marking seam)" do
    # Sabotage: dropping the leading `.sb-node` from one mark selector - the
    # rule reaches anything else that ever carries the attribute, and this
    # goes red. `.sb-palette` already carries data attributes of its own,
    # which is why the scoping is asserted rather than trusted.
    test "every mark rule is scoped to .sb-node" do
      for {selector, _tokens} <- mark_rules(), part <- String.split(selector, ",") do
        assert String.starts_with?(String.trim(part), ".sb-node"),
               "an unscoped mark rule reaches whatever else carries the attribute: #{part}"
      end
    end

    # Every family here is one a theme actually retunes, which is the property
    # that keeps a mark from being right in the light theme and wrong in every
    # other one. Three of them are families the editor already had. The fourth,
    # `--sb-run-done`, is a token this package declares for the done mark alone
    # (sb-ht2e), and declaring one is allowed for exactly one reason:
    # `docs/theming.md`'s example and the spike's host-brand theme both restate
    # it, and the theme audit fails the build on a colour token a theme leaves
    # at the package default. A new token is reachable when the record makes it
    # reachable; declaring one and stopping there is what this list catches.
    # Sabotage: replacing `var(--sb-accent)` in the active rule with the
    # literal `#1c62e9` - the mark stops following the host's theme, the
    # token disappears from this list, and the assertion goes red.
    # Sabotage (sb-ht2e): pointing the done rule at `var(--sb-run-don)` - a
    # name one character off resolves to nothing, and this goes red on the
    # list rather than leaving an unpainted mark to be found by eye.
    test "the marks are painted only in tokens, and only in reachable families" do
      tokens = mark_rules() |> Enum.flat_map(&elem(&1, 1)) |> Enum.uniq() |> Enum.sort()

      assert tokens == ~w(
               --sb-accent --sb-accent-muted --sb-bg-muted --sb-border-strong
               --sb-error --sb-error-bg --sb-run-done --sb-run-done-bg
               --sb-space-half
             )

      for {_selector, declarations} <- mark_declarations(),
          {property, value} <- declarations,
          property in ~w(border-color background box-shadow) do
        assert value =~ "var(--sb-", "a mark paints `#{property}` with a literal: #{value}"
      end
    end

    # Sabotage: deleting the `error` rule - a call that came back badly is
    # painted the same as one that came back, and this goes red on the count
    # and on the selector.
    test "there is a rule for each mark and for each outcome the sheet names" do
      selectors = Enum.map_join(mark_rules(), " ", &elem(&1, 0))

      assert length(mark_rules()) == 4
      assert selectors =~ ~s(data-run-active="true")
      assert selectors =~ ~s(data-run-invoking="true")
      assert selectors =~ ~s(data-invoke-outcome="done")
      assert selectors =~ ~s(data-invoke-outcome="error")
    end
  end

  # Every `<button>` in the editor components, paired with the classes it
  # carries. The pairing is nearest-following: between a `<button` and its own
  # `class=` no other element can open, so the next class attribute in the
  # source is always that button's.
  defp button_classes do
    for source <- button_sources(),
        text = File.read!(source),
        {position, _length} <- :binary.matches(text, "<button"),
        class <- classes_after(text, position),
        do: {class, source}
  end

  defp button_sources, do: Path.wildcard("lib/statifier_blocks/editor/*.ex")

  # The `sb-` classes in the first class attribute at or after `position`.
  # Both HEEx forms are read: `class="a b"` and `class={["a", cond && "b"]}`,
  # where every literal in the list is a class the element can carry.
  defp classes_after(text, position) do
    rest = binary_part(text, position, byte_size(text) - position)

    case Regex.run(~r/class=(?:"([^"]*)"|\{(.*?)\n?\s*\}\n)/s, rest, capture: :all_but_first) do
      nil ->
        []

      captures ->
        captures
        |> Enum.join(" ")
        |> then(&Regex.scan(~r/[\w-]+/, &1))
        |> List.flatten()
        |> Enum.filter(&String.starts_with?(&1, "sb-"))
    end
  end

  describe "the drawer's tab bar is one row at every width" do
    # The bar labels the panel under it, so its height is chrome the panel
    # pays for: a bar that grows a row when a host contributes a tab takes
    # that row out of the content the drawer exists to show. Measured at a
    # 640-wide editor with six tabs, wrapping put the bar at 65px against 36px
    # at 1280; scrolling holds it at 36px at both.
    #
    # Asserted against the stylesheet because the alternative is a browser,
    # and the three declarations below are the whole mechanism - `nowrap` on
    # the bar so nothing moves downward, `min-width: 0` so the strip is the
    # flex item that gives, and `overflow-x` so what does not fit is reachable
    # rather than gone. Any one of them removed restores the second row.
    #
    # Sabotage: putting `flex-wrap: wrap` back on `.sb-drawer__bar` - the bar
    # wraps again at 640 and this goes red naming the declaration that did it.
    test "the bar does not wrap and the strip scrolls instead" do
      bar = declarations_of(".sb-drawer__bar")
      strip = declarations_of(".sb-drawer__tabs")

      assert Map.get(bar, "flex-wrap") == "nowrap"
      assert Map.get(strip, "flex-wrap") == "nowrap"
      assert Map.get(strip, "min-width") == "0"
      assert Map.get(strip, "overflow-x") == "auto"
    end

    # The other half of the earlier fix, which this one must not undo: the
    # overflow moves sideways and never inward, so a tab's label and its count
    # stay one line however narrow the bar gets.
    #
    # Sabotage: dropping `white-space: nowrap` from `.sb-drawer__tab` - the
    # count falls under the label inside a clipped tab, which is the defect
    # the strip's own scroll would otherwise hide.
    test "a tab still keeps its label and its count on one line" do
      assert declarations_of(".sb-drawer__tab") |> Map.get("white-space") == "nowrap"
    end

    # The controls at the end of the bar are the strip's counterweight: if
    # they shrink too, the slider narrows before the strip has scrolled at
    # all, and the overflow lands on the wrong item.
    #
    # Sabotage: removing `flex: none` from `.sb-drawer__resize` - the slider
    # compresses at 640 while the strip still shows every tab, so nothing
    # above goes red and the bar quietly stops being measurable.
    test "the height slider and the collapse control hold their size" do
      assert declarations_of(".sb-drawer__resize") |> Map.get("flex") == "none"
      assert declarations_of(".sb-drawer__close") |> Map.get("flex") == "none"
    end
  end

  # The classes that appear beside `sb-button` on the same element.
  defp vocabulary_wearers do
    for {class, _source} <- button_classes(),
        class != "sb-button",
        "sb-button" in classes_beside(class),
        uniq: true,
        do: class
  end

  defp classes_beside(class) do
    for source <- button_sources(),
        text = File.read!(source),
        {position, _length} <- :binary.matches(text, "<button"),
        classes = classes_after(text, position),
        class in classes,
        found <- classes,
        do: found
  end

  # Every declaration made for this selector, as a map. Merged across blocks
  # rather than taken from the first, because a rule can legitimately be
  # extended inside a container query and a check that read only one of the
  # two would be answering about half the rule.
  #
  # A selector is matched as a MEMBER of a block's comma-separated list and
  # not by string equality with the whole list, because whether a control's
  # box is written on its own or shared with the control beside it is a
  # question about duplication, not about what the control declares. Equality
  # answered "nothing" for a rule that declares everything (an operator
  # ruling shared `.sb-palette__search`'s box with `.sb-field__input`), and
  # a guard that reports a themed control as unthemed is worse than no guard.
  defp declarations_of(selector) do
    @stylesheet
    |> File.read!()
    |> StatifierBlocks.ThemeAudit.declaration_blocks()
    |> Enum.filter(fn block ->
      block.selector
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.member?(selector)
    end)
    |> Enum.flat_map(& &1.declarations)
    |> Map.new()
  end

  # A class is styled when some selector in the stylesheet names it - on its
  # own, in a group, or qualified by a state.
  defp styled?(class) do
    stylesheet() =~ ~r/\.#{Regex.escape(class)}(?![\w-])/
  end

  # The mark rules, as `{selector, tokens}`. `data-run-` is the whole family:
  # both marks and both outcomes carry it, and nothing else in the stylesheet
  # does.
  defp mark_rules do
    for {selector, declarations} <- mark_declarations() do
      tokens =
        declarations
        |> Enum.flat_map(fn {_property, value} -> Regex.scan(~r/var\((--sb-[\w-]+)\)/, value) end)
        |> Enum.map(&Enum.at(&1, 1))

      {selector, tokens}
    end
  end

  defp mark_declarations do
    @stylesheet
    |> File.read!()
    |> StatifierBlocks.ThemeAudit.declaration_blocks()
    |> Enum.filter(&String.contains?(&1.selector, "data-run-"))
    |> Enum.map(&{&1.selector, &1.declarations})
  end

  defp stylesheet do
    @stylesheet |> File.read!() |> StatifierBlocks.ThemeAudit.strip_comments()
  end

  # Every hook exported by every file in `assets/js/`, with the file it is
  # in, in file order and then source order. Read off the files rather than
  # off a list here: a list here is the thing that would silently need
  # updating and would not get it.
  defp hook_sources do
    for source <- @sources, hook <- hooks_in(source), do: {hook, source}
  end

  defp hooks_in(source) do
    ~r/^export const (\w+) = \{/m
    |> Regex.scan(File.read!(source))
    |> Enum.map(fn [_all, name] -> name end)
  end

  # A quoted name in any of the three JavaScript spellings.
  @quoted ~S/"[^"]*"|'[^']*'|`[^`]*`/

  # The event name each push in the JavaScript `text` sends: `{:literal,
  # name}` for a name it spells - in double quotes, single quotes or a
  # template, or through a `const`, `let` or `var` bound to one of those -
  # and `{:expression, text}` for one it reads from elsewhere.
  # `pushEventTo`'s first argument is the target and is skipped.
  defp push_names(text) do
    ~r/\b(?:pushEvent\s*\(|pushEventTo\s*\(\s*(?:#{@quoted}|[^,"'`]+?)\s*,)\s*(#{@quoted}|[^,)]+)/
    |> Regex.scan(text)
    |> Enum.map(fn [_all, argument] -> push_name(String.trim(argument), text) end)
  end

  defp push_name(argument, text) do
    cond do
      argument =~ ~r/\A(?:#{@quoted})\z/ -> {:literal, unquote_name(argument)}
      held = held_name(argument, text) -> {:literal, held}
      true -> {:expression, argument}
    end
  end

  # The name a bare identifier holds when `text` binds it to a quoted name.
  defp held_name(argument, text) do
    with true <- argument =~ ~r/\A[A-Za-z_$][\w$]*\z/,
         [_all, quoted] <-
           Regex.run(
             ~r/\b(?:const|let|var)\s+#{Regex.escape(argument)}\s*=\s*(#{@quoted})/,
             text
           ) do
      unquote_name(quoted)
    else
      _no -> nil
    end
  end

  defp unquote_name(quoted), do: String.slice(quoted, 1..-2//1)

  # Whether `text` pushes an event name of its own: a literal other than
  # the measurement.
  defp pushes_own_name?(text) do
    Enum.any?(push_names(text), &match?({:literal, name} when name != @measurement, &1))
  end

  # The hooks that push an event name of their own.
  defp command_pushers do
    for {hook, source} <- hook_sources(), pushes_own_name?(File.read!(source)), do: hook
  end

  # What kind of hook the JavaScript `text` holds, by what it pushes: only
  # the measurement is `:measure`; nothing, or only names read from the
  # host's stamped `data-*-event` attributes, is `:draw` (7f); pushes that
  # are all expressions with no stamped name read are `{:unstamped,
  # names}`; anything else is answered as the pushes themselves.
  defp kind(text) do
    names = push_names(text)

    cond do
      names != [] and Enum.all?(names, &(&1 == {:literal, @measurement})) -> :measure
      names == [] -> :draw
      not Enum.all?(names, &match?({:expression, _text}, &1)) -> names
      stamped_names?(text) -> :draw
      true -> {:unstamped, names}
    end
  end

  # Whether `text` reads an event name the host stamped on the hook's
  # element: `el.dataset.<something>Event`.
  defp stamped_names?(text), do: text =~ ~r/\bel\.dataset\.[a-z]\w*Event\b/

  # The names in a file's `export default { ... }`, sorted. This is the object
  # a host spreads into `hooks:`, so it is the list that decides what actually
  # gets registered.
  defp default_export(source) do
    [_all, body] = Regex.run(~r/^export default \{([^}]*)\};?$/m, File.read!(source))

    body
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.sort()
  end

  # Every module specifier a file imports, in source order.
  defp imports(source) do
    ~r/^\s*import\s(?:[^;]*?\sfrom\s)?\s*"([^"]+)"/m
    |> Regex.scan(File.read!(source))
    |> Enum.map(fn [_all, specifier] -> specifier end)
  end
end
