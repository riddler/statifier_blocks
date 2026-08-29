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
    zoom.js        the canvas scale: the ladder, the fits, and the one
                   coordinate conversion a transform costs
    panes.js       the palette / config-form / findings view models (d9-d11)
    palette-pane.js the left pane, rendered from the registry
    inspector.js   the Config and Findings panes, rendered
    sequence.js    the generation token the async document loader guards with
    shell.js       the shell's own behaviour: tabs, theme, document loader
  fixtures/
    documents/     the two demo documents
    datamodel.json typed, scoped datamodel for the panel and the conditions
  dev/
    selftest.html    browser-run assertions over every pure module above
    theme-audit.html the same arithmetic pointed at the real stylesheets
    narrow.html      the editor in a host box of a chosen width, which is the
                     only way to exercise the shell's container queries
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
| a container with a body to fill | the block type DECLARING a slot (sb-mu2) |

That last row is a rule about types, not about documents, and it is the one
the spike got wrong first: `shapeOf` used to call a block a container only
once a slot HELD something, so a freshly inserted `core.invoke` or
`core.group` drew as a leaf, emitted no body, and therefore offered neither a
"+" gap nor a drop target for the slot it declares. The authoring path the
vocabulary invites could not start. A declared slot is now drawn whether or
not it is occupied, and the empty ones carry a placeholder that names the
slot where no header above it already does.

## The panes

`panes.js` is to the three panes what `layout.js` is to the canvas: the pure
half. Which palette entries match a query and where they were matched, which
controls a block's `config_schema/1` derives into, what a finding's anchor
resolves to - all answerable without a browser, so `dev/selftest.html`
answers them there rather than probing a rendered page.

| Pane | Contract | Notes |
|---|---|---|
| Palette | ADR-0005 d10 | Rendered from the registry, so registering a block type is all a host does. Search matches label, type name, description and declared `keywords`, and says which when the match is one the reader cannot see. |
| Config | ADR-0005 d9 | Schema-driven over ADR-0002 d7's closed field-type set. Edits commit on `change`, as one `update_config`; d9's gate refuses invalid config, and the refusal is shown under the field without discarding what the author typed. A refused edit is held as a per-block **draft** and re-offered with the next one, so a type with several required fields can be filled in a field at a time - see below. The duration control takes what a person types (`1h30m`, `2d`) and stores an *omission* for an empty optional - also below. |
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

### Draft accumulation: filling in more than one required field (sb-5ow)

ADR-0005 d9 validates a config as a **unit** and stores nothing when the
gate refuses. That invariant is the right one - a stored config is always a
valid config - and on its own it made a block type with two required fields
and no usable defaults impossible to configure through a form that commits
one field at a time. `core.assign` is the live repro: fill `path` and the
config still carries an empty `value`, so the gate refuses; fill `value`
afterwards and the edit is computed against the *stored* config, which never
took `path`, so the gate refuses again. Both fields are correct on screen,
the revision never moves, and the author is told twice that a value they
typed correctly is wrong.

The mechanism, ruled 2026-08-29 and implemented here:

- The inspector holds a **draft config per block** - `createDraftStore()` in
  `panes.js`, one `Map` of block id to config, held beside the DOM by
  `createInspector` rather than on the session. A draft is exactly the
  "in-progress form state" d9 puts in transient assigns, and a draft on the
  session would be a config the document model knows about and the gate has
  never seen.
- Every field edit is written through the draft when one is outstanding and
  through the stored config otherwise (`editBase`), then offered to the gate
  **whole**, exactly as before (`commitField`). Nothing about the gate, the
  schema, the command algebra or the undo stack moves.
- The first config that validates lands as **one** `update_config` - one
  revision, one undo step - and the draft is dropped. A refusal stores
  nothing, as it always did; the difference is only that what the author
  typed is now carried forward into the next edit instead of being computed
  away.
- The config pane renders its form over the draft, so a half-filled form
  keeps showing what was typed across a re-render, and the condition pane
  reads the same draft so the two surfaces cannot disagree about what the
  block currently says.
- The **uncommitted-edits affordance** (`.sb-form__pending`) names the
  fields that are outstanding, says why nothing is stored yet, and offers
  "Discard edits". A draft was never a command, so it cannot be undone; it
  can only be thrown away, and that gesture has to exist somewhere.

Two other shapes were considered in that ruling and rejected: relaxing
validation per field, which lets an invalid config reach the document and is
the thing d9 exists to prevent; and seeding defaults at insert time, which
puts values into an author's document that the author never chose.

What the store deliberately does **not** do, and what the shipped editor
will have to decide when it inherits this design under `sb-8dc`:

