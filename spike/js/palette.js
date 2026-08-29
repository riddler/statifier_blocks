/*
 * spike/js/palette.js - the block-type registry, mirrored in the browser.
 *
 * A client-side mirror of `StatifierBlocks.Palette` plus the `core.*`
 * vocabulary (ADR-0002 decisions 2, 3, 5-8 and 10; ADR-0005 decisions 9, 10
 * and 12). The `core.*` descriptors below are transcribed BY HAND from
 * `lib/statifier_blocks/core/*.ex` - names, slot declarations, arities,
 * labels, config fields and presentation metadata are verbatim, so the
 * spike's palette browser and config forms are looking at the real
 * vocabulary rather than at an invented one.
 *
 * What is deliberately NOT transcribed, and why:
 *
 *   - `emit/2`. The spike compiles nothing; SCXML emission is ADR-0004's and
 *     has no visual surface here.
 *   - `fixtures/0`. The fixture-runner pane is mocked (campaign D4), and the
 *     bundle spelling is statifier-ui's contract, not this file's to guess.
 *   - `migrate_config/2` on the core types, none of which declares one -
 *     every core type is at `current_version` 1. The mechanism itself IS
 *     mirrored, and one demo type exercises it.
 *
 * ## A descriptor
 *
 * The Elixir seam is a behaviour module; the JS seam is a plain object with
 * the same callbacks as functions of config:
 *
 *     {
 *       name, currentVersion,
 *       slots(config)        -> [{ name, arity, label }]
 *       configSchema(config) -> [{ key, type, label, required, default, valuePath? }]
 *       validateConfig(cfg)  -> null | [{ key, message }]
 *       io(config)           -> { kinds?, consumes?, produces?, slotAccepts? }
 *       paletteEntry         -> ADR-0005 decision 10's metadata
 *       migrateConfig?(from, config) -> ok(config) | err(reason)
 *     }
 *
 * Arity is ADR-0002 decision 6's closed set, spelled as strings:
 * `"any"`, `"at_least_one"`, `"exactly_one"`, `"zero_or_one"`.
 *
 * One field NO descriptor below declares, and none should: `label`. The
 * editor injects it into every descriptor it resolves (`withEditorFields`),
 * because every card titles itself from it and a type declaring it was
 * writing the editor's boilerplate.
 *
 * A field type is ADR-0002 decision 7's closed set: the string `"string"`,
 * `"integer"`, `"boolean"`, `"expression"` or `"duration"`, or the object
 * `{ select: [{ value, label }] }` or `{ list: <field type> }`. Closed on
 * purpose - the config form must be able to render every one of them, and an
 * open set makes that unprovable.
 */

import { compareUtf8, err, ok } from "./document.js";

/* ------------------------------------------------- shared config checks */

/*
 * `StatifierBlocks.Core.Config`'s predicates, verbatim regexes included.
 * They live here for the same reason they live in one module upstream: seven
 * descriptors would otherwise spell them seven times and drift.
 */
const IDENTIFIER = /^[a-z][a-z0-9_]*$/;
const ARM_SLOT = /^arm_[a-z][a-z0-9_]*$/;
const EVENT_NAME = /^[A-Za-z_][A-Za-z0-9_.\-]*$/;
const DURATION = /^P(?!$)(\d+Y)?(\d+M)?(\d+W)?(\d+D)?(T(?!$)(\d+H)?(\d+M)?(\d+S)?)?$/;

const nonEmptyString = (value) => typeof value === "string" && value !== "";
const isIdentifier = (value) => nonEmptyString(value) && IDENTIFIER.test(value);
const isArmSlot = (value) => nonEmptyString(value) && ARM_SLOT.test(value);
const isEventName = (value) => nonEmptyString(value) && EVENT_NAME.test(value);
const isDuration = (value) => nonEmptyString(value) && DURATION.test(value);
const oneOf = (value, options) => typeof value === "string" && options.includes(value);

/** `validate_config/1`'s return: `null` for `:ok`, or an ordered finding list. */
const verdict = (findings) => (findings.length === 0 ? null : findings);

/*
 * `List.wrap/1`: an array is itself, `nil` is `[]`, anything else is wrapped.
 * `null` maps to `[]` rather than `[null]` because that is what `List.wrap`
 * does, and the two spellings of "absent" should not diverge here.
 */
const asList = (value) =>
  Array.isArray(value) ? value : value === undefined || value === null ? [] : [value];

/*
 * `Map.get(config, key, default)`: the default applies to an ABSENT key only.
 * `config[key] ?? fallback` would also swallow a stored `null`, and ADR-0001
 * decision 6 admits `null` as a config value - so `{"arms": null}` has to
 * reach `validate_config`'s "must be a list of arms" arm rather than being
 * coalesced into a valid empty list.
 */
const configGet = (config, key, fallback) =>
  Object.hasOwn(config, key) ? config[key] : fallback;

/* ------------------------------------------------- the core vocabulary */

/*
 * core.sequence - an ordered run of steps, and the conventional document
 * root. One `body` slot, no config at all; adjacency inside `body` IS
 * sequencing (ADR-0001 decision 5), which is why it is the one core type
 * transparent to type flow.
 */
const coreSequence = {
  name: "core.sequence",
  currentVersion: 1,
  slots: () => [{ name: "body", arity: "any", label: "Steps" }],
  configSchema: () => [],
  validateConfig: () => null,
  io: () => ({
    kinds: ["step"],
    produces: { passthrough: "body" },
    slotAccepts: { body: ["step"] },
  }),
  paletteEntry: {
    label: "Sequence",
    group: "Structure",
    description: "Runs its steps one after another.",
    icon: "bars-3",
    keywords: ["steps", "order", "then"],
    order: 0,
    layout: "stack",
  },
};

