# Block document model (ADR-0001) Implementation Plan

## Overview

Layer-1 implementation of accepted ADR-0001: the `%StatifierBlocks.Document{}`
/ `%StatifierBlocks.Block{}` tree, block and document id minting, structural
validation, the deterministic canonical-JSON encoder, SHA-256 document
identity, and the registry-free structural decoder. Bead: `sb-xti`.

Scope is ADR-0001 decisions 1-9. Decision 10 (the core block vocabulary) and
every block-type contract are explicitly out of scope and belong to `sb-dvj`
and the core-types bead.

## Current State Analysis

The package is a scaffold. `lib/` holds one moduledoc-only module
(`lib/statifier_blocks.ex`), `test/` holds one loadability test
(`test/statifier_blocks_test.exs:6`), and there is no `test/support/`
directory yet even though `mix.exs:37` already adds it to `elixirc_paths` for
`:test` and `coveralls.json` already skips it for coverage.

Baseline `mix quality` (full) is green as of this plan: format, compile
(warnings-as-errors), credo `--strict`, deps audit, dialyzer, and tests at
100% coverage against the fleet's 90% floor.

Key constraints discovered:

- **Elixir 1.18.3** (`mise.toml`), so the built-in `JSON` module is available.
  Verified in this checkout: `JSON.decode/1` exists and returns floats for
  fractional literals (`JSON.decode(~s({"a":1.5}))` -> `{:ok, %{"a" => 1.5}}`)
  and integers for integral ones, so the two are distinguishable after decode
  and ADR-0001 decision 6's no-floats rule is enforceable at the decode
  boundary.
- **`JSON.encode!/1` does not sort object keys.** It emits map keys in Erlang
  term order, which is not UTF-8 byte order for the general case and is not a
  documented guarantee at all. The canonical encoder (decision 8) therefore
  has to emit its own object and array framing, sorted, into iodata, and may
  use `JSON.encode!/1` only for **scalars** - where it gets a correct,
  RFC-8259 string escaper for free rather than hand-rolling one.
- **No new dependency is needed or wanted.** statifier-ex's ADR-0008 was
  amended to drop the `uxid` dependency and mint UXID-format ids inline; the
  family-standard minting is
  `/Users/johnnyt/Dev/github/statifier/statifier-ex/lib/statifier/machine_state.ex:571-585`
  (`generate_session_id/0` and `crockford32/1`): a 48-bit big-endian
  millisecond timestamp followed by 80 bits of `:crypto.strong_rand_bytes/1`,
  rendered with `Base.hex_encode32(case: :lower, padding: false)` and
  translated character-for-character from the hex32 alphabet into Crockford's.
  This plan copies that pattern for `blk_` and `bdoc_`. `statifier ~> 2.0` is
  already a dependency but does not export a public id minter, so the
  translation table and the two functions are re-stated here rather than
  reached into.
- **Family content-hash form**:
  `/Users/johnnyt/Dev/github/statifier/statifier-ex/lib/statifier/machine/identity.ex:53`
  formats a SHA-256 content hash as `"sha256:" <> Base.encode16(digest, case:
  :lower)`. See Open Question 2.
- **Repo conventions that bind every phase** (`CLAUDE.md`): errors are events
  (`{:ok, v} | {:error, e}`, never rescue-to-default at a leaf); `@spec` on
  every public function; every new test that asserts `lib/` behaviour is
  sabotage-verified and carries a one-line mutation note directly above it;
  `mix format` is run by hand because the gate's format stage is check-only.
- **Changelog fragments** (`changelog.d/README.md`): public API additions get
  one fragment named `changelog.d/sb-xti.md`. Test fixtures and internal
  modules do not.

## Desired End State

`StatifierBlocks.Document` and `StatifierBlocks.Block` exist with exactly the
struct shapes ADR-0001's typespec block declares, and the following public
API is implemented, specced, documented, and tested:

| Function | Contract |
|---|---|
| `Block.new/3` | mints a `blk_` id, builds a block |
| `Document.new/1` | mints a `bdoc_` id, wraps a root block |
| `Document.validate/1` | `:ok \| {:error, reason}`, the event-shaped structural check |
| `Document.to_json/1` | deterministic canonical bytes (decision 8) |
| `Document.content_hash/1` | SHA-256 over `to_json/1` |
| `Document.from_json/1` | registry-free structural decode with ADR-0001's exact error arms |
| `Document.fetch_path/2` | `{:ok, path()} \| :error` |

Verification that the end state is reached:

1. `test/fixtures/documents/worked_example.json` holds the ADR's worked
   example as canonical bytes, and the suite asserts, in both directions,
   that `to_json/1` of the hand-built equivalent produces exactly those bytes
   and that `from_json/1` of those bytes re-encodes to exactly those bytes.
2. The `encode(decode(bytes)) == bytes` property holds over a generated
   corpus of valid documents, and `decode(encode(d)) == d` holds structurally.
