# SF040: an element editor over this editor - findings

**A findings document, not a proposal.** It weighs two answers to Riddler's
Q15 - *is Riddler's element editor this editor with an element palette and
its own emit?* - against two throwaway spikes run 2026-09-12. Nothing here
amends a record and nothing here is a decision; the asks it names are filed
separately and listed in section 4.

Written in the vocabulary settled by the operator on 2026-09-12 (campaign
SF040 consent amendment A2, recorded as a Riddler `docs/decisions.md` R10d
amendment): **a question owns its `answer_options`; a visitor's Journey owns
`responses`, and the datamodel root a screen writes is
`responses.<element_key>`; the host-supplied root is `context`.** Quoted code,
fixture values and spike notes keep their own spelling, which in places is
still the older one; where that happens it is marked.

## Inputs

All paths relative to the private umbrella working set
(`~/Dev/github/statifier`). Both spike branches are local to `Mac.lan`, were
never pushed, and are never to be deleted.

| Input | Where |
|---|---|
| q1 (`sb-q8sw`) branch | `spike/sf040-element-emit` at `a1aab91`, on `fa61fd7`, in `statifier_blocks-worktrees/sb-q8sw-element-emit` |
| q1 spike notes | `statifier_blocks-worktrees/sb-q8sw-element-emit/SPIKE-NOTES.md` |
| q1 capture and artifact | `.claude/fleet/pending/SF040-spikes/sb-q8sw-element-editor.png`, `sb-q8sw-emitted.json` |
| q1 capture harness (not committed) | same directory, `sb-q8sw-render.exs`, `sb-q8sw-page.rb` |
| q2 (`se-aud`) branch | `spike/sf040-element-editor` in `statifier_examples`, local, cut from `f81e92a` |
| q2 authoring notes | `.claude/fleet/pending/SF040-spikes/se-aud-authoring-notes.md` |
| q2 captures | same directory, `se-aud-editor-element-tree.png`, `se-aud-inspector-text-question.png`, `se-aud-palette-browser.png` |
| q2 artifact and diff | same directory, `se-aud-emitted.json`, `se-aud-fixture-diff.txt` |
| This package | `statifier_blocks` at `fa61fd7`; every line cite below was read there |

Every count in section 1 was re-derived for this document from
`git diff origin/main --stat` on `a1aab91`, and every count in section 3 from
`se-aud-fixture-diff.txt` and the q2 notes' own tables. Where a re-count
disagrees with a spike note, the re-count is given and the disagreement is
stated.

## 1. The seam as built

### What it cost

`git diff origin/main --stat` on `spike/sf040-element-emit` is 15 files,
1,220 insertions, 14 deletions. `SPIKE-NOTES.md` (274) is not code, which
leaves 946 lines, and they fall into three piles that should not be added
together:

| Pile | Files | Lines |
|---|---|---|
| **The seam** - a JSON emit pass and a second artifact | `compiler/json_emitter.ex` (142), `emitted_document.ex` (41) | **183 new** |
| **The seam** - what it changed in existing files | `compiler.ex` (+71/-7), `block_type.ex` (+1/-1), `editor.ex` (+31/-5), `docs/profiles.md` (+13/-1) | **+116 / -14** |
| **A vocabulary** - the four element types | `element/heading.ex` (81), `element/button.ex` (66), `element/text_question.ex` (67), `element/text.ex` (41), `element.ex` (39) | 294 |
| **A vocabulary** - its tests | `element_emit_test.exs` (176), `editor/element_profile_test.exs` (122), `support/element_fixture.ex` (55) | 353 |

**The seam is 299 lines: 183 of new pass plus 116 added across four existing
files, against 14 removed.** The 647 lines of vocabulary and tests are the
cost of *a* vocabulary and are paid under either answer to Q15; a second JSON
vocabulary pays them again and pays none of the 299.

