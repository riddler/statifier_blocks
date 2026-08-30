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
  @stylesheet "assets/css/statifier_blocks.css"

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

    # The defect this guards is the one campaign 016 found in every host seen:
    # registering the drag hook alone leaves the connector layer with no
    # measurements, so the editor renders as stacked rows with no flow lines
    # and nothing anywhere reports an error. A default export carrying both is
    # what makes `hooks: { ...StatifierBlocks }` register both or neither.
    # Sabotage: dropping `StatifierBlocksMeasure` from the default export of
    # assets/js/statifier_blocks.js - the one-line registration in the README
    # silently goes back to registering the drag hook alone, and this goes red.
    test "the entry point's default export carries both hooks" do
      assert default_export(@hook_source) == ["StatifierBlocksDrag", "StatifierBlocksMeasure"],
             """
             A host registers hooks from the default export
             (`hooks: { ...StatifierBlocks }`, README "Embedding the editor"), so a
             hook missing from it is a hook no host registers. `StatifierBlocksMeasure`
             is what feeds the server the geometry `connector_layer.ex` draws from:
             without it the editor renders stacked rows with no connectors and no
             error to explain them.

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
    # Since campaign-021 ruling R4 the box is not the search box's alone: the
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
    # of a document, and a canvas of borderless glyphs is what R3's "the gap
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

    # A colour token declared only in this stylesheet's `:root` is a token no
    # host theme overrides, so a mark painted in one is right in the light
    # theme and wrong in every other. The marks are therefore drawn in
    # families a theme already retunes.
    # Sabotage: replacing `var(--sb-accent)` in the active rule with the
    # literal `#1c62e9` - the mark stops following the host's theme, the
    # token disappears from this list, and the assertion goes red.
    test "the marks are painted only in tokens, and only in reachable families" do
      tokens = mark_rules() |> Enum.flat_map(&elem(&1, 1)) |> Enum.uniq() |> Enum.sort()

      assert tokens == ~w(
               --sb-accent --sb-accent-muted --sb-bg-muted --sb-border-strong
               --sb-error --sb-error-bg --sb-info --sb-info-bg --sb-space-half
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
  # answered "nothing" for a rule that declares everything (campaign-021
  # ruling R4 shared `.sb-palette__search`'s box with `.sb-field__input`), and
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

  # The names in a file's `export default { ... }`, sorted. This is the object
  # a host spreads into `hooks:`, so it is the list that decides what actually
  # gets registered.
  defp default_export(source) do
    [_all, body] = Regex.run(~r/^export default \{([^}]*)\};/m, File.read!(source))

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
