/*
 * spike/js/panes.js - the palette, config-form and findings view models.
 *
 * The pure half of sb-8cm. Nothing in this file touches the DOM, and that is
 * the same split `layout.js` draws for the canvas: the questions a pane has to
 * answer - which palette entries match "wai", which controls a selected block's
 * config schema derives into, where a finding's anchor lives in the tree - are
 * all answerable without a browser, so they are answered here and asserted in
 * `dev/selftest.html` rather than probed through a rendered page.
 *
 * `inspector.js` and `palette-pane.js` are the translation layers that turn
 * these values into elements and the resulting gestures back into commands.
 *
 * ## The three contracts this file implements
 *
 *   - **ADR-0005 decision 9**, the config form. The closed field-type set is
 *     ADR-0002 decision 7's, and the mapping below is exhaustive by
 *     construction: every member of the set has exactly one control, and an
 *     unrecognized type degrades to a text control rather than throwing. The
 *     schema is RE-DERIVED from current config on every call and never cached,
 *     because a schema is a function of config (a branch grows a condition
 *     field per arm) and a cached one is a lie the moment an arm is added.
 *
 *   - **ADR-0005 decision 10**, the palette's grouping and metadata. The
 *     grouping rule is `palette.js`'s `paletteGroups` verbatim - group name,
 *     then `order`, then label - and the search filter is applied over that
 *     result rather than instead of it, so filtering never reorders a palette
 *     an author has learned the shape of.
 *
 *   - **ADR-0005 decision 11**, anchored findings. An anchor is the whole
 *     routing mechanism, so `resolveAnchor` is the one function that turns one
 *     into a block id plus the ancestors that have to be unfolded to see it.
 *
 * ## Where a finding comes from, and why both sources exist
 *
 * Two sources, deliberately distinguishable through `origin`:
 *
 *   - `origin: "validation"` - REAL. Produced by `layout.js` from
 *     `validateConfig/1` and from resolution failure, exactly as the shipped
 *     editor will produce them. Every one of these is reproducible by editing
 *     the document until it is wrong.
 *
 *   - `origin: "demo"` - a small STATIC set, below. It exists because decision
 *     11 names anchors and severities that validation cannot currently produce
 *     at all: a `:slot` anchor (arity and undeclared-slot findings are not
 *     computed in the spike), and the `:lint` source, whose whole point in the
 *     record is that nothing catches an unregistered invoke type at authoring
 *     time. Without the static set the findings panel could only ever
 *     demonstrate one severity anchored one way, which would make the pane
 *     evidence of nothing.
 *
 * The `origin` is carried through to the rendered row so a reader of a
 * screenshot can tell which half is real. Nothing downstream branches on it.
 *
 * ## One severity the record does not have
 *
 * ADR-0005 decision 11 spells severity as two-valued, `:error | :warning`. The
 * spike renders a third, `info`, because the campaign asked the findings pane
 * to show three and because a lint that is purely advisory reads wrong in
 * warning chrome. That is a PROPOSAL about the record, not a reading of it:
 * every `info` here is `origin: "demo"`, no validation path produces one, and
 * whether decision 11 should gain the third value is the operator's call, not
 * this file's. See the bead note.
 */

import { fetchPath, findBlock } from "./document.js";
import { humanizeDuration, readValuePath } from "./layout.js";
import { describe, paletteEntryFor, paletteGroups } from "./palette.js";

/* ========================================================== the palette pane */

/**
 * The palette as the left pane renders it: `paletteGroups`'s grouping, then
 * this bead's search filter over it.
 *
 * A query matches an entry when it appears, case-insensitively, in the entry's
 * label, its type name, its description, or any of its `keywords` (ADR-0005
 * decision 10's "additional palette search terms"). `matchedOn` names which,
 * so an entry that matched on a keyword the author cannot see can say so
 * rather than looking like a false positive - "Wait" surfacing for "sleep" is
 * correct and inexplicable unless the pane explains it.
 *
 * Returns
 *
 *     {
 *       query,      the trimmed query, "" when there is none
 *       total,      how many entries the registry holds
 *       matched,    how many survived the filter
 *       empty,      true when a non-empty query matched nothing
 *       groups: [{ name, entries: [Entry] }]
 *     }
 *
 * where an Entry carries `segments` - the label split into matched and
 * unmatched runs, which is what lets the renderer highlight without ever
 * building markup from a query string.
 */
