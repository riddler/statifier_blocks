# Editor spike

**Status: exploratory. This is a laboratory, not the product.**

A pure client-side prototype of the `statifier_blocks` editor: plain HTML,
CSS, JavaScript and SVG, served from disk. No LiveView, no Elixir, no build
step, no bundler, and no external CSS or JS library.

It exists to work through layout, visual design, styling architecture and
panel composition on their own, without the round trip through a server-side
component tree. What it learns comes back as ADR amendments and as CSS and
DOM that graduate into `assets/`; the spike itself is never the shipped
editor.

## What it is not

- **Not part of the Hex package.** `mix.exs` lists the package's `files:`
  explicitly and `spike/` is not among them, so nothing here reaches a
  release tarball.
- **Not a second implementation of the editor.** ADR-0005's shipped
  architecture - server-side commands, one drag hook, function components
  over a view model - is untouched by anything in this directory.
- **Not authoritative.** Where this directory and an accepted ADR disagree,
  the ADR is the contract and the spike is an experiment that has not been
  written up yet.

## What it deliberately mirrors

So the learnings transfer rather than having to be re-derived:

- A nested **tree**, never a flat graph. Connector lines are *rendered* from
  adjacency and nesting; they are never *authored*.
- The ADR-0005 command algebra semantics: insert, remove, move,
  update_config, inverses for undo, per-slot drop validity, and the "+"
  button as the no-drag path.
- ADR-0005 d10 presentation metadata (`layout: :columns` for parallel lanes,
  a secondary slot style for interrupt rails). The editor never branches on
  a type name.
- ADR-0005 d11 findings: anchored, with count badges on collapsed groups.
- **ADR-0005 d14 theming**, which is the contract the styling here is built
  on and is stress-testing: every emitted class is prefixed `sb-`, and every
  colour, space, radius and drag treatment is a `--sb-*` custom property.

## Layout

```
spike/
  README.md      this file
  serve.rb       static file server, Ruby stdlib only
  index.html     the editor shell
  css/
    reset.css    scoped element reset (everything under .sb-spike)
    tokens.css   the --sb-* surface: light default, dark theme block
    editor.css   structure and default treatment, all sb- prefixed
    themes/
      host-brand.css   the third theme, as a pure token override
  js/
    document.js    the block document model, mirrored (ADR-0001)
    palette.js     the block-type registry + the core.* vocabulary (ADR-0002)
    demo-types.js  the host vocabulary the demo documents are written against
    proposed-core.js  core.* types the package does NOT ship (see below)
    edit.js        the command algebra and undo stacks (ADR-0005 d2-d4)
    targets.js     drop-target enumeration (ADR-0005 d5)
    layout.js      the layout model, and connector geometry as pure functions
    render.js      the layout model as DOM, and the connectors as SVG
    interact.js    pointer and key events, translated into commands
    session.js     selection, collapse, drag and edits, with no DOM
    theme.js       the per-block-type accent hook, and the audit arithmetic
    panes.js       the palette / config-form / findings view models (d9-d11)
    palette-pane.js the left pane, rendered from the registry
    inspector.js   the Config and Findings panes, rendered
    shell.js       the shell's own behaviour: tabs, theme, document loader
  fixtures/
    documents/     the two demo documents
    datamodel.json typed, scoped datamodel for the panel and the conditions
  dev/
    selftest.html    browser-run assertions over every pure module above
    theme-audit.html the same arithmetic pointed at the real stylesheets
```

Open `index.html?doc=signup-wizard` to load a named fixture directly; the
default is `card-processing`, the deep one.

## The canvas, in two passes

`layout.js` turns `{document, registry}` into a layout tree - a shape and an
arrangement per block, its slots partitioned into primary and secondary, and
each arm's guard read off the block type's config schema. `render.js` emits
that tree as nested DOM and *then* measures what the browser laid out and
draws the connectors over it. Nothing computes a coordinate: the browser does
the layout, and the connectors are derived from where the cards actually
landed.

Three derivations do the structural work, and every one of them reads
ADR-0005 decision 10's presentation metadata rather than a type name:

| Rendering | Derived from |
|---|---|
| primary slots side by side | `layout: :columns`, or more than one primary slot |
| lanes ("all of") vs arms ("one of") | `layout: :columns` distinguishes the two |
| an interrupt rail with exit edges | a slot whose `slot_style` is `:secondary` |
| a boundary box around a body | the same - a rule needs a region with an edge |
| an arm's condition pill | an `:expression` config field keyed by the slot name |
| a compact chip instead of a card | a leaf whose whole schema is one `:duration` |

