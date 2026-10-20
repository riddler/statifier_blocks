# Upgrading a host from 0.31 to 0.44

This page says what a host changes to move `statifier_blocks` from 0.31.0 to
0.44.0, one minor at a time. A host here is the code that embeds the package:
the palette it builds, the compile it calls, the documents it stores and the
publish step it runs. What each release added is in
[CHANGELOG.md](../CHANGELOG.md); this page lists only what a host has to do
about it, and says **NONE** where the answer is nothing.

Take the minors in order, and move the pin with each one, as the README
recommends: `{:statifier_blocks, "~> 0.32.0"}`, then `"~> 0.33.0"`,
`"~> 0.34.0"`, `"~> 0.35.0"`, `"~> 0.36.0"`, `"~> 0.37.0"`, `"~> 0.38.0"`,
`"~> 0.39.0"`, `"~> 0.40.0"`, `"~> 0.41.0"`, `"~> 0.42.0"`, `"~> 0.43.0"`
and `"~> 0.44.0"`. A patch release rides its minor's pin, so each section
below covers the patches of the minor it moves to.

One value moves at every release, a patch included, and the sections below
do not repeat it: the compiler version. `StatifierBlocks.Compiler.compiler_version/0`
answers the package's version, and the `StatifierBlocks.CompilationRecord` in
what `StatifierBlocks.Compiler.compile/3` answers carries it as
`compiler_version`, so a record compiled after the bump carries the new
version. **If you pin `compiler_version` in a test**, or compare it with a
record you stored, move the literal with each pin.

What an **author** changes in a document is a separate page:
[Migrating a document from 0.27 to 0.34](https://github.com/riddler/statifier_blocks/blob/main/docs/guides/migrating-documents-0.27-to-0.34.md).
Nothing on it is required, and no stored document has to be migrated for any
release below.

## 0.31 to 0.32

- **If you call StatifierBlocks.Composite.unraisable_outcomes/4 yourself**,
  call `unraisable_outcomes/5` instead, passing the config of the block you
  expanded as the new third argument, between the type ref and the expansion
  members:

  ```elixir
  Composite.unraisable_outcomes(palette, ref, block.config, members, param_map)
  ```

  This is the release's one **Breaking** entry. The compiler makes this call
  itself, so a host that never called it directly changes nothing for it.
- **Recompile the documents you store before you switch.** A composite that
  declares no outcomes used to compile green when a slot on it broke the
  declaration: a child in a slot its type does not declare was dropped, and a
  declared slot holding the wrong number of children lost its refusal. On
  0.32 the compile refuses both at the Resolve stage, as `:undeclared_slot` and
  `:slot_arity_violated`. A document refused there is its author's to fix; the
  finding's message says how.

## 0.32 to 0.33

- **Finish rolling 0.32 off before an author saves an `accepts` list.** A
  document saved with a non-empty `accepts` list cannot be read by 0.32.0 or
  earlier, so a node still on 0.32, or a rollback to it, refuses that
  document. A stored document decodes unchanged on 0.33 and keeps its
  `content_hash/1`.
- **If you match exhaustively on a `StatifierBlocks.Finding`'s anchor or
  source**, add the `:document` anchor and the `:graph` source.
  `Finding.from_compiler/2` now adapts a Document-stage finding to the
  `:document` anchor where it answered `{:error, {:unanchorable, finding}}`.
- **If you rescue a raise from `StatifierBlocks.Compiler.compile/3`** for a
  document whose `root` is not a block, or whose `slots` value is not a map of
  block lists, match the `{:error, findings}` it returns now instead.
- **If you key on `:duplicate_id` at the Chart stage** for a block placed in a
  composite's pass-through slot, or in a declaring composite's `on_<name>`
  slot, under an id the expansion mints for one of its own members, key on
  `:minted_id_collision` at the Resolve stage instead.
- **If you store `%StatifierBlocks.CompilationRecord{}` field by field**, it
  gains an `accepts` field, the document's list as written.
- **If you call `StatifierBlocks.Shell.drawer_view/1` or
  `Shell.findings_groups/3` yourself**, the first takes an optional `accepts`
  key and the groups the second answers gain a `document?` key.
- **Put the publish gate in your publish step.** Two calls judge a document
  before you publish it, and your step refuses on an `:error` from either:
  - `StatifierBlocks.Publish.findings/3` takes the document as saved, the
    palette and the editor's context map (`:datamodel`, `:declare`,
    `:chart_outcomes`), and answers the findings of the compile's stages
    before Emit followed by the editor's own, in the editor's order. An
    `:error` among them is a document the compile would refuse before Emit or
    one the editor marks in error. An undeclared datamodel path is an `:info`
    advisory, never a refusal.
  - `StatifierBlocks.Graph.check/2` takes the parent's compiled artifact and
    your resolver from a document id to that document's published artifact.
    It refuses a child that is not published, an outcome the parent routes on
    that the child does not declare (`error` exempt), and a done-data key the
    parent reads that the child does not declare. Its reverse,
    `StatifierBlocks.Graph.consumers_broken/2`, judges a child's next revision
    against the published parents that name it.

  The order they run in, with the compile between them, is
  [How to publish a document](guides/publish-a-document.md).

