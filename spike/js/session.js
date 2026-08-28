/*
 * spike/js/session.js - the editor session: selection, collapse, drag, edits.
 *
 * Everything an author's gestures mean, with no DOM anywhere in the file. The
 * shipped editor keeps this state in the one stateful LiveView component
 * (ADR-0005 decision 13) and re-renders after every command; the spike keeps
 * it in a plain value and re-renders after every command, which is the same
 * shape with a different transport. `interact.js` is the translation layer
 * that turns pointer events into calls on this module and the resulting
 * session back into DOM - and it is the ONLY file that knows what an event is.
 *
 * The split is not tidiness. Pre-hover drop validity, the "+" picker's type
 * list, the move-index correction and the undo stacks are all answerable
 * without a browser, so they are all asserted in `dev/selftest.html` against
 * this module rather than probed through a rendered page.
 *
 * ## What this module does NOT own
 *
 *   - The command algebra and its inverses. That is `edit.js`, mirrored from
 *     `StatifierBlocks.Edit`, and every mutation here goes through its
 *     `commit`/`undo`/`redo` funnel. This file builds commands; it never
 *     applies one itself.
 *   - Drop-target enumeration. That is `targets.js`, mirrored from
 *     `Edit.Targets.droppable_slots/3`. A drag session holds the set that
 *     module computed and consults it; it never re-derives a rule.
 *
 * ## The one piece of arithmetic that lives here and nowhere else
 *
 * `moveIndexFor`. ADR-0005 decision 4 fixes the command's meaning - a move's
 * target index is read against the slot with the block ALREADY REMOVED - and
 * `edit.js` implements exactly that. But a gap in the rendered canvas is
 * numbered against the slot as it stands NOW, with the dragged block still in
 * it. Dropping a block on the gap after its two later siblings means index 3
 * to the canvas and index 2 to the command. Converting between the two is a
 * gesture-layer concern, so it is here, where a test can reach it, rather than
 * inside an event handler.
 */

import {
  block,
  err,
  fetchPath,
  findBlock,
  mintBlockId,
  ok,
  subtreeIds,
} from "./document.js";
import {
  canRedo,
  canUndo,
  commit,
  createHistory,
  insert,
  move,
  redo,
  remove,
  target,
  undo,
  updateConfig,
} from "./edit.js";
import { describe, paletteEntryFor } from "./palette.js";
import { droppableSlotSet, slotKey } from "./targets.js";

/* =============================================================== the value */

/**
 * A fresh session over one decoded document.
 *
 *     {
 *       document, registry, history,
 *       selectedId,  the block whose chrome is selected, or null
 *       collapsed,   a Set of block ids folded shut
 *       drag,        the live drag session, or null
 *     }
 *
 * `collapsed` is a Set of IDS rather than of layout nodes on purpose: the
 * canvas is rebuilt from scratch after every command, so anything keyed by a
 * rendered element would be lost on the first edit. Keyed by id, a fold
 * survives an insert, a move, an undo, and a document reload of the same
 * fixture - which is the requirement, stated as a data-structure choice.
 */
export function createSession(document, registry, { history = createHistory() } = {}) {
  return {
    document,
    registry,
    history,
    selectedId: null,
    collapsed: new Set(),
    drag: null,
  };
}

/* ================================================================ selection */

/** Selects `id`, or clears the selection when `id` is `null` or unknown. */
export function select(session, id) {
  if (id !== null && !findBlock(session.document, id)) return deselect(session);
  return session.selectedId === id ? session : { ...session, selectedId: id };
}

export const deselect = (session) => select(session, null);

export const selectedBlock = (session) =>
  session.selectedId === null ? null : findBlock(session.document, session.selectedId);

/**
 * The three fields the inspector's Block section shows. `null` when nothing is
 * selected; the schema-driven config form below it is sb-8cm's subject.
 *
 * The root block reports slot `"root"` rather than an empty string: it is in
 * no slot, and saying so in words beats showing a blank an author has to
 * interpret.
 */
export function selectionSummary(session) {
  const node = selectedBlock(session);
  if (!node) return null;

  const position = positionOf(session.document, node.id);
  const { unresolved } = describe(session.registry, node);

  return {
    id: node.id,
    type: node.type,
    slot: position ? position.slot : "root",
    parentId: position ? position.parentId : null,
    index: position ? position.index : null,
    unresolved,
  };
}

/** Where a block currently sits, or `null` for the root and for absentees. */
export function positionOf(doc, id) {
  const path = fetchPath(doc, id);
  return path === null || path.length === 0 ? null : path[path.length - 1];
}

/* ================================================================= collapse */

/** Folds a block shut, or opens it. Idempotent per call, its own inverse. */
export function toggleCollapsed(session, id) {
  const collapsed = new Set(session.collapsed);

  if (collapsed.has(id)) collapsed.delete(id);
  else collapsed.add(id);

  return { ...session, collapsed };
}

export const isCollapsed = (session, id) => session.collapsed.has(id);

