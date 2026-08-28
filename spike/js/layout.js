/*
 * spike/js/layout.js - the canvas's layout model and its connector geometry.
 *
 * Two pure halves, and the split is the point of the file.
 *
 * The FIRST half turns `{document, registry}` into a layout tree: for every
 * block, the shape it takes on the canvas, how its slots are arranged, which
 * of them are rails, what its caption and config summary read, and where the
 * guard on a branch arm comes from. It is `ViewModel`'s job (ADR-0005 d13)
 * narrowed to what a canvas needs, and like `ViewModel` it does the palette
 * lookups so `render.js` does none.
 *
 * The SECOND half is geometry: functions from measured rectangles to SVG path
 * data. They know nothing about blocks - a rectangle is a rectangle - which is
 * what makes connector routing assertable in `dev/selftest.html` without a
 * layout engine anywhere near it.
 *
 * ## The rule this file is built to keep
 *
 * **Connectors are rendered, never authored, and the editor never branches on
 * a type name.** Adjacency inside a slot and the nesting of slots are the only
 * source of truth; every edge below is derived from one of those two, and
 * every difference in how a block is arranged is derived from ADR-0005
 * decision 10's presentation metadata rather than from what the block is
 * called. The three derivations that carry that weight:
 *
 *   1. **Side-by-side arrangement.** A block arranges its primary slots side
 *      by side when it declares `layout: "columns"`, or when it declares more
 *      than one primary slot. `core.parallel` hits the first (it declares
 *      columns); `core.branch` hits the second (arms plus `otherwise`);
 *      `core.sequence` and `core.group` hit neither and stack. A host type of
 *      the same shape gets the same rendering, which is d10's whole promise.
 *
 *   2. **Exclusive versus concurrent.** Of the two side-by-side cases, the one
 *      reached through `layout: "columns"` fans into lanes that all run, and
 *      the one reached through multiple primary slots fans into arms of which
 *      one is taken. That is exactly the distinction `layout` was given to
 *      express, so the fan marker reads it and nothing else.
 *
 *   3. **A slot's guard.** A column shows a condition when the block's
 *      `configSchema` declares an `expression` field keyed by that slot's
 *      name - which is precisely how `core.branch` publishes an arm's
 *      condition (ADR-0002 decision 7, and the `valuePath` amendment). No
 *      type name is consulted and no config key is guessed at.
 *
 * ## What is NOT here
 *
 * Selection, drag, collapse and the "+" affordances are sb-ad2's. This file
 * leaves the hooks - a shape per node, a stable slot identity, a collapsed
 * flag that nothing sets yet - and stops.
 */

import { compareUtf8, slotChildren, sortedSlotNames } from "./document.js";
import { describe, paletteEntryFor } from "./palette.js";

/* ============================================================ layout tree */

/**
 * The layout tree for one document.
 *
 * Returns `{ root, blockCount, findings }`, where `findings` is the flat,
 * document-level list ADR-0005 decision 11's panel renders and `root` is a
 * layout node (below). Total: an unresolvable block type produces a node with
 * `unresolved: true` rather than an absent one or a throw.
 */
export function layoutDocument(document, registry, session = {}) {
  const findings = [];
  // The two hooks this file left for sb-ad2, now supplied by the caller: which
  // blocks are folded shut, and what `data-drop` each slot carries during a
  // drag. Both default to "no session", so a call with two arguments still
  // produces the inert canvas the previous wave rendered.
  // `extra` is sb-8cm's addition: findings the caller computed that validation
  // cannot produce - a `:slot` anchor, the `:lint` source - folded in HERE
  // rather than beside the tree, so a folded card's count badge and the
  // findings panel's list are two readings of one set. Two sources that each
  // counted their own half is exactly how a badge starts lying.
  const view = {
    collapsed: session.collapsed ?? new Set(),
    dropState: session.dropState ?? (() => null),
    extra: groupByBlock(session.extraFindings ?? []),
  };

  const root = layoutBlock(document.root, registry, findings, {
    depth: 1,
    slot: null,
    parentId: null,
    view,
  });

  return { root, blockCount: countNodes(root), findings, maxDepth: depthOf(root) };
}

