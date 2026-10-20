# Documents, revisions, charts and executions, and why blocks compile to a chart

This page explains the four nouns this package and its docs use - document,
revision, chart and execution - what each one is for, and why the package
compiles blocks to a chart rather than editing the chart directly. It
describes how the pieces relate; the how-to guides cover doing the work.

The running example is patron registration: a visitor becomes a library patron
through a few screens, and a library card is issued when the visitor is old
enough for one.

## Why blocks compile to a chart

Statecharts are the right execution model for long-running workflows, and
SCXML is the right interchange format for them. Neither is something a
non-engineer will author by hand. This package is the authoring layer in
between: a person composes typed blocks, and the package turns what they
composed into SCXML that Statifier can run.

That gives the package two artifacts with two different jobs. The document is
a tree of typed blocks, each block a unit with a declared shape rather than
free-form XML. It is the source of truth that gets edited and stored. The
chart is what the compiler emits from it, the form the engine runs.

The direction is deliberate. Documents compile to charts, and nothing
decompiles a chart back into blocks. Editing happens on the document, where
each block has a declared shape; the chart is derived from it. So
that a position in a running chart is not a dead end, the compiler also
carries a provenance map: it lets a runtime position be pointed back at the
block that produced it.

## The four nouns

Each noun has one job, and the same four are used by the engine's
[persistence guide](https://github.com/riddler/statifier-ex/blob/main/docs/persistence.md#the-four-nouns).

| Noun | What it is here | Identity | Owner | Changes when |
|---|---|---|---|---|
| **Document** | The block tree an author edits, under one stable id | The `id` of a `%StatifierBlocks.Document{}` | The host's authoring store | Never |
| **Revision** | One saved edit of a document | The document id plus the ordinal in the document's `revision` field | The host's revision store; this package stores nothing | Every saved edit |
| **Chart** | The SCXML `StatifierBlocks.Compiler.compile/3` emits for a revision | `chart_identity`: the SHA-256 hash of the SCXML bytes, plus the document id as `:chart_name` and a `nil` `:chart_version` (`Statifier.Machine.Identity`, the engine's ADR-0052) | The engine | A byte of the SCXML changes |
| **Execution** | One instance of a chart a host starts | A minted id, pinned to one chart identity | The persistence package or the host | Re-pinned only by an explicit migration |

In patron registration, the registration flow is one document. Each time an
author saves an edit, the host keeps a new revision of it. Compiling a
revision gives a chart. Each visitor who starts registering is an execution
of one chart.

The "Changes when" column is the useful one. A document never changes
identity, however many revisions it collects. A revision changes on every
saved edit. A chart changes only when a byte of its SCXML does, which is
why two revisions can share a chart. An execution does not change chart at
all unless the host migrates it.

## The record that joins a revision to a chart

`StatifierBlocks.CompilationRecord` is the bridge between a revision and a
chart. Every successful compile returns one as `compiled.record`. It holds
the revision's side (`document_id`, `revision`, and `document_hash`, the
SHA-256 of the revision's canonical bytes), the compile inputs
(`palette_hash`, `compiler_version`) and the chart's side
(`chart_identity`).

Neither hash is derived from the other. Two revisions that differ only in
`metadata` compile to one chart, so the revision's hash and the chart's
identity can disagree about whether two things are the same. The compile
therefore emits the join as a fact instead of leaving a reader to infer it.

An execution names its chart identity. Looking the record up by
`chart_identity` gives back the document, and the revision or revisions that
compiled to that chart.

## Three more parts of the compiled artifact

Three more parts of what a compile returns belong to the same nouns:

- **`accepts`** is a document field, so each revision carries its own
  list: the names of the external events it declares its chart accepts.
  The compile passes it through onto `compiled.accepts` and
  `compiled.record.accepts` without judging it. It never reaches the
  SCXML, so a revision that edits only `accepts` compiles to the same
  chart. Whether the chart can take each name is a publish-time question,
  answered by the fourth check in the README's
  [At publish](../../README.md#at-publish) section.
- **`interface`** on `%StatifierBlocks.Compiled{}` is what the chart offers
  a parent that invokes it - the outcomes and done-data keys its root
  declares - and what it relies on from each document it names. A child is
  named by document id, never by chart: which revision, and so which
  chart, an id resolves to is the host's resolver's answer. `interface`
  adds nothing to the SCXML and is not on the record.
- **`StatifierBlocks.Publish.findings/3`** judges one revision - the
  document the host is about to publish - and emits no SCXML, so it runs
  before any chart for that revision exists. The host refuses to publish
  the revision on an `:error`.

## What publishing does and does not touch

Publishing makes a chart and its record, and touches no execution. An
execution already in progress stays pinned to the chart it started on.
Moving it to another chart is an explicit migration a host performs, never
a side effect of a publish, and nothing in this package migrates one.

In patron registration, that means a visitor halfway through the screens
keeps the chart they started on when the library publishes a new revision of
the registration document. The new revision compiles to a chart of its own;
the visitor's execution is not moved to it.

## Where to go next

- [How to build a block document and compile it to a chart](../guides/build-and-compile.md)
  shows the compile and its record in running code.
- [At publish](../../README.md#at-publish) lists the checks a host's publish
  step makes before it keeps a revision.
