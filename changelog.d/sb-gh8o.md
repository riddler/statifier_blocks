<!-- Keep this fragment: it is a documentation addendum to the 0.22.0 Notes, promoted into the 0.23.0 section under the SF035 walk's ruling RQ-SF035-13, which overrides this directory's README rule that documentation gets no fragment. -->

### Added

- A worked example of the failure propagation 0.22.0 introduced, which the
  0.22.0 Notes stated as a rule without showing a run. A `core.sequence` body
  holds a `myapp:authorize` invoke followed by a `myapp:capture` invoke, and
  authorize ends on its `error` outcome. With the authorize invoke's own
  `on_error` slot filled - handling is declared by the failing block, never by
  the sequence around it - the slot's child runs, the invoke ends on `error`,
  the sequence advances, and the run ends at the document's ordinary completion
  final with capture having run. With `on_error` empty and the document
  compiled under `child_use: true` or `terminate: true`, the invoke's `error`
  final is emitted anyway, the root's transition on
  `done.outcome.<authorize state id>.error` is selected before the sequence's
  own `done.state`, and the run ends at the shared top-level failed final
  carrying the reserved `statifier_persistence:run_status` param with the value
  `failed` - capture never runs. Compiled under neither option there is no root
  catch, nothing selects the outcome event, and the sequence advances to
  capture exactly as it does on success. ADR-0002's amendment of 2026-09-06,
  section 4 ("The nested-to-root propagation rule") and section 6 ("What this
  costs a host, and what it does not"), carry the full walk-through.