/** Caller-supplied findings, bucketed by the block their anchor names. */
function groupByBlock(findings) {
  const buckets = new Map();

  for (const finding of findings) {
    const id = finding.anchor?.blockId;
    if (id === undefined || id === null) continue;
    if (!buckets.has(id)) buckets.set(id, []);
    buckets.get(id).push(finding);
  }

  return buckets;
}

function countNodes(node) {
  return node.slots.reduce(
    (total, slot) => total + slot.children.reduce((sum, child) => sum + countNodes(child), 0),
    1
  );
}

function depthOf(node) {
  const children = node.slots.flatMap((slot) => slot.children);
  return children.length === 0 ? 1 : 1 + Math.max(...children.map(depthOf));
}

/**
 * One block as the canvas sees it.
 *
 *     {
 *       id, type, typeVersion, config, depth, parentId, slotName,
 *       unresolved, reason,
 *       title,        the author's words, or the palette label
 *       caption,      the block type's label, or its raw name when unresolved
 *       icon,         an icon NAME (d10: never markup)
 *       summary,      [{ key, label, value }] - the card's config line
 *       chips,        [{ key, label, value }] - select fields, shown as chips
 *       shape,        "chip" | "card" | "container"
 *       arrangement,  "stack" | "fan" | "lanes"
 *       slots,        every slot view, declared order then present-but-undeclared
 *       primary/secondary, the same views partitioned by slot_style
 *       collapsed,    always false here; sb-ad2 owns the interaction
 *       findings      the block's own, also appended to the document list
 *     }
 */
function layoutBlock(node, registry, findings, { depth, slot, parentId, view }) {
  const described = describe(registry, node);
  const { descriptor, block, unresolved } = described;
  const entry = paletteEntryFor(descriptor);
  const config = block.config;

  const own = [];

  if (unresolved) {
    own.push({
      severity: "error",
      source: "resolution",
      origin: "validation",
      anchor: { kind: "block", blockId: node.id },
      message: entry.description,
    });
  } else {
    for (const problem of descriptor.validateConfig(config) ?? []) {
      own.push({
        severity: "error",
        source: "config",
        origin: "validation",
        anchor: { kind: "config", blockId: node.id, key: problem.key },
        message: problem.message,
      });
    }
  }

  // The caller's own findings, appended after validation's so that a block
  // carrying both reads real-first. `origin` is already stamped on these by
  // whoever supplied them, and this file neither invents nor rewrites one.
  own.push(...(view.extra.get(node.id) ?? []));

  const schema = safeSchema(descriptor, config);
  const slots = slotViews(node, descriptor, entry, config, schema, view);

  const layoutNode = {
    id: node.id,
    type: node.type,
    typeVersion: node.typeVersion,
    config,
    depth,
    parentId,
    slotName: slot,
    unresolved,
    reason: described.reason ?? null,
    title: titleFor(config, schema, entry),
    caption: unresolved ? node.type : entry.label,
    icon: entry.icon,
    group: entry.group,
    summary: summaryOf(schema, config),
    chips: chipsOf(schema, config),
    rawConfig: unresolved ? canonicalConfig(config) : null,
    collapsed: view.collapsed.has(node.id),
    findings: own,
    slots: [],
  };

  layoutNode.slots = slots.map(({ rawChildren, ...slotView }) => ({
    ...slotView,
    children: rawChildren.map((child) =>
      layoutBlock(child, registry, findings, {
        depth: depth + 1,
        slot: slotView.name,
        parentId: node.id,
        view,
      })
    ),
  }));

  layoutNode.primary = layoutNode.slots.filter((one) => one.style === "primary");
  layoutNode.secondary = layoutNode.slots.filter((one) => one.style === "secondary");
  layoutNode.shape = shapeOf(layoutNode, schema);
  layoutNode.arrangement = arrangementOf(layoutNode, entry);
  layoutNode.descendantFindings = 0;

  findings.push(...own);

  for (const one of layoutNode.slots) {
    for (const child of one.children) {
      layoutNode.descendantFindings +=
        child.findings.length + child.descendantFindings;
    }
  }

  // What a folded card reports it is hiding. Counted from the layout tree
  // rather than re-walked from the document, so the number on the badge and
  // the subtree the fold actually hides are the same walk by construction.
  layoutNode.descendantCount = countNodes(layoutNode) - 1;

  return layoutNode;
}

