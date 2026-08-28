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

const nonEmptyString = (value) => typeof value === "string" && value !== "";
const isIdentifier = (value) => nonEmptyString(value) && IDENTIFIER.test(value);
const verdict = (findings) => (findings.length === 0 ? null : findings);

/*
 * The one config field every demo step carries, and the reason it is declared
 * rather than left as undeclared stored data:
 *
 *   `invoke_type`  the host handler this step names. ADR-0002's two-registry
 *             seam: a block type NAMES an invoke type, it never runs one.
 *
 * `label` used to be declared beside it, and no longer is (sb-jvz). The
 * canvas titles EVERY card from `label`, so declaring it here was writing the
 * editor's own field: a type that forgot lost its author's words, which is
 * exactly what happened to the proposed `core.invoke`. The editor now injects
 * it into every descriptor it resolves (`withEditorFields` in palette.js), so
 * these types get it - and its check - without asking, and so does every type
 * a host writes next.
 */
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

  /* No `label` check here: the editor injects the field, so the editor checks
   * it, for every type rather than only for these. */

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
    configSchema: () => [invokeTypeField, ...fields],
    validateConfig: (config) => verdict([...checkCommon(config), ...check(config)]),
    io: () => io,
    paletteEntry: { label, group, description, icon, keywords, order, accentToken: HOST_ACCENT },
  };

  if (migrateConfig) descriptor.migrateConfig = migrateConfig;

  return descriptor;
}

/* ------------------------------- RETIRED 2026-08-28: the interrupt rules
 *
 * `myapp.guarded_on_event` and `myapp.timeout_rule` used to live here, and
 * they are gone (sb-0o4; operator ruling D12 in the umbrella's
 * `docs/decisions.md`, 2026-08-28). Both were CRUTCHES, and the note they
 * carried said so: they existed because the core vocabulary could not express
 * a guarded interrupt rule or a timeout rule, and the demo documents needed
 * both to have something to draw an exit edge FOR.
 *
 * The spike answered the question they were asked to hold open, so they were
 * removed rather than left standing:
 *
 *   - `myapp.guarded_on_event` was `core.on_event` plus a `cond`. `core.on_event`
 *     now declares that optional `cond` itself - a PROPOSED key on a SHIPPED
 *     type, flagged as a mirror divergence at the descriptor in `palette.js`,
 *     the way `core.parallel`'s `complete` is;
 *   - `myapp.timeout_rule` was an `after` duration plus the same guard.
 *     `core.timeout` in `proposed-core.js` is that type, proposed as core
 *     because nothing about "interrupt this group after a duration" is
 *     host-specific.
 *
 * `fixtures/documents/card-processing.json` was re-authored onto the two core
 * forms in the same change. Every block id held and every config key kept its
 * spelling, so `fixtures/runs.json` needed no edit at all - which is the
 * cleanest evidence available that the core forms cover what these two were
 * standing in for.
 *
 * What this file lost with them: it no longer declares an interrupt rule of
 * any kind, and no demo type here declares an `expression` field. That is not
 * a gap. The seam these two were meant to demonstrate - a host registering a
 * block type through the caller-supplied registry (ADR-0002 decision 2) - is
 * demonstrated by the eleven steps below and by `palette.js`'s three, and a
 * crutch kept for symmetry is still a crutch.
 *
 * Nothing else was removed from this file. Anything else that looks like
 * fixture furniture stays until the operator says otherwise.
 */

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
};