- It does not reconcile against edits from elsewhere. An undo, a redo, or an
  edit to the same block from another surface changes the stored config
  underneath an outstanding draft, and the draft is left as the author wrote
  it. Dropping a block's draft on any command that touches that block is
  the obvious rule; whether it is the right one is a question about what an
  author expects undo to mean while a form is half-filled, and the spike
  does not answer it.
- Its only automatic clear is a document change, where every block id in the
  store is about a block that is no longer on screen.
- Nothing persists a draft. Reloading the page loses it, which is correct
  for a spike and is a real question for a LiveView that may lose a socket.

Asserted in `dev/selftest.html` under "config drafts": the gate still
refuses each half on its own, two edits in either order produce one revision
carrying both fields, a value the type refuses is still refused with the
document keeping the last config that validated, and discarding returns the
form to the document.

### Placeholders, and the editor's own field (sb-ed7)

Placeholders in the config form were chosen entirely by **control type**: an
expression field says "an expression", a duration says "PT1H30M", and a bare
`string` field says nothing, because there is nothing a type as wide as
"string" can suggest. That rule left the injected `label` field - the first
field every author meets, and the one the canvas titles every card from -
rendering blank beside siblings that told the author what they wanted.

The mechanism, implemented here: **a field may declare a `placeholder`, and a
declared one wins over the control type's**. Three small pieces, none of which
knows a key or a type name:

- `LABEL_FIELD` in `palette.js` declares `placeholder: "Authorize the card"`,
  beside its `label` and its optionality. The editor owns this field
  (ADR-0002's amendment section C: the editor injects it, a type that declared
  one was writing boilerplate), so the editor owns its hint too.
- `fieldView` in `panes.js` carries `field.placeholder` onto the derived
  control view, exactly as it already carries `label` and `default`. Absent
  stays `undefined`.
- `textControl` in `inspector.js` prefers `field.placeholder` over the
  control-type hint it is passed.

That is deliberately **not** a by-key or by-type-name special case, which is
what the finding warned against: nothing downstream tests for `"label"`, and
the same three lines would serve any field that declared a hint. The editor's
own field is simply the only declarer today.

**Open proposal, recorded as a proposal.** Whether a HOST block type may
declare `placeholder` on its own fields is *not* decided here and no ADR is
edited by this change. ADR-0002 decision 7 closes the field **type** set, not
the keys of a field record - `keyLabel` and `valueLabel` are already
presentation-only keys the derivation reads - so admitting `placeholder` is a
widening of the same kind rather than a new mechanism. The argument for
admitting it is that a host type knows what its own `path` or `event` field
should look like far better than the editor does; the argument against is that
every presentation key a schema admits is one more thing a host can make the
form say, and the closed set is what makes the form provable. `sb-8dc` inherits
the question along with the code.

### The truth table moved to a bottom drawer (sb-054)

The condition fixtures - the precomputed truth tables - were the Fixtures
tab's middle sub-view, and the pane had written down what was wrong with that
in three places before it was filed. The inspector is `--sb-inspector-width`
(21rem). A truth table is one column per arm plus one per bound path. The
pane's three workarounds for that were to scroll the grid sideways, to invert
the conventional column order so the verdicts rather than the inputs were the
part on screen, and to say in a sentence under the table that the values were
off to the right.

The operator's ruling is a **bottom drawer**, over keeping the tables in the
inspector until the shipped editor graduates the pattern. What that buys is
the one axis the inspector could never give: the drawer is row three of the
shell grid, so it is the full width of the embed by construction rather than
by a rule that every breakpoint would have to restate.

What moved, and what deliberately did not:

- **The derivation did not move.** `tableView` is still `fixtures.js`'s and
  is unchanged, and its suites in `dev/selftest.html` are untouched. What is
  new beside it is `drawerView`, which decides *which* tables are on screen
  and never what one flattens to.
- **The drawer does not own a selection.** It shows the selected block's
  tables and follows the canvas. A drawer that pinned its own subject would
  be a second cursor in the editor.
- **The way in is anchored to the condition.** The Condition pane renders one
  "Truth table" button per *block* - a branch's arms are separate condition
  fields covered by a single table whose columns are those arms - and only
  when a table exists. A button that opens a drawer saying "nothing here" is
  the affordance teaching an author to stop pressing it.
- **The drawer closes on a document switch** rather than re-deriving, because
  the block it was showing does not exist in the next document.
- **The column order did not change**, and that is now a finding rather than
  a workaround: the verdicts-before-inputs inversion existed because of the
  21rem, the drawer removes that reason, and restoring convention is a
  readability change with its own before/after rather than a rider on the
  move that made it possible.

`drawerView`'s six states - closed, no document, no fixtures, no selection,
none for this block, ready - are asserted in `dev/selftest.html` under
"drawer". Five of the six are reachable only through a sequence of gestures,
which is exactly the shape of thing a screenshot cannot cover and a pure
derivation can.
### The duration control: what a person types, and what empty means (sb-709)