/*
 * core.group - a boundary around a run of steps that interrupt rules can fire
 * against. Two named slots meaning entirely different things, which is the
 * case slots are named for (ADR-0001 decision 10), and the `slot_style`
 * secondary rail ADR-0005 decision 10 renders `interrupts` with.
 */
const coreGroup = {
  name: "core.group",
  currentVersion: 1,
  slots: () => [
    { name: "body", arity: "any", label: "Steps" },
    { name: "interrupts", arity: "any", label: "Interrupt rules" },
  ],
  configSchema: () => [],
  validateConfig: () => null,
  io: () => ({
    kinds: ["step"],
    slotAccepts: { body: ["step"], interrupts: ["interrupt_handler"] },
  }),
  paletteEntry: {
    label: "Group",
    group: "Structure",
    description: "Groups steps so interrupt rules can fire against them.",
    icon: "rectangle-group",
    keywords: ["interrupt", "boundary", "scope"],
    order: 1,
    layout: "stack",
    slotStyle: { body: "primary", interrupts: "secondary" },
  },
};

/*
 * core.resumable_group - core.group plus a history mode. ADR-0005 decision 10
 * is explicit that the mode needs no editor support: it renders through the
 * ordinary `:select` form machinery, and the presentation metadata this type
 * carries is about its two slots rather than about resuming.
 */
const RESUMABLE_HISTORY = ["shallow", "deep"];

const coreResumableGroup = {
  name: "core.resumable_group",
  currentVersion: 1,
  slots: () => [
    { name: "body", arity: "any", label: "Steps" },
    { name: "interrupts", arity: "any", label: "Interrupt rules" },
  ],
  configSchema: () => [
    {
      key: "history",
      type: {
        select: [
          { value: "shallow", label: "Shallow - the last top-level step" },
          { value: "deep", label: "Deep - the exact position" },
        ],
      },
      label: "Resume at",
      required: true,
      default: "shallow",
    },
  ],
  validateConfig: (config) =>
    oneOf(config.history, RESUMABLE_HISTORY)
      ? null
      : [{ key: "history", message: 'pick "shallow" or "deep"' }],
  io: () => ({
    kinds: ["step"],
    slotAccepts: { body: ["step"], interrupts: ["interrupt_handler"] },
  }),
  paletteEntry: {
    label: "Resumable group",
    group: "Structure",
    description: "A group that remembers where it was when it resumes.",
    icon: "arrow-path",
    keywords: ["history", "resume", "interrupt"],
    order: 2,
    layout: "stack",
    slotStyle: { body: "primary", interrupts: "secondary" },
  },
};

/*
 * core.branch - one slot per condition arm, plus `otherwise`. The
 * config-parameterized case ADR-0001 decision 5 exists for.
 *
 * Three details the upstream moduledoc calls out, mirrored here because each
 * is a place a reader would reasonably guess the other way:
 *
 *   - an arm stores its WHOLE slot name (`"arm_approved"`), not the suffix;
 *   - arms are `at_least_one`, `otherwise` is `any`;
 *   - the condition field is keyed by the arm's slot name but READ through
 *     `valuePath: ["arms", i, "cond"]`, with `i` the arm's index in the
 *     STORED list - so an arm below a malformed one still addresses its own
 *     condition while an author is mid-edit (ADR-0002 decision 7, amended
 *     2026-08-27).
 */
function branchIndexedArms(config) {
  const seen = new Set();

  return asList(config.arms)
    .map((arm, index) => ({ arm, index }))
    .filter(({ arm }) => arm !== null && typeof arm === "object" && isArmSlot(arm.slot))
    .filter(({ arm }) => {
      if (seen.has(arm.slot)) return false;
      seen.add(arm.slot);
      return true;
    });
}

/** `"arm_approved"` reads as `When "approved"` - the suffix is the author's name. */
function branchArmLabel(slot) {
  return `When "${slot.slice("arm_".length)}"`;
}

const coreBranch = {
  name: "core.branch",
  currentVersion: 1,
  slots: (config) => [
    ...branchIndexedArms(config).map(({ arm }) => ({
      name: arm.slot,
      arity: "at_least_one",
      label: branchArmLabel(arm.slot),
    })),
    { name: "otherwise", arity: "any", label: "Otherwise" },
  ],
  configSchema: (config) =>
    branchIndexedArms(config).map(({ arm, index }) => ({
      key: arm.slot,
      type: "expression",
      label: branchArmLabel(arm.slot),
      required: true,
      default: "",
      valuePath: ["arms", index, "cond"],
    })),
  validateConfig: (config) => {
    const arms = configGet(config, "arms", []);
    if (!Array.isArray(arms)) {
      return [{ key: "arms", message: "must be a list of arms" }];
    }

    const findings = [];
    const seen = new Set();

    for (const arm of arms) {
      const wellFormed = arm !== null && typeof arm === "object" && "slot" in arm && "cond" in arm;

      if (!wellFormed) {
        findings.push({ key: "arms", message: 'every arm needs a "slot" and a "cond"' });
        continue;
      }

      if (!isArmSlot(arm.slot)) {
        findings.push({ key: "arms", message: 'an arm\'s slot must look like "arm_approved"' });
      } else if (seen.has(arm.slot)) {
        findings.push({ key: arm.slot, message: "two arms cannot share one slot" });
      } else if (!nonEmptyString(arm.cond)) {
        seen.add(arm.slot);
        findings.push({ key: arm.slot, message: "needs a condition expression" });
      } else {
        seen.add(arm.slot);
      }
    }

    return verdict(findings);
  },
  // `produces` is `:unknown`, not a join of the arms: combining them is a
  // type lattice and ADR-0003 decision 4 refuses to build one.
  io: (config) => ({
    kinds: ["step"],
    produces: "unknown",
    slotAccepts: Object.fromEntries(coreBranch.slots(config).map(({ name }) => [name, ["step"]])),
  }),
  paletteEntry: {
    label: "Branch",
    group: "Structure",
    description: "Takes the first arm whose condition holds, or otherwise.",
    icon: "arrows-right-left",
    keywords: ["if", "condition", "else", "when"],
    order: 3,
    layout: "stack",
  },
};