export function paletteView(registry, rawQuery = "") {
  const query = String(rawQuery ?? "").trim();
  const needle = query.toLowerCase();
  const groups = paletteGroups(registry);

  const total = groups.reduce((sum, group) => sum + group.entries.length, 0);

  const filtered = groups
    .map((group) => ({
      name: group.name,
      entries: group.entries
        .map(({ name, entry }) => paletteEntry(name, entry, needle))
        .filter((entry) => entry !== null),
    }))
    .filter((group) => group.entries.length > 0);

  const matched = filtered.reduce((sum, group) => sum + group.entries.length, 0);

  return { query, total, matched, empty: needle !== "" && matched === 0, groups: filtered };
}

function paletteEntry(typeName, entry, needle) {
  const keywords = Array.isArray(entry.keywords) ? entry.keywords : [];

  const matchedOn =
    needle === ""
      ? []
      : [
          contains(entry.label, needle) ? "label" : null,
          contains(typeName, needle) ? "type" : null,
          contains(entry.description, needle) ? "description" : null,
          keywords.some((word) => contains(word, needle)) ? "keywords" : null,
        ].filter(Boolean);

  if (needle !== "" && matchedOn.length === 0) return null;

  return {
    type: typeName,
    label: entry.label,
    description: entry.description,
    icon: entry.icon,
    group: entry.group,
    order: entry.order,
    accentToken: entry.accentToken,
    keywords,
    matchedOn,
    segments: highlight(entry.label, needle),
  };
}

const contains = (value, needle) =>
  typeof value === "string" && value.toLowerCase().includes(needle);

/**
 * One string split into alternating matched and unmatched runs. Every
 * occurrence, not just the first: a search for "e" in "Resumable group" should
 * light all of them or none, and lighting only the first reads as a bug.
 *
 * Returned as data rather than as markup on purpose. A renderer that built an
 * HTML string here would be interpolating a user-typed query into markup,
 * which is the one habit a spike other beads copy from must not teach.
 */
export function highlight(text, needle) {
  const value = String(text ?? "");
  if (needle === "" || value === "") return [{ text: value, match: false }];

  const haystack = value.toLowerCase();
  const segments = [];
  let cursor = 0;

  for (;;) {
    const at = haystack.indexOf(needle, cursor);
    if (at === -1) break;

    if (at > cursor) segments.push({ text: value.slice(cursor, at), match: false });
    segments.push({ text: value.slice(at, at + needle.length), match: true });
    cursor = at + needle.length;
  }

  if (segments.length === 0) return [{ text: value, match: false }];
  if (cursor < value.length) segments.push({ text: value.slice(cursor), match: false });

  return segments;
}

/* =========================================================== the config form */

/*
 * ADR-0002 decision 7's closed field-type set, mapped to the controls the
 * inspector renders. Exhaustive by construction: the set is closed precisely so
 * that this mapping can be total, and the `default` arm exists for a foreign
 * descriptor rather than for a member of the set.
 *
 * "Decimal" is not a member and there is no control for one. ADR-0001 decision
 * 6 forbids floats in config, so a decimal IS a string - `"12.50"` typed into
 * the `string` control - and adding a `:decimal` field type would widen a
 * closed set to describe something the set already covers. The `inputMode`
 * below is the whole accommodation: a text control that offers a numeric
 * keypad still stores, and still round-trips, a string.
 */
export function controlFor(type) {
  if (type !== null && typeof type === "object") {
    if (Array.isArray(type.select)) return "select";
    if (type.list !== undefined) return "list";
    /* sb-e2x: the PROPOSED `{ map: T }` field type - rows of a string key and a
     * `T` value. Read exactly as `{ list: T }` is read, one line below it,
     * because it is the same kind of thing: a container parameterised by a
     * member of the closed set. This mapping is the whole reason the set is
     * closed, so a proposed member has to earn its arm here or it is not a
     * field type at all. `proposed-core.js` carries the divergence flag and the
     * argument; nothing in this file knows which type declared it. */
    if (type.map !== undefined) return "map";
    return "text";
  }

  switch (type) {
    case "string":
      return "text";
    case "integer":
      return "integer";
    case "boolean":
      return "boolean";
    case "expression":
      return "expression";
    case "duration":
      return "duration";
    default:
      return "text";
  }
}