d9 sketched the duration field as "a structured value/unit control emitting
an ISO-8601 string" and left the control itself as an open question. sb-709
gave that question a live failure: `core.send`'s `delay` is the vocabulary's
first **optional** duration, and clearing the field committed `PT0H` - a
zero-length durable timer where the author meant no timer at all - because
`durationFrom("")` had nowhere else to go. "Cleared" and "never set" also drew
differently, which is a distinction the document does not make.

Ruled 2026-08-29 and implemented here as one text box:

- **Predicator duration strings are the primary input**, with the examples on
  screen: `30s`, `15m`, `1h30m`, `2d`, `3d8h`. That is predicator-ex's own
  duration literal, so the string an author types is a string the expression
  language already lexes rather than a spelling this package invented.
- **ISO-8601 is still accepted**, so nothing already stored has to be retyped
  and the escape hatch needs no button to reach. The readout under the box
  names the reading in words and shows the ISO-8601 form the compiler will
  emit, which is how an author who typed `3d8h` finds out it lands as `P3DT8H`
  without having to know ISO-8601 to write it.
- **Empty is absence.** The field commits an *omission* rather than a value
  (`OMIT` and `omitAtPath` in `panes.js`, through the same draft path and the
  same whole-config gate every other edit takes), so a cleared optional delay
  leaves no `delay` key at all - and a cleared field and a never-set one are
  the same value, so they cannot draw differently.
- **The format is checked in the control**, before the gate is asked. A string
  that is not a duration in either grammar never becomes an `update_config`;
  the field says so inline as you type.

The grammar the control accepts mirrors predicator's lexer rule by rule, with
the file and line cited beside each rule in `panes.js` - a run of
`<number><unit>` pairs, no whitespace, lower-case `y mo w d h m s`, with the
two-letter units tried first. It deliberately refuses a strict **subset**:
`ms`, fractional components like `1.5h`, and a repeated unit (`3h2h`) are all
things predicator lexes and this control declines, because the ISO-8601 form
the block types validate has no sub-second component and because picking a
reading of a repeated unit is not this spike's call. Refusing a subset is the
safe direction; accepting a string predicator would reject is the failure the
repo's cross-repo rule is about.

**What the document stores is a PROPOSAL.** Campaign 014's pre-decision D4,
accepted for the spike at kickoff: store the author's own string verbatim and
compile to ISO-8601 at emit time (`Predicator.Duration` on the Elixir side).
That is why `core.wait`, `core.send` and `core.timeout` now validate both
spellings. The shipped `:duration` field type is ADR-0002 d7's and **no ADR
text changes here**; if D4 is not adopted, the alternative that needs no ADR
at all is to compile at commit time and store the ISO string, which is a
change to one branch of this control and nothing else.

