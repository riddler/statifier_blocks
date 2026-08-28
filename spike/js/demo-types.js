/*
 * spike/js/demo-types.js - the host vocabulary the demo documents are written
 * against.
 *
 * `palette.js` mirrors the real `core.*` types plus the three `myapp.*`
 * entries that exercise the extension seam itself (a slot, a migration, a
 * second group heading). The demo documents in `fixtures/documents/` name
 * more host types than that, because a card-processing workflow that only
 * ever authorizes and captures is not a workflow worth laying out. Those
 * extra descriptors live here rather than in `palette.js` for two reasons:
 *
 *   - `palette.js` is transcribed from `lib/statifier_blocks/core/*.ex` and
 *     its `demoTypes` are the seam demonstration. Padding it with fixture
 *     furniture would blur what it is a mirror OF.
 *   - a host registering block types is supposed to be a caller-supplied
 *     value (ADR-0002 decision 2), so a second file composing a bigger
 *     registry is the mechanism working as designed, not a workaround.
 *
 * Every invoke type here is in the campaign's approved example namespace
 * (`myapp:*`) and every one of them is named by a committed fixture.
 *
 * ONE type the fixtures name is deliberately absent: `myapp.legacy_check`.
 * That is the ADR-0005 decision 12 case - the block whose type does not
 * resolve, planted at depth 7 of card-processing.json so the unavailable
 * chrome is exercised deep in the tree. Registering it would delete the test.
 */

/* ------------------------------------------------------- the host accent
 *
 * sb-957. Every type in this file belongs to one host, so every one of them
 * points at the host's own accent token. The value is declared in
 * `css/tokens.css` under "demo host block accents" and overridden by
 * `css/themes/host-brand.css`; nothing here knows what colour it is, which is
 * the point - a host declares an identity, a theme decides what it looks
 * like, and the editor stays out of both conversations.
 *
 * The one exception lives in `palette.js`: `myapp.capture` points at
 * `--sb-accent-myapp-capture` instead, which resolves to this same colour in
 * light and dark and to a different one under host-brand.
 */
const HOST_ACCENT = "--sb-accent-myapp";

/* ------------------------------------------------------- shared checks */

const IDENTIFIER = /^[a-z][a-z0-9_]*$/;
const INVOKE_TYPE = /^myapp:[a-z][a-z0-9_]*$/;
const DURATION = /^P(?!$)(\d+Y)?(\d+M)?(\d+W)?(\d+D)?(T(?!$)(\d+H)?(\d+M)?(\d+S)?)?$/;
const EVENT_NAME = /^[A-Za-z_][A-Za-z0-9_.\-]*$/;

const nonEmptyString = (value) => typeof value === "string" && value !== "";
const isIdentifier = (value) => nonEmptyString(value) && IDENTIFIER.test(value);
const isDuration = (value) => nonEmptyString(value) && DURATION.test(value);
const isEventName = (value) => nonEmptyString(value) && EVENT_NAME.test(value);
const verdict = (findings) => (findings.length === 0 ? null : findings);

/*
 * Two config fields every demo step carries, and the reason each is declared
 * rather than left as undeclared stored data:
 *
 *   `label`   the author's own words for this step. The canvas reads it as
 *             the card's title, falling back to the palette label - which is
 *             a general rule over the SCHEMA (a declared string field keyed
 *             `label`), not a branch on any type name.
 *   `invoke_type`  the host handler this step names. ADR-0002's two-registry
 *             seam: a block type NAMES an invoke type, it never runs one.
 */
const labelField = {
  key: "label",
  type: "string",
  label: "Step name",
  required: false,
  default: "",
};

const invokeTypeField = {
  key: "invoke_type",
  type: "string",
  label: "Invoke type",
  required: true,
  default: "",
};

function checkCommon(config) {
  const findings = [];

  if (!nonEmptyString(config.invoke_type) || !INVOKE_TYPE.test(config.invoke_type)) {
    findings.push({ key: "invoke_type", message: 'must look like "myapp:capture"' });
  }
  if ("label" in config && typeof config.label !== "string") {
    findings.push({ key: "label", message: "must be text" });
  }

  return findings;
}