/**
 * The form for one selected block, derived from its type's `configSchema/1`
 * against its CURRENT config.
 *
 * Returns
 *
 *     {
 *       blockId, typeName, unresolved, reason,
 *       readOnly,   true exactly when the block does not resolve (d12)
 *       rawConfig,  the read-only canonical JSON, or null
 *       fields: [Field],
 *       empty       true when a resolvable block has no fields at all
 *     }
 *
 * `empty` is structurally false for a resolvable block since sb-jvz: the
 * editor injects a `label` field into every descriptor `describe` resolves,
 * so the schema this form is derived from is never the empty list. It is
 * kept in the shape rather than dropped because it states the invariant -
 * a caller reading `empty` gets a true answer, and one asserting it can
 * still catch the day the injection stops happening.
 *
 * That injection is also why nothing here mentions `label`. The form does
 * not know the field exists: it derives from the schema `describe` hands
 * back, and the schema already carries it.
 *
 * `readOnly` is decision 12 stated as a boolean: "its config shown read-only as
 * canonical JSON, because there is no `config_schema/1` to drive a form and
 * inventing one would be guessing". The form does not half-render an
 * unresolvable block; it renders its bytes.
 */
export function configFormFor(registry, node, documentFindings = []) {
  if (!node) return null;

  const { descriptor, block, unresolved, reason } = describe(registry, node);
  const config = block.config;

  // ADR-0005 decision 11: "a `:config` finding renders inline beneath its
  // field". Routed by anchor, from the SAME set the findings panel lists, so a
  // row in the panel and the message under a field are one finding shown
  // twice rather than two findings that happen to read alike.
  // `validate_config/1` is asked directly as well as read off the anchored
  // set, so the form is correct for a caller that supplies no document
  // findings at all - the self-test, and any future pane that wants a form
  // without a whole layout pass. Duplicates are collapsed on key and message.
  const anchored = dedupe([
    ...(describeValidation(descriptor, config) ?? []),
    ...documentFindings
      .filter((finding) => finding.anchor?.kind === "config" && finding.anchor.blockId === node.id)
      .map((finding) => ({
        key: finding.anchor.key,
        // sb-e2x: a map field's anchor may name a row as well as a key. Carried
        // through so the row control can put the message on that row, and
        // ABSENT rather than `undefined` when the anchor names none.
        ...(finding.anchor.row === undefined ? {} : { row: finding.anchor.row }),
        message: finding.message,
        severity: finding.severity ?? "error",
        origin: finding.origin ?? "validation",
      })),
  ]);

  if (unresolved) {
    return {
      blockId: node.id,
      typeName: node.type,
      unresolved: true,
      reason: reason ?? null,
      readOnly: true,
      rawConfig: canonicalJson(node.config),
      fields: [],
      empty: false,
    };
  }

  const schema = safeSchema(descriptor, config);

  return {
    blockId: node.id,
    typeName: node.type,
    unresolved: false,
    reason: null,
    readOnly: false,
    rawConfig: null,
    fields: schema.map((field) => fieldView(field, config, anchored)),
    empty: schema.length === 0,
  };
}

/*
 * One declared field as a control. `path` is the field's `valuePath` when it
 * declares one and `[key]` otherwise, and it is what an edit writes through -
 * `core.branch` keys an arm's condition by its slot name while storing it at
 * `["arms", i, "cond"]`, and the form has to honor both readings at once.
 *
 * Findings are matched on the field's KEY, which is the same key
 * `validate_config/1` reports against and the same key ADR-0005 decision 11's
 * `{:config, block_id, key}` anchor carries. That is why the branch keys arms
 * by slot name rather than by index.
 */