/*
 * core.parallel - one slot per lane, with no ordering between the lanes.
 *
 * A lane stores its BARE name and the slot prefixes it (`"lane_capture"`),
 * where a branch's arm stores the whole slot name. The asymmetry is not this
 * type's choice: it is what ADR-0001's worked example stores, and the stored
 * bytes win over any tidier scheme.
 *
 * ## sb-dxs: `complete`, and a MIRROR DIVERGENCE flagged in the open
 *
 * The `complete` field below is PROPOSED. `core.parallel` is a SHIPPED
 * `core.*` type and `lib/statifier_blocks/core/parallel.ex` declares no such
 * key, so this descriptor is no longer a verbatim transcription: it is the
 * shipped type plus one proposed config field. Same standing as `core.wait`'s
 * proposed badge (sb-p0k) and `core.invoke` (sb-nt3), and flagged the same
 * way - in the open, at the point of divergence, so nobody reads this mirror
 * as evidence of what the package ships.
 *
 * What it means, and what is still open:
 *
 *   - `"all"` (the default) is the statifier-native reading: the lanes are a
 *     `<parallel>` and the region is done when every lane is final, which
 *     compiles to a `done.state.<id>` transition on all-final. Nothing new is
 *     needed downstream for it.
 *   - `"first"` is the OPEN Phase-B semantics question. First-lane-wins is
 *     not a `<parallel>` completion rule; expressing it means cancelling the
 *     losing lanes, and what "cancel" does to a lane mid-invoke is a contract
 *     question this spike is not entitled to answer. It renders, it
 *     validates, it labels its join marker, and it compiles to nothing.
 *
 * Backward compatibility is load-bearing here and asserted in the selftest:
 * every stored `core.parallel` in the demo documents predates this key, so an
 * ABSENT `complete` has to decode and validate exactly as it did before. That
 * is why `validate_config` reads it through `configGet(config, "complete",
 * "all")` - the default applies to an absent key, and a stored `null` still
 * reaches the refusal arm the way ADR-0001 decision 6 requires.
 */
const PARALLEL_COMPLETE = ["all", "first"];

/*
 * The join marker's words, derived from config (sb-dxs).
 *
 * This is a `paletteEntry.joinLabel` callback rather than a renderer branch,
 * and the distinction is the whole point of the item: `render.js` draws
 * whatever string the view model hands it and never learns that the type
 * arranging these columns is called `core.parallel`. A host type that fans
 * into lanes with its own completion rule declares its own callback and gets
 * its own words, which is ADR-0005 decision 10's promise applied to the one
 * piece of chrome that had a hard-coded string left in it.
 */
function parallelJoinLabel(config) {
  return configGet(config, "complete", "all") === "first"
    ? "continue at first"
    : "continue when all";
}

function parallelLanes(config) {
  const seen = new Set();

  return asList(config.lanes).filter((lane) => {
    if (!isIdentifier(lane) || seen.has(lane)) return false;
    seen.add(lane);
    return true;
  });
}

const coreParallel = {
  name: "core.parallel",
  currentVersion: 1,
  slots: (config) =>
    parallelLanes(config).map((lane) => ({
      name: `lane_${lane}`,
      arity: "any",
      label: lane,
    })),
  // `lanes` stays FIRST. The config form addresses a parallel's lane rows as
  // `fields[0]`, and a proposed key is not allowed to renumber a shipped one.
  configSchema: () => [
    {
      key: "lanes",
      type: { list: "string" },
      label: "Lanes",
      required: true,
      default: [],
    },
    {
      // PROPOSED (sb-dxs) - see the divergence note above this descriptor.
      key: "complete",
      type: {
        select: [
          { value: "all", label: "All - when every lane is done" },
          { value: "first", label: "First - when any one lane is done" },
        ],
      },
      label: "Continue",
      required: false,
      default: "all",
    },
  ],
  validateConfig: (config) => {
    const findings = [];

    // Read through the default, so a document stored before `complete`
    // existed validates exactly as it did before. A stored `null` is NOT
    // absent and still lands on the refusal (ADR-0001 d6).
    if (!oneOf(configGet(config, "complete", "all"), PARALLEL_COMPLETE)) {
      findings.push({ key: "complete", message: 'pick "all" or "first"' });
    }

    const lanes = configGet(config, "lanes", []);
    if (!Array.isArray(lanes)) {
      findings.push({ key: "lanes", message: "must be a list of lane names" });
      return verdict(findings);
    }

    const seen = new Set();

    for (const lane of lanes) {
      if (!isIdentifier(lane)) {
        findings.push({
          key: "lanes",
          message: 'a lane name must be a bare lowercase identifier, like "capture"',
        });
      } else if (seen.has(lane)) {
        findings.push({ key: "lanes", message: `two lanes cannot share the name "${lane}"` });
      } else {
        seen.add(lane);
      }
    }

    return verdict(findings);
  },
  io: (config) => ({
    kinds: ["step"],
    produces: "unknown",
    slotAccepts: Object.fromEntries(coreParallel.slots(config).map(({ name }) => [name, ["step"]])),
  }),
  // `layout: "columns"` is how the lanes render side by side without the
  // editor ever branching on the string "core.parallel" (ADR-0005 d10).
  paletteEntry: {
    label: "Parallel",
    group: "Structure",
    description: "Runs its lanes at the same time, in no particular order.",
    icon: "view-columns",
    keywords: ["lanes", "concurrent", "fork", "at once"],
    order: 4,
    layout: "columns",
    /* sb-dxs. PROPOSED, like the `complete` key it reads. The join marker
     * under a fan said "continue" for every block that had one; with a
     * completion rule in config that string is a half-truth, and the fix is
     * a callback the type owns rather than a case in the renderer. */
    joinLabel: parallelJoinLabel,
  },
};