## 0.33 to 0.34

**NONE.** Nothing needs migrating, the package gains no dependency, and an
editor mounted without the new `publish_status` assign renders exactly what it
rendered on 0.33.0. The release's additions are opt-in; the CHANGELOG says
what they are.

## 0.34 to 0.35

**NONE.** Nothing needs migrating, and the package gains no dependency.
`StatifierBlocks.Plan.expressible/3` and `Plan.expressible?/3` are new and
opt-in, so a host that calls neither sees no change from 0.34.0. The 0.35.1
patch, which the `"~> 0.35.0"` pin takes, changes the shipped stylesheet
only: a card's title no longer breaks mid-word.

## 0.35 to 0.36

- **If you pin a card line in a test**, or match the words a card shows,
  read the new words for three core types, each of which now declares
  `sentence/1` where it showed its label: `core.sequence` reads
  `Run its steps in order` where it read `Sequence`; `core.group` reads
  `Run interruptible steps` where it read `Group`; and `core.await` reads
  `Wait for <event>`, followed by `, giving up after <timeout>` when a
  deadline is set, where it read `Wait for event`. The same sentences name
  those blocks in the lines of `StatifierBlocks.Describe`, new in this
  release.

The rest of 0.36.0 is opt-in: `StatifierBlocks.Describe` and the JSON
Schema the package now ships, read through `StatifierBlocks.Schema`, change
nothing for a host that calls neither, and the package gains no runtime
dependency. The 0.36.1 patch needs nothing from a host: `Describe.outline/3`
now draws the interrupt edge for an abandon handler that names
`finish_as`, which 0.36.0 left out.

## 0.36 to 0.37

- **If you pin a delayed `core.send`'s card line**, or a
  `StatifierBlocks.Describe` line built from it, read the new words: a send
  with a delay names that delay, `In 7 days, send loan.fines_notice` where
  it read `Send loan.fines_notice`, the short duration form put in words
  and any other stored spelling shown as stored. A send with no delay reads
  exactly as before.
- **If you match every edge kind `Describe.outline/3` answers**, add
  `:timer`, the edge from a delayed `core.send` to each `core.on_event` and
  `core.await` that names its event, and read its delay from
  `StatifierBlocks.Describe.Edge`'s new `delay` field. `render/2` writes it
  as `In 24 hours, registration.deadline reaches ...`, and a phrasing
  module rewords it through the new optional `Phrasing.timer/2` callback.
  A document with no delayed send describes exactly as before.

Nothing needs migrating and the package gains no dependency. The new
`explain/0` callback on `StatifierBlocks.BlockType` is optional, so a host
type that declares none changes nothing.

## 0.37 to 0.38