function fieldView(field, config, findings) {
  const path = field.valuePath ?? [field.key];
  const control = controlFor(field.type);
  const value = readValuePath(config, path);

  const view = {
    key: field.key,
    label: field.label ?? field.key,
    required: field.required === true,
    path,
    control,
    type: field.type,
    value,
    default: field.default,
    /*
     * sb-ed7. Carried, never invented: a field that declares a placeholder
     * gets it, and one that does not gets `undefined` and leaves the choice to
     * the control type (`inspector.js`). The derivation stays type-driven -
     * there is no key here and no type name - which is what keeps the editor's
     * own `label` field (`LABEL_FIELD`, the only declarer today) an ordinary
     * declaring field rather than a case in this switch.
     */
    placeholder: field.placeholder,
    findings: findings.filter((finding) => finding.key === field.key),
  };

  if (control === "select") view.choices = field.type.select;
  if (control === "duration") view.duration = durationParts(value);

  /*
   * sb-e2x's row control, derived the same way the list control's rows are:
   * pure data the renderer only has to draw.
   *
   * Rows come back in KEY order rather than insertion order, because a map has
   * no row order and pretending otherwise is what the text field did. That
   * also matches ADR-0001 decision 8's canonical key sort, so the order an
   * author sees is the order the stored bytes are in.
   *
   * Findings are routed by `row`: a finding naming a map key sits on that row,
   * and one without a `row` stays under the field as every other control's
   * does. `field.findings` keeps the whole set either way - a caller that
   * ignores `rows` still renders every message - which is what makes the row
   * routing a presentation refinement rather than a second finding source.
   */
  if (control === "map") {
    const entries = mapEntries(value);

    view.valueType = field.type.map;
    view.valueControl = controlFor(field.type.map);
    view.keyLabel = field.keyLabel ?? "Key";
    view.valueLabel = field.valueLabel ?? "Value";
    view.rows = entries.map(([key, item]) => ({
      key,
      path: [...path, key],
      value: item,
      control: controlFor(field.type.map),
      findings: view.findings.filter((finding) => finding.row === key),
    }));
    view.fieldFindings = view.findings.filter(
      (finding) => finding.row === undefined || !entries.some(([key]) => key === finding.row)
    );
  }

  if (control === "list") {
    view.itemType = field.type.list;
    view.itemControl = controlFor(field.type.list);
    view.rows = (Array.isArray(value) ? value : []).map((item, index) => ({
      index,
      path: [...path, index],
      value: item,
      control: controlFor(field.type.list),
    }));
  }

  return view;
}

function safeSchema(descriptor, config) {
  try {
    return descriptor.configSchema(config) ?? [];
  } catch {
    return [];
  }
}

function describeValidation(descriptor, config) {
  return (descriptor.validateConfig(config) ?? []).map((problem) => ({
    key: problem.key,
    // sb-e2x: the map row a row-level problem is about, when the type reports
    // one. Spread rather than set to `undefined`, so a finding that names no
    // row has no `row` key at all - which is what keeps it deep-equal to the
    // finding this line produced before the map field existed.
    ...(problem.row === undefined ? {} : { row: problem.row }),
    message: problem.message,
    // sb-c2o: the problem's own severity, defaulted - `layout.js` reads it the
    // same way now, and the form and the canvas have to agree about a finding
    // or the panel and the field under the author's cursor say different
    // things about one problem.
    severity: problem.severity ?? "error",
    origin: "validation",
  }));
}

function dedupe(findings) {
  const seen = new Set();

  return findings.filter((finding) => {
    // The row joins the token (sb-e2x): two rows of one map field can carry the
    // same message about different rows, and collapsing those would silently
    // drop one of them.
    const token = `${finding.key}\u0000${finding.row ?? ""}\u0000${finding.message}`;
    if (seen.has(token)) return false;
    seen.add(token);
    return true;
  });
}

/** The read-only bytes decision 12 shows, pretty-printed for reading. */
export function canonicalJson(config) {
  try {
    return JSON.stringify(config ?? {}, null, 2);
  } catch {
    return String(config);
  }
}

/* --------------------------------------------------------- writing a value */

/**
 * `config` with one `valuePath` replaced. Returns a NEW value all the way down
 * the path and shares everything else, because the previous config is the
 * inverse command's payload (ADR-0005 decision 3) and mutating it in place
 * would quietly corrupt the undo stack.
 *
 * String keys build objects and integer keys build arrays, which is
 * `session.js`'s `writeValuePath` rule; unlike that one this returns a copy
 * rather than writing into a fresh accumulator. `defineProperty` at every step
 * for the same reason both files give: a path is data, and a `"__proto__"`
 * segment must create an own key rather than move a prototype.
 */
export function writeAtPath(config, path, value) {
  if (path.length === 0) return value;

  const [step, ...rest] = path;
  const base = Number.isInteger(step)
    ? Array.isArray(config)
      ? config.slice()
      : []
    : cloneObject(config);

  const existing = Number.isInteger(step)
    ? base[step]
    : Object.hasOwn(base, step)
      ? base[step]
      : undefined;

  const next = rest.length === 0 ? value : writeAtPath(existing, rest, value);

  if (Number.isInteger(step)) {
    base[step] = next;
    return base;
  }

  Object.defineProperty(base, step, {
    value: next,
    enumerable: true,
    writable: true,
    configurable: true,
  });

  return base;
}