/*
 * core.wait - a leaf whose whole meaning is its config. The duration is an
 * ISO-8601 string rather than a number because ADR-0001 decision 6 forbids
 * floats, and "1.5 hours" has to be `PT1H30M`.
 */
const coreWait = {
  name: "core.wait",
  currentVersion: 1,
  slots: () => [],
  configSchema: () => [
    {
      key: "duration",
      type: "duration",
      label: "Wait for",
      required: true,
      default: "PT1H",
    },
  ],
  validateConfig: (config) => {
    if (!("duration" in config)) return [{ key: "duration", message: "required" }];

    return isDuration(config.duration)
      ? null
      : [{ key: "duration", message: "must be an ISO-8601 duration, like PT30S or P1D" }];
  },
  io: () => ({ kinds: ["step"] }),
  paletteEntry: {
    label: "Wait",
    group: "Structure",
    description: "Pauses for a fixed duration before continuing.",
    icon: "clock",
    keywords: ["delay", "timer", "pause", "sleep"],
    order: 5,
    /* sb-p0k. The one thing a reader cannot see from "Wait for 2m": the
     * compiled form of this block is a DELAYED SEND, not a sleep - the chart
     * stays live and answers events for the whole duration. PROPOSED, like
     * the key itself; a shipped `core.*` type carrying presentation metadata
     * this specific is a Phase-B question. */
    badge: "timer",
  },
};

/*
 * core.on_event - an interrupt handler, valid inside an `interrupts` slot and
 * nowhere else. It declares `kinds: ["interrupt_handler"]` and nothing else,
 * and that single tag is the whole placement rule in BOTH directions: a
 * handler dropped into `body` fails because `body` declares `["step"]`, and a
 * step dropped into `interrupts` fails because `interrupts` declares
 * `["interrupt_handler"]`. There is no placement check in this descriptor and
 * there is not supposed to be one.
 *
 * ## sb-0o4: `cond`, and a MIRROR DIVERGENCE flagged in the open
 *
 * The `cond` field below is PROPOSED. `core.on_event` is a SHIPPED `core.*`
 * type and `lib/statifier_blocks/core/on_event.ex` declares no such key, so
 * this descriptor is no longer a verbatim transcription: it is the shipped
 * type plus one proposed config field. Same standing as `core.parallel`'s
 * `complete` (sb-dxs), `core.wait`'s badge (sb-p0k) and `core.invoke`
 * (sb-nt3), and flagged the same way - in the open, at the point of
 * divergence, so nobody reads this mirror as evidence of what the package
 * ships.
 *
 * What it means: an interrupt rule that fires only when a predicate holds.
 * `core.on_event` could previously only ask "did this event arrive"; a rule
 * that also asks "and is the money still unmoved" had to be a host type, and
 * the demo documents grew `myapp.guarded_on_event` to say it. That crutch is
 * retired (2026-08-28, umbrella D12) and this key is what replaced it.
 *
 * The field is `expression`, which is the SAME declared type a branch arm's
 * condition uses - so it gets the same one-line mono control in the config
 * form, and `datamodel.js`'s condition pane picks it up without learning a
 * type name (`conditionFields` filters on the declared type, never on a list
 * of types).
 *
 * What is still open, for Phase B rather than for this descriptor:
 *
 *   - the compiled form. A guard on an interrupt rule is a `cond` on the
 *     transition the rail emits, which is the obvious reading, but ADR-0004
 *     has not said so and nothing here compiles anything;
 *   - whether an interrupt rule with a guard that never holds deserves a
 *     document-level finding. `run_cp_three_ds_timeout` in `fixtures/runs.json`
 *     is exactly that case written down, and it is recorded as a fixture
 *     rather than as an editor affordance on purpose.
 *
 * Backward compatibility is load-bearing and asserted in the selftest: every
 * stored `core.on_event` that predates this key must decode and validate
 * exactly as it did before, so an ABSENT `cond` is silent and only a PRESENT
 * one is checked. `event` and `outcome` keep their indices - a proposed key
 * does not renumber a shipped one (the `core.parallel` precedent above), which
 * is why `cond` is appended rather than slotted between them where it would
 * read better.
 */
const ON_EVENT_OUTCOMES = ["abandon", "resume"];

const coreOnEvent = {
  name: "core.on_event",
  currentVersion: 1,
  slots: () => [],
  configSchema: () => [
    {
      key: "event",
      type: "string",
      label: "When this event arrives",
      required: true,
      default: "",
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
      // PROPOSED (sb-0o4) - see the divergence note above this descriptor.
      // Appended, not inserted: `event` is fields[0] and `outcome` is
      // fields[1] in the shipped type, and a proposed key does not renumber
      // a shipped one.
      key: "cond",
      type: "expression",
      label: "Only when",
      required: false,
      default: "",
    },
  ],
  validateConfig: (config) => {
    const findings = [];

    if (!isEventName(config.event)) {
      findings.push({ key: "event", message: "must be an event name, like order.cancelled" });
    }
    if (!oneOf(config.outcome, ON_EVENT_OUTCOMES)) {
      findings.push({ key: "outcome", message: 'pick "abandon" or "resume"' });
    }
    // An ABSENT `cond` is silent, so a document stored before this key
    // existed validates exactly as it did before. A key that IS present has
    // to carry an expression: a stored `null` or `""` is not "no guard", it
    // is a guard an author started and did not finish (ADR-0001 d6's reading
    // of absent-versus-null, applied to the one optional key here).
    if ("cond" in config && !nonEmptyString(config.cond)) {
      findings.push({ key: "cond", message: "a guard, if present, needs an expression" });
    }

    return verdict(findings);
  },
  io: () => ({ kinds: ["interrupt_handler"] }),
  paletteEntry: {
    label: "On event",
    group: "Structure",
    description: "Interrupts the group it sits in when an event arrives.",
    icon: "bolt",
    keywords: ["interrupt", "cancel", "event", "handler"],
    order: 6,
  },
};

