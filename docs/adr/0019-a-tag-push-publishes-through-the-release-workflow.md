# ADR-0019: A tag push publishes through the release workflow - three checks at the tagged commit, the full gate, then Hex

Status: accepted (2026-10-10, statifier_blocks 0.42.1); proposed (2026-10-04, drafted under the operator's campaign consent;
the move to publishing on a tag push was ruled by the operator,
2026-10-04). It merges at proposed and stays proposed until the workflow it
records has published a version of this package; flipping it to accepted is
a separate request through the same `docs/adr/` gate, with that workflow
run's address as the evidence beside the SHA.

Cites into `.github/workflows/ci.yml` and `CLAUDE.md` were read at
`9874ead` and carry their anchors; the workflow this record decides,
`.github/workflows/release.yml`, lands in the same request as this record
and is cited by its step names. Re-locate by anchor, not by number.

## Context

**The publish was the one release step a person ran by hand.** Before this
record, the version bump and the changelog promotion of a release prep, and
the tag of that prep once it is merged, were already an agent's work under
`CLAUDE.md`'s authority table (the release-prep row) and its Release preps
paragraph; the publish, `mix hex.publish`, was the operator's alone, and the
release-prep row's last cell held it back "always". Every release therefore
waited on the operator being at a machine that held the Hex credentials,
after everything that decides what ships had already happened.