export const expandAll = (session) =>
  session.collapsed.size === 0 ? session : { ...session, collapsed: new Set() };

/* ===================================================================== drag */

/**
 * Starts a drag and computes the valid-target set ONCE, which is the whole
 * point of ADR-0005 decision 5 and the reason every accepting slot can light
 * up before the pointer has been anywhere near it.
 *
 * Two sources, one code path:
 *
 *   `{ kind: "move", id }`      an existing block, relocating
 *   `{ kind: "insert", block }` a block the palette just constructed
 *
 * `targets.js` answers both through `droppableSlotsFor`, so a palette drag and
 * a rearrange drag cannot disagree about what is legal.
 */
export function beginDrag(session, source) {
  const candidate =
    source.kind === "move" ? findBlock(session.document, source.id) : source.block;

  if (!candidate) return session;

  return {
    ...session,
    drag: {
      kind: source.kind,
      id: source.kind === "move" ? source.id : candidate.id,
      label: source.label ?? candidate.type,
      candidate,
      slots: droppableSlotSet(session.document, session.registry, candidate),
    },
  };
}

export const endDrag = (session) => (session.drag ? { ...session, drag: null } : session);

/**
 * What `data-drop` a slot carries right now: `"ok"`, `"no"`, or `null` when no
 * drag is running at all. Three states rather than two, because "no drag" and
 * "this slot refuses the dragged block" must not style the same - a canvas
 * where every slot reads as rejecting at rest is a canvas that looks broken.
 */
export function dropStateFor(session, parentId, slot) {
  if (!session.drag) return null;
  return session.drag.slots.has(slotKey({ parentId, slot })) ? "ok" : "no";
}

export const isDropAllowed = (session, parentId, slot) =>
  dropStateFor(session, parentId, slot) === "ok";

/** How many slots the live drag would accept. The drag banner's counter. */
export const droppableCount = (session) => (session.drag ? session.drag.slots.size : 0);

/* ============================================================ the mutations */

/**
 * Converts a CANVAS gap index into a COMMAND index for a move (see the header
 * comment). Returns `to.index` unchanged for an insert, for a cross-slot move,
 * and for a move to an earlier position in the same slot; only a later
 * position in the same slot shifts, and only by one.
 */
export function moveIndexFor(doc, id, to) {
  const from = positionOf(doc, id);

  const sameSlot = from && from.parentId === to.parentId && from.slot === to.slot;
  return sameSlot && from.index < to.index ? to.index - 1 : to.index;
}

/**
 * Completes the live drag at one gap. Refuses - as a value, never a throw -
 * when there is no drag, or when the gap's slot is not in the set computed at
 * drag start. The second check is not belt-and-braces: a keyboard or a stale
 * pointer can reach a gap the highlight never offered, and decision 5's four
 * rules are the editor's only hard refusal.
 */
export function dropAt(session, to) {
  const drag = session.drag;
  if (!drag) return err({ tag: "no_drag" });

  if (!isDropAllowed(session, to.parentId, to.slot)) {
    return err({ tag: "not_droppable", target: to });
  }

  const command =
    drag.kind === "move"
      ? move(drag.id, target(to.parentId, to.slot, moveIndexFor(session.document, drag.id, to)))
      : insert(target(to.parentId, to.slot, to.index), drag.candidate);

  const applied = runCommand(endDrag(session), command);
  if (!applied.ok) return applied;

  return ok(select(applied.value, drag.id));
}

/**
 * The no-drag insertion path (ADR-0005 decision 8). Same command, same
 * predicate, no drag session involved - which is exactly why the record asks
 * for it: everything a drop can do is reachable from a button.
 */
export function insertTypeAt(session, typeName, to) {
  const node = blockForType(session.registry, typeName);
  if (!node) return err({ tag: "unknown_block_type", type: typeName });

  const staged = beginDrag(session, { kind: "insert", block: node });
  return dropAt(staged, to);
}

/**
 * The types a "+" at this position may offer: every registered type whose
 * freshly-constructed block this slot would accept. It runs decision 5's
 * predicate over each candidate rather than reimplementing the four rules, so
 * the picker and the drag highlight can never disagree.
 */
export function typesForSlot(session, parentId, slot) {
  const offered = [];

  for (const typeName of Object.keys(session.registry.types)) {
    const node = blockForType(session.registry, typeName);
    if (!node) continue;

    const slots = droppableSlotSet(session.document, session.registry, node);
    if (!slots.has(slotKey({ parentId, slot }))) continue;

    const descriptor = session.registry.types[typeName];
    const entry = paletteEntryFor(descriptor);

    offered.push({
      type: typeName,
      label: entry.label,
      description: entry.description,
      group: entry.group,
      icon: entry.icon,
      order: entry.order,
    });
  }

  return offered.sort(
    (a, b) =>
      (a.group < b.group ? -1 : a.group > b.group ? 1 : 0) ||
      a.order - b.order ||
      (a.label < b.label ? -1 : a.label > b.label ? 1 : 0)
  );
}