/** The seven `core.*` entries, keyed by type name (`Palette.core_types/0`). */
export const coreTypes = {
  "core.sequence": coreSequence,
  "core.group": coreGroup,
  "core.branch": coreBranch,
  "core.parallel": coreParallel,
  "core.wait": coreWait,
  "core.resumable_group": coreResumableGroup,
  "core.on_event": coreOnEvent,
};

/* -------------------------------------------------- the demo vocabulary */

/*
 * Three host-namespaced demo types, here to prove that custom registration
 * needs nothing from the editor beyond the same callbacks the core types
 * answer - a different group heading, a different icon, one of them with a
 * slot of its own, and one exercising `migrateConfig`.
 *
 * The invoke types they name are the campaign's approved example flavors and
 * nothing else: `myapp:authorize`, `myapp:capture`, `myapp:signup`. A block
 * type never runs anything; it names an invoke type that a host registers a
 * runtime handler for separately (ADR-0002's two-registry seam).
 */
const myappAuthorize = {
  name: "myapp.authorize",
  invokeType: "myapp:authorize",
  // Version 2, so ADR-0001's worked example - which stores this type at
  // `type_version` 2 - resolves without migrating, and a document stored at
  // 1 exercises the migration path below.
  currentVersion: 2,
  slots: () => [],
  configSchema: () => [
    {
      key: "assign_to",
      type: "string",
      label: "Write the decision to",
      required: true,
      default: "authorization",
    },
    {
      key: "timeout",
      type: "duration",
      label: "Timeout",
      required: false,
      default: "PT30S",
    },
  ],
  validateConfig: (config) => {
    const findings = [];

    if (!isIdentifier(config.assign_to)) {
      findings.push({ key: "assign_to", message: "must be a bare lowercase identifier" });
    }
    if ("timeout" in config && !isDuration(config.timeout)) {
      findings.push({ key: "timeout", message: "must be an ISO-8601 duration, like PT30S" });
    }

    return verdict(findings);
  },
  io: () => ({ kinds: ["step"], produces: "myapp.authorization" }),
  // v1 spelled the target key `field`; v2 spells it `assign_to`. A single
  // hop, straight from the stored version to current, and the migrated
  // config is never written back (ADR-0002 decision 8).
  migrateConfig: (from, config) => {
    if (from !== 1) return err({ tag: "no_migration_from", from });

    const { field, ...rest } = config;
    return ok({ ...rest, assign_to: field ?? "authorization" });
  },
  paletteEntry: {
    label: "Authorize card",
    group: "Card processing",
    description: "Authorizes the transaction against the card network.",
    icon: "credit-card",
    keywords: ["authorize", "card", "payment"],
    order: 0,
    accentToken: "--sb-accent-myapp",
  },
};

const myappCapture = {
  name: "myapp.capture",
  invokeType: "myapp:capture",
  currentVersion: 1,
  slots: () => [],
  configSchema: () => [
    {
      key: "amount_key",
      type: "string",
      label: "Amount read from",
      required: true,
      default: "amount",
    },
    {
      key: "retries",
      type: "integer",
      label: "Retries",
      required: false,
      default: 2,
    },
  ],
  validateConfig: (config) => {
    const findings = [];

    if (!isIdentifier(config.amount_key)) {
      findings.push({ key: "amount_key", message: "must be a bare lowercase identifier" });
    }
    if ("retries" in config && !Number.isInteger(config.retries)) {
      findings.push({ key: "retries", message: "must be a whole number" });
    }

    return verdict(findings);
  },
  io: () => ({ kinds: ["step"], consumes: "myapp.authorization" }),
  paletteEntry: {
    label: "Capture funds",
    group: "Card processing",
    description: "Captures a previously authorized amount.",
    icon: "banknotes",
    keywords: ["capture", "settle", "payment"],
    order: 1,
    /* The layering proof (sb-957): its own token rather than the family's.
     * Light and dark resolve it to the family colour, host-brand does not. */
    accentToken: "--sb-accent-myapp-capture",
  },
};

/*
 * The one demo type with a slot of its own, so the spike has a non-core
 * container to drag into - and, because that slot is `zero_or_one`, a
 * natural exercise of ADR-0005 decision 5's rule 3 (a slot with no room is
 * not a target) outside the core vocabulary.
 */
const myappSignup = {
  name: "myapp.signup",
  invokeType: "myapp:signup",
  currentVersion: 1,
  slots: () => [{ name: "on_complete", arity: "zero_or_one", label: "After this step" }],
  configSchema: () => [
    {
      key: "step",
      type: {
        select: [
          { value: "email", label: "Email address" },
          { value: "profile", label: "Profile details" },
          { value: "confirm", label: "Confirmation" },
        ],
      },
      label: "Wizard step",
      required: true,
      default: "email",
    },
    {
      key: "skippable",
      type: "boolean",
      label: "Author may skip",
      required: false,
      default: false,
    },
  ],
  validateConfig: (config) => {
    const findings = [];

    if (!oneOf(config.step, ["email", "profile", "confirm"])) {
      findings.push({ key: "step", message: 'pick "email", "profile" or "confirm"' });
    }
    if ("skippable" in config && typeof config.skippable !== "boolean") {
      findings.push({ key: "skippable", message: "must be true or false" });
    }

    return verdict(findings);
  },
  io: () => ({ kinds: ["step"], slotAccepts: { on_complete: ["step"] } }),
  paletteEntry: {
    label: "Signup step",
    group: "Signup wizard",
    description: "Collects one step of the signup wizard.",
    icon: "user-plus",
    keywords: ["signup", "wizard", "onboarding"],
    order: 0,
    accentToken: "--sb-accent-myapp",
  },
};