function cloneObject(value) {
  const out = {};
  if (value === null || typeof value !== "object" || Array.isArray(value)) return out;

  for (const [key, item] of Object.entries(value)) {
    Object.defineProperty(out, key, {
      value: item,
      enumerable: true,
      writable: true,
      configurable: true,
    });
  }

  return out;
}

/* -------------------------------------------------------- the list controls */

/**
 * The three row gestures, as pure list transforms. `moveRow` clamps rather
 * than refusing, so "up" on the first row and "down" on the last are no-ops the
 * caller does not have to guard - which is what lets the renderer disable those
 * buttons for looks rather than for correctness.
 */
export function addRow(rows, item) {
  return [...rows, item];
}

export function removeRow(rows, index) {
  return rows.filter((_row, at) => at !== index);
}

export function moveRow(rows, index, step) {
  const to = index + step;
  if (index < 0 || index >= rows.length || to < 0 || to >= rows.length) return rows.slice();

  const out = rows.slice();
  const [held] = out.splice(index, 1);
  out.splice(to, 0, held);

  return out;
}

/* ------------------------------------------------------- the map controls
 *
 * sb-e2x. The list controls above transform an array; these transform an
 * object, and the difference in the gestures they offer is not an omission.
 * There is no `moveMapRow`, because a map has no row order to move a row
 * within - the storage shape decides the interaction, which is the honest
 * consequence of storing the pairs as pairs rather than as text.
 *
 * All four are pure and total: they take a map and return a NEW map, for the
 * reason `writeAtPath` gives (the previous config is the inverse command's
 * payload, ADR-0005 decision 3, and mutating it corrupts the undo stack). They
 * are exported so `dev/selftest.html` can check the transforms without a DOM,
 * which is where every claim about them is machine-checked.
 */

/** A map's entries in key order - the order the canonical bytes are in. */
export function mapEntries(value) {
  if (value === null || typeof value !== "object" || Array.isArray(value)) return [];
  return Object.keys(value)
    .sort()
    .map((key) => [key, value[key]]);
}

/**
 * The map with one new unnamed row. Idempotent BY CONSTRUCTION, and that is
 * the point: a map cannot hold two unnamed rows, so "add" while one is
 * unfinished can only mean the row already there. The control disables its add
 * button while that is true rather than letting a click silently do nothing,
 * but the transform is honest on its own so a caller that does not check gets
 * the same map back rather than a lost row.
 */
export function addMapRow(map, seed = "") {
  return mapFrom([...mapEntries(map).filter(([key]) => key !== ""), ["", seed]]);
}

export function removeMapRow(map, key) {
  return mapFrom(mapEntries(map).filter(([at]) => at !== key));
}

export function setMapValue(map, key, value) {
  return mapFrom([...mapEntries(map).filter(([at]) => at !== key), [key, value]]);
}

/**
 * The map with one row renamed, or `null` when the rename would collide.
 *
 * `null` rather than a silent overwrite, and rather than a second row: writing
 * `b` over an existing `b` is the one gesture a map makes destructive and a
 * text field did not, so it is refused where the author can see it. The caller
 * marks the row and puts the old key back; nothing is stored. Renaming a key to
 * itself is a no-op that succeeds, so a blur with no edit is not a refusal.
 */
export function renameMapRow(map, from, to) {
  if (from === to) return mapFrom(mapEntries(map));

  const entries = mapEntries(map);
  if (entries.some(([key]) => key === to)) return null;

  return mapFrom(entries.map(([key, value]) => (key === from ? [to, value] : [key, value])));
}

/* Own keys only, defined rather than assigned, for `writeAtPath`'s reason: a
 * key is data, and a `"__proto__"` row must create an own key rather than move
 * a prototype. Rebuilt in key order so the object a form hands back is already
 * in the order the canonical encoder will put it in. */
function mapFrom(entries) {
  const out = {};

  for (const [key, value] of [...entries].sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))) {
    Object.defineProperty(out, key, {
      value,
      enumerable: true,
      writable: true,
      configurable: true,
    });
  }

  return out;
}