/**
 * Removes a block and selects what was above it, so an author who deletes four
 * steps in a row is not hunting for the cursor between each one. The root is
 * refused here rather than at `edit.js`'s depth so the refusal can carry the
 * gesture's vocabulary.
 */
export function removeBlock(session, id) {
  if (!id) return err({ tag: "nothing_selected" });
  if (session.document.root.id === id) return err({ tag: "cannot_remove_root", id });

  const position = positionOf(session.document, id);
  const applied = runCommand(endDrag(session), remove(id));
  if (!applied.ok) return applied;

  return ok(select(applied.value, position ? position.parentId : null));
}

/** `updateConfig` through the same funnel, so decision 9's gate always runs. */
export function updateBlockConfig(session, id, config) {
  return runCommand(session, updateConfig(id, config));
}

/* ================================================================ undo/redo */

export const canUndoSession = (session) => canUndo(session.history);
export const canRedoSession = (session) => canRedo(session.history);

export function undoSession(session) {
  return replay(session, undo(session.history, session.registry, session.document));
}

export function redoSession(session) {
  return replay(session, redo(session.history, session.registry, session.document));
}

function replay(session, result) {
  if (!result.ok) return result;

  const next = {
    ...endDrag(session),
    history: result.value.history,
    document: bumpRevision(result.value.document),
  };

  // A block that undo removed cannot stay selected, and a stale id in
  // `selectedId` would put the inspector in a state no gesture could produce.
  return ok(select(next, next.selectedId));
}

/* ================================================================= internals */

/*
 * The one funnel. Every mutation in this file goes through `edit.js`'s
 * `commit`, so the config gate, the inverse capture and the redo-stack clear
 * happen once each rather than once per gesture.
 */
function runCommand(session, command) {
  const result = commit(session.history, session.registry, session.document, command);
  if (!result.ok) return result;

  return ok({
    ...session,
    history: result.value.history,
    document: bumpRevision(result.value.document),
  });
}

/*
 * A revision is a monotonic counter, not a position in the undo stack: undoing
 * an insert takes the document forward to a revision that happens to look like
 * an earlier one. Counting every applied command - forward, undone and redone
 * alike - is what makes "revision 12" mean "twelve edits have been applied",
 * which is the only reading under which two sessions cannot land on the same
 * number holding different bytes.
 */
const bumpRevision = (doc) => ({ ...doc, revision: doc.revision + 1 });

/**
 * A brand-new block of one registered type, its config seeded from the
 * declared defaults in `configSchema/1`.
 *
 * Two passes over the schema, because a schema is a function OF the config -
 * `core.branch` publishes one expression field per arm - so the fields a block
 * declares once it holds its own defaults are not always the fields it
 * declared while empty. Two passes reach the fixed point for every shape the
 * spike's vocabulary has; a type whose schema oscillates would need a real
 * fixed-point loop, and none does.
 */
export function blockForType(registry, typeName) {
  const descriptor = registry.types[typeName];
  if (!descriptor) return null;

  let config = {};

  for (let pass = 0; pass < 2; pass += 1) {
    config = seedConfig(descriptor, config);
  }

  return block({ id: mintBlockId(), type: typeName, typeVersion: descriptor.currentVersion, config });
}

function seedConfig(descriptor, config) {
  const seeded = {};

  for (const field of safeSchema(descriptor, config)) {
    if (field.default === undefined) continue;
    writeValuePath(seeded, field.valuePath ?? [field.key], field.default);
  }

  return seeded;
}

function safeSchema(descriptor, config) {
  try {
    return descriptor.configSchema(config) ?? [];
  } catch {
    return [];
  }
}

/*
 * The write half of `layout.js`'s `readValuePath`: string keys build objects,
 * integer keys build arrays. Written with `defineProperty` at every step for
 * the reason `document.js` gives - a `valuePath` is data, and a `"__proto__"`
 * segment must create an own key rather than move the prototype.
 */
function writeValuePath(root, path, value) {
  let cursor = root;

  for (let index = 0; index < path.length - 1; index += 1) {
    const segment = path[index];
    const existing = Object.hasOwn(cursor, segment) ? cursor[segment] : undefined;
    const child =
      existing !== null && typeof existing === "object"
        ? existing
        : Number.isInteger(path[index + 1])
          ? []
          : {};

    define(cursor, segment, child);
    cursor = child;
  }

  if (path.length > 0) define(cursor, path[path.length - 1], value);

  return root;
}

function define(host, key, value) {
  Object.defineProperty(host, key, {
    value,
    enumerable: true,
    writable: true,
    configurable: true,
  });
}

/**
 * How many blocks a folded subtree is hiding - the collapsed card's count.
 * Built on `subtreeIds`, which is the walk the whole spike counts with, minus
 * the block itself: a folded group reports what is INSIDE it, not what is
 * inside it plus itself.
 */
export function descendantCount(doc, id) {
  const node = findBlock(doc, id);
  return node ? subtreeIds(node).size - 1 : 0;
}
