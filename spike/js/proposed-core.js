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
 * Seven descriptors now, grouped by the shape they take rather than by the
 * order they appear in below:
 *
 *   - LEAVES, no slots at all: `core.raise` names one internal event and hands
 *     control on; `core.assign` writes one literal to one datamodel path;
 *     `core.send` names an event and says WHEN - now, or after a delay.
 *   - STEPS WITH A FAILURE PATH: `core.invoke` calls the host and waits;
 *     `core.subchart` runs another chart and waits. Both declare the same
 *     `on_error` slot, character for character, because a host call that fails
 *     and a child chart that fails are the same shape of thing to an author.
 *   - A CONTAINER: `core.foreach` runs its one `body` slot once per item of a
 *     datamodel list.
 *   - A RAIL RULE: `core.timeout` fires on the clock rather than on an event,
 *     which is the half of `core.on_event`'s pair the vocabulary was missing.
 *
 * File order is NOT that order, and four of the descriptors say so where they
 * sit: `core.timeout`, `core.assign`, `core.send` and `core.foreach` each
 * carry an APPENDED BY note, because each landed while a sibling bead was
 * writing into this same file, and a pure append at the end of the file and of
 * the map is the only edit two writers can make to one file without meeting in
 * the middle. Placement is a merge courtesy; if this file is ever tidied, the
 * grouping above is the reading order it wants.
 *
 * Every one of them carries a COMPILE SKETCH rather than a compiler: what the
 * block would emit, which upstream record owns the part this repo does not,
 * and what is still open. Nothing in this file compiles anything, and the
 * sketches are written so that the gap is visible instead of assumed.
 *
 * Whether any of this earns an ADR-0002/0004 amendment is a Phase-B finding.
 * The specific open questions each type raises are flagged at that type.
 *
 * ## No type here declares `label`, and that is now correct
 *
 * It used to be a gap: `card-processing.json` stores a label on both of its
 * `core.invoke` blocks, the canvas titled the cards from it, and the config
 * form could not edit it, because a schema field keyed `label` was something
 * each type had to remember to declare. The editor injects that field now
 * (`withEditorFields` in palette.js), so the proposals here declare only
 * what their own work needs - which is what made the gap visible in the
 * first place and is the argument sb-jvz was decided on.
 */

import { fixtureDocumentIds, fixtureDocumentOptions } from "./fixture-documents.js";

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

const nonEmptyString = (value) => typeof value === "string" && value !== "";
const isIdentifier = (value) => nonEmptyString(value) && IDENTIFIER.test(value);
const isInvokeType = (value) => nonEmptyString(value) && INVOKE_TYPE.test(value);
const isEventName = (value) => nonEmptyString(value) && EVENT_NAME.test(value);
const verdict = (findings) => (findings.length === 0 ? null : findings);

/* --------------------------------------------------------------- params
 *
 * ## The storage shape (sb-e2x): a MAP, not text
 *
 * `params` used to be a plain `string`, one `name=path` pair per line, and
 * this file called that a compromise in so many words: ADR-0002 decision 7's
 * field types are a closed set and none of them is "a list of pairs". The
 * compromise is gone, and it is gone from the STORED BYTES rather than hidden
 * behind a nicer control:
 *
 *     "params": { "amount": "amount_cents", "currency": "currency" }
 *
 * Two principles decided it, in this order.
 *
 * ONE HOME FOR ONE FACT. A param binding is two facts - a name the host
 * handler receives, and a datamodel path the value is read from. In the text
 * form neither has a home: they live inside a line, inside a newline-joined
 * blob, in a micro-format no record defines, and every reader that wants
 * either one - `validate_config/1`, the document-level declaration pass, the
 * compile sketch, and one day a compiler - has to re-derive it by parsing.
 * Four parsers of an undocumented format is four chances to disagree about
 * what a document says. As a map each fact has a JSON address, and ADR-0002's
 * `value_path` amendment already gives the editor the vocabulary to point at
 * one (`["params", "amount"]`).
 *
 * THE HONEST REPLAYER. The spike's documents are meant to be what a host
 * would really store. A structured editor over a flattened text field would
 * show an author rows while storing prose, and the parse/serialize layer
 * between the two is exactly where a spike stops being evidence: line order,
 * blank lines, padding whitespace and duplicate names all survive in the
 * stored bytes but not in the control, so the round trip is lossy in the
 * direction that matters (what the author sees is not what the document
 * holds). Removing the compromise means removing it from storage.
 *
 * WHAT THE MAP BOUGHT, beyond the two principles:
 *
 *   - duplicate names are structurally impossible, so the "two params cannot
 *     share the name" finding is deleted rather than reworded - the shape
 *     enforces what the validator used to have to say;
 *   - ADR-0001 decision 8 sorts object keys, so a document's identity stops
 *     depending on the order an author happened to type the lines in. Two
 *     documents that bind the same params are now byte-identical;
 *   - ADR-0001 decision 6 is untouched: keys and values are strings, and
 *     nothing here is a float.
 *
 * WHAT IT COST, paid rather than dodged: a document migration. Both shipped
 * fixture documents were rewritten by hand (five `params` values), along with
 * the selftest's assertions about them. `fixtures/runs.json` carries no
 * `params` and needed no change. That is the whole bill, and it is the reason
 * to pay it now rather than after a host has stored any.
 *
 * WHAT ORDER STOPPED BEING. A map has no row order, so the control has no
 * "move row up" gesture and the rows render in key order. That is a real loss
 * against the text field and it is the right one: nothing downstream reads
 * params positionally (a handler receives them by name), so row order was a
 * fact the document was storing on the author's behalf without anyone needing
 * it - and storing it is what made two equivalent documents hash differently.
 */

/* The path grammar this file is willing to assert: non-empty, no whitespace.
 * Deliberately not tighter - this file does not own the datamodel path
 * grammar, and guessing at it here would be a second, quieter proposal. The
 * same latitude the `name=path` line took for its right-hand side. */
const isPathish = (value) =>
  typeof value === "string" && value.trim() !== "" && !/\s/.test(value.trim());

const isConfigMap = (value) =>
  value !== null && typeof value === "object" && !Array.isArray(value);

/**
 * `params` as `{ name, path }` rows, in key order. Exported because
 * `dev/selftest.html` checks the derivation directly and because the compile
 * sketches below describe what a row becomes.
 *
 * Key order, not insertion order, and the two agree with ADR-0001 decision
 * 8's canonical key sort: the key grammar is `[a-z][a-z0-9_]*`, so every
 * well-formed key is ASCII and a code-unit sort IS a UTF-8 byte sort. A row
 * whose key is mid-edit and not yet an identifier still sorts deterministically
 * - it just may not sort where its bytes eventually will, which is a redraw an
 * author sees on blur rather than a difference in what is stored.
 */
export function paramRows(value) {
  if (!isConfigMap(value)) return [];

  return Object.keys(value)
    .sort()
    .map((name) => ({ name, path: value[name] }));
}

/*
 * The two config checks `core.invoke` and `core.subchart` share, written once.
 *
 * Not a general utility and not exported as one: they exist because the two
 * types make the SAME proposal - the `params` map above, and an optional
 * `assign_to` naming where the outcome lands - and a second spelling of either
 * would be two chances for the proposal to drift from itself inside one file.
 * The shared predicates this file duplicates from `palette.js` are a different
 * case and the header says why.
 *
 * Every row finding carries `row`, the map key it is about, beside the `key`
 * ADR-0005 decision 11's anchor already carries. That is a PROPOSED widening
 * of the finding shape and it is flagged as one at the field declaration; a
 * reader that ignores `row` gets today's behaviour exactly - the message under
 * the field - which is why the messages name their row in words as well.
 */