/** The demo `myapp.*` entries, keyed by type name. */
export const demoTypes = {
  "myapp.authorize": myappAuthorize,
  "myapp.capture": myappCapture,
  "myapp.signup": myappSignup,
};

/* ------------------------------------------------------- the registry */

/**
 * A registry is a caller-supplied VALUE, never global state (ADR-0002
 * decision 2). Nothing in the spike holds one across operations; a panel that
 * wants a different set of types builds a different value.
 */
export function createRegistry(types = {}) {
  return { types: { ...types } };
}

/** The core vocabulary alone. */
export function coreRegistry() {
  return createRegistry(coreTypes);
}

/** The core vocabulary plus the demo types - what the spike's shell uses. */
export function spikeRegistry() {
  return createRegistry({ ...coreTypes, ...demoTypes });
}

/**
 * Resolves a type name to a descriptor. Total; never throws (ADR-0002
 * decision 3).
 */
export function fetchType(registry, typeName) {
  const descriptor = registry.types[typeName];
  return descriptor ? ok(descriptor) : err({ tag: "unknown_block_type", type: typeName });
}

/**
 * Resolves a block and, if needed, migrates its config IN MEMORY. Four
 * distinguishable outcomes, checked in this order (`Palette.resolve/2`):
 *
 *   - no entry for the block's type -> `unknown_block_type`;
 *   - versions equal -> the block exactly as given;
 *   - stored version above the descriptor's -> `block_type_too_new`, a hard
 *     error rather than a best-effort read: the code is older than the data,
 *     and guessing is how a rollback corrupts documents;
 *   - stored version below -> one `migrateConfig` hop, never a ladder. The
 *     returned block's `typeVersion` is left AS STORED, so an in-memory
 *     migration can never be mistaken for one written to disk.
 */
export function resolveBlock(registry, node) {
  const found = fetchType(registry, node.type);
  if (!found.ok) return found;

  const descriptor = found.value;
  const stored = node.typeVersion;
  const current = descriptor.currentVersion;

  if (stored === current) return ok({ descriptor, block: node });

  if (stored > current) {
    return err({ tag: "block_type_too_new", id: node.id, version: stored });
  }

  if (typeof descriptor.migrateConfig !== "function") {
    return err({ tag: "migration_failed", id: node.id, reason: "no_migration_available" });
  }

  const migrated = descriptor.migrateConfig(stored, node.config);
  if (!migrated.ok) {
    return err({ tag: "migration_failed", id: node.id, reason: migrated.error });
  }

  return ok({ descriptor, block: { ...node, config: migrated.value } });
}

/* ---------------------------------------------- unresolvable block types */

/*
 * ADR-0005 decision 12. A block whose type does not resolve renders rather
 * than crashing, and never loses data: its config is shown read-only (there
 * is no `configSchema` to drive a form and inventing one would be guessing),
 * its existing children render normally and recursively, and it may be
 * selected, moved and deleted but not config-edited.
 *
 * It is not a drop target for anything, and that falls out of the rules
 * rather than being a special case: `slots()` returns `[]`, so ADR-0005
 * decision 5's rule 1 - the slot must be DECLARED - excludes every slot it
 * carries. (Decision 12 does allow reordering blocks WITHIN one of its
 * existing slots, since order asks the parent's type nothing. The shipped
 * `Assignability.valid_targets/4` does not offer those positions either, and
 * the spike mirrors the shipped behaviour rather than the sentence.)
 */
export function placeholderDescriptor(typeName, reason) {
  return {
    name: typeName,
    unresolved: true,
    reason,
    currentVersion: 1,
    slots: () => [],
    configSchema: () => [],
    validateConfig: () => null,
    // `{}` rather than `{ kinds: [] }`: ADR-0003 decision 5 degrades an
    // absent declaration to `["step"]`, which is what lets decision 12's
    // "it may be selected, moved, and deleted" actually hold - an
    // unresolvable block with no kinds at all could be dragged nowhere.
    io: () => ({}),
    paletteEntry: {
      label: typeName,
      group: "Unavailable",
      description: unresolvedMessage(reason),
      icon: null,
      keywords: [],
      order: 0,
      layout: "stack",
    },
  };
}

function unresolvedMessage(reason) {
  switch (reason?.tag) {
    case "unknown_block_type":
      return `No block type named ${reason.type} is available.`;
    case "block_type_too_new":
      return "This block was authored by a newer version of its block type.";
    case "migration_failed":
      return "This block's config could not be migrated to the current version.";
    default:
      return "This block type is unavailable.";
  }
}

/* --------------------------------------- the editor's own config field */

/*
 * sb-jvz. `label` is the author's own words for one block, and EVERY card
 * titles itself from it. It is therefore the editor's field, not a block
 * type's: a type that declared one was writing boilerplate, and a type that
 * forgot lost its author's words silently - `core.invoke` stored a label the
 * canvas titled from and the config form could not edit, because no type had
 * declared it.
 *
 * So the editor injects it, once, into every descriptor it resolves. A block
 * type declares what its own work needs and nothing more; the editor owns the
 * one field that is about authoring rather than about behaviour. A host type
 * that still declares `label` is not an error - its declaration is dropped in
 * favour of this one, so the field cannot be redefined out from under the
 * canvas, which reads it by schema (a `string` field keyed `label`) and never
 * by type name.
 *
 * Deliberately NO `default`. It is optional, and a default would seed
 * `{"label": ""}` into the config of every block ever inserted - bytes in
 * every document to say nothing at all.
 *
 * sb-ed7: it DOES carry a `placeholder`, and that is the same ownership
 * argument one step further. Placeholders were previously chosen by control
 * type in `inspector.js` (an expression field says "an expression", a
 * duration says "PT1H30M"), and a `string` field has no type-level hint to
 * offer - so the first field every author meets rendered blank beside
 * siblings that suggested their own shape. The editor owns this field, so
 * the editor owns its hint: the placeholder is declared HERE, next to the
 * label and the optionality, rather than special-cased downstream by key or
 * by type name. `panes.js` carries whatever a field declares and
 * `inspector.js` prefers it over the control-type default; neither one knows
 * that `label` exists.
 *
 * Whether a HOST type may declare `placeholder` on its own fields is a
 * PROPOSAL, not a decision - see the README section of the same name. Nothing
 * here needs it answered: the mechanism is the same either way, and today the
 * editor's own field is the only declarer.
 */