/*
 * ADR-0002 decision 6 guarantees `slots/1` and `config_schema/1` return
 * without raising only for config `validate_config/1` accepts, and a fixture
 * or an author mid-edit can hand us config it does not. Refusing to call them
 * is the shipped editor's discipline; here, where the canvas has to render
 * SOMETHING for every block, the calls are wrapped and a refusal degrades to
 * "no declared shape" - which is the same place decision 12 already lands an
 * unresolvable block, and therefore a case the renderer already handles.
 */
function safeSchema(descriptor, config) {
  try {
    return descriptor.configSchema(config) ?? [];
  } catch {
    return [];
  }
}

function safeSlots(descriptor, config) {
  try {
    return descriptor.slots(config) ?? [];
  } catch {
    return [];
  }
}

/**
 * Every slot the canvas draws for one block: the declared ones in declared
 * order, then any slot key the document carries that the type did not declare.
 *
 * The second list is ADR-0005 decision 12's "its existing children rendered
 * normally, recursively; slot headers show the raw slot names". It is not
 * only the unresolvable case - a resolvable type whose config changed can
 * strand a slot the same way - so it is derived from the document rather than
 * from `unresolved`.
 */
function slotViews(node, descriptor, entry, config, schema, view) {
  const declared = safeSlots(descriptor, config);
  const declaredNames = new Set(declared.map((slot) => slot.name));

  const stranded = sortedSlotNames(node.slots)
    .filter((name) => !declaredNames.has(name) && slotChildren(node, name).length > 0)
    .map((name) => ({ name, arity: "any", label: name, undeclared: true }));

  return [...declared, ...stranded].map((slot) => ({
    name: slot.name,
    label: slot.label ?? slot.name,
    arity: slot.arity ?? "any",
    undeclared: slot.undeclared === true,
    style: entry.slotStyle?.[slot.name] === "secondary" ? "secondary" : "primary",
    guard: guardFor(schema, config, slot.name),
    rawChildren: slotChildren(node, slot.name),
    // Drop validity, asked of the session rather than derived here: this file
    // stays a pure function of {document, registry, view} and `targets.js`
    // keeps sole ownership of decision 5's four rules.
    dropState: view.dropState(node.id, slot.name),
  }));
}

/*
 * Derivation 3 from the header comment: a slot's guard is the value of an
 * `expression` field whose key IS the slot's name. `core.branch` publishes an
 * arm's condition exactly that way, and reads it back through a `valuePath`
 * into the stored `arms` list, so the read has to honor the path rather than
 * poking `config[slot]`.
 */
function guardFor(schema, config, slotName) {
  const field = schema.find(
    (candidate) => candidate.key === slotName && candidate.type === "expression"
  );
  if (!field) return null;

  const value = readValuePath(config, field.valuePath ?? [field.key]);
  return typeof value === "string" && value !== "" ? value : null;
}

/** Walks a `valuePath` - string keys into objects, integers into arrays. */
export function readValuePath(config, path) {
  let cursor = config;

  for (const step of path) {
    if (cursor === null || typeof cursor !== "object") return undefined;
    if (typeof step === "number") {
      if (!Array.isArray(cursor)) return undefined;
      cursor = cursor[step];
    } else {
      if (!Object.hasOwn(cursor, step)) return undefined;
      cursor = cursor[step];
    }
  }

  return cursor;
}

