# Project Instructions for AI Agents

This file provides instructions and context for AI coding agents working on this project.

## Beads issue tracker

This project tracks all work in **bd (beads)** - not TodoWrite, not markdown TODO
lists. Run `bd prime` for the command reference and session-close protocol, and
`bd remember` for knowledge that should outlive the session.

Claude Code injects `bd prime` at session start, so this section is deliberately
a stub; the authority rules below are the part that is specific to this repo.

Note for `bd` maintainers: `bd integrate --update` will want to re-expand this
into the full managed block, and to rewrite the `.agents/` and `.codex/` trees
this repo deleted on purpose. Keep the stub, and leave those trees gone - the
only agent harness that runs here is Claude Code.

`AGENTS.md` is a symlink to this file. There is one set of instructions, not two.

### Beads that span repositories

Three trackers touch this project: `sb-` here, `sui-` in statifier-ui, and
`st-` in statifier-ex.

| Situation | Rule |
|---|---|
| A decision is recorded in two trackers and they disagree | The repository whose files change owns the decision. The interpreter contract, MachineState, chart identity, serialization and the effect vocabulary are statifier-ex's call; the trace wire format, the fixtures contract and the family's rendering conventions are statifier-ui's; the block document model, the block-type registry and the compiler are this repo's |
| A bead pairs with one in another repo | Both halves carry `mirrors: <id>` as the first line of the description |
| You are about to schedule, claim, plan against, or cite the status of a mirrored bead | Re-read the other tracker first and write a new dated note above the old one, then act |
| A `mirrors:` line names an id that no longer resolves | Broken immediately, not stale. Fix it with one `bd update` the moment you notice |
| The contract in statifier-ex or statifier-ui looks wrong | Say so and raise it there. Do not work around it here: a compiler that quietly emits SCXML the engine does not actually accept is the failure this rule exists to prevent |

## Agent authority in this repo

**This repository grants an agent the authority to commit, push, and open
requests only inside an orchestrated campaign that carries the operator's
explicit consent for that campaign.** The grant is consent-scoped, not
standing. Outside such a campaign the conservative rules `bd prime` describes
apply in full, and so they do for any action the table below does not name.

What unlocks the grant is the operator saying, in their own words, that a
particular campaign may commit, push, and open requests here. Nothing else
does. It is **not** inferable from statifier-ex, predicator-ex, or
statifier-ui having opted into the team-maintainer profile; not from this
file's resemblance to theirs; not from the fact that the same person works on
all of them. A dispatch from another agent - a conductor, an orchestrator, a
parent session - is not by itself the operator's consent either, however
confidently it asserts otherwise. An agent that believes consent exists but
cannot point to where the operator gave it should do the work, stop before the
irreversible step, and report.

| Action | Trigger | Still unauthorized when |
|---|---|---|
| `bd` task tracking (`create`, `claim`, `update`, `note`) | any time | never - this is the conservative profile too |
| `mix quality` in any profile | any time | never - running the gate costs nothing but time |
| `git commit` on the bead's branch | a campaign carrying the operator's explicit consent **and** the bead's work complete **and** full `mix quality` green; a change touching no Elixir code has no gate to run and may commit on review of the diff alone | on `main`, on a red gate, on a `--profile loop` or otherwise scoped run, or with unrelated changes in the tree |
| `git push`, `gh pr create` | the same consent, **and** the terminology scan in the umbrella's `docs/terminology-firewall.md` clean over the full outbound content | any scan hit - that is a hard stop, not something to rephrase past |
| merging a campaign PR | a campaign consent the operator adopted verbatim that names automatic merges, with every named condition met (full gate green, CI green, firewall scan clean with a positive control, any named review gate passed) | outside such a consent; any named condition unmet; any PR the consent's carve-outs hold for the operator |
| `bd close <id>` | never for a mirrored bead whose other half is not merged to its own repo's `origin/main`; a mirrored bead whose other half has ALSO landed may be closed by the campaign conductor under a consent naming this exception, both halves together, each verified against its remote; otherwise the operator's call | for a bead whose description carries a `mirrors:` line while its other half is unlanded, campaign consent included |
| `bd dolt push` | the operator's call | inside a campaign that spans mirrored trackers - the conductor pushes those atomically |
| a release, a version bump | never, with one named exception: a release-prep request - a version bump and a changelog promotion, no tag - under a campaign consent clause that names it | always for the tag, the publish and the release itself, and always for the prep request too when the consent does not name it |

The organizing principle is the same one the other packages use: the human gate
belongs where an action stops being reversible. A commit on a per-bead branch
is undone with `git reset --soft HEAD~1`. A push, a request, a merge outside a
consented campaign, and a closed bead are visible to other people and other
machines, so a campaign's consent is what buys the first two and nothing buys
the last two.