/** A new row's seed value for a list of `itemType`. */
export function seedRow(itemType) {
  switch (controlFor(itemType)) {
    case "integer":
      return 0;
    case "boolean":
      return false;
    case "select":
      return itemType.select[0]?.value ?? "";
    default:
      return "";
  }
}

/* ------------------------------------------------------- the duration control */

const DURATION_UNITS = [
  { unit: "S", label: "seconds", designator: "T" },
  { unit: "M", label: "minutes", designator: "T" },
  { unit: "H", label: "hours", designator: "T" },
  { unit: "D", label: "days", designator: "P" },
  { unit: "W", label: "weeks", designator: "P" },
];

export const durationUnits = () => DURATION_UNITS.map((one) => ({ ...one }));

const SINGLE = /^P(?:(\d+)([YMWD])|T(\d+)([HMS]))$/;

/**
 * ADR-0005 decision 9's structured duration control, as a value.
 *
 *     { simple, amount, unit, iso, human }
 *
 * `simple` is true when the stored string is ONE component - `PT30S`, `P1D` -
 * which is the case a number-plus-unit control can round-trip losslessly.
 * `PT1H30M` is not, and rather than silently rewriting it to `90 minutes` the
 * control falls back to editing the ISO string directly and keeps the
 * humanized readout beside it. Round-tripping an author's stored bytes matters
 * more than always showing the prettier control.
 *
 * `human` is `layout.js`'s `humanizeDuration`, so the card's summary line and
 * the form's readout can never disagree about what `PT1H30M` reads as.
 */
export function durationParts(value) {
  const iso = typeof value === "string" ? value : "";
  const match = SINGLE.exec(iso);

  if (!match) {
    return { simple: false, amount: null, unit: null, iso, human: humanizeDuration(iso) };
  }

  const amount = Number(match[1] ?? match[3]);
  const unit = match[2] ?? match[4];

  // `P1M` is months and `PT1M` is minutes. The regex keeps them apart by which
  // half of the pattern matched, and this is the one place the ambiguity in
  // ISO-8601's "M" can bite, so it is spelled out rather than inferred.
  const designator = match[2] ? "P" : "T";

  return {
    simple: DURATION_UNITS.some((one) => one.unit === unit && one.designator === designator),
    amount,
    unit,
    designator,
    iso,
    human: humanizeDuration(iso),
  };
}

/** The inverse: a number and a unit back into the stored ISO-8601 string. */
export function durationFrom(amount, unit) {
  const whole = Math.max(0, Math.trunc(Number(amount) || 0));
  const known = DURATION_UNITS.find((one) => one.unit === unit) ?? DURATION_UNITS[1];

  return known.designator === "T" ? `PT${whole}${known.unit}` : `P${whole}${known.unit}`;
}

/* =============================================================== the findings */

/*
 * The static demo set (`origin: "demo"`). Keyed by document id, because a
 * finding anchored to `blk_cp_authorize` means nothing in the signup fixture
 * and an anchor that resolves to no block would be worse than an absent one.
 *
 * Everything here is a shape validation CANNOT currently produce: a `:slot`
 * anchor, the `:lint` source ADR-0005 decision 11 introduces precisely because
 * nothing catches an unregistered invoke type at authoring time, and the
 * advisory `info` severity the record does not yet have. The real findings -
 * every config error and every resolution failure - come from `layout.js` and
 * are never listed here.
 */
const DEMO_FINDINGS = {
  bdoc_cp_demo: [
    {
      severity: "warning",
      source: "lint",
      anchor: { kind: "block", blockId: "blk_cp_authorize" },
      message: "No runtime handler is registered for myapp:authorize in this host.",
    },
    {
      severity: "warning",
      source: "arity",
      anchor: { kind: "slot", blockId: "blk_cp_authz", slot: "interrupts" },
      message: "Two interrupt rules guard the same event; only the first can fire.",
    },
    {
      severity: "info",
      source: "lint",
      anchor: { kind: "config", blockId: "blk_cp_fraud_wait", key: "duration" },
      message: "This hold outlasts the authorization window it sits inside.",
    },
    {
      severity: "info",
      source: "lint",
      anchor: { kind: "block", blockId: "blk_cp_capture_retry_call" },
      message: "A retry with no backoff will re-run as soon as the branch is taken.",
    },
  ],
  bdoc_signup_demo: [
    {
      severity: "warning",
      source: "lint",
      anchor: { kind: "block", blockId: "blk_su_provision" },
      message: "No runtime handler is registered for myapp:provision in this host.",
    },
    {
      severity: "info",
      source: "lint",
      anchor: { kind: "slot", blockId: "blk_su_verify", slot: "interrupts" },
      message: "Nothing here abandons the wizard if the address never verifies.",
    },
  ],
};

