# Architecture Decision Records

| # | Decision | Status |
|---|---|---|
| [0001](0001-block-document-schema.md) | The block document is a tree of typed blocks with named slots | accepted |
| [0002](0002-block-type-behaviour.md) | A block type is a behaviour module resolved through a caller-supplied palette | accepted |
| [0003](0003-assignability.md) | Assignability is opaque-string identity plus a host-supplied widening relation | accepted |
| [0004](0004-compiler-provenance.md) | One block, one state - a deterministic compile carrying a provenance map | accepted |
| [0005](0005-liveview-editor.md) | The editor is a pure command algebra and view model with a thin LiveView shell | accepted |
| [0006](0006-datamodel-document.md) | The datamodel document is a typed, three-scope declaration, and the declared-path set is its projection | accepted |
| [0007](0007-block-type-defaults.md) | A block type declares its defaults with `use`, and the leaf invoke step is one declaration | accepted |
| [0008](0008-durable-subchart-handler.md) | The durable subchart handler answers at dispatch time, not from a pure `start/2`, and its refusal set gains exactly one reason | accepted |
| [0009](0009-fan-out-block-type.md) | Durable fan-out is a new block type, `core.map`, compiling to one invocation whose handler starts N children | accepted |
| [0010](0010-clock-interrupt-spelling.md) | A clock interrupt is a delayed `core.send` at the head of a group's body caught by a `core.on_event` on its rail, and there is no `core.timeout` | accepted |

New ADRs: next number, same three-section format (Context, Decision,
Consequences). Pick the number against a freshly fetched remote.

This repository inherits the family's ADR practice rather than restating it,
so there is no local "record architecture decisions" record; the umbrella's
decision D8 governs. A bare `ADR-NNNN` cites this repository's own records;
a cross-repo citation carries the owning repo's beads prefix (`st-ADR-0052`
is statifier-ex's ADR-0052, `sp-ADR-0003` is statifier_persistence's).

A `## Note` on a record carries no Status line. Every Status line in these
records sits on the record's own header or under a `## Amendment`, because an
amendment changes what the record decides and a note does not: a note records
where something already decided renders, or what a sentence already accepted
was about. Most of these notes open by saying what the note is not - a dated
note rather than an amendment, or rather than a proposed decision - then name
the decision they are about and close on what they leave unchanged. That is
the usual shape and not a required one: several open some other way, on the
finding itself or on why it came to be recorded, and a note is not wrong for
doing so.