The fork is one `case` in one function. `compile/3` takes
`emitter: :scxml | :json` defaulting to `:scxml`, and `after_resolve/5` forks:
the document stage, resolve, config and structure are shared, and the JSON
tail runs `config_and_structure_stages/5`, `chart_use_stage/2` and
`JsonEmitter.emit/2`, reaching `chart_stage/5` never. Five stages drop off the
JSON path and q1 justified each individually rather than as a job lot -
`chart_stage/5` (serialized bytes, byte-span provenance, chart identity,
`Chart.validate/3` are all statements about SCXML), `emit_stage/3` (host
`<data>` roots and the hoist), `self_reference_stage/2` (`<invoke src>`),
`sensitive_stage/2` (emitted `<data>` and `<send>` payloads),
`donedata_stage/2` (`donedata_type/1` against `<donedata>`). No stage turned
out to be half-SCXML and half-general. That is the strongest single result of
the spike.

### The surfaces that broke

Seven in q1, four more in q2 once three screens rather than three nodes went
through the editor. Only the first is a record question; the rest are
ordinary defects or gaps.

1. **`BlockType.emit/2`'s return type (the only real break).**
   `block_type.ex:505-506` types the callback
   `{:ok, StatifierBlocks.Emission.t()} | {:error, emit_error()}`. A type
   returning a JSON map is a type break: with the callback unchanged,
   dialyzer refuses the four element modules. The spike widened it one line
   to admit `map()` and dialyzer went clean. **That widening is a record
   question, not a code question** - see section 4, ask R.
2. **`%Compiled{}` cannot hold a JSON document.** It enforces `scxml`,
   `provenance` and `record`, and all three are chart statements: the bytes
   are identity-bearing, the provenance is keyed by state id and byte span,
   and `record.chart_identity` hashes the bytes. The spike added a second
   struct, `StatifierBlocks.EmittedDocument`, rather than fill three `nil`s -
   a chart artifact claiming to be empty is worse than a second struct.
3. **Two post-stage rewriters name the struct.** `reanchor/2` and
   `in_document_order/2` each read exactly one field, `warnings`, and each
   gets at it by matching `%Compiled{}`, so each needed a second clause.
   This is the one cost in the list that is **per emitter** rather than
   one-off (`sb-ahsn`).
4. **The card's title key is the literal string `"label"`.** The defect both
   captures show. `ViewModel.title_override/2` (`view_model.ex:2290`, a
   private function feeding the public `ViewModel.title/1` at
   `view_model.ex:653-654`) finds a card's title by looking for a config
   field whose key is literally `"label"` and whose type is `:string`.
   `element.text_question` and `element.button` spell their title field
   `"label"`, so their cards read the author's text. `element.heading` spells
   its `"text"` and `element.text` spells its `"body"`, so both read the
   **palette label** instead: `se-aud-editor-element-tree.png` is a six-card
   screen whose root card reads "Heading" and two of whose cards read "Text",
   with the author's prose - the page title included - nowhere on the canvas.
   It leaks past the card face too: the insert banner in
   `se-aud-palette-browser.png` reads "Pick a block to insert into Contents of
   **Heading**" rather than naming the page (`sb-u1d2`).
   On a chart this is one card in a diagram of shapes. On a page, prose *is*
   the content, so it blanks half the canvas.
5. **The run pane was not addressable by a profile.** Two thirds of the
   asked-for profile needed no code: `drawer_tabs: [:findings]` drops truth
   tables and Source, and `inspector_tabs`/`toolbar` trim the rest. The run
   pane needed a new key, because every other profile key names a surface the
   editor draws out of its own state while the run pane is drawn because a
   **host seated a run in it**. The spike's `run?: false` therefore *unseats*
   the run rather than hiding the pane - a hidden pane whose run still marked
   the canvas would be an editor marking states for a reason the reader
   cannot see. `editor.ex:668-674` on `main` carries `drawer_tabs`,
   `inspector_tabs`, `palette_groups`, `toolbar` and `read_only?` and no
   `run?` (`sb-ij80`, which the bead notes needs a record amendment first).
