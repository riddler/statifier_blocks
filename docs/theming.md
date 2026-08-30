# Theming the editor

How to make `StatifierBlocks.Editor` look like your product without forking it.

The contract is ADR-0005 decision 14 and its 2026-08-28 amendment. This page
is the how-to; the record is in
[`docs/adr/0005-liveview-editor.md`](adr/0005-liveview-editor.md), and the
shipped surface is
[`assets/css/statifier_blocks.css`](../assets/css/statifier_blocks.css), whose
header comment carries the tier of every token.

## The rule

> A host theme sets `--sb-*` custom properties. It writes no other
> declaration.

That is the whole bargain, and it is checked rather than asked for:
`test/statifier_blocks/theme_audit_test.exs` reads the example on this page
out of this file and fails the build if it ever declares anything but a
`--sb-*` property.

The rule is what makes the surface honest in both directions. If a restyle you
want turns out to need a structural declaration - a `padding`, a
`grid-template-columns`, a rule against an `sb-` class - that is a **hole in
the token surface**, not a licence to write the rule. File it; the fix belongs
in the stylesheet, and every token in the surface today was found exactly that
way by the campaign-012 spike's third theme.

## Where to put it

The tokens are declared on the editor's own container, `.sb-editor`. There are
two ways to override them and they differ in reach, not in power:

| | What it is | Use it when |
|---|---|---|
| the `theme` assign | a map of property name to value, rendered as an inline `style` on the canvas root | the values are computed - a tenant's brand colour out of the database |
| a stylesheet | a rule of your own that sets the properties on `.sb-editor` | the theme is static, which is the ordinary case |

One gotcha, and it is the only one: a declaration on an **ancestor** of the
editor does not work. `.sb-editor` declares every token on itself, and a
declaration on the element beats an inherited value from its parent however
specific the parent's selector is. Set the properties on `.sb-editor` itself,
or on a selector that reaches that element:

```text
/* No: the editor's own declarations win over anything inherited. */
[data-theme="cardpay"] { --sb-bg: #1a1f27; }

/* Yes: the same element the package declares its defaults on. */
[data-theme="cardpay"] .sb-editor { --sb-bg: #1a1f27; }
```

Load your stylesheet after the package's, so a tie in specificity goes your
way.

## The three tiers

Not three sets of tokens - three answers to "what am I taking on by setting
this?". Every token in the stylesheet's header comment carries its tier.

1. **The palette.** Colour, space, shape, type. A couple of dozen lines, and a
   host that stops here has a themed editor.
2. **The treatments.** One specific mark - the drop affordance, the drag seam,
   the focus ring, a canvas metric, the canvas's dotted ground
   (`--sb-canvas-grid`, which carries the whole `background` shorthand so its
   colour and its spacing move together), the editor's own height
   (`--sb-editor-height`, below), the shaping of a per-type accent - that you
   can disagree with without overriding a rule.
3. **`--sb-color-scheme`.** Its own tier, because it is not a value this
   package paints with. See below.

A candidate is not a token. The amendment's 14f lists names the spike needed -
the syntax roles, the path underlines, the drag ghost, the run mark, the
scroll shadows - and they are deliberately **not declared** until the rule
that reads them ships. A declared token nothing consumes is worse than an
absent one: you would set it, nothing would move, and there would be no way to
tell that from a bug in your own stylesheet.

## `--sb-color-scheme` is not optional

Half of a control is painted by the browser and reachable by no colour token
at all: a `<select>`'s drop-down, the scrollbar troughs, the text caret, the
selection highlight, an input's clear button. A dark theme that restates every
colour and omits this one line opens a white menu over a dark editor.

So every theme states it, `light` or `dark`. The package reads it as
`color-scheme: var(--sb-color-scheme)` on `.sb-editor` and nowhere else -
telling the host page which scheme it is in would be the editor reaching
outside its own box, which is the one thing decision 14 says it does not do.

## Bounding the editor's height

By default the editor is as tall as the document in it and your page scrolls.
That is the right default for a page whose only content is the editor, and the
wrong one for an application shell: on a long document the drawer - the
findings and truth-table strip along the bottom - ends up below the fold, and
an author scrolls the whole page to reach it.