export const demoFindings = (documentId) =>
  (DEMO_FINDINGS[documentId] ?? []).map((finding) => ({ ...finding, origin: "demo" }));

const SEVERITY_ORDER = { error: 0, warning: 1, info: 2 };

/**
 * The document-level finding list decision 11's panel renders: the real ones
 * `layout.js` computed, then the static demo set, sorted by severity and then
 * by the order the blocks appear on the canvas.
 *
 * Document order rather than insertion order, so the panel reads top-to-bottom
 * the way the canvas does. A finding whose anchor names a block the document no
 * longer holds is DROPPED rather than listed unresolvable: it is only reachable
 * through a stale demo entry, and a row that cannot be clicked is a row that
 * teaches an author to stop clicking rows.
 */
export function collectFindings(tree, document, extras = []) {
  const order = documentOrder(tree.root);

  // `tree.findings` already carries the demo set when the caller handed it to
  // `layoutDocument` as `extraFindings`, which is what the shell does; the
  // second argument is for a caller that did not, and for the self-test.
  const all = [...tree.findings, ...extras]
    .map((finding) => ({ ...finding, at: order.get(finding.anchor?.blockId) }))
    .filter((finding) => finding.at !== undefined && findBlock(document, finding.anchor.blockId));

  return all
    .sort(
      (a, b) =>
        (SEVERITY_ORDER[a.severity] ?? 9) - (SEVERITY_ORDER[b.severity] ?? 9) || a.at - b.at
    )
    .map(({ at: _at, ...finding }) => finding);
}

function documentOrder(root, order = new Map()) {
  order.set(root.id, order.size);

  for (const slot of root.slots) {
    for (const child of slot.children) documentOrder(child, order);
  }

  return order;
}

/** `{ error, warning, info, total }` - what the tab's count badge reads off. */
export function severityCounts(findings) {
  const counts = { error: 0, warning: 0, info: 0, total: findings.length };

  for (const finding of findings) {
    if (counts[finding.severity] !== undefined) counts[finding.severity] += 1;
  }

  return counts;
}

/**
 * How many findings are anchored at or below one block - the number a folded
 * card's badge has to agree with. `layout.js` counts its own from validation
 * alone; this counts the panel's whole set, which is what makes "5 findings
 * inside this folded block" and the five rows in the panel the same five.
 */
export function findingsUnder(document, findings, blockId) {
  return findings.filter((finding) => {
    const id = finding.anchor?.blockId;
    if (id === blockId) return true;

    const path = fetchPath(document, id);
    return path !== null && path.some((step) => step.parentId === blockId);
  }).length;
}

/**
 * ADR-0005 decision 11's routing, resolved. Turns an anchor into everything a
 * reveal needs:
 *
 *     { ok, blockId, ancestorIds, slot, key, label }
 *
 * `ancestorIds` is every block between the root and the target, which is
 * exactly the set a reveal must unfold - the record's "a collapsed subtree
 * carries a count badge so a finding can never hide inside something folded
 * shut" is only half the promise, and this is the other half.
 */
export function resolveAnchor(document, anchor) {
  const blockId = anchor?.blockId ?? null;
  const path = blockId === null ? null : fetchPath(document, blockId);

  if (path === null) {
    return { ok: false, blockId, ancestorIds: [], slot: null, key: null, label: anchorLabel(anchor) };
  }

  return {
    ok: true,
    blockId,
    ancestorIds: path.map((step) => step.parentId),
    slot: anchor.kind === "slot" ? anchor.slot : null,
    key: anchor.kind === "config" ? anchor.key : null,
    label: anchorLabel(anchor),
  };
}

/** The monospace breadcrumb under a finding's message. */
export function anchorLabel(anchor) {
  if (!anchor) return "document";

  switch (anchor.kind) {
    case "config":
      return `${anchor.blockId} › config.${anchor.key}`;
    case "slot":
      return `${anchor.blockId} › slot:${anchor.slot}`;
    default:
      return anchor.blockId;
  }
}

/* ========================================================== config drafts */

