/*
 * spike/js/fixtures.js - the Fixtures pane's view model.
 *
 * The pure half of sb-9z3, in the same split `panes.js` keeps against
 * `inspector.js` and `layout.js` keeps against `render.js`: every question the
 * pane has to answer - which step is current, which blocks that makes active,
 * what a run's verdict is after four of its nine steps, which truth tables a
 * selected block owns, whether an author's edited JSON is usable - is
 * answerable without a browser, so it is answered here and asserted in
 * `dev/selftest.html`.
 *
 * ## Everything here REPLAYS. Nothing here computes.
 *
 * The campaign's D4 ruling, verbatim: "chart/block runs are MOCKED (scripted
 * step sequences in fixture JSON - enough to prove the runner UI: step list,
 * active-block highlight via the tree, pass/fail chips). Condition fixtures get
 * a truth-table UI over precomputed expected values; a small real JS predicate
 * evaluator is a stretch bead only. The UX is the deliverable, not the
 * machinery."
 *
 * So: a run is a sequence an author wrote down, a check's result is a value in
 * the file, and a truth table's cells are typed in. There is no interpreter
 * here and no expression evaluator, not even a small one - the file says
 * `"result": "fail"` and the chip goes red. That is a real constraint on what
 * this pane may claim, and it is why the verdict vocabulary below is about
 * REACHING steps rather than about deciding anything: `verdictOf` counts the
 * checks the cursor has consumed, and consuming a check is the only thing that
 * makes it count.
 *
 * ## The one place a design decision hides
 *
 * `expected` on a run is the author's claim about the whole fixture, and the
 * derived `verdict` is what the scripted steps actually record. A fixture whose
 * steps disagree with its own `expected` is the interesting case - it is a
 * fixture that has caught something - so `agrees` is computed and surfaced
 * rather than collapsed into the verdict. Two runs in the shipped fixtures are
 * deliberately in that state.
 */

/* ============================================================ the document */

/**
 * Everything one document's fixtures hold.
 *
 *     { documentId, known, runs: [Run], tables: [Table] }
 *
 * `known` is false when the fixture file has no section for this document at
 * all, which is a different thing from a section holding no runs: the first is
 * "nobody has written fixtures for this yet" and the second is "someone wrote
 * the section and left it empty". The pane says different sentences for them.
 */
export function fixturesFor(data, documentId) {
  const section = data?.documents?.[documentId];

  return {
    documentId,
    known: section !== undefined && section !== null,
    runs: Array.isArray(section?.runs) ? section.runs : [],
    tables: Array.isArray(section?.tables) ? section.tables : [],
  };
}

/** Every block id in this document's fixtures that owns a truth table. */
export function tableBlockIds(fixtures) {
  const seen = [];

  for (const table of fixtures.tables) {
    if (table.blockId && !seen.includes(table.blockId)) seen.push(table.blockId);
  }

  return seen;
}

/** The tables anchored to one block - what the pane shows for a selection. */
export function tablesForBlock(fixtures, blockId) {
  return blockId === null || blockId === undefined
    ? []
    : fixtures.tables.filter((table) => table.blockId === blockId);
}

export function runById(fixtures, runId) {
  return fixtures.runs.find((run) => run.id === runId) ?? null;
}

/* ================================================================= the run */

/*
 * The cursor. `-1` is "not started", `0 .. steps.length - 1` is "sitting on
 * that step", and `steps.length` is "finished". Three regions rather than two,
 * because a run that has finished is not the same state as a run parked on its
 * last step: the last step's active blocks are still highlighted in the second
 * and nothing is highlighted in the first, and a transport that cannot express
 * "done" has to fake the difference with a separate boolean that then drifts.
 */
export const NOT_STARTED = -1;