## The panes

`panes.js` is to the three panes what `layout.js` is to the canvas: the pure
half. Which palette entries match a query and where they were matched, which
controls a block's `config_schema/1` derives into, what a finding's anchor
resolves to - all answerable without a browser, so `dev/selftest.html`
answers them there rather than probing a rendered page.

| Pane | Contract | Notes |
|---|---|---|
| Palette | ADR-0005 d10 | Rendered from the registry, so registering a block type is all a host does. Search matches label, type name, description and declared `keywords`, and says which when the match is one the reader cannot see. |
| Config | ADR-0005 d9 | Schema-driven over ADR-0002 d7's closed field-type set. Edits commit on `change`, as one `update_config`; d9's gate refuses invalid config, and the refusal is shown under the field without discarding what the author typed. |
| Findings | ADR-0005 d11 | Anchored: clicking a row selects and reveals its target, unfolding every collapsed ancestor over it. Count badge on the tab, and the collapsed-card badges count the same set. |

Two things there are worth naming because they are proposals rather than
readings of the record, and both are noted on `sb-8cm`:

- **A third severity.** d11 spells severity as `:error | :warning`. The pane
  renders `info` as well, for advisory lints that read wrong in warning
  chrome. Every `info` is `origin: "demo"`; no validation path produces one.
- **A static demo finding set.** Alongside the real findings `layout.js`
  computes, `panes.js` carries a small per-document set covering the shapes
  validation cannot currently produce - a `:slot` anchor and the `:lint`
  source. Rows say which half they came from, so a screenshot is not
  ambiguous.

There is no decimal control, on purpose: ADR-0001 d6 forbids floats in
config, so a decimal is a `:string` holding `"12.50"` and the text control
stores and round-trips it unchanged. Adding a `:decimal` field type would
widen a closed set to describe something the set already covers.

## The three themes

One mechanism, exercised three ways:

| Theme | How it is selected |
|---|---|
| Light | the default, declared on `.sb-spike` |
| Dark | `data-sb-theme="dark"` on the container or any ancestor |
| Host brand | `data-sb-theme="host-brand"`, from `css/themes/host-brand.css` |

`host-brand.css` is the proof, and it holds itself to a hard rule: a theme
file may set `--sb-*` properties and may do nothing else. No structural rule,
no `sb-` class, no layout. If a restyle turns out to need something that file
is not allowed to do, that is a finding about the token surface and the fix
goes in `tokens.css`.

The theme selector in the top bar switches between all three at runtime, and
it reads the container's current `data-sb-theme` on load rather than assuming
light - a control that disagrees with the screen behind it is worse than no
control.

`dev/theme-audit.html` checks all of that rather than asserting it in a
comment: contrast ratios, token coverage in both directions, whether each
theme restates every colour it has to, and whether `host-brand.css` is still
pure. Open it beside the editor.

## Theming: what a host overrides, and how

Everything below is what the spike learned by taking the dark theme to parity
and making host-brand carry the whole surface (`sb-957`). The mechanism is
ADR-0005 decision 14's; what W4 established is what the surface has to
CONTAIN for that mechanism to be enough.

### The three tiers

A host reaches for exactly one of these, and which one says how much it is
taking on.

**Tier 1 - the palette.** Eleven or so colour tokens and the shape and type
scale. Set these and the whole editor moves: `--sb-bg*`, `--sb-fg*`,
`--sb-border*`, `--sb-accent*`, the status colours, `--sb-radius*`,
`--sb-font`, `--sb-space`. This is what most hosts want and it is a couple of
dozen lines.

**Tier 2 - the treatments.** Named marks that a host may reasonably disagree
with, each with its own token so that disagreeing with one does not mean
overriding a rule:

| Token family | The mark |
|---|---|
| `--sb-drop-ok-*`, `--sb-gap-*` | the drag affordance: which slots accept, how tall the seam grows, what the armed bar is painted in |
| `--sb-run-mark*` | the ring a replayed fixture step puts on a card - its own colour, width and offset, so it stays tellable apart from selection |
| `--sb-ghost-*` | the chip that follows the pointer. Inverted by default; dark reverses the inversion, which is the reason it is three tokens and not `var(--sb-fg)` in a rule |
| `--sb-connector*` | the rendered edges |
| `--sb-syntax-*`, `--sb-path-*` | the condition editor's five roles and its known/unknown path underlines |
| `--sb-focus-*` | one focus treatment for the whole subtree |

