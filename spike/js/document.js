/*
 * spike/js/document.js - the block document model, mirrored in the browser.
 *
 * A client-side mirror of `StatifierBlocks.Document` and
 * `StatifierBlocks.Block` (ADR-0001), built so the spike's canvas has a real
 * tree to render, a real path walk to lay out from, and real bytes to
 * round-trip. It is deliberately NOT a second implementation of the shipped
 * editor: ADR-0005's architecture is server-side commands over these same
 * semantics, and this file exists only so the visual work can happen without
 * a server in the loop.
 *
 * Where this file and an accepted ADR disagree, the ADR is the contract and
 * this file is the bug.
 *
 * ## The in-memory shape
 *
 * A block is `{ id, type, typeVersion, config, slots }` and nothing else
 * (ADR-0001 decision 2); a document is
 * `{ schemaVersion, id, revision, root, metadata }`. The stored spelling is
 * snake_case (`type_version`, `schema_version`) and the in-memory spelling is
 * camelCase, because JavaScript reads better that way and the translation
 * happens in exactly two places - `fromJson` and `toJsonValue`. Nothing else
 * in the spike may spell a stored key.
 *
 * ## Results, not exceptions
 *
 * Every operation that can fail returns `ok(value)` or `err(reason)`, where
 * `reason` is a plain object carrying a `tag` - the JS spelling of the
 * package's `{:no_such_block, id}` tuples. ADR-0002 decision 3's discipline
 * (an ordered check, one arm per distinguishable cause, nothing rescued to a
 * default and nothing raised) is the whole reason the editor can render an
 * unresolvable block instead of falling over on it, and it is worth keeping
 * on this side of the wire too.
 *
 * The single exception is `toJson`, which throws on an invalid document, the
 * same way `Document.to_json/1` raises rather than producing bytes that only
 * look canonical.
 */

/* ------------------------------------------------------------- results */

/** A success. */
export function ok(value) {
  return { ok: true, value };
}

/** A typed refusal. `reason.tag` is the JS spelling of an error atom. */
export function err(reason) {
  return { ok: false, error: reason };
}

/* -------------------------------------------------------- construction */

const SCHEMA_VERSION = 1;

let idCounter = 0;

/*
 * ADR-0001 decision 3: ids are `blk_`-prefixed, opaque, document-unique, and
 * never reused. The package mints UXIDs; the spike mints something opaque and
 * unique enough for one browser session, because nothing here parses an id
 * and nothing here outlives the tab.
 *
 * Minting lives outside the command algebra on purpose (ADR-0005 decision 2):
 * the gesture mints the id, and the finished block is baked into the
 * `insert`, which is what keeps the command replayable.
 */
export function mintBlockId() {
  idCounter += 1;
  const entropy = Math.random().toString(36).slice(2, 8);
  return `blk_${entropy}${idCounter.toString(36).padStart(3, "0")}`;
}

export function mintDocumentId() {
  const entropy = Math.random().toString(36).slice(2, 10);
  return `bdoc_${entropy}`;
}

/** A block. `slots` maps a slot name to an ordered list of child blocks. */
export function block({ id, type, typeVersion = 1, config = {}, slots = {} }) {
  return { id: id ?? mintBlockId(), type, typeVersion, config, slots };
}

/** A document envelope around one root block (ADR-0001 decision 1). */
export function createDocument(root, { id, revision = 0, metadata = {} } = {}) {
  return {
    schemaVersion: SCHEMA_VERSION,
    id: id ?? mintDocumentId(),
    root,
    revision,
    metadata,
  };
}

/* ------------------------------------------------------------ traversal */

/*
 * Every block, pre-order, root first, with slots visited in UTF-8-sorted
 * slot-name order - `Document.blocks/1`'s order exactly. The sort is what
 * makes the walk deterministic regardless of how the `slots` object happened
 * to be built, and every other walk in the spike is built on this one rather
 * than re-deriving its own.
 */
export function blocks(document) {
  return walk(document.root);
}

function walk(node) {
  const children = sortedSlotNames(node.slots).flatMap((name) =>
    node.slots[name].flatMap(walk)
  );
  return [node, ...children];
}

/** Slot names in UTF-8 byte order. See `compareUtf8` for why not `sort()`. */
export function sortedSlotNames(slots) {
  return Object.keys(slots).sort(compareUtf8);
}