/** The cursor after one transport gesture, clamped rather than refused. */
export function moveCursor(run, cursor, step) {
  const end = stepsOf(run).length;

  // A run with no steps has nowhere to go. Without this guard the arithmetic
  // lands on 0, which is simultaneously "the first step" and "past the end" -
  // and `runView` reads it as neither, so the transport would enable its
  // buttons for a run that can never advance.
  if (end === 0) return NOT_STARTED;

  const at = Number.isInteger(cursor) ? cursor : NOT_STARTED;

  return Math.max(NOT_STARTED, Math.min(end, at + step));
}

export const resetCursor = () => NOT_STARTED;

/** The cursor a "play to the end" gesture lands on. */
export const endCursor = (run) => (stepsOf(run).length === 0 ? NOT_STARTED : stepsOf(run).length);

const stepsOf = (run) => (Array.isArray(run?.steps) ? run.steps : []);

/**
 * One run at one cursor, as the pane renders it.
 *
 *     {
 *       id, name, description, expected,
 *       cursor, started, finished, stepCount,
 *       progress,     "not run" | "step 3 of 9" | "finished"
 *       activeIds,    the blocks the CURRENT step lights up - [] when not on one
 *       invoke,       the CURRENT step's host call, or null - the canvas badge
 *                     mark reads this the way the highlight reads activeIds
 *       foreach,      the CURRENT step's iteration, or null - which container
 *                     it belongs to, and which authored pass it is
 *       steps: [StepView],
 *       current,      the current StepView, or null
 *       verdict,      "not-run" | "running" | "failing" | "pass" | "fail"
 *       agrees,       true/false once finished, null before
 *       failures,     the consumed checks that failed
 *       bindings      every delta the run has applied so far, last write winning
 *     }
 */
export function runView(run, cursor) {
  const steps = stepsOf(run);
  const at = clamp(cursor, steps.length);
  const started = at > NOT_STARTED;
  const finished = at >= steps.length && steps.length > 0;

  const views = steps.map((step, index) => stepView(step, index, at));
  const current = at >= 0 && at < steps.length ? views[at] : null;

  const failures = views
    .filter((view) => view.consumed && view.check?.result === "fail")
    .map((view) => ({ step: view.index, label: view.label, ...view.check }));

  const verdict = verdictOf({ started, finished, failed: failures.length > 0 });

  return {
    id: run.id,
    name: run.name,
    description: run.description ?? "",
    expected: run.expected === "fail" ? "fail" : "pass",
    cursor: at,
    started,
    finished,
    stepCount: steps.length,
    // Not "not run": the chip beside it already says that, and two identical
    // words side by side read as a rendering bug. Before the replay starts the
    // useful fact is how long it is.
    progress: finished
      ? "finished"
      : started
        ? `step ${at + 1} of ${steps.length}`
        : `${steps.length} step${steps.length === 1 ? "" : "s"}`,
    activeIds: current ? current.active : [],
    // Null on a finished or not-started run for the same reason `activeIds` is
    // empty there: the mark belongs to the step the cursor is ON, and a badge
    // left lit after the transport ran out would go on claiming a call is in
    // flight.
    invoke: current ? current.invoke : null,
    // Null off the current step for `invoke`'s reason, and the reason bites
    // harder here: an iteration marker left lit after the transport ran out
    // would go on saying "pass 2 of the list" over a chart that has finished.
    foreach: current ? current.foreach : null,
    steps: views,
    current,
    verdict,
    agrees: finished ? (verdict === (run.expected === "fail" ? "fail" : "pass")) : null,
    failures,
    bindings: bindingsAt(steps, at),
  };
}

/*
 * A step's own state, and the distinction the transport lives on: `consumed`
 * is "the cursor has been here", which is what makes a check count, and it is
 * true for the current step as well as for the ones behind it. `state` is what
 * the row wears - past, current, future - and a finished run has no current
 * row at all.
 */
function stepView(step, index, cursor) {
  const consumed = cursor >= index;

  return {
    index,
    label: step.label ?? `Step ${index + 1}`,
    note: step.note ?? null,
    event: step.event ?? null,
    active: Array.isArray(step.active) ? step.active : [],
    deltas: Array.isArray(step.deltas) ? step.deltas : [],
    check: step.check ?? null,
    invoke: invokeView(step.invoke),
    foreach: foreachView(step.foreach),
    consumed,
    state: cursor === index ? "current" : consumed ? "past" : "future",
  };
}