Set `--sb-editor-height` to a length and the editor scrolls as a pane instead.
The canvas takes the slack, the canvas panel scrolls inside it, and the drawer
stays pinned at the bottom of the editor:

```text
.myapp-page .sb-editor { --sb-editor-height: calc(100vh - 4rem); }
```

Any length works - `40rem`, or `100%` inside a box your own layout has already
sized. The default is `auto`, so a host that never sets it sees exactly the
arrangement it has today. In the bounded mode each pane scrolls in its own box
rather than spilling down the page: the canvas, the palette and the inspector
all get their own scrollbar when their content is taller than the editor.

This is one of the tokens that has to be a token, and it is the clearest case
of the rule at the top of this page. Writing `height` on `.sb-editor` yourself
is the structural declaration the bargain rules out, and it does not work
anyway: it bounds the editor's outer box and stops there, while the grid one
level in is still as tall as the document and simply overflows you. Setting the
token does both halves - the editor takes the height, and the grid inside it is
allowed to be shorter than the tree it holds, which is what hands the scrolling
to the panes.

## Per-block-type accents

A palette entry may declare `accent_token`: the **name** of a `--sb-*` custom
property, never a colour.

```text
%{type: "myapp:authorize", label: "Authorize", accent_token: "--sb-accent-myapp-authorize"}
```

The renderer stamps that name onto the block's card and its palette row as a
`--sb-block-accent` reference with the editor's accent as the fallback arm.
Three things follow, and they are why this is worth a key rather than a rule
per type in your own CSS:

- **The editor never learns a type name.** Two rules read
  `--sb-block-accent` - an icon tile and a card stripe - and adding a block
  type with its own identity adds no CSS at all.
- **The theme decides the value.** A descriptor carries a name; what colour
  that name means is yours, and it can mean different colours in your light
  and dark themes.
- **It degrades.** The name is validated against an anchored pattern before it
  reaches a style attribute (`StatifierBlocks.ViewModel.accent_token/1`), so a
  malformed value falls back to the editor's accent rather than injecting. A
  well-formed name you forget to **define** also falls back - silently - so
  the example below defines every name its registry points at, and the audit
  has a check for exactly that mistake.

The **stripe** is drawn on cards whose type declared a token, and on no
others. A type that declared nothing keeps the plain card it has always had,
so the stripe reads as "this one is yours" rather than as decoration every
card carries - painted on all of them it would say nothing, an undeclared type
resolving to the editor's own accent. The **tile** is on every card either
way, which is why a type that declares nothing still has a coloured icon.

Group the names to get grouping for free: below, `myapp:authorize` and
`myapp:capture` both resolve through `--sb-accent-myapp`, so the family reads
as one, and the theme can still pull one of them out.

## Icons are markup, and a theme does not touch them

The package ships a default icon set - `StatifierBlocks.Editor.Icons`, inline
SVG for the names the core block types declare, no font and no CDN - and the
editor uses it whenever the host passes no `icon` component. It is **markup,
not styling**, and the split is the same one this whole document is about: a
glyph's shape is the package's, a glyph's colour and size are the theme's.

So there is no `--sb-icon-*` token, and there is nothing here to override:

- every path paints with `currentColor`, and the `<svg>` fills its tile;
- the tile - `.sb-node__icon` on a card, `.sb-palette__icon` on a palette row -
  is the only rule with an opinion, and it reads `--sb-block-accent` and
  `--sb-block-accent-tint`, which the section above already covers;
- so restyling the icons is restyling those two tokens, and a per-block-type
  `accent_token` moves a type's tile with its stripe, for free.

Two states are deliberate rather than absent, and neither is a hole a theme is
expected to paper over:

- **a block type that declares no icon gets no tile at all.** The chrome closes
  up around the label. A type that declared nothing is not missing something.
- **a name the shipped set does not have gets a neutral mark** - three dots, in
  the tile, with the name in `data-icon`. A host block type declaring
  `icon: "credit-card"` gets a chip that reads as deliberate. The right fix is
  to pass your own `icon` component, which wins on every tile on both surfaces;
  the mark is what the editor looks like until you do.