function paramFindings(config) {
  if (config.params === undefined) return [];

  if (!isConfigMap(config.params)) {
    return [{ key: "params", message: "must be a map of names to datamodel paths" }];
  }

  const findings = [];

  for (const { name, path } of paramRows(config.params)) {
    if (name !== "" && !isIdentifier(name)) {
      findings.push({
        key: "params",
        row: name,
        message: `"${name}" is not a name: use lowercase letters, digits and underscores, starting with a letter`,
      });
    }

    if (isBlank(path)) continue;

    if (!isPathish(path)) {
      findings.push({
        key: "params",
        row: name,
        message: `${name === "" ? "the unnamed row" : `"${name}"`} needs a datamodel path, like signup.email`,
      });
    }
  }

  return findings;
}

const isBlank = (value) => value === undefined || value === null || value === "";

/*
 * ## Why the HALF-WRITTEN row is silent, and why that is a gate consequence
 * rather than a taste
 *
 * A row with no name yet, and a named row with no path yet, produce no
 * finding. That is not leniency, it is the only shape that leaves the control
 * usable, and finding out why is what this bead's verify pass was for.
 *
 * ADR-0005 decision 9's gate is absolute: an `update_config` reaches the
 * document ONLY when `validate_config/1` returns ok (`checkConfig` in
 * `edit.js`). So a finding about a row is not a message beside a row - it is a
 * REFUSAL of the whole edit that contains it. "Add row" creates an unnamed row;
 * if an unnamed row is a finding, the add is refused and the row can never come
 * into existence. Naming it is the next edit; if a named row with no path yet
 * is a finding, that one is refused too. A validator that spoke at either
 * moment would have made a control that cannot be used at all - which is
 * exactly what the first cut of this control did, and what a browserless
 * gesture check caught.
 *
 * The precedent is already in this file and in sb-c2o's pass, for the same
 * reason in different words: an empty `assign_to` is silent, and the
 * declaration check stays silent on an empty value because "the type's own
 * error already says the field is unfinished". Here the row itself is the
 * thing that says so - an empty box in front of the author's cursor - and a
 * refusal is the least useful possible way to repeat it.
 *
 * What stays checked is every part an author has actually written: a name that
 * is not an identifier, and a path that is not a path. Those are wrong rather
 * than unfinished, and refusing them is decision 9 working as intended.
 *
 * NAMED, NOT BUILT: nothing yet says "this row is unfinished and will bind
 * nothing" at the moment it stops being in progress - the document-level pass
 * is where such a warning could live, since a warning there is not a refusal,
 * and `layout.js` already walks every annotated field. Whether an unfinished
 * row is worth a warning, and what a compiler does with one, are Phase-B
 * questions this file does not answer.
 */

/*
 * The `params` field declaration, written once and shared by both types that
 * make the proposal, for the same one-spelling reason `paramFindings` is
 * shared. A function rather than a constant because `configSchema/1` is called
 * per render and a shared mutable `default` would be one object every form
 * points at.
 *
 * ## PROPOSED FIELD TYPE (sb-e2x): `{ map: <member of the closed set> }`
 *
 * FLAGGED DIVERGENCE, in the idiom the rest of this file uses for a proposed
 * key: ADR-0002 decision 7's field-type set is CLOSED, and this is a new
 * member of it. Nothing here amends the record - whether the set widens is an
 * operator's call on a Phase-B finding, and this file is the evidence for it,
 * not the decision.
 *
 * The shape is deliberately `{ list: T }`'s, one word over: a container type
 * parameterised by a member of the closed set, so the editor's control mapping
 * stays total and a host declaring one gets a control the editor can already
 * draw. Keys are strings (ADR-0001 decision 6 says config keys are), and this
 * type's key grammar is the identifier grammar - which is a rule
 * `validate_config/1` states and the schema only hints at, exactly as decision
 * 7 asks.
 *
 * What is NOT proposed here is a `datamodel_path` field type. sb-c2o already
 * settled that question the other way: the fact "this string names a datamodel
 * path" is an ANNOTATION beside the type, and `datamodelPath: "reads"` below is
 * that same annotation reading the map's VALUES rather than a bare string. A
 * host type that wants the declaration warning on its own map field gets it by
 * declaring the annotation, and `layout.js` still never learns a type name.
 *
 * `keyLabel` and `valueLabel` are the third proposed key, and the smallest one:
 * a two-column row control has two column headings, and "Name"/"Datamodel path"
 * are facts about this field that only this field knows. Absent, the control
 * falls back to "Key"/"Value".
 */
const paramsField = () => ({
  key: "params",
  type: { map: "string" },
  label: "Params",
  required: false,
  default: {},
  keyLabel: "Name",
  valueLabel: "Datamodel path",
  /* sb-c2o's annotation, applied per map VALUE: a params path is a path this
   * block READS, so an undeclared one warns with the "read a path it already
   * declares" ending rather than the "write it somewhere else" one. */
  datamodelPath: "reads",
});

/*
 * Optional, so an absent key and an empty string are both fine; anything
 * present and non-empty has to be a bare identifier, because it names a
 * datamodel key the result is written to.
 *
 * What this deliberately does NOT check is whether that key is DECLARED in the
 * datamodel document. sb-ig4 found `assign_to: "authorization"` writing to a
 * path `fixtures/datamodel.json` never declares, and sb-c2o answered it: a
 * WARNING finding rather than a refusal, so authoring stays fluid, made at
 * document level in `layout.js` where the datamodel index is in reach.
 * `validate_config/1` is still handed a config and still cannot make it - what
 * changed is that the field now SAYS it holds a datamodel path
 * (`datamodelPath: "writes"` in the schema below), and the document-level pass
 * reads that declaration rather than a type name.
 */
