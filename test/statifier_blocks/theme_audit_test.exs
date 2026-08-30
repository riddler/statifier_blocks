defmodule StatifierBlocks.ThemeAuditTest do
  @moduledoc """
  The theme audit, held against the stylesheet rather than against a comment.

  ADR-0005 decision 14's proposed amendment 14e asks for exactly this, and asks
  for it in **both directions**:

  > The package's own check fails on **either** direction: a `var(--sb-*)`
  > reference with no declaration, and a declared token no rule reads.

  The second half is the one worth having. A missing declaration produces a
  visible defect the first time someone looks at the editor; a declared token
  nothing reads produces no defect at all - a host sets it, nothing moves, and
  there is no way to tell that from a bug in their own stylesheet. The spike
  shipped two of those (`--sb-gap-height` and `--sb-gap-hover-bg`, declared in
  its first pass and consumed by nothing) and found them by measuring rather
  than by reading.

  14b's reset rule is checked here too, because it is "mechanical enough to be
  a lint" and that is the only form it survives in - the bug it prevents is
  silent by construction.

  Contrast, override purity, the tier table and the accent names are checked
  here too (`sb-2b9`). The arithmetic is `StatifierBlocks.ThemeAudit`, a port
  of the pure half of the spike's `js/theme.js` that `dev/theme-audit.html`
  could only ever run in a browser by hand. Purity needed a subject and now has
  one: `docs/theming.md` carries a complete host theme, this file reads it out
  of the document, and the example is held to the rule it documents rather than
  to a promise that it follows it.

  Deliberately **not** tagged `:liveview`: it reads a file off disk, so it runs
  in the headless tree too, where `assets/` is easiest to forget.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.ThemeAudit

  @stylesheet "assets/css/statifier_blocks.css"
  @theming_doc "docs/theming.md"

  # The four surfaces a foreground token can land on, and the roles that land
  # on them. Every colour token the stylesheet declares is accounted for by one
  # of these lists or by `@no_ratio` below, and a test asserts that - a new
  # colour token arriving without a contrast ruling is the thing that would
  # otherwise slip through.
  @surfaces ~w(--sb-bg-canvas --sb-bg --sb-bg-muted --sb-bg-sunken)

  # Read as text, so 4.5:1 against the worst surface in the theme.
  @text_tokens ~w(
    --sb-fg --sb-fg-muted --sb-fg-subtle
    --sb-accent --sb-accent-hover
    --sb-error --sb-warning --sb-info
  )

  # Lines that carry meaning rather than text: 3:1, the non-text threshold.
  @line_tokens ~w(--sb-border-strong --sb-drop-ok-border)

  @no_ratio %{
    # The operator's design ruling, recorded in the d14 amendment: it divides
    # two panes of one surface, so it is decoration rather than a boundary
    # carrying information, and holding it to 3:1 turns every pane edge into a
    # rule.
    "--sb-border" => "a design ruling, not a measurement",
    # Measured against the accent it sits on, not against a surface it never
    # touches. Checked separately below.
    "--sb-fg-on-accent" => "checked against --sb-accent",
    # A ratio against a translucent fill is a number about a guess: what it is
    # painted over decides it, and that is the surface's ratio already.
    "--sb-accent-muted" => "translucent",
    "--sb-error-bg" => "translucent",
    "--sb-warning-bg" => "translucent",
    "--sb-info-bg" => "translucent",
    "--sb-drop-ok-bg" => "translucent"
  }

  setup_all do
    raw = File.read!(@stylesheet)
    source = ThemeAudit.strip_comments(raw)
    example = host_theme_example()

    %{
      raw: raw,
      source: source,
      declared: ThemeAudit.declared_tokens(source),
      referenced: ThemeAudit.referenced_tokens(source),
      values: ThemeAudit.token_values(source),
      example: example,
      # What a host actually renders under: the package's defaults with the
      # host's theme layered over them, which is the only map a contrast claim
      # about a theme is true of.
      example_values: Map.merge(ThemeAudit.token_values(source), ThemeAudit.token_values(example))
    }
  end

  # The host theme from `docs/theming.md`, read out of the document.
  #
  # The document holds exactly ONE ```css fence and it is the example; anything
  # shown that is deliberately wrong is fenced as ```text so that it is never
  # audited as if it were a theme. A test asserts the count, because the day
  # someone adds a second css fence is the day this silently starts auditing
  # half of it.
  defp host_theme_example do
    blocks =
      ~r/```css\n(.*?)```/s
      |> Regex.scan(File.read!(@theming_doc))
      |> Enum.map(fn [_all, body] -> body end)

    assert length(blocks) == 1,
           "#{@theming_doc}: expected exactly one ```css fence, found #{length(blocks)}"

    hd(blocks)
  end

  describe "token coverage runs in both directions (14e)" do
    # Sabotage: adding `color: var(--sb-fg-nonexistent)` to `.sb-node` - the
    # reference has no declaration and this goes red naming it.
    test "every token a rule reads is declared", context do
      undeclared = MapSet.difference(context.referenced, context.declared)

      assert MapSet.to_list(undeclared) == [], """
      ADR-0005 amendment 14e: a `var(--sb-*)` reference with no declaration is
      a token a host cannot set and a value that falls back to nothing.

      Referenced and never declared: #{inspect(MapSet.to_list(undeclared))}
      """
    end

    # Sabotage: declaring `--sb-ghost-bg: #fff` on `.sb-editor` without a rule
    # that reads it - a reserved name in a published surface is a promise, and
    # this goes red on it.
    test "every token declared is read by some rule", context do
      dead = MapSet.difference(context.declared, context.referenced)

      assert MapSet.to_list(dead) == [], """
      ADR-0005 amendment 14e: a declared token no rule reads is worse than a
      missing one - a host sets it, nothing moves, and there is no way to tell
      that from a bug. Either give it a consumer or retire the name; a name in
      a published surface is a commitment to keep meaning what it says.

      Declared and never read: #{inspect(MapSet.to_list(dead))}
      """
    end

    # Not a claim about the stylesheet: it is what stops the two checks above
    # from passing vacuously if the scan regexes ever stop matching anything.
    # Sabotage: narrowing `declared_tokens/1` to a name that does not exist -
    # both directions go quiet and this is what notices.
    test "the scan actually saw the surface", context do
      assert MapSet.member?(context.declared, "--sb-accent")
      assert MapSet.member?(context.referenced, "--sb-accent")
    end
  end

  describe "the scheme token (14a)" do
    # Sabotage: deleting the `color-scheme: var(--sb-color-scheme)` declaration
    # - every theme's `<select>` drop-downs, scrollbars and carets go back to
    # being unreachable by any token, which is the defect that reads as "the
    # dark theme is half-finished" and cannot be diagnosed from the stylesheet.
    test "the editor declares --sb-color-scheme and reads it as color-scheme",
         %{source: source, declared: declared} do
      assert MapSet.member?(declared, "--sb-color-scheme")
      assert source =~ ~r/color-scheme:\s*var\(--sb-color-scheme\)/
    end

    # Sabotage: moving the declaration onto `:root` - the editor then tells the
    # host page which scheme it is in, which is the editor reaching outside its
    # own box.
    test "it is scoped to the editor's container, never :root", %{source: source} do
      refute source =~ ~r/(^|\})\s*:root\b/,
             "14a: scoped to the editor's own container, never `:root`"
    end
  end

  describe "the scoped reset is zero-specificity on its container half (14b)" do
    # Sabotage: rewriting one reset selector as `.sb-editor p` - it out-weighs
    # every single-class component rule below it, which is how a reset starts
    # silently stripping the padding and margins it exists to make room for.
    test "no selector matches the container as a class and an element", %{source: source} do
      offenders =
        ~r/\.sb-editor\s+[a-zA-Z]/
        |> Regex.scan(source)
        |> Enum.map(fn [match] -> match end)
        |> Enum.uniq()

      assert offenders == [], """
      ADR-0005 amendment 14b: a scoped reset may match its container only
      through `:where(.sb-editor)`. `.sb-editor p` weighs one class plus one
      element, which beats any single-class component rule, so it forces every
      rule below it to defend itself with an element qualifier the next author
      will not know to copy.

      Found: #{inspect(offenders)}
      """
    end

    # The same corroborator for the check above: a stylesheet with no reset at
    # all satisfies the specificity rule perfectly.
    # Sabotage: deleting the reset block - the lint above stays green and this
    # goes red.
    test "the reset is actually present", %{source: source} do
      assert source =~ ":where(.sb-editor) button"
      assert source =~ ":where(.sb-editor) :focus-visible"
    end
  end

  describe "the token surface's shape (decision 14)" do
    # Sabotage: declaring a `--sb-*` token inside `.sb-node` - a host setting it
    # through the `theme` assign, which writes to the canvas root, then cannot
    # override it, because the nearer declaration wins.
    test "every token is declared on the editor root", %{source: source} do
      root_block = source |> String.split("\n.sb-editor {", parts: 2) |> List.last()
      {tokens, rest} = String.split(root_block, "\n}\n", parts: 2) |> List.to_tuple()

      stray =
        ~r/(--sb-[a-z0-9-]+)\s*:/
        |> Regex.scan(rest)
        |> Enum.map(fn [_all, name] -> name end)
        |> Enum.uniq()

      assert stray == [], """
      ADR-0005 decision 14: every custom property is declared on the canvas
      root, which is where the `theme` assign writes. A declaration further in
      is one a host cannot override.

      Declared elsewhere: #{inspect(stray)}
      """

      assert tokens =~ "--sb-accent", "the split found the root block"
    end

    # Sabotage: renaming one token to `--radius` - the namespace is what keeps
    # the package from colliding with a host's own properties, and the record
    # commits to it.
    test "no custom property outside the --sb-* namespace is declared", %{source: source} do
      stray =
        ~r/(--(?!sb-)[a-z0-9-]+)\s*:/
        |> Regex.scan(source)
        |> Enum.map(fn [_all, name] -> name end)
        |> Enum.uniq()

      assert stray == [],
             "decision 14: the property namespace is `--sb-*`. Found: #{inspect(stray)}"
    end
  end

  describe "contrast, on the shipped palette (14a's evidence, 14f's ruling)" do
    # The completeness guard. Every check below names its tokens, so the way
    # this stops being true is a NEW colour token arriving with no ruling about
    # what it has to clear - which is silent, because nothing fails.
    # Sabotage: adding `--sb-accent-alt: #cccccc` (with a consumer, so 14e stays
    # green) - this goes red naming it as unaccounted for.
    test "every colour token is accounted for by a ratio or by a recorded reason",
         %{source: source} do
      accounted = MapSet.new(@surfaces ++ @text_tokens ++ @line_tokens ++ Map.keys(@no_ratio))

      unaccounted =
        source |> ThemeAudit.colour_tokens() |> Enum.reject(&MapSet.member?(accounted, &1))

      assert unaccounted == [], """
      A colour token with no contrast ruling. Either give it a threshold in
      `@text_tokens` or `@line_tokens`, or record in `@no_ratio` why it is not
      held to one - `--sb-border` is not held to a ratio and that is a design
      ruling the record carries, which is exactly the kind of thing that has to
      be said out loud rather than left out.

      Unaccounted for: #{inspect(unaccounted)}
      """
    end

    # Sabotage: moving `--sb-fg-subtle` back to `#9aa2b0` (2.9:1 on the sunken
    # surface, which is where the spike found it) - this goes red with the
    # ratio and the surface, which is the failure the amendment describes.
    test "text clears 4.5:1 on the worst surface, not the nearest one", context do
      for token <- @text_tokens do
        colour = ThemeAudit.resolve(context.values, token)
        assert colour, "#{token} does not resolve to a colour"

        {ratio, surface, on} = ThemeAudit.worst_contrast(colour, context.values, @surfaces)

        assert ratio >= 4.5,
               "#{token} (#{colour}) is #{ratio}:1 on #{surface} (#{on}), under 4.5:1"
      end
    end

    # Sabotage: taking `--sb-border-strong` back to `#c3cad6` - the boundary
    # box's edge and the undeclared-slot outline stop being boundaries at all,
    # and this goes red where looking at it would not.
    test "a line that carries meaning clears 3:1", context do
      for token <- @line_tokens do
        colour = ThemeAudit.resolve(context.values, token)
        {ratio, surface, on} = ThemeAudit.worst_contrast(colour, context.values, @surfaces)

        assert ratio >= 3,
               "#{token} (#{colour}) is #{ratio}:1 on #{surface} (#{on}), under 3:1"
      end
    end

    # Sabotage: setting `--sb-fg-on-accent: #cfdcf6` - a pale blue on the
    # accent still looks fine and stops clearing the ratio, which is the case
    # eyes are worst at.
    test "--sb-fg-on-accent clears 4.5:1 on the accent it sits on", context do
      {ratio, _token, _on} =
        context.values
        |> ThemeAudit.resolve("--sb-fg-on-accent")
        |> ThemeAudit.worst_contrast(context.values, ["--sb-accent", "--sb-accent-hover"])

      assert ratio >= 4.5, "--sb-fg-on-accent is #{ratio}:1 on the accent, under 4.5:1"
    end

    # The corroborator for all four: an arithmetic bug that made every ratio
    # large would leave them all passing and say nothing.
    # Sabotage: dropping the sRGB linearisation from `relative_luminance/1` -
    # the mid-grey pair moves and this goes red.
    test "the arithmetic is WCAG's" do
      assert ThemeAudit.contrast_ratio("#000000", "#ffffff") == 21.0
      assert ThemeAudit.contrast_ratio("#ffffff", "#000000") == 21.0
      assert ThemeAudit.contrast_ratio("#777777", "#ffffff") == 4.48
      assert ThemeAudit.channels("#fff") == ThemeAudit.channels("#ffffff")
    end
  end

  describe "the three tiers are written down (14c)" do
    # 14c is "a statement about the ones there are", which is only true while
    # it covers all of them.
    # Sabotage: deleting the `3  --sb-color-scheme` line from the header - the
    # token a theme most often forgets loses the entry that tells a host what
    # it is for, and this goes red.
    test "every declared token carries a tier in the stylesheet's header",
         %{raw: raw, declared: declared} do
      untiered = MapSet.difference(declared, MapSet.new(Map.keys(tiers(raw))))

      assert MapSet.to_list(untiered) == [], """
      ADR-0005 amendment 14c: the surface has three tiers and a host should be
      able to tell which one it is in. A token with no tier line in the header
      comment is a token no host can place.

      Declared without a tier: #{inspect(MapSet.to_list(untiered))}
      """
    end

    # The other direction, and the one that rots quietly: a token is retired
    # from the surface and its tier line is left behind, so the documentation
    # promises a name that no longer exists.
    # Sabotage: adding `2  --sb-run-mark` (a 14f candidate that is deliberately
    # not shipped) to the header - this goes red naming it.
    test "no tier line names a token that is not declared", %{raw: raw, declared: declared} do
      phantom = raw |> tiers() |> Map.keys() |> Enum.reject(&MapSet.member?(declared, &1))

      assert phantom == [], """
      A tier line for a token the stylesheet does not declare. A name in a
      published surface is a commitment to keep meaning what it says, and a
      tier table is where a host reads that commitment.

      Tiered but not declared: #{inspect(phantom)}
      """
    end

    # Not a claim about the header: it is what stops both checks above from
    # passing vacuously if the tier-line shape ever changes.
    # Sabotage: narrowing the scan to a shape the header does not use - both
    # checks go quiet and this is what notices.
    test "the scan actually saw the tier table", %{raw: raw} do
      found = tiers(raw)

      assert map_size(found) > 40
      assert found["--sb-color-scheme"] == "3"
      assert found["--sb-accent"] == "1"
      assert found["--sb-focus-ring"] == "2"
    end
  end

  describe "the shell's tokens and breakpoints (the 2026-08-29 amendment)" do
    @shell_tokens ~w(--sb-palette-width --sb-inspector-width --sb-drawer-height)

    # 14e in both directions, named for the tokens the shell added, so a later
    # refactor that drops a consumer says which surface it dropped rather than
    # only that some token went dead.
    # Sabotage: deleting `max-height: var(--sb-drawer-height)` from
    # `.sb-drawer__panel` - the remembered height stops reaching anything and
    # this goes red naming the token.
    test "each is declared and read", context do
      for token <- @shell_tokens do
        assert MapSet.member?(context.declared, token), "#{token} is not declared"
        assert MapSet.member?(context.referenced, token), "#{token} is declared and never read"
      end
    end

    # Sabotage: removing the `2  --sb-drawer-height` line from the header - a
    # host cannot place the token in a tier, which is what 14c is for.
    test "each carries a tier", %{raw: raw} do
      tiers = tiers(raw)

      for token <- @shell_tokens do
        assert tiers[token] == "2", "#{token} is not tier 2 in the header"
      end
    end

    # 7A: container queries, not media queries, because the editor is embedded
    # in a host page whose chrome this package does not control.
    # Sabotage: rewriting one `@container` as `@media` - the editor starts
    # arranging itself by the viewport's width rather than by the width it was
    # actually given, which is wrong in exactly the case that matters (a narrow
    # column on a wide screen) and looks right everywhere else.
    test "the editor is the query container and every recorded step has a rule",
         %{source: source} do
      assert source =~ ~r/container-type:\s*inline-size/
      assert source =~ ~r/container-name:\s*sb-editor/

      for width <- [1280, 1024, 900, 780, 640] do
        assert source =~ ~r/@container sb-editor \(width < #{width}px\)/,
               "7A lists a #{width} step and no container query answers it"
      end

      refute source =~ ~r/@media[^{]*width/,
             "7A: the breakpoints are container queries; a media query is the arrangement this package cannot know"
    end

    # The corroborator: a scan that matched nothing would pass the step check
    # above vacuously if the rule shape ever changed.
    #
    # The two counts are different claims. 7A's steps are a closed list and are
    # pinned exactly, which is the stricter half and the one that would notice
    # a sixth breakpoint arriving unrecorded. The total is a floor, because a
    # query on the same container that is not a 7A step is a legitimate thing
    # for a pane affordance to want - the palette's fold is one (parity item
    # 1.1), scoped to the only arrangement that has a palette column to narrow.
    # Sabotage: narrowing the scan to a container name the stylesheet does not
    # use - the check above goes quiet and this notices.
    test "the scan actually saw the queries", %{source: source} do
      steps = Regex.scan(~r/@container sb-editor \(width < \d+px\)/, source)
      found = Regex.scan(~r/@container sb-editor/, source)

      assert length(steps) == 5
      assert length(found) >= 5
    end
  end

  describe "the canvas grid token (parity item 1.2)" do
    # 14e in both directions, named rather than merely counted, and the tier
    # line with it - the same three claims the shell and connector tokens make.
    # Sabotage: deleting `background: var(--sb-canvas-grid)` from `.sb-canvas` -
    # the ground goes flat and this goes red naming the token.
    test "it is declared, read, and tier 2", context do
      assert MapSet.member?(context.declared, "--sb-canvas-grid")
      assert MapSet.member?(context.referenced, "--sb-canvas-grid")
      assert tiers(context.raw)["--sb-canvas-grid"] == "2"
    end

    # ONE token carrying the whole `background` shorthand is the ruling, not an
    # accident: a host wanting denser dots and a host wanting fainter ones are
    # the same host reaching for the same declaration.
    # Sabotage: splitting the size out into a second token - the default keeps
    # working, and a theme that sets only the colour half silently loses the
    # spacing it also meant to set.
    test "it carries colour and spacing together, and chains to the palette",
         %{values: values} do
      value = values["--sb-canvas-grid"]

      assert value =~ "var(--sb-border)", "the dot colour chains to the palette"
      assert value =~ "var(--sb-space-3)", "the spacing chains to the space scale"
      assert value =~ "/", "a `background` shorthand needs position / size to parse"
    end

    # The ground is not a line that carries information, so it is deliberately
    # held to no contrast ratio - and the audit's colour scan must agree, or a
    # ruling about a decoration turns into a threshold nobody decided.
    # Sabotage: declaring it as a bare `#d7dbe2` - it lands in `colour_tokens/1`
    # unaccounted for, and the completeness guard above goes red.
    test "it is not a colour token, so no threshold is claimed for it", %{source: source} do
      refute "--sb-canvas-grid" in ThemeAudit.colour_tokens(source)
    end
  end

  describe "the connector tokens (decision 7's 2026-08-29 amendment)" do
    @connector_tokens ~w(--sb-edge --sb-edge-interrupt --sb-edge-width)
    @connector_lines ~w(--sb-edge --sb-edge-interrupt)

    # 14e in both directions, named for the tokens the connector layer added,
    # so a later refactor that drops a consumer says which surface it dropped
    # rather than only that some token went dead.
    #
    # The two stroke assertions are not redundant with the coverage check
    # above them: an arrowhead's `fill` also reads `--sb-edge`, so 14e stays
    # green with the STROKE gone and every connector falls back to the SVG
    # default, which is no stroke at all. The load-bearing consumer has to be
    # named, not merely counted.
    # Sabotage: deleting `stroke: var(--sb-edge)` from `.sb-edge` - the
    # coverage check stays green, the connectors disappear, and this is what
    # notices.
    test "each is declared and read, and the stroke is the consumer that matters",
         %{declared: declared, referenced: referenced, source: source} do
      for token <- @connector_tokens do
        assert MapSet.member?(declared, token), "#{token} is not declared"
        assert MapSet.member?(referenced, token), "#{token} is declared and never read"
      end

      assert source =~ ~r/\.sb-edge\s*\{[^}]*stroke:\s*var\(--sb-edge\)/,
             "an edge with no stroke is an edge nobody can see"

      assert source =~ ~r/\.sb-edge--interrupt\s*\{[^}]*stroke:\s*var\(--sb-edge-interrupt\)/,
             "10e: the out-of-band way out is marked, and the mark is a token"

      assert source =~ ~r/\.sb-edge\s*\{[^}]*stroke-width:\s*var\(--sb-edge-width\)/
    end

    # Sabotage: removing the `2  --sb-edge-interrupt` line from the header - a
    # host cannot place the token in a tier, which is what 14c is for.
    test "each carries a tier", %{raw: raw} do
      tiers = tiers(raw)

      for token <- @connector_tokens do
        assert tiers[token] == "2", "#{token} is not tier 2 in the header"
      end
    end

    # A connector is a line that carries information - it is the whole of what
    # the editor says about order and about ways out - so it is held to the
    # non-text threshold, exactly as `--sb-border-strong` is. Both defaults
    # are `var()` references to tokens that already clear it, which is what
    # makes this check about the CHAIN rather than about two literals: a theme
    # that moves `--sb-border-strong` moves the edges with it.
    # Sabotage: pointing `--sb-edge` at `--sb-border` - the decorative line
    # that is deliberately held to no ratio - and this goes red with the
    # ratio and the surface.
    test "a connector clears 3:1 on the worst surface, in the shipped palette", context do
      for token <- @connector_lines do
        colour = ThemeAudit.resolve(context.values, token)
        assert colour, "#{token} does not resolve to a colour"

        {ratio, surface, on} = ThemeAudit.worst_contrast(colour, context.values, @surfaces)

        assert ratio >= 3,
               "#{token} (#{colour}) is #{ratio}:1 on #{surface} (#{on}), under 3:1"
      end
    end

    # And in the documented example, which is the file a host copies. A dark
    # theme is where a line hue goes wrong: the grey that reads on white does
    # not read on near-black, and the example overrides both tokens the
    # connector defaults chain to.
    # Sabotage: taking the example's `--sb-warning` to `#8a6a1f` - it looks
    # plausible in the file, the interrupt channel stops being visible against
    # the canvas, and this goes red where the screenshot would not.
    test "and in the documented example, which is where a line hue goes wrong", %{
      example_values: values
    } do
      for token <- @connector_lines do
        colour = ThemeAudit.resolve(values, token)
        {ratio, surface, on} = ThemeAudit.worst_contrast(colour, values, @surfaces)

        assert ratio >= 3, "#{token} (#{colour}) is #{ratio}:1 on #{surface} (#{on})"
      end
    end

    # The connector layer is drawn from the shipped `--sb-*` surface and from
    # nothing else, which is what "the shipped theming surface for stroke
    # colours" means. A literal in one of these rules is a colour a host
    # cannot reach.
    # Sabotage: writing `stroke: #7f8a9d` into `.sb-edge` - the edges stop
    # moving with the theme and this goes red naming the declaration.
    test "no connector rule paints with a literal", %{source: source} do
      literals =
        ~r/\.sb-(?:edge|arrow|connectors)[^{]*\{([^}]*)\}/
        |> Regex.scan(source)
        |> Enum.flat_map(fn [_all, body] -> Regex.scan(~r/:\s*(#[0-9a-fA-F]{3,8})/, body) end)
        |> Enum.map(fn [_all, colour] -> colour end)

      assert literals == [], """
      ADR-0005 decision 14: the connector layer paints through the `--sb-*`
      surface. A literal colour in one of these rules is a colour a host
      cannot reach and a diagram that stays in the package's palette.

      Found: #{inspect(literals)}
      """
    end

    # The corroborator for the check above: a scan that matched no rule would
    # report no literal however many there were.
    # Sabotage: narrowing the scan to a class the stylesheet does not use -
    # the check above goes quiet and this notices.
    test "the scan actually saw the connector rules", %{source: source} do
      assert length(Regex.scan(~r/\.sb-edge\b/, source)) >= 2
      assert source =~ ~r/\.sb-connectors\s*\{/
    end
  end

  describe "a host theme is a pure token override (decision 14)" do
    # The rule the whole surface is built to keep, held against the example the
    # documentation tells a host to copy.
    # Sabotage: adding `padding: 1rem;` to the example in `docs/theming.md` -
    # this goes red naming the selector and the property, which is the finding
    # "the token surface has a hole" arrives as.
    test "the documented example declares nothing but --sb-* properties", %{example: example} do
      structural = ThemeAudit.structural_declarations(example)

      assert structural == [], """
      ADR-0005 decision 14: a host theme sets `--sb-*` custom properties and
      writes no other declaration. A theme that needs one has found a hole in
      the token surface, and the fix belongs in the surface.

      Structural declarations: #{inspect(structural)}
      """
    end

    # The corroborator: a purity check that never reports anything would pass
    # on a theme file that was one long structural rule.
    # Sabotage: making `structural_declarations/1` return `[]` unconditionally -
    # the check above stays green on anything and this goes red.
    test "the purity check reports a structural declaration when there is one" do
      impure = ".sb-editor { --sb-bg: #fff; padding: 1rem; }"

      assert ThemeAudit.structural_declarations(impure) == [
               %{selector: ".sb-editor", property: "padding"}
             ]
    end

    # A theme that leaves one surface at the light default is the dark-theme
    # failure mode in its purest form: one token, and half the editor stays
    # light. The list is derived from the stylesheet rather than written down
    # here, so a colour token added upstream lands on the example too.
    # Sabotage: deleting `--sb-bg-sunken` from the example - this goes red
    # naming it, where the rendered page would just look slightly wrong.
    test "the example restates every colour token, and the scheme", %{
      source: source,
      example: example
    } do
      covered = ThemeAudit.declared_tokens(example)
      must = ["--sb-color-scheme" | ThemeAudit.colour_tokens(source)]
      missing = Enum.reject(must, &MapSet.member?(covered, &1))

      assert missing == [], """
      `docs/theming.md`'s example is the file a host copies, so a token it
      leaves at the package default is a token every host will leave there too.

      Left at the default: #{inspect(missing)}
      """
    end

    # The example is a dark theme, and a dark theme is where contrast goes
    # wrong: the same hue that reads on white does not read on near-black.
    # Sabotage: changing the example's `--sb-fg-subtle` to `#5d6675` - it looks
    # plausible in the file and fails on the muted surface, which is the whole
    # reason this is arithmetic rather than an opinion.
    test "the example's own palette clears the same ratios", %{example_values: values} do
      for token <- @text_tokens do
        colour = ThemeAudit.resolve(values, token)
        {ratio, surface, on} = ThemeAudit.worst_contrast(colour, values, @surfaces)
        assert ratio >= 4.5, "#{token} (#{colour}) is #{ratio}:1 on #{surface} (#{on})"
      end

      for token <- @line_tokens do
        colour = ThemeAudit.resolve(values, token)
        {ratio, surface, on} = ThemeAudit.worst_contrast(colour, values, @surfaces)
        assert ratio >= 3, "#{token} (#{colour}) is #{ratio}:1 on #{surface} (#{on})"
      end

      {on_accent, _token, _on} =
        values
        |> ThemeAudit.resolve("--sb-fg-on-accent")
        |> ThemeAudit.worst_contrast(values, ["--sb-accent", "--sb-accent-hover"])

      assert on_accent >= 4.5
    end
  end

  describe "a per-type accent names a token, and the name has to mean something (14d)" do
    # `ViewModel.accent_token/1` refuses anything that is not an anchored
    # `--sb-` name, which is what keeps a colour out of a descriptor and a typo
    # out of a style attribute. It cannot know whether the name it accepts is
    # DEFINED anywhere - and an undefined one degrades silently to the editor's
    # accent, so the block type just quietly loses its identity.
    # Sabotage: renaming `--sb-accent-myapp-capture` in the example's theme
    # block - the registry below still points at it and this goes red, which is
    # the mistake a screenshot cannot show you.
    test "every name the documented registry points at is defined by the theme", %{
      example: example,
      declared: declared
    } do
      defined = MapSet.union(declared, ThemeAudit.declared_tokens(example))

      assert ThemeAudit.accent_token_gaps(documented_registry(), defined) == []
    end

    # The corroborator, and the check itself: a gap has to be reported, or the
    # test above passes on a registry pointing at nothing.
    # Sabotage: making `accent_token_gaps/2` return `[]` unconditionally - the
    # check above stays green and this goes red.
    test "a well-formed name nothing defines is reported", %{example: example, declared: declared} do
      defined = MapSet.union(declared, ThemeAudit.declared_tokens(example))

      entries = [%{type: "myapp:refund", accent_token: "--sb-accent-myapp-refund"}]

      assert ThemeAudit.accent_token_gaps(entries, defined) == ["--sb-accent-myapp-refund"]
    end

    # The normalizer's half of the contract, from the audit's side: a value
    # that is not a token NAME never becomes a gap, because it never becomes an
    # accent at all.
    # Sabotage: dropping the `--sb-` anchor from `ViewModel`'s pattern - a
    # colour and an injection attempt both start being reported as gaps, which
    # is this check noticing they got as far as the audit.
    test "a colour, or an injection attempt, is refused before it is a name" do
      entries = [
        %{type: "myapp:authorize", accent_token: "#ff0000"},
        %{type: "myapp:capture", accent_token: "red; background: url(x)"},
        %{type: "myapp:signup", accent_token: "--brand-accent"},
        %{type: "core.step"}
      ]

      assert ThemeAudit.accent_token_gaps(entries, []) == []
    end
  end

  describe "the bounded-height token (sb-ceb)" do
    # 14e in both directions and 14c's tier line, named rather than merely
    # counted, exactly as the shell, connector and canvas-grid tokens are.
    # Sabotage: deleting `height: var(--sb-editor-height)` from `.sb-editor` -
    # the token stops reaching anything, a host sets it and nothing moves, and
    # this goes red naming it.
    test "it is declared, read, and tier 2", context do
      assert MapSet.member?(context.declared, "--sb-editor-height")
      assert MapSet.member?(context.referenced, "--sb-editor-height")
      assert tiers(context.raw)["--sb-editor-height"] == "2"
    end

    # Two elements, one bound. The token is read on the editor ROOT, so it is
    # the whole component's height and a host's `calc(100vh - <chrome>)` means
    # what a host thinks it means, with the header slot inside the bound. The
    # GRID is then what yields: `flex` hands it the rest of that height and
    # `min-height: 0` is what lets it be shorter than its content. Neither half
    # is optional - a bounded root over a grid that will not shrink is exactly
    # the "it overflows instead of scrolling" the bead describes.
    #
    # `[;{]` in front of the property is not decoration: without it the pattern
    # also matches a `min-height`, which is a different declaration with a
    # different failure mode.
    # Sabotage: deleting `min-height: 0` from `.sb-editor__layout` - the root is
    # still bounded, the grid grows back to the height of the tree inside it,
    # and this goes red on the half that was doing the work.
    test "the root reads it and the layout grid is what yields", %{source: source} do
      assert source =~ ~r/\.sb-editor\s*\{[^}]*[;{]\s*height:\s*var\(--sb-editor-height\)/,
             "the token is the editor's own height"

      # The first match is the base rule; the rest are the 7A arrangements,
      # which restate columns and rows and nothing about the bound.
      assert [[_all, layout] | _] = Regex.scan(~r/\.sb-editor__layout\s*\{([^}]*)\}/, source)

      assert layout =~ ~r/flex:\s*1/, "the grid takes the rest of the editor"
      assert layout =~ ~r/min-height:\s*0/, "and is allowed to be shorter than its content"
    end

    # The default is the whole of "hosts that do not set it see no change": an
    # `auto` height is the height the shell has always had, and every other
    # declaration in this mode resolves to nothing on top of it.
    # Sabotage: shipping `100vh` as the default - every host that never asked
    # for a bounded editor gets one, which is a silent regression in their page
    # rather than in this package.
    test "its default is intrinsic, so an unset host is unchanged", %{values: values} do
      assert values["--sb-editor-height"] == "auto"
    end

    # The clamp and the release, together: `max-height` alone is defeated by a
    # grid item's content-based automatic minimum size, so the pair is the
    # mechanism and either one alone is a rule that looks right and does
    # nothing. The `overflow` is the third part and it is a separate rule
    # because it is a separate claim - a pane may be clamped everywhere, but it
    # may only become a scroll container where the palette is a column rather
    # than a sheet hanging out of its own box.
    # Sabotage: dropping `min-height: 0` - the panes grow past the row they were
    # clamped to, the overflow lands on the host page again, and this goes red
    # where the screenshot of a short document would not.
    test "the grid's children are clamped, allowed to shrink, and scroll",
         %{source: source} do
      assert [[_all, clamp], [_all2, scroll]] =
               Regex.scan(~r/\.sb-editor__layout\s*>\s*\*\s*\{([^}]*)\}/, source)

      assert clamp =~ ~r/min-height:\s*0/
      assert clamp =~ ~r/max-height:\s*100%/
      assert scroll =~ ~r/overflow:\s*auto/

      assert source =~
               ~r/@container sb-editor \(width >= 780px\)\s*\{\s*\.sb-editor__layout\s*>\s*\*/,
             "below 780 the palette body is an absolutely positioned sheet, which a scroll container clips"
    end

    # Where the scrolling actually ends up. The panel already had `overflow`;
    # what it did not have was permission to be shorter than its content, which
    # is what makes an `overflow` scroll rather than merely be declared.
    # Sabotage: deleting `min-height: 0` from `.sb-canvas-panel` - the flex item
    # refuses to shrink, the canvas pushes the drawer down again, and this goes
    # red naming the panel.
    test "the canvas panel may shrink below its content, which is what scrolls it",
         %{source: source} do
      assert [[_all, body]] = Regex.scan(~r/\.sb-canvas-panel\s*\{([^}]*)\}/, source)

      assert body =~ ~r/min-height:\s*0/
      assert body =~ ~r/overflow:\s*auto/
    end

    # 7A and the bounded mode have to agree. Three of the five breakpoints move
    # the canvas to a different row, and a row order restated without saying
    # which row takes the slack hands it to whatever is first - silently, since
    # an `fr` row and an `auto` row size identically while the height is
    # `auto`. So the rule is structural: an arrangement that names areas names
    # rows.
    # Sabotage: deleting `grid-template-rows` from the `width < 640px` block -
    # every default-mode capture is unchanged and this goes red naming the
    # arrangement that would have put the slack under the canvas.
    test "every arrangement that restates the areas restates the rows", %{source: source} do
      bodies =
        ~r/\.sb-editor__layout[^{]*\{([^}]*)\}/
        |> Regex.scan(source)
        |> Enum.map(fn [_all, body] -> body end)

      arrangements = Enum.filter(bodies, &(&1 =~ "grid-template-areas"))

      assert length(arrangements) == 4,
             "1A plus the three 7A steps that move the canvas; found #{length(arrangements)}"

      for body <- arrangements do
        assert body =~ ~r/grid-template-rows:/, """
        An arrangement that names `grid-template-areas` and no
        `grid-template-rows` inherits a row order written for a different one.

        Found: #{inspect(body)}
        """
      end
    end
  end

  # The tier of every token, read from the stylesheet's header comment. Read
  # from the RAW source on purpose: this is the one check whose subject is the
  # comment rather than what the browser sees.
  defp tiers(raw) do
    ~r/^\s*\*\s+([123])\s+(--sb-[a-z0-9-]+)\s*$/m
    |> Regex.scan(raw)
    |> Map.new(fn [_all, tier, name] -> {name, tier} end)
  end

  # The palette entries `docs/theming.md` shows a host registering. Written out
  # here rather than parsed out of the prose: the document shows one entry to
  # explain the shape, and what this needs is the set of names its theme block
  # promises to define.
  defp documented_registry do
    [
      %{type: "myapp:authorize", accent_token: "--sb-accent-myapp-authorize"},
      %{type: "myapp:capture", accent_token: "--sb-accent-myapp-capture"},
      %{type: "core.step"}
    ]
  end
end