**Tier 3 - `--sb-color-scheme`.** The one property that is not a colour and
cannot be replaced by one. It tells the BROWSER which scheme to paint its own
chrome in: a `<select>`'s drop-down, both pane scrollbars, the text caret, the
selection highlight. Nothing in `tokens.css` can reach those, and a dark
theme that omits this has a top bar whose controls open a white menu over a
dark editor. `editor.css` reads it as `color-scheme: var(--sb-color-scheme)`
on `.sb-spike` - scoped to the container, never on `:root`, because telling
the host page which scheme it is in is the editor reaching outside its box.

### Per-block-type identity

A host that registers its own block types usually wants them to LOOK like its
own. The hook is one field and no CSS:

```js
// in the block type's paletteEntry
accentToken: "--sb-accent-myapp"
```

and one declaration in the host's theme file:

```css
.sb-spike[data-sb-theme="host-brand"] {
  --sb-accent-myapp: #8a4a1f;
}
```

The renderer stamps `data-sb-block-accent="<the name>"` on the card and the
palette row and rebinds `--sb-block-accent` on that element to
`var(<the name>, var(--sb-accent))`. Three consequences, and they are the
point:

- **The editor never learns a type name.** No rule in `editor.css` and no
  branch in any module mentions `myapp.capture`. `js/theme.js` validates the
  name against `/^--sb-[a-z0-9-]+(-[a-z0-9-]+)*$/` and falls back to the
  editor's accent for anything else, so a typo in a host's registry degrades
  to the default rather than to a broken card.
- **The value is decided by the theme, not by the block type.** A descriptor
  carries a token NAME, never a colour - the same discipline `icon` is under,
  and for the same reason: a block type that named a hex value would be
  deciding what it looks like in themes it has never seen.
- **Adding a type with its own identity adds no CSS.** Two rules read
  `--sb-block-accent` (the icon tile, and a `::before` stripe on the card),
  and they are the only two.

Two more tokens shape the treatment rather than colour it:
`--sb-block-accent-mix` is how much of the accent the icon tile is tinted
with (dark raises it, because 14% of a pale colour over near-black is not a
tint), and `--sb-block-edge` is the stripe's width - set it to `0` to keep
the colour and drop the stripe.

The spike demonstrates the layering with `myapp.capture`, which points at
`--sb-accent-myapp-capture` instead of the family's token. Light and dark
resolve that to the family colour and the whole `myapp.*` group reads as one;
host-brand gives it a hotter red, so the block type that moves money stands
out from its own family. Same document, same DOM, same JavaScript, one line
in a theme file.

### A badge is metadata too

The same seam, one key further along. A block type may declare

```js
// in the block type's paletteEntry
badge: "calls the host"
```

and the card grows a small outlined chip in its meta row, between the type
caption and the config chips. Three types declare one: the proposed
`core.invoke` and `core.raise`, and `core.wait`, whose badge says "timer"
because the one thing a reader cannot get from "Wait for 2m" is that the
compiled form is a delayed send rather than a sleep.

It earns its place for the same three reasons the accent hook does. The
editor never learns a type name - `render.js` draws whatever string
`layout.js` hands it, and no rule in `editor.css` mentions a type. The value
is normalized in one place (`badgeFor` in `js/palette.js`), which refuses a
non-string, an empty string, a newline, and anything past 24 characters, so a
host that declares a sentence gets the ordinary card rather than one with its
title squeezed out - the same degrade-to-default rule a malformed accent
token is under. And it needs no CSS from the host, because it is deliberately
uncoloured: a config chip is a value the author set and is filled in the
accent, while a badge is an annotation the type carries and is outlined in
`--sb-border-strong`. The card already has one identity, in its accent
stripe; a second one would argue with it.

Whether this belongs in ADR-0005 decision 10's metadata is a Phase-B finding,
exactly as `accentToken` is.

### A join marker that reads the config (sb-dxs)

One key further still, and the first one that is a **function** rather than a
value. Every block whose slots are arranged side by side draws a marker under
the columns, and until now that marker said `continue` for all of them. Once a
block type can carry a completion rule in its config that string is a
half-truth, so a type may now declare

```js
// in the block type's paletteEntry
joinLabel: (config) => (config.complete === "first" ? "continue at first" : "continue when all")
```