- **Run the palette pre-flight before you deploy.** A block type's declared
  field types now bind: a config value its declared field type in
  `config_schema/1` does not admit (an integer in a `:string` field, a
  value outside a `{:select, choices}`) is refused before
  `validate_config/1` runs, at compile, at the edit gate and under the
  field in the view model, with a finding naming the field's key and its
  declared type. After taking 0.38 and before deploying it, run
  `StatifierBlocks.Palette.preflight/1` over your palette and
  `StatifierBlocks.Palette.preflight/2` over the documents you store, and
  correct each declaration or stored block they list; an empty list means
  you are ready. A host type whose documents disagree with its declared
  field types otherwise sees new `:config` findings. `validate_config/1`
  still runs and its findings follow; an absent key and a `null` are still
  the type's own to judge.

`StatifierBlocks.Schema.for_palette/1` is new and opt-in, and the package
gains no dependency.

## 0.38 to 0.39

- **Finish rolling 0.38 off before a document carries a block `note`.**
  Decode now admits an optional `note` string on a block, a key 0.38.0 and
  earlier refuse, so a node still on 0.38, or a rollback to it, refuses a
  document that carries one. A note that is not a string is refused as
  `{:malformed_block, id, {:note, :not_a_string}}`.
- **If you build `%StatifierBlocks.Block{}` structs yourself**, or match
  them field by field, it gains a `note` field, `""` by default (the absent
  note), which `Block.new/2` takes as `:note`. Canonical form omits an
  empty note, so a document with no notes keeps its `content_hash/1`; a
  note changes the document's hash, not the compiled chart.
- **If you audit the licenses of your dependencies**, the package metadata
  lists `EPL-2.0` beside `MIT`: elkjs 0.9.3 ships vendored and unmodified
  as `assets/vendor/elk.bundled.js`, with its Eclipse Public License 2.0
  text beside it. Only a bundle that imports the `statifier_blocks/map`
  entry point loads it; the default export is unchanged.

The Map itself is opt-in: `StatifierBlocks.Map`, `Map.Info` and
`StatifierBlocks.Editor.MapRegions` change nothing for a host that mounts
neither region, and the package gains no Hex dependency.

## 0.39 to 0.40

- **If you match every member of `StatifierBlocks.Edit.t()` by hand**, add
  a clause for `{:update_note, id, note}`, the new command that writes a
  block's author note; an empty note removes it. `Edit.apply/2` answers
  its inverse, `{:update_note, id, previous_note}`, and refuses a note that
  is not a string with `{:malformed_block, id, {:note, :not_a_string}}`,
  the term `Document.validate/1` answers for such a note. A host that only
  passes commands on to `Edit.apply/2` or `Edit.History` changes nothing.
- **The editor draws a description region under its canvas**:
  `StatifierBlocks.Editor.MapRegions.description_region/1`, read from the
  editor's own document, palette and selection, with no map beside it. It
  is drawn in a read-only mount too, and no `profile` key hides it. There
  is nothing to pass for it.
- **If you mount `description_region/1` yourself**, it takes two new
  attrs, both optional: `map`, `true` by default, and `false` for a region
  with no map beside it (no hover layer, no store and no how-to-read
  paragraph in the idle description); and `label`, the live region's
  `aria-label`, `"Description"` by default. A host that passes neither gets
  the region it had.
- **If you set the `--sb-*` palette on `.sb-map__description`**, set it on
  `.sb-map__description-frame` instead, the wrapper the region now sits in
  beside its hover layer, so the layer reads it too.
- **If you stamp the `StatifierBlocksMap` hook's ids on your own element**
  rather than mounting `map_region/1` and `description_region/1`, stamp
  `data-info-hover` with the id of an `aria-hidden`, `hidden` element
  beside the region for the hook to fill. The hook finds its hover layer
  there and no longer reads `data-info-region`, so without it the map has
  no hover. A hover no longer changes what the region announces; only a
  new selection does.
