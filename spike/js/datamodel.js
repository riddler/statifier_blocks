/*
 * spike/js/datamodel.js - the datamodel tree and the condition source, as values.
 *
 * The pure half of sb-84k, and the same split `panes.js` draws against
 * `inspector.js`: what a scope section contains, which entries survive a
 * filter, which paths a condition names and whether the datamodel declares
 * them are all questions answerable without a browser, so they are answered
 * here and asserted in `dev/selftest.html`. `datamodel-pane.js` and the
 * condition half of `inspector.js` are the translation layers.
 *
 * ## What this file is NOT reading from
 *
 * No accepted ADR defines a datamodel document. `fixtures/datamodel.json` is
 * the SPIKE'S PROPOSAL - three scopes, per-entry `path`/`type`/`label`, an
 * optional `example`, `one_of`, `note`, nested `fields` for an object and
 * `item_type` for a list - and every reading of that shape below is a design
 * decision this bead is making rather than a contract it is implementing. The
 * decisions are written down where they are made, and collected in the bead
 * note for the campaign learnings doc. When a record does land, the disagreement
 * is this file's bug, not the record's.
 *
 * ## The one thing the condition half is not
 *
 * It is not an evaluator, and there is no path to becoming one here. It
 * TOKENIZES for display and it LOOKS UP the paths it finds in the datamodel
 * index. "Unknown" therefore means "the datamodel document does not declare
 * this", never "this is wrong" - a host can carry values it has not described,
 * so an unknown path is advisory and an error would be a lie. That asymmetry is
 * why the two treatments are `known` and `unknown` rather than `valid` and
 * `invalid`.
 */

import { highlight } from "./panes.js";

/* ============================================================== the tree */

/*
 * A scope's chrome has to answer one question the tree itself cannot: WHEN is
 * this value there, and who wrote it. That is the whole reason the sections are
 * separated rather than the paths being merged into one alphabetical list -
 * `currency` and `merchant.currency` are the same word about two different
 * lifetimes, and a flat list makes an author pick between them with no
 * information. So the header carries the scope's lifetime as a short line
 * beside its name, straight from the fixture's `description`.
 *
 * `prefix` is the second half of that: the `event` scope's entries are ADDRESSED
 * with an `event.` prefix in a condition, and the header says so once rather
 * than every row repeating it.
 */
const SCOPE_PREFIX = { event: "event." };

/**
 * The whole datamodel as the pane renders it, with `query` applied.
 *
 *     {
 *       version, query, total, matched, empty,
 *       scopes: [{ scope, label, description, prefix, total, matched, nodes }]
 *     }
 *
 * A scope survives the filter when anything under it does; an empty scope is
 * still listed, because "Global has nothing matching" is information and a
 * vanished section reads as a broken pane. `empty` is the document-wide answer.
 */
export function datamodelView(doc, rawQuery = "") {
  const query = String(rawQuery ?? "").trim();
  const needle = query.toLowerCase();
  const scopes = Array.isArray(doc?.scopes) ? doc.scopes : [];

  const built = scopes.map((scope) => {
    const nodes = (Array.isArray(scope.entries) ? scope.entries : [])
      .map((entry) => entryNode(entry, needle, 0))
      .filter((node) => node !== null);

    return {
      scope: scope.scope,
      label: scope.label ?? scope.scope,
      description: scope.description ?? "",
      prefix: SCOPE_PREFIX[scope.scope] ?? "",
      total: countLeaves(scope.entries),
      // What "n of m match" counts is ENTRIES THAT MATCHED, not rows on
      // screen. A matched object drags its five fields into view (see
      // `entryNode`), and counting those as matches would make one hit on
      // `card` read as six - a number the author can see is wrong the moment
      // they look at the highlighting.
      matched: needle === "" ? countNodes(nodes) : countMatched(nodes),
      nodes,
    };
  });

  const total = built.reduce((sum, scope) => sum + scope.total, 0);
  const matched = built.reduce((sum, scope) => sum + scope.matched, 0);

  return {
    version: doc?.version ?? null,
    query,
    total,
    matched,
    empty: needle !== "" && matched === 0,
    scopes: built,
  };
}

/*
 * One entry as a node.
 *
 * The filter rule is deliberately asymmetric, and this is the design decision
 * most likely to be argued with: a parent that matches keeps ALL its children,
 * while a parent that does not keeps only the children that do. Searching
 * "card" should show the whole card object - that is what the author asked
 * about - and searching "last4" should not drag `card.brand` in beside it. The
 * alternative, filtering children independently of the parent, produces the
 * one result everybody reads as a bug: `card` shown with three of its five
 * fields and no indication that two are missing.
 *
 * A node matches on its name, its label, its full path, or its type - the path
 * because an author who has a condition in front of them is searching for
 * `fraud.verdict`, not for "Verdict", and the type because "every datetime in
 * this chart" is a real question a typed tree should be able to answer.
 */