/**
 * A leaf step: no slots, the two common fields plus whatever else it
 * declares, and `kinds: ["step"]` unless it says otherwise.
 */
function step({
  name,
  currentVersion = 1,
  label,
  group,
  description,
  icon,
  order = 0,
  keywords = [],
  fields = [],
  check = () => [],
  io = { kinds: ["step"] },
  migrateConfig,
}) {
  const descriptor = {
    name,
    currentVersion,
    slots: () => [],
    configSchema: () => [labelField, invokeTypeField, ...fields],
    validateConfig: (config) => verdict([...checkCommon(config), ...check(config)]),
    io: () => io,
    paletteEntry: { label, group, description, icon, keywords, order, accentToken: HOST_ACCENT },
  };

  if (migrateConfig) descriptor.migrateConfig = migrateConfig;

  return descriptor;
}

/**
 * An interrupt rule: `kinds: ["interrupt_handler"]` and nothing else, which
 * is the whole placement rule in both directions (see `core.on_event`'s note
 * in palette.js). These two exist because `core.on_event` carries no guard
 * and no duration, and the fixture needs both to have something to draw an
 * exit edge FOR. Whether they earn an ADR-0002 amendment is a W6 finding.
 */
const OUTCOMES = [
  { value: "abandon", label: "Abandon - leave the group" },
  { value: "resume", label: "Resume - re-enter the group" },
];

const outcomeField = {
  key: "outcome",
  type: { select: OUTCOMES },
  label: "Then",
  required: true,
  default: "abandon",
};

const guardField = {
  key: "cond",
  type: "expression",
  label: "Only when",
  required: false,
  default: "",
};

function checkOutcome(config) {
  return OUTCOMES.some((option) => option.value === config.outcome)
    ? []
    : [{ key: "outcome", message: 'pick "abandon" or "resume"' }];
}

function checkGuard(config) {
  if (!("cond" in config)) return [];
  return nonEmptyString(config.cond)
    ? []
    : [{ key: "cond", message: "a guard, if present, needs an expression" }];
}

/* --------------------------------------------------- card processing */

const myappIntake = step({
  name: "myapp.intake",
  label: "Intake",
  group: "Card processing",
  description: "Accepts the incoming payment request and normalizes it.",
  icon: "inbox",
  order: 0,
  io: { kinds: ["step"], produces: "myapp.payment_request" },
});

const myappRiskRating = step({
  name: "myapp.risk_rating",
  label: "Risk rating",
  group: "Card processing",
  description: "Scores the transaction against the fraud model.",
  icon: "shield",
  order: 2,
  io: { kinds: ["step"], produces: "myapp.risk_rating" },
});

const myappManualFlag = step({
  name: "myapp.manual_flag",
  label: "Manual flag",
  group: "Card processing",
  description: "Marks the transaction for a human to look at.",
  icon: "flag",
  order: 3,
});

const myappBalanceCheck = step({
  name: "myapp.balance_check",
  label: "Balance check",
  group: "Card processing",
  description: "Reads the available balance on the funding source.",
  icon: "scale",
  order: 4,
  io: { kinds: ["step"], produces: "myapp.balance" },
});

/*
 * `type_version` 2 in the fixture, so this descriptor is at 2 as well and the
 * block resolves without migrating - the mirror case of `myapp.authorize`,
 * whose v1-to-v2 hop palette.js already exercises.
 */
const myappThreeDs = step({
  name: "myapp.three_ds_challenge",
  currentVersion: 2,
  label: "3-D Secure",
  group: "Card processing",
  description: "Sends the cardholder a step-up authentication challenge.",
  icon: "device-phone",
  order: 5,
});

const myappPark = step({
  name: "myapp.park",
  label: "Park",
  group: "Card processing",
  description: "Puts the work on a queue and waits for a human.",
  icon: "pause",
  order: 6,
  fields: [
    {
      key: "queue",
      type: "string",
      label: "Queue",
      required: true,
      default: "manual_review",
    },
  ],
  check: (config) =>
    isIdentifier(config.queue)
      ? []
      : [{ key: "queue", message: "must be a bare lowercase identifier" }],
});

const myappResolveReview = step({
  name: "myapp.resolve_review",
  label: "Resolve review",
  group: "Card processing",
  description: "Applies the reviewer's decision and continues.",
  icon: "check",
  order: 7,
});

