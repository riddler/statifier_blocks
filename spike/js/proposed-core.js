/*
 * spike/js/proposed-core.js - core block types that DO NOT EXIST YET.
 *
 * PROPOSED VOCABULARY. Nothing in this file is transcribed from
 * `lib/statifier_blocks/core/*.ex`, because nothing in this file has a module
 * there. These are descriptors written to find out what a `core.*` type would
 * have to declare if the package grew one, and the spike registers them the
 * same way a host registers its own - through the caller-supplied registry
 * value ADR-0002 decision 2 already provides.
 *
 * ## Why this is a separate file and not a `proposedCoreTypes` map in palette.js
 *
 * `palette.js` opens by saying what it IS: a hand transcription of the
 * shipped core vocabulary, "so the spike's palette browser and config forms
 * are looking at the real vocabulary rather than at an invented one". A map
 * of invented types living in that file - however loudly headed - costs it
 * exactly the property that makes it worth reading. `demo-types.js` was
 * split out of `palette.js` for the same reason one campaign earlier, and
 * this file follows that precedent rather than inventing a second one. The
 * mirror stays a mirror; the proposals sit beside it.
 *
 * The cost is duplicated shared predicates (`IDENTIFIER` and friends below).
 * `demo-types.js` pays the same cost and it is the cheaper of the two
 * mistakes: exporting palette.js's private predicates would make the mirror
 * a utility module as well as a mirror.
 *
 * ## What is proposed here, and what would have to be decided
 *
 * Whether any of this earns an ADR-0002/0004 amendment is a Phase-B finding.
 * The specific open questions each type raises are flagged at that type.
 */

/* ------------------------------------------------------- shared checks
 *
 * The same predicates `palette.js` and `demo-types.js` each keep privately.
 * `INVOKE_TYPE` is deliberately GENERIC - `namespace:name`, any namespace -
 * where `demo-types.js` hard-codes `^myapp:`. A core type may not know the
 * demo host's namespace; only the demo documents use `myapp:*`.
 */
const IDENTIFIER = /^[a-z][a-z0-9_]*$/;
const INVOKE_TYPE = /^[a-z][a-z0-9_]*:[a-z][a-z0-9_]*$/;
/* Verbatim `StatifierBlocks.Core.Config`'s spelling, the same one `palette.js`
 * keeps for `core.on_event`. A raised event and a caught one have to be the
 * same grammar or the rail catches nothing, and two regexes are two chances
 * for them to drift. */
const EVENT_NAME = /^[A-Za-z_][A-Za-z0-9_.\-]*$/;

/* One `name=path` pair, with whitespace around either side tolerated. The
 * name is an identifier; the path is any non-empty run of non-whitespace,
 * because this file does not own the datamodel path grammar and guessing at
 * it here would be a second, quieter proposal. */
const PARAM_LINE = /^\s*([a-z][a-z0-9_]*)\s*=\s*(\S+)\s*$/;

const nonEmptyString = (value) => typeof value === "string" && value !== "";
const isIdentifier = (value) => nonEmptyString(value) && IDENTIFIER.test(value);
const isInvokeType = (value) => nonEmptyString(value) && INVOKE_TYPE.test(value);
const isEventName = (value) => nonEmptyString(value) && EVENT_NAME.test(value);
const verdict = (findings) => (findings.length === 0 ? null : findings);

/**
 * The non-blank lines of a `params` block, in order. Blank lines are ignored
 * rather than refused: an author who leaves a trailing newline in a textarea
 * has not made an error, and a validator that says otherwise trains people to
 * stop reading it.
 */
export function paramLines(value) {
  if (typeof value !== "string") return [];
  return value.split("\n").filter((line) => line.trim() !== "");
}

/**
 * `params` parsed into `{ name, path }` pairs, or the ordered list of the
 * lines that did not parse. Exported because `dev/selftest.html` checks the
 * parse directly - the string field is a spike compromise (see below) and the
 * shape it stands in for is the part worth pinning down.
 */
export function parseParams(value) {
  const ok = [];
  const bad = [];

  for (const line of paramLines(value)) {
    const match = PARAM_LINE.exec(line);
    if (match) ok.push({ name: match[1], path: match[2] });
    else bad.push(line.trim());
  }

  return { params: ok, malformed: bad };
}

