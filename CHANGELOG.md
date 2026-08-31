# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Entries for unreleased work are not written here directly. Each issue drops a
fragment in [`changelog.d/`](changelog.d/README.md); the fragments are assembled
into a version section at release. See that README for the format and for when a
change warrants an entry at all.

## [0.9.0] 2026-08-31

0.9.0 is the release where the editor can watch a run. A host hands the
editor the block ids a run has activated and the block it is calling out to,
and the editor draws them on the cards themselves, in the accent and finding
tokens a theme already retunes. The same host seam widens the drawer: a host
contributes its own tabs beside the package's Truth tables and Findings, so a
run feed the host is appending to lives in the drawer rather than beside the
editor. Around that the chrome gives room back - the inspector folds to a
rail the way the palette already does - the config form's fields are dressed
from the same tokens as the palette's search box, and connectors stop
overshooting the cards they point at.

### Added

- The editor's inspector folds to a rail from a chevron on its own header, the
  way the palette already does, giving its width back to the canvas.
- `--sb-inspector-collapsed-width`, the theme token for how wide that rail is.
- The editor takes run marks from its host: `active_marks`, the block ids a run
  has activated, and `invoke_mark`, the block a run is calling out to together
  with how the call came back. Both are ordinary assigns, so a host pushes them
  with `Phoenix.LiveView.send_update/3` and needs no new API; both are held as
  editor state, so a re-render the host makes for its own reasons does not drop
  them; and both are cleared when the host opens a different document, because
  a mark addresses one block.
- The marks reach the markup as `data-run-active`, `data-run-invoking` and -
  only once a call has come back - `data-invoke-outcome` on the block's
  `.sb-node`, and the stylesheet draws them in tokens a host theme already
  retunes: the accent family for the active mark, the finding severities for
  the outcomes. A mark on a folded container stays visible.
- The editor accepts an optional `invoke_types` assign, and an `invoke_type`
  field then offers those types as a suggestion list; free text stays valid
  and an unknown type stays a lint rather than a refusal.
- `StatifierBlocks.Connectors.slots_anchor/1`, the anchor key for a
  container's body box. The editor stamps it on the element holding a
  container's slots, and an interrupt channel is now offset from that box
  rather than from the container's whole node box.
- The editor takes drawer tabs from its host: `drawer_tabs` is a list of
  `%{id:, title:, content:}` descriptors, with an optional `count:`, and each
  one is drawn beside the package's own Truth tables and Findings tabs and
  activates the same way. `content` is a function component, the same seam
  shape `icon` and `expression_component` use, called when its tab is the
  active one. The descriptors are ordinary editor state, so a host pushes them
  with `Phoenix.LiveView.send_update/3` and a feed the host is appending to
  redraws as it grows - a tab whose content changes under the host is what the
  seam exists for.
- The collapsed strip and the unchosen-tab resolution reach host tabs too: a
  document with no truth tables and no findings and a running feed opens on
  the feed rather than on an empty `Truth tables 0`, and a collapsed drawer
  names it.
- `StatifierBlocks.Shell.host_tabs/1` is the admission rule, and
  `StatifierBlocks.Shell.drawer_tab/2` resolves a tab name against the
  package's tabs and the host's together. A host tab named for one of the
  package's own, or repeating an id already used, is not drawn: the id is
  stamped into the tab's DOM id and its panel's. No tab name is ever turned
  into an atom, so a crafted `phx-value-tab` reaches at worst a tab the host
  declared.

The package's own tabs, the drawer's five states, its resize and its collapse
are unchanged, and a host that contributes no tabs gets the drawer it had.

### Changed

- The config form's fields are dressed the way the palette's search box always
  was - a token-built box with a border, a radius and the pane's own fill -
  instead of being left to whatever the host's browser paints a bare `<input>`
  or `<select>` as. The two are now one rule rather than two, so a host
  retuning `--sb-border`, `--sb-radius-sm` or `--sb-bg` moves every control in
  the editor together.
- Placeholder text in those fields takes `--sb-fg-subtle`, and a disabled field
  is muted with `--sb-disabled-opacity`, which is what a disabled `sb-button`
  has always used. Boolean fields, which render a checkbox, are excluded from
  the box by selector and are unchanged.

### Fixed

- Connector arrowheads keep one size at every stroke width and land their tip
  on the endpoint, rather than being scaled by the stroke of the path that
  references them and overshooting the card they point at.
- A flow edge whose head was measured above its tail is drawn level instead of
  ascending, so no arrowhead points back at the block the flow just left.
- An interrupt edge clears the container it exits instead of turning down
  inside it. A container is now as wide as what it holds rather than as wide
  as the box around it, so the box the routing is measured from means what it
  encloses.
- A gap's insertion marker masks the flow line it sits on, and its glyph stays
  legible when the canvas is zoomed out. The dashed placeholder ring stays on
  empty slots only.

## [0.8.0] 2026-08-30

0.8.0 is the release where a container folds shut. A container in the
editor now carries a fold control on its own card, and folding it does not
hide what is inside: a folded container wears a ring badge counting the
findings under it, so a problem stays visible from the outside. Alongside
that, an editor whose host swaps one document out for another fits the new
document the way it fitted the first - the `fit` attr is spent once per
open document rather than once per editor, so a swap now behaves exactly as
a mount does. Hosts: see Removed - the `--sb-fg-on-accent` theme token is
gone, and a theme that still sets it can drop the declaration.

### Added

- A container in the editor folds shut from a control on its own card, and a
  folded container carries a ring badge counting the findings inside it.

### Changed

- The editor's `fit` attr is now spent once per open document rather than once
  per editor: a document the host swaps in is armed from the attr passed in
  that same update and fitted by the next measurement, exactly as at mount. A
  host re-render carrying the document already open still never re-fits, and
  `:manual` or an absent attr still arms nothing.

### Removed

- The `--sb-fg-on-accent` theme token, which no rule in the stylesheet reads
  any more. A host theme that sets it can drop the declaration.

## [0.7.0] 2026-08-30

0.7.0 is the release where a finding looks like a finding wherever it is
read. One row anatomy - severity word, anchor tail, source chip, message -
now draws on the drawer's tab and on both inspector panels, which used to
show the bare message, and the two document-level surfaces carry a severity
pill row above the list. Alongside that, the 24-character presentation cap
on summary chips stops failing silently: a dropped chip raises a `:lint`
warning against its block and `summary_refusals/2` says which chip and why,
so a card with no second line can be told apart from a type that declared
none. And an editor opened with a fit no longer flashes at 100% before
snapping to it. Hosts: see Removed - `:no_presentation_source` leaves
`Finding.from_compiler/2`'s refusal type, and the canvas toolbar's dead
`inserting?` attribute is gone.

### Added

- `StatifierBlocks.Shell.severity_counts/1` cuts a findings list by severity,
  in `:error`, `:warning`, `:info` order and omitting any with nothing at
  them; it sums to `findings_count/1` for the same list.
- `StatifierBlocks.Editor.Findings.row/1` and `anchor_tag/1` are public, so a
  host rendering findings of its own gets the editor's row anatomy rather than
  re-deriving it.
- `StatifierBlocks.BlockType.summary_refusals/2` reports the summary chips the
  24-character presentation cap dropped, as `{index, reason}` with `reason` in
  `:too_long`, `:blank`, `:multiline` or `:not_a_string`, and
  `summary_refusal_message/3` puts one into the words an author reads.

### Changed

- A finding renders the same way everywhere: severity word, anchor tail
  (`config.duration`, `slot:body`, nothing for a block anchor), source chip
  and message. The inspector's two findings panels showed only the message
  before.
- Both document-level findings surfaces - the drawer's Findings tab and the
  inspector's with nothing selected - carry a severity pill row above the
  list. The list itself is still grouped by block.
- The view model raises a `:lint` warning against a block for every summary
  chip the presentation cap refused, so a card that draws no second line can
  be told apart from a type that declared none. A well-formed document gains
  no findings.

### Removed

- `StatifierBlocks.Finding.from_compiler/2` no longer declares the
  `:no_presentation_source` refusal in `from_compiler_error/0`; nothing has
  produced it since the adapter began mapping unplaced compiler findings to
  `:compile`, so a caller that matched on it can drop the clause and keep the
  `{:unanchorable, finding}` one.