/**
 * A step's PROPOSED `invoke` field (sb-ig4), normalized for the pane.
 *
 *     { block, outcome: "done" | "error", payload: [{ name, value }] }
 *
 * or `null` for a step that is not a host call.
 *
 * ## What this does NOT do, and it is the whole point
 *
 * `outcome: "error"` does not make anything walk the block's `on_error`
 * subtree. The step after an error carries its own authored `active`, the same
 * as every other step, and the runner replays it - the honest-replayer rule
 * this file opens with, applied to the one field most likely to be mistaken
 * for machinery. `deltas` are accumulated on an error step exactly as on a
 * successful one; nothing here suppresses or synthesizes a write.
 *
 * Two normalizations, both deliberate:
 *
 *   - a missing `block` drops the whole field. The pane's only job with an
 *     invoke is to mark a card, and an invoke naming no card is a fixture
 *     typo that would otherwise render as a silent no-op;
 *   - anything other than the string "error" reads as "done", the same way
 *     `runView` reads `expected`. A misspelt outcome landing on the safe side
 *     is a rendering that under-claims rather than one that paints a red
 *     failure the author never wrote.
 */
export function invokeView(invoke) {
  if (invoke === null || typeof invoke !== "object" || Array.isArray(invoke)) return null;
  if (typeof invoke.block !== "string" || invoke.block === "") return null;

  const payload =
    invoke.payload !== null && typeof invoke.payload === "object" && !Array.isArray(invoke.payload)
      ? Object.keys(invoke.payload).map((name) => ({ name, value: String(invoke.payload[name]) }))
      : [];

  return {
    block: invoke.block,
    outcome: invoke.outcome === "error" ? "error" : "done",
    payload,
  };
}

/**
 * A step's PROPOSED `foreach` field (sb-9nn), normalized for the pane.
 *
 *     { block, index: integer | null, item: string | null }
 *
 * or `null` for a step that is not inside an iteration.
 *
 * ## Every one of those three values is TYPED IN, and that is the whole point
 *
 * A run over a list is the case a replayer is most likely to be mistaken for a
 * loop, so nothing here counts anything. `index` is the ordinal the fixture's
 * author wrote down, not a counter this module keeps: two steps in a row may
 * both say `0`, an author may skip from `0` to `2`, and the pane reports what
 * is there. `item` is display-only source text under the same string rule the
 * deltas hold to, and nothing reads it back. The runner does not iterate, does
 * not know how long the list is, and does not check `index` against it - which
 * is D4's honest-replayer rule applied to the field most likely to look like
 * machinery, exactly as `invokeView` above applies it to `outcome`.
 *
 * Three normalizations, the first two `invokeView`'s and the third this
 * field's own:
 *
 *   - a missing `block` drops the whole field, for `invokeView`'s reason: the
 *     pane's job with it is to name a card, and a foreach naming no card is a
 *     fixture typo that would otherwise render as a silent no-op;
 *   - anything unusable lands on the quiet side rather than being invented;
 *   - a non-integer or negative `index` becomes `null` rather than `0`. `0` is
 *     a legitimate ordinal - it is the FIRST pass - so coercing a malformed
 *     value to it would put a wrong iteration number on screen, which is worse
 *     than putting none there. `null` renders as "an iteration, position not
 *     recorded"; `0` would render as a claim.
 */
export function foreachView(foreach) {
  if (foreach === null || typeof foreach !== "object" || Array.isArray(foreach)) return null;
  if (typeof foreach.block !== "string" || foreach.block === "") return null;

  return {
    block: foreach.block,
    index: Number.isInteger(foreach.index) && foreach.index >= 0 ? foreach.index : null,
    item:
      foreach.item === undefined || foreach.item === null || foreach.item === ""
        ? null
        : String(foreach.item),
  };
}