/* ----------------------------------------------------------- core.invoke
 *
 * A step that calls the host and waits for it to answer, with an optional
 * subtree for the failure case.
 *
 * ## The on_error SLOT, and why it is not a port
 *
 * RULED 2026-08-28 (operator; umbrella `docs/decisions.md` D13): an outcome
 * path is a SLOT, never a port. This is decided, not recommended. The tree
 * invariant the whole editor rests on - connectors are RENDERED, never
 * authored - survives only if every edge in a document is a parent/slot/child
 * relationship, and a port-shaped alternative would have made the failure
 * edge the one thing an author draws by hand.
 *
 * The slot declaration itself needs no new machinery: `zero_or_one` arity and
 * a rail slot style are exactly what `core.group`'s `interrupts` rail already
 * declares, and the renderer reads both off ADR-0005 decision 10's metadata
 * without learning a type name. What it did need, once both were drawn, was a
 * second rail VOCABULARY - see the `slotStyle` note below.
 *
 * ## What this would compile to (Phase B; nothing here compiles anything)
 *
 *   - the block emits an `<invoke>` whose `type` is `invoke_type`, resolved
 *     through the per-session registry statifier-ex ADR-0051 defines. A block
 *     type NAMES an invoke type; it never runs one (ADR-0002's two-registry
 *     seam);
 *   - `assign_to`, when set, is where the invoke's result lands in the
 *     datamodel;
 *   - the `on_error` subtree is the target of the transition on statifier-ex
 *     ADR-0068's `error.communication.invoke.<id>` event, with `<id>` the
 *     invoke's own id. An absent `on_error` means no such transition is
 *     emitted and the error propagates as it does today.
 *
 * None of that is settled. Whether it earns an ADR-0002/0004 amendment - and
 * how a two-outcome block reconciles with ADR-0004's single-final emission -
 * is a Phase-B finding.
 *
 * ## The params field is a spike compromise
 *
 * `params` is a plain `string`, one `name=path` pair per line, because
 * ADR-0002 decision 7's field types are a CLOSED set and none of them is "a
 * list of pairs". The honest options were to propose a new field type or to
 * flatten the pairs into text; the second one proves the block type's shape
 * without also proposing an editor feature. A structured param editor - a
 * `{ list: { record: ... } }` field type, or a dedicated control - is a
 * Phase-B question, and the shape it would carry is `parseParams` above.
 */
const coreInvoke = {
  name: "core.invoke",
  currentVersion: 1,
  slots: () => [{ name: "on_error", arity: "zero_or_one", label: "If it fails" }],
  configSchema: () => [
    {
      key: "invoke_type",
      type: "string",
      label: "Invoke type",
      required: true,
      default: "",
    },
    {
      key: "assign_to",
      type: "string",
      label: "Write the result to",
      required: false,
      default: "",
    },
    {
      key: "params",
      type: "string",
      label: "Params (one name=path per line)",
      required: false,
      default: "",
    },
  ],
  validateConfig: (config) => {
    const findings = [];

    if (!isInvokeType(config.invoke_type)) {
      findings.push({
        key: "invoke_type",
        message: 'must look like "namespace:name", such as "myapp:authorize"',
      });
    }

    /* Optional, so an absent key and an empty string are both fine; anything
     * present and non-empty has to be a bare identifier, because it names a
     * datamodel key the result is written to. */
    if (nonEmptyString(config.assign_to) && !isIdentifier(config.assign_to)) {
      findings.push({ key: "assign_to", message: "must be a bare lowercase identifier" });
    }

    if ("params" in config && typeof config.params !== "string") {
      findings.push({ key: "params", message: "must be text, one name=path pair per line" });
    } else {
      const { params, malformed } = parseParams(config.params);

      for (const line of malformed) {
        findings.push({ key: "params", message: `"${line}" is not a name=path pair` });
      }

      const seen = new Set();
      for (const { name } of params) {
        if (seen.has(name)) {
          findings.push({ key: "params", message: `two params cannot share the name "${name}"` });
        }
        seen.add(name);
      }
    }

    return verdict(findings);
  },
  /*
   * `produces: "unknown"` for the reason `core.branch` does (ADR-0003
   * decision 4 refuses to build a type lattice): a block with two outcomes
   * would otherwise have to join the type its own body produces with the type
   * its `on_error` subtree produces. `consumes` is absent - an invoke reads
   * its inputs through `params`, not through the type flow.
   */
  io: () => ({
    kinds: ["step"],
    produces: "unknown",
    slotAccepts: { on_error: ["step"] },
  }),
  paletteEntry: {
    label: "Invoke",
    group: "Proposed core",
    description: "Calls a host handler and waits for it to answer.",
    icon: "arrow-up-right",
    keywords: ["invoke", "call", "host", "service", "error"],
    order: 0,
    layout: "stack",
    /* The `interrupts` precedent for PLACEMENT: the failure path is a rail
     * beside the step, not a second body.
     *
     * PROPOSED slot-style value (sb-68b): `failure`, not `secondary`. Placed
     * like a `secondary` rail, painted in the error family and solid, because
     * an `on_error` subtree is an in-band continuation of a step that went
     * badly - not a rule that fires out of band at a region. Declared the same
     * way d10's two values are, so it costs a metadata value and no type
     * name. Widening d10's table to hold it is a Phase-B finding for the
     * record, not a decision taken here. */
    slotStyle: { on_error: "failure" },
    accentToken: "--sb-accent-invoke",
    /* PROPOSED metadata key (sb-p0k builds the renderer). A short chip on the
     * card header saying what a reader could not otherwise see: this step
     * leaves the chart. A string a block type declares, exactly as
     * `accentToken` is a token name it declares - the editor renders whatever
     * is there and never learns a type name. Whether it belongs in ADR-0005
     * decision 10's metadata is a Phase-B finding. */
    badge: "calls the host",
  },
};