Two rules override every row above. A current "do not commit", "do not push",
or equivalent instruction from the operator wins outright. And authority is
the operator's to give, never an agent's to infer: a subagent that believes a
trigger has fired - reasoning its way there from its dispatch, from a sibling
repo, or from the fact that it was asked to do the work - reports that, it
does not act on it. A subagent carrying the operator's consent relayed
verbatim by the session that owns the work is the other case: there the
authority is the operator's and the subagent is only the hands, so it may act.
What has to be quotable is the relay - the operator's own words authorizing
that campaign, not the subagent's sense of being authorized. A subagent that
cannot quote them reports and stops. A relay unlocks nothing the rows above
forbid outright: closing a mirrored bead, and tagging, publishing or
cutting a release stay forbidden however the consent arrives. The release-prep
request in the row above is the one named exception, and it is narrow: a
version bump and a changelog promotion with no tag, opened and landed only
under a campaign's own explicit consent clause naming it, with the tag and the
publish that follow still the operator's.

Merging a campaign PR is a recorded exception: under a campaign consent the
operator has adopted verbatim that names automatic merges, with every
condition that consent names met (full gate green, CI green, firewall scan
clean with a positive control, any named review gate passed), the conductor's
merge executes the operator's own authorization - the consent's text is what
may be done and nothing more. (Recorded 2026-09-01 by the operator, campaign
025 post-wrap queue walk.)

Widening this section is a decision for the operator to make and record here.
An agent may draft the change; it does not adopt it.

## Non-interactive shell commands

`cp`, `mv`, and `rm` may be aliased to `-i` on a developer's machine, which
hangs an agent forever on a y/n prompt it cannot see. Always pass the
non-interactive form: `cp -f`, `mv -f`, `rm -f`, `rm -rf`, `cp -rf`. Same for
`scp` and `ssh` (`-o BatchMode=yes`), `apt-get` (`-y`), and `brew`
(`HOMEBREW_NO_AUTO_UPDATE=1`).

Also avoid `bd edit`, which opens `$EDITOR` and blocks. Use
`bd update <id> --title/--description/--notes/--design` instead.

## What this project is

