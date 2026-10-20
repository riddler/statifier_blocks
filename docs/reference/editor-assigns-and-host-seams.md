# Editor assigns and host seams

This page lists what `StatifierBlocks.Editor` holds once mounted, every seam
a host declares to shape it, the two gestures that rewrite a composite, the
limits the canvas draws within, and what the editor leaves to the host.
[How to embed the editor in a LiveView host](../guides/embed-the-editor.md)
puts these to work. `StatifierBlocks.Editor`'s own moduledoc carries the
full assign table.

## Optional dependencies

| Dependency | Declared | Without it |
|---|---|---|
| `phoenix_live_view` | optional | no module under `StatifierBlocks.Editor.*` compiles |
| `statifier_ui` | `{:statifier_ui, "~> 0.8", optional: true}` | an `:expression` field renders this package's plain source input |

Neither is added for you, and nothing warns at compile time when
`statifier_ui` is absent. Its resolution is a runtime `Code.ensure_loaded?/1`
plus `function_exported?/3` against the module named by
`:statifier_blocks, :expression_component_module`, which defaults to
`StatifierUI.Live.ExpressionInput`. Across `lib/` a `StatifierUI` module is
reached in exactly one place, as the default value of that config key.

The package's client-side surface is two hooks, both in the default export of
`assets/js/statifier_blocks.js` and both available as named exports:
`StatifierBlocksDrag`, which turns pointer gestures into commands, and
`StatifierBlocksMeasure`, which reports the laid-out geometry the server draws
the connectors from. Without `StatifierBlocksMeasure` no connectors are drawn
and the editor renders as stacked rows with no flow lines.

## What an `:expression` field renders

| State | An `:expression` field renders |
|---|---|
| no `statifier_ui` on the load path | the plain source input this package has always rendered, with a `<datalist>` of the declared datamodel paths - clause 3 of the ordering `StatifierBlocks.Editor.Field` documents |
| `statifier_ui` resolves, hooks not registered | statifier-ui's own component, since this package passes it no `hook` assign and its attributes take their shipped defaults - but the JavaScript those `phx-hook` names refer to is not in your bundle, so nothing upgrades the field: no caret-aware completion list, and the picklist controls have nothing to write the expression source with |
| `statifier_ui` resolves and its hooks are registered | picklists of field, operator and value while the source is inside the subset predicator can round-trip, a text input over everything else, and caret-aware completion over the declared paths |

Nothing else in the editor changes across those three rows: the canvas, the
palette, the drawer and its tabs, findings, the undo history, the compiler and
this package's own two hooks call no function from statifier-ui. An
`expression_component` the host passes wins over every row (clause 1 of the
same ordering).

statifier-ui's expression editor never refuses what an author typed and never
rewrites it, and every control it draws writes a complete expression source
string into the same input. When the host passes a datamodel **document**, the
kinds it declares reach that editor: a clause on a path declared `integer`
offers the numeric operators, and one on a `date` path the date set. It is a
control and not a check - the operator the source carries is still offered,
the value in it is still kept, and a disagreement renders as an advisory beside
the clause - and a path the document says nothing about renders as it would
with no document.

`StatifierUIHooks` is `StatifierUIExpressionInput` and
`StatifierUIExpressionPicklist`, keyed by the names statifier-ui's component
renders. Hook names and export names are public API under statifier-ui's
ADR-0009, the same as an exported function.

## What the mounted component holds

The `document` passed in, an undo history over it, the current selection, and
a `drafts` map of config edits the validation gate has not accepted yet. A
draft is never in the document and never on the undo stack: a form whose
config has not been accepted names the fields that are outstanding and offers
"Discard edits", because a draft was never a command and so cannot be undone.

The selection is the editor's. The **`selected_id` assign** moves it on any
update that carries it, and the result comes back on `on_select` like any
other selection. An update that does not carry it leaves the author's
selection alone, and an id the open document does not hold clears the
selection. It is not a document edit: no command, nothing serialized, nothing
on the undo stack.

`on_select` is called with a descriptor `%{id:, type:, label:}`, where `label`
is the line the card draws, or with `nil` when nothing is selected. It fires
when the selection changes and not otherwise. The block's config is not in
the descriptor.

The **`datamodel` assign** carries paths rather than logic: the datamodel
paths the host declares. They drive the undeclared-path advisory ADR-0005
amendments `11e`-`11g` specify: a config field a block type annotated
`datamodel_path?: true` whose value is not in that set gets an `:info` finding
anchored on the field. `nil` is the default, and per `11f` the check then does
not run at all, which is not the same as an empty set (a host declaring that
its documents address nothing). Beyond that set the package checks path
*shape* and nothing more; it does not own the datamodel path grammar.

## The host seams

Each seam is a declaration on a value the host already passes in - the
palette, the palette entry, an assign, the document - or a function the host
calls.