3. `content_hash/1` is stable across a decode/re-encode cycle and differs for
   any document that differs.
4. Every error arm in ADR-0001's `from_json/1` typespec has at least one test
   that reaches it.
5. Full `mix quality` is green at the end of every phase.

### Key Discoveries:

- `lib/statifier_blocks.ex` is the only module in `lib/`; there is no
  namespace directory yet, so this bead creates `lib/statifier_blocks/`.
- `statifier-ex/lib/statifier/machine_state.ex:375-381` carries the exact
  Crockford translation table and the comment explaining why hex32-to-Crockford
  is order-preserving over a fixed-width big-endian bit string.
- `statifier-ex/lib/statifier/machine/identity.ex:96-108` is the family's
  reference shape for a total, typed, ordered decode of untrusted persisted
  bytes - the shape ADR-0001 decision 9 points at.
- `mix.exs:37` already compiles `test/support` in `:test`, and
  `coveralls.json` already excludes it, so fixture builders placed there cost
  nothing in coverage.
- ADR-0001's worked-example JSON block is already sorted at every level
  (envelope `id, metadata, revision, root, schema_version`; blocks `config,
  id, slots, type, type_version`; slot names `body, interrupts`,
  `arm_qualified, otherwise`, `lane_crm, lane_nurture`), so the fixture is a
  faithful minification of it and not a re-derivation.
- The example's ids (`blk_ROOT`, `bdoc_01JDOC`, ...) are the ADR's own
  abbreviations and are **not** valid UXIDs. That is load-bearing, not a
  defect in the fixture: decision 3 says this layer treats ids as opaque and
  never parses them, so decoding them must succeed. No id-format validation
  belongs in `validate/1` or `from_json/1`.

## What We're NOT Doing

- **Block types.** No `core.sequence`, `core.branch`, `core.parallel`,
  `core.wait`, `core.resumable_group`, or interrupt-rule implementation.
  ADR-0001 decision 10 names them only as the load the schema must carry, and
  the bead says explicitly not to implement them (`sb-dvj` and the core-types
  bead own them).
- **The block-type registry and the block-type behaviour** (ADR-0002,
  `sb-5n0`). Decision 9 requires decoding to be registry-free, so nothing in
  this bead may reference a registry at all.
- **Assignability / slot arity checking** (ADR-0003, `sb-7rx`). Decision 5
  says arity is "a validation rule applied against that uniform shape" and
  that rule is the block type's, not this layer's. `validate/1` checks that
  `slots` is a map of string names to lists of blocks, and stops there.
- **The compiler and the provenance map** (ADR-0004, `sb-iwz`). No SCXML, no
  state-id generation, and no relation between document identity and the
  engine's chart identity (st-ADR-0052) - decision 8 hands that to `sb-iwz`.
- **Editor mutations** (ADR-0005, `sb-w50`). No move/insert/delete/reorder
  operations. `fetch_path/2` is in scope because ADR-0001's typespec block
  lists it; nothing that mutates a tree is.
- **`config` schema validation.** Decision 6 makes `config` opaque here: this
  layer checks it is a map of string keys to canonical-JSON values and never
  looks at what the keys mean.
- **Id-format validation.** See the Key Discovery above - ids are opaque.
- **Any new hex dependency.** JSON comes from Elixir 1.18's `JSON`, ids are
  minted inline.
- **Schema migration.** `schema_version` is 1 and an unknown version is a
  typed refusal, not an upgrade path.

## Implementation Approach

Four phases, ordered so that each one is independently committable and leaves
a full-gate-green tree with real tests covering the code it adds.

The ordering principle is that the encoder lands before the decoder, and the
worked-example fixture is exercised from the encoder side in phase 3 and from
the decoder side in phase 4. That gives the headline acceptance test two
independent halves: phase 3 proves the canonical bytes are what a hand-built
document produces, and phase 4 proves those same bytes survive a decode. If
the two were combined, a compensating bug in both directions could hide.

Module layout:

```
lib/statifier_blocks/id.ex              # Phase 1  (public, thin)
lib/statifier_blocks/block.ex           # Phase 1  (public struct)
lib/statifier_blocks/document.ex        # Phases 1-4 (public struct + API)
lib/statifier_blocks/validation.ex      # Phase 2  (@moduledoc false)
lib/statifier_blocks/canonical_json.ex  # Phase 3  (@moduledoc false)
lib/statifier_blocks/decode.ex          # Phase 4  (@moduledoc false)
test/support/document_fixtures.ex       # Phase 3  (builders; coverage-skipped)
test/fixtures/documents/worked_example.json  # Phase 3
```

`Document` is the single public entry point for `to_json/1`,
`content_hash/1`, `from_json/1`, `validate/1` and `fetch_path/2`; the three
`@moduledoc false` modules exist so no single file grows past what credo
`--strict` tolerates, and so the encoder's and decoder's internals are not
public API that a later bead has to keep.

