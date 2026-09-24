# Upgrading a host from 0.31 to 0.34

This page says what a host changes to move `statifier_blocks` from 0.31.0 to
0.34.0, one minor at a time. A host here is the code that embeds the package:
the palette it builds, the compile it calls, the documents it stores and the
publish step it runs. What each release added is in
[CHANGELOG.md](../CHANGELOG.md); this page lists only what a host has to do
about it, and says **NONE** where the answer is nothing.

Take the minors in order, and move the pin with each one, as the README
recommends: `{:statifier_blocks, "~> 0.32.0"}`, then `"~> 0.33.0"`, then
`"~> 0.34.0"`.

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