| Seam | Declared on | What it does |
|---|---|---|
| `:assignability` | `Palette.new/2` (also `from_modules/2`) | the host's widening relation for "may this block land in this slot" - both gates, kind admission and data flow, run against the palette the caller passed. It runs last, after the datamodel document's own read check (ADR-0003 decision 6 as ADR-0011 decision 3 narrows it) |
| `:validators` | `Palette.new/2` | the host's own whole-document rules: a list of `StatifierBlocks.DocumentValidator` modules, each handed the document as authored and answering `{anchor, message}` (optionally with `severity:`) for anything it objects to. Every module in the list runs, in list order; the package stamps the source `:lint` and defaults the severity to `:warning`, because a host's rule cannot make a document not compile. It is for the rules that are about the document rather than about one block - "a decision step must precede an act step" - which `validate_config/1` has no way to see (ADR-0005 `11p`-`11t`) - [How to write a host advisory finding](../host-validators.md) is the how-to |
| `accent_token` | palette entry | the NAME of a `--sb-*` property, stamped on that type's cards and palette rows |
| `badge` | palette entry | a short chip for the card header, at most 32 characters; a longer one is dropped rather than clipped |
| `join_label` | palette entry | a one-argument function of config, phrasing the join marker under a side-by-side arrangement |
| `subject` | palette entry | a datamodel path. Read from the document's **entry** block - the first block of the root's `body` slot - it names where the document's subject lives, and `io/1`'s `consumes` and `produces` are a read and a write there. Absent means the document has no subject and those two keys declare nothing (ADR-0011 decision 6) |
| `singleton` | palette entry | `:anywhere` or `:head` - how many blocks of this type the document may hold, and (for `:head`) that the one it holds is first in the root's first declared slot. A document that does not comply draws one `:config` finding on the root, one per violating type; nothing is ever inserted, removed or moved for you (ADR-0005 `10z`/`11o`) |
| `slot_outcome_key` | palette entry | names the config key the blocks in one slot carry their outcome under, so a renderer routes an interrupt rule's escape without branching on a type name; it reaches the view model as `Slot.outcome_key` and the resolved value as `Node.outcome` |
| `summary/1` | your own block type | the chips a card draws under its title. A chip longer than 32 characters is drawn clipped to the cap, with an ellipsis in its last position, and the chip's `title` carries its full text |
| `icon` | the `icon` assign | a function component taking `name` and `class`, rendered as if the editor had written `<.icon name={...} class={...} />`; it must return a `~H` template. Unset, `StatifierBlocks.Editor.Icons` draws the names the core block types declare, painting with `currentColor`. A block type declares an icon **name**, never markup, and a type that declares none gets no tile, so the component is never called with a `nil` name |
| `--sb-*` tokens | the `theme` assign, or your own CSS | every colour, space, radius and drag treatment - see [How to theme the editor](../theming.md) |
| compile findings | `findings` assign | `StatifierBlocks.Finding.from_compiler/2` adapts a compiler finding into the shape the editor renders, so a compile result routes back to the field somebody typed it into; `from_compiler_all/2` answers the anchored findings and, separately, the ones it refused with the reason |
| `datamodel` | the `datamodel` assign | the datamodel paths the host declares; drives the undeclared-path advisory of ADR-0005 `11e`-`11g`, and `nil` (the default) turns it off entirely |
| `{:path, opts}` field type | `config_schema/1` on your own block type | says a config field holds a datamodel path - the eighth member of ADR-0002 decision 7's closed field-type set, and the spelling `datamodel_path?: true` already had. `StatifierBlocks.BlockType.datamodel_path?/1` answers `true` for it by construction, so the field carries the same undeclared-path advisory, and the editor renders it as a text input backed by a `<datalist>` of the paths `StatifierBlocks.Datamodel.candidates/3` derives from what the host declared. It suggests and never constrains: free text stays valid, `validate_config/1` stays the only authority, and with no `datamodel` handed in the list is empty and the plain input renders |
| `compile_options` | the `compile_options` assign | the rest of the option list the host compiles this document with - `terminate:`, `known_invoke_types:`, `datamodel:`. The editor recompiles the open document to resolve an execution's state ids back to blocks, and those options change the emission: `terminate: true` alone adds a top-level `<final>` per root-block outcome, so a finished execution sits on a state a recompile without the option has never heard of and the Run pane marks nothing. `:declare` is taken from the `declare` assign whatever this list says, and `[]` (the default) recompiles exactly as it did before |
| `expression_component` | the `expression_component` assign | the control an `:expression` field renders. Unset, it resolves to statifier-ui's expression editor when `statifier_ui` is present and to the package's plain source input when it is not; set, the host's own function component wins over both |
| `value_candidates` | the `value_candidates` assign | the values the host offers per datamodel path, `%{path => [%{label:, value:} \| binary]}`. Read by whatever fills the `expression_component` seam - a path with no entry gets a free-text value control |
| `chart_outcomes` | the `chart_outcomes` assign | what the host says each of its stored documents finishes with, `%{document id => [outcome]}`. A `core.subchart` names a chart by document id and declares its outcomes by hand, because a block type cannot read the document it references; only the host knows which of its documents it compiles with `:child_use` - those are the ones a subchart may name - and what finals each of those emits. The editor offers that list on the `outcomes` field and reports a disagreement between it and what the block declares. A document the map does not name is *unknown*, which is not disagreement: `%{}`, the default, reports nothing about anything |
| `selected_id` | the `selected_id` assign | the block the editor is about, written by a host that draws its own selection surface. Honoured only on an update that carries it; an id the open document does not hold clears the selection. It moves the selection, it does not edit the document - nothing is serialized and nothing goes on the undo stack |
| `on_select` | the `on_select` assign | a one-argument function called with each new selection, `%{id:, type:, label:}` or `nil`. Optional; a host that passes nothing sees no difference |
| `profile` | the `profile` assign | which of the editor's surfaces this mount draws, and whether it edits at all: `%{drawer_tabs:, inspector_tabs:, palette_groups:, toolbar:, read_only?:}`, every key optional and every list `:all` by default. No arrangement of the map, `%{}` included, removes a surface a host did not name, and an id a list names that the package cannot resolve is dropped rather than raised. `read_only?: true` renders the document offering no way to change it - [How to mount the editor for one audience](../profiles.md) works it through |
| `field_candidates` | the `field_candidates` assign | the values a host offers for one field, keyed `{type_name, field_key}`: `[{value, label}]` for a closed list, which a `:string` field draws as a `<select>`, or `{:open, [{value, label}]}` for an open one, drawn as a `<datalist>`. A `{:path, opts}` and an `:expression` field read it too and draw either spelling as a `<datalist>`, ahead of the declared datamodel paths, because the value stays typed by the control. `%{}` (the default) offers none. It draws a control and decides nothing: `validate_config/1` is still the only authority on a value |
| `on_collapse` | the `on_collapse` assign | a one-argument function called with each declaration the "Save as a step" gesture proposes, in `on_select`'s shape. The gesture edits no document and this package persists nothing: which table the saved step lives in, which tenant owns it, and whether it is saved at all are the host's. Swapping the arrangement for the registered type is the host's second act, through the compound `StatifierBlocks.Composite.Collapse.replacement/4` answers. Passing nothing draws no control |
| `debounce` | the `debounce` assign, and `StatifierBlocks.Editor.ConfigForm.config_form/1` / `StatifierBlocks.Editor.Field.field/1` directly | what `phx-debounce` the inspector's config controls carry, for a host persisting what the form posts on its own `on_change`. It takes what LiveView takes - milliseconds, or `:blur` - and defaults to no attribute. It is the same attr from the mount as from the two components. Controls drawn by an `expression_component` override are that component's own and are not covered |
| `event` | `StatifierBlocks.Editor.ConfigForm.config_form/1` | the event name the form posts under, written to both `phx-change` and `phx-submit`. The default, `"config-change"`, is the name `StatifierBlocks.Editor` handles. A host that draws one block's fields under its own `handle_event/3` names its own event here and reads the block the params are about out of the hidden `block-id` input the form posts |
| `fit` | the `fit` assign | `:width` or `:active`: the zoom the canvas opens a document at |
| `capture` | `core.on_event` config, in the document | a map that writes values out of the firing event's payload into the datamodel: the key is the destination (a datamodel path) and the value is the source (a path inside `_event.data`). One `<assign>` per pair is emitted on the handler's own transition, in the destinations' sorted order, before the `<raise>` that carries the outcome. `config_schema/1` declares no field for it - the field-type set has no member that describes a map - so it is authored through the document rather than through the editor. At execution time a source whose root is bound but whose named member is missing writes the interpreter's explicit unbound marker and raises nothing (ADR-0002's capture Note, as corrected 2026-09-05), so a reader of a captured path tests for that marker rather than assuming an authored absence - unless the handler declares a `payload`, in which case the read is checked at compile and the marker write never happens |
| `payload` | `core.on_event` config, an optional `:string` field | the name of a type the datamodel document declares (`StatifierDatamodel.Declarations`), saying what `_event.data` carries **for the event this handler names**. Two handlers for one event may declare different payloads; each governs its own `capture`. With one declared, a `capture` pair whose source path reads a member the payload does not carry is a `:config` refusal on the `capture` key - the first segment against the payload's fields, deeper segments only where the field's own type resolves to another declaration, and a scalar, list or opaque field stops the walk. Absent, blank, naming a type the document does not declare, or compiled with no `:datamodel`: nothing is refused and nothing changes. `payload` emits no SCXML of its own (ADR-0002's amendment of 2026-09-06) |
| `admits_at?/5` | `StatifierBlocks.Edit.Targets`, called by the host | `(document, palette, {parent_id, slot}, type, context)`: whether appending a block of `type` at the end of that slot would be accepted - the question a "+" at the end of a slot asks. It checks the slot's append gap once rather than walking the whole document; a parent that names nothing, an undeclared slot and a full `:exactly_one` or `:zero_or_one` slot are `false`, and so is a type that does not resolve through the palette |
| `accepted_types_at/5` | `StatifierBlocks.Edit.Targets`, called by the host | `admits_at?/5` over a candidate list: the set of `candidates` that would be accepted at `{parent_id, slot}`, the palette's own type names when `candidates` is `nil`. A candidate that does not resolve through the palette is left out |
| `refusal/1` | `StatifierBlocks.Edit.Session`, called by the host | the session's `last_error` as one sentence for a surface to draw, in the words the editor uses for the refused gesture. It never names a block by its id, and a reason it does not recognize gets the generic sentence `"That change was refused."` |
| `expressible/3` | `StatifierBlocks.Plan`, called by the host | whether a document that did not come out of the editor can be expressed with a palette: `:ok` when every block's type resolves through the palette, every block sits in a slot the editor would let an author drop it into - declared, with room, and admitting its kinds - and every empty required slot is one the palette can fill; otherwise `{:no, reasons}`, each reason naming the rule and the block. A read the environment contradicts is not a reason: the editor flags it as a finding. `expressible?/3` answers `true` or `false`. The assignability context is the optional third argument |

The metadata readers are total and refuse rather than repair: a badge that is
blank, carries a newline, or runs past 32 characters is dropped rather than
clipped, an accent that is not an anchored `--sb-*` name never reaches a style
attribute, and a `join_label` that raises degrades to the editor's own word.

## Gestures that rewrite a composite

| Gesture | Where it appears | What it does |
|---|---|---|
| **"Replace with its steps"** | a composite block's card | takes the composite out and puts the blocks it stands for in where it stood, as a single compound edit, so one undo puts the composite back whole. The blocks it writes are the ones `StatifierBlocks.Composite.expand/2` answers inside `{:ok, {blocks, param_map}}` - the same expansion the compiler reads through `expand!/2` at Resolve - which is why the chart compiles to the same bytes on both sides of the gesture. It is refused, and nothing is written, when the slot the composite sits in will not admit the blocks that come out of it |
| **"Save as a step"** | a selected arrangement's card, when the host passes `on_collapse` | a tray for marking which of the arrangement's values the saved step should ask for, then a call to `on_collapse` with the `Composite.Data` declaration `StatifierBlocks.Composite.Collapse.propose/3` answers - the params, the subtree template, and a pass-through slot for an unfilled slot inside the selection. It does not name the type and edits no document. `Collapse.replacement/4` answers the compound edit that swaps the arrangement for the registered type; nothing in the package commits it |

## Canvas limits

- A **summary chip** is capped at 32 characters: one longer than that is
  drawn clipped, with an ellipsis in its last position, and the chip's
  `title` carries its full text. A card has a fixed width.
- The **canvas pane scrolls** rather than squeezing the document: at 100
  percent zoom a document wider than the canvas scrolls horizontally inside
  the editor. The toolbar's zoom steps and `Fit width` bring it into view, and
  the `fit` assign opens a document that way.
- **Height.** By default the editor is as tall as the document in it.
  `--sb-editor-height` set to a length bounds it: the panes scroll in their
  own boxes and the drawer stays pinned at the bottom. The default is `auto`.
- **Class and property names.** Every class the package emits is prefixed
  `sb-`, and every colour, space, radius and drag treatment is a `--sb-*`
  custom property with a default.

## Not yet

- **Connectors.** Blocks are arranged by containment, and there is no
  free-floating edge between two cards. Whether the editor grows one is an
  open ADR-0005 decision-7 question.
- **A datamodel path grammar.** The undeclared-path advisory `11e`-`11g`
  settled is shipped, but only against the set of paths a host declares.
  Nothing here parses or validates a path beyond its shape, and a host that
  supplies no datamodel gets no advisory at all.
- **A chart view.** Nothing here draws a compiled chart's transitions as a
  flow between blocks. What such a view's edges would mean - the block-level
  flow graph lifted from the compiled transitions, which is not
  `StatifierBlocks.Graph` - is defined in
  [The block-level flow graph](../block-level-flow-graph.md).

## What the host keeps

Which palette entries a tenant may use, who may edit or publish a document,
where its revisions are stored, and what publishing means. The editor is a
single-session component: it surfaces the `revision` it loaded for optimistic
concurrency on save, and it does not merge or resolve anything.