6. **A slot a node never named is dropped in silence.** The JSON splice
   replaces a `{:slot, name}` marker with that slot's compiled children; a
   type that declares a slot and emits no marker loses those children with no
   finding. The SCXML pass checks only the opposite direction -
   `splice/3` (`compiler.ex:1928`, raising `:unspliced_child` at
   `compiler.ex:1940`) refuses a placeholder naming a block that is *not* a
   child - so this is a gap the JSON pass **inherits** rather than a JSON-only
   gap (`sb-l1ih`). *Correction to the inputs:* q1's notes cite `splice/3` at
   `compiler.ex:1986`; on `fa61fd7` it is at `:1928`.
7. **No dev host exists in this package.** The q1 brief assumed one: there is
   no `config/`, no endpoint under `lib/`, no `phx.server`, and the `spike/`
   directory at the repo root is a static HTML/JS lab with no Elixir in it.
   The capture was taken the way this repo has taken every editor capture
   (`sb-4e2-harness`, `sb-9dn-harness`): `render_component/2` under
   `MIX_ENV=test` wrapped in a static page carrying the shipped stylesheet.
8. **A JSON target has no Source surface.** Authoring a JSON document with no
   way to see the JSON is authoring blind, and on a page the JSON *is* the
   artifact rather than a convenience. The q2 mount had to grow its own
   **Emit JSON** button in the host header, which is a host invention with no
   package counterpart; `SourceView` is a chart listing (`sb-12q2`).
9. **Two questions can claim the same `responses` key, silently.** q2
   authored two `element.text_question` nodes both keyed `email`; the Findings
   count did not move. A page whose two questions write the same
   `responses.<element_key>` is a page where one answer destroys the other
   (`sb-9hpg`). This is the sharpest instance of gap 6, and it is a *key* gap
   rather than a JSON gap - keys are what a page is made of.
10. **A blank required field masks the next one.** An `element.button` with
    both required fields blank raised **one** finding, naming `config.label`;
    the blank outcome field produced nothing of its own. Findings appear to be
    one per block rather than one per failing field, so an author clearing
    them one at a time will think they are done a field early. The message is
    also thin: a blank required string reads `config must be text`, which
    describes a type error rather than an empty field (`sb-2w79`).
11. **The canvas is mostly empty.** A page is a single vertical column
    roughly 300px wide in a canvas pane 1,200px wide. Vertical-only stacking
    shows up over a page as wasted space rather than as a missing feature, and
    `:fits` was hidden by the profile so the author could not fill the pane.

### What Findings and provenance mean for a JSON target

**Findings survive intact, and that was the surprise.** A finding names a
stage, a block id, a config key and a severity, and none of those is an SCXML
concept. The config stage refuses a heading with empty text on the JSON path
exactly as on the SCXML path, ordering is document order either way, and
composite re-anchoring needed only the struct clause in break 3. The findings
pane in `sb-q8sw-element-editor.png` is the shipped pane, unmodified.

The one thing that does not carry is `config_value_span` - byte offsets into a
config value, composed by the chart stage - so a JSON target has no
sub-expression underlining. That is a loss of precision *inside* a finding,
not a loss of findings.

Two cautions the q2 spike adds, and they matter more than the loss above. The
findings pane being present is not the same as it being **right**: over the k1
fixture it read **0 while 25 of 64 fields were being dropped** (section 3),
because nothing in the document claimed those fields. And gaps 9 and 10 mean
the pane under-reports even what the vocabulary does declare. Findings carry
to a JSON target as a *mechanism*; their coverage over a page is a vocabulary
question.

**Provenance changes shape but not meaning.** `StatifierBlocks.Provenance`
answers which block owns a runtime state id and which block owns a byte span,
and a JSON target has neither. The same question in a JSON idiom - given a
position in the artifact, which block wrote it - is answered by a map of JSON
pointer to block id, which the spike produced in nine lines:

```elixir
%{"/" => "blk_page", "/children/0/" => "blk_email", "/children/1/" => "blk_submit"}
```

Two properties of the SCXML map do not carry. There is no attribute-level
ownership, because a JSON node has exactly one owner, where the SCXML map
records `attribute_owners` precisely because one element's attributes can come
from two blocks. And there is no runtime half at all: a page is not executed,
so nothing ever asks which block the machine is in. The provenance map for a
JSON target is **strictly simpler**, and that simplicity is itself the reason
not to reuse `Provenance`: a struct with the state-id half permanently empty
invites a reader to ask it a question it can never answer.