Open, and worth an operator's eye when this graduates under `sb-8dc`: the
type-level refusal messages still name only ISO-8601 ("must be an ISO-8601
duration, like PT30S or P1D"), because the selftest pins their text and the
control's own inline message is what an author actually reads. If D4 is
adopted, those three sentences should name both spellings.

Asserted in `dev/selftest.html` under "sb-709": the grammar mirror including
every shape it declines, the compile to ISO-8601, the `''` case reading as an
omission, `PT0S` reading as a set value that a cleared field does not equal,
`omitAtPath` removing a key without mutating its input, and a `core.send`
whose delay is typed, cleared to nothing, and stored again - through
`commitField`, so the omission takes the same draft-and-gate path as every
other edit.

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
with the decision about where a truth table lives, not ahead of it. That
decision has since been made - sb-054 moved the tables to a bottom drawer - and
it downgraded rather than answered this one: at the shell's full width the
fixtures' tables do not clip at all, so the mark is now the answer for a narrow
embed rather than for every reader.

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

## What the second polish pass found (sb-pt1)

The same checklist re-run over the surfaces the proposed vocabulary added -
the `core.invoke` card and its badge, the `on_error` slot in both its shapes,
the join marker's two readings, `core.raise` beside the interrupt rail it
raises into, and the fixture runner's invoke replay. Two findings are about
mechanisms rather than about one surface.

**A descendant selector is a promise that the tree stays shallow.** `on_error`
is the first secondary slot in the spike that can hold a CONTAINER, and both
rules the rail was built out of assumed it never would. `.sb-rail .sb-card`
painted the rail's warning identity onto every card at every depth, so an
ordinary sequence of ordinary steps inside an error path read as five
out-of-band interrupt rules; and the rail's fixed `--sb-rail-width` stopped
clipping and started OVERFLOWING, because nested cards will not shrink below
their content and rendered outside the boundary box, over the connectors and
over the sibling rail. Neither is visible in a leaf-only document, which is
every document the spike had until Phase A. The fix scopes the paint to the
rail's direct members and lets a rail that `:has()` a container size to it;
six of the seven rails in the demo measure identically before and after.

**A blank control is a claim, and it was the wrong one.** `core.parallel`'s
`complete` is the spike's first optional select, and an absent key rendered
the control EMPTY - no option matches `""` - next to a form of filled-in
fields. Every other surface reads the key through its default, so the canvas
was drawing "continue when all" while the form said nothing at all. The
control now names the default in the declared choice's own words, disabled,
because there is no value it could commit to get absence back.

Two queued findings were deliberately NOT fixed, and the reasoning is the
finding:

- **`.sb-chip--config`'s dead rule was deleted, not revived.** Four beads of
  visual judgment - including the badge's ring, chosen so a badge would not
  read as a filled config chip - were made against the plain chip that has
  actually been rendering. Reviving an accent fill nobody has ever seen is a
  new design, and it lands hardest where it fits worst: the chips are on the
  interrupt rules, whose cards already carry the rail's warning identity.
- **An empty container still renders no slots.** `shapeOf` calls a block a
  container only when a slot already HAS children, so a freshly inserted
  `core.invoke` offers neither a "+" gap nor a drop target for its own
  `on_error` - the authoring path that would fill one cannot start. The
  one-line rule that fixes it (a block that DECLARES slots is a container)
  moves the shape derivation that drives arrangement, boundary boxes and
  connector routing for every block, which is a model change and not a polish
  one. **Fixed in sb-mu2**, as its own item with its own re-verification pass:
  both demo documents measure byte-identical afterwards - every node's shape,
  arrangement, boundary flag and rectangle, and all 69 connector paths in
  card-processing - because they fill every slot they declare, which is
  exactly why no machine check in the campaign had ever seen the gap.

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

There are seven, and the sections below take them in this order: `core.invoke`
and `core.raise` (the first two), then `core.timeout`, `core.subchart`,
`core.assign`, `core.send` and `core.foreach`. Every one of them carries a
compile **sketch** rather than a compiler - what the block would emit, which
upstream record owns the part this repo does not, and what is still open.
Nothing in the spike compiles anything.

### `core.invoke`, and the `on_error` slot

The first one. A step that calls a host handler and waits for it to answer,
with an optional subtree for the failure case:

- `invoke_type` (required) names the handler, validated against a **generic**
  `namespace:name` - a core type may not know any particular host's namespace,
  so the demo documents' `myapp:*` is a demo fact rather than a rule in the
  descriptor. `assign_to` (optional) is where the result lands. `params`
  (optional) is a map of name to datamodel path.
- `on_error` is a **slot**, arity `zero_or_one`, styled `secondary` - the
  same declaration `core.group`'s `interrupts` rail already makes, and the
  renderer needs nothing new to draw it.

That last point is the load-bearing one. An outcome path is a slot and never a
port (ruled 2026-08-28; the umbrella's `docs/decisions.md` D13). The whole
editor rests on connectors being rendered rather than authored, which holds
only while every edge in a document is a parent/slot/child relationship; a
port-shaped failure edge would have been the one edge an author draws by hand.

`params` used to be a plain string - one `name=path` pair per line - and the
file called that a compromise in so many words: ADR-0002 decision 7's field
types are a closed set and none of them is a list of pairs. sb-e2x answered it
by widening the set rather than by flattening the data. `params` is stored as a
**map** and edited as key/path rows, both `core.invoke` and `core.subchart`
declare the same field, and the control is driven by the declared type
(`{ map: "string" }`, a PROPOSED member of the closed set) rather than by
either type's name - a host type that declares it gets the same rows.

The storage shape is the part worth arguing about, and `proposed-core.js`
carries the argument: a param binding is two facts, and in the text form
neither had a home that was not a re-parse; a structured control over a
flattened field would have shown an author rows while storing prose. The map
also makes duplicate names structurally impossible and stops a document's
identity depending on the order the lines were typed in (ADR-0001 decision 8
sorts keys). It cost a document migration - five `params` values across the two
shipped fixture documents - which is the honest price of not leaving the
compromise in the bytes. Whether decision 7's set actually gains `{ map: T }`
is an operator's call on a Phase-B finding; the spike is the evidence, not the
decision.

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

### `core.timeout`, the rail rule that fires on the clock

`core.on_event` catches an event; nothing caught the clock. "Interrupt this
group after fifteen minutes, whatever it is doing" is a different shape from
`core.wait`, which is a step inside a body that the chart sits at, and no
shipped `core.*` type expressed it - so the demo documents grew a
`myapp.timeout_rule` crutch to say it. That crutch is retired (D12) and this
descriptor is what replaced it, key for key.

`after` is a `duration`, spelled `after` rather than `duration` because a
wait's duration is how long the step **takes** and a rule's `after` is when it
**fires**; `outcome` is `abandon` or `resume`, spelled exactly as
`core.on_event` spells it, because two rules on one rail whose "Then" menus
disagreed would be the drift this vocabulary repeats itself to avoid; `cond`
is the same optional `expression` guard. It declares
`kinds: ["interrupt_handler"]` and nothing else, and that single tag is the
whole placement rule in both directions - there is no placement check
anywhere and there is not supposed to be one. Whether the vocabulary should
insist on one spelling of "duration" across a step and a rule is a Phase-B
naming question, flagged and not decided.

### `core.subchart`, and a reference rather than an embedding

A step that runs another chart and waits for it, with `core.invoke`'s
`on_error` slot declared character for character - the same slot, because a
child chart that fails and a host call that fails are the same shape of thing
to the author who has to say what happens next.

The child is **named, not embedded**. A body slot holding the child's blocks
inline would be a second copy of a document that already exists with its own
id, its own revision and its own runs, and a document is a tree whose chart is
a build product of it. So the type declares no body slot at all, and D11
settles the spike's half of the reference: the picker offers only the spike's
own fixture documents, derived from `js/fixture-documents.js` rather than
typed into the descriptor, so a reference cannot name a chart the shell could
not open. What it stores is the child document's id - which is the only chart
identity a spike with no compiler has, where a compiler would emit the
identity statifier-ex ADR-0052/0057 defines.

`fixtures/documents/signup-invitations.json` is the fixture built for it, and
`run_si_invited` / `run_si_invite_abandoned` replay the two outcomes. The
child's own steps are **not** replayed: the spike opens one document at a
time, and a run that walked the child's blocks under the parent's name would
be claiming machinery the D4 ruling refuses.

Two open questions the type raises and does not answer. A child chart has more
than two outcomes in general - it can finish in any of its final states, and
"done / error" flattens that to the two an invoke has; how "which final state"
maps to "which slot" is not something ADR-0051's invoke contract or ADR-0004's
single-final emission decides today, so the type has an invoke's two outcomes
and says so. And nothing refuses a reference to the document the block sits in:
`validate_config/1` is handed a config, not a document, so a self-reference and
a cycle through two documents are document-level findings, filed with sb-c2o.

### `core.assign`, the first block that writes

The vocabulary could read the datamodel from the day `core.branch` grew a
`cond` and could never write it. Every value in the demo documents arrives
from a host call or an event payload, so a chart that wanted to record a fact
of its own - a flag it set, a decision it made - had nowhere to put it.
`core.assign` is a leaf with `path` and `value`.

`value` is **source text**: `false`, `42350`, `"manual_review"`, quotes
included for a string. That is the same rule `fixtures/runs.json` already
holds every delta to, and holding both to it is what makes the replay claim
checkable - a run's delta on an assign step and the block's own config are the
same two strings, so the fixture can be compared to the document character for
character rather than by interpretation. `dev/selftest.html` does exactly that.

Two things are deliberately absent. Expressions: `capture_attempts + 1` is the
obvious next `value` and three things would have to be decided first - which
language, how it is stored, and what the spike would then have to refuse to do,
since D4 means an expression-valued assign would replay exactly as a literal
one and the screen would look identical while claiming more. And the
declaration check: nothing asks whether `path` is declared in
`fixtures/datamodel.json`, because that finding wants to be a **warning** and
`layout.js` stamps `severity: "error"` on everything `validateConfig` returns.
Both belong to sb-c2o, which is now the third type to say so.

The replay half is the strongest thing that can be said for a mechanism that
was already there: `core.assign` proposes **no** fixture field at all. The
run's existing `deltas` carry `{ path, value }` and `bindingsAt` already
accumulates them last-write-wins, so an assign step's delta simply is the
step's own work rather than a side effect of a call.

### `core.send`, and the two things it declines to declare

`core.raise` names an event and hands control on, now. `core.send` names an
event and says **when** - `event`, plus an optional `delay` duration. They are
two types rather than one type with an optional key, because a raise is
internal and synchronous while a delayed send outlives the step that armed it,
has to survive a restart, and compiles through infrastructure outside the
interpreter (the `sob-` durable-timers lane; statifier-ex
`docs/durable-timers.md`, ADR-0054/0059). A `delay` key that quietly turned a
raise into a durable timer would make `core.raise`'s whole note false half the
time.

`delay` is the vocabulary's first **optional** duration, which is a state
sb-d9's open control question had never had to express: "no delay" is not
`PT0S` and it is not an unfinished field either. The signup document arms a
`PT2H` deadline, so that question had a case that ships - and it is what
opened sb-709, where clearing the field turned out to commit `PT0H`. The
control is ruled and built now; the config-pane section above says how, and
`delay` is the field it was built against.

Two omissions, both argued rather than accidental. No `target`: what a target
may name is not this repo's decision - session identity is statifier-ex's
(ADR-0052) and reaching the host is the invoke seam ADR-0051 defines, which
the vocabulary already spells `core.invoke` - and a config key that validates
nothing is a proposal made by accident. No `core.cancel`: a cancel names the
send it cancels, which makes it a cross-subtree reference to another block,
the exact shape D13 refused. The alternative that keeps the tree invariant is
scope-shaped rather than reference-shaped - a delayed send is cancelled when
the region that armed it is left - and that is a compiler rule rather than a
block type, which is a strong hint the vocabulary may need no cancel at all.
Either way it is an upstream question no accepted ADR answers.

The badge is a static `sends` rather than `timer` when a delay is set. `timer`
is already `core.wait`'s badge, where it means the chart stays **live** for the
duration - which a delayed send does not say about the block it sits on - and
a badge that changes as a field is typed is a chip a reader cannot learn.
(Whether `badge` should be allowed to be a callback the way `joinLabel` is, is
a Phase-B finding this type is the first real evidence for.)

### `core.foreach`, the container that binds a name

Every container the package ships is about **when** a run of steps happens -
`core.sequence` one after another, `core.parallel` at once, `core.group`
inside a boundary rules fire against. None of them is about **how many times**.
A chart that has to do the same work for each of three invitees could only be
authored by copying the subtree once per item, which is transcription rather
than authoring and goes wrong the moment the list has a length nobody knew at
authoring time.

`core.foreach` declares one `body` slot and three config fields: `items`, a
datamodel path naming a list; `item_as`, the name the item is bound to inside
the body, defaulted to `item`; and an optional `index_as` for the ordinal. The
two names must differ - the only cross-field check in the file, and it earns
its place, because `item_as: "row"` with `index_as: "row"` reads fine and
means nothing.

`item_as` is the genuinely new idea. Every other block reads the datamodel
through paths that exist before the chart runs; this one introduces a name that
exists only inside its own subtree. The demo appearance is in
`signup-invitations.json`, where the subchart that was already there is now
**wrapped** rather than copied - one authored subtree standing for as many
passes as the list has - and `signup.invitees` was added to
`fixtures/datamodel.json` for it.

The bound name is **not** offered in the condition editor, and that is a
deferral with a scope note rather than a gap. The condition surface resolves
paths against one index, built once in `shell.js` as `indexPaths(datamodelDoc)`
and handed to the inspector; it is a fact about the datamodel and knows nothing
about which block is selected. A scoped offering would need an ancestor walk
per selection, a layered index that can distinguish a bound name from a
declared path (rendering them identically would claim the datamodel declares
something it does not), and a new value threaded from `shell.js` through
`inspector.js`. It also needs an answer this bead has no standing to give:
`invitee.email` is only offerable if something knows the item type of the list,
and the datamodel proposal today says `"list of string"` rather than a shape.
So the editor reports a bound name as an unknown path, which is advisory and
never an error - a true answer rather than a flattering one. Phase-B, and it
wants the datamodel-document proposal decided first.

The replay is `foreach: { block, index, item }` on a step - the sb-ig4 pattern
again, and under more pressure than anywhere else in the fixture file, because
a run over a list is the case a replayer is most likely to be mistaken for a
loop. Nothing iterates. The runner does not read the list, does not know its
length, and does not check `index` against it; two steps may both say `0`, and
a malformed index renders as "an iteration" rather than collapsing onto `0`,
because `0` is a legitimate ordinal and coercing to it would put a claim on
screen the fixture never made. `run_si_each_invitee` is two authored passes
over two invitees, and the pane says "recorded, not counted" under the step.

That run also records a real finding about the proposal rather than hiding it:
both passes write `signup.email`, so the accumulator ends on the last one.
Where a per-item result should accumulate is not something `core.foreach`
decides today.

The compile is **sketched and not built**, in two shapes the vocabulary has no
key to choose between. Sequential is a loop-shaped subgraph: the body compiles
once into a state entered with the item bound, its completion transitioning
back to the head with the cursor advanced. That is the open part - SCXML's
`<foreach>` iterates executable content and a body of blocks is states, so the
emission is a state machine rather than an executable-content element, and what
binds the item and where the cursor lives are statifier-ex's calls. Parallel
fan-out is `core.subchart`'s sketch applied N times, one child session per
item, which inherits that sketch's open question and adds a second: what the
parent does when three of five children fail. No `mode` field chooses between
them, deliberately - it would be a key whose two values name two compilers that
do not exist, which is the same argument `core.send` makes for declining a
`target`.
## Zoom, fit, and a narrow embed (sb-bl1)

Three controls the canvas did not have, and one of them is a direct answer to
something W5 wrote down as not worth building. The reasoning W5 gave was
right; its premise was wrong, and that is the finding.

**The zoom sb-vhu costed was costed against a hit-test this editor does not
have.** The note said a canvas-wide zoom "is a transform whose scale every
pointer coordinate in `interact.js` would have to be divided by". There are no
such coordinates. The drag hit-test is `document.elementFromPoint(clientX,
clientY)`, and its nearest-gap fallback compares that same client point
against `getBoundingClientRect()` boxes. Both of those are defined on RENDERED
geometry, so both sides of every comparison are already in viewport space, and
two viewport quantities need no scale factor between them. The reveal
arithmetic is safe for the same reason one step further out: `centerUnion` adds
a viewport-space *delta* to `scrollLeft`, and a delta between two viewport
points does not change with scale.

So the real cost of a transform-based zoom here is **one division, in one
helper**: `routeConnectors` is the only place in the spike that crosses
coordinate spaces, because it subtracts a post-transform origin from
post-transform boxes and writes the result into an `<svg>` that lives inside
the stage and is drawn in the stage's untransformed space. `zoom.js`'s
`scaleOf` and `unscaleRect` are that division, extracted so the self-test
covers it. The two conditions that make the rest correct by construction are
worth stating because a shipped editor has to keep them: the overlays
(`.sb-ghost`, `.sb-picker`) must stay OUTSIDE the transform - they hang off
`.sb-spike`, an ancestor, so the stage's transform never becomes their
containing block - and the scale must be read off the DOM rather than
remembered, so a transform a host applied further up is corrected too.

The generalizable rule for the shipped editor: **an editor that hit-tests
through the browser can be zoomed cheaply, and an editor that hit-tests
through its own arithmetic cannot.** That is a reason to keep
`elementFromPoint` in ADR-0005's drag hook, not merely a convenience.

Verified in the browser rather than argued: a real pointer drag from the
palette onto a chosen gap at 67% landed in exactly the gap aimed at
(`blk_cp_lanes / lane_balance_check / 0`), and the same at 150%
(`blk_cp_validation / arm_valid / 0`).

**A fit that reports success it did not have is worse than no fit.** The first
version announced "Fitted to width at 40%" for the deep demo document, which
wants 38% in a 902px pane and gets the ladder's floor - a third of the tree
still off the edge, and an author told the control had worked. Distinguishing
the three cases needs the UNCLAMPED ratio, because `fitZoom` returning the
floor is ambiguous between "the floor is what fits" and "the floor is as close
as I can get". The same honesty is why the ladder stops at 0.4: below that the
labels stop being readable, and a canvas of unreadable rectangles is a
minimap, which is a different feature with a different design.

**Fit-to-active is the composition, not a new mechanism.** sb-9z3 built the
union-centring and sb-vhu could only announce when the union did not fit.
Zoom-to-fit-the-union plus that same centring is the gesture; when the union
already fits it centres and does not rescale, and when even the floor cannot
contain it `announceSpread`'s sentence still says so. Two defects fell out of
building it, both about time rather than geometry. A reveal's `scrollend`
receipt stays live for 700ms, which is longer than it takes to press a fixture
step and then Fit active, so a stale correction was throwing the fit away -
`setZoom` bumps `settleToken` now, which is exactly what that token is for.
And the centring needs two frames, not one, for the reason `renderCanvas`
already takes two.

**The narrow-embed finding was in the top bar, and no grid change could have
reached it.** The shell would not shrink below about 958px however the pane
tracks were tuned: `.sb-topbar` was a nowrap flex row, so the sum of its five
controls was a min-content floor under the entire editor, and a host box
narrower than that got an editor hanging out of it with the theme selector cut
off at the edge. `flex-wrap: wrap` on that one row - with the shell's first
grid track relaxed to `minmax(topbar-height, auto)` so nothing moves until it
actually wraps - is the whole fix. Chosen over hiding controls at a breakpoint
because which of the five an embed can live without is a product decision.

**A component asks how wide its box is, not how wide the window is.** The
shell's breakpoints are `@container` queries now. An editor in a 900px column
inside a 1900px window is the narrow case that matters, and a media query
cannot see it. Two gotchas, both paid for:

- **A container cannot match its own query.** `container-type` was on
  `.sb-editor__body` first, so rules whose subject was a PANE applied - their
  nearest ancestor container was `__body` - and rules whose subject was
  `__body` itself silently did not. The panes moved to their narrow positions
  inside a grid still using its wide track list, and the inspector was laid
  over the canvas. The container is on `.sb-editor` now, one level out.
- **It cannot go on `.sb-spike`.** That would be the tidier place, and it is
  the one place it must not be: `container-type` applies layout containment,
  which would make `.sb-spike` the containing block for the `position: fixed`
  ghost and picker that hang off it - so the drag chip would be positioned
  against the editor's box instead of the viewport. Correct on the demo page,
  wrong in every real embed, and invisible until one. Exactly the class of
  quiet wrongness this bead's zoom was supposed to avoid.

The breakpoints are chosen by arithmetic against `--sb-canvas-min-width`
rather than by eye, and that floor is a real `min-width` so a future
breakpoint that stops satisfying it overflows visibly instead of silently
squeezing the canvas back to where this bead found it. Measured across the
harness's five widths, the canvas is wider than the inspector at every one and
the shell fits its host at every one - which is the finding the bead was filed
on, closed.

The collapse controls are the other half, and the half that works at any
width: either side pane folds to a rail and the canvas takes the width back.
With both folded, the deep document that could not be fitted at all fits at
59%.

**One thing the transform costs and this bead did not fix.** Scrollable
overflow never shrinks below in-flow layout size, so at scales below 1 the
scroller still reports the unscaled width and there is empty ground to the
right of a fitted document. Zooming IN is fine - the transformed box does
extend the scroll region, and nothing is unreachable at 150%. The fix is a
compensating negative margin reapplied on every render, which is more
machinery than the symptom justifies in a spike; the shipped editor should
decide with a real embed in front of it.

## What graduated (sb-8dc)

The point of a laboratory is that things leave it. `sb-8dc` moved this
directory's findings into the shipped `assets/` and
`lib/statifier_blocks/editor/`, and this section is the pointer so that the
next reader of a spike file knows whether they are looking at an experiment or
at the source of something already shipped.

**Graduated**, and now held by tests in the package rather than by
`dev/theme-audit.html`:

| From here | Where it landed |
|---|---|
| the `:where()`-wrapped scoped reset (`css/reset.css`) | `assets/css/statifier_blocks.css`, scoped to `.sb-editor`, with the 14b specificity rule as a lint in `test/statifier_blocks/theme_audit_test.exs` |
| `--sb-color-scheme` and `color-scheme` on the container (14a) | the same stylesheet, and the same test |
| token coverage in both directions (14e) | `test/statifier_blocks/theme_audit_test.exs` |
| the space, type and shape scales, the third text step, the strong border, the status tints, the drag seam's drag-time height, the canvas sizing constants | the shipped token surface |
| retiring a token nothing reads | `--sb-drop-no-opacity` retired; `--sb-disabled-opacity` says what it is |
| pre-hover validity marking, one-sided | the shipped stylesheet marks the accepting slots and leaves the rest alone |
| `accentToken` (14d) | `accent_token` on the palette entry, read by `StatifierBlocks.ViewModel.accent_token/1` and stamped by `BlockNode` and `PaletteBrowser` |
| the boundary box for a rail-bearing container (10c/10h) | `ViewModel.boundary?/1` and `rail?/1` |
| draft accumulation and the uncommitted-edits affordance (sb-5ow) | already present as `Editor`'s `drafts`; the affordance, the discard gesture and the tests are new |
| placeholders chosen by control type (sb-ed7) | `Editor.Field`, for `:expression` and `:duration` |

**Deliberately did not graduate**, each for a reason rather than for lack of
time:

- **The connectors** (10b, 10d, 10e) and everything in `layout.js`,
  `render.js` and `zoom.js`. Drawing them means measuring laid-out boxes in
  the browser, which is a second JavaScript hook, and ADR-0005 decision 7
  makes a second hook a record amendment. The shipped editor renders nested
  DOM and no edges until that decision is taken.
- **The panes** - `fixtures-pane.js`, `datamodel-pane.js`, the truth-table
  drawer (sb-054) and the `markInvoking` host seam. ADR-0005 decision 15 still
  defers per-palette-entry fixtures to `sui-13q`, so the shipped editor has no
  fixtures surface for any of them to attach to. Inventing one would be
  editor surface the record has not decided, which is the same reason `sb-e3c`
  left its evaluator unwired.
- **The duration control** (sb-709). Decision 9's ACCEPTED text specifies a
  structured value/unit control; the one-text-box predicator-string control
  this spike built is what the still-proposed d10/13 amendment asks the
  shipped editor to decide between. The record is the contract, so the shipped
  control is unchanged and the question goes to the operator with the
  amendment.
- **`badge`, `joinLabel` and the demo `myapp.*` and `proposed-core` types.**
  Each is a proposal about `palette_entry/0` or about a core type's config,
  and none is a decided one.
- **`--sb-syntax-*`, `--sb-path-*`, `--sb-ghost-*`, `--sb-run-mark*`, the
  scroll shadows.** Every one is real, and every one's consumer - syntax
  highlighting, a drag ghost, a replayed step, a clipped scroller - is a
  surface the shipped editor does not have. 14e fails the build on a declared
  token no rule reads, so they arrive with the rules that read them.

Nothing under `spike/` other than this section changed, so `dev/selftest.html`
and `dev/theme-audit.html` still answer for the spike exactly as they did.

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