function assignToFindings(config) {
  return nonEmptyString(config.assign_to) && !isIdentifier(config.assign_to)
    ? [{ key: "assign_to", message: "must be a bare lowercase identifier" }]
    : [];
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
 * ## The params field
 *
 * A map of name to datamodel path, edited as key/path rows. The text-field
 * compromise this section used to describe is gone, in the bytes as well as in
 * the control; the reasoning, the migration it cost and the field type it
 * proposes are all in the `params` section above, which both types share.
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
      /* sb-c2o: the field says of itself that its value is a datamodel path,
       * and the document-level pass in `layout.js` warns when the datamodel
       * does not declare it. An ANNOTATION beside `type`, not a new decision-7
       * field type: the type set is closed, and what a reader needs here is one
       * fact about the string, not a new control. */
      datamodelPath: "writes",
    },
    paramsField(),
  ],
  validateConfig: (config) => {
    const findings = [];

    if (!isInvokeType(config.invoke_type)) {
      findings.push({
        key: "invoke_type",
        message: 'must look like "namespace:name", such as "myapp:authorize"',
      });
    }

    findings.push(...assignToFindings(config), ...paramFindings(config));

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
 * set to grow. `params` above now proposes one such widening and says what it
 * cost; a second widening proposed here, for a payload nothing has asked this
 * type to carry, would be guessing rather than evidence. Left out on purpose.
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

/* --------------------------------------------------------- core.subchart
 *
 * A step that runs ANOTHER chart and waits for it to finish, with the same
 * optional failure subtree `core.invoke` has.
 *
 * ## Why this is a leaf, and why the child is a REFERENCE
 *
 * The obvious alternative - a `chart` slot holding the child's blocks inline -
 * was not on the table. A document is a tree and a chart is a build product of
 * one (`CLAUDE.md`'s first bullet); a subchart whose body lived inside the
 * parent would be a second copy of a document that already exists on its own,
 * with its own id, its own revision and its own runs. So the child is named,
 * not embedded, and this type declares no body slot at all.
 *
 * That makes the reference the whole design question, and D11 answers the
 * spike's half of it: the picker offers ONLY the spike's own fixture
 * documents, derived from `fixture-documents.js` rather than typed in here, so
 * a reference cannot name a chart the shell could not open. What it stores is
 * the child document's id.
 *
 * ## The on_error slot is `core.invoke`'s, deliberately unchanged
 *
 * Same declaration, same arity, same `failure` slot style (sb-68b), same D13
 * reason: an outcome path is a SLOT, never a port. A child chart that fails is
 * the same shape of event as a host call that fails - the step went badly and
 * the author wants somewhere to say what happens next - and giving it a second
 * spelling would have been a vocabulary an author has to learn twice.
 *
 * ## Two questions this type raises and does not answer
 *
 *   - a child chart has MORE than two outcomes in general. It can finish in
 *     any of its final states, and "done / error" flattens that to the two
 *     `core.invoke` already has. Whether a subchart should be able to declare
 *     a slot per named child outcome - and what names those would be, given
 *     ADR-0004's single-final emission - is open, and it is the open question
 *     this bead's note records rather than settles;
 *   - nothing here refuses a reference to the document the block itself sits
 *     in. `validate_config/1` is handed a config, not a document, so a
 *     self-reference (and a cycle through two documents) is a DOCUMENT-level
 *     finding, the same shape of check sb-c2o describes for `assign_to`. Named
 *     here so the gap is on the record rather than discovered by a reader.
 *
 * ## What this would compile to (SKETCH ONLY - nothing here compiles anything)
 *
 * This is the bead's compile-mapping sketch, and it is a sketch on purpose:
 * every clause below names an upstream record and none of it is built.
 *
 *   - the block emits an `<invoke>` whose type is the child-chart invoke type
 *     the host registers, resolved through the per-session registry
 *     statifier-ex ADR-0051 defines - the same seam `core.invoke` uses, and
 *     for the same reason: a block type NAMES an invocable thing and never
 *     runs one. A subchart is not a new execution mechanism, it is a
 *     particular invoke whose handler happens to start a child session;
 *   - `chart` identifies WHICH chart, and identity is statifier-ex's
 *     (ADR-0052 chart identity and position serialization, ADR-0057). The
 *     spike stores a block-document id because that is the only identity it
 *     has; a compiler would have to emit the chart identity that record
 *     defines, and a persisted parent position is meaningful only against the
 *     exact child revision it ran - which is the same rule a provenance map
 *     already lives under (ADR-0004);
 *   - `params` are the child session's initial datamodel writes and
 *     `assign_to` is where the child's outcome lands in the parent's, exactly
 *     as for an invoke;
 *   - the `on_error` subtree is the target of the transition on
 *     ADR-0068's `error.communication.invoke.<id>` event, `<id>` being this
 *     block's own. An absent `on_error` means no such transition is emitted.
 *
 * OPEN, and the reason nothing above is more than a sketch: how a child
 * chart's outcomes reach the parent's slots. An invoke answers once, with one
 * result; a chart finishes in one of several final states, and the mapping
 * from "which final state" to "which slot" is not something ADR-0051's invoke
 * contract or ADR-0004's single-final emission decides today. Until it is
 * decided upstream, a subchart has the two outcomes an invoke has, and this
 * file says so rather than inventing a third.
 */
const coreSubchart = {
  name: "core.subchart",
  currentVersion: 1,
  /* `core.invoke`'s declaration, character for character. The failure path is
   * the same path; a second wording would read as a second concept. */
  slots: () => [{ name: "on_error", arity: "zero_or_one", label: "If it fails" }],
  configSchema: () => [
    {
      /* ADR-0002 decision 7's `{ select: [...] }`, built from
       * `fixture-documents.js` at call time rather than captured at module
       * load: the schema is a function so that it can be, and a picker whose
       * options were frozen at import would go stale the moment the list did.
       *
       * The default is "" rather than the first document. A subchart with no
       * chart chosen is an unfinished block and should read as one; defaulting
       * to whichever fixture happens to be listed first would author a
       * reference nobody chose. `required: true` and the finding below are
       * what say so. */
      key: "chart",
      type: { select: fixtureDocumentOptions() },
      label: "Run this chart",
      required: true,
      default: "",
    },
    {
      key: "assign_to",
      type: "string",
      label: "Write the outcome to",
      required: false,
      default: "",
      /* sb-c2o, `core.invoke`'s annotation for `core.invoke`'s reason. The
       * shipped signup-invitations document writes to `onboarding`, which
       * `fixtures/datamodel.json` deliberately does not declare (sb-7s2) - so
       * the demo carries one honest warning rather than a clean board. */
      datamodelPath: "writes",
    },
    /* `core.invoke`'s declaration, because it is literally the same one. sb-7s2
     * wrote this field as the existing idiom rather than a second one so that
     * sb-e2x would have one thing to convert, and it did: the two types moved
     * together, in one edit, with no type name anywhere in the control. */
    paramsField(),
  ],
  validateConfig: (config) => {
    const findings = [];

    if (!fixtureDocumentIds().includes(config.chart)) {
      findings.push({
        key: "chart",
        message: "pick one of the spike's fixture documents",
      });
    }

    findings.push(...assignToFindings(config), ...paramFindings(config));

    return verdict(findings);
  },
  /*
   * `core.invoke`'s io exactly: a step with two outcomes, so `produces` is
   * `"unknown"` rather than a join of the body's type with the `on_error`
   * subtree's (ADR-0003 decision 4 refuses to build a type lattice), and no
   * `consumes` - a subchart reads its inputs through `params`.
   */
  io: () => ({
    kinds: ["step"],
    produces: "unknown",
    slotAccepts: { on_error: ["step"] },
  }),
  paletteEntry: {
    label: "Subchart",
    group: "Proposed core",
    description: "Runs another chart and waits for it to finish.",
    /* `core.group`'s glyph, and the collision is the point: a subchart is
     * another chart, so the boxes-in-a-box drawing is the right picture twice.
     * Minting a new glyph would have meant editing `render.js`'s icon set for
     * a proposal, which is the cost `core.raise` declined too. */
    icon: "rectangle-group",
    keywords: ["subchart", "child", "chart", "call", "compose", "error"],
    order: 2,
    layout: "stack",
    /* sb-68b's `failure` value, the same one `core.invoke` declares. */
    slotStyle: { on_error: "failure" },
    /* `tokens.css` says the teal is for the step whose work happens outside
     * this chart. A subchart's work happens in a different chart entirely, so
     * it is the same fact rather than a neighbouring one, and it takes the
     * same token rather than proposing a second one. */
    accentToken: "--sb-accent-invoke",
    /* The bead's badge, and short enough for `badgeFor`'s cap. What a reader
     * cannot get from the card's title: this step is a whole other chart. */
    badge: "subchart",
  },
};

/* ---------------------------------------------------------- core.timeout
 *
 * APPENDED BY sb-0o4, deliberately at the END of this file and of the map
 * below, because a sibling bead was editing the two descriptors above at the
 * same time. Placement is a merge courtesy and nothing more; if this file is
 * ever tidied, `core.timeout` belongs beside `core.raise` in reading order.
 *
 * An interrupt rule that fires once a duration has elapsed. The other half of
 * the pair `core.on_event` opens: that one catches an event, this one catches
 * the clock, and both sit on a group's `interrupts` rail and declare
 * `kinds: ["interrupt_handler"]` and nothing else. That single tag is the
 * whole placement rule in both directions, exactly as it is for
 * `core.on_event`; there is no placement check here and there is not supposed
 * to be one.
 *
 * ## Why the vocabulary needed it
 *
 * `core.wait` is a STEP inside a body: the chart sits at it and moves on when
 * the duration is up. "Interrupt this group after fifteen minutes, whatever it
 * is doing" is a different shape and no shipped `core.*` type expressed it, so
 * the demo documents grew `myapp.timeout_rule` to say it. That crutch is
 * retired (2026-08-28, umbrella D12) and this descriptor is what replaced it -
 * which is the whole argument for the type: the core form covers what the host
 * form was standing in for, key for key.
 *
 * ## Its config, and the one question it leaves open
 *
 *   - `after` is a `duration`, ADR-0002 decision 7's existing field type, so
 *     it gets the same ISO-8601 control `core.wait`'s duration does. The key
 *     is spelled `after` rather than `duration` because the two mean different
 *     things at the same block: a wait's duration is how long the step TAKES,
 *     a rule's `after` is when it FIRES. Whether the vocabulary should insist
 *     on one spelling across both is a Phase-B naming question, flagged and
 *     not decided;
 *   - the duration CONTROL question sb-d9's item raised stays open. This
 *     descriptor takes the control as it is and proposes nothing about it;
 *   - `cond` is the same optional guard `core.on_event` grew in sb-0o4, with
 *     the same `expression` type, the same "absent is silent, present must be
 *     an expression" rule, and for the same reason - so the condition pane
 *     picks it up without learning a type name;
 *   - `outcome` is `abandon` or `resume`, spelled exactly as `core.on_event`
 *     spells it. Two interrupt rules on one rail whose "Then" menus disagreed
 *     would be the drift this repeats itself to avoid.
 *
 * ## What this would compile to (Phase B; nothing here compiles anything)
 *
 * A delayed send on entry to the group plus a transition on its arrival -
 * which is what `core.wait`'s badge already says about the neighbouring
 * vocabulary, a wait being a delayed send rather than a sleep. Whether that
 * earns an ADR-0002/0004 amendment is a Phase-B finding, and so is what the
 * timer does when a `resume` outcome re-enters the group it just left.
 */

/* Verbatim `palette.js`'s spelling, for the reason `EVENT_NAME` above is
 * verbatim: a duration this file accepts and `core.wait` refuses would be two
 * controls disagreeing about the same string. BOTH spellings, since sb-709 -
 * the ISO-8601 form and predicator-ex's own `3d8h` literal, which the duration
 * control makes the primary way to type one. `palette.js`'s comment carries
 * the citation and the reason the predicator half is here at all. */
const DURATION = /^P(?!$)(\d+Y)?(\d+M)?(\d+W)?(\d+D)?(T(?!$)(\d+H)?(\d+M)?(\d+S)?)?$/;
const PREDICATOR_DURATION = /^(?:\d+(?:mo|[ydwhms]))+$/;
const isDuration = (value) =>
  nonEmptyString(value) && (DURATION.test(value) || PREDICATOR_DURATION.test(value));

const TIMEOUT_OUTCOMES = ["abandon", "resume"];

const coreTimeout = {
  name: "core.timeout",
  currentVersion: 1,
  slots: () => [],
  configSchema: () => [
    {
      key: "after",
      type: "duration",
      label: "After",
      required: true,
      default: "PT15M",
    },
    {
      key: "outcome",
      type: {
        select: [
          { value: "abandon", label: "Abandon - leave the group" },
          { value: "resume", label: "Resume - re-enter the group" },
        ],
      },
      label: "Then",
      required: true,
      default: "abandon",
    },
    {
      key: "cond",
      type: "expression",
      label: "Only when",
      required: false,
      default: "",
    },
  ],
  validateConfig: (config) => {
    const findings = [];

    if (!isDuration(config.after)) {
      findings.push({ key: "after", message: "must be an ISO-8601 duration, like PT15M" });
    }
    if (!TIMEOUT_OUTCOMES.includes(config.outcome)) {
      findings.push({ key: "outcome", message: 'pick "abandon" or "resume"' });
    }
    /* Absent is silent; present has to carry an expression. The same rule
     * `core.on_event`'s `cond` states, in the same words, on purpose. */
    if ("cond" in config && !nonEmptyString(config.cond)) {
      findings.push({ key: "cond", message: "a guard, if present, needs an expression" });
    }

    return verdict(findings);
  },
  io: () => ({ kinds: ["interrupt_handler"] }),
  paletteEntry: {
    label: "Timeout",
    group: "Proposed core",
    description: "Interrupts the group it sits in once a duration has elapsed.",
    /* One of `render.js`'s existing glyph names, the one the retired
     * `myapp.timeout_rule` used, so the rail looks the same to an author who
     * knew the demo before the crutch went away. */
    icon: "clock-alert",
    keywords: ["interrupt", "timeout", "deadline", "expire", "after"],
    order: 2,
    /* No `accentToken`, for `core.raise`'s reason: a timeout is an
     * inside-the-chart rule, not work that leaves it, so it takes the
     * editor's own accent like every other core type. */
  },
};

/* ----------------------------------------------------------- core.assign
 *
 * APPENDED BY sb-y4a at the END of this file and of the map below, for the
 * reason `core.timeout` says above: a sibling bead was appending its own
 * descriptor at the same time, and a pure append is what makes two of those
 * compose. Placement is a merge courtesy; in reading order this belongs beside
 * `core.raise`, with the other leaves.
 *
 * A leaf step that writes one literal to one datamodel path. The vocabulary
 * could read the datamodel from the day `core.branch` grew a `cond` and could
 * never write it: every value in either demo document arrives from a host call
 * (`assign_to`) or from an event payload, so a chart that wanted to record a
 * fact of its own - a flag it set, a counter it moved, a decision it made - had
 * nowhere to put it and no way to say it had.
 *
 * ## `value` is SOURCE TEXT, and that is the whole design
 *
 * `value` stores the literal as an author would type it: `false`, `42350`,
 * `"manual_review"` - quotes included for a string. That is not a shortcut
 * around ADR-0002 decision 7's closed field-type set, it is the same rule
 * `fixtures/runs.json` already holds every delta to ("every value is a STRING
 * of source text, never a live value"), and holding both to it is what makes
 * the replay claim below checkable: a run's delta on an assign step and the
 * block's own config are the same two strings, so the fixture can be compared
 * to the document character for character rather than by interpretation.
 *
 * A typed value - `{ literal: "boolean" }`, or a control that knows the
 * declared type of `path` - is the honest alternative and it is a Phase-B
 * question, not something this descriptor decides. It would need the field-type
 * set to grow, which is the same wall `params` hit - and which `params` now
 * proposes climbing, for a container shape a typed literal does not share.
 *
 * ## EXPRESSION support: a sketch, deliberately not built
 *
 * The obvious next `value` is an expression - `capture_attempts + 1`,
 * `amount_cents * merchant.settlement_fx_rate` - and the spike does not have
 * one. Not a gap left open by accident; three things would have to be decided
 * first, and none of them is this bead's:
 *
 *   - WHICH language. predicator is the family's expression language and it is
 *     deliberately non-evaluative on the condition surface; whether the same
 *     grammar is the right one for a value that is COMPUTED, and whether a
 *     block document may carry an expression that must be evaluated to compile,
 *     is predicator-ex's and statifier-ex's call jointly, not this repo's;
 *   - HOW it is stored. A second field (`value` xor `expression`), or one field
 *     with a mode, or the `expression` field type `core.on_event`'s `cond`
 *     already uses. The third is cheapest and is probably right, and "probably
 *     right" is not a reason to author it into a fixture;
 *   - what the SPIKE would then have to refuse to do. D4's honest-replayer
 *     ruling means the runner may not evaluate anything, so an expression-valued
 *     assign would replay exactly as a literal one does - the delta the author
 *     wrote - and the screen would look identical while claiming more. That is
 *     the shape of thing this spike exists to avoid shipping.
 *
 * So: literals only, said out loud here rather than discovered by a reader.
 *
 * ## Replay: the delta IS the step
 *
 * `core.invoke` needed a PROPOSED `invoke` step field (sb-ig4) because "this
 * step left the chart" is a fact no other part of a run records. An assign
 * needs nothing: the run's `deltas` mechanism already carries `{ path, value }`
 * writes, `bindingsAt` already accumulates them last-write-wins, and an assign
 * step's delta is simply the step's own work rather than a side effect of a
 * call. This descriptor therefore proposes no fixture field at all, which is
 * the strongest thing that can be said for the mechanism that is already there.
 *
 * ## The DECLARATION check is not here, and that is still true (sb-c2o)
 *
 * Nothing below asks whether `path` is DECLARED in `fixtures/datamodel.json`,
 * and it never will: `validate_config/1` is handed a config, not a document, so
 * the datamodel index the check needs is not in reach. sb-c2o landed the check
 * where it is - a document-level pass in `layout.js`, off the
 * `datamodelPath: "writes"` annotation the schema below now carries.
 *
 * The second half of that bead is why the finding can be a WARNING at all.
 * `layout.js` used to stamp `severity: "error"` on every problem
 * `validateConfig` returned, so a warning-shaped return would have rendered as
 * an error on the card and in the panel; it now carries `problem.severity`
 * through, defaulting to `"error"`. A type that wants to return a warning of
 * its own may, which is a door this file does not walk through yet.
 *
 * ## What this would compile to (Phase B; nothing here compiles anything)
 *
 * An `<assign location="..." expr="...">` in the onentry of the state the block
 * compiles into - the SCXML the engine already executes, which is why this is
 * the shortest compile sketch in the file. What it does NOT settle is where the
 * write is ordered against the state's other onentry content, and whether an
 * assign to an undeclared location is an error at compile time or a datamodel
 * that grows a key. Both are statifier-ex's, both are open.
 */

/* Non-empty and no whitespace, and NOT a dotted-identifier grammar, which is
 * the deliberate part. `isPathish` above takes exactly this stance and says
 * why: this file does not own the datamodel path grammar, and a regex here that
 * accepted `review.parked` and refused something `fixtures/datamodel.json`
 * legitimately declares would be a second, quieter proposal riding along with
 * this one. Whether the two paths a `params` row and an assign name are the
 * same grammar is a real question and it has one answer, not two spellings.
 * Two predicates in one file spelling one stance is a smell the day that
 * answer arrives; until then neither owns the grammar and both say so. */
const isDatamodelPath = (value) => nonEmptyString(value) && !/\s/.test(value);

const coreAssign = {
  name: "core.assign",
  currentVersion: 1,
  slots: () => [],
  configSchema: () => [
    {
      key: "path",
      type: "string",
      label: "Write to",
      required: true,
      default: "",
      /* sb-c2o, as `core.invoke`'s `assign_to`. The grammar stays unowned by
       * this file (see `isDatamodelPath`); what the annotation adds is not a
       * second grammar but a lookup in the datamodel document. */
      datamodelPath: "writes",
    },
    {
      key: "value",
      /* `string` because the stored form is source text (see the note above),
       * so the control an author gets is the one that shows them the quotes
       * they typed. An `expression` type would be the wrong promise. */
      type: "string",
      label: "This literal",
      required: true,
      default: "",
    },
  ],
  validateConfig: (config) => {
    const findings = [];

    if (!isDatamodelPath(config.path)) {
      findings.push({ key: "path", message: "must be a datamodel path, like review.parked" });
    }
    /* An empty `value` is refused, and the source-text rule is why it can be:
     * writing an empty string is spelled `""`, two characters, so nothing
     * legitimate is spelled with nothing at all. Under a typed value this
     * check would have to change with it. */
    if (!nonEmptyString(config.value)) {
      findings.push({
        key: "value",
        message: 'must be a literal, written as source text - false, 42350, "manual_review"',
      });
    }

    return verdict(findings);
  },
  /*
   * `core.raise`'s io exactly, for `core.raise`'s reason: one outcome, so there
   * is no join to refuse and `produces` is absent rather than `"unknown"`. An
   * assign reads nothing through the type flow either - its input is a literal
   * it carries - so there is no `consumes`.
   */
  io: () => ({ kinds: ["step"] }),
  paletteEntry: {
    label: "Assign",
    group: "Proposed core",
    description: "Writes a literal to a datamodel path.",
    /* `render.js`'s existing glyph for something landing in a container, which
     * is what a write to the datamodel is. It collides with `myapp.intake`, and
     * the collision is the same kind `core.raise` accepted for `megaphone`:
     * cheaper than editing the renderer's icon set for a proposal. */
    icon: "inbox",
    keywords: ["assign", "set", "write", "datamodel", "variable", "flag"],
    order: 3,
    /* The bead's badge. What a card titled "Clear the parked flag" cannot say:
     * this step changes the datamodel, so a reader tracing where a value came
     * from has somewhere to look that is not a host call. Well under
     * `badgeFor`'s 24-character cap. */
    badge: "writes",
    /* No `accentToken`, for the reason `core.raise` gives: the teal is for work
     * that happens outside this chart, and a write to the chart's own datamodel
     * is as inside as a step gets. */
  },
};

/* ------------------------------------------------------------- core.send
 *
 * APPENDED BY sb-ajr, at the END of this file and of the map below, for the
 * reason `core.timeout` says above: a sibling bead was appending its own
 * descriptor at the same time, and a pure append is the only edit two writers
 * can make to one file without meeting in the middle. Placement is a merge
 * courtesy; in reading order `core.send` belongs beside `core.raise`, which is
 * the type it is one config field away from.
 *
 * A leaf step that sends one event, immediately or after a delay.
 *
 * ## What it adds to `core.raise`, and why it is a second type
 *
 * `core.raise` names an event and hands control on, now. `core.send` names an
 * event and says WHEN - and the delay is not a detail of the same block, it is
 * a different thing to compile and a different thing to reason about. A raise
 * is internal and synchronous: the enclosing group's rail sees it during the
 * same macrostep. A delayed send outlives the step that armed it, has to
 * survive a restart, and is the one form in this file whose compiled shape
 * needs infrastructure outside the interpreter (see the compile note below).
 *
 * Folding the two into one type with an optional `delay` was the alternative
 * and it is worse: `core.raise`'s whole descriptor argues that a raise is the
 * most inside-the-chart step there is, and a key that quietly turns it into a
 * durable timer would make that note false half the time. Two types, one
 * grammar for the event name, is the same shape `core.wait` and `core.timeout`
 * already have - the same clock, said from a body and said from a rail.
 *
 * ## The badge is `sends`, and NOT `timer` when a delay is set
 *
 * The bead left this to the drafter. Decided: a single static `sends`.
 *
 * The dynamic reading - `timer` when `delay` is set, `sends` when it is not -
 * was checked against the metadata layer before being turned down, because it
 * is expressible: `paletteEntry.joinLabel` is a CALLBACK of config (sb-dxs),
 * so d10 already has a precedent for a config-dependent presentation value.
 * `badge` is not one. `badgeFor(entry)` in `palette.js` takes the entry and
 * nothing else, and `layout.js` calls it that way; making the badge dynamic
 * means widening that signature and its call site - an in-place change to two
 * shared files, proposing a d10 metadata amendment, made in passing by a leaf
 * descriptor whose bead is about neither. That is the tail wagging the dog.
 *
 * Two reasons besides the mechanical one, and they are the ones that would
 * still hold if `badgeFor` took a config tomorrow:
 *
 *   - `timer` is already `core.wait`'s badge (sb-p0k), where it means the
 *     thing a reader cannot otherwise see: the chart stays LIVE for the whole
 *     duration. A delayed send does not say that about the block it sits on -
 *     the send finishes immediately and the delay is the event's, not the
 *     step's. The same chip meaning two different things on two cards is worse
 *     than no chip;
 *   - a badge that changes as a config field is typed is a chip a reader
 *     cannot learn. `sends` is true of every `core.send` in every
 *     configuration, which is what makes it worth putting on the card at all.
 *
 * Whether `badge` should be allowed to be a callback the way `joinLabel` is -
 * and this type is the first real evidence for the question - is a Phase-B
 * finding, recorded on the bead.
 *
 * ## `target` is SKETCHED, not built
 *
 * An SCXML `<send>` carries a target: the same session, another session, or an
 * external I/O processor. This descriptor declares NO `target` field, and the
 * omission is deliberate rather than an oversight:
 *
 *   - what a target may NAME is not this repo's decision. Session identity is
 *     statifier-ex's (ADR-0052), and reaching the host is the invoke seam
 *     ADR-0051 defines, which the vocabulary already spells `core.invoke`. A
 *     `target` string field here would be a third way to leave the chart,
 *     invented in a spike file, with no record behind it;
 *   - a config key that validates nothing is a proposal made by accident. The
 *     field would have to accept any string, because this file does not own
 *     the grammar - and then the first author to type one would have authored
 *     a document the compiler cannot honour.
 *
 * So the sketch is this paragraph. If a target lands, the shape it would take
 * is a `{ select: [...] }` over targets a HOST declares - the same move
 * `core.subchart`'s chart picker makes (D11) - and never a free string. Every
 * `core.send` in a document without one means the internal target: this
 * session, which is what makes a delayed send catchable by a rail in the same
 * chart, which is what the demo does.
 *
 * ## `<cancel>` is SKETCHED HERE and NOT BUILT - deliberately
 *
 * A `<send>` with a delay and an id can be cancelled by a `<cancel>` before it
 * fires, and every real use of a durable timer wants that: the deadline that
 * stops mattering once the customer finishes. This file proposes NO
 * `core.cancel`, and will not, because the missing piece is not a descriptor:
 *
 *   - a cancel names the SEND it cancels, so it needs an identity for a send.
 *     `sendid` in SCXML is a compile-time artifact; a block document's handle
 *     would have to be the sending block's id, which makes the cancel a
 *     cross-subtree REFERENCE to another block - the exact shape D13 refused
 *     for `core.invoke`'s failure path and `core.raise`'s catch (operator,
 *     2026-08-28, umbrella `docs/decisions.md`). Every edge in a document is a
 *     parent/slot/child relationship, and a cancel pointing at a send would be
 *     the first hand-drawn one;
 *   - the alternative that keeps the tree invariant is scope-shaped rather
 *     than reference-shaped: a delayed send is cancelled when the region that
 *     armed it is left. That is a COMPILER rule, not a block type, and it is
 *     also what `core.timeout` already means on a rail - which is the strong
 *     hint that the vocabulary may need no `core.cancel` at all;
 *   - either way it is an upstream question (what a delayed send's lifetime is
 *     bound to) that no accepted ADR answers, and CLAUDE.md is explicit that a
 *     bead needing an answer no accepted ADR gives is a stop-and-report rather
 *     than a guess encoded in code.
 *
 * Sketched, named, and left unbuilt. A Phase-B finding, on the bead.
 *
 * ## What this would compile to (Phase B; nothing here compiles anything)
 *
 *   - `<send event="..." />` in the onentry of the state this block compiles
 *     into. With no `delay`, that is a zero-delay send to this session, which
 *     is the same delivery `core.raise` gets and the reason `core.raise`'s
 *     note leaves "`<raise>` or a zero-delay `<send>`" open - whichever way
 *     that is settled, it should be settled ONCE for both types;
 *   - with a `delay`, `<send delay="...">`, and that is the clause with an
 *     owner outside this repo: a delayed send that survives a restart is the
 *     statifier_oban lane (`sob-`, durable timers; statifier-ex
 *     `docs/durable-timers.md`, ADR-0054/0059). This descriptor names that
 *     lane and proposes nothing about it. `core.wait`'s badge already says the
 *     neighbouring fact - a wait compiles to a delayed send rather than a
 *     sleep - which means the two types would compile through the SAME
 *     machinery, one saying "pause here until" and one saying "wake me later";
 *   - an event nothing catches is not an error, exactly as for `core.raise`:
 *     it is delivered, no transition is enabled, the chart carries on. A
 *     document-level finding ("nothing catches signup.onboarding_expired") is
 *     an editor affordance worth having and is not this descriptor's job.
 *
 * ## The duration CONTROL question (sb-d9) gets its live test case here
 *
 * `delay` is ADR-0002 decision 7's existing `duration` field type, so it draws
 * the same control `core.wait`'s duration and `core.timeout`'s `after` draw.
 * sb-d9's open item was whether that control is the right one to author with;
 * this is the first duration in the vocabulary that is OPTIONAL, which is a
 * state the control had never had to express - "no delay" is not `PT0S` and it
 * is not an unfinished field either. It was this field that answered it: the
 * old control committed `PT0H` when the box was cleared, which is sb-709, and
 * the ruling there rebuilt the control around what a person types (`1h30m`,
 * `2d`) with empty meaning the key is OMITTED. This descriptor still proposes
 * nothing about the control; it is the field the control was built against,
 * and the spike README's config-pane section is where that ruling is written
 * down.
 */
const coreSend = {
  name: "core.send",
  currentVersion: 1,
  /* `core.raise`'s declaration: a send has no subtree and no outcome path. */
  slots: () => [],
  configSchema: () => [
    {
      key: "event",
      type: "string",
      label: "Send this event",
      required: true,
      default: "",
    },
    {
      /* Optional, and the default is "" rather than a duration: a send with no
       * delay is the ordinary case, and defaulting to `PT1H` the way
       * `core.wait` does would author a timer nobody asked for. */
      key: "delay",
      type: "duration",
      label: "After (leave empty to send now)",
      required: false,
      default: "",
    },
  ],
  validateConfig: (config) => {
    const findings = [];

    /* `core.raise`'s check and `core.raise`'s message, word for word, through
     * the same `EVENT_NAME` this file already shares with `core.on_event`. A
     * name one type accepts and another refuses is a rail that catches
     * nothing, and the selftest asserts the three agree rather than asserting
     * one regex three times. */
    if (!isEventName(config.event)) {
      findings.push({ key: "event", message: "must be an event name, like signup.abandoned" });
    }

    /* `assignToFindings`' idiom for an optional field, not `core.timeout`'s
     * `cond` idiom, and the difference is deliberate. A `cond` that is present
     * and empty is an author who started writing a guard and stopped; a
     * `delay` that is present and empty is the field's own DEFAULT, which the
     * config form writes into every block of this type. So absent and "" are
     * both silent, and anything else present has to be a real duration - a
     * stored `null` included, which reaches this arm and is refused, as
     * ADR-0001 decision 6 requires. */
    if ("delay" in config && config.delay !== "" && !isDuration(config.delay)) {
      findings.push({
        key: "delay",
        message: "must be an ISO-8601 duration, like PT2H, or empty to send now",
      });
    }

    return verdict(findings);
  },
  /*
   * `core.raise`'s io exactly, for `core.raise`'s reason: one outcome, so
   * `produces` is absent rather than `"unknown"` - there is no join to refuse.
   * A delayed send is still one outcome; the block finishes when the send is
   * armed, not when it arrives.
   */
  io: () => ({ kinds: ["step"] }),
  paletteEntry: {
    label: "Send",
    group: "Proposed core",
    description: "Sends an event, now or after a delay.",
    /* `core.invoke`'s glyph - an arrow leaving the box - and the collision is
     * argued rather than accidental, the way `core.subchart` argues its reuse
     * of `rectangle-group`. A send DISPATCHES: the event leaves this block and
     * is delivered on its own, possibly long after the step has finished.
     * `megaphone` would have been the other candidate and it is worse: that is
     * `core.raise`'s glyph, and raise and send are the two types in this file
     * a reader is most likely to confuse, so they are the two that must not
     * look alike. The teal accent is what tells this card apart from an
     * invoke's, and this type declines it - see below. */
    icon: "arrow-up-right",
    keywords: ["send", "event", "delay", "later", "timer", "deadline", "notify"],
    order: 3,
    /* The decision argued at length above: static, and `sends` rather than
     * `timer`. Under `badgeFor`'s 24-character cap with room to spare. */
    badge: "sends",
    /* No `accentToken`, for `core.raise`'s reason: with no target, a send goes
     * to this chart's own session, so it is inside-the-chart work and takes
     * the editor's own accent. `tokens.css` says the teal is for the step
     * whose work happens outside, and this is not that step - which is also
     * what keeps the shared glyph from reading as an invoke. */
  },
};

/* ---------------------------------------------------------- core.foreach
 *
 * APPENDED BY sb-9nn at the END of this file and of the map below, for the
 * reason `core.timeout` says above. Placement is a merge courtesy; in reading
 * order this is the file's one CONTAINER and belongs beside nothing else here.
 *
 * A container that runs its `body` once for each item of a datamodel list.
 *
 * ## Why the vocabulary needed it
 *
 * Every container the package ships is about WHEN a run of steps happens -
 * `core.sequence` one after another, `core.parallel` at the same time,
 * `core.group` inside a boundary rules can fire against. None of them is about
 * HOW MANY TIMES. A chart that has to do the same work for each of three
 * invitees, or each transaction in a statement batch, could only be authored by
 * copying the subtree once per item - which is not authoring, it is
 * transcription, and it goes wrong the moment the list has a length nobody
 * knew at authoring time.
 *
 * ## Its config, and the one key that is a genuinely new idea
 *
 *   - `items` is a datamodel path, checked the way `core.assign`'s `path` is
 *     checked and for the same stated reason: this file does not own the
 *     datamodel path grammar. Whether the path is DECLARED is a document-level
 *     question `validate_config/1` cannot answer, and sb-c2o answered it in
 *     `layout.js` off the `datamodelPath: "reads"` annotation below - a
 *     warning, never a refusal. What is still unchecked is that the thing the
 *     path names is a LIST rather than a string, which needs the datamodel
 *     document's own type vocabulary to be decided first;
 *   - `item_as` BINDS A NAME. That is the new idea, and it is the reason this
 *     type is more than a container: every other block in the vocabulary reads
 *     the datamodel through paths that exist before the chart runs, and this
 *     one introduces a name that exists only inside its own body. A bare
 *     identifier, defaulted to `item`, because a foreach with nothing to call
 *     its item is an unfinished block and an empty default would read as one
 *     the author had abandoned;
 *   - `index_as` is optional and binds the ordinal the same way. Optional
 *     because most bodies never name it, and a required key an author has to
 *     fill in to say "I do not need this" is a key that teaches them to ignore
 *     the form.
 *
 * The two bound names must differ. That is the only cross-field check here,
 * and it is worth making: `item_as: "row"` with `index_as: "row"` is a config
 * that reads fine and means nothing, and the author who typed it will look for
 * the mistake everywhere except at the block.
 *
 * ## The declared body slot renders EMPTY, and that is sb-mu2's landing
 *
 * `slots()` declares one `body`, so `layout.js` calls this block a container
 * whether or not anything is in it (`shapeOf`: the test is over DECLARED
 * slots), and the renderer draws a labeled drop target for the empty slot. A
 * freshly inserted foreach is therefore fillable, which is not something this
 * descriptor had to build - sb-mu2 made the container test a statement about
 * the TYPE rather than about a document's contents, and every later container
 * gets it for free. Asserted in `dev/selftest.html` rather than assumed,
 * because "for free" is the kind of claim that stops being true quietly.
 *
 * ## The bound name is NOT offered in the condition editor yet - DEFERRED
 *
 * The bead asks whether `item_as`'s name becomes offerable to a condition
 * written INSIDE the body, so an author can write `invitee.email` where they
 * can today only write `signup.email`. It does not, and this is a deliberate
 * deferral with a scope note rather than a gap:
 *
 *   - the condition surface resolves paths against ONE index, built once in
 *     `shell.js` as `indexPaths(datamodelDoc)` and handed to the inspector.
 *     It is a fact about the DOCUMENT-independent datamodel, and it knows
 *     nothing about which block is selected;
 *   - a scoped offering is a different object: the index a block sees would
 *     have to be the datamodel index PLUS the names bound by every
 *     `core.foreach` on the path from the root to that block. That needs an
 *     ancestor walk per selection, a layered index that can say which of its
 *     entries are bound rather than declared (they are not the same thing to a
 *     reader, and rendering them identically would claim the datamodel
 *     declares something it does not), and a new value threaded from `shell.js`
 *     through `inspector.js` to `annotateCondition`;
 *   - it also raises a question this bead has no standing to answer: what an
 *     item's own FIELDS are. `invitee.email` is only offerable if something
 *     knows the item type of the list `items` names - which is the datamodel
 *     document's `item_type`, today a string like `"string"` and not a shape.
 *     Offering a bare `invitee` and nothing under it is honest; offering
 *     `invitee.email` needs the datamodel proposal to grow, and that is a
 *     proposal, not an implementation detail.
 *
 * So: the descriptor binds the name, the document stores it, the selftest
 * asserts it is stored, and the condition editor reports a bound name as an
 * UNKNOWN path exactly as it reports any path the datamodel does not declare -
 * which is advisory, never an error (see `datamodel.js`'s header on why that
 * asymmetry exists). A reader gets a true answer rather than a flattering one.
 * Filed as a Phase-B finding on sb-9nn, and it wants the datamodel-document
 * proposal decided first.
 *
 * ## Replay: an AUTHORED `foreach` step field (D4)
 *
 * A run over a list is the case a replayer is most likely to be mistaken for a
 * loop, so the fixture field is shaped to make the mistake impossible to make
 * quietly. `fixtures/runs.json` grows `foreach: { block, index, item }` on a
 * step - the sb-ig4 pattern, the same way `invoke` was added - and every one of
 * those three values is TYPED IN by the fixture's author:
 *
 *   - `block` is the foreach block the step is inside, so the pane can say
 *     which container the iteration belongs to;
 *   - `index` is the ordinal the author wrote, not a counter the pane keeps;
 *   - `item` is display-only source text, the same string rule the deltas hold
 *     to, and nothing reads it back.
 *
 * Nothing in the runner iterates. A run over two invitees is two authored
 * passes of authored steps, and if an author writes indices 0 and 2 the pane
 * shows 0 and 2. That is D4 applied to the one field most likely to be
 * mistaken for machinery, which is exactly what sb-ig4's note says about
 * `invoke` and is repeated here because the temptation is stronger.
 *
 * ## What this would compile to (SKETCH ONLY - nothing here compiles anything)
 *
 * Two shapes, and the vocabulary does not yet say which one a `core.foreach`
 * means, because it has no key to say it with:
 *
 *   - SEQUENTIAL, which is what this descriptor assumes and what the demo
 *     replays: a loop-shaped subgraph. The body compiles once, into a state
 *     entered with the item bound, and its completion transitions back to the
 *     head with the cursor advanced - the datamodel carrying the cursor and the
 *     bound name, since SCXML has no loop construct and a `<foreach>` in
 *     executable content is not a place a whole subtree can live. That is the
 *     part that is genuinely open: `<foreach>` iterates EXECUTABLE CONTENT, and
 *     a body of blocks is states, so the emission is a state machine and not an
 *     executable-content element. What binds the item, where the cursor lives,
 *     and whether either is visible in the datamodel a host can read are
 *     statifier-ex's calls, not this repo's;
 *   - PARALLEL FAN-OUT: one child session per item, which is
 *     `core.subchart`'s compile sketch applied N times - an `<invoke>` per item
 *     through the per-session registry statifier-ex ADR-0051 defines, with the
 *     item passed as a param. That sketch already names its own open question
 *     (how a child chart's several final states reach a parent's slots), and a
 *     fan-out inherits it and adds a second: what the parent does when three
 *     of five children fail. Cited rather than restated.
 *
 * Neither is built and no config key chooses between them. A `mode` field was
 * the obvious thing to declare and it is left out on purpose: it would be a
 * key whose two values name two compilers that do not exist, which is a
 * proposal made by accident - the same argument `core.send` makes for
 * declining a `target`. When the emission is decided the key follows it.
 */

const coreForeach = {
  name: "core.foreach",
  currentVersion: 1,
  /* One primary slot, so `layout.js` arranges it as a stack rather than a fan
   * (`arrangementOf`: more than one primary slot is what fans). `core.group`'s
   * `body` declaration with a label that says what makes this container
   * different - the steps inside run more than once. */
  slots: () => [{ name: "body", arity: "any", label: "For each item" }],
  configSchema: () => [
    {
      key: "items",
      type: "string",
      label: "For each item in",
      required: true,
      default: "",
      /* sb-c2o, and the one `reads` of the four: a foreach never writes the
       * list it walks, so the finding's fix says "read a path it already
       * declares" rather than "write to one". What is STILL not checked is
       * that the declared path is a LIST rather than a string - that is a
       * type-shape question the datamodel-document proposal has to settle
       * first, and the selftest asserts the shipped list is declared as one
       * rather than the editor enforcing it. */
      datamodelPath: "reads",
    },
    {
      key: "item_as",
      type: "string",
      label: "Call the item",
      required: true,
      default: "item",
    },
    {
      key: "index_as",
      type: "string",
      label: "Call the position (optional)",
      required: false,
      default: "",
    },
  ],
  validateConfig: (config) => {
    const findings = [];

    if (!isDatamodelPath(config.items)) {
      findings.push({
        key: "items",
        message: "must be a datamodel path naming a list, like signup.invitees",
      });
    }
    if (!isIdentifier(config.item_as)) {
      findings.push({ key: "item_as", message: "must be a bare lowercase identifier" });
    }
    /* `assignToFindings`' idiom for an optional field, not `core.timeout`'s
     * `cond` idiom, and for `core.send`'s stated reason: "" is this field's own
     * DEFAULT, which the config form writes into every block of this type, so
     * absent and empty are both silent. */
    if (nonEmptyString(config.index_as) && !isIdentifier(config.index_as)) {
      findings.push({ key: "index_as", message: "must be a bare lowercase identifier" });
    }
    /* The only cross-field check in this file, and the note above says why it
     * earns its place: two names that collide read fine and mean nothing. */
    if (
      isIdentifier(config.item_as) &&
      nonEmptyString(config.index_as) &&
      config.item_as === config.index_as
    ) {
      findings.push({
        key: "index_as",
        message: "the item and its position cannot share one name",
      });
    }

    return verdict(findings);
  },
  /*
   * `core.group`'s io: a step containing steps. `produces` is absent rather
   * than `"unknown"` - a foreach has one outcome, so there is no join to
   * refuse, which is the distinction `core.invoke` and `core.branch` are
   * `"unknown"` for. `consumes` is absent too, and it is the one place a reader
   * might expect otherwise: a foreach does read the datamodel, through `items`,
   * but that is a config path rather than a value arriving through the type
   * flow, which is exactly the reason `core.invoke` declares no `consumes`
   * either while reading its inputs through `params`.
   */
  io: () => ({
    kinds: ["step"],
    slotAccepts: { body: ["step"] },
  }),
  paletteEntry: {
    label: "For each",
    group: "Proposed core",
    description: "Runs its body once for each item in a datamodel list.",
    /* `core.resumable_group`'s glyph - a circling arrow - and the collision is
     * argued the way `core.subchart` argues its reuse of `rectangle-group`:
     * both blocks are about coming back to the same place, and the drawing is
     * the right picture twice. Minting a new glyph would mean editing
     * `render.js`'s icon set for a proposal, which is the cost `core.raise`,
     * `core.assign` and `core.subchart` all declined. */
    icon: "arrow-path",
    keywords: ["foreach", "each", "loop", "iterate", "list", "batch", "repeat"],
    order: 4,
    layout: "stack",
    /* The one slot is the body, so it takes the primary style `core.group`'s
     * body takes. Declared rather than left to `layout.js`'s fallback (which
     * would reach the same answer) because a container whose slot style is
     * implicit is the one place a later rail would land silently. */
    slotStyle: { body: "primary" },
    /* What a card titled "For each invitee" cannot say on its own: the steps
     * below it run more than once. Well under `badgeFor`'s 24-character cap. */
    badge: "for each",
    /* No `accentToken`, for `core.raise`'s reason: the teal is for work that
     * happens outside this chart, and a foreach is pure control flow inside
     * it. The steps in its body claim their own accents where they earn them,
     * which is what keeps the container from out-shouting its contents. */
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
  /* APPENDED by sb-0o4 - see the placement note at the descriptor. */
  "core.timeout": coreTimeout,
  "core.subchart": coreSubchart,
  /* APPENDED by sb-y4a - see the placement note at the descriptor. */
  "core.assign": coreAssign,
  /* APPENDED by sb-ajr - see the placement note at the descriptor. */
  "core.send": coreSend,
  /* APPENDED by sb-9nn - see the placement note at the descriptor. */
  "core.foreach": coreForeach,
};