**Error vocabulary is defined once, in phase 2**, as `Validation`'s reason
type, and reused verbatim by `from_json/1` in phase 4. ADR-0001's typespec
block is the definition of the arms:

```elixir
@type error ::
        :not_a_block_document
        | {:unsupported_schema_version, pos_integer()}
        | {:duplicate_block_id, Block.id()}
        | {:malformed_block, Block.id() | nil, term()}
        | {:malformed_envelope, term()}
```

The distinction between `:not_a_block_document` and `{:malformed_envelope,
_}` is fixed here so both phases agree: `:not_a_block_document` means the
bytes are not JSON at all, or the decoded top level is not a JSON object, or
that object has no `"schema_version"` key. Anything past that point is a
recognizable block document that is wrong in a specific way, and gets
`{:malformed_envelope, reason}` or a block-level arm.

---

## Phase 1: Ids, structs, and the tree walk

### Overview

Create the namespace, the two structs exactly as ADR-0001's typespec block
declares them, family-standard inline id minting, and the read-only tree walk
that later phases share.

### Changes Required:

#### 1. Id minting

**File**: `lib/statifier_blocks/id.ex` (new)
**Changes**: Public module with `block/0` and `document/0`, minting
`"blk_" <> uxid` and `"bdoc_" <> uxid` respectively, following st-ADR-0008 as
implemented at `statifier-ex/lib/statifier/machine_state.ex:571-585`. Do not
add a dependency.

```elixir
@hex32_alphabet ~c"0123456789abcdefghijklmnopqrstuv"
@crockford_alphabet ~c"0123456789abcdefghjkmnpqrstvwxyz"
@hex32_to_crockford Map.new(Enum.zip(@hex32_alphabet, @crockford_alphabet))

@spec block() :: StatifierBlocks.Block.id()
def block, do: "blk_" <> uxid()

@spec document() :: StatifierBlocks.Document.id()
def document, do: "bdoc_" <> uxid()

# st-ADR-0008: 48-bit millisecond timestamp, then 80 bits of entropy.
defp uxid do
  <<System.os_time(:millisecond)::48, :crypto.strong_rand_bytes(10)::binary>>
  |> Base.hex_encode32(case: :lower, padding: false)
  |> String.to_charlist()
  |> Enum.map(&Map.fetch!(@hex32_to_crockford, &1))
  |> List.to_string()
end
```

Carry a moduledoc noting that ids are opaque to this layer (decision 3) and
that nothing here or downstream parses them back apart.

#### 2. The Block struct

**File**: `lib/statifier_blocks/block.ex` (new)
**Changes**: The struct, `defstruct` and every `@type`/`@typedoc` transcribed
from ADR-0001's typespec block without alteration (`json`, `id`, `type_name`,
`slot_name`, `config`, `t`), plus a constructor:

```elixir
@spec new(type_name(), keyword()) :: t()
def new(type, opts \\ [])
```

`opts` accepts `:id` (default `StatifierBlocks.Id.block/0`), `:type_version`
(default `1`), `:config` (default `%{}`), `:slots` (default `%{}`). Options
rather than positional arguments because four of the five fields have
defaults and the fixture builders in phase 3 set different subsets.

Moduledoc states decision 2 (`{type, id, config, slots}` plus the
`type_version` axis decision 4 adds, and nothing else - no layout, selection,
validation results, or generated SCXML) and cites ADR-0001.

#### 3. The Document struct and the tree walk

**File**: `lib/statifier_blocks/document.ex` (new)
**Changes**: The struct and types transcribed from ADR-0001, plus:

```elixir
@spec new(Block.t(), keyword()) :: t()          # :id, :revision, :metadata
@spec blocks(t()) :: [Block.t()]                # pre-order, root first
@spec fetch_path(t(), Block.id()) :: {:ok, path()} | :error
```

`blocks/1` is the shared pre-order walk (slot names visited in sorted order
so every consumer sees one deterministic order) and is what phases 2 and 3
build on. `fetch_path/2` returns `{:ok, []}` for the root - a path names the
`{parent id, slot name, index}` steps taken from the root, so the root has
taken none - and `:error` for an absent id.

**`fetch_path/2`'s return shape is provisional pending an operator ruling on
Open Question 1** - ADR-0001 contradicts itself here, its `@doc` line saying
`nil` and its `@spec` saying `:error`. This plan implements the `@spec`. If
the ruling goes the other way the blast radius is bounded and known: one
clause in `document.ex`, one `@spec` line, and the three `fetch_path/2`
assertions this phase adds. Nothing in phases 2-4 consumes `fetch_path/2`,
which is why that is the whole of it - but it is a rework, not a free change,
and the implementer should raise the question rather than assume it settled.

`to_json/1`, `content_hash/1`, `from_json/1` and `validate/1` are **not**
declared in this phase; a `@spec` with no body would fail compile, and a stub
that raises would be untestable code against the coverage floor.

### Success Criteria:

#### Automated Verification:
- [x] Full gate green: `mix quality`
- [x] `lib/statifier_blocks/id.ex`, `block.ex`, `document.ex` exist
- [x] Tests assert `Id.block/0` returns a `"blk_"`-prefixed 26-character
      Crockford body, that two calls differ, and that ids minted in
      increasing milliseconds sort lexicographically in that order
- [x] Tests assert `Block.new/2` and `Document.new/2` defaults
      (`type_version: 1`, `config: %{}`, `slots: %{}`, `revision: 0`,
      `metadata: %{}`, `schema_version: 1`)
- [x] Tests assert `fetch_path/2` for the root (`{:ok, []}`), a nested block
      (the exact `{parent_id, slot, index}` list), a second child in the same
      slot (index 1), and an absent id (`:error`)
- [x] A test builds a block whose `slots` map is inserted in reverse-sorted
      name order and asserts `blocks/1` visits the slots in UTF-8-sorted
      order - without it, a `Map.to_list/1`-order implementation passes every
      other criterion here and phase 2's walk order is silently undefined

#### Manual Verification:
- [ ] Every new test carries its one-line sabotage mutation note, and the
      mutation described actually turns that test red (no command checks
      this - `mix quality` cannot see a comment)
- [ ] The struct fields and `@type` definitions are a character-faithful
      transcription of ADR-0001's typespec block, with no field added,
      dropped, or renamed
- [ ] The minting matches statifier-ex's `generate_session_id/0` bit-for-bit
      in structure (48-bit timestamp, 80 bits entropy, lowercase Crockford)

**Implementation Note**: Use `mix quality --profile loop` between edits; run
full `mix quality` as the phase gate. In interactive execution pause here for
the human; in `--loop` execution the Automated Verification block gates
advancement and the Manual items defer to `/wurk:verify`.

---

## Phase 2: Structural validation

### Overview

Implement ADR-0001's structural rules as one ordered, total, event-shaped
check over an in-memory document: decision 3 (id uniqueness), decision 6
(`config` is a map of string keys to canonical-JSON values, no floats),
decision 5 (`slots` is a map of string names to lists of blocks), and
decision 7's envelope axes. This is the vocabulary phase 4's decoder reuses,
which is why it lands before the encoder.

### Changes Required:

#### 1. The validation walk

**File**: `lib/statifier_blocks/validation.ex` (new, `@moduledoc false`)
**Changes**: `@spec validate(Document.t()) :: :ok | {:error, error()}` plus
the `error()` type from "Implementation Approach". The ordered checks:

1. Envelope: `schema_version == 1` (otherwise
   `{:unsupported_schema_version, v}`); `id` a non-empty UTF-8 binary;
   `revision` a non-negative integer; `metadata` a canonical-JSON object;
   `root` a `%Block{}`. Failures are `{:malformed_envelope, reason}` with
   `reason` a `{key, problem}` tuple, e.g. `{:revision, :not_a_non_neg_integer}`.
2. Per block, in `Document.blocks/1` pre-order: `id` a non-empty UTF-8
   binary; `type` a non-empty UTF-8 binary; `type_version` a positive
   integer; `config` a canonical-JSON object; `slots` a map whose keys are
   non-empty UTF-8 binaries and whose values are lists of `%Block{}`.
   Failures are `{:malformed_block, id, reason}`, with `id` `nil` when the
   block's own id is the thing that is malformed.
3. Id uniqueness across the whole pre-order walk:
   `{:duplicate_block_id, id}` on the second sighting.

A separate `canonical_json?`-style recursive predicate decides decision 6's
value grammar: `nil`, booleans, integers, UTF-8 binaries, lists of the same,
and maps with UTF-8-binary keys. **Floats are rejected explicitly and by
name** so the reason distinguishes `{:float, path}` from a merely unknown
term - the ADR calls no-floats out as the rule that makes byte-stability
achievable, and an author who trips it needs to be told which rule they hit.
Atoms other than `nil`/`true`/`false`, tuples, pids, refs, funs and structs
are rejected as `{:not_json, term}`.

`String.valid?/1` is the UTF-8 check, and it is required rather than
cosmetic: phase 3's encoder escapes strings through `JSON.encode!/1`, which
raises on invalid UTF-8, so an unvalidated non-UTF-8 binary would turn a
typed refusal into an exception.

#### 2. Public entry point

**File**: `lib/statifier_blocks/document.ex`
**Changes**: `@spec validate(t()) :: :ok | {:error, Validation.error()}`
delegating to `Validation.validate/1`, with a doc naming the ordered checks
and the fact that it never consults a block-type registry.

#### 3. Changelog fragment

**File**: `changelog.d/sb-xti.md` (new)
**Changes**: Start the `### Added` section for this bead; phases 3 and 4 add
lines to the same file. `changelog.d/README.md` requires one file per bead
and no nested bullets.

### Success Criteria:

