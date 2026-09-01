# Release extension

Additional required steps for `/wurk:release` in this repo. The skill reads
this file before step 1 of its `kind: "hex"` recipe and treats what is here as
required steps placed where this file says. Extensions add; they never
override, and nothing below rewrites a step the skill already performs.

Read this together with `.claude/wurk.json`'s `release` block. Between them
they name every file a release commit here touches, and no others.

## Why the recipe names no changelog

`kind: "hex"`'s changelog step renames a `## [Unreleased]` heading in one file
to `## [X.Y.Z] - YYYY-MM-DD`. This repo has no such heading and never will:
`changelog.mode` is `fragments`, and `CHANGELOG.md` says so in its own header -
unreleased work lives one file per issue in `changelog.d/`, and the fragments
are assembled into a version section at release. Pointing `release.changelog`
at `CHANGELOG.md` would make the skill's precondition read for an unreleased
section that is not there, and its edit rename a heading that does not exist.

So `release.changelog` is deliberately absent, and a recipe that does not name
a changelog names no changelog edit. The promotion this repo actually performs
is step B below - a required step, not an optional one. A release commit
without it is not a release commit.

The unreleased-work check the skill makes before anything else reads
`changelog.d/` here: if the directory holds no fragment other than its own
`README.md`, there is nothing to release, and the run stops exactly as it
would on an empty unreleased section.

## Step A: the compiler's version carrier

Placed with the skill's version-file edit, in the same commit.

`lib/statifier_blocks/compiler.ex` carries the package version a second time,
as `@compiler_version`. It is the compiler's third determinism input and it is
stamped into every compiled record, so it has to move with `mix.exs` on every
release. Bump it to the same `X.Y.Z`.

`test/statifier_blocks/compiler_test.exs:272` asserts
`Compiler.compiler_version() == Mix.Project.config()[:version]`, so the two
cannot drift silently: a `mix.exs` bump on its own takes the gate red rather
than shipping a record stamped with the previous version. That assertion is
the check, not a substitute for doing this step.

Nothing else in `compiler.ex` changes. The comment above the attribute already
explains why it exists; the release moves the string.

## Step B: promote the changelog fragments

Placed where the skill's changelog step would have been, and modeled on the
0.11.0 prep commit `2677063`, which is the reference for the shape.

1. Read every `changelog.d/*.md` fragment except `README.md`. Each is a Keep a
   Changelog section heading followed by its bullets.
2. Insert a new `## [X.Y.Z] YYYY-MM-DD` section into `CHANGELOG.md` directly
   above the previous version's section, dated today. The heading form is the
   one the file already uses - the bracketed version and the date, with no
   separator between them.
3. Under the heading, write a short lead paragraph saying what the release is,
   then the fragments' bullets grouped by heading and ordered `Added`,
   `Changed`, `Deprecated`, `Removed`, `Fixed`, `Security`.
   **Carry every bullet over byte for byte.** The lead paragraph and the link
   reference are the only prose written at release time; reordering,
   consolidating or rewording a fragment's bullet is an editorial pass a human
   does separately, before the release.
4. Add `[X.Y.Z]: https://github.com/riddler/statifier_blocks/releases/tag/vX.Y.Z`
   at the top of the link-reference block at the end of the file.
5. Delete the promoted fragment files in the same commit. `README.md` stays.

Whether the release is major, minor or patch is not decided here - the version
is explicit input to the skill. The fragments' headings are evidence for that
judgement, not a rule that computes it.

## The README install pin needs no step here

`release.readme_pin` is `true`, and the skill's own step covers this repo's pin
without help: `README.md` carries `{:statifier_blocks, "~> 0.11"}` in its
`def deps` snippet, which is exactly the major/minor form with the patch
component dropped that the skill bumps, and `2677063` shows the previous
release moving it that way (`~> 0.10` to `~> 0.11`). It is named here only so
that the carriers a release moves are all listed in one place.

## The files a release commit touches

Exactly these, and a release commit that touches anything else is wrong:

| File | Moved by |
|---|---|
| `mix.exs` | the recipe's `version_file` |
| `README.md` | the recipe's `readme_pin` |
| `lib/statifier_blocks/compiler.ex` | step A |
| `CHANGELOG.md` | step B |
| `changelog.d/*.md` (deleted) | step B |

## What a release here still is not

The skill does not tag, push, open a request or publish, and this extension
does not either. In this repo those are the operator's, in every campaign and
outside every campaign - `CLAUDE.md`'s authority table says so, and the one
exception it names is a release-prep request: the version bump and the
changelog promotion above, no tag, under a campaign consent clause that names
it.
