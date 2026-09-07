# Quality configuration for statifier_blocks.
#
#   mix quality                 - full gate: format, compile, credo, dialyzer,
#                                 deps audit, full test suite with coverage.
#                                 Run before every commit.
#
#   mix quality --profile loop  - inner loop while implementing: skips dialyzer
#                                 and coverage, runs only the tests covering
#                                 changed code. Use between edits.
#
# Agents: prefer `--format json --report -` when you want to route on results.
#
# Deliberately smaller than statifier-ex's gate. That repo's custom stages -
# the gate guard, the ADR guard and judge, the regression ratchet - all exist
# to protect a conformance corpus and an accepted ADR set this package does
# not have. Adopting any of them here is a decision to record when there is
# something for it to protect, not a default to inherit.
#
# There is deliberately no .credo.exs either: credo's own defaults under
# --strict are the gate until this package has a reason to deviate from one.
#
# Recorded deviation from the satellite shape - coveralls.json carries
# "treat_no_relevant_lines_as_covered": true on top of the shared
# minimum_coverage: 90. The satellites do not need it because they all have
# executable code; this package is currently a moduledoc-only scaffold, so
# excoveralls sees zero relevant lines and, by default, reports that as 0.0%
# rather than "nothing to cover" - which would fail the 90% bar with no way
# to fix it short of lowering the bar. The flag keeps the threshold at the
# fleet's 90% and only changes the empty-file case. Drop it once the package
# has real code if the fleet prefers strict parity.

[
  format: [
    check: true
  ],
  compile: [
    warnings_as_errors: true
  ],
  credo: [
    strict: true
  ],
  profiles: [
    loop: [
      stages: [:format, :compile, :credo, :test],
      test: [scope: :changed, coverage: false]
    ]
  ],

  # The first custom stage this package has taken, and the exception the header
  # above describes rather than a change of mind about inheriting statifier-ex's
  # gate: there is now something for it to protect. The records cite each other
  # by line number, and nothing else in the gate can tell that an insert in one
  # record has moved a line another record points at. `mix adr.cites` resolves
  # every such citation against a recorded baseline and fails when the cited
  # text has changed underneath it; the module doc says how, and what it warns
  # about rather than failing. It reads `docs/adr/` and nothing else, so it is a
  # reader, and it is absent from the loop profile's `stages:` allow-list, which
  # makes it a pre-commit concern rather than an every-edit one.
  custom: [
    [
      key: :adr_cites,
      name: "ADR cites",
      command: "mix",
      args: ["adr.cites", "--format", "json"],
      kind: :reader
    ]
  ]
]