#### Automated Verification:
- [x] Full gate green: `mix quality`
- [x] A test reaches each of: `{:unsupported_schema_version, 2}`,
      `{:malformed_envelope, _}` for each envelope key, `{:malformed_block,
      _, _}` for each block field, and `{:duplicate_block_id, id}` for a
      duplicate deep in the tree
- [x] Float rejection is tested at three depths: a top-level `config` value,
      a value inside a nested list, and a value inside `metadata`
- [x] A valid document built by `Block.new/2`/`Document.new/2` returns `:ok`
- [x] `validate/1` returns a value in every case and raises in none, over a
      table of hostile inputs (tuple, pid-free struct, atom, non-UTF-8 binary)

#### Manual Verification:
- [ ] Every new test carries its sabotage mutation note, verified by hand
- [ ] The check order matches ADR-0001 decision 9's "ordered check, one error
      arm per distinguishable cause" and no two distinguishable causes
      collapse into one arm
- [ ] No rescue-to-default anywhere in the module (`CLAUDE.md` convention)

**Implementation Note**: as phase 1.

---

## Phase 3: Canonical JSON encoding and document identity

### Overview

Implement decision 8: a deterministic encoder that emits sorted object keys,
no insignificant whitespace, omitted empty `slots`/`config`/`metadata`, and
no floats - plus SHA-256 identity over those bytes. Land the worked-example
fixture and prove the encoder produces it exactly.

### Changes Required:

#### 1. The canonical encoder

**File**: `lib/statifier_blocks/canonical_json.ex` (new, `@moduledoc false`)
**Changes**: `@spec encode(Document.t()) :: iodata()`, building the bytes
itself.

```elixir
# Objects and arrays are framed here, sorted here. Only scalars go through
# JSON.encode!/1, and only for its RFC-8259 string escaper: JSON.encode!/1
# emits map keys in Erlang term order, which is not the UTF-8 byte order
# ADR-0001 decision 8 requires.
defp object(pairs) do
  inner =
    pairs
    |> Enum.sort_by(&elem(&1, 0))          # binaries compare byte-wise
    |> Enum.map(fn {k, v} -> [JSON.encode!(k), ?:, value(v)] end)
    |> Enum.intersperse(?,)

  [?{, inner, ?}]
end
```

Emission rules, stated as code shape:

- Document -> object of `id`, `revision`, `root`, `schema_version`, and
  `metadata` **only when non-empty**.
- Block -> object of `id`, `type`, `type_version`, plus `config` **only when
  non-empty**, plus `slots` **only when non-empty**.