### Does the canvas read as a layout tree?

Yes, and q2 puts it more strongly than q1 after 18 nodes rather than 3. The
gap `+` is the whole insert story: one between every pair of siblings and one
at each end, the target stated in words before the pick, and **no drag
anywhere** - inserting into the middle of a screen is the same two clicks as
appending to the end. The `CONTENTS` slot label reads as a region name and
survives a six-child page unchanged.

Three qualifications. A tree is not a preview: the cards say what type each
node is, not what the page looks like, and combined with break 4 an author
reviewing a screen cannot read the screen. There is no page boundary and no
row - one column, no notion of where a screen ends; the k1 fixture has no rows
either, so nothing was lost, but a real signup screen wants a two-up name
field early. ADR-0005 decision 10's presentation metadata already carries
`layout: :columns`, so the mechanism exists and a page vocabulary would
declare it on a container type; untested here.

**No canvas mode is proposed by this document.** `docs/decisions.md` D16 is
explicit that components promote and layouts do not - "a second way to lay a
document out is a host's page, not a mode inside the package editor" - and
nothing above asks to reopen it.

## 2. The D16 fallback, estimated against the same four types

The fallback is D16's own shape: a host-native view over the public
`StatifierBlocks.ViewModel` and `Edit` APIs, reusing `Editor.Field`, with no
drag and no fork of the package.

This is not a hypothesis. `statifier_examples`'
`lib/statifier_examples_web/live/plan_live.ex` is **860 lines** and is the
shipped reference for exactly that claim; its moduledoc carries a table of the
seventeen public APIs it is built from and states that it holds no copy of any
of them. So the fallback can be costed against a built thing rather than
guessed.

### What the package gives a page view for free

| What a page view needs | The public API that answers it |
|---|---|
| read the document into nodes | `ViewModel.build/3` (`view_model.ex:511`) |
| order the rows | `ViewModel.outline/1` (`view_model.ex:1003`) |
| label a row | `ViewModel.sentence/1` (`view_model.ex:1325`), `ViewModel.title/1` (`:653`) |
| pick a row's fields | `ViewModel.shown_fields/1` (`view_model.ex:1341`), `fields_for/2` |
| find a block and where it sits | `ViewModel.find_node/2` (`:1074`), `positions/1` (`:1141`) |
| read a block's config | `Document.committed_config/2` (`document.ex:187`), `effective_config/3` (`:220`) |
| draw a block's form | `Editor.ConfigForm.config_form/1` (655 lines) |
| read a form back | `Editor.ConfigForm.decode/3` |
| render one field | `Editor.Field.field/1` (1,727 lines, total over the closed field-type set) |
| write to the document | `Edit.Session.commit/2`, `change_config/3`, `update_list/4`, `step/2` |
| say which types fit a gap | `Edit.Targets.accepted_types/4` |
| build an inserted block | `Palette.new_block/2` |
| walk every block in order | `Document.blocks/1` (`document.ex:107`) |

`ConfigForm`'s moduledoc says the reuse out loud: what it draws is
`ViewModel.shown_fields/1`'s list "and nothing else", and "a host drawing its
own form calls the same function - so a change to what counts as shown reaches
both surfaces at once". `Field` is total over the closed field-type set by
construction (ADR-0005 decision 9, ADR-0002 decision 7). Neither needs a line
of package change to serve a page.

### What a Riddler package would write

Against the same four element types, and taking `PlanLive` as the measured
precedent:

- **The page view: roughly 400 to 600 lines.** Smaller than `PlanLive`'s 860,
  because the four element types are leaves or single-slot containers:
  `outline/1`'s `:step | :arm | :rail | :tray` partition collapses to `:step`,
  there is no rail section and no tray footer, and there are no arm conditions
  to render. Larger than nothing, because the host rebuilds the insert
  affordance, the selection model and the page chrome the canvas supplies.
