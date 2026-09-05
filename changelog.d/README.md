# Changelog fragments

Changelog entries for unreleased work live here as one file per issue, not as
edits to `CHANGELOG.md`. At release the fragments are assembled into a single
version section and deleted.

## Why fragments

Parallel work happens in one worktree per issue, so several branches are
usually open at once. If each branch appended to the `## [Unreleased]` block
at the top of `CHANGELOG.md`, every branch would touch the same few lines of
the same file and nearly every pull request would conflict with every other
one.

A fragment is named after its issue, so no two branches ever write the same
file and the conflict cannot happen.

## When a change needs a fragment

The changelog serves **people who use the library**. Repo history is git's job,
and work tracking is beads' job. Neither belongs here.

Write a fragment for:

- a public API addition, change, or removal
- a change in observable behavior
- a bug fix a user could have noticed
- anything breaking

Do **not** write a fragment for:

- test harness or fixtures
- documentation, ADRs, or plans
- internal refactors with no visible effect
- quality gate, CI, or agent tooling changes

If you are unsure, ask whether someone who only ever calls the public API could
tell the difference. If not, skip it.

## Format

One file per issue, named for the beads issue ID:

    changelog.d/sb-abc.md

Contents are the Keep a Changelog section heading followed by the entry:

```markdown
### Added

- Block documents compile to SCXML together with a provenance map from
  runtime positions back to the blocks that produced them.
```

Rules:

- Use only the standard headings: `Added`, `Changed`, `Deprecated`, `Removed`,
  `Fixed`, `Security`.
- One line per change, present tense, describing the effect on the user.
- No nested bullets. Detail belongs in the pull request and the commit body; a
  changelog line that needs sub-points is really several changes or one that is
  over-explained.
- One file may carry more than one heading if an issue genuinely spans them.
- For a breaking change, say what to do about it, not just what broke.

## At release

Assemble the fragments into a new version section in `CHANGELOG.md`, grouped by
heading and ordered `Added`, `Changed`, `Deprecated`, `Removed`, `Fixed`,
`Security`. Within one heading, when more than one fragment contributed bullets
to it, the fragments go in fragment-name order - `sb-0l36.md` before
`sb-4r1p.md` - and each fragment's own bullets keep the order they have in
their file. Delete the promoted fragments in the same commit; this `README.md`
stays.

That commit is a release **prep**: the version bump and this promotion, and
nothing else. It does not tag, push, publish, or cut a GitHub release - those
are the operator's, in every campaign and outside every campaign, as
`CLAUDE.md`'s authority table says. `.claude/wurk/release.md` is the full
recipe and it says the same.