/* ------------------------------------------------------------ core.raise
 *
 * A leaf step that raises one event, for an enclosing group's interrupt rail
 * to catch. The other half of a wiring the vocabulary could previously only
 * express half of: `core.on_event` has always been able to catch an event,
 * and nothing in a document could send one.
 *
 * ## Why this is a leaf, and why the edge is still not drawn
 *
 * A raise has no subtree and no outcome path: it names an event and hands
 * control on. It therefore declares no slots at all, exactly as `core.wait`
 * and `core.on_event` do - and the send -> catch relationship, the one edge a
 * reader most wants to see, is deliberately NOT an edge in the document. It
 * is two blocks naming the same string in two places, and the enclosing
 * group's rail is where the catch lives.
 *
 * That is the same D13 answer `core.invoke`'s `on_error` gets (operator,
 * 2026-08-28; umbrella `docs/decisions.md`), arrived at from the other side.
 * There an outcome path is a SLOT rather than a port; here a send is a NAME
 * rather than a port. Both refusals protect the one invariant the editor
 * rests on: every edge in a document is a parent/slot/child relationship, so
 * connectors are rendered and never authored. A `core.raise` with a port
 * pointing at the handler it wakes would have been the first hand-drawn edge,
 * and it would have been a cross-subtree one at that.
 *
 * What a reader loses is real - `signup.abandoned` in two cards is a weaker
 * cue than a line - and buying it back is a RENDERING question (highlight the
 * rail when a raise of its event is selected), not a document-shape one.
 * Whether the spike's canvas should do that is a Phase-B finding.
 *
 * ## What this would compile to (Phase B; nothing here compiles anything)
 *
 *   - the block emits a `<raise event="...">` in the onentry of the state it
 *     compiles into: an INTERNAL event, delivered to the same session, which
 *     is what makes an enclosing group's transition the thing that sees it.
 *     `core.wait`'s badge already says the neighbouring fact about that
 *     vocabulary - a wait is a delayed send rather than a sleep;
 *   - an event no enclosing rail catches is not an error. It is raised, no
 *     transition is enabled by it, and the chart carries on. A document-level
 *     finding ("nothing catches signup.abandoned") is an editor affordance
 *     worth having and is not this descriptor's job.
 *
 * Whether `<raise>` or a zero-delay `<send>` is the right emission, and
 * whether a raise should be able to carry a payload the handler reads through
 * `event.*`, are both open. The datamodel fixture already declares payload
 * fields for `signup.abandoned`, so the second question has a shape; a
 * `payload` config field would need ADR-0002 decision 7's closed field-type
 * set to grow, or the same flattening compromise `params` makes above. Left
 * out on purpose rather than guessed at.
 */
const coreRaise = {
  name: "core.raise",
  currentVersion: 1,
  slots: () => [],
  configSchema: () => [
    {
      key: "event",
      type: "string",
      label: "Raise this event",
      required: true,
      default: "",
    },
  ],
  validateConfig: (config) =>
    isEventName(config.event)
      ? null
      : [{ key: "event", message: "must be an event name, like signup.abandoned" }],
  /*
   * A step, and nothing more. `produces` is absent rather than `"unknown"`:
   * a raise has one outcome, so there is no join to refuse (the reason
   * `core.invoke` and `core.branch` both say `"unknown"`), and `core.wait` -
   * the other single-outcome leaf - declares its io exactly this way.
   */
  io: () => ({ kinds: ["step"] }),
  paletteEntry: {
    label: "Raise",
    group: "Proposed core",
    description: "Raises an event for an enclosing group's interrupt rules.",
    /* One of `render.js`'s existing glyph names. `myapp.notify` uses it too,
     * which is a legible collision - both announce something - and minting a
     * new one would mean editing the renderer's icon set for a proposal. */
    icon: "megaphone",
    keywords: ["raise", "event", "send", "signal", "interrupt", "abandon"],
    order: 1,
    /* PROPOSED, like the key itself. The one thing a reader cannot get from
     * "Raise signup.abandoned": that the event goes to this chart's own
     * handlers rather than out to the host. Under `badgeFor`'s 24-character
     * cap with room to spare. */
    badge: "raises",
    /* No `accentToken`, deliberately, and the omission is the argument.
     * `core.invoke` claims one because its work happens OUTSIDE the chart -
     * that is what `tokens.css` says the teal is for. A raise is the
     * opposite: it is the most inside-the-chart step there is, so it takes
     * the editor's own accent like every other core step. Declaring a second
     * proposed token here would also have meant a theme change in three
     * files for a type whose whole point is that it is ordinary.
     */
  },
};

/* -------------------------------------------------------------- the value */

/**
 * The proposed `core.*` entries, keyed by type name.
 *
 * Deliberately NOT merged into `palette.js`'s `coreTypes`, and deliberately
 * not reachable from `coreRegistry()` or `spikeRegistry()`: those two answer
 * "what does the package actually ship", and a proposal that quietly joined
 * them would make that question unanswerable. `shell.js` spreads this map
 * into the registry it builds, beside the other three.
 */
export const proposedCoreTypes = {
  "core.invoke": coreInvoke,
  "core.raise": coreRaise,
};