export const LABEL_FIELD = Object.freeze({
  key: "label",
  type: "string",
  label: "Step name",
  required: false,
  placeholder: "Authorize the card",
});

/*
 * The injected field's own check, which moves here for the same reason the
 * field does: the editor owns the field, so the editor owns what makes it
 * valid. An absent key is fine - the field is optional - and `null` is not,
 * because ADR-0001 decision 6 admits `null` as a stored config value and the
 * canvas would have to render it as a title.
 */
function checkLabel(config) {
  if (!config || !Object.hasOwn(config, "label")) return [];
  if (typeof config.label === "string") return [];

  return [{ key: "label", message: "must be text" }];
}

/*
 * One wrapper per descriptor, cached on the descriptor itself: `describe` is
 * called for every block on every layout pass, and a fresh object each time
 * would make descriptor identity meaningless to anything holding one.
 */
const injected = new WeakMap();

/**
 * A resolved descriptor as the EDITOR sees it: the type's own declarations,
 * plus `LABEL_FIELD` at the head of `configSchema/1` and its check at the
 * head of `validateConfig/1`.
 *
 * Error semantics are the type's, unchanged: a `configSchema/1` that raises
 * for config `validate_config/1` would refuse (ADR-0002 decision 6 permits
 * exactly that) still raises through this wrapper, so the callers that
 * already have a degradation policy for it keep owning that policy. This
 * wrapper adds a field; it does not add a rescue.
 */
export function withEditorFields(descriptor) {
  if (!descriptor || descriptor.unresolved === true) return descriptor;

  const cached = injected.get(descriptor);
  if (cached) return cached;

  const wrapped = {
    ...descriptor,
    configSchema: (config) => [
      { ...LABEL_FIELD },
      ...(descriptor.configSchema(config) ?? []).filter((field) => field?.key !== "label"),
    ],
    validateConfig: (config) => {
      const findings = [...checkLabel(config), ...(descriptor.validateConfig(config) ?? [])];
      return verdict(findings);
    },
  };

  injected.set(descriptor, wrapped);
  return wrapped;
}

/**
 * The descriptor to render `node` with: the resolved one, or decision 12's
 * placeholder. Total - it is the call the canvas makes for every block, and
 * an unresolvable type must never be a crash.
 *
 * Returns `{ descriptor, block, unresolved }`, where `block` carries the
 * in-memory-migrated config when a migration ran and is `node` untouched
 * otherwise. The document's own bytes are never rewritten by this call.
 *
 * A resolved descriptor arrives carrying the editor's injected `label`
 * field (`withEditorFields`); the placeholder does not. That asymmetry IS
 * decision 12: an unresolvable block has no form at all, so injecting an
 * editable field into it would be offering to edit the config of a block
 * whose type nothing can validate.
 *
 * This is the one injection seam. Every surface that reads a schema or runs
 * a check - the canvas, the config form, the command gate - reaches its
 * descriptor through here, so none of them has to know the field exists.
 * `fetchType` is deliberately NOT wrapped: it answers "what did the host
 * register", which is a question about the registry rather than about how a
 * block is edited.
 */
export function describe(registry, node) {
  const resolved = resolveBlock(registry, node);

  if (resolved.ok) {
    return {
      ...resolved.value,
      descriptor: withEditorFields(resolved.value.descriptor),
      unresolved: false,
    };
  }

  return {
    descriptor: placeholderDescriptor(node.type, resolved.error),
    block: node,
    unresolved: true,
    reason: resolved.error,
  };
}

/* ------------------------------------------- presentation metadata (d10) */

const PALETTE_ENTRY_DEFAULTS = {
  group: "Other",
  description: "",
  icon: null,
  keywords: [],
  order: 0,
  layout: "stack",
  slotStyle: {},
  /* sb-957. The name of a `--sb-*` custom property this type's cards and
   * palette rows take their accent from, or `null` for the editor's own.
   * A NAME, never a colour - the same discipline `icon` is under, and for
   * the same reason: a descriptor that carried a hex value would be a block
   * type deciding what it looks like in a theme it has never seen. Whether
   * this belongs in ADR-0005 decision 10's metadata is a W6 finding. */
  accentToken: null,
  /* sb-nt3. A short chip a block type may declare for its card header - the
   * one-line "what is this, really" a label has no room for. A STRING the
   * type declares, under the same discipline as `accentToken` and `icon`:
   * the editor renders whatever is here and never learns a type name.
   * PROPOSED - whether it belongs in ADR-0005 decision 10's metadata is a
   * Phase-B finding, and the two declarations that exist (`core.wait` below
   * and `core.invoke` in `js/proposed-core.js`) are the evidence for it.
   *
   * The default lives here rather than in the proposal file so that
   * `paletteEntryFor(descriptor).badge` is total for every descriptor, the
   * way every other key in this map is.
   *
   * sb-p0k: `core.wait` now declares one too, and `badgeFor` below is the
   * normalizer the renderer reads it through. */
  badge: null,
  /* sb-dxs. What the JOIN MARKER under a side-by-side arrangement says, as a
   * FUNCTION of config rather than a string - the words depend on how the
   * block is configured, which is exactly what the other d10 keys do not have
   * to cope with. `null` means "the editor's own word", which is what every
   * type that declares nothing keeps.
   *
   * A callback and not a config key on the block, because the join marker is
   * chrome the editor draws and not a slot the author fills; and a callback
   * and not a renderer case, because the moment `render.js` asks "is this a
   * parallel" the d10 promise is gone for every host type of the same shape.
   *
   * PROPOSED, on the same footing as `badge` and `accentToken`: whether a
   * CALLBACK belongs in decision 10's metadata at all - every other key there
   * is inert data - is a Phase-B finding, and `core.parallel`'s declaration
   * above is the evidence for it. */
  joinLabel: null,
};