- `slots` -> object keyed by slot name, sorted; a slot whose list is empty is
  omitted entirely (decision 8: "empty slots omitted rather than encoded as
  `[]`"), and a `slots` object left empty by that omission is itself omitted.
- Values -> `nil`/booleans/integers/binaries through `JSON.encode!/1`; lists
  and maps framed here, recursively.
- A float reaching the encoder is a bug upstream of it, not a case to format:
  the encoder has no float clause, so it raises `FunctionClauseError`. See
  Open Question 3 for why `to_json/1` is the raising boundary.

#### 2. Public entry points

**File**: `lib/statifier_blocks/document.ex`
**Changes**:

```elixir
@spec to_json(t()) :: binary()          # ADR-0001's declared spec, unchanged
@spec content_hash(t()) :: binary()
```

`to_json/1` runs `validate/1` first and raises `ArgumentError` carrying the
validation reason when it fails, so an invalid document can never produce
bytes that claim to be canonical. `content_hash/1` is
`"sha256:" <> Base.encode16(:crypto.hash(:sha256, to_json(doc)), case: :lower)`
- see Open Question 2.

#### 3. The worked-example fixture and its builder

**File**: `test/fixtures/documents/worked_example.json` (new)
**Changes**: ADR-0001's worked-example JSON, minified to canonical form:
whitespace removed, key order preserved (the ADR's block is already sorted at
every level), content otherwise byte-identical including the abbreviated ids.
**Stored with no trailing newline**, and the test helper that reads it
applies `String.trim_trailing/1` anyway so an editor that adds one cannot
turn the headline acceptance test red for a reason that is not about the
encoder.

**File**: `test/support/document_fixtures.ex` (new)
**Changes**: `worked_example/0` building the same document with
`Block.new/2`/`Document.new/2` and explicit ids, and `worked_example_json/0`
reading and trimming the fixture file. `test/support` is already on
`elixirc_paths` for `:test` (`mix.exs:37`) and already excluded from coverage
(`coveralls.json`).

Deliberately build the fixture document with the slot and config maps in a
**different** insertion order from the canonical output, so the test would
fail if the encoder ever leaned on map iteration order instead of sorting.

#### 4. Changelog fragment

**File**: `changelog.d/sb-xti.md`
**Changes**: add the canonical-encoding and content-hash lines.

### Success Criteria:

#### Automated Verification:
- [ ] Full gate green: `mix quality`
- [ ] `to_json(DocumentFixtures.worked_example()) ==
      DocumentFixtures.worked_example_json()` - byte equality, the headline
      acceptance test
- [ ] The fixture bytes contain no `\n`, and no `" "` outside a JSON string
- [ ] Key-sort tests: a document whose `metadata`, `config` and `slots` maps
      are built in reverse-sorted insertion order encodes with sorted keys
- [ ] Omission tests: a leaf block emits no `"slots"` key; an empty `config`
      emits no `"config"` key; empty `metadata` emits no `"metadata"` key; a
      block with one empty and one non-empty slot emits only the non-empty one
- [ ] Escaping tests: quote, backslash, newline, tab, a control character
      (U+0001), and a multi-byte UTF-8 string round-trip through
      `JSON.decode/1` back to the input value
- [ ] Sort-order test with non-ASCII keys, asserting UTF-8 **byte** order
      rather than codepoint-collation order
- [ ] `content_hash/1` is equal for two independently built equal documents
      and differs when any one field differs
- [ ] `to_json/1` raises `ArgumentError` (not `FunctionClauseError`) for a
      document carrying a float

#### Manual Verification:
- [ ] Every new test carries its sabotage mutation note, verified by hand
- [ ] The fixture is a faithful minification of ADR-0001's worked example -
      read them side by side; no key added, dropped, reordered or retyped
- [ ] The encoder never calls `JSON.encode!/1` on a map or a list

**Implementation Note**: as phase 1.

---

## Phase 4: Registry-free structural decoding and the round-trip laws

### Overview

Implement decision 9: `from_json/1` as an ordered, total, registry-free
decode with ADR-0001's exact error arms, and close the bead's acceptance
properties.

### Changes Required:

#### 1. The decoder

**File**: `lib/statifier_blocks/decode.ex` (new, `@moduledoc false`)
**Changes**: `@spec decode(binary()) :: {:ok, Document.t()} | {:error,
Validation.error()}`, in this order:

1. `JSON.decode/1`; any error -> `{:error, :not_a_block_document}`.
2. Decoded term is a map carrying a `"schema_version"` key -> else
   `{:error, :not_a_block_document}`.
3. `"schema_version"` is the integer `1` -> else
   `{:error, {:unsupported_schema_version, v}}` for another positive integer,
   `{:error, {:malformed_envelope, {:schema_version, :not_a_pos_integer}}}`
   otherwise.
4. Build the envelope: `"id"`, `"revision"`, `"root"`, optional `"metadata"`
   (absent reads as `%{}`). A missing or wrongly-shaped key ->
   `{:error, {:malformed_envelope, reason}}`.
5. Build each block recursively: required `"id"`, `"type"`, `"type_version"`;
   optional `"config"` and `"slots"`, each absent reading as `%{}`; a slot
   value must be a list. An unknown extra key on a block object is
   `{:malformed_block, id, {:unexpected_key, key}}` - the document is the
   minimum that must round-trip (decision 2), so a key the encoder would not
   have written cannot be silently dropped without breaking
   `encode(decode(bytes)) == bytes`.
6. Run `Validation.validate/1` on the assembled document, which is what
   supplies the no-floats and id-uniqueness refusals rather than
   re-implementing them here.

The decoder constructs `%Block{}`/`%Document{}` by literal struct syntax on
explicitly extracted keys - never `struct/2` over decoded input, never
`String.to_atom/1`, and never `String.to_existing_atom/1` (decision 6). An
unknown `"type"` decodes successfully and is not resolved against anything
(decision 9).

#### 2. Public entry point

**File**: `lib/statifier_blocks/document.ex`
**Changes**: `from_json/1` with ADR-0001's declared `@spec` transcribed
exactly, delegating to `Decode.decode/1`. Doc states the registry-free rule
and that unknown types load.

#### 3. Changelog fragment

**File**: `changelog.d/sb-xti.md`
**Changes**: add the decoding line.

### Success Criteria:

#### Automated Verification:
- [ ] Full gate green: `mix quality`
- [ ] **Worked example, byte-stable**:
      `from_json(worked_example_json())` returns `{:ok, doc}`, `doc ==
      DocumentFixtures.worked_example()`, and `to_json(doc) ==
      worked_example_json()`
- [ ] **Round-trip property**: over a generated corpus of at least 200 valid
      documents (varying depth, slot counts, empty and non-empty
      config/metadata/slots, unicode and escape-bearing strings, negative and
      large integers), `decode(encode(d)) == d` and
      `encode(decode(encode(d))) == encode(d)`. Generation is deterministic
      from a fixed seed printed on failure - no `:rand` seeding from the
      clock, so a red run is reproducible
- [ ] **Identity stability**: `content_hash(d) ==
      content_hash(elem(from_json(to_json(d)), 1))` across that corpus
- [ ] Each error arm reached by at least one test: `:not_a_block_document`
      (garbage bytes; a JSON array; a JSON object with no `schema_version`),
      `{:unsupported_schema_version, 2}`, `{:duplicate_block_id, _}` (the
      same id on two blocks in different subtrees),
      `{:malformed_block, _, _}`, `{:malformed_envelope, _}`
- [ ] A float anywhere in decoded `config` or `metadata` is refused, and the
      reason names the float
- [ ] A document whose `type` is `"nobody.knows.this"` decodes to `{:ok, _}`
- [ ] Decoding does not create atoms: assert `:erlang.system_info(:atom_count)`
      is unchanged across decoding a document whose keys and values are novel
      random strings. **This test module runs `async: false`**:
      `:erlang.system_info(:atom_count)` is a VM-global counter, and another
      async module interning an atom mid-assertion would make it flake
      unreproducibly

#### Manual Verification:
- [ ] Every new test carries its sabotage mutation note, verified by hand
- [ ] The error arms in `from_json/1`'s implemented `@spec` are
      character-identical to ADR-0001's declared spec
- [ ] The check order is defensible as "one arm per distinguishable cause" -
      read the ordered list against decision 9

**Implementation Note**: as phase 1. This is the last phase; run
`/wurk:verify --unattended` after it to work the deferred manual items and
the open questions below.

---

## Open Questions

These are recorded rather than resolved because no human is available. Each
carries the resolution this plan implements so the work is not blocked; each
is a `/wurk:verify` item and each is cheap to reverse.

**1. `fetch_path/2` doc-vs-spec contradiction inside ADR-0001 (BLOCKING -
operator decision).** ADR-0001 line 325 documents `fetch_path/2` as "Walks
the tree; `nil` when the id is absent", while the `@spec` on line 326 is
`{:ok, path()} | :error`. Those cannot both be true. This plan follows the
`@spec` (`:error`), because the section is titled "The schema as typespecs"
and the specs are the normative content there, while the `@doc` line is
prose; `:error` is also the repo's convention shape (`{:ok, v} | :error` for
a lookup) and is what `Map.fetch/2`-named functions return. **This is a
genuine contradiction in an accepted ADR and is not something this plan
should have decided.** It needs an operator ruling and, if the prose is the
intended contract, an ADR amendment - which this bead may not make, since
`docs/adr/` is owned by another worker this session.

