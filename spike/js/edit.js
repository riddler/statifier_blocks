/*
 * spike/js/edit.js - the command algebra and its history, mirrored.
 *
 * A client-side mirror of `StatifierBlocks.Edit` and
 * `StatifierBlocks.Edit.History` (ADR-0005 decisions 2, 3, 4 and 9). The
 * shipped editor builds these commands on the server and re-renders; the
 * spike builds them in the browser so the canvas work can happen without one.
 * The SEMANTICS are the contract, and they are mirrored exactly.
 *
 * ## Four commands, closed set, each a serializable value
 *
 *   | Command                                       | Meaning                         |
 *   |-----------------------------------------------|---------------------------------|
 *   | `{ op: "insert", target, block }`             | put this block (and its subtree) here |
 *   | `{ op: "remove", id }`                        | detach this block and its subtree     |
 *   | `{ op: "move", id, target }`                  | relocate an existing block            |
 *   | `{ op: "updateConfig", id, config }`          | replace one block's config            |
 *
 * A target is `{ parentId, slot, index }` - ADR-0001 decision 5's path
 * element, unchanged.
 *
 * Four, not seven, because the obvious extras are not primitive. Reordering
 * within a slot is a `move` whose target parent and slot happen to match the
 * source; duplication is an `insert` of a subtree whose ids were freshly
 * minted before the command was built; inserting from the palette is an
 * `insert` of a block the palette constructed. Collapsing them means there is
 * ONE code path that puts a block into a slot.
 *
 * ## The four structural rules
 *
 * 1. A target's index is read against the slot's current children, where an
 *    absent slot key means `[]`. Valid indices are `0..children.length`
 *    inclusive.
 * 2. An absent slot key is CREATED by an insert or a move into it - a
 *    declared slot with no children carries no key at all in canonical JSON,
 *    so refusing to create it would break the commonest drop there is.
 * 3. A remove PRUNES a slot key that it empties. Symmetric with rule 2, and
 *    it is what makes `apply(apply(d, e), inverse)` equal `d` structurally
 *    rather than merely as equal bytes.
 * 4. A `move` reads its target index against the slot with the moved block
 *    ALREADY REMOVED (ADR-0005 decision 4). Concretely: detach, then insert.
 *    Moving from index 1 to index 3 of the same five-child slot means
 *    "remove it, then insert at 3 of the remaining four".
 *
 * ## The four inverses
 *
 *   | Command          | Inverse                                        |
 *   |------------------|------------------------------------------------|
 *   | `insert`         | `remove` of the inserted block's id            |
 *   | `remove`         | `insert` of the detached subtree at its position |
 *   | `move`           | `move` back to the original target              |
 *   | `updateConfig`   | `updateConfig` to the previous config           |
 *
 * The move inverse carries the SAME index the block came from, because
 * removing at `i` and re-inserting at `i` in the shortened list is the
 * identity - true whether or not the source and target slots are the same.
 *
 * ## Purely structural, gated one layer up
 *
 * `applyCommand` takes no registry: it never runs `validateConfig`, never
 * checks whether a slot is declared, and never asks a block type anything.
 * ADR-0005 decision 9's gate ("an `update_config` reaches the document only
 * when `validateConfig` returns ok") lives in `checkConfig` and is enforced
 * by the history, which is the only thing an editor should call.
 */

import {
  err,
  fetchPath,
  findBlock,
  insertChild,
  ok,
  removeAtPath,
  subtreeIds,
  updateAtPath,
} from "./document.js";
import { describe } from "./palette.js";

/* ------------------------------------------------------ command builders */

export const insert = (target, node) => ({ op: "insert", target, block: node });
export const remove = (id) => ({ op: "remove", id });
export const move = (id, target) => ({ op: "move", id, target });
export const updateConfig = (id, config) => ({ op: "updateConfig", id, config });

export const target = (parentId, slot, index) => ({ parentId, slot, index });

/* --------------------------------------------------------------- apply */

/**
 * Applies one command, returning `{ document, inverse }`. Total: it refuses
 * rather than throwing, and the refusal names one distinguishable cause.
 */
