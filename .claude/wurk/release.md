# Release extension

Additional required steps for `/wurk:release` in this repo. The skill reads
this file before step 1 of its `kind: "hex"` recipe and treats what is here as
required steps placed where this file says. Extensions add; they never
override, and nothing below rewrites a step the skill already performs.

Read this together with `.claude/wurk.json`'s `release` block. Between them
they name every file a release commit here touches, and no others.

The reference for every shape below is **the most recent release-prep commit
on `main`**, resolved when you read this rather than named here. Find it with:

```bash
git log --oneline --no-patch -L '/@version/,+1:mix.exs'
```

The first line is the last commit that moved `@version`, and the last commit
that moved `@version` is the last release prep by definition. Where this file
and that commit disagree, the commit is the evidence and this file is the
defect.

**This file names no SHA for that reference, on purpose, and it carries no
version string anywhere.** A hard-coded reference stops being the most recent
the moment the next release lands: the sentence that used to sit in step B
named the 0.11.0 prep commit and asserted it was the shape to copy, and the
0.17.0 prep found it five releases stale (`sb-0id2`). Nothing below needs
editing at a release, and a release commit does not touch this file - the
table at the end lists every file it does touch, and this is not one of them.

Commits cited further down are historical evidence for a claim about the past
("this happened once, in that commit"). They are not the reference, and they
stay correct as releases accumulate.

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

The test named `"compiler_version is this package's version"` in
`test/statifier_blocks/compiler_test.exs` asserts
`Compiler.compiler_version() == Mix.Project.config()[:version]`, so the two
cannot drift silently: a `mix.exs` bump on its own takes the gate red rather
than shipping a record stamped with the previous version. Find it with
`grep -n 'compiler_version is this package' test/statifier_blocks/compiler_test.exs`
rather than by a line number, which rots on the next edit above it. That
assertion is the check, not a substitute for doing this step.

Nothing else in `compiler.ex` changes. The comment above the attribute already
explains why it exists; the release moves the string.

## Step B: promote the changelog fragments

Placed where the skill's changelog step would have been, and modeled on the
reference prep commit above.

1. Read every `changelog.d/*.md` fragment except `README.md`. Each is a Keep a
   Changelog section heading followed by its bullets.
2. Insert a new `## [X.Y.Z] YYYY-MM-DD` section into `CHANGELOG.md` directly
   above the previous version's section, dated today. The heading form is the
   one the file already uses - the bracketed version and the date, with no
   separator between them.
3. Under the heading, write a short lead paragraph saying what the release is,
   then the fragments' bullets grouped by heading and ordered `Added`,
   `Changed`, `Deprecated`, `Removed`, `Fixed`, `Security`.

   Within one heading, when more than one fragment contributed bullets to it,
   the fragments go in **fragment-name order** - `changelog.d/sb-0l36.md`
   before `changelog.d/sb-4r1p.md` - and each fragment's own bullets keep the
   order they have in their file. That is an arbitrary but stable rule, and
   stable is the point: it is not a judgement about which change matters
   most, so no release worker has to make one. The 0.17.0 prep is the first
   one that had to choose (six fragments, three headings) and it chose this;
   `changelog.d/README.md` states the same rule from the other side.

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

`release.readme_pin` is `true`, and the skill's own step covers this repo's
pin without help: `README.md` carries a `{:statifier_blocks, "~> X.Y"}` pin in
its `def deps` snippet - exactly the major/minor form with the patch component
dropped that the skill bumps. It is named here only so that the carriers a
release moves are all listed in one place.

The pin's current value is not written down here, for the same reason no
version is written down anywhere else in this file. Read it and check it
against the version file instead:

```bash
grep 'statifier_blocks, "~>' README.md   # the pin
grep '@version "' mix.exs                # the version it should track
```

They should agree on major and minor. If they ever do not, the pin edit
repairs the drift in one move rather than stepping one release at a time: it
goes straight to the current major/minor, and that is the recipe working, not
a mistake to correct back.

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