const myappReceipt = step({
  name: "myapp.receipt",
  label: "Receipt",
  group: "Card processing",
  description: "Renders the receipt for the completed transaction.",
  icon: "receipt",
  order: 8,
});

/* --------------------------------------------------------- messaging */

const myappNotify = step({
  name: "myapp.notify",
  label: "Notify",
  group: "Messaging",
  description: "Sends one templated message.",
  icon: "megaphone",
  order: 0,
  fields: [
    {
      key: "template",
      type: "string",
      label: "Template",
      required: true,
      default: "",
    },
  ],
  check: (config) =>
    isIdentifier(config.template)
      ? []
      : [{ key: "template", message: "must be a bare lowercase identifier" }],
});

/* ------------------------------------------------------ signup wizard */

const SIGNUP_STEPS = [
  "account",
  "send_verification",
  "company_details",
  "preferences",
  "confirm",
];

const myappSignupStep = step({
  name: "myapp.signup_step",
  label: "Signup step",
  group: "Signup wizard",
  description: "Collects one step of the signup wizard.",
  icon: "user-plus",
  order: 0,
  fields: [
    {
      key: "step",
      type: {
        select: SIGNUP_STEPS.map((value) => ({ value, label: value.replace(/_/g, " ") })),
      },
      label: "Wizard step",
      required: true,
      default: "account",
    },
  ],
  check: (config) =>
    SIGNUP_STEPS.includes(config.step)
      ? []
      : [{ key: "step", message: `pick one of ${SIGNUP_STEPS.join(", ")}` }],
});

const myappProvision = step({
  name: "myapp.provision",
  label: "Provision",
  group: "Signup wizard",
  description: "Creates the account's workspace once signup completes.",
  icon: "sparkles",
  order: 1,
});

/* ---------------------------------------------------- interrupt rules */

const myappGuardedOnEvent = {
  name: "myapp.guarded_on_event",
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
    guardField,
    outcomeField,
  ],
  validateConfig: (config) =>
    verdict([
      ...(isEventName(config.event)
        ? []
        : [{ key: "event", message: "must be an event name, like review.resolved" }]),
      ...checkGuard(config),
      ...checkOutcome(config),
    ]),
  io: () => ({ kinds: ["interrupt_handler"] }),
  paletteEntry: {
    label: "On event, when",
    group: "Interrupt rules",
    description: "Interrupts the group when an event arrives and a guard holds.",
    icon: "bolt",
    keywords: ["interrupt", "guard", "condition", "event"],
    order: 0,
    accentToken: HOST_ACCENT,
  },
};

const myappTimeoutRule = {
  name: "myapp.timeout_rule",
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
    guardField,
    outcomeField,
  ],
  validateConfig: (config) =>
    verdict([
      ...(isDuration(config.after)
        ? []
        : [{ key: "after", message: "must be an ISO-8601 duration, like PT15M" }]),
      ...checkGuard(config),
      ...checkOutcome(config),
    ]),
  io: () => ({ kinds: ["interrupt_handler"] }),
  paletteEntry: {
    label: "Timeout",
    group: "Interrupt rules",
    description: "Interrupts the group once a duration has elapsed.",
    icon: "clock-alert",
    keywords: ["interrupt", "timeout", "deadline", "expire"],
    order: 1,
    accentToken: HOST_ACCENT,
  },
};

/* ---------------------------------------------------------- the value */

/** Every host type the demo documents name, except the unresolvable one. */
export const fixtureTypes = {
  "myapp.intake": myappIntake,
  "myapp.risk_rating": myappRiskRating,
  "myapp.manual_flag": myappManualFlag,
  "myapp.balance_check": myappBalanceCheck,
  "myapp.three_ds_challenge": myappThreeDs,
  "myapp.park": myappPark,
  "myapp.resolve_review": myappResolveReview,
  "myapp.receipt": myappReceipt,
  "myapp.notify": myappNotify,
  "myapp.signup_step": myappSignupStep,
  "myapp.provision": myappProvision,
  "myapp.guarded_on_event": myappGuardedOnEvent,
  "myapp.timeout_rule": myappTimeoutRule,
};