export function applyCommand(doc, command) {
  switch (command.op) {
    case "insert":
      return applyInsert(doc, command);
    case "remove":
      return applyRemove(doc, command);
    case "move":
      return applyMove(doc, command);
    case "updateConfig":
      return applyUpdateConfig(doc, command);
    default:
      return err({ tag: "unknown_command", op: command.op });
  }
}

function applyInsert(doc, { target: to, block: node }) {
  const slotName = checkSlotName(to);
  if (slotName) return slotName;

  const parent = findBlock(doc, to.parentId);
  if (!parent) return err({ tag: "no_such_block", id: to.parentId });

  const duplicate = firstDuplicateId(doc, node);
  if (duplicate) return err({ tag: "duplicate_block_id", id: duplicate });

  const range = checkIndex(parent, to);
  if (range) return range;

  const path = fetchPath(doc, to.parentId);
  const root = updateAtPath(doc.root, path, (found) =>
    insertChild(found, to.slot, to.index, node)
  );

  return ok({ document: { ...doc, root }, inverse: remove(node.id) });
}

function applyRemove(doc, { id }) {
  const node = findBlock(doc, id);
  if (!node) return err({ tag: "no_such_block", id });
  if (doc.root.id === id) return err({ tag: "cannot_remove_root", id });

  const path = fetchPath(doc, id);
  const { node: root, detached, target: from } = removeAtPath(doc.root, path);

  return ok({ document: { ...doc, root }, inverse: insert(from, detached) });
}

function applyMove(doc, { id, target: to }) {
  const moved = findBlock(doc, id);
  if (!moved) return err({ tag: "no_such_block", id });
  if (doc.root.id === id) return err({ tag: "cannot_remove_root", id });

  // Rule 4's companion invariant: a block cannot become its own descendant,
  // and ADR-0001 decision 1's tree invariant is not negotiable.
  if (subtreeIds(moved).has(to.parentId)) return err({ tag: "would_cycle", id });

  const slotName = checkSlotName(to);
  if (slotName) return slotName;

  // Detach first, so the target index is read against the shortened slot.
  const path = fetchPath(doc, id);
  const { node: withoutRoot, detached, target: from } = removeAtPath(doc.root, path);
  const without = { ...doc, root: withoutRoot };

  const parent = findBlock(without, to.parentId);
  if (!parent) return err({ tag: "no_such_block", id: to.parentId });

  const range = checkIndex(parent, to);
  if (range) return range;

  const parentPath = fetchPath(without, to.parentId);
  const root = updateAtPath(without.root, parentPath, (found) =>
    insertChild(found, to.slot, to.index, detached)
  );

  return ok({ document: { ...without, root }, inverse: move(id, from) });
}

function applyUpdateConfig(doc, { id, config }) {
  const node = findBlock(doc, id);
  if (!node) return err({ tag: "no_such_block", id });

  const path = fetchPath(doc, id);
  const root = updateAtPath(doc.root, path, (found) => ({ ...found, config }));

  return ok({ document: { ...doc, root }, inverse: updateConfig(id, node.config) });
}

/* ---------------------------------------------------------- the checks */

/*
 * The one meaning left to `no_such_slot` once rule 2 allows slot creation: a
 * target whose slot name is not a usable slot key. Commands are serializable
 * values that can arrive from a replayed log, so this is a real arm.
 */
function checkSlotName(to) {
  if (typeof to?.slot === "string" && to.slot !== "") return null;
  return err({ tag: "no_such_slot", parentId: to?.parentId, slot: to?.slot });
}

function checkIndex(parent, to) {
  const children = parent.slots[to.slot] ?? [];
  const inRange = Number.isInteger(to.index) && to.index >= 0 && to.index <= children.length;

  return inRange ? null : err({ tag: "index_out_of_range", target: to });
}

/*
 * ADR-0001 decision 1 makes document-wide id uniqueness an invariant, so an
 * insert carrying an id the document already holds has to be refused rather
 * than produce a document that fails its own validator.
 */