**What ships is decided before the publish.** The tag names a commit; the
version is `@version` in `mix.exs` at that commit; the code is that commit's
tree; and the full quality gate (`mix quality`, the `gate.full` command in
`.claude/wurk.json`) is what says the commit is fit. CI already runs that
gate on every push to the default branch (`ci.yml:96`, the "Full quality
gate" step of the `gate` job). The publish adds no judgement of its own; it
uploads what the three facts already fix.

## Decision

1. **A tag push is the trigger, and nothing else.**
   `.github/workflows/release.yml` runs on a push of a tag matching
   `v*.*.*` and on no other event: no branch push, no pull request, no
   manual dispatch. Its one job, "Verify, gate and publish", holds
   `contents: read` and no other token permission, and runs at most once
   per tag at a time, never cancelled once started.

2. **Three conditions hold at the tagged commit, or nothing is published.**
   - **On the default branch.** The tagged commit is an ancestor of the
     default branch's head (`git merge-base --is-ancestor`), the branch
     named by the push event itself
     (`github.event.repository.default_branch`) and fetched under that
     name, never written into the file (the steps "Fetch the default
     branch" and "Check the tagged commit is on the default branch").
   - **The tag names the version.** The tag name without its leading `v`
     equals `@version` in `mix.exs` at the tagged commit (the step "Check
     the tag names the version in mix.exs").
   - **The full gate is green.** The workflow runs the gate itself, the
     `gate.full` command read out of `.claude/wurk.json` exactly as the
     `gate` job of `ci.yml` runs it, after the toolchain, cache and
     dependency steps copied from that job (`ci.yml:26-102`, from the
     comment above "Read the toolchain out of mise.toml" to the end of
     "Full quality gate"), Node included. The `headless` job is not copied:
     it proves an optional-dependency tree (ADR-0005 decision 1), it is not
     part of the gate, and `ci.yml` runs it on every push to the default
     branch.

   The first two checks, and a fourth below, run before any toolchain is
   installed, so a wrong tag stops in seconds. Running the gate inside the
   workflow, rather than reading CI's result for the commit, reading the
   default branch from the event, reading the version from `mix.exs` at the
   tag, copying the toolchain from `ci.yml` rather than sharing it, and
   leaving out a manual dispatch were decided by the conductor under a
   standing consent, 2026-10-03.

3. **The registry is Hex, and the key is named, never held.** The publish
   step runs `mix hex.publish --yes`, which builds and publishes the package
   and its docs together; HexDocs keeps every version's documentation as it
   did when the publish was by hand, and the docs that publish are the docs
   the gate built. The step authenticates with the `HEX_API_KEY` secret,
   read as `${{ secrets.HEX_API_KEY }}` in that one step's environment and
   nowhere else; Hex reads it in place of a logged-in user. The secret is
   the operator's, created and rotated outside this repository; no agent
   or session reads, writes or holds its value. The last step prints the
   published version's addresses on hex.pm and HexDocs. Publishing the
   docs with the package was decided by the conductor under a standing
   consent, 2026-10-04.

4. **A failed publish is not retried by the workflow.** A run that stops at
   a check or at the gate publishes nothing, and the tag stands as the
   record of what was attempted: the fix lands on the default branch and
   the next patch version is tagged; a tag is never moved or pushed again.
   A run whose publish step failed on a registry or network error may be
   re-run once by hand from the run's page in the Actions tab; the re-run
   repeats the whole job, the checks and the gate included, which is safe
   because each is read-only until the publish. A failed
   gate is never re-run, and a second failure of the publish is the
   operator's. A version Hex already shows is reported and never published
   again: the step "Check Hex does not already show this version" stops the
   run (or a re-run) before the toolchain when Hex answers that the version
   exists, and also stops it when Hex does not answer. This handling was
   decided by the conductor under a standing consent, 2026-10-04.

5. **An agent or a session never runs the publish.** `CLAUDE.md`'s
   release-prep row, its relay paragraph and its Release preps paragraph,
   and the closing section of `.claude/wurk/release.md`, say so in the
   operator's words: the release workflow publishes on the tag push the
   release-prep row already allows, and a failed workflow is re-run from
   its Actions page, never worked round by a local publish.

## Consequences

- A release is the prep, its merge and its tag; the publish follows from
  the tag with no one at a credentialed machine. Each release costs one
  more run of the full gate, inside the workflow.
- A published version stands. Hex lets a new version of an existing
  package be replaced or reverted only within one hour of its publication
  (`mix help hex.publish`, "Reverting a package"). The workflow does
  neither: its Hex check refuses to publish a version Hex already shows,
  and no agent or session replaces or reverts one. After that hour a
  version can only be retired (`mix help hex.retire`), which flags it but
  keeps it resolvable.
- A tag pushed for a commit off the default branch, or naming a version
  `mix.exs` does not state, or on a red gate, is visible in the Actions
  log and publishes nothing; it is not undone by deleting or moving the
  tag.
- If the publish step lands the package but its docs fail,
  the version is on hex.pm without docs; a re-run reports it as already
  on Hex, and the docs are the operator's to republish by hand, never an
  agent's or a session's.
- The workflow's toolchain block is a copy of `ci.yml`'s, so a change to
  how CI provisions the toolchain or runs the gate is made in both files.
- `changelog.d/README.md`'s "At release" section still says the publish
  is the operator's; that sentence is outside this record's request and
  is corrected separately.

## Note (2026-10-10): this record is flipped to accepted

A dated Note rather than an amendment: it carries no `Status:` line, decides
nothing, and edits no clause. The only line this request changes above it is
the head status line (`:3`), where the status word `accepted` with its date
and the version leads and the original `proposed (2026-10-04, ...` text stays
as written; the rest of the Status paragraph is unchanged. Everything else is
this Note, at the foot of the file, so no line another record cites moves.

The Status paragraph names its own condition: the record stays proposed
until the workflow it records has published a version of this package, and
the flip carries that workflow run's address beside the SHA. The condition
is met. The first publish through the workflow is statifier_blocks 0.42.1,
published on Hex from the `v0.42.1` tag at `f258547`
(`f258547bcebb28e13ee7e95205a2c851699156d3`), by the run
https://github.com/riddler/statifier_blocks/actions/runs/37308136300 (the
job "Verify, gate and publish", first attempt, every step green, the step
"Publish to Hex" included). No later version has been published through the
workflow. That a whole-record flip of these release-workflow records takes
the first workflow publish as its evidence was ruled by the operator,
2026-10-06; naming that version on the status line was decided by the
conductor under a standing consent, 2026-10-10.

Every claim the record makes was re-verified against `main` at `2e6240c`
(`2e6240c047c682310aa5247abfd49cb8089be1c4`) on the day of this flip; no
commit after `f258547` touches a file the record cites. Every cite below
was read there and is written anchor first, line second.

### Each decision, and where it reads today

| Decision | Read at `2e6240c` |
|---|---|
| 1, a tag push is the trigger | `.github/workflows/release.yml` triggers on `push: tags: "v*.*.*"` alone (`on:`, `:11-14`); its one job is named "Verify, gate and publish" (`:29`); `permissions: contents: read` is the only token permission (`:18-19`); `concurrency` groups on the tag ref with `cancel-in-progress: false` (`:23-25`) |
| 2, on the default branch | the steps "Fetch the default branch" (`:41`) and "Check the tagged commit is on the default branch" (`:49`) read `github.event.repository.default_branch` and run `git merge-base --is-ancestor` |
| 2, the tag names the version | the step "Check the tag names the version in mix.exs" (`:61`) compares the tag without its `v` to `@version` in `mix.exs`; at `f258547`, `mix.exs:4` reads `@version "0.42.1"` |
| 2, the full gate is green | the step "Full quality gate" (`:164`) reads `.gate.full` out of `.claude/wurk.json` (`["mix", "quality"]`) and runs it as `ci.yml`'s step of the same name (`ci.yml:96`) does; the block from the comment above "Read the toolchain out of mise.toml" to the end of "Full quality gate" (`ci.yml:26-102`) is copied line for line (`release.yml:94-170`), Node included (`actions/setup-node@v4`); no `headless` job is in the file |
| 2, checks before the toolchain | "Check Hex does not already show this version" (`:75`) and the two checks above run before "Read the toolchain out of mise.toml" (`:97`) |
| 3, Hex, the key named | the step "Publish to Hex" (`:175`) runs `mix hex.publish --yes` with `HEX_API_KEY: ${{ secrets.HEX_API_KEY }}` in that step's `env:` and nowhere else in the file; "Print the published version's address" (`:180`) prints the hex.pm and HexDocs addresses |
| 4, no retry by the workflow | the Hex check (`:75`) stops on a `200` and on any answer but `404`; the file has no retry, and the header comment (`:3-9`) names the one manual re-run |
| 5, never an agent's publish | `CLAUDE.md`'s release-prep row (the authority table's last row), its relay paragraph ("the publish that follows is the release workflow's") and its Release preps paragraph ("An agent or a session never runs `mix hex.publish`"); `.claude/wurk/release.md`, "What a release here still is not", its closing paragraph |
| Context, CI runs the gate on every push to the default branch | `ci.yml`'s `on:` (`:3-8`) names `push: branches: [main]`; its `gate` job's "Full quality gate" (`:96`) |
| Consequences, the one-hour window | `mix help hex.publish`, "Reverting a package": a new version of an existing package can be reverted or updated within one hour |

### Sentences that name a status

They are met here, not edited.

- The head status paragraph's "It merges at proposed and stays proposed until
  the workflow it records has published a version of this package; flipping
  it to accepted is a separate request through the same `docs/adr/` gate,
  with that workflow run's address as the evidence beside the SHA" is met by
  this request, 0.42.1 and the run above.
- The cites paragraph's "the workflow this record decides ... lands in the
  same request as this record" described the day it was written; it landed
  with this record in `d504636`.
- The last Consequence, that `changelog.d/README.md`'s "At release" section
  still says the publish is the operator's, still reads so at `2e6240c`
  ("Publishing and the release itself stay the operator's"); the record left
  it to a separate request, and this Note changes nothing there.