Neither state is the white square the editor used to render (`sb-jja`). If you
see one, you are looking at a font, not at this package.

## A complete host theme

A credit-card processing host, dark, brand accent, two block types with
identities of their own. It restates every colour token the package declares
plus the scheme, and it declares nothing else. That is the file the audit
holds to the rule.

```css
/*
 * cardpay: an example host theme for StatifierBlocks.Editor.
 *
 * Every declaration is a `--sb-*` custom property. If a restyle needs
 * anything else, that is a hole in the token surface upstream.
 */

[data-theme="cardpay"] .sb-editor {
  /* Tier 3 first, because it is the one that gets forgotten: the browser's
   * own chrome inside the editor's subtree. */
  --sb-color-scheme: dark;

  /* Surfaces, back to front. */
  --sb-bg-canvas: #12151b;
  --sb-bg: #1a1f27;
  --sb-bg-muted: #212733;
  --sb-bg-sunken: #0e1116;

  /* Text. Each of these clears 4.5:1 on the WORST of the four surfaces, not
   * on the one it happens to sit over in the screenshot. */
  --sb-fg: #eef1f6;
  --sb-fg-muted: #a8b2c2;
  --sb-fg-subtle: #93a0b2;
  --sb-fg-on-accent: #0e1116;

  /* Lines. `--sb-border-strong` carries meaning - a boundary box, an
   * undeclared slot - and clears 3:1. `--sb-border` divides two panes of one
   * surface and is decoration, so it is deliberately held to no ratio. */
  --sb-border: #2c3442;
  --sb-border-strong: #6e7b8f;

  /* Brand accent. */
  --sb-accent: #4da3ff;
  --sb-accent-hover: #7bbcff;
  --sb-accent-muted: rgba(77, 163, 255, 0.16);

  /* Findings. A text colour and a tint each, because a finding row reads as
   * text on its own tint. */
  --sb-error: #ff8a7a;
  --sb-error-bg: rgba(255, 138, 122, 0.12);
  --sb-warning: #e8b551;
  --sb-warning-bg: rgba(232, 181, 81, 0.14);
  --sb-info: #4da3ff;
  --sb-info-bg: rgba(77, 163, 255, 0.12);

  /* The drop affordance. Tier 2: the mark stays, its colour is ours. */
  --sb-drop-ok-border: #57c98a;
  --sb-drop-ok-bg: rgba(87, 201, 138, 0.12);

  /* Tier 2 shaping, and the reason it is a token: 14% of a pale accent over
   * near-black is not a tint. */
  --sb-block-accent-mix: 24%;

  /* The nesting bands. The package derives these from `--sb-bg` and
   * `--sb-bg-sunken`, so a theme that restates the four surfaces bands
   * correctly without saying anything here at all. They are restated anyway,
   * and that is the point worth showing: the separation this theme wants
   * between one nesting level and the next is a little wider than the gap
   * between two of its own surfaces, and these two names are where a host
   * says so rather than reaching for a rule. Opaque, both of them - two
   * translucent bands stacked by the nesting they describe accumulate into
   * "deeper is darker", which is not what a band is for. */
  --sb-band-even: #1a1f27;
  --sb-band-odd: #0e1116;

  /* Per-type identity. These are ours, not the package's: a name a palette
   * entry points at is defined by whoever writes the theme. The family reads
   * as one, and the type that moves money is pulled out of it. */
  --sb-accent-myapp: #4da3ff;
  --sb-accent-myapp-authorize: var(--sb-accent-myapp);
  --sb-accent-myapp-capture: #e8b551;
}
```

## Running the same checks yourself

The package audits its own stylesheet and this page's example in the gate:
token coverage in both directions, contrast, override purity, tier coverage,
and accent names that nothing defines. The arithmetic is in
`test/support/theme_audit.ex` and it is pure - it takes stylesheet text and
returns values, with no browser and no file access - so a host with a theme of
its own can copy it and hold that theme to the same numbers.

What it will not tell you is whether the result looks right. That still takes
eyes.