and the marker reads whatever comes back. `layout.js` resolves it onto the
view model beside the badge and the accent token; `render.js` draws a string
and still never learns a type name, which is the entire reason it is a
callback and not a case in the renderer. A host type that fans into lanes with
its own completion rule declares its own words and gets them.

`joinLabelFor` in `js/palette.js` is the one normalizer, under `badgeFor`'s
rules - a non-string, an empty string, a newline or anything past 24
characters degrades to the old constant - plus one this key needs and the
badge does not: the callback is host code running during layout, so it is
called inside a `try` and a throw degrades too. A bug in a host's `joinLabel`
costs that block its words, not the canvas.

The declaration that motivates it is a **proposed config key on a shipped core
type**, which is a sharper divergence than the proposals in
`js/proposed-core.js` and is flagged in the open at the descriptor.
`core.parallel` gains `complete: all | first`, defaulting to `all`:

- **`all`** is the statifier-native reading. The lanes are a `<parallel>`, the
  region is done when every lane is final, and that compiles to a
  `done.state` transition on all-final. Nothing downstream is new.
- **`first`** is an open Phase-B semantics question, not a decision taken
  here. First-lane-wins is not a `<parallel>` completion rule; expressing it
  means cancelling the losing lanes, and what cancelling does to a lane
  mid-invoke is a contract question this spike is not entitled to answer. It
  renders, it validates, it labels its marker, and it compiles to nothing.

The default is a **read-time** default, which is what makes it safe: every
`core.parallel` in the demo documents predates the key, none of them was
edited, and `dev/selftest.html` pins that an absent `complete` decodes,
validates and lays out exactly as it did before - down to a stored `null`
still reaching the refusal rather than being coalesced into the default, which
is ADR-0001 decision 6's distinction.

Whether a callback belongs in decision 10's metadata at all - every other key
there is inert data - is the Phase-B finding this one adds.

### What W4 found the d14 surface was missing

Four holes, all closed by widening `tokens.css` rather than by letting a theme
write a rule. They are the spike's input to a d14 amendment, not a decision
taken here:

1. **No `color-scheme`.** The largest of the four. A colour-token surface
   cannot reach the parts of a component the browser paints, so "every colour
   is a token" was not sufficient for a dark theme, and the failure was
   invisible until someone opened a `<select>`.
2. **Marks with no name.** The replayed-step ring hard-coded its width and
   offset and borrowed `--sb-accent`; the drag ghost hard-coded a foreground
   /background inversion that produces a white chip in a dark theme. A
   treatment a theme must be able to reverse needs tokens of its own.
3. **Declared-and-never-read tokens.** `--sb-gap-height` and
   `--sb-gap-hover-bg` were declared in W0 and consumed by nothing. That is
   worse than a missing token: a host sets it and nothing moves. The audit
   now fails on either direction, and one reserved token
   (`--sb-connector-active`) was retired rather than left as a promise.
4. **No per-block-type seam.** d14 gives a host the editor and gives it
   nothing below the editor. The `accentToken` hook above is the proposal.

A fifth is a judgment rather than a hole: `--sb-border-strong` sat near
1.9:1 in all three themes and now clears 3:1. `--sb-border` deliberately does
not - it is the divider between two panes of the same surface, decoration
rather than a boundary carrying information, and holding it to a ratio turns
every pane edge into a rule.

## What the polish pass found (sb-vhu)

W5 walked every surface against a written checklist - alignment, spacing
rhythm, type scale, contrast in all three themes, hover, drag and focus
states, connector legibility at depth, and viewport widths down to 1024px -
and worked the queue of defects the earlier beads had noted in passing. Four
of the findings are about the spike's mechanisms rather than about one pane,
and those are the ones worth carrying forward.

**A reset that out-specifies is a reset that fights.** `reset.css` said so
about buttons in W2 and then did the same thing to block elements: `.sb-spike
p` and `.sb-spike pre` score one class plus one element, which beats any
single-class component rule, so `.sb-hint`'s `margin-top`, `.sb-code`'s
`padding`, `.sb-empty`'s padding and `.sb-pane__title`'s font size were all
being silently stripped by the layer that exists to make room for them. The
symptom is quiet - a hint flush against the line above it, a pane title one
step too large - which is why it survived four beads. The whole block is
`:where(.sb-spike)` now, and the six rules that had escaped locally by
qualifying themselves with an element name (`p.sb-datamodel__none`,
`ul.sb-datamodel__list--nested`, and four others) dropped the qualification.
This is the spike's clearest input to whether a scoped reset belongs in the
shipped package: it does, and every selector in it has to be zero-specificity
on the container half or it is a bug generator.