- The canvas toolbar's dead `inserting?` attribute, left declared when
  0.6.0 removed its "Cancel insert" button. A host still passing it to
  `StatifierBlocks.Editor.Toolbar` gets an undefined-attribute warning;
  drop the assignment (statifier_blocks#172).

### Fixed

- An editor opened with `fit: :width` or `fit: :active` no longer paints its
  first frame at 100% and then snaps to the fit. While a fit is armed the
  root carries `data-fit-pending` and the stylesheet keeps the stage
  unpainted under it, so the first frame an author sees is the fitted one; a
  host that never imported the measurement hook, and so never spends the fit,
  is revealed by a CSS-only fallback half a second in rather than left blank.

## [0.6.0] 2026-08-30

0.6.0 is the release where the editor tells one story about findings. The
Findings tab reads the whole document when nothing is selected, the drawer's
strip and a host header can finally show the same number, and a container no
longer wears a badge on every uncollapsed face. Alongside that: a block type's
summary draws as a row of chips rather than one joined string, the palette's
search field wears the package's own chrome, and a host can open a document
already fitted to the canvas. Hosts: see Removed - `source: :arity` leaves
`StatifierBlocks.Finding` (pass `:assignability`) and `:compile` joins the enum;
`ViewModel.subtitle/1` now answers only a type label, with the chips behind the
new `summary_chips/1`; `.sb-badge` is rendered by nothing; and the canvas
toolbar's "Cancel insert" is gone, its job done by the palette's Cancel.

### Added

- `StatifierBlocks.Finding`'s `source` gains `:compile`, and
  `from_compiler/2` maps any compiler finding its by-stage rule cannot place
  onto it instead of refusing, so a compile error raised against generated
  SCXML or against the document envelope can be rendered by the editor.
- `StatifierBlocks.Shell.findings_groups/3` groups a document's findings by
  the block each is anchored to, unanchored ones last, without dropping any -
  the grouping behind that panel, and headless like the rest of `Shell`.
- The editor takes a `fit` attr - `:manual` (the default, unchanged
  behaviour), `:width` or `:active` - so a host can open a document already
  fitted to the canvas instead of leaving the author to press `Fit width` on
  every document. The first measurement performs the fit once; after it the
  editor behaves exactly as if the author had pressed the button, and an
  unknown value is refused into `:manual`.
- `StatifierBlocks.Editor.findings_count/3` returns the number of findings the
  editor's Findings tab reports for a document, from the same `document`,
  `palette`, `findings` and `datamodel` a host already passes the component, so
  a host header and the drawer cannot show two different numbers.

### Changed

- A block type's `summary/1` chips draw as a row of separate chips under the
  card's title (`.sb-node__summary`, one `.sb-node__chip` per chip) instead of
  one string joined with `", "`; the row wraps, and a type declaring no summary
  draws no row at all.
- `StatifierBlocks.ViewModel.subtitle/1` answers only the type label an author-
  named card carries, and `nil` otherwise. Read the chips from the new
  `StatifierBlocks.ViewModel.summary_chips/1` instead of the joined string.
- The inspector's Findings tab reads the whole document when nothing is
  selected: the count beside the tab is the document's findings number - the
  same one the drawer's strip and `StatifierBlocks.Editor.findings_count/3`
  report - and the panel lists those findings grouped by block, each row
  selecting its block. Findings anchored to a block the document no longer
  holds get an `Unanchored` group of their own, since they are inside the
  count. With a block selected the tab is that block's findings, unchanged.
  A host styling the panel has three new classes: `.sb-inspector__groups`,
  `.sb-inspector__group` (with `data-block-id` and `data-unanchored`) and
  `.sb-inspector__group-title`, plus `.sb-inspector__group-row` on the rows.
- The palette's search field is drawn by the package - a border, a surface, padding and a radius, all from `--sb-*` tokens - rather than left to whatever box the host's browser paints inside the pane.
- A gap's "+" wears the editor's button chrome at rest, so an insertion point reads as a control without being hovered first. Its hover, armed and drag states are unchanged.
- The finding count badge no longer renders on a container's face. ADR-0005
  places it on a collapsed subtree and the editor has no collapse command yet,
  so a badge on every container read as an error on every card while the counts
  multiplied up the tree. Every finding is still reachable: the node keeps its
  subtree rollup in `data-findings-count`, and the drawer's Findings tab and the
  inspector both list them. A host styling `.sb-badge` should know the class is
  now rendered by nothing.

### Removed

- `:arity` leaves `StatifierBlocks.Finding`'s `source` type. Nothing ever
  produced it: slot arity and undeclared-slot violations arrive through the
  compiler's `:structure` stage and have always carried `:assignability`.
  Pass `:assignability` where you passed `source: :arity`; the finding's
  `{:slot, block_id, slot_name}` anchor, and so where it renders, is
  unchanged.
- The canvas toolbar's "Cancel insert" button. Leaving an insert is the palette's Cancel, beside the line that names the slot the next pick fills, or Escape.

## [0.5.0] 2026-08-30

0.5.0 is the release where the editor behaves like the spike it was drawn
from. It bounds its own height and hands scrolling to the panes; every zoom
step and both fits scale the canvas for real; an arranged container's lanes
size to their own content, so connectors stop crossing sibling cards;
inserting visibly arms the gap the pick will land in, and a palette entry can
be dragged onto one; an unresolvable block's card is compact again, with its
findings and stored config moved to the inspector; the core block types
summarise themselves on a card's second line; nesting depth is banded across
the canvas; the plain controls render as buttons; and a host's `icon`
component is rendered as a function component. Hosts: see Changed -
`.sb-node__raw-config` is now `.sb-inspector__raw-config`, the editor's
buttons carry a new `sb-button` class, and two band tokens
(`--sb-band-even`, `--sb-band-odd`) join the tier-2 theming surface.

### Added

- A palette entry can be dragged onto a gap on the canvas to insert a block of
  that type there. The slots that accept the dragged type highlight as soon as
  the drag starts, exactly as they do when a card is dragged, and the drop
  produces the same insert a "+" and a pick produce.
- `--sb-editor-height` bounds the editor: set it to a length and the panes
  scroll in their own boxes while the drawer stays pinned at the bottom,
  instead of the whole document growing the host page. The default is `auto`,
  so an editor nobody bounds is unchanged.
- Two theming tokens for the editor's nesting bands, `--sb-band-even` and
  `--sb-band-odd` (tier 2). Both default to a surface the theme already
  carries, so a host that restates `--sb-bg` and `--sb-bg-sunken` in its own
  palette bands the canvas without setting either one.
- Block types may export an optional `summary/1`, returning `nil`, a short
  string, or a list of chips, which the editor draws as a card's second line
  when the author has not named the block. It is read through
  `StatifierBlocks.BlockType.summary/2`, which normalises every shape to a
  chip list and drops an over-long chip rather than truncating it.
- `core.parallel`, `core.wait`, `core.on_event`, `core.send` and `core.branch`
  summarise themselves on the card: lane names, `timer <duration>`, the outcome
  and the event, the event, and `N arms + otherwise`.
- `sb-button`, one class carrying the editor's button look, so a host restyling the family changes one selector rather than seven.

### Changed

- The measurement hook's payload carries the canvas panel's usable box under a `viewport` key, read from the element the editor stamps `data-sb-anchor="viewport"`. A host that registers the hooks from the package's default export needs no change; a host that reimplemented the hook against the documented payload should send the new key for the fits to resolve to a number.
- Every slot on the canvas carries `data-sb-depth`, its root-relative nesting
  depth, and the stylesheet paints a full-width band per nesting level,
  alternating by the depth's parity. Depth 0 is deliberately unbanded, so the
  canvas keeps its own dotted ground.
- The interrupt-rules rail has a ground of its own, in the warning family its
  dashed edge already uses.
- `StatifierBlocks.ViewModel.Node` carries a `summary` field, and
  `ViewModel.subtitle/1` returns it for a block whose title is its type's. A
  block the author has named still reads its type's label there.
- An unresolvable block's card reads its type and one short reason; its
  findings and its stored config moved to the inspector, so the card is the
  same width as its siblings.
- The inspector's Block section shows an unresolvable block's stored config
  as canonical JSON, wrapping mid-token rather than spilling past the pane.
- The stored-config `<pre>` moved from the card to the inspector, and its class
  with it: `.sb-node__raw-config` is now `.sb-inspector__raw-config`. A host
  styling the old class should restyle the new one.

### Fixed

- A slot that refuses the block being dragged no longer accepts a drop when it
  sits inside a slot that accepts it. The gaps in the refused slot were live
  targets, and dropping on one put the block in the slot that had said no.
- Every zoom step in the editor toolbar now scales the canvas, and the panel scrolls the scaled size rather than the unscaled one.
- `Fit width` resolves to the largest zoom step at which the chart fits the canvas panel, instead of only recording that the fit was asked for.
- `Fit active` resolves to the largest zoom step at which the selected block fits, and scrolls that block to the centre of the panel.
- A host's `icon` component is rendered as a function component rather than
  applied to a bare map, so it receives a tracked assigns map and may use
  `Phoenix.Component` helpers such as `assign/3` and `assign_new/3`. A host
  that worked around the old behavior by adding `__changed__` to the assigns
  itself no longer needs to; the component must still return a `~H` template,
  which it always had to.
- Connector edges no longer cross sibling cards: an arranged container's lanes
  size to their own content, so a nested arrangement wider than one lane no
  longer overflows into the lanes beside it (ADR-0005 decision 10b).
- Clicking a gap's "+" now visibly arms that gap, and the palette says which
  slot of which block the pick will land in, with a Cancel beside it and
  `Escape` as the way out.
- A palette pick made with nothing armed says why it did nothing instead of
  failing silently.
- A palette narrowed to the types a slot accepts now looks different from a
  palette that simply holds that many types.
- The editor's plain controls - Undo, Redo, Cancel insert, the zoom steps, Fit width, Fit active, and a list field's add/remove - render as buttons rather than as whatever the host's browser paints, with a hover, a muted disabled state and an accented pressed state.

## [0.4.0] 2026-08-30

### Added

- The inspector's Config tab is two labelled sections. **Block** states the
  selected block's type label, its id and the slot it sits in, and renders with
  nothing selected too - three rows in the same place, reading as a dash.
- `StatifierBlocks.Shell.slot_label/2` answers which slot a block sits in, by
  the slot's label rather than its name, with `"root"` for the document root.
- A block type may declare a `:string` config field keyed `label`, and the
  editor draws that value as the card's title with the type's own label as a
  subtitle underneath - so a host's steps read as the names an author gave
  them without the type ever being hidden.
- A card carrying `invoke_type` in its config draws it in mono on a third
  line, which is the fact an author checks most on a step that calls out to a
  handler.
- `StatifierBlocks.ViewModel.title/1` and `subtitle/1` answer what a card's
  two name lines say, and `ViewModel.Node` carries `title` and `invoke_type`
  for a host rendering its own cards.
- The compiler refuses a `core.subchart` whose `chart` names the document the
  block sits in, as an `:emit`-stage `:self_reference` finding against that
  block: a document cannot run itself. A cycle through two or more documents
  needs the host's document graph and stays the host resolver's to refuse.
- `StatifierBlocks.Shell.drawer_tabs/0`, `drawer_tab/1` and `drawer_title/1`,
  in the same shape as the inspector's tab helpers - an unknown tab from a
  crafted `phx-value-tab` resolves to the first one.
- `.sb-findings__row`, `__severity`, `__subject`, `__label`, `__id` and
  `__message`, the row's parts. The severity colour stays on `.sb-finding`
  and its severity modifier, so a host that had restyled one severity keeps
  that styling with no edit. No new custom property.
- A slot's header shows the condition it is subject to: the expression source,
  read-only, in a monospaced chip under the slot's name, clipped to one line
  with the whole of it in the chip's `title`. A branch's arms on the canvas now
  say what picks between them instead of only naming themselves.
- `StatifierBlocks.ViewModel.Slot.condition` carries that source. It is derived
  from the container's own `:expression` config field keyed by the slot's name,
  read through the field's declared `value_path`, so a host block type that
  guards a slot the way `core.branch` guards an arm gets the same chip without
  the editor learning either type's name.
- The palette and the inspector render as framed panes with a header row. The
  palette's names the pane and carries a chevron that folds it to a rail,
  giving its width back to the canvas; the inspector's names the pane and
  states its subject on the right - the selected block type's label, or
  `no selection`.
- `--sb-palette-collapsed-width`, the width the folded palette narrows to
  (tier 2, default `2.25rem`).
- The palette carries a count line under its search box: the size of the
  palette when nothing is filtering it, and how much of it is left plus what
  is doing the narrowing when something is - a query, or the acceptance set of
  the slot the palette was opened from.
- Each group header carries the number of rows currently under it, so a
  filtered section says how much of it survived the filter.
- The editor draws the join marker under a container whose slots sit side by
  side, reading the words the block type's `join_label` callback returns -
  `core.parallel` completing on its first lane says "continue at first" - and
  falling back to the editor's own word for a type that declares none.
- `StatifierBlocks.ViewModel.Node` carries `join_label`, the normalized words
  that callback returned for the block's config, or `nil` when it declared
  none.
- The editor's canvas is a named panel: the toolbar is its header row, with a
  `Canvas` label, a `nested tree` chip, one segmented zoom control, and the
  depth and block-count metrics as right-aligned chips.
- The canvas sits on a bordered, dotted ground, and `--sb-canvas-grid` is the
  tier-2 token a theme sets to change the dots' colour and spacing together.
- The editor draws a `ONE OF` pill above a container whose body slots are
  alternatives and an `ALL OF` pill above one whose lanes run concurrently,
  which is the only place that distinction is stated on the canvas.
- `StatifierBlocks.ViewModel.arrangement/1`, `body_slots/1` and `fan_label/1`
  derive how a container arranges its body slots, shared by the renderer and
  the connector geometry so the layout and the lines cannot disagree.
- `StatifierBlocks.Connectors.fan_anchor/1` and `join_anchor/1` name the two
  markers a fan leaves from and rejoins at, so an edge is no longer drawn
  through the words that say what it means.
- `--sb-card-width` sets the width of a block's card, which is what keeps the
  measured connector geometry from collapsing every edge onto one spine.

### Changed

- **Configuration**'s empty state is a box standing where the form stands,
  saying what selecting a block would let the author do, rather than the
  one-line sentence the other tabs use for having nothing to read.
- A required field is marked with the word `Required` beside its label instead
  of an asterisk on the end of it - the asterisk needed a legend the editor
  does not have and is read aloud as "star".
- The Findings tab's count is a pill in the error hue rather than a tinted
  rectangle, and it is still the block's own findings, never the subtree's.
- The delete control on a card is revealed on hover, on keyboard focus and on
  the selected card, and is hidden at rest. It is still in the DOM and still
  focusable, so the keyboard path is unchanged.
- The card title reads as a title rather than as a native button, and the
  count badge, the subtitle and the invoke line are placed by a grid on the
  card's chrome.
- The per-block-type accent stripe is drawn on cards whose type declared an
  `accent_token` and on no others. A type that declared nothing keeps a plain
  card; its icon tile is unchanged.
- The document-level findings list is the drawer's **Findings** tab, beside
  Truth tables, and no longer a block of text under the canvas (operator
  ruling R4, 2026-08-29, under ADR-0005 ruling 1A: a list of findings is a
  grid of rows about the whole document). Each row carries the finding's
  severity, the block it is about - label and id - and the message, and
  clicking one selects and reveals that block. The inspector's Findings tab
  is unaffected and stays the selected block's findings (3A), as do the
  per-card counts.
- The collapsed drawer strip reports the **active tab**. An author who has
  not picked a tab gets the first one that holds something, so a document
  with findings and no fixtures reads `Findings 4` rather than
  `Truth tables 0`; once a tab is picked the pick stands. A host swapping the
  open document resets the pick along with the drawer's open state.
- `StatifierBlocks.Shell.drawer_view/1` accepts `:tab`, `:findings` and
  `:orphan_findings`, and its result gains `tab`, `tabs`, `findings` and
  `orphans`. `title` and `count` now describe the active tab rather than the
  truth tables specifically; the truth-table `status` values are unchanged.
- `StatifierBlocks.Editor.Findings.findings/1` takes `findings`, `orphans`,
  `root` and `target` instead of `view_model`, and renders the tab's panel
  rather than a headed section: the tab is the heading.
- Slot labels are small, uppercased and letter-spaced - the treatment the fan
  pill and the join marker already carry for chrome that labels a structure.
  The transform is presentation only: the string a block type declares for a
  slot is unchanged, and every other reader still sees it as written.
- Concurrent lanes carry a rule in the block accent across the top of each
  lane's header, drawn off `data-arrangement="lanes"`. The pill above says
  `ALL OF` once; the rule is what carries that distinction down a document
  taller than one screen, where a set of lanes and a set of branch arms
  otherwise look alike.
- An interrupt rail's dashed edge and its heading take the colour the connector
  layer already draws an interrupt edge in, so the rail and the edge leaving it
  read as one thing.
- `StatifierBlocks.Editor.PaletteBrowser` takes a `collapsed` attribute, and
  the editor answers a `palette-collapse` event with one boolean and no hook,
  in the same shape as the shell amendment's other gestures. The fold is not
  reset when the host swaps the open document: it is a preference about the
  pane rather than state about the document.
- The narrow arrangement (ADR-0005 ruling 7A) is unchanged. Below a container
  width of 780 the strip and its sheet are still the palette's whole chrome
  and the pane header stands down, so the fold has nothing to do there.
- A container draws a box around its body only when it is a boundary - a
  container with a slot in the rail partition (ADR-0005 decision 10c, as
  amended by 10h). Every other container draws none: its own card stays at
  the head of its body and its children sit under it with the connectors,
  where a box around each of them turned a deep document into nested
  rectangles.
- A boundary's box is the border, the radius and the inset that enclose its
  body and its rail, rather than the border colour it was before.
- A container's card carries its own border, its accent stripe and its
  selection ring, so the block is still a card on the canvas when the box
  around its subtree is gone. A leaf card is unchanged.
- A palette row is now a tile, a name, and the type's description on a second
  line, at a row height that gives the description room to wrap. The tile is a
  slot rather than an icon: a block type that declared no icon still renders
  the box, so every name in the list lines up.
- A row's accent moved from a stripe down its leading edge onto the tile, which
  is where the card the pick produces carries it. The stamp itself is
  unchanged - a type that declares no accent token still gets neither the
  attribute nor the custom property.
- A `core.wait` mints its delayed send under the reserved `send` role, so a
  chart containing one now compiles to `s_<block id>__send` where it compiled
  to `s_<block id>__timer`.
- The package's default JavaScript export now carries both hooks, so
  `hooks: { ...StatifierBlocks }` registers `StatifierBlocksDrag` and
  `StatifierBlocksMeasure` together - a host that registered only the drag hook
  got an editor with no connectors and no error explaining it. Both names are
  still exported individually, and `statifier_blocks/measure` still resolves for
  a host that wants measurement alone.
- The canvas stage renders inside a `.sb-canvas-panel` element, which is now
  the scrolling box; `#sb-canvas` stays the drag hook's element, the stage
  anchor, and where the `theme` assign's declarations land.
- A container with more than one body slot now lays its slots out side by side
  and fans into them, as a container declaring `layout: :columns` already did -
  a branch's arms no longer stack full-width with each fan edge running down
  through the arm above its target.
- Columns are a CSS grid taking their natural heights, cards are a fixed width
  centred in the box they sit in, and a column's header is card-width and
  centred over the first card it governs.
- The "+" between two blocks is now the insertion marker: subtle at rest,
  highlighted on hover, on keyboard focus and for the whole of a drag, and
  drawn as a placeholder ring in a slot that is still empty. It is the same
  button with the same events, so nothing about the keyboard path changed.
- `StatifierBlocks.Editor.Slot` stamps `data-empty`, and
  `StatifierBlocks.Editor.BlockNode` stamps `data-container` and
  `data-arrangement`, on the markup a host may style against.
- The collapsed drawer's strip reads as a label and a quantity: a small-caps
  title with letter-spacing, and the count as a chip carrying a bare number
  rather than a parenthesised one inline with the title.

### Removed

- The stub exit tick a rail drew below itself in CSS. The exit edge is
  measured and drawn now, and a fixed-length mark beside it was a second claim
  about the same thing that pointed somewhere else.

### Fixed

- Leaving the scope around a `core.wait` cancels the wait's delayed timer, so
  a wait abandoned before its duration elapses no longer leaves an armed timer
  behind in a durable host.
- A `core.subchart` outcome-routing condition is no longer attributed to the
  `outcomes` config field, so a chart finding landing inside it reports
  `fault: :package` with no `config_key` rather than blaming the author for
  bytes the compiler composed.

## [0.3.0] 2026-08-29

Charts get more shapes to compile into. Campaign 015 adds four emitters to the
`core.*` vocabulary - `core.subchart`, which runs another chart and routes on
the outcome the child reported; `core.foreach`, a container whose body runs
once per item of a datamodel list; scope-correct cancellation for a delayed
`core.send`; and `core.parallel`'s `complete: "first"`, which finishes the
block at the first lane's completion and exits the losing lanes. The compiler
gains two root-document options, `terminate:` and `declare:`, a typed
datamodel index that refuses a document reading a path the host declared
sensitive, and predicator duration strings wherever a duration is typed. In
the editor, connectors graduate out of the spike, a default icon set ships so
a host needs no asset pipeline to get one, and the shell is laid out as the
arrangement record describes it. This is a minor bump because every block's
conventional `<final>` moves from `s_<block>__done` to `s_<block>__o_done`:
the compiled bytes of every outcome-bearing chart move with it, so a host that
stores compiled charts or provenance maps recompiles them, and a chart-level
position saved against the old bytes no longer resolves.

Dependency floor: unchanged - `statifier ~> 2.2` and `predicator ~> 9.0`.

### Added

- A `core.subchart` block type: a step that runs another chart and waits,
  routing `done.invoke` on the outcome the child reported
  (`_event.data.outcome`) to one slot per declared outcome, with
  `core.invoke`'s `on_error` slot unchanged for a failed invocation.
- A `core.foreach` block type: a container whose `body` runs once for each
  item of a datamodel list, compiled as a plain SCXML loop - a per-loop cursor
  and a snapshot of the list taken once on entry, the `item_as` and `index_as`
  bindings re-assigned from that snapshot on each pass, and the body compiled
  once with an internal loop-back transition. Iteration ends on the
  out-of-bounds read, `snapshot[cursor] === undefined`.
- `core.parallel` accepts a `complete` config key choosing when the block is
  done: `"all"` (the default, and what a document stored before the key reads
  as) keeps the shipped rule, and `"first"` compiles the racing rule - one
  transition per lane on the `<parallel>` element itself, taken on that lane's
  own completion event and targeting the block's done final, so the block
  finishes at the first lane's completion and the engine exits the losing
  lanes with their `<onexit>` content and one `CancelInvoke` per live
  invocation.
- Block types may declare `outcomes/1`, an optional callback returning ordered
  `{name, label}` pairs for the ways a block can finish; a type that does not
  export it has exactly one outcome, `done`, and behaves as before.
- A child summary in the compiler context carries an `outcomes` field: the
  child's declared outcomes in declaration order, each with the `<final>` it
  compiled to and the completion event a parent wires on. It is never empty.
- `StatifierBlocks.Compiler.compile/3` accepts `terminate: true`, which emits
  one top-level `<final>` per root-block outcome with no `<donedata>`, so a
  compiled root document reaches `:done` when its root block completes;
  without it a root document never terminates, and passing it together with
  `child_use: true` is refused with an `:emit` finding.
- `StatifierBlocks.Compiler.compile/3` accepts `child_use: true`, which
  compiles a document for use as another chart's child: the emission gains one
  top-level `<final>` per outcome the root block declares, carrying that
  outcome name as done data, so a parent session can see which way the child
  finished.
- `StatifierBlocks.Compiler.compile/3` takes a `:declare` option - a list of
  `{id, expr}` pairs - so a host can declare the `<data>` roots its root
  document assigns to and guards on, hoisted ahead of block-declared roots
  into the chart's single `<datamodel>`.
- `Compiler.compile/3` takes a `:datamodel` option and refuses a document that
  reads a path the host declared `sensitive?: true` into a position the chart
  evaluates against the datamodel; with no datamodel supplied nothing is
  produced.
- A block type may now contribute declared `<data>` roots to the chart:
  `StatifierBlocks.Compiler.DeclaredRoots.declare/2` emits a declaration among
  the block's own children and the compiler lifts every one of them into a
  single top-level `<datamodel>`, in document order. A document that declares
  no roots emits no `<datamodel>` element, so charts compiled before this
  change are byte-identical.
- A new Emit-stage finding, `:duplicate_binding`: a declared root whose name a
  block it sits inside already declares is refused against the declaring block
  and the config field the name was typed into, because early binding makes
  both roots global and the inner one would silently overwrite the outer.
- The compiler refuses a block type that declares a malformed or duplicated
  outcome name with an `:invalid_outcome` Emit finding, against the block
  whose type declared it.
- A chart-stage finding for an expression the author typed carries
  `config_value_span`, the byte range of the offending sub-expression within
  that config value, so an editor can underline the sub-expression rather than
  the whole field.
- `StatifierBlocks.Predicates.Datamodel` indexes a datamodel document - the
  typed, three-scope declaration sb ADR-0006 defines - into a path/entry
  index: the type of a path, the entries under a prefix, whether a path is
  declared, and the record's one total derivation of the declared-path set.
  The index is advisory; an undeclared path is unknown, never wrong.
- `StatifierBlocks.Datamodel.declared_paths/1` accepts such a document as a
  fourth shape, alongside `nil`, a list and a `MapSet`, and projects it
  through that derivation. A document declaring no entries normalizes to the
  empty set - a host claim - rather than to `nil`, which stays reserved for no
  datamodel at all.
- The editor renders the arrangement ADR-0005's shell amendment records: a
  palette, canvas and inspector across three columns with a full-width drawer
  row beneath them, at container-query breakpoints of 1280, 1024, 900, 780 and
  640.
- A canvas toolbar with stepped zoom, Fit width, Fit active, and the
  document's block count and depth.
- The inspector is tabbed - Config, Findings and Condition - where Findings is
  the selected block's own and Condition reads the per-arm predicator source.
- A drawer that is never open-or-gone: collapsed it is a strip carrying a
  title and the document's table count, and opened on a block with no table it
  shows an index of the blocks that have one.
- `fixtures`, an assign carrying `%{block_id => [TruthTable.t()]}`, is what
  the drawer's truth-table tab reads; with none supplied the drawer is still
  present and reads 0.
- `drawer_height` and `on_drawer_resize` are the host's seam for the drawer's
  resizable height, which the host remembers per viewer.
- A `:header` slot the host fills with the outer header - document identity,
  the switcher, the theme control, compile and publish - which this package
  now explicitly does not draw.
- Below 780 the palette collapses to a strip that opens as a sheet.
- `StatifierBlocks.Shell` exposes the shell's arrangement as pure functions -
  the zoom ladder, the document metrics, the drawer's five states, and which
  of a block's fields are conditions.
- Three tier-2 theme tokens: `--sb-palette-width`, `--sb-inspector-width` and
  `--sb-drawer-height`.
- The editor draws connectors. Adjacency inside a slot, a container's entry,
  the fan and rejoin around a container arranged side by side, and a rail's
  exit are rendered as SVG in the LiveView tree, derived from the document's
  shape rather than authored.
- A second JavaScript entry point, `statifier_blocks/measure`, exporting the
  `StatifierBlocksMeasure` LiveView hook. Its whole job is measurement: after a
  render it reads the boxes the browser laid out for the anchors the server
  stamped and pushes them, and it issues no commands and mutates no DOM. A
  host that wants connectors adds one import; a host that does not gets the
  editor it had before, minus the drawn connectors.
- `StatifierBlocks.Connectors`: the connector geometry as pure functions from
  measured rectangles to SVG path data, outside the Phoenix guard, so a host
  can route its own connectors and a test can assert them without a browser.
- Three `--sb-*` tokens for the connector layer: `--sb-edge`,
  `--sb-edge-interrupt` and `--sb-edge-width`.
- `StatifierBlocks.Editor.Icons`, a default icon set the editor uses when the
  host passes no `icon` component. Inline SVG for the eleven names the core
  block types declare, with no font, no CDN and nothing to register in a
  host's asset pipeline. Every glyph paints with `currentColor` and fills its
  tile, so `--sb-block-accent` and `--sb-block-accent-tint` still decide the
  colour and a per-block-type `accent_token` still moves a type's tile with
  its stripe.
- Palette entries render their icon. The `icon` assign the editor passes the
  palette browser was declared and never rendered, so no host could put an
  icon on a palette row; a type now looks the same in the palette as on the
  card the pick produces.
- A slot declaring `slot_style: :failure` renders in its own vocabulary - a
  solid error-family edge, its own `sb-slot--failure` class, and an ordinary
  flow edge where an interrupt rail draws a dashed escape.
- `StatifierBlocks.ViewModel.exit_edge/1` says which edge vocabulary a slot's
  exit is drawn in, and the editor stamps it as `data-exit-edge`.
- The editor takes an optional `datamodel` assign - the paths the host
  declares - and reports a config field whose declared datamodel path is not
  among them as an `:info` finding in the findings panel; with no datamodel
  supplied nothing is produced.
- Block types may declare a config field with `datamodel_path?: true`, saying
  its value is a path into the host's datamodel; `core.assign`'s `path` field
  carries it.
- `StatifierBlocks.Core.Parallel.join_label/1`, declared on the type's palette
  entry, so a renderer draws "continue at first" or "continue when all" from
  the block's config without learning the type's name.
- `StatifierBlocks.DurationInput` reads a typed duration for that control,
  accepting exactly what `StatifierBlocks.Core.Duration` compiles and naming
  the limit a refused value hit.

### Changed

- Every block's conventional `<final>` moves from `s_<block>__done` to
  `s_<block>__o_done` and now raises `done.outcome.<state id>.done` on entry,
  so compiled SCXML moves for every document; a host that stores compiled
  charts or provenance maps recompiles them, and a chart-level position saved
  against the old bytes no longer resolves.
- `Compiler.compiler_version/0` (and every compilation record's
  `compiler_version`) moves to `0.3.0` with the package, per ADR-0004
  decision 6, and is the third input to the byte-determinism guarantee: this
  release is where the outcome-final byte movement is recorded.
- `core.send` now emits its `<send>` with `id="<the block's state id>__send"`,
  so a delayed send can be named after it is armed.
- A delayed `core.send` is now cancelled by its scope: the compiler emits
  `<cancel sendid="..."/>` in the `<onexit>` of the nearest enclosing
  `<state>`, so a pending send does not outlive the sequence, group, region or
  lane that armed it. Charts containing a delayed `core.send` change bytes;
  every other chart is unchanged, `core.wait` timers included.
- `core.wait` accepts a predicator duration string (`1h30m`, `2d`, `3d8h`) as
  well as ISO-8601, stores whichever spelling the author typed, and compiles
  it to the emitted `delay` attribute; its refusal message names both
  spellings.
- `core.wait`'s declared `duration` default is now the predicator string `1h`
  rather than the ISO-8601 `PT1H`, so a newly inserted block starts from the
  spelling an author types. Both spellings stay accepted and each compiles to
  the same `delay` attribute, so no chart's emitted SCXML changes and no
  stored document has to be retyped.
- A `:duration` config field renders as one text control taking predicator
  duration strings, with `30s`, `15m`, `1h30m`, `2d` and `3d8h` shown beside
  it; ISO-8601 is still accepted and the author's string is stored verbatim.
- An empty `:duration` field omits its config key rather than storing an empty
  string, so a cleared field and a never-set field are the same value.
- An icon entry that declares no icon renders no tile, rather than an empty
  one, and a host's `icon` component is never called with a `nil` name.
- An icon name the shipped set does not have renders a neutral mark with the
  name in `data-icon`.
- A `slot_style` this editor does not recognize renders as an ordinary body
  slot instead of reaching the markup unresolved; its children are still
  rendered, still selectable and still saved.

### Removed

- `StatifierBlocks.Editor.Field.units/0`, `format_duration/2` and
  `parse_duration/1`, which served the retired value/unit control. Call
  `StatifierBlocks.Core.Duration.to_iso/1` to canonicalise a stored duration.

### Fixed

- The editor no longer renders a `U+25A1` white square in every icon tile when
  the host passes no `icon`. Passing one still overrides every tile, on the
  canvas cards and the palette rows alike.
- A delayed `core.send` in the body of a `core.group` that carries interrupt
  rules is now cancelled when the group is abandoned. Its `<cancel>` is
  emitted in the body region's `<onexit>` rather than the group's own, and
  abandoning the group exits the region without exiting the group, so the old
  placement never fired.

### Known limits

- A `core.foreach` list holding a `nil` item iterates to its end rather than
  stopping at it: `===` is strict, so only an out-of-bounds read is
  `undefined`.
- Two `core.foreach` blocks in one document may not bind the same name, even
  when neither is inside the other; the second is refused with a duplicate-id
  finding on its `item_as` field.

## [0.2.0] 2026-08-29

The editor ships. Campaign 014 graduated the authoring spike into the
package: `StatifierBlocks.Editor` renders from `assets/` with a documented
`--sb-*` theming surface, a drag marks the slots that accept a block and can
say why a slot refused, and a host registers its own block types through
`Palette.from_modules/2`. The `core.*` vocabulary grows by `core.invoke`,
`core.raise`, `core.assign` and `core.send`; the compiler now evaluates
predicator conditions, refuses slot-arity and undeclared-slot violations, and
adapts its findings into the shape the editor renders.

Dependency floor: `statifier ~> 2.2` (was `~> 2.0`); `predicator ~> 9.0` is
now a direct dependency.

### Added

- `core.raise` raises an event for an enclosing group's interrupt rules.
- `core.assign` writes a literal to a datamodel path.
- `docs/theming.md`: the theming guide - the three tiers of the `--sb-*`
  surface, the scheme token, per-block-type accents, and a complete host
  theme that sets custom properties and nothing else.
- `core.send` sends an event, now or after a delay.
- A block type may declare `slot_outcome_key` in its palette entry, naming the
  config key the blocks in one of its slots carry their outcome under, so a
  renderer can route an interrupt rule's escape without branching on a type
  name; the declaration reaches the view model as `Slot.outcome_key` and the
  resolved value as `Node.outcome`.
- `StatifierBlocks.BlockType.slot_outcome_key/2` and
  `StatifierBlocks.BlockType.outcome_name/2` read that declaration totally: a
  malformed declaration or value is refused rather than repaired, and reads as
  no declared outcome.
- A block type may declare `accent_token`, the NAME of a `--sb-*` property,
  and the editor stamps it on that type's cards and palette rows. Two rules
  in the stylesheet read it; no rule and no module names a block type
  (ADR-0005 amendment 14d, consumption side).
- `StatifierBlocks.Finding.severity_class/1`, and `:info` as a third
  severity for advisory findings (decision 11, amended 2026-08-29). Nothing
  emits one yet; only `:lint` may.
- A form whose config the gate has not accepted names the fields that are
  outstanding, says why nothing is stored, and offers "Discard edits". A
  draft was never a command, so it cannot be undone - it can only be thrown
  away, and that gesture had nowhere to live.
- `:expression` and `:duration` controls carry a placeholder. A bare
  `:string` still carries none: there is nothing a type that wide can
  suggest.
- A theme audit test over the stylesheet, failing in both directions: a
  `var(--sb-*)` with no declaration, and a declared token no rule reads (14e).
- `StatifierBlocks.SlotValidation`, a palette-aware whole-document check for
  a block's declared slots (`:undeclared_slot`) and each declared slot's
  arity (`:slot_arity_violated`).
- `StatifierBlocks.Predicates` evaluates a condition expression against a
  binding context through predicator, returning a boolean or a tagged error.
- `StatifierBlocks.Predicates.TruthTable` builds a checked truth table over
  fixture rows, applying first-match-wins arm ordering.
- `StatifierBlocks.Finding.from_compiler/2` and `from_compiler_all/2` adapt a
  compiler finding into the presentation shape the editor renders, so a host
  can route compile findings through `ViewModel.build/3`.
- `StatifierBlocks.Assignability.seam_reason/4`, `finding_reason/2` and
  `seam_reasons/3` name why a data-flow seam came out the way it did:
  `:not_assignable` and `{:fixable_by, block_id}` for a refusal, and
  `:source_untyped` / `:target_untyped` / `:both_untyped` for a seam that
  passed only because a block declared no type. `seam_reasons/3` is how a
  host finds the parts of its palette it has not typed yet.
- `StatifierBlocks.Assignability.target_verdicts/4` returns every position
  `valid_targets/4` enumerates with its full verdict, and
  `StatifierBlocks.Edit.Targets.slot_verdicts/3` projects those to slots -
  the accepting ones and the reason each refusing one gives.
- The editor stamps a refused slot's reason as `data-drop-reason` beside
  `data-drop`, so a hover affordance can explain a refusal with no
  round-trip and no JavaScript.
- A `core.invoke` block type: it names an invoke type for the host to run,
  sends datamodel values along as `<param>`s, writes the result where its
  `assign_to` names, and takes an optional `on_error` subtree entered on a
  permanent invoke failure.
- `StatifierBlocks.Compiler.Context.outcome_id/2` and `outcome_event/2`, for a
  block type with more than one way to finish: one `<final>` per outcome, and
  the `done.outcome.<state id>.<outcome>` event a parent wires on.
- `StatifierBlocks.Palette.from_modules/2`, the registration API a host uses
  to contribute its own block types: an ordered, explicit list of
  `{type_name, module}` registrations, with `core: true` to sit on top of
  the `core.*` vocabulary. Later entries win. It is still a value - no
  global registry, no application-configuration lookup, and no discovery
  pass.
- A palette entry may declare `badge`, a short chip for the card header, and
  `join_label`, a one-argument function of the block's config phrasing the
  join marker under a side-by-side arrangement (ADR-0002 amendment B).
  `StatifierBlocks.BlockType.badge/1` and `join_label/2` read them.
- Both readers are total and **refuse rather than repair**: a chip that is
  blank, carries a newline or tab, or runs past 24 characters is dropped,
  not clipped, and a `join_label` that raises degrades to the editor's own
  word rather than taking the canvas down.
- `accent_token`, `badge` and `join_label` are admitted keys of
  `t:StatifierBlocks.BlockType.palette_entry/0`.
- The README carries a worked host example - a `myapp.risk_hold` block type
  registered beside the core vocabulary, with a badge and an accent token -
  and it is executed on every build rather than trusted.

### Changed

- `Compiler.compiler_version/0` (and every compilation record's
  `compiler_version`) moves to `0.2.0` with the package, per ADR-0004
  decision 6: a record compiled by 0.1.0 identifies itself as such.
- `--sb-drop-ok-border` moves from `#2f9e5f` to `#2c945a`. The outline that
  says a slot accepts a drop was 2.93:1 on the sunken surface, under the 3:1
  a mark carrying information is held to; the tint follows it.
- `predicator` is now a direct dependency (`~> 9.0`), because
  `StatifierBlocks.Core.Duration` calls `Predicator.Duration.parse/1`. It
  already resolved transitively through `statifier`, so the resolved version
  does not move; naming it records the call.
- The editor's stylesheet carries a scoped reset, and every selector in it
  matches the container through `:where(.sb-editor)` so a component rule
  always wins (ADR-0005 amendment 14b).
- `--sb-color-scheme` is declared and read as `color-scheme` on the editor's
  own container, so the parts of a control the browser paints - a `<select>`'s
  drop-down, the scrollbars, the caret - follow the theme (14a).
- The `--sb-*` surface gains the space, type and shape scales, a third text
  step, a strong border, status tints, the drag seam's drag-time height, and
  the canvas sizing constants that were literals in rules.
- A `:secondary` and a `:failure` slot are both placed as attached rails,
  and a container declaring either is drawn as a boundary box - the rail
  partition, not the `:secondary` partition (amendments 10c and 10h).
- `--sb-drop-no-opacity` is **retired**. A drag now marks the slots that
  accept the block and leaves the rest alone rather than dimming them; the
  disabled-control opacity it doubled as is `--sb-disabled-opacity`.
- The compiler now refuses a document whose slots violate their declared
  arity or name a slot the block type does not declare, instead of silently
  dropping those children from the emission.
- Reasons change no verdict: `:unknown` stays permissive in both positions,
  `Assignability.validate/3` reports exactly the findings it did before, and
  neither finding tuple gained a field.
- `slot_style` admits a third value, `:failure`, for a slot whose children
  are an in-band continuation taken on a bad outcome; `core.invoke` declares
  it for `on_error`.
- The role namespace beginning `o_` is reserved for outcome finals;
  `Context.role_id/2` now refuses such a role with a `:reserved_role` finding.

### Fixed

- The editor's root rule sets `font-family` rather than the `font`
  shorthand, so `--sb-font` reaches the editor. `font: <family-list>` is not
  a valid shorthand, so the whole declaration was dropped and the editor's
  text did not inherit the host page's font as the token promised.

## [0.1.0] 2026-08-27

First release: the authoring layer above the
[statifier](https://hex.pm/packages/statifier) statechart engine. A block
document is the source of truth - a tree of typed blocks, each with a declared
shape - and it compiles one way to SCXML plus a provenance map that points a
runtime position back at the block that produced it. Block types are
host-pluggable: a host registers the types its own domain needs, and the
compiler and the editor work off that registry rather than a closed built-in
vocabulary. The `core.*` structural vocabulary, the compiler, the edit algebra,
and the LiveView editor shell all ship here.

The `Changed` entries below describe the shape of callbacks and metadata as
they stand at this first release; there is no earlier published version to have
changed from.

### Added

- `StatifierBlocks.Document.validate/1` checks a block document's structure:
  schema version, envelope shape, per-block shape, and document-wide id
  uniqueness.
- `StatifierBlocks.Document.to_json/1` encodes a document to ADR-0001's
  deterministic canonical JSON: sorted object keys, no insignificant
  whitespace, empty `slots`/`config`/`metadata` omitted, no floats.
- `StatifierBlocks.Document.content_hash/1` returns a `"sha256:" <> hex`
  document identity over `to_json/1`'s canonical bytes.
- `StatifierBlocks.Document.from_json/1` decodes canonical JSON back into a
  document, structurally and registry-free: unknown block types decode
  successfully, and every refusal is one of ADR-0001's typed error arms.
- `StatifierBlocks.BlockType` behaviour: the nine-callback authoring-time
  extension seam (ADR-0002), five required (`slots/1`, `config_schema/1`,
  `validate_config/1`, `current_version/0`, `emit/2`) and four optional
  (`io/1`, `migrate_config/2`, `fixtures/0`, `palette_entry/0`).
- `StatifierBlocks.Palette`: a caller-supplied `type_name => module` value
  (ADR-0002 decision 2), with `new/1` to build one and a total `fetch/2` that
  returns `{:ok, module}` or `{:error, {:unknown_block_type, type_name}}` and
  never raises (ADR-0002 decision 3).
- `StatifierBlocks.Palette.resolve/2`: resolves a block through the palette and
  migrates its config in memory when the stored `type_version` is below the
  type's `current_version/0` (ADR-0002 decision 8). Migration is applied to the
  returned struct only and never written back to a document; a stored version
  above `current_version/0` hard-errors as
  `{:error, {:block_type_too_new, id, version}}` rather than reading
  best-effort, and a failing or missing `migrate_config/2` surfaces as
  `{:error, {:migration_failed, id, reason}}`.
- The `core.*` structural block types (ADR-0002 decision 10), one
  `StatifierBlocks.BlockType` module each: `StatifierBlocks.Core.Sequence`,
  `.Group`, `.Branch`, `.Parallel`, `.Wait`, `.ResumableGroup` and `.OnEvent`.
  `core.branch` derives one slot and one `:expression` field per declared arm,
  `core.parallel` one slot per declared lane, and each type is the authority on
  its own config through `validate_config/1`.
- `StatifierBlocks.Palette.core/0` and `StatifierBlocks.Palette.core_types/0`:
  the core vocabulary as a palette, and as the plain `type_name => module` map
  a host merges its own entries into.
- Structural placement through ADR-0003 decision 3 kind tags: `core.on_event`
  declares `kinds: [:interrupt_handler]` and the group types accept only that
  kind in their `interrupts` slot, so an interrupt handler is admitted there
  and refused everywhere else, and an ordinary step is refused there - in both
  directions, from the declarations alone, with no special-cased rule.
- `fixtures/0` on `core.branch` (an arm condition evaluated against two
  datasets) and `core.on_event` (one example event payload). The bundle shape
  follows an amendment to ADR-0002 decision 9 that is not yet accepted, and is
  documented as provisional until it is.
- `StatifierBlocks.Assignability`: the one decision function for whether a
  block may land in a slot, checking structural admission by kind tag and
  data-flow compatibility by type-expression identity plus an optional
  host-supplied widening relation (ADR-0003). `check/5` decides a single
  candidate position; `valid_targets/4` lists every position a candidate may
  occupy in a document; `validate/3` reports every finding already present in a
  document; `inbound_type/4` and `assignable?/3` are the two primitives both
  are built from.
- `StatifierBlocks.Assignability.Relation`: the behaviour a host implements to
  widen data-flow compatibility beyond exact type-expression identity. A host
  module can only grow the accepted set, never shrink it.
- `StatifierBlocks.Palette` gains an `assignability` field naming the host's
  `Assignability.Relation` module, set via
  `Palette.new(types, assignability: MyApp.Blocks.Types)`. Defaults to `nil`,
  meaning no widening relation is declared; existing calls to `Palette.new/1`
  are unaffected.
- `StatifierBlocks.Compiler`: the one-way compile (ADR-0004 decisions 1-4,
  6-7). `compile/3` is a total function of `{document, palette}` returning
  `{:ok, %StatifierBlocks.Compiled{}}` or
  `{:error, [%StatifierBlocks.Compiler.Finding{}]}` - no process state, no
  clock, no IO, and no arm that raises. The pipeline runs Document, Resolve,
  Config and Emit, stopping at the first stage that produces errors and
  reporting every error from that stage.
- `StatifierBlocks.Emission`: the structural representation of one SCXML
  subtree a block type returns from `emit/2`, with `element/3` and the
  `child_ref/1` placeholder the compiler splices its children into.
- `StatifierBlocks.Compiler.Serializer`: the deterministic serializer.
  Attributes sorted, one canonical empty-element form, no incidental whitespace
  at all. It is identity-bearing code - chart identity hashes source bytes
  (st-ADR-0052) - and `serializer_test.exs` now enforces the whitespace
  sensitivity ADR-0004 decision 6 named and left unenforced.
- `StatifierBlocks.Compiler.StateId`: `state_id/1`, `state_id/2`,
  `unstate_id/1` and `done_event/1`. State ids derive from block ids
  (`"s_" <> block_id`, `"__" <> role` for an auxiliary state), so they are
  unique, invertible and total over generated states.
- `StatifierBlocks.Compiler.Context`: what a block type is entitled to know
  while emitting - its own ids, the document id, its children's summaries
  (block id, state id, done event) and the role-minting function. No palette,
  and no child's emitted SCXML.
- `StatifierBlocks.Compiled` and `StatifierBlocks.CompilationRecord`: the
  artifact, and the join between document identity and chart identity.
  `chart_name` carries the document id and `chart_version` stays `nil`, so a
  revision bump or a metadata-only edit still matches the identity a running
  session holds.
- `StatifierBlocks.Core.Emit`: the SCXML shapes the `core.*` vocabulary
  compiles to, and the builders a host block type follows to compose with them.
- `StatifierBlocks.Provenance`: the map from generated SCXML back to the blocks
  that produced it (ADR-0004 decision 5). Keyed by state id for highlighting a
  running session's configuration, and by byte span for routing findings that
  carry no element reference. `owner_at/2`, `owner_of_state/2`,
  `owners_of_states/2`, and canonical `to_json/1` / `from_json/1` so a host can
  store the map beside the chart.
- `StatifierBlocks.Compiled` now carries all five of ADR-0004 decision 1's
  fields: `provenance`, `invoke_types` and `warnings` join `scxml` and
  `record`.
- `invoke_types` publishes the sorted set of invoke types the chart emits,
  unconditionally, so a host can compare it against its `Statifier.Session`
  registration at deploy time (ADR-0004 decision 8).
- `Compiler.compile/3` accepts `:known_invoke_types`, an opt-in lint that
  **warns** - never errors - for every emitted invoke type absent from the set
  the caller believes will be registered.
- `Compiler.compile/3` accepts `:entry_type`, ADR-0003 decision 4's
  caller-supplied context, which the new Structure stage passes to
  `StatifierBlocks.Assignability.validate/3`.
- The compiler now runs a **Structure** stage (assignability) and a **Chart**
  stage (statifier's own pipeline over the generated bytes), and maps every
  upstream finding back to the block that caused it.
- `StatifierBlocks.Emission.attributed_to/2`, `from_config/2` and
  `attribute_from_config/3`: the hints a block type leaves so a finding lands
  on the block an author would recognise, and on the config field they typed
  into.
- `StatifierBlocks.Edit`: the editor's command algebra - insert, remove, move,
  and update-config - as a purely structural, invertible rewrite over a
  document with no palette involved (ADR-0005). `apply/2` applies one command
  and returns both the new document and the command that undoes it;
  `check_config/3` is the separate config-validity gate one layer up.
- `StatifierBlocks.Edit.History`: undo and redo over `Edit` commands.
  `commit/4` is the one funnel a host calls - it runs `Edit.check_config/3`
  before `Edit.apply/2`, then pushes the inverse and clears the redo stack, so
  invalid config never reaches the document on any path, undo and redo
  included.
- `StatifierBlocks.Edit.Targets`: `droppable_slots/3` and
  `droppable_slots_for/3`, which slots would accept a dragged block, at slot
  granularity rather than gap granularity, built as a reduction of
  `StatifierBlocks.Assignability.valid_targets/4`.
- `StatifierBlocks.Finding`: the presentation finding ADR-0005 specifies,
  anchored to a block, a slot, or a config field so the editor knows where to
  render it. Distinct from the existing `StatifierBlocks.Compiler.Finding`,
  which serves the compile pipeline.
- `StatifierBlocks.ViewModel`: the structure the editor actually renders,
  derived from a document, a palette, and a list of findings. Resolves and
  normalizes every block's slots, form fields, and palette presentation
  metadata, and routes every finding to the position that renders it.
- `StatifierBlocks.Editor`: the LiveView editor shell (ADR-0005). A
  `LiveComponent` a host embeds over a `%Document{}` and a `%Palette{}`; it is
  the only stateful module in the package's rendered half, and everything it
  does is translate a `phx-` event into one of `StatifierBlocks.Edit`'s four
  commands. Drag is two round-trips - one at `dragstart` to enumerate valid
  slots, one at `drop` - with zero per hover, because validity reaches the
  client as `data-drop` markup rather than as client-side logic.
- `StatifierBlocks.Editor.Canvas`, `.BlockNode`, `.Slot`, `.ConfigForm`,
  `.Field`, `.PaletteBrowser`, `.Findings`: the function components the shell
  renders, each independently renderable in a test. `BlockNode` and `Slot`
  recurse into each other, and there is no per-block-type component: a block
  type's `layout` and `slot_style` presentation metadata is the only thing that
  distinguishes a group from a set of lanes.
- `assets/js/statifier_blocks.js`: the package's entire client-side surface,
  one hook named `StatifierBlocksDrag`, shipped as source. A host adds
  `"statifier_blocks": "file:../deps/statifier_blocks"` to its
  `assets/package.json` and imports the hook in `app.js`; this repository
  bundles nothing and has no Node toolchain.
- `assets/css/statifier_blocks.css`: one stylesheet of structural CSS and no
  visual opinion beyond it. Every class is prefixed `sb-`, every color, space,
  radius and drag treatment is a `--sb-*` custom property with a default, and
  every top-level component takes a `class` attr appended to its own.
- A headless CI job that resolves the dependency tree with `phoenix_live_view`
  absent, compiles it with warnings as errors, and runs the non-LiveView suite
  - the acceptance property that makes the optional dependency's guard
  trustworthy rather than decorative. `STATIFIER_BLOCKS_HEADLESS=1` reproduces
  it locally without disturbing the ordinary build.
- `StatifierBlocks.BlockType`: a config field declaration may now carry an
  optional `value_path`, a list of keys and list indexes from the config root
  down to the value it edits (ADR-0002 decision 7, amended 2026-08-27). A
  declaration without one behaves exactly as before - its `key` addresses
  `config[key]`. The `key` remains the field's identity in both cases: the DOM
  id, the form param name, and what a `{:config, block_id, key}` finding
  anchors to.
- `StatifierBlocks.BlockType.value_path/1`, `fetch_value/2` and `put_value/3`:
  the reader and writer that resolve a declaration to a path and then read or
  write through it. `value_path/1` answers `[key]` for a declaration that
  declares none, so a caller never branches on which case it has.
  `fetch_value/2` is total and answers `:error` for a path that does not
  resolve. `put_value/3` writes the last segment whether or not a value was
  already there - an arm with no condition yet is exactly the one an author is
  about to type into - but never invents an intermediate map or list a block
  type did not write.
- `StatifierBlocks.ViewModel.Field` carries `value_path`, and
  `ViewModel.Field.value_path/1` reads it with the same `[key]` default.

### Changed

- `c:StatifierBlocks.BlockType.io/1`'s return type is
  `StatifierBlocks.Assignability.io/0` instead of `term()`. Every core block
  type already returns a value of this shape; a custom block type implementing
  `io/1` should confirm its return value conforms.
- All seven `core.*` block types implement `emit/2` for real; the
  `{:error, {:not_implemented, block_id}}` placeholder and
  `StatifierBlocks.Core.Config.emit_deferred/1` are gone.
- `c:StatifierBlocks.BlockType.emit/2` is narrowed from
  `(Block.t(), term()) :: {:ok, term()} | {:error, term()}` to
  `(Block.t(), StatifierBlocks.Compiler.Context.t()) :: {:ok, StatifierBlocks.Emission.t()} | {:error, StatifierBlocks.BlockType.emit_error()}`.
  A host block type that was returning something else now has a type to conform
  to.
- `StatifierBlocks.Compiler.Finding` gains `path`, `severity`, `fault` and
  `code`. `fault` is `:author` when a document edit fixes the finding and
  `:package` when it is a bug in this package or a host's block type - which is
  what lets an editor say "this cannot be fixed here" rather than blaming the
  author for a generated state id.
- Findings from every stage come back in document order over blocks rather than
  in the order a stage happened to collect them.
- A bad `:expression` config field now surfaces as an `:author` finding naming
  the arm's config key, rather than as an unrouted upstream error.
- `c:StatifierBlocks.BlockType.palette_entry/0`'s return type is
  `StatifierBlocks.BlockType.palette_entry/0` instead of `map()`. Every core
  block type already returns a value of this shape; a custom block type
  implementing `palette_entry/0` should confirm its return value conforms.
- `phoenix_live_view` is a declared optional dependency at `~> 1.0`, matching
  statifier_ui's floor. Every module under `StatifierBlocks.Editor.*` is
  compiled behind `Code.ensure_loaded?(Phoenix.LiveView)`, and no module
  outside that namespace references Phoenix - so a host that only compiles
  documents adds no Phoenix dependency and compiles no editor code.
- The hex package's `files:` list includes `assets`. The hook and the
  stylesheet ship as source, and source that is not in the tarball is not
  public API.
- Every illustrative example in the package - ADR worked examples, doc
  examples, and the shipped fixture bundles - uses one of the family's two
  canonical example domains: credit-card authorization and capture, or a signup
  wizard with A/B testing.
- `StatifierBlocks.Core.Branch.fixtures/0` ships budget-decision datasets
  (`"approved"` / `"declined"`) and the expression `"budget_remaining > amount"`.
  A host rendering the bundle in a palette panel sees those names.
- The arm-slot and lane-name validation messages on `core.branch` and
  `core.parallel` name `"arm_approved"` and `"capture"` as their exemplars.

### Fixed

- A `core.branch` arm's condition is now readable and editable in the editor.
  `Core.Branch.config_schema/1` keys one `:expression` field per arm by the
  arm's slot name, but the condition is stored at `config["arms"][i]["cond"]`;
  the form previously read and wrote the slot name as a top-level config key,
  so every branch condition rendered empty, no edit to one reached the arm, and
  a junk `config["arm_approved"]` accumulated beside it. Each per-arm field now
  declares `value_path: ["arms", i, "cond"]`, and `StatifierBlocks.ViewModel`
  and `StatifierBlocks.Editor.ConfigForm` read and write through it. `i` is the
  arm's index in the **stored** list rather than its index among the
  well-formed ones, so a good arm below a malformed one still addresses its own
  condition while an author is mid-edit.
- `StatifierBlocks.Editor`'s `field-list-add` and `field-list-remove` events
  read and write the rows through the field's `value_path` as well, rather than
  through the top-level key. A key naming no field in the selected block's
  schema now edits nothing, matching the guard `ConfigForm.decode/3` already
  applied.
- `StatifierBlocks.Assignability.check/5` and `valid_targets/4` no longer raise
  a `MatchError` when the candidate is the document root.
  `Document.fetch_path/2` answers `{:ok, []}` for the root, and the
  vacated-seam check now reads that as what it is - the root occupies no slot,
  so it leaves no seam behind - instead of calling `List.last/1` on the empty
  path. `StatifierBlocks.Edit.Targets.droppable_slots/3` answers `[]` for the
  root rather than crashing, so a caller no longer has to guard around it.

[0.9.0]: https://github.com/riddler/statifier_blocks/releases/tag/v0.9.0
[0.8.0]: https://github.com/riddler/statifier_blocks/releases/tag/v0.8.0
[0.7.0]: https://github.com/riddler/statifier_blocks/releases/tag/v0.7.0
[0.6.0]: https://github.com/riddler/statifier_blocks/releases/tag/v0.6.0
[0.5.0]: https://github.com/riddler/statifier_blocks/releases/tag/v0.5.0
[0.4.0]: https://github.com/riddler/statifier_blocks/releases/tag/v0.4.0
[0.3.0]: https://github.com/riddler/statifier_blocks/releases/tag/v0.3.0
[0.2.0]: https://github.com/riddler/statifier_blocks/releases/tag/v0.2.0
[0.1.0]: https://github.com/riddler/statifier_blocks/releases/tag/v0.1.0
