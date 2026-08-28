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
 * A field type is ADR-0002 decision 7's closed set: the string `"string"`,
 * `"integer"`, `"boolean"`, `"expression"` or `"duration"`, or the object
 * `{ select: [{ value, label }] }` or `{ list: <field type> }`. Closed on
 * purpose - the config form must be able to render every one of them, and an
 * open set makes that unprovable.
 */

import { err, ok } from "./document.js";

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

const asList = (value) => (Array.isArray(value) ? value : value === undefined ? [] : [value]);

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
    const arms = config.arms ?? [];
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
 */
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
  configSchema: () => [
    {
      key: "lanes",
      type: { list: "string" },
      label: "Lanes",
      required: true,
      default: [],
    },
  ],
  validateConfig: (config) => {
    const lanes = config.lanes ?? [];
    if (!Array.isArray(lanes)) {
      return [{ key: "lanes", message: "must be a list of lane names" }];
    }

    const findings = [];
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
  ],
  validateConfig: (config) => {
    const findings = [];

    if (!isEventName(config.event)) {
      findings.push({ key: "event", message: "must be an event name, like order.cancelled" });
    }
    if (!oneOf(config.outcome, ON_EVENT_OUTCOMES)) {
      findings.push({ key: "outcome", message: 'pick "abandon" or "resume"' });
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

/**
 * The descriptor to render `node` with: the resolved one, or decision 12's
 * placeholder. Total - it is the call the canvas makes for every block, and
 * an unresolvable type must never be a crash.
 *
 * Returns `{ descriptor, block, unresolved }`, where `block` carries the
 * in-memory-migrated config when a migration ran and is `node` untouched
 * otherwise. The document's own bytes are never rewritten by this call.
 */
export function describe(registry, node) {
  const resolved = resolveBlock(registry, node);

  if (resolved.ok) {
    return { ...resolved.value, unresolved: false };
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
};

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
 * The palette browser's view: entries grouped by their `group`, groups in
 * first-appearance order of their lowest `order`, entries sorted by `order`
 * then label. Presentation only - nothing here decides validity.
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
        (a, b) => a.entry.order - b.entry.order || a.entry.label.localeCompare(b.entry.label)
      ),
    }))
    .sort((a, b) => a.entries[0].entry.order - b.entries[0].entry.order
      || a.name.localeCompare(b.name));
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