function entryNode(entry, needle, depth) {
  const path = String(entry.path ?? entry.name ?? "");
  const name = String(entry.name ?? path);
  const label = entry.label ?? name;

  const self =
    needle === "" ||
    contains(name, needle) ||
    contains(label, needle) ||
    contains(path, needle) ||
    contains(entry.type, needle);

  const children = (Array.isArray(entry.fields) ? entry.fields : []).map((field) =>
    entryNode(field, self ? "" : needle, depth + 1)
  );

  // Filtered in both branches. A self-matched node's children are built with
  // an empty needle so none of them can be null, which makes the filter a
  // no-op there - but relying on that invariant from a caller's distance is
  // how a null reaches a consumer, and the sabotage run for this suite found
  // exactly that when the invariant was broken.
  const kept = children.filter((child) => child !== null);

  if (!self && kept.length === 0) return null;

  return {
    name,
    path,
    label,
    type: entry.type ?? "string",
    itemType: entry.item_type ?? null,
    example: hasExample(entry) ? entry.example : undefined,
    oneOf: Array.isArray(entry.one_of) ? entry.one_of : null,
    note: entry.note ?? null,
    depth,
    container: kept.length > 0,
    matched: self && needle !== "",
    // Two highlighted runs, because the row shows two names and a filter that
    // lit only one of them would look like it had missed the other. The PATH
    // segment is the primary: it is what an author types into a condition,
    // and the label is the sentence that explains it.
    nameSegments: highlight(name, needle),
    labelSegments: highlight(label, needle),
    children: kept,
  };
}

// `false`, `0` and `""` are all legitimate examples, so presence is asked as
// presence. `example: ""` on `review.resolution` is the point: an empty string
// is the value that arm's condition compares against.
const hasExample = (entry) => Object.hasOwn(entry ?? {}, "example");

const contains = (value, needle) =>
  typeof value === "string" && value.toLowerCase().includes(needle);

function countNodes(nodes) {
  return nodes.reduce((sum, node) => sum + 1 + countNodes(node.children), 0);
}

function countMatched(nodes) {
  return nodes.reduce(
    (sum, node) => sum + (node.matched ? 1 : 0) + countMatched(node.children),
    0
  );
}

function countLeaves(entries) {
  return (Array.isArray(entries) ? entries : []).reduce(
    (sum, entry) => sum + 1 + countLeaves(entry.fields),
    0
  );
}

/**
 * How an entry's type reads on its chip. A list says what it holds, because
 * `list` alone is the one type name that answers nothing: `risk_reasons` being
 * a list is not the fact an author writing a condition against it needs.
 */
export function typeLabel(node) {
  return node.type === "list" && node.itemType ? `list of ${node.itemType}` : node.type;
}

/**
 * The example, rendered. Objects have none by construction (their fields carry
 * their own), a list joins its items, and a string keeps its quotes so that
 * `""` reads as the empty string rather than as a missing example - which is
 * exactly the distinction `review.resolution` turns on.
 */
export function exampleText(node) {
  const value = node.example;
  if (value === undefined) return null;

  if (Array.isArray(value)) {
    return value.length === 0 ? "[]" : value.map(exampleScalar).join(", ");
  }

  return exampleScalar(value);
}

function exampleScalar(value) {
  if (typeof value === "string") return `"${value}"`;
  if (value === null) return "null";
  return String(value);
}

/* ============================================================ the index */

/**
 * Every path the datamodel declares, keyed by the string a condition writes.
 * Containers are indexed too: `card` is a path an author can legitimately name
 * even though a condition usually names one of its fields, and an index that
 * held only leaves would flag `card` unknown while `card.brand` was known.
 */
export function indexPaths(doc) {
  const index = new Map();

  for (const scope of Array.isArray(doc?.scopes) ? doc.scopes : []) {
    walk(scope.entries, scope, index);
  }

  return index;
}

function walk(entries, scope, index) {
  for (const entry of Array.isArray(entries) ? entries : []) {
    const path = String(entry.path ?? entry.name ?? "");

    // `set` rather than a collision check: the fixture's invariant is that a
    // path is unique, and a duplicate would be a fixture bug this lookup has
    // no way to report. The tree is where a reader would see two of them.
    if (path !== "") {
      index.set(path, {
        path,
        name: entry.name ?? path,
        label: entry.label ?? entry.name ?? path,
        type: entry.type ?? "string",
        itemType: entry.item_type ?? null,
        example: hasExample(entry) ? entry.example : undefined,
        oneOf: Array.isArray(entry.one_of) ? entry.one_of : null,
        scope: scope.scope,
        scopeLabel: scope.label ?? scope.scope,
        container: Array.isArray(entry.fields) && entry.fields.length > 0,
      });
    }

    walk(entry.fields, scope, index);
  }
}

/** The ancestors of a dotted path, outermost first - what a reveal unfolds. */
export function ancestorPaths(path) {
  const steps = String(path ?? "").split(".");
  const out = [];

  for (let at = 1; at < steps.length; at += 1) out.push(steps.slice(0, at).join("."));

  return out;
}

/* ======================================================== the condition */