/** The block carrying `id`, or `null`. */
export function findBlock(document, id) {
  return blocks(document).find((candidate) => candidate.id === id) ?? null;
}

/**
 * The path from the root to the block carrying `id`: the ordered
 * `{ parentId, slot, index }` steps taken from the root (ADR-0001 decision
 * 5). The root's own path is `[]` - it has taken none - and a `null` return
 * is the `:error` arm of `Document.fetch_path/2`.
 */
export function fetchPath(document, id) {
  if (document.root.id === id) return [];
  return findPath(document.root, id);
}

function findPath(node, id) {
  for (const slot of sortedSlotNames(node.slots)) {
    const children = node.slots[slot];

    for (let index = 0; index < children.length; index += 1) {
      const child = children[index];
      const step = { parentId: node.id, slot, index };

      if (child.id === id) return [step];

      const rest = findPath(child, id);
      if (rest !== null) return [step, ...rest];
    }
  }

  return null;
}

/** The block one step above `id`, or `null` for the root and for absentees. */
export function parentOf(document, id) {
  const path = fetchPath(document, id);
  if (path === null || path.length === 0) return null;
  return findBlock(document, path[path.length - 1].parentId);
}

/** A slot's children, where an absent slot key reads back as `[]`. */
export function slotChildren(node, slot) {
  return node.slots[slot] ?? [];
}

/** Every id in `node`'s own subtree, `node` included (ADR-0005 rule 4). */
export function subtreeIds(node) {
  const ids = new Set([node.id]);

  for (const slot of sortedSlotNames(node.slots)) {
    for (const child of node.slots[slot]) {
      for (const id of subtreeIds(child)) ids.add(id);
    }
  }

  return ids;
}

/* ----------------------------------------------------------- validation */

/*
 * ADR-0001's structural rules: the envelope, then every block pre-order, then
 * document-wide id uniqueness. Registry-free by construction - nothing here
 * resolves a `type` against anything, and `config` is checked for its value
 * grammar only (decision 6: no floats).
 *
 * Returns `null` when the document is sound, or a reason object otherwise.
 */
export function validate(document) {
  const envelope = validateEnvelope(document);
  if (envelope) return envelope;

  const seen = new Set();
  return validateTree(document.root, seen);
}

function validateEnvelope(document) {
  if (document.schemaVersion !== SCHEMA_VERSION) {
    return { tag: "unsupported_schema_version", version: document.schemaVersion };
  }
  if (!nonEmptyString(document.id)) {
    return { tag: "malformed_envelope", field: "id" };
  }
  if (!Number.isInteger(document.revision) || document.revision < 0) {
    return { tag: "malformed_envelope", field: "revision" };
  }
  if (!isJsonObject(document.metadata)) {
    return { tag: "malformed_envelope", field: "metadata" };
  }

  const metadataProblem = jsonProblem(document.metadata);
  if (metadataProblem) {
    return { tag: "malformed_envelope", field: "metadata", problem: metadataProblem };
  }

  if (!isJsonObject(document.root)) {
    return { tag: "malformed_envelope", field: "root" };
  }
  return null;
}

function validateTree(node, seen) {
  const reportedId = nonEmptyString(node.id) ? node.id : null;

  if (!nonEmptyString(node.id)) {
    return { tag: "malformed_block", id: reportedId, field: "id" };
  }
  if (!nonEmptyString(node.type)) {
    return { tag: "malformed_block", id: reportedId, field: "type" };
  }
  if (!Number.isInteger(node.typeVersion) || node.typeVersion < 1) {
    return { tag: "malformed_block", id: reportedId, field: "type_version" };
  }
  if (!isJsonObject(node.config)) {
    return { tag: "malformed_block", id: reportedId, field: "config" };
  }

  const configProblem = jsonProblem(node.config);
  if (configProblem) {
    return { tag: "malformed_block", id: reportedId, field: "config", problem: configProblem };
  }

  if (!isJsonObject(node.slots)) {
    return { tag: "malformed_block", id: reportedId, field: "slots" };
  }

  if (seen.has(node.id)) return { tag: "duplicate_block_id", id: node.id };
  seen.add(node.id);

  for (const slot of sortedSlotNames(node.slots)) {
    const children = node.slots[slot];

    if (!nonEmptyString(slot) || !Array.isArray(children)) {
      return { tag: "malformed_block", id: reportedId, field: "slots", slot };
    }

    for (const child of children) {
      if (!isJsonObject(child)) {
        return { tag: "malformed_block", id: reportedId, field: "slots", slot };
      }
      const problem = validateTree(child, seen);
      if (problem) return problem;
    }
  }

  return null;
}