/*
 * The five verdicts, and why "failing" is one of them. A run whose fourth step
 * failed its check is not "pending" - the fixture has already lost - and it is
 * not "fail" either, because five steps remain and their checks are still
 * unknown. Collapsing the two would either hide a failure until the end or
 * claim a final verdict the run has not reached, and the whole point of a
 * step-through transport is to be able to see the moment it went wrong.
 */
function verdictOf({ started, finished, failed }) {
  if (!started) return "not-run";
  if (finished) return failed ? "fail" : "pass";
  return failed ? "failing" : "running";
}

/*
 * The datamodel as the run has written it up to `cursor` - last write wins,
 * insertion order kept, so the list reads as "what this run has established"
 * rather than as a replay log. Display only: these are strings out of the
 * fixture, not values, and nothing reads them back.
 */
export function bindingsAt(steps, cursor) {
  const order = [];
  const byPath = new Map();

  for (let index = 0; index <= cursor && index < steps.length; index += 1) {
    for (const delta of steps[index].deltas ?? []) {
      if (!byPath.has(delta.path)) order.push(delta.path);
      byPath.set(delta.path, { path: delta.path, value: delta.value, step: index });
    }
  }

  return order.map((path) => byPath.get(path));
}

/** The chip a run's row wears in the list, before it is opened. */
export function runSummary(run) {
  const steps = stepsOf(run);

  return {
    id: run.id,
    name: run.name,
    description: run.description ?? "",
    expected: run.expected === "fail" ? "fail" : "pass",
    stepCount: steps.length,
    checkCount: steps.filter((step) => step.check).length,
    // Counted through `invokeView` rather than off the raw key, so a malformed
    // `invoke` counts the same in the list as it renders in the runner: not at
    // all. A row promising "2 host calls" over a run that shows one is the
    // sort of drift a summary computed a second way always eventually has.
    invokeCount: steps.filter((step) => invokeView(step.invoke) !== null).length,
  };
}

function clamp(cursor, length) {
  const at = Number.isInteger(cursor) ? cursor : NOT_STARTED;
  return Math.max(NOT_STARTED, Math.min(length, at));
}

/* ========================================================== the truth table */

/**
 * One truth table, flattened for rendering.
 *
 *     {
 *       id, name, description, blockId,
 *       columns: [{ key, label, expr }],
 *       paths,                        the datamodel paths the rows bind
 *       rows: [{ name, note, bindings: [{path, value}], cells: [{key, expected}] }],
 *       trueCounts                    per column, how many rows expect true
 *     }
 *
 * Every `expected` is FIXTURE DATA. Nothing evaluates `expr`; it is shown so a
 * reader can check the table against the condition themselves, which is the
 * only checking that happens here at all.
 */
export function tableView(table) {
  const columns = (table.columns ?? []).map((column) => ({
    key: column.key,
    label: column.label ?? column.key,
    expr: column.expr ?? "",
  }));

  const paths = Array.isArray(table.paths) ? table.paths : derivePaths(table);

  const rows = (table.rows ?? []).map((row, index) => ({
    index,
    name: row.name ?? `Row ${index + 1}`,
    note: row.note ?? null,
    bindings: paths.map((path) => ({ path, value: row.bindings?.[path] ?? "—" })),
    cells: columns.map((column) => ({
      key: column.key,
      label: column.label,
      // Tri-state on purpose: a table that grows a column and does not fill it
      // in must read as "nobody said" rather than as false, which is the one
      // wrong answer a truth table can give.
      expected: row.expected?.[column.key] === undefined ? null : row.expected[column.key] === true,
    })),
  }));

  return {
    id: table.id,
    name: table.name ?? table.id,
    description: table.description ?? "",
    blockId: table.blockId ?? null,
    columns,
    paths,
    rows,
    // Counted off the FLATTENED cells, not off the raw rows: `rows` above is
    // already the view, and a view row has `cells` rather than `expected`.
    // Reading the raw shape here counted zero for every column and looked
    // plausible doing it.
    trueCounts: columns.map(
      (column, index) => rows.filter((row) => row.cells[index]?.expected === true).length
    ),
  };
}