function firstDuplicateId(doc, node) {
  const existing = subtreeIds(doc.root);

  for (const id of subtreeIds(node)) {
    if (existing.has(id)) return id;
  }

  return null;
}

/* ------------------------------------------------- the config gate (d9) */

/**
 * ADR-0005 decision 9's gate. `applyCommand` is purely structural and cannot
 * ask a block type whether a config is valid; this is where that question
 * gets asked.
 *
 * Returns `null` when the command may proceed, or a reason otherwise.
 *
 *   - `insert`, `remove` and `move` never touch a block's config, so there is
 *     nothing for a block type to validate.
 *   - `updateConfig` resolves the named block's CURRENT type and runs its
 *     `validateConfig` against the CANDIDATE config the command carries.
 *   - A block that does not resolve at all passes: there is no authority to
 *     consult, and decision 12 already forbids the editor from offering a
 *     config form for an unresolvable block's config in the first place.
 */
export function checkConfig(registry, doc, command) {
  if (command.op !== "updateConfig") return null;

  const node = findBlock(doc, command.id);
  if (!node) return null;

  const { descriptor, unresolved } = describe(registry, node);
  if (unresolved) return null;

  const findings = descriptor.validateConfig(command.config);
  if (!findings) return null;

  return { tag: "invalid_config", id: command.id, findings };
}

/* -------------------------------------------------------------- history */

/**
 * Undo and redo over commands - not over document snapshots, and not over
 * hand-written inverse pairs (ADR-0005 decision 3). `undo[0]` is what the
 * next `undo()` runs and `redo[0]` is what the next `redo()` runs.
 *
 * `limit` bounds how many entries the undo stack may carry; `Infinity` (the
 * default) never drops one.
 */
export function createHistory({ limit = Infinity } = {}) {
  return { undo: [], redo: [], limit };
}

export const canUndo = (history) => history.undo.length > 0;
export const canRedo = (history) => history.redo.length > 0;

/**
 * The one funnel every editor command goes through: `checkConfig`, then
 * `applyCommand`, then push and clear. A fresh commit invalidates whatever
 * `redo` would have replayed.
 */
export function commit(history, registry, doc, command) {
  const applied = applyGated(registry, doc, command);
  if (!applied.ok) return applied;

  return ok({
    history: {
      ...history,
      undo: bounded([applied.value.inverse, ...history.undo], history.limit),
      redo: [],
    },
    document: applied.value.document,
  });
}

/**
 * Applies the top of the undo stack - the inverse already captured at commit
 * time, so it is already correctly targeted - and moves the NEW inverse onto
 * the redo stack, so `redo` replays the original forward command.
 */
export function undo(history, registry, doc) {
  if (!canUndo(history)) return err({ tag: "nothing_to_undo" });

  const [command, ...rest] = history.undo;
  const applied = applyGated(registry, doc, command);
  if (!applied.ok) return applied;

  return ok({
    history: { ...history, undo: rest, redo: [applied.value.inverse, ...history.redo] },
    document: applied.value.document,
  });
}

/** The mirror of `undo`, in the other direction. */
export function redo(history, registry, doc) {
  if (!canRedo(history)) return err({ tag: "nothing_to_redo" });

  const [command, ...rest] = history.redo;
  const applied = applyGated(registry, doc, command);
  if (!applied.ok) return applied;

  return ok({
    history: {
      ...history,
      redo: rest,
      undo: bounded([applied.value.inverse, ...history.undo], history.limit),
    },
    document: applied.value.document,
  });
}

/*
 * The gate runs on undo and redo too, not only on the initial commit. One
 * code path means one thing to test, and it is the strict reading of decision
 * 9: "invalid config never reaches the document" is a property of every path
 * that can produce a document, not only the first one.
 */
function applyGated(registry, doc, command) {
  const problem = checkConfig(registry, doc, command);
  if (problem) return err(problem);

  return applyCommand(doc, command);
}

function bounded(stack, limit) {
  return limit === Infinity ? stack : stack.slice(0, limit);
}