**A padded scrollport needs a sticky idiom, not a sticky rule.**
`.sb-pane__body` is both the scroller and a padded box, and content scrolls
THROUGH the top padding rather than being clipped at it - so a header stuck at
`top: 0` has a band of moving rows above it. The three declarations that fix
it (negative offset, equal negative margin, matching top padding) are one
mechanism and none works alone, which is why two earlier attempts at the
inspector's datamodel header each got half of it and concluded the palette's
idiom would not transplant. It transplants. The arithmetic lives in one
`.sb-sticky-head` rule now and a new pane joins by adding a selector.

**A clipped scroller has to say so, and a background can only say it where
content is transparent.** Three surfaces clipped silently: the inspector's
read-only config preview, the same preview on the card, and the truth-table
grid. The four-layer background (two covers attached `local`, two shadows
attached `scroll`) is the right answer for the two `pre` surfaces - correct on
first paint, no scroll listener, and it disappears exactly when there is
nothing more to see. It is only intermittent on the grid, because a background
paints below content and the verdict cells carry opaque chips. Making that one
reliable means an overlay, which is a change to the pane's markup and belongs
with the decision about where a truth table lives, not ahead of it.

**A smooth scroll is a request, and a reveal has to check it was granted.**
Anything that scrolls the canvas mid-animation cancels it and the browser
stops where it is, which is how a revealed card ends up pinned to the bottom
edge instead of centred. The reveal now keeps a receipt: `scrollend` fires
once the canvas has actually stopped, the distance from the centre is then a
fact, and an instant correction lands the card where the reveal promised.

Two things were deliberately NOT built, and the reasoning is the finding:

- **No zoom or fit-to-width control.** A canvas-wide zoom is not a stylesheet
  change - it is a transform whose scale every pointer coordinate in
  `interact.js` would have to be divided by, and a drag hit-test that is
  subtly wrong is worse than no zoom at all. What the spike does instead is
  centre the union of a step's active cards, and, when they cannot all fit,
  SAY so in the live region rather than leave the author believing the step
  lit one block. Whether the shipped editor wants a real zoom is a question
  for the panel-design work, with a cost estimate this pass can supply.
- **A `:config` finding still does not switch the inspector to the Config
  tab.** It selects and reveals the block and leaves the tab where the author
  put it. Moving a reader's tab out from under them to show them a field is
  the kind of helpfulness that reads as a bug the second time it happens, and
  the anchor is already visible on the finding row. Held for an operator's
  eye rather than changed on a worker's judgment.

## The proposed vocabulary

`js/proposed-core.js` holds `core.*` block types the package **does not
ship**. They are descriptors written to find out what such a type would have
to declare, registered by `shell.js` through the same caller-supplied registry
value a host uses for its own types (ADR-0002 decision 2). Nothing about them
is decided; whether any of it earns an ADR-0002/0004 amendment is a Phase-B
finding, and each type's own open questions are flagged at the type.

They are a separate file rather than a second map inside `palette.js` on
purpose. `palette.js` is a hand transcription of the shipped core vocabulary,
and that is the only thing it is worth reading it FOR; a map of invented types
living there would cost it that property however loudly it were headed.
`demo-types.js` was split out for the same reason. `coreTypes`,
`coreRegistry()` and `spikeRegistry()` keep answering "what does the package
actually ship", and the proposals sit beside them.

### `core.invoke`, and the `on_error` slot

The first one. A step that calls a host handler and waits for it to answer,
with an optional subtree for the failure case:

- `invoke_type` (required) names the handler, validated against a **generic**
  `namespace:name` - a core type may not know any particular host's namespace,
  so the demo documents' `myapp:*` is a demo fact rather than a rule in the
  descriptor. `assign_to` (optional) is where the result lands. `params` is
  text, one `name=path` pair per line.
- `on_error` is a **slot**, arity `zero_or_one`, styled `secondary` - the
  same declaration `core.group`'s `interrupts` rail already makes, and the
  renderer needs nothing new to draw it.