/*
 * A display tokenizer for the predicator surface the fixtures actually use:
 * dotted paths, the comparison operators, `AND`/`OR`/`NOT`, quoted strings,
 * integers, and parentheses. It is not a parser and it does not know precedence
 * - it produces a flat run of tokens for colouring, and an unrecognized
 * character becomes a `text` token rather than an error, because a condition an
 * author is halfway through typing must still render.
 *
 * Both `=` and `==` are accepted. The fixtures write `==`; the placeholder
 * markup this pane replaces wrote `=`; predicator accepts both, and a
 * highlighter that refused one of them would be making a language decision that
 * belongs in predicator-ex, not here.
 */
/*
 * The combinators only. `true`, `false` and `null` are deliberately NOT here:
 * they are values, they are spelled in lower case in every fixture, and
 * treating them as keywords would colour them like `AND` - which reads as
 * structure where the author wrote a literal. They fall through to the word
 * rule and `annotateCondition` recognizes them, which is also what stops
 * `true` from ever being reported as an undeclared datamodel path.
 */
const KEYWORDS = new Set(["AND", "OR", "NOT", "IN", "BETWEEN"]);

const RULES = [
  { kind: "space", re: /^\s+/ },
  { kind: "string", re: /^'(?:[^'\\]|\\.)*'|^"(?:[^"\\]|\\.)*"/ },
  { kind: "number", re: /^-?\d+(?:\.\d+)?/ },
  { kind: "operator", re: /^(?:==|!=|>=|<=|=|>|<)/ },
  { kind: "paren", re: /^[()]/ },
  { kind: "word", re: /^[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*/ },
  { kind: "text", re: /^[^\s]/ },
];

/**
 * `source` as display tokens: `[{ kind, text, path? }]`, where `kind` is one of
 * `space`, `string`, `number`, `operator`, `paren`, `keyword`, `path`, `text`.
 *
 * Concatenating every `text` reproduces the input exactly. That is the property
 * that makes this safe to render from - the pane never rebuilds a condition out
 * of tokens, it only colours the one the document stores.
 */
export function tokenizeCondition(source) {
  let rest = String(source ?? "");
  const tokens = [];

  while (rest.length > 0) {
    for (const rule of RULES) {
      const match = rule.re.exec(rest);
      if (!match) continue;

      const text = match[0];

      if (rule.kind === "word") {
        tokens.push(
          KEYWORDS.has(text.toUpperCase()) && !text.includes(".")
            ? { kind: "keyword", text }
            : { kind: "path", text, path: text }
        );
      } else {
        tokens.push({ kind: rule.kind, text });
      }

      rest = rest.slice(text.length);
      break;
    }
  }

  return tokens;
}

/**
 * The tokens with every `path` resolved against the index: each gains
 * `known` and, when known, the `entry` behind it.
 *
 * `true`, `false` and `null` arrive from the tokenizer as words rather than as
 * keywords (see `KEYWORDS`), so they are recognized here and become `literal`
 * instead of being looked up. Flagging `true` as an undeclared datamodel path
 * is the single most confusing thing this pane could say, and this is the line
 * that stops it.
 */
export function annotateCondition(source, index) {
  return tokenizeCondition(source).map((token) => {
    if (token.kind !== "path") return token;

    if (LITERALS.has(token.text.toLowerCase())) {
      return { kind: "literal", text: token.text };
    }

    const entry = index.get(token.path) ?? null;
    return { ...token, known: entry !== null, entry };
  });
}

const LITERALS = new Set(["true", "false", "null"]);

/**
 * The paths one condition names, de-duplicated in first-appearance order, each
 * marked known or not. This is what the pane's footer counts and what a reader
 * of a screenshot uses to check the claim.
 */
export function conditionPaths(source, index) {
  const seen = new Set();
  const out = [];

  for (const token of annotateCondition(source, index)) {
    if (token.kind !== "path" || seen.has(token.path)) continue;
    seen.add(token.path);
    out.push({ path: token.path, known: token.known, entry: token.entry });
  }

  return out;
}

/* ------------------------------------------- which fields carry a condition */

/**
 * The condition-bearing fields of one selected block, derived from the form
 * `panes.js` already built rather than from a list of block types.
 *
 * That derivation is the decision worth naming: a condition is any field whose
 * declared type is `expression` (ADR-0002 decision 7's field-type set), so a
 * branch's per-arm `cond`, `myapp.guarded_on_event`'s guard and
 * `myapp.timeout_rule`'s guard all arrive here without this file knowing any of
 * those type names, and a host that declares an `expression` field gets the
 * pane for free. A hard-coded list of types would have been shorter and would
 * have been wrong for the first host block type nobody thought of.
 *
 * An unresolvable block (d12) yields nothing at all: its config is read-only
 * bytes with no schema to say which of them is an expression, and guessing
 * would be inventing the schema decision 12 refuses to invent.
 */
export function conditionFields(form) {
  if (!form || form.readOnly) return [];

  return form.fields.filter((field) => field.control === "expression");
}