/*
 * sb-5ow: the per-block DRAFT config, and why the inspector needs one.
 *
 * ADR-0005 decision 9 gates every `:update_config` on `validate_config/1`
 * over the WHOLE config, and a refusal stores nothing. That invariant is the
 * right one - a stored config is always a valid config - but it made a block
 * type with two required fields and no defaults unconfigurable through a form
 * that commits per field. `core.assign` is the live repro: fill `path` and
 * the config still has an empty `value`, so the gate refuses; fill `value`
 * afterwards and the edit is computed against the STORED config, which never
 * took `path`, so the gate refuses again. The revision never moves and the
 * author is told twice that a field they filled in correctly is wrong.
 *
 * The operator's ruling (2026-08-29) is DRAFT ACCUMULATION. The inspector
 * holds a draft config per block; fields edit the draft freely; the draft is
 * offered to the gate on every edit and becomes the stored config the first
 * time it validates AS A UNIT. Nothing about the gate, the schema, or the
 * command algebra moves: `updateConfig` is still the only way into the
 * document, still validated whole, still one undo step. What changes is only
 * WHICH config the next edit is computed against - the draft, when one is
 * outstanding, rather than the last one that happened to be storable.
 *
 * Two shapes were considered and rejected in that ruling. Relaxing validation
 * per field would let an invalid config reach the document, which is d9's
 * whole point. Seeding defaults at insert time would put values into the
 * author's document that the author never chose.
 *
 * The store is deliberately dumb: a Map of block id to config, no revision
 * tracking and no reconciliation against edits from elsewhere. `reset()` on a
 * document change is the only automatic clear; see the spike README's panes
 * section for what that leaves open (undo/redo under an outstanding draft).
 */

/**
 * A draft store.
 *
 *     read(blockId, stored)   the draft for that block, or `stored`
 *     pending(blockId)        is a draft outstanding for that block
 *     stage(blockId, config)  hold `config` as the block's draft
 *     clear(blockId)          drop that block's draft
 *     reset()                 drop every draft (a new document)
 *     size()                  how many blocks have one
 *
 * Mutable on purpose. Everything else in this file is a value transform, but
 * a draft is exactly the "in-progress form state" decision 9 puts in transient
 * assigns - state the shipped editor holds in its stateful component and the
 * spike holds beside the DOM. Modelling it as a value would mean threading it
 * through every control closure for no gain.
 */
export function createDraftStore() {
  const drafts = new Map();

  return {
    read: (blockId, stored) => (drafts.has(blockId) ? drafts.get(blockId) : stored),
    pending: (blockId) => drafts.has(blockId),
    stage: (blockId, config) => {
      drafts.set(blockId, config);
      return config;
    },
    clear: (blockId) => drafts.delete(blockId),
    reset: () => drafts.clear(),
    size: () => drafts.size,
  };
}

/**
 * The top-level keys on which a draft and the stored config disagree, sorted.
 *
 * Top level rather than deep: it feeds a sentence naming the fields an author
 * has edited but not yet stored, and a config form's fields are keyed at the
 * top level even when a field WRITES deeper (`core.branch` keys an arm by its
 * slot name and stores it at `["arms", i, "cond"]`). A deep diff would name
 * `arms` in a vocabulary no label in the form uses.
 *
 * Compared through `stableJson` below rather than through `canonicalJson`,
 * which pretty-prints for a human and does NOT sort keys: the order the keys
 * of a nested value happened to be built in is not an author edit.
 */
export function pendingKeys(draft, stored) {
  const left = isObject(draft) ? draft : {};
  const right = isObject(stored) ? stored : {};
  const keys = new Set([...Object.keys(left), ...Object.keys(right)]);

  return [...keys]
    .filter((key) => stableJson(left[key] ?? null) !== stableJson(right[key] ?? null))
    .sort();
}

const isObject = (value) => typeof value === "object" && value !== null && !Array.isArray(value);

/*
 * JSON with object keys in sorted order, at every depth. `document.js` owns
 * the document's canonical encoding and this is deliberately not a second
 * spelling of it: it never leaves this file, it is only ever compared against
 * itself, and it exists because two configs that differ only in key order are
 * the same config.
 */
function stableJson(value) {
  return JSON.stringify(value, (_key, seen) =>
    isObject(seen)
      ? Object.fromEntries(Object.keys(seen).sort().map((key) => [key, seen[key]]))
      : seen
  );
}