/* Every path any row binds, in first-seen order - for a table that did not
 * declare its own `paths`. Declared beats derived, because the declaration is
 * also the column ORDER and a derived set would reorder itself as rows change. */
function derivePaths(table) {
  const seen = [];

  for (const row of table.rows ?? []) {
    for (const path of Object.keys(row.bindings ?? {})) {
      if (!seen.includes(path)) seen.push(path);
    }
  }

  return seen;
}

/* ======================================================== the JSON editor */

/**
 * An author's edited fixture text, parsed and shape-checked.
 *
 *     { ok: true, value }
 *     { ok: false, message, line, column }
 *
 * A refusal is a value, not an exception - the same rule `session.js` and
 * `edit.js` hold to - because the pane has to render the reason under the
 * textarea and a thrown error reaches it as nothing at all.
 *
 * `line` and `column` are best-effort: engines report a JSON syntax error's
 * position differently and some report none, so the caller must handle `null`.
 * Recovering the position when it IS available is worth the regex - "expected
 * ',' at line 214" is a fixable message and "Unexpected token }" is not.
 */
export function parseFixtures(text) {
  let value;

  try {
    value = JSON.parse(text);
  } catch (error) {
    const message = String(error?.message ?? error);
    return { ok: false, message, ...positionOf(message, text) };
  }

  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    return {
      ok: false,
      message: "The fixture file must be a JSON object.",
      line: null,
      column: null,
    };
  }

  if (value.documents === undefined) {
    return {
      ok: false,
      message: "No `documents` key. Runs and tables are keyed by document id under it.",
      line: null,
      column: null,
    };
  }

  // `typeof [] === "object"`, so the array case has to be named. A `documents`
  // array parses and then indexes to `undefined` for every document id, which
  // reaches the author as "no fixtures for this document" - a wrong answer
  // rather than a refusal.
  if (value.documents === null || typeof value.documents !== "object" || Array.isArray(value.documents)) {
    return {
      ok: false,
      message: "`documents` must be an object keyed by document id.",
      line: null,
      column: null,
    };
  }

  return { ok: true, value };
}

/*
 * Two shapes of engine message, and a character offset turned into a line and
 * a column. V8 says "at position 214 (line 9 column 3)" in newer builds and
 * only "at position 214" in older ones; JavaScriptCore and SpiderMonkey say
 * "at line 9 column 3". Taking whichever is present rather than picking one
 * engine's format.
 */
function positionOf(message, text) {
  const lineColumn = /line (\d+) column (\d+)/.exec(message);
  if (lineColumn) return { line: Number(lineColumn[1]), column: Number(lineColumn[2]) };

  const offset = /position (\d+)/.exec(message);
  if (offset) return at(text, Number(offset[1]));

  /*
   * The one family of message that carries no position at all, and it is the
   * one an editing author hits most (sb-9z3's note, item 11): delete a closing
   * brace, or stop typing mid-object, and every engine says some version of
   * "unexpected end of JSON input" with nothing to point at. Nothing to point
   * at is not the same as nowhere to point: the parser ran out of input, so
   * the place it ran out is the END of the text, and that is where the author's
   * missing bracket goes.
   *
   * Matched on "end of" rather than on any one engine's wording, and NOT
   * generalised to every position-less message - a message we cannot place is
   * still reported without a place, because a confident wrong line number
   * costs an author more than an honest missing one.
   */
  if (/end of (the )?(JSON )?(input|data|file|document)/i.test(message)) return at(text, text.length);

  return { line: null, column: null };
}

/** A character offset into the edited text, as a 1-based line and column. */
function at(text, offset) {
  const lines = text.slice(0, offset).split("\n");
  return { line: lines.length, column: lines[lines.length - 1].length + 1 };
}

/** The pretty-printed text the editor opens on. Two spaces, as the file is. */
export const fixturesText = (data) => JSON.stringify(data, null, 2);