/*
 * The card's title. A declared `string` field keyed `label` is the author's
 * own name for this step, so it wins over the type's palette label - and the
 * palette label then becomes the caption underneath, so the type is never
 * hidden. A type that declares no such field simply has no title override.
 */
function titleFor(config, schema, entry) {
  const field = schema.find(
    (candidate) => candidate.key === "label" && candidate.type === "string"
  );
  if (!field) return entry.label;

  const value = readValuePath(config, field.valuePath ?? ["label"]);
  return typeof value === "string" && value !== "" ? value : entry.label;
}

/*
 * The card's one-line config summary. Every declared field except the ones
 * that already have somewhere else to be: `label` is the title, an
 * `expression` keyed by a slot is that column's guard pill, and a `select` is
 * a chip. What is left is the short scalar detail a reader wants on the face
 * of the card - a duration, a template name, a queue.
 */
function summaryOf(schema, config) {
  return schema
    .filter((field) => field.key !== "label")
    .filter((field) => !isSelect(field.type))
    .filter((field) => field.type !== "expression")
    .map((field) => ({
      key: field.key,
      label: field.label ?? field.key,
      value: formatValue(field.type, readValuePath(config, field.valuePath ?? [field.key])),
    }))
    .filter((item) => item.value !== null);
}

/*
 * Select fields render as chips on the card's header rather than in the
 * summary line, because they are the "which mode is this block in" facts -
 * a resumable group's history, an interrupt rule's outcome, a wizard step -
 * and reading them at a glance is the affordance. `core.resumable_group`'s
 * shallow-versus-deep is the case ADR-0005 decision 10 pointedly leaves to
 * ordinary config machinery, and this is that machinery.
 */
function chipsOf(schema, config) {
  return schema
    .filter((field) => isSelect(field.type))
    .map((field) => {
      const raw = readValuePath(config, field.valuePath ?? [field.key]);
      const option = field.type.select.find((candidate) => candidate.value === raw);
      if (raw === undefined) return null;
      return {
        key: field.key,
        label: field.label ?? field.key,
        value: shortLabel(option ? option.label : String(raw)),
      };
    })
    .filter((chip) => chip !== null);
}

function isSelect(type) {
  return type !== null && typeof type === "object" && Array.isArray(type.select);
}

/* An option label reads "Deep - the exact position"; the chip wants "Deep". */
function shortLabel(label) {
  return label.split(" - ")[0];
}

function formatValue(type, value) {
  if (value === undefined || value === null || value === "") return null;
  if (type === "duration") return humanizeDuration(String(value));
  if (typeof value === "boolean") return value ? "yes" : "no";
  if (Array.isArray(value)) return value.join(", ");
  if (typeof value === "object") return null;
  return String(value);
}

/**
 * `PT1H30M` reads as `1h 30m`. Presentation only - the stored value is always
 * the ISO-8601 string, because ADR-0001 decision 6 forbids the float that
 * "1.5 hours" would otherwise want to be.
 *
 * Anything that is not an ISO-8601 duration comes back unchanged rather than
 * mangled: an author mid-edit has invalid config almost continuously, and a
 * summary line is not the place to tell them so.
 */