- **If you pass `phrase` to `map_region/1` or `description_region/1`**,
  pass `nil` or a function of one argument. Any other value now raises an
  `ArgumentError` naming the attr, where it raised a `FunctionClauseError`;
  `nil` and a one-argument function render as before.

## 0.40 to 0.41

- **If you match the edge lines `StatifierBlocks.Describe.render/2`
  answers**, or pin them in a test, read the new words. An edge line
  names a container by a noun where it named it by its sentence: its
  title where it has one; else a short noun for its type, `the steps`
  for a sequence, `the group` for a group or a resumable group, `the
  branch`, `the lanes` for a parallel and `the loop` for a for-each;
  else `the` and its palette label in lower case. A noun that opens a
  line with a lower-case `the` takes a capital there, and `the steps`
  and `the lanes` take `start` where the others take `starts`: the line
  that read `Run its steps in order starts with Wait 14d` now reads
  `The steps start with Wait 14d`, and `Send loan.overdue (done) ends
  Run its steps in order` reads `Send loan.overdue (done) ends the
  steps`. Wherever an edge line embeds a delayed send's sentence it is
  set in double quotation marks, so its own comma does not read as the
  line's: `After "In 7 days, send loan.overdue" (done), Wait 14d`. Node
  lines, and a step named in an edge line, keep their sentence. To keep
  other words, give the container a title, or reword the line through
  `StatifierBlocks.Describe.Phrasing`, whose callback receives the new
  default.
- **If you build `StatifierBlocks.Describe.Node` structs yourself**, it
  gains a `noun` field, `nil` by default. `outline/3` fills it; a node
  built by hand with no noun is named by its sentence in an edge line,
  as before. A host that only reads `outline/3`'s nodes changes nothing.
- **If you match the idle description's how-to-read text**, the
  `explanation` of `StatifierBlocks.Map.Info.idle/4`, read the new
  paragraph: it names every mark the Map draws, the clock on a timed
  wait among them.
- **If you attach the `StatifierBlocksMap` hook to your own element**
  rather than mounting `map_region/1`, give that element a child marked
  `data-map-canvas` for the hook to draw into. Without one the hook
  still draws into the element itself, which LiveView patches, and now
  warns once per mount in the browser console that this is not
  supported. `map_region/1` renders the child.

The Map's other changes need nothing from a host: it draws the happy
path straight through a group whose body holds a container, the hook
laying such a document out twice, and it draws the clock mark on a
timed wait (`core.wait`), which still takes no part in a timer edge.

## 0.41 to 0.42

**NONE** for a host that mounts neither the editor nor the Map
(`map_region/1` and `description_region/1`) and passes no `:phrase` to
`StatifierBlocks.Map.graph/2` or `StatifierBlocks.Map.Info.elements/6`:
nothing needs migrating, and the package gains no dependency. A host that
does mount them reads the bullets below.

- **If you read `data-info-region` off the element `map_region/1`
  renders**, take the region's id from the `description` you pass to
  `map_region/1` instead. The element no longer carries the attribute,
  which the `StatifierBlocksMap` hook has not read since 0.40.0, so the
  hover is unchanged. A host that stamps the attribute on its own element,
  or never read it, changes nothing.
- **If you pass `phrase` to `map_region/1` or `description_region/1`, or
  `:phrase` to `StatifierBlocks.Map.graph/2` or
  `StatifierBlocks.Map.Info.elements/6`, and pin a phrased line in a
  test**, re-read the lines where a name your function has words for sat
  outside event position. Words now replace a name only in event
  position: after `Send` or a delayed send's `send`, after `Wait for`, or
  after a rule's `When`. A known name anywhere else stays as written, such
  as a path a step sets, a name after a send or wait word glued to a
  dotted prefix, or the event a timer edge's line names before `reaches`.
  A name in event position reads as it did on 0.41.0.