That last point is the load-bearing one. An outcome path is a slot and never a
port (ruled 2026-08-28; the umbrella's `docs/decisions.md` D13). The whole
editor rests on connectors being rendered rather than authored, which holds
only while every edge in a document is a parent/slot/child relationship; a
port-shaped failure edge would have been the one edge an author draws by hand.

`params` being a plain string is the file's one visible compromise: ADR-0002
decision 7's field types are a closed set and none of them is a list of pairs.
Flattening the pairs into text proves the block type's shape without also
proposing an editor feature. A structured param editor is a Phase-B question;
`parseParams` in that file is the shape it would carry.

Both outcomes are replayed in `fixtures/runs.json`. A step may carry a
proposed `invoke: { block, outcome, payload? }`, and the Fixtures pane lights
that block's badge for the length of the step - the one fact about the step a
reader could not otherwise see, which is that it left the chart.
`run_cp_invoke_done` has the host answer the authorization and then the
capture; `run_cp_invoke_error` has the authorization fail, parks it through the
`on_error` subtree, and carries on to the manual-review group until a reviewer
resolves it.

What that run does NOT do is the point. On an `error` outcome nothing walks the
failure subtree: the next step's `active` ids are ids a human wrote after
reading the document, and the pane says so under the step rather than only in
the fixture file's comment. A runner that looked like it routed the failure
itself would be claiming the one thing this spike has no machinery for. Two
Phase-B findings fell out of writing them: `assign_to` on the authorize block
names `authorization`, which `fixtures/datamodel.json` does not declare, and
what happens once an `on_error` subtree finishes - whether the enclosing group
carries on, and how that squares with ADR-0004's single-final emission - is
undecided, so the run states its assumption instead of rendering it as fact.

The new `badge` palette-entry key is declared here and rendered elsewhere: a
short chip a type may put on its card header, a string under the same
discipline as `accentToken` and `icon`. The editor renders whatever is there
and still never learns a type name. See "A badge is metadata too" below.

### `core.raise`, and the edge that is deliberately not drawn

The second one, and the other half of a wiring the vocabulary could previously
only express half of. `core.on_event` has always been able to catch an event;
nothing in a document could send one. `core.raise` is a leaf with one config
field, `event`, validated against the same event-name grammar `core.on_event`
uses - a name one accepts and the other refuses is a rail that can never catch
what a step raises, so `dev/selftest.html` asserts the two agree rather than
asserting a regex twice.

The signup-wizard fixture uses it end to end. The plan branch now sits inside
a group whose interrupt rail carries `signup.abandoned`, and the branch's
`otherwise` arm nudges the customer and then raises `signup.abandoned`. The
group catches it and abandons, so the provisioning step inside that group
never runs. `run_su_declined` in `fixtures/runs.json` replays it a step at a
time.

The load-bearing part is what that raise is NOT: there is no edge from the
raise to the handler it wakes. The two blocks name the same string in two
places, and the innermost enclosing group is what hears it. That is the same
answer `core.invoke`'s `on_error` gets (D13) reached from the other side -
there an outcome path is a slot rather than a port, here a send is a name
rather than a port - and both protect the same invariant: every edge in a
document is a parent/slot/child relationship, so connectors are rendered and
never authored. A raise with a port pointing at its handler would have been
the first hand-drawn edge in the editor, and a cross-subtree one at that.

What a reader loses is real. `signup.abandoned` on two cards is a weaker cue
than a line, and buying it back is a **rendering** question - highlight the
rails that catch the event of the selected raise - rather than a
document-shape one. Whether the canvas should do that, whether an event no
enclosing rail catches deserves a document-level finding, and whether a raise
should be able to carry a payload (the datamodel fixture already declares
`event.signup_abandoned.last_step`) are all Phase-B findings.

`core.raise` declares no accent token, and the omission is the argument.
`core.invoke` claims one because its work happens outside the chart; a raise
is the most inside-the-chart step there is, so it takes the editor's own
accent like every other core step.

## Serving it

The spike is served as static files. Anything that serves this directory over
HTTP will do; opening `index.html` from the filesystem will not, because the
shell is an ES module and `file://` blocks module loading.

From inside `spike/`:

```sh
ruby serve.rb . 8642
```

Then open <http://localhost:8642>.

`serve.rb` is about fifty lines of Ruby stdlib `socket`: it serves files under
the document root it is given, refuses paths that escape it, and sends
`Cache-Control: no-store` so a reload always shows the current file.

**Why not `ruby -run -e httpd`.** The one-liner is the obvious answer and it
does not work here: `-run -e httpd` is a front end for webrick, which stopped
being a bundled standard library gem. On the Ruby this repository is
developed against (4.0.5) the one-liner fails outright rather than falling
back to anything. `serve.rb` has no such dependency, which is the whole reason
it exists.

To serve on a different port, pass it: `ruby serve.rb . 8080`. Stop the server
with Ctrl-C.