**2. `content_hash/1` return form (underspecified, non-blocking).** Decision
8 says `:crypto.hash(:sha256, canonical_json)` "is a usable document
identity" - a raw 32-byte digest - while the `@spec` is only `binary()`,
which a formatted string also satisfies, and the family's own content hash
(`statifier-ex/lib/statifier/machine/identity.ex:53`) is
`"sha256:" <> Base.encode16(digest, case: :lower)`. This plan emits the
family form: it satisfies the declared spec, it is safe in a JSON field, a
URL, a log line and a diff, and it names its own algorithm so a future
algorithm change is visible rather than silent. Reversing it later is a
one-line change plus test updates, and no other package consumes it yet.

**3. `to_json/1` raises rather than returning an event (non-blocking).**
ADR-0001 declares `@spec to_json(t()) :: binary()`, which leaves no room for
`{:error, _}`, while `CLAUDE.md` says errors are events. This plan keeps the
declared spec and makes `to_json/1` raise `ArgumentError` on an invalid
document, with `Document.validate/1` as the event-shaped path a caller uses
first. That is the same split the family uses for bang and non-bang pairs,
and it keeps the invariant that canonical bytes are never produced for a
document that would not validate. If the operator prefers a `{:ok, binary()}`
return, that is an ADR amendment, not a plan edit.

**4. `Document.validate/1` is public API the ADR does not list
(non-blocking).** ADR-0001's typespec block names `to_json/1`,
`content_hash/1`, `from_json/1` and `fetch_path/2`. Decision 6 requires the
no-floats rule to be enforced "on validate" and the bead's scope line repeats
that, so the check exists regardless; making it public is what lets a host
check a document it assembled in memory rather than only one it decoded. The
ADR lists the functions it constrains, not an exhaustive API, so this reads
as an addition rather than a contradiction.

**5. Duplicate keys in a decoded JSON object (unspecified, non-blocking).**
`JSON.decode/1` keeps the last occurrence. ADR-0001 says nothing about it.
This plan accepts that behaviour and does not detect duplicates - the decoded
document is well-formed and re-encodes canonically, so the round-trip law
still holds on the re-encoded bytes rather than the original ones. Worth a
sentence in a future amendment if a host ever diffs raw stored bytes.

**6. Decision 2's "and nothing else" versus `type_version` (resolved,
recorded for the reader).** Decision 2 says a block is `{type, id, config,
slots}` and nothing else; decision 4 adds `type_version` and the typespec
block carries all five fields. Not a real contradiction - decision 2 is
excluding derived data (layout, selection, validation results, generated
SCXML, provenance) and decision 4 adds a stored axis on purpose. The struct
has five fields.

