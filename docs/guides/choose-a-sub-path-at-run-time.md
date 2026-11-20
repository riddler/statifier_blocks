# How to choose a sub-path at run time

This guide shows you how to let a document decide, while it runs, which other
document to run as a child: a `core.subchart` that reads the child's document
id from the datamodel instead of naming it when the document is written, and
a resolver in your host that runs only the documents you offer.

The example host is a library system. When a branch library joins, its
onboarding runs one setup for each integration the branch picked: a catalogue
sync, a reading-list import or a card-reader setup. Each setup is its own
document, published for use as a child. One block in the onboarding document
runs whichever setup comes next, so a branch that picks two setups runs two,
and a fourth setup is a new document rather than an edit to the onboarding.

The document on this page is a fixture,
[`test/fixtures/documents/sub_path_at_run_time/branch_onboarding.json`](https://github.com/riddler/statifier_blocks/blob/main/test/fixtures/documents/sub_path_at_run_time/branch_onboarding.json),
quoted byte for byte, and
[`test/statifier_blocks/sub_path_at_run_time_guide_test.exs`](https://github.com/riddler/statifier_blocks/blob/main/test/statifier_blocks/sub_path_at_run_time_guide_test.exs)
compiles it and runs the resolver below against it on the current release.

## Before you start

- A host that already runs subcharts: a module that uses
  `StatifierBlocks.Runtime.Subchart` (or `StatifierBlocks.Runtime.DurableSubchart`
  for durable executions), serving the `statifier_blocks:subchart` invoke
  type. [Config fields and the handlers this package
  ships](../reference/config-fields-and-handlers.md) sets one up.
- The setup documents, each one compiling with `child_use: true`.
- A datamodel path that an earlier step writes the next setup's document id
  to. Here it is `onboarding.setup_document`.

## Name the child by a path

A `core.subchart` names its child by exactly one of two config keys:

- `chart`, a document id, fixed when the document is written; or
- `chart_from`, a datamodel path whose value, when the block's child starts,
  is the document id to run.

In the editor, select the subchart block. Its config form draws **Run this
chart** for `chart` and, under it, **Or run the chart whose id is at** for
`chart_from`. Leave **Run this chart** empty and type the path into the
second field. The path field offers the datamodel paths the document
declares, as **Write the outcome to** does. A form that fills in both fields
is refused with one finding on `chart_from`: clear one of them. To move a
block from `chart` to `chart_from`, empty the first field and fill in the
second in the same edit.

With the block selected, the description under the canvas then reads **Run
the chart named at onboarding.setup_document and wait**.

## List every outcome the setups finish with

The block cannot read the documents its path may name, so it declares the
outcomes they finish with in **It can finish with**, one per line, and gets
one `on_<outcome>` slot for each, with `on_error` last. A child that finishes
with fewer outcomes is fine: a slot the child never reaches is simply not
taken. A child whose root declares an outcome the block does not list is
not started: the block receives `error.communication.invoke.<block id>`
with the reason `child_outcome_undeclared`, and its `detail` names the
outcomes the block is missing.

The three setups finish this way:

| Document id | Root outcomes |
|---|---|
| `doc_catalogue_sync` | `done`, `skipped` |
| `doc_reading_list_import` | `done` |
| `doc_card_reader_setup` | `done`, `skipped`, `needs_site_visit` |

So the block lists `done`, `skipped` and `needs_site_visit`. The whole
document:

```json
{
  "schema_version": 1,
  "id": "doc_branch_onboarding",
  "revision": 1,
  "metadata": {"name": "Branch library onboarding"},
  "accepts": ["onboarding.setup_reviewed"],
  "datamodel": [
    {"id": "onboarding", "description": "The branch's onboarding: setup_document holds the id of the next setup to run."}
  ],
  "root": {
    "id": "blk_ROOT", "type": "core.sequence", "type_version": 1,
    "slots": {"body": [
      {"id": "blk_SETUP", "type": "core.subchart", "type_version": 1,
       "config": {"chart_from": "onboarding.setup_document",
                  "outcomes": "done\nskipped\nneeds_site_visit"},
       "slots": {
         "on_needs_site_visit": [
           {"id": "blk_VISIT", "type": "core.send", "type_version": 2,
            "config": {"event": "onboarding.site_visit_requested"}}
         ],
         "on_error": [
           {"id": "blk_REFUSED", "type": "core.await", "type_version": 1,
            "config": {"event": "onboarding.setup_reviewed"}}
         ]
       }}
    ]}
  }
}
```

It compiles under the core palette with no finding. The block's `<invoke>`
carries the path as `srcexpr` instead of a `src`, and one reserved param
carrying the block's declared outcomes, which the handler removes before the
child starts:

```xml
<invoke id="blk_SETUP" srcexpr="onboarding.setup_document" type="statifier_blocks:subchart">
  <param expr="'done skipped needs_site_visit error'" name="statifier_blocks:outcomes"/>
</invoke>
```

## Make your resolver the allow-list

The path is read when the child starts, and whatever string it holds then
reaches your resolver's `resolve_chart/2`, including a string an external
event's data wrote. This package checks nothing about the id beyond that it
is a string, so the resolver is the one place that decides which documents
may run. Answer only the ids you offer, and `:error` for every other:

```elixir
defmodule Library.OnboardingSetups do
  use StatifierBlocks.Runtime.Subchart

  alias StatifierBlocks.Palette

  @setups ["doc_catalogue_sync", "doc_reading_list_import", "doc_card_reader_setup"]

  @impl true
  def resolve_chart(document_id, _ctx) when document_id in @setups,
    do: Library.Documents.published(document_id)

  def resolve_chart(_document_id, _ctx), do: :error

  @impl true
  def palette, do: Palette.core()
end
```

`Library.Documents.published/1` stands for your own document store: it
answers `{:ok, document}` with the revision to run, or `:error`.

With this resolver:

- `onboarding.setup_document` holds `"doc_catalogue_sync"`: the setup starts
  as the child, and the block takes the slot of the outcome it finishes with.
- It holds `"doc_branch_closure"`, a document you do not offer: the resolver
  answers `:error`, no child starts, and the block receives
  `error.communication.invoke.blk_SETUP` with the reason `unknown_document`.
  Its `on_error` slot catches it, here by waiting for the desk to review
  the branch's choice (`onboarding.setup_reviewed`).
- It holds something that is not a string, such as a number, or nothing has
  written it yet: the handler refuses it `unknown_document` without calling
  the resolver, and `on_error` catches it the same way.

## What a publish no longer checks

A block that names its child by `chart` is checked at publish against the
document it names: the compile records the reference, refuses a block that
names its own document, and the graph checks compare the parent's outcomes
with the child's. A `chart_from` block has no document id until it runs, so
the compile records no reference for it and none of those checks judge it.
Whether the id names a document you offer, whether that document compiles as
a child, and whether running it would loop back to a document already
running are decided when the child starts, by your resolver and the handler.
A resolver that can be handed a document's own id answers `{:cycle, path}`
for it, and the handler refuses `cycle_refused`; the allow-list above offers
no id of the onboarding document, so it cannot be asked to run itself.