- **If your page mounts the editor and reads the notes it stores**, a note
  a browser posts with CRLF line breaks is now stored with LF: each CRLF
  becomes LF at the editor's note event, before the command, so a change
  of line endings alone is no longer an undo entry. A lone CR is stored as
  posted. The `{:update_note, id, note}` command a host issues itself
  through `StatifierBlocks.Edit.apply/2` still stores the note's bytes as
  written.
- **If you pass `class` to `description_region/1`**, it now goes on the
  region's hover layer as well as on the region, so what your class gives
  the region still shows while a hover is drawn. A rule of yours on that
  class now reaches the layer too; the package's stylesheet keeps a hidden
  layer out whatever display a single class of yours sets.
- **If you rescued a raise out of `description_region/1`** on a document
  whose composite declaration cannot expand, you can drop the rescue: the
  region now renders with no description in it and no
  `data-map-description` attribute, its id, `aria-live` and label kept,
  and with `map={true}` its hover layer and an empty store.

The release's fix for a note-free stored block needs nothing from a host:
a block built before blocks had a note, in a document kept as a stored
Erlang term, now goes through the note edit command,
`StatifierBlocks.Map.Info`'s descriptions and the editor's note field as
a note-free block instead of raising.

The 0.42.1 patch, which the `"~> 0.42.0"` pin takes, changes documentation
only: **NONE**, beyond the compiler version every release moves (see the
top of this page).

## 0.42 to 0.43

**NONE** for a host that mounts neither the editor nor the Map
(`map_region/1` and `description_region/1`), reads none of the Map's
answers itself (`StatifierBlocks.Map.graph/2`, `StatifierBlocks.Map.caption/1`,
`StatifierBlocks.Map.start_text/0` and the descriptions
`StatifierBlocks.Map.Info` answers) and pins none of the findings
`StatifierBlocks.Datamodel.findings/4` or `StatifierBlocks.Publish.findings/3`
answers: nothing needs migrating, and the package gains no dependency. A
host that mounts the Map gets its new drawing with nothing to pass for it:
the start dot first, marked Start; every end ring marked End; a legend of
the marks the drawing uses, beside it at its top right; and a drafts shelf
in a drawer under the drawing, closed on a page that cannot edit and open on
one that can. A host that does read those answers reads the bullets below.

- **If you draw the graph `StatifierBlocks.Map.graph/2` answers yourself**,
  read its new shape. `StatifierBlocks.Map.nodes/1` is unchanged.
  - The start dot is the graph's first node, at its top level beside the
    root box rather than inside it, and its start edge is the graph's own.
    The edge still runs into the first step of the document's flow, or into
    the root's box on a document whose root body holds only a drafts shelf.
  - The start node and each end node carry the word Start or End as their
    one ELK `labels` entry, with `layoutOptions` placing it outside the mark
    on its right. The start edge's caption reads "Starts when the system is
    told to", and its label is wider.
  - A new top-level `legend` list carries the key, one
    `%{"mark" => mark, "line" => line, "lines" => lines}` per mark the
    drawing uses.
  - A drafts shelf's node carries a new `drafts` field,
    `%{"count" => count, "label" => label}`, and the `legend` gains a last
    `drafts` entry whose line is that row; the node stays where it was.
  - A group deeper in the document's tail whose rules abandon it (the last
    step of an arm of the root's last step, or of the body of a group that
    is) gains an `abandon` edge into the `abandon` end node, so one abandon
    end can have several edges into it.
  - A group's rules column carries `caption` "Rules: watch the steps while
    they run" in place of the group's sentence, and a new
    `explanation_lines` field, that sentence wrapped to a box's line.
  - A branch node's wrapped arm entry starts every line after its first with
    no-break spaces as wide as the entry's number (`"1. "`, `"10. "`).
- **If you draw `StatifierBlocks.Map.caption/1` yourself**, expect the
  whole first sentence of the type's explanation for a branch and the two
  group types, never cut to one line and ended in "...".