- **A JSON emit walk: roughly 60 to 120 lines, and no package change at all.**
  This is the part worth stating plainly, because it is where the two answers
  really differ. A host does **not** need `compile/3` to get JSON out of a
  document. `Document.blocks/1` plus `committed_config/2` walk the committed
  tree in order, and a page vocabulary's node shape is a direct function of a
  block's type and config. The result is the same document
  `sb-q8sw-emitted.json` holds, produced with **zero** lines changed in
  `statifier_blocks` and **zero** record cost.
- **The four element types: 294 lines plus 353 of test, unchanged.** They are
  `BlockType` modules under either answer. The fallback's types simply never
  implement `emit/2` for a JSON target, because nothing calls it.

### What the fallback gives up

All four of the things the seam got for free, and they are not small:

- the **palette** and the gap `+` insert path (q2: 77 gestures for 18 nodes,
  no drag, no gesture that failed);
- the **findings pane**, wired to the same findings the compiler raises;
- the **canvas**, which q2 found reads as a layout tree better than expected;
- the **inspector**, `ConfigForm` and `Field` in their shipped arrangement -
  reusable as components, but the host writes the arrangement.

And it gives up one thing that is easy to miss: **config validation on the
path that produces the artifact**. The fallback's emit walk reads
`committed_config/2`, which is post-gate, so it inherits
`Edit.check_config/3`'s refusals - but nothing downstream re-checks the tree
as a whole, and the compiler's config and structure stages are exactly where
q1's JSON path still ran them.

### The two costs side by side

| | Emit seam (q1 as built) | D16 fallback |
|---|---|---|
| `statifier_blocks` lines | 299 (183 new + 116 changed) | 0 |
| Host lines | the mount and its profile | ~460 to 720 (view + JSON walk) |
| Vocabulary (either way) | 294 lib + 353 test | 294 lib + 353 test |
| Record cost | **one decision** (ADR-0004 d4) | none |
| Palette, canvas, findings pane, inspector | free | host rebuilds or forgoes |
| Per-emitter tax | 2 clauses (`sb-ahsn`) | none |

## 3. Recommendation for Riddler Q15

### The deciding numbers

1. **Authoring gestures are not the problem.** q2 authored three k1 screens -
   18 nodes - in **77 gestures** (33 clicks, 44 field fills, 657 characters).
   Reckoned as a person rather than as a driven script, that is two to three
   minutes a screen and seven to nine minutes for the three. **The per-node
   cost is flat**: click the trailing gap `+`, click the type in the palette,
   fill one to four fields in an inspector already open on what was just
   inserted. No node cost more.
   *Re-counted for this document:* the q2 notes state the budget as
   `2 x nodes + fields`. The per-screen clicks are 11, 13 and 9 for 6, 7 and 5
   nodes, which is `2n - 1`, not `2n`: the root heading is the document root
   and costs no gap click. The honest formula is **`2 x nodes + fields - 1`
   per screen**, and the total is 77 rather than 80. The conclusion is
   unchanged and the correction is recorded because the doc is the citation.