/*
 * ADR-0001 decision 6's value grammar: null, booleans, integers, strings,
 * arrays of the same, and objects with string keys. A float is rejected by
 * name rather than as a generic non-JSON value, because the no-floats rule is
 * the surprising one and an author who trips it deserves to be told which
 * rule they hit. Returns a problem object or `null`.
 */
function jsonProblem(value, path = []) {
  if (value === null) return null;

  const type = typeof value;

  if (type === "boolean" || type === "string") return null;

  if (type === "number") {
    return Number.isInteger(value) ? null : { tag: "float", path };
  }

  if (Array.isArray(value)) {
    for (let index = 0; index < value.length; index += 1) {
      const problem = jsonProblem(value[index], [...path, index]);
      if (problem) return problem;
    }
    return null;
  }

  if (isJsonObject(value)) {
    for (const key of Object.keys(value)) {
      if (typeof key !== "string") return { tag: "not_json", path };
      const problem = jsonProblem(value[key], [...path, key]);
      if (problem) return problem;
    }
    return null;
  }

  return { tag: "not_json", path };
}

function isJsonObject(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function nonEmptyString(value) {
  return typeof value === "string" && value !== "";
}

/* -------------------------------------------------------- serialization */

/**
 * The document as a plain JSON value, in the stored spelling: `type_version`,
 * `schema_version`, empty `config`/`metadata`/`slots` omitted, and a slot
 * whose list is empty omitted from `slots` entirely (ADR-0001 decision 8).
 */
export function toJsonValue(document) {
  const value = {
    id: document.id,
    revision: document.revision,
    root: blockToJsonValue(document.root),
    schema_version: document.schemaVersion,
  };

  if (Object.keys(document.metadata).length > 0) value.metadata = document.metadata;

  return value;
}

function blockToJsonValue(node) {
  const value = {
    id: node.id,
    type: node.type,
    type_version: node.typeVersion,
  };

  if (Object.keys(node.config).length > 0) value.config = node.config;

  const slots = {};
  for (const slot of sortedSlotNames(node.slots)) {
    const children = node.slots[slot];
    if (children.length > 0) slots[slot] = children.map(blockToJsonValue);
  }
  if (Object.keys(slots).length > 0) value.slots = slots;

  return value;
}

/**
 * Canonical JSON per ADR-0001 decision 8: object keys sorted by their UTF-8
 * bytes, no insignificant whitespace, empty containers omitted, no floats.
 * Two encodes of equal documents are byte-identical, which is what makes the
 * round-trip law testable.
 *
 * Throws on an invalid document rather than producing bytes that only look
 * canonical - `Document.to_json/1` raises for the same reason.
 */
export function toJson(document) {
  const problem = validate(document);
  if (problem) {
    throw new Error(`cannot encode an invalid document: ${JSON.stringify(problem)}`);
  }
  return canonicalStringify(toJsonValue(document));
}

function canonicalStringify(value) {
  if (value === null || typeof value === "boolean" || typeof value === "number") {
    return JSON.stringify(value);
  }
  if (typeof value === "string") return JSON.stringify(value);

  if (Array.isArray(value)) {
    return `[${value.map(canonicalStringify).join(",")}]`;
  }

  const pairs = Object.keys(value)
    .sort(compareUtf8)
    .map((key) => `${JSON.stringify(key)}:${canonicalStringify(value[key])}`);

  return `{${pairs.join(",")}}`;
}

/*
 * Decision 8 sorts object keys by their UTF-8 bytes; JavaScript's default
 * string comparison is UTF-16 code-unit order, and the two disagree for
 * astral-plane characters (a surrogate pair sorts below U+E000 in UTF-16 and
 * above it in UTF-8). No key in this package's own vocabulary is affected,
 * but a host's config key could be, and getting it right costs six lines.
 */
const utf8 = new TextEncoder();

export function compareUtf8(left, right) {
  if (left === right) return 0;

  const a = utf8.encode(left);
  const b = utf8.encode(right);
  const shared = Math.min(a.length, b.length);

  for (let index = 0; index < shared; index += 1) {
    if (a[index] !== b[index]) return a[index] < b[index] ? -1 : 1;
  }

  return a.length - b.length;
}

/**
 * Structural decode (ADR-0001 decision 9): validates the envelope and the
 * tree and never consults a block-type registry, so a document naming a block
 * type this palette has never heard of decodes successfully. Accepts a JSON
 * string or an already-parsed value.
 */
export function fromJson(input) {
  let raw = input;

  if (typeof input === "string") {
    try {
      raw = JSON.parse(input);
    } catch (error) {
      return err({ tag: "not_a_block_document", detail: String(error) });
    }
  }

  if (!isJsonObject(raw) || !("schema_version" in raw)) {
    return err({ tag: "not_a_block_document" });
  }

  const decoded = {
    schemaVersion: raw.schema_version,
    id: raw.id,
    revision: raw.revision ?? 0,
    root: isJsonObject(raw.root) ? blockFromJsonValue(raw.root) : raw.root,
    metadata: raw.metadata ?? {},
  };

  const problem = validate(decoded);
  return problem ? err(problem) : ok(decoded);
}

function blockFromJsonValue(raw) {
  const slots = {};

  if (isJsonObject(raw.slots)) {
    for (const slot of Object.keys(raw.slots)) {
      const children = raw.slots[slot];
      slots[slot] = Array.isArray(children)
        ? children.map((child) => (isJsonObject(child) ? blockFromJsonValue(child) : child))
        : children;
    }
  }

  return {
    id: raw.id,
    type: raw.type,
    typeVersion: raw.type_version ?? 1,
    config: raw.config ?? {},
    slots,
  };
}

/* ------------------------------------------------------ structural edits */

/*
 * The two rewrites `edit.js` is built out of. They live here because they are
 * about the tree rather than about the command algebra, and because keeping
 * them next to the walk that produces a path is what stops the two drifting.
 *
 * Both are non-destructive: the blocks along the path are rebuilt and every
 * other node is shared, so a previous document stays usable as the undo
 * stack's reference point.
 */

/** Replaces the block at `path` (from the root) with `fn(oldBlock)`. */
export function updateAtPath(node, path, fn) {
  if (path.length === 0) return fn(node);

  const [{ slot, index }, ...rest] = path;
  const children = slotChildren(node, slot);
  const updated = children.slice();
  updated[index] = updateAtPath(children[index], rest, fn);

  return { ...node, slots: { ...node.slots, [slot]: updated } };
}

/**
 * Detaches the block at `path` and prunes the slot key it empties - the
 * symmetry with canonical JSON's omission of empty slots, and what makes
 * `apply(apply(d, e), inverse)` equal `d` structurally rather than merely as
 * equal bytes (`Edit`'s rule 3).
 *
 * Returns `{ node, detached, target }`, where `target` is the position the
 * detached block used to occupy.
 */
export function removeAtPath(node, path) {
  const [{ slot, index }, ...rest] = path;
  const children = slotChildren(node, slot);

  if (rest.length === 0) {
    const remaining = children.slice(0, index).concat(children.slice(index + 1));
    const slots = { ...node.slots };

    if (remaining.length === 0) {
      delete slots[slot];
    } else {
      slots[slot] = remaining;
    }

    return {
      node: { ...node, slots },
      detached: children[index],
      target: { parentId: node.id, slot, index },
    };
  }

  const inner = removeAtPath(children[index], rest);
  const updated = children.slice();
  updated[index] = inner.node;

  return {
    node: { ...node, slots: { ...node.slots, [slot]: updated } },
    detached: inner.detached,
    target: inner.target,
  };
}

/** Inserts `child` into `slot` of `parent` at `index`, creating the slot key. */
export function insertChild(parent, slot, index, child) {
  const children = slotChildren(parent, slot);
  const updated = children.slice(0, index).concat([child], children.slice(index));

  return { ...parent, slots: { ...parent.slots, [slot]: updated } };
}