/*
 * How long a badge is allowed to be.
 *
 * A chip is a chip: it sits on a card that is already carrying a title, a
 * caption and up to three config chips, and at depth 7 the card is narrow. A
 * badge long enough to wrap is a description, and a description already has a
 * home - `paletteEntry.description`, which the palette browser and the "+"
 * picker both show. 24 characters fits "calls the host" and "timer" with room
 * to spare and refuses a sentence.
 */
const BADGE_MAX = 24;

/**
 * The badge a palette entry declares, trimmed, or `null`.
 *
 * Under exactly the discipline `accentTokenFor` is under, and for the same
 * reason: a host that declares something malformed gets the ordinary card,
 * never a broken one. A non-string, an empty or all-whitespace string, and
 * anything past `BADGE_MAX` all degrade to no badge rather than to a chip
 * that eats the title's width.
 *
 * Newlines are refused rather than collapsed. A badge with a newline in it is
 * a host meaning something the chip cannot express, and silently flattening
 * it would hide that.
 */
export function badgeFor(entry) {
  const value = entry && typeof entry === "object" ? entry.badge : null;
  if (typeof value !== "string" || /[\n\r\t]/.test(value)) return null;

  const text = value.trim();
  return text === "" || text.length > BADGE_MAX ? null : text;
}

/**
 * The word the join marker under a side-by-side arrangement carries.
 *
 * `JOIN_LABEL_FALLBACK` is what the renderer said before sb-dxs and what it
 * still says for every type that declares no callback, so a block that gained
 * nothing here renders byte-identically.
 *
 * The refusals are `badgeFor`'s, for `badgeFor`'s reason - the marker is a
 * small pill under a fan and a sentence in it pushes the columns apart - plus
 * one this key needs and the badge does not: the callback is HOST code called
 * during layout, so it is called inside a try and a throw degrades to the
 * fallback. A host type with a bug in its `joinLabel` gets the ordinary
 * marker; it does not take the canvas down with it.
 */
const JOIN_LABEL_FALLBACK = "continue";
const JOIN_LABEL_MAX = 24;

export function joinLabelFor(entry, config = {}) {
  const declared = entry && typeof entry === "object" ? entry.joinLabel : null;
  if (typeof declared !== "function") return JOIN_LABEL_FALLBACK;

  let value;
  try {
    value = declared(config);
  } catch {
    return JOIN_LABEL_FALLBACK;
  }

  if (typeof value !== "string" || /[\n\r\t]/.test(value)) return JOIN_LABEL_FALLBACK;

  const text = value.trim();
  return text === "" || text.length > JOIN_LABEL_MAX ? JOIN_LABEL_FALLBACK : text;
}

/**
 * ADR-0005 decision 10's metadata with every default filled in. Every key is
 * optional except a label, which defaults to the type name, because a block
 * type declaring no presentation metadata at all must still render.
 */
export function paletteEntryFor(descriptor) {
  return {
    ...PALETTE_ENTRY_DEFAULTS,
    label: descriptor.name,
    ...(descriptor.paletteEntry ?? {}),
  };
}

/**
 * The palette browser's view: entries grouped by their `group`, sorted group
 * NAME, then `order`, then label - `ViewModel`'s `palette_groups/1` rule
 * exactly (ADR-0005 decision 10's grouping rule). Presentation only; nothing
 * here decides validity.
 *
 * Group name rather than lowest `order` within the group, which is the
 * tempting alternative and is wrong: `order` is documented as a sort position
 * WITHIN a group, and reaching across groups with it makes a host's palette
 * reorder itself the moment a group's lowest-ordered entry changes.
 */
export function paletteGroups(registry) {
  const entries = Object.values(registry.types).map((descriptor) => ({
    name: descriptor.name,
    entry: paletteEntryFor(descriptor),
  }));

  const groups = new Map();

  for (const item of entries) {
    const name = item.entry.group;
    if (!groups.has(name)) groups.set(name, []);
    groups.get(name).push(item);
  }

  return [...groups.entries()]
    .map(([name, items]) => ({
      name,
      entries: items.sort(
        (a, b) => a.entry.order - b.entry.order || compareUtf8(a.entry.label, b.entry.label)
      ),
    }))
    .sort((a, b) => compareUtf8(a.name, b.name));
}

/* --------------------------------------------- assignability primitives */

/*
 * ADR-0003 decision 5's permissive defaults, which `targets.js` consults and
 * nothing else in the spike should re-derive: an absent `io` is `{}`, an
 * absent `kinds` is `["step"]`, and an absent `slotAccepts` entry is "any",
 * spelled here as `null`.
 */
export function kindsOf(descriptor, config) {
  return descriptor.io?.(config)?.kinds ?? ["step"];
}

export function slotAccepts(descriptor, config, slot) {
  const accepts = descriptor.io?.(config)?.slotAccepts ?? {};
  return slot in accepts ? accepts[slot] : null;
}

/**
 * ADR-0003 decision 3's structural verdict for placing a child in a slot:
 * "any" admits everything, otherwise the slot's accepted kinds and the
 * child's own kinds must intersect.
 */
export function admits(parent, parentConfig, slot, child, childConfig) {
  const accepted = slotAccepts(parent, parentConfig, slot);
  if (accepted === null) return true;

  return kindsOf(child, childConfig).some((kind) => accepted.includes(kind));
}