2. **The vocabulary lost 25 of 64 fields with Findings at 0.** Walking the k1
   fixture against the re-authored document
   (`se-aud-fixture-diff.txt:157-159`): **64 fields walked, 39 carried, 25
   lost, and the Findings pane read 0 for every one of them.** By kind: 14
   node `key`s on non-question nodes (only `element.text_question` has a key
   field; every other node's identity is a generated block id), 6 `condition`s
   (no element type has one, so each node was authored unconditionally and its
   screen now always shows it), 2 `writes`, 2 `payload`s, 1 `format` (so the
   email question validates nothing).
3. **Six concepts are missing from `element.*`, plus two smaller ones.** A
   node `key` on non-question nodes; `condition`; `writes`; `payload`;
   `format`; and **a screen container** - the fixture is one document holding
   three screens, and the editor emitted three documents, one per screen, each
   rooted at an `element.heading`, with the screen's own `key` homeless and
   its title surviving only as the root heading's text. The document envelope
   (`schema_version`, document `id`, `metadata`) has no emitted counterpart at
   all. Beside those six: **`element.button` requires a `style`** the fixture
   has no value for, so every button was given `primary` or `secondary` to
   clear a required-field finding - the vocabulary inventing presentation the
   target document has no slot for. And **`outcome` became `action`**: the
   fixture's `outcome` is what a Journey raises, `element.button` spells the
   same idea `action`, and nothing in the type says they are the same thing,
   so a page and the Path that consumes it can drift by a word.
4. **Structure and prose carried exactly.** Node ordering, nesting, the
   heading-owns-contents relation and every plain string field survived. What
   failed is everything a page does *besides* holding text in order.
5. **The seam is 299 lines and one record decision; the fallback is roughly
   460 to 720 host lines and none.**

### The recommendation

**Yes for the editor. Not yet for the in-compiler emit. Neither answer is the
project's critical path - the vocabulary is.**

In three parts, in the order they should be taken.

**(a) Riddler's element editor is this editor with an element palette.** The
editor half is nearly free and the evidence is a working page editor in two
captures. The insert path is two clicks with no drag, the canvas reads as a
layout tree, `ConfigForm` and `Field` draw every element's form with no
package change, and the findings pane is the shipped pane. The profile
mechanism carried two thirds of the asked-for hiding with no code. Nothing in
either spike suggests a page editor built from scratch would be better, and
q2's gesture count is better than most page builders manage. This part of Q15
answers yes with no qualification beyond the defects in section 1 - and the
one that would be felt first, `ViewModel.title_override/2`'s `"label"` lookup
(`sb-u1d2`), is a small fix with a large effect: over a prose vocabulary it
blanks half the canvas.

**(b) Do not take the in-compiler JSON emit yet; it turns on a record
decision.** The seam is small and clean - one `case`, 299 lines, every dropped
stage individually justified - but `BlockType.emit/2`'s return type is a
record question (section 4, ask R), and every other item on the list is small
if it lands and moot if it does not. Until SF041 rules it, a host walk of
`Document.blocks/1` plus `committed_config/2` produces the same JSON in under
about 120 lines with zero package change and zero record cost. That is the
D16-shaped fallback applied to the **emit** half only, and the two halves are
separable: taking (a) does not commit anyone to the seam, and the seam can be
taken later without redoing (a).

**(c) The blocking work under either answer is the vocabulary, and it is
larger than either seam.** Six missing concepts, a naming decision that should
be settled before either spelling ships (`outcome` vs `action`), and a
required `style` the target document cannot hold. 25 of 64 fields with
Findings at 0 is not an editor defect and no answer to Q15 shrinks it: the
same 25 fields are missing from a host-native view, because they are missing
from the types. Whoever owns the page vocabulary should decide these first;
until they do, neither answer to Q15 produces a document the k1 fixture's
consumers can run.

One consequence worth stating: a page profile should **keep Source rather than
drop it**, which is the opposite of what the q1 profile did. On a chart Source
is a convenience; on a page the JSON is the artifact, and authoring it unseen
is authoring blind (`sb-12q2`).

## 4. Upstream asks under either answer

Filed already by the conductor, at P4, labelled `campaign-SF040` and
`sf041-candidate`. Cited here by id; this document files nothing.

| Id | Ask | Live under |
|---|---|---|
| `sb-ahsn` | A `warnings` accessor across compile artifacts, so `reanchor/2` and `in_document_order/2` stop matching `%Compiled{}` | the seam only (it is the per-emitter tax) |
| `sb-u1d2` | `ViewModel.title_override/2` takes the card-title key from the block type rather than the literal `"label"` | **both** - it is an editor defect, and q2 raises its priority rather than adding to it |
| `sb-ij80` | A `run?` profile key that **unseats** the run rather than hiding the pane (a record decides first) | **both**, and independent of Q15: any host mounting for an audience that must not see a run needs it today |
| `sb-l1ih` | A totality check in the emit pass for a compiled child that was never placed (confirm against ADR-0004 first - it may be deliberate silence) | **both** - the SCXML pass has the same gap in the other direction |
| `sb-9hpg` | Two blocks claiming the same key raise no finding | **both**, wherever answer keys are a concept |
| `sb-2w79` | Findings are one per block, not one per failing required field, and a blank required string reads as a type error | **both** |
| `sb-12q2` | A JSON emitter target has no Source surface; `SourceView` is a chart listing | the seam only |
| `sb-czla` | A reads-before-writes check over the typed environment walk | **both** (arrived from t1, listed here because a page of questions is where it bites) |

### Ask R: `BlockType.emit/2`'s return type is a record question, for the SF041 walk

**This document amends no record** (campaign SF040 consent clause 9). It
states the question as precisely as the spike allows, for the SF041 walk to
rule.

What the code says today, read at `fa61fd7`:

- `block_type.ex:505-506` types the callback
  `{:ok, StatifierBlocks.Emission.t()} | {:error, emit_error()}`, and its
  `@doc` just above says "The return is structural, never a string".
- **ADR-0004 decision 4** ("`emit/2` receives a block and a context, and
  returns an emission") fixes the same narrow signature in the record:
  `{:ok, Emission.t()} | {:error, [finding()]}`, and explains
  `Emission.t()` as "a structural representation of one SCXML subtree".
- **ADR-0002**'s typespec section types the callback
  `{:ok, term()} | {:error, term()}` and glosses it "Emits this block's SCXML
  subtree", explicitly deferring the signature to ADR-0004
  ("Signature and context shape are sb-iwz's; this record fixes only that the
  callback lives here and is pure").

*Correction to the inputs:* q1's `SPIKE-NOTES.md` and the `sb-q8sw` closing
note attribute the sentence "emits this block's SCXML subtree" to ADR-0004
decision 4. It is ADR-0002's prose, and ADR-0002 is the record that types the
return **loosely**; ADR-0004 decision 4 is the one that types it narrowly.
This sharpens the ask rather than changing it: the binding narrowing is
ADR-0004 decision 4, and ADR-0002's gloss is a sentence that would be
falsified alongside it.

The question, then: **should a block type be able to emit for a non-SCXML
target, and if so by what shape?** Two candidates, and the spike's own
preference is the second:

1. **Widen `emit/2`.** One line, dialyzer clean, and the spike did it. But
   `map()` is not a narrowing of ADR-0004 decision 4's sentence, it is a
   different sentence, and a type answering `{:ok, %{}}` would sail through
   the SCXML pass and fail downstream with no finding naming it. A widened
   `emit/2` also cannot let one type serve both targets.
2. **A separate optional callback** (`emit_json/2`, or an emitter-keyed
   callback). It keeps decision 4's sentence true, it lets a type serve both
   targets, and a type that declares neither is refused at resolve rather than
   at emit.

Whichever way it is ruled, everything else in this document is small if it
lands and moot if it does not.

### Reported, not filed

Two items from q2's divergence notes are outside `statifier_blocks` and are
recorded here so they are not lost. Neither is this package's to fix.

- **`statifier_examples`' documented local-development path-dep arm does not
  carry the asset pipeline.** `mix.exs` already has a `statifier_blocks_dep/0`
  that reads `STATIFIER_BLOCKS_PATH` and swaps in a path dep, documented for
  exactly this use - but `assets/css/app.css:11` imports
  `../../deps/statifier_blocks/assets/css/statifier_blocks.css`, and a Mix
  path dep is never materialised under `deps/`, so `mix assets.build` fails to
  resolve it. q2 worked around it with a symlink. A real gap in a supported
  arm, independent of anything in SF040.
- **`statifier_examples`' gate cannot be green while that arm is in use**, by
  construction: `test/statifier_examples/mix_deps_test.exs` guards the Hex arm
  with `refute System.get_env("STATIFIER_BLOCKS_PATH")`. That is the right
  guard and no change is wanted; it is recorded because it means "gate red" is
  the expected state of a mounted spike rather than a defect in it, and
  because it is on its own sufficient to keep anything from such a branch out
  of a commit.

## 5. Reviewer qualifications

None recorded.