export function humanizeDuration(value) {
  const match = /^P(?:(\d+)Y)?(?:(\d+)M)?(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$/.exec(
    value
  );
  if (!match) return value;

  const [, years, months, weeks, days, hours, minutes, seconds] = match;
  const parts = [
    [years, "y"],
    [months, "mo"],
    [weeks, "w"],
    [days, "d"],
    [hours, "h"],
    [minutes, "m"],
    [seconds, "s"],
  ]
    .filter(([amount]) => amount !== undefined)
    .map(([amount, unit]) => `${amount}${unit}`);

  return parts.length === 0 ? value : parts.join(" ");
}

/**
 * Canonical JSON for the read-only config of an unresolvable block (ADR-0005
 * decision 12), pretty-printed for reading rather than for bytes: the bytes
 * that matter are the document's, and this call never touches them.
 */
function canonicalConfig(config) {
  return JSON.stringify(sortDeep(config), null, 2);
}

function sortDeep(value) {
  if (Array.isArray(value)) return value.map(sortDeep);
  if (value === null || typeof value !== "object") return value;

  const sorted = {};
  for (const key of Object.keys(value).sort(compareUtf8)) sorted[key] = sortDeep(value[key]);
  return sorted;
}

/*
 * Three shapes, and a block gets the smallest one its content allows.
 *
 *   container  it has children to nest
 *   chip       it is a leaf whose entire meaning is one duration - a wait, a
 *              delay, a cool-off. Drawn compact, because a full card for
 *              "wait two minutes" is what makes a deep tree unreadable.
 *   card       everything else
 *
 * The chip test is over the SCHEMA, not the type name: a leaf declaring
 * exactly one field and that field a duration. `core.wait` is the core type
 * shaped that way and a host's cool-off step would be too.
 */
function shapeOf(node, schema) {
  if (node.slots.some((view) => view.children.length > 0)) return "container";

  const substantive = schema.filter((field) => field.key !== "label");
  const onlyDuration =
    substantive.length === 1 && substantive[0].type === "duration";

  return onlyDuration ? "chip" : "card";
}

/*
 * Derivations 1 and 2 from the header comment. `lanes` and `fan` differ only
 * in the marker the renderer draws and in whether the columns read as "all of
 * these" or "one of these"; both put their primary slots side by side.
 */
function arrangementOf(node, entry) {
  if (node.shape !== "container") return "stack";
  if (entry.layout === "columns") return "lanes";
  return node.primary.length > 1 ? "fan" : "stack";
}

/* ========================================================== connectors */

/*
 * Everything below takes measured rectangles - `{ x, y, width, height }` in
 * one shared coordinate space - and returns SVG path data. No DOM, no blocks,
 * no palette. Orthogonal routing with rounded corners rather than curves,
 * because at depth 7 a bezier that passes near a card reads as ambiguous and
 * a right angle never does, and because an orthogonal path's corners are
 * where a reader's eye already expects a decision.
 */

/** The point flow leaves a rectangle from. */
export function outlet(rect) {
  return { x: rect.x + rect.width / 2, y: rect.y + rect.height };
}

/** The point flow enters a rectangle at. */
export function inlet(rect) {
  return { x: rect.x + rect.width / 2, y: rect.y };
}

/** Rounds to a tenth of a pixel: shorter path data, no visible difference. */
function n(value) {
  return Math.round(value * 10) / 10;
}

const STRAIGHT_EPSILON = 0.75;

/**
 * A flow edge from one point down to another, orthogonally.
 *
 * Straight when the two are vertically aligned, which is the common case
 * inside a sequence; otherwise down to the halfway line, across, and down
 * again, with the corners rounded by `radius` (clamped so a short edge cannot
 * turn its own corners inside out).
 */
export function flowPath(from, to, radius = 10) {
  if (Math.abs(to.x - from.x) < STRAIGHT_EPSILON) {
    return `M ${n(from.x)} ${n(from.y)} L ${n(from.x)} ${n(to.y)}`;
  }

  const midY = (from.y + to.y) / 2;
  const dir = to.x > from.x ? 1 : -1;
  const r = Math.max(
    0,
    Math.min(radius, Math.abs(to.x - from.x) / 2, Math.abs(to.y - from.y) / 2)
  );

  return [
    `M ${n(from.x)} ${n(from.y)}`,
    `V ${n(midY - r)}`,
    `Q ${n(from.x)} ${n(midY)} ${n(from.x + dir * r)} ${n(midY)}`,
    `H ${n(to.x - dir * r)}`,
    `Q ${n(to.x)} ${n(midY)} ${n(to.x)} ${n(midY + r)}`,
    `V ${n(to.y)}`,
  ].join(" ");
}

/**
 * A fan edge: from a hub down and out to one column's inlet. Same routing as
 * a flow edge - the distinction is the class the renderer puts on it and the
 * marker it carries, not the geometry - but the elbow is pulled up close to
 * the hub rather than sitting halfway, so every arm of one fan turns on the
 * same line and the result reads as a distribution bar rather than as several
 * unrelated edges.
 */
export function fanPath(hub, to, radius = 10) {
  if (Math.abs(to.x - hub.x) < STRAIGHT_EPSILON) {
    return `M ${n(hub.x)} ${n(hub.y)} L ${n(hub.x)} ${n(to.y)}`;
  }

  const elbowY = hub.y + Math.min(radius * 1.6, Math.abs(to.y - hub.y) / 2);
  const dir = to.x > hub.x ? 1 : -1;
  const r = Math.max(
    0,
    Math.min(radius, Math.abs(to.x - hub.x) / 2, Math.abs(to.y - elbowY), Math.abs(to.y - elbowY))
  );

  return [
    `M ${n(hub.x)} ${n(hub.y)}`,
    `V ${n(elbowY - r)}`,
    `Q ${n(hub.x)} ${n(elbowY)} ${n(hub.x + dir * r)} ${n(elbowY)}`,
    `H ${n(to.x - dir * r)}`,
    `Q ${n(to.x)} ${n(elbowY)} ${n(to.x)} ${n(elbowY + r)}`,
    `V ${n(to.y)}`,
  ].join(" ");
}

/**
 * A rejoin edge: from one column's outlet down and in to a join hub. The
 * mirror of `fanPath` - the elbow sits close to the HUB, which here is the
 * lower end, so every arm turns on one line again.
 */
export function joinPath(from, hub, radius = 10) {
  if (Math.abs(hub.x - from.x) < STRAIGHT_EPSILON) {
    return `M ${n(from.x)} ${n(from.y)} L ${n(from.x)} ${n(hub.y)}`;
  }

  const elbowY = hub.y - Math.min(radius * 1.6, Math.abs(hub.y - from.y) / 2);
  const dir = hub.x > from.x ? 1 : -1;
  const r = Math.max(
    0,
    Math.min(radius, Math.abs(hub.x - from.x) / 2, Math.abs(elbowY - from.y))
  );

  return [
    `M ${n(from.x)} ${n(from.y)}`,
    `V ${n(elbowY - r)}`,
    `Q ${n(from.x)} ${n(elbowY)} ${n(from.x + dir * r)} ${n(elbowY)}`,
    `H ${n(hub.x - dir * r)}`,
    `Q ${n(hub.x)} ${n(elbowY)} ${n(hub.x)} ${n(elbowY + r)}`,
    `V ${n(hub.y)}`,
  ].join(" ");
}

/**
 * An interrupt exit edge: from a rule on the secondary rail, out past the
 * right-hand side of its group, and down to the group's exit point.
 *
 * One corner rather than two, and it leaves the rail card from its RIGHT edge
 * and travels down a channel to the right of everything the group contains -
 * `channelX` is that channel. This is the routing rule that keeps interrupt
 * edges from crossing the body of the group at any depth: the channel is
 * outside the group's own box, so there is nothing there to cross.
 */
export function interruptPath(from, exit, channelX, radius = 10) {
  const r = Math.max(
    0,
    Math.min(radius, Math.abs(channelX - from.x), Math.abs(exit.y - from.y) / 2)
  );

  return [
    `M ${n(from.x)} ${n(from.y)}`,
    `H ${n(channelX - r)}`,
    `Q ${n(channelX)} ${n(from.y)} ${n(channelX)} ${n(from.y + r)}`,
    `V ${n(exit.y - r)}`,
    `Q ${n(channelX)} ${n(exit.y)} ${n(channelX - r)} ${n(exit.y)}`,
    `H ${n(exit.x)}`,
  ].join(" ");
}