**7. No-floats in `metadata` as well as `config` (underspecified,
non-blocking).** Decision 6's prose scopes the no-floats rule to `config`
("Canonical form additionally forbids floats in config"), but decision 8
states it as an encoding rule with no such qualifier ("no floats"), and the
typespec block gives `metadata` the type `%{optional(String.t()) =>
Block.json()}` where `json()` structurally excludes floats. This plan takes
the stricter reading and rejects floats in `metadata` too: the encoder has no
float formatting contract at all, so a float in `metadata` would break
byte-stability exactly as one in `config` would, and decision 8 is the rule
that byte-stability actually rests on. Recorded here because the prose reads
narrower than what the plan implements.


## Testing Strategy

### Unit Tests:

- `test/statifier_blocks/id_test.exs` - prefix, length, alphabet membership,
  uniqueness, and lexicographic ordering by mint time.
- `test/statifier_blocks/block_test.exs` and
  `test/statifier_blocks/document_test.exs` - constructor defaults, the
  pre-order walk, `fetch_path/2` including the root and absent cases.
- `test/statifier_blocks/validation_test.exs` - one test per error arm, the
  canonical-JSON value grammar (including floats at three depths), and
  totality over a table of hostile terms.
- `test/statifier_blocks/canonical_json_test.exs` - key sorting (including
  non-ASCII byte order), omission rules, escaping, no-whitespace, and the
  worked-example byte equality.
- `test/statifier_blocks/decode_test.exs` - the worked-example round trip,
  every error arm, unknown types, the atom-count assertion, and the
  generated-corpus properties.

Key edge cases to cover explicitly: an empty slot map versus an absent
`slots` key; a slot present but empty; a block whose `config` contains a
nested empty map (which is a value, not an omitted field, and must survive);
integers at the 64-bit boundary and beyond; a string containing a lone
`"` and a `\`; a document one block deep and one twelve blocks deep.

Per `CLAUDE.md`, every test that asserts `lib/` behaviour is sabotage-verified
- break the code it covers, confirm red, revert - and carries a one-line
mutation note directly above it.

### Manual Testing Steps:

1. Read `test/fixtures/documents/worked_example.json` side by side with
   ADR-0001's worked-example block and confirm the minification is faithful.
2. In `iex -S mix`, build a small document, `to_json/1` it, edit one byte of
   `config` in the resulting string, `from_json/1` it, and confirm the
   `content_hash/1` changes.
3. Confirm `from_json/1` on a document naming a block type this package has
   never heard of returns `{:ok, _}` - the registry-free guarantee, checked by
   eye as well as by test.
4. Confirm nothing in `lib/` references a registry, a block type name, or
   SCXML.

## References

- Source spec: `docs/adr/0001-block-document-schema.md` (accepted 2026-08-26)
- Related ADRs, all out of scope here: `docs/adr/0002-block-type-behaviour.md`,
  `docs/adr/0003-assignability.md`, `docs/adr/0004-compiler-provenance.md`,
  `docs/adr/0005-liveview-editor.md`
- Family id minting (st-ADR-0008, amended to drop the `uxid` dependency):
  `/Users/johnnyt/Dev/github/statifier/statifier-ex/lib/statifier/machine_state.ex:571-585`
  and the Crockford table at `:375-381`
- Family content hash and total typed decode of untrusted bytes (st-ADR-0052):
  `/Users/johnnyt/Dev/github/statifier/statifier-ex/lib/statifier/machine/identity.ex:53`
  and `:96-108`
- Conventions and gate rules: `CLAUDE.md`, `.quality.exs`, `coveralls.json`,
  `changelog.d/README.md`
- Bead: `sb-xti` (depends on `sb-nny`, blocks `sb-dvj`)

## Deferred Manual Verification

Manual verification items are deferred during looped (--loop) execution and
surfaced here once, rather than blocking after each phase. Confirm these
before considering the plan fully landed.

### Phase 1

- [ ] Every new test carries its one-line sabotage mutation note, and the
      mutation described actually turns that test red (no command checks
      this - `mix quality` cannot see a comment)
- [ ] The struct fields and `@type` definitions are a character-faithful
      transcription of ADR-0001's typespec block, with no field added,
      dropped, or renamed
- [ ] The minting matches statifier-ex's `generate_session_id/0` bit-for-bit
      in structure (48-bit timestamp, 80 bits entropy, lowercase Crockford)

**Implementation Note**: Use `mix quality --profile loop` between edits; run
full `mix quality` as the phase gate. In interactive execution pause here for
the human; in `--loop` execution the Automated Verification block gates
advancement and the Manual items defer to `/wurk:verify`.

---

### Phase 2

- [ ] Every new test carries its sabotage mutation note, verified by hand
- [ ] The check order matches ADR-0001 decision 9's "ordered check, one error
      arm per distinguishable cause" and no two distinguishable causes
      collapse into one arm
- [ ] No rescue-to-default anywhere in the module (`CLAUDE.md` convention)

**Implementation Note**: as phase 1.

---