- **If you match or pin the descriptions `StatifierBlocks.Map.Info`
  answers**, read the new values.
  - `idle/4`'s `explanation`, the paragraph on how to read the map, is
    shorter: it opens with "A plain box is a step, drawn inside the step
    that holds it, with its type's name on top and what it does under it.",
    says what a column beside a group holds, and leaves what each mark means
    to the key.
  - `idle/4` answers two new facts: "Finishes with", right after "What
    starts it", the document's ends in order (each outcome, and "abandons"
    for an abandon end), for example `["done", "abandons"]`, with no such
    fact on a document whose map draws no end; and a last fact,
    `{"Legend", lines}`, the key's lines.
    `StatifierBlocks.Editor.MapRegions.description_region/1` shows the
    "Legend" fact with a map beside it and leaves it out with `map={false}`,
    as it leaves out the paragraph.
  - `StatifierBlocks.Map.start_text/0` answers "Starts when the system is
    told to" where it answered "Starts when told to", on every document, so
    the "What starts it" fact reads it too.
  - `elements/6` lists the start dot before the root box and the start edge
    after the root's own elements and edges. The start edge's `sentence`
    reads as two sentences, "Starts when the system is told to. First: Wait
    21 days." where it read "Starts when told to, Wait 21 days". A timer
    edge's explanation says the delayed event arrives at the interrupt rule
    or the hourglass step that hears it. Each new abandon edge is described
    as the root-level one is.
- **If you count or pin the findings `StatifierBlocks.Datamodel.findings/4`
  answers**, or those `StatifierBlocks.Publish.findings/3` answers after
  them, a `{:list, {:path, opts}}` field's rows now get the `:info`
  undeclared-path advisory a `{:path, opts}` field gets: one for each
  undeclared row, a path repeated across rows once, anchored on the list
  field's key. It is `:info`, so a publish step that refuses on an `:error`
  refuses nothing new. The editor binds each row's input to a `<datalist>`
  of `path_candidates`, with nothing to pass for it.

The release's other changes need nothing from a host:
`StatifierBlocks.Describe.render/2` reads a timer or interrupt edge whose
event is blank as "its event", as it already did for an edge with no event;
and the `StatifierBlocksMap` hook draws the first layout where it drew the
error pane when a second layout fails, draws a resume edge clear of its own
rule's box, and holds the SVG wide enough for a timer edge between two
steps of one column.

The 0.43.1 patch, which the `"~> 0.43.0"` pin takes, widens the `predicator`
requirement to admit 9.5 (`~> 9.4 and >= 9.4.1`), so a host moving to a
`statifier` that requires `predicator` 9.5 can resolve this package beside
it: **NONE**, beyond the compiler version every release moves (see the top
of this page).

## 0.43 to 0.44

**NONE** for a host that mounts neither the editor nor the Map
(`map_region/1` and `description_region/1`), reads none of the Map's
answers itself (`StatifierBlocks.Map.graph/2` and the descriptions
`StatifierBlocks.Map.Info` answers), reads no compiled `interface`, pins
or refuses on none of the findings `StatifierBlocks.Publish.findings/3` or
`StatifierBlocks.Graph` answers, and stores no `core.await` with a
`capture` key: nothing needs migrating, no stored document has to change,
and the package gains no dependency. A host that mounts the
editor gets the capture rows on `core.await` with nothing to pass for them,
and may pass the new `advisories` assign. A host that does read those
answers reads the bullets below.

- **If your publish step refuses on the `:error` findings
  `StatifierBlocks.Publish.findings/3` answers**, it now refuses a document
  that declares its own datamodel roots (its `datamodel` key holds an
  entry) and holds a config path no declaring surface declares: there the
  undeclared-path advisory is answered at `:error`, with the advisory's
  anchor, `:lint` source and message. Declaring the path, or correcting it,
  lets the document publish. A document that declares no roots is
  unchanged: with only your `:datamodel` or `:declare` roots the advisory
  stays `:info` and refuses nothing, and with nothing declared anywhere
  there is none. The editor and `StatifierBlocks.Datamodel.findings/4`
  still answer it at `:info`.
