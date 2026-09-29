# Upgrading a host from 0.31 to 0.34, and from 0.39 to 0.41

This page says what a host changes to move `statifier_blocks` from 0.31.0 to
0.34.0, one minor at a time, and from 0.39.0 to 0.41.0. It does not cover
0.34 to 0.39; the CHANGELOG's sections for those releases say what each one
changed. A host here is the code that embeds the package:
the palette it builds, the compile it calls, the documents it stores and the
publish step it runs. What each release added is in
[CHANGELOG.md](../CHANGELOG.md); this page lists only what a host has to do
about it, and says **NONE** where the answer is nothing.

Take the minors in order, and move the pin with each one, as the README
recommends: `{:statifier_blocks, "~> 0.32.0"}`, then `"~> 0.33.0"`, then
`"~> 0.34.0"`; from 0.39, to `"~> 0.40.0"`, then `"~> 0.41.0"`.

What an **author** changes in a document is a separate page:
[Migrating a document from 0.27 to 0.34](guides/migrating-documents-0.27-to-0.34.md).
Nothing on it is required, and no stored document has to be migrated for any
release below.

## 0.31 to 0.32

- **If you call `StatifierBlocks.Composite.unraisable_outcomes/4` yourself**,
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

  The order they run in, with the compile between them, is the README's
  [At publish](https://github.com/riddler/statifier_blocks/blob/main/README.md#at-publish)
  section.

## 0.33 to 0.34

**NONE.** Nothing needs migrating, the package gains no dependency, and an
editor mounted without the new `publish_status` assign renders exactly what it
rendered on 0.33.0. The release's additions are opt-in; the CHANGELOG says
what they are.

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
