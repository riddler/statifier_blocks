# Architecture Decision Records

| # | Decision | Status |
|---|---|---|
| [0001](0001-block-document-schema.md) | The block document is a tree of typed blocks with named slots | accepted |
| [0002](0002-block-type-behaviour.md) | A block type is a behaviour module resolved through a caller-supplied palette | accepted |
| [0003](0003-assignability.md) | Assignability is opaque-string identity plus a host-supplied widening relation | accepted |
| [0004](0004-compiler-provenance.md) | One block, one state - a deterministic compile carrying a provenance map | accepted |
| [0005](0005-liveview-editor.md) | The editor is a pure command algebra and view model with a thin LiveView shell | accepted |

New ADRs: next number, same three-section format (Context, Decision,
Consequences). Pick the number against a freshly fetched remote.

This repository inherits the family's ADR practice rather than restating it,
so there is no local "record architecture decisions" record; the umbrella's
decision D8 governs. A bare `ADR-NNNN` cites this repository's own records;
a cross-repo citation carries the owning repo's beads prefix (`st-ADR-0052`
is statifier-ex's ADR-0052, `sp-ADR-0003` is statifier_persistence's).