- **If you read the compiled `interface`'s `references`, or match the
  findings `StatifierBlocks.Graph.check/2` and `consumers_broken/2`
  answer**, read the new values.
  - A `core.subchart` or `core.map` that a composite's expansion placed is
    recorded under the composite block the stored document holds: its
    `block_id` is the outermost composite's id, and a new `expanded_from`
    key carries the expanded member's id, which the stored document does
    not hold. A finding about it is anchored `{:block, composite_id}` on
    the composite, where it was anchored on the member's field.
  - A `core.map` whose `collect_type` names a type the compile's
    `:datamodel` does not declare is now marked `unresolved`, and its
    done-data read is reported unchecked with the same `:graph` `:warning`
    on `collect_type` a compile without `:datamodel` gets, its message
    saying the supplied datamodel does not declare the name; before, the
    read passed with no finding. It is a `:warning`, so a publish step that
    refuses on an `:error` refuses nothing new. Passing a `:datamodel` that
    declares the name, or writing the `collect_type` inline, lets the keys
    be checked.
  - A reference that is `unresolved` carries a new `unresolved_reason`,
    `:no_datamodel` or `:not_declared`. A reference recorded before the key
    existed, with `unresolved` set and no reason, reads as `:no_datamodel`,
    the only case that set `unresolved` then.
- **If you build or store documents whose `core.await` blocks carry a
  `capture` key**, it now compiles: `core.await` takes an optional
  `capture` map with `core.on_event`'s semantics, each pair an assign on the
  transition the awaited event selects, and a malformed map is refused
  where the key used to be ignored. An await with no `capture`, or an empty
  one, compiles to the same bytes as before.
- **If your page mounts the editor and stores the config it posts**, the
  first time its form posts an edit to an await that holds no `capture`,
  the block's config gains an empty `capture` map, since the form now draws
  the capture rows for every await. It compiles to the same bytes as an
  absent one; a host that compares stored configs key for key sees the new
  key.
- **If you want the editor to show advisories only your host can raise**,
  pass the new optional `advisories` assign to `StatifierBlocks.Editor`: a
  one-argument function the editor calls with the document on every
  rebuild, returning `{anchor, message}` or `{anchor, message, opts}` as a
  `StatifierBlocks.DocumentValidator` does. Each becomes a `:lint` finding
  at `:warning` unless its `opts` say otherwise, drawn where its anchor
  routes it. Pass the same function to
  `StatifierBlocks.Editor.findings_count/3` as its `:advisories` option so
  your count agrees with the drawer's. With the assign unset the editor
  draws what it drew before.
- **If you match or pin the descriptions `StatifierBlocks.Map.Info`
  answers, or the `legend` `StatifierBlocks.Map.graph/2` answers**, read
  the new wording.
  - `idle/4`'s `explanation`, the paragraph on how to read the map, says
    "A caption on a branch's band, or under a group's rules column with its
    explanation beneath, says what that kind of step does." in place of the
    sentence that called it "a one-line caption".
  - The abandon end's explanation in `elements/6`, and the key's
    dashed-ring line (the graph's `end-abandon` `legend` entry, and so the
    "Legend" fact `idle/4` answers), say an interrupt rule abandons "a group
    at the end of its flow" where they said "its last step".
  - The Finish edge's explanation in `elements/6` reads "The arrow into a
    final mark: the document's last step, or a group at the end of its
    flow, is behind it, so when control leaves it this way, the document
    finishes with the outcome it names."

The release's fixes need nothing from a host: a face finding on a selected
card spans the card's width below its title row; the editor's Expand
gesture writes each member a composite mints at its block type's current
version; `StatifierBlocks.Editor.ConfigForm.config_form/1` renders a `class`
you pass on its read-only form as well as on the editable one, so a rule
of yours on that class now reaches the read-only form too; and the
`StatifierBlocksMap` hook leaves the drafts drawer out and draws the path
when the drafts shelf alone fails to lay out.