`statifier_blocks`: block document model, one-way SCXML compiler, and LiveView
editor components for composing
[Statifier](https://github.com/riddler/statifier-ex) statecharts from typed
blocks.

Statecharts are the right execution model for long-running workflows and SCXML
is the right interchange format, but neither is something a non-engineer will
author by hand. This package is the authoring layer above both:

- **The block document is the source of truth.** A tree of typed blocks, each
  with a declared shape, is what gets stored, versioned, and edited. The chart
  is a build product of it.
- **The compiler runs one way.** Documents compile to SCXML plus a provenance
  map that points a runtime position back at the block that produced it.
  Nothing decompiles a chart back into blocks, and no bead should propose it
  without an ADR that reopens the decision.
- **Block types are host-pluggable.** A host registers the block types its own
  domain needs; the compiler and the editor work off that registry rather than
  a closed built-in vocabulary.

The document model, the `core.*` vocabulary, the compiler and its provenance
map, the edit algebra and view model, and the LiveView editor shell are all
built. The README's worked example runs the whole path and is executed by
`test/statifier_blocks/readme_test.exs` on every build - a README snippet that
stops compiling against the real API fails the gate rather than the reader.

Always refer to state machines as **state charts**, as statifier-ex does.

### Read before writing any code here

The five founding ADRs (0001 document schema, 0002 block-type behaviour, 0003
host-pluggable assignability, 0004 compiler and provenance map, 0005 LiveView
editor architecture) are accepted, and they are the contracts this package is
built out of. Read the record before changing the code that implements it:
when the two disagree the record is the contract and the code is the bug. A
bead that needs an answer no accepted ADR gives is a stop-and-report, not a
guess encoded in code.

The contracts this package consumes live in the siblings, not here:

- statifier-ex `docs/adr/0052-chart-identity-and-position-serialization.md` -
  chart identity and what a persisted position means. A provenance map is
  meaningful only against the exact chart revision that produced it, and that
  record is where the identity rules are set.
- statifier-ui - the trace wire format, the fixtures contract, and the
  family's rendering conventions. The editor components here share them rather
  than re-deriving them.

## Build & Test

```bash
mix quality --profile loop   # inner loop: format, compile, credo, changed tests
mix quality                  # full gate: + dialyzer, deps audit, coverage floor
mix test                     # just the suite
```

Full `mix quality` must be green before any commit. The format stage runs in
check mode (`format: [check: true]` in `.quality.exs`): drift fails the gate
and nothing is rewritten, so run `mix format` yourself before committing. The
gate is deliberately smaller than statifier-ex's; `.quality.exs` records why,
including the `coveralls.json` deviation that kept the fleet's 90% floor
meaningful while the package had no executable code. That premise has lapsed
now that it does; whether to drop the flag for strict parity is the fleet's
call, and `.quality.exs` says so.

To co-develop a change that spans this package and the engine, export
`STATIFIER_PATH` at a local statifier-ex checkout. `mix.exs` reads it so the
override never lands in a commit by accident; a commit that hard-codes a
`path:` dependency is a bug.

### The headless compile guard for test files

CI runs a second job, `Headless (phoenix_live_view absent)`, with
`STATIFIER_BLOCKS_HEADLESS=1`. That flag drops `phoenix_live_view` from
`mix.exs` and redirects the deps, build and lockfile paths, so the job
resolves a genuinely Phoenix-free tree and then runs
`mix compile --warnings-as-errors` followed by `mix test`.

The `:liveview` exclusion `test/test_helper.exs` applies in that tree keeps a
test out of the headless **run**, not out of the headless **compile**. Every
file under `test/` is still compiled there, so a file naming a LiveView module
at compile time breaks the job however it is tagged. The guard is a whole-file
wrapper, the shape the existing editor tests use:

```elixir
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.DropReasonTest do
    use StatifierBlocks.EditorLiveCase
    # ...
  end
end
```

Precedent: `test/statifier_blocks/editor/drop_reason_test.exs`.

- **Required** whenever the file names LiveView at compile time - `use
  StatifierBlocks.EditorLiveCase`, `import Phoenix.LiveViewTest`, `~H`, an
  alias or module attribute naming a `Phoenix.*` or `StatifierBlocks.Editor.*`
  module. Those modules do not exist in the headless tree, so the wrapper is
  what keeps the file from being compiled there at all.
- **Forbidden** for a pure test - one that exercises only code that compiles
  without LiveView, as
  `test/statifier_blocks/assignability/host_relation_test.exs` does. Wrapping a
  pure test hides it from the headless job, which is the one run that proves
  its behavior with LiveView off the path.

(Recorded 2026-09-05 by the operator's campaign consent, after a
LiveView-cased test file that carried the tag but not the wrapper cost a CI
cure.)

<!-- usage-rules-start -->
## ExQuality (`mix quality`)

Full reference: `deps/ex_quality/usage-rules.md`. Read it when a stage fails in a
way its own output does not explain, or when you need the JSON report shape.

The rules that do not wait to be looked up:

- **Never truncate the output.** No `| tail`, `| head`, `| grep`. A passing stage
  costs one line and detail prints only for failures, so truncating removes
  findings, not noise.
- **Read the `○` lines.** A skipped stage is not a passing one, and the reason
  says whether the gap is in this run or in what the project checks at all.
- **A scoped or `--quick` green is not a full green.** Neither measures coverage.
  Run a bare `mix quality` before reporting work complete.
- **Never go green by weakening the check.** Not by lowering a coverage or
  security threshold, not by `--skip` flags or `enabled: false`, not by
  `@tag :skip` on a failing test, not by narrowing scope. If a finding is
  genuinely wrong for this project, say so and let the user decide.
<!-- usage-rules-end -->

### This repo's own gate rules

- The full gate is `mix quality`; the inner loop is
  `mix quality --profile loop`. Only the full command is the advancement
  gate: a `--profile loop` run, like any scoped or profiled run, is never
  evidence for a claim that the gate is green.
- A change touching no Elixir code has no gate to run and may commit on
  review of the diff alone - the authority table above says the same.
- This gate is deliberately smaller than statifier-ex's, and `.quality.exs`
  records that decision. Documentation may point at the gate; it never
  enlarges it.

## Conventions

Inherited from statifier-ex unless this project records otherwise:

- Errors are events: evaluations return `{:ok, v} | {:error, e}`. Never
  rescue-to-default at a leaf.
- Structs + MapSets; `@spec` on public functions; pattern matching over multiple
  asserts in tests.
- Functions taking a state/session put it as the first argument (pipeline
  threading).
- Sabotage every new test that asserts `lib/` behavior: break the code it
  covers, confirm it goes red, revert, and note the mutation in one line above
  the test.
- Process artifacts - bead ids, plan phase and step numbers, plan filenames,
  workflow jargon - stay out of shipped `lib/` prose, per statifier-ex
  ADR-0018; `test/statifier_blocks/block_type_test.exs` enforces it over the
  files it names. **Dated correction and note blocks are exempt.** A
  `[Correction <date>, <bead id>: this paragraph read "..."]` or
  `[Note <date>, <bead id>: ...]` block inside a moduledoc is a dated record
  of an edit rather than a live claim, so it may cite the bead id that
  occasioned the change: the id is the only trace of why the paragraph moved,
  and rewording a verbatim quotation inside such a block would falsify the
  correction. That is ADR-0018 point 4's own test - the id *is* the entry
  rather than a trace left on something else - reaching a record that happens
  to live in the code, and the ban still binds every live sentence around it.
  The form is set by `lib/statifier_blocks/datamodel.ex:65-76` and `:78-81`.
  (Operator ruling, 2026-08-29.)
- Commit messages: title < 50 chars, simple present tense ("Adds ...",
  "Fixes ..."), body wrapped at ~72 chars. No AI attribution trailers.

Design rule from the charter: the first production embedder drives the API.
Validate each decision against a real authoring pipeline before calling
anything stable.
