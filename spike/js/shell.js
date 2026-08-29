/*
 * spike/js/shell.js - the shell frame's own behaviour, and the canvas mount.
 *
 * Everything here is translation and nothing here is semantics. The tab strip
 * and the theme selector are the shell's own; the document selector fetches a
 * fixture, decodes it through the real model, hands it to `layout.js`, and
 * hands the result to `render.js`. The shell holds the loaded document and
 * the render handle and no other state - which is the same division ADR-0005
 * decision 13 draws between the one stateful component and everything else.
 *
 * Kept as an ES module served straight from disk. No build step, no bundler,
 * no dependency, ever.
 */

import { findBlock, fromJson } from "./document.js";
import { coreTypes, createRegistry, demoTypes, describe } from "./palette.js";
import { fixtureTypes } from "./demo-types.js";
import { proposedCoreTypes } from "./proposed-core.js";
import { fixtureDocuments } from "./fixture-documents.js";
import { createEditor } from "./interact.js";
import { createDatamodelPane } from "./datamodel-pane.js";
import { createFixturesPane } from "./fixtures-pane.js";
import { createTableDrawer } from "./table-drawer.js";
import { tableCountFor } from "./fixtures.js";
import { indexPaths } from "./datamodel.js";
import { createPalettePane } from "./palette-pane.js";
import { createSequence } from "./sequence.js";

const root = document.getElementById("sb-spike");

/* ------------------------------------------------------------------ tabs */

const tabs = Array.from(document.querySelectorAll('[role="tab"]'));

function selectTab(tab) {
  for (const candidate of tabs) {
    const selected = candidate === tab;
    const panel = document.getElementById(
      candidate.getAttribute("aria-controls")
    );

    candidate.setAttribute("aria-selected", String(selected));
    candidate.tabIndex = selected ? 0 : -1;

    if (panel) {
      panel.hidden = !selected;
    }
  }
}

for (const [index, tab] of tabs.entries()) {
  tab.tabIndex = tab.getAttribute("aria-selected") === "true" ? 0 : -1;

  tab.addEventListener("click", () => selectTab(tab));

  // Arrow-key movement is what makes a tab strip a tab strip to a screen
  // reader; it costs four lines and the shell is the right place to get it
  // right once.
  tab.addEventListener("keydown", (event) => {
    const step =
      event.key === "ArrowRight" ? 1 : event.key === "ArrowLeft" ? -1 : 0;
    if (step === 0) return;

    event.preventDefault();
    const next = tabs[(index + step + tabs.length) % tabs.length];
    selectTab(next);
    next.focus();
  });
}

/* ----------------------------------------------------------------- theme */

const themeSelect = document.getElementById("sb-theme");

if (root && themeSelect) {
  /*
   * The select was write-only: it pushed a theme onto the container and never
   * read one back, so it opened claiming "Light" whatever `data-sb-theme` the
   * markup already carried, and a host that shipped the editor pre-set to
   * dark got a control that disagreed with the screen behind it.
   *
   * Reading the attribute back also decides what an UNKNOWN theme does. The
   * container keeps it - the attribute is the host's, and a theme this select
   * has never heard of is a theme the host may well have a stylesheet for -
   * and the select shows nothing selected rather than silently claiming the
   * theme is Light. That is the one honest reading of "the control does not
   * know what is on screen".
   */
  const current = root.getAttribute("data-sb-theme") ?? "";
  const known = [...themeSelect.options].some((option) => option.value === current);
  themeSelect.value = known ? current : "";
  if (!known) themeSelect.selectedIndex = -1;

  themeSelect.addEventListener("change", () => {
    if (themeSelect.value === "") {
      root.removeAttribute("data-sb-theme");
    } else {
      root.setAttribute("data-sb-theme", themeSelect.value);
    }
  });
}

/* -------------------------------------------------------------- canvas */

/*
 * The registry the spike renders with: the real `core.*` vocabulary, the
 * three `myapp.*` entries that demonstrate the extension seam, and the host
 * vocabulary the demo documents are written against. A registry is a
 * caller-supplied value (ADR-0002 decision 2), and this is the caller.
 *
 * `myapp.legacy_check` is deliberately absent - it is the ADR-0005 decision
 * 12 case the deep end of card-processing.json exists to exercise.
 *
 * `proposedCoreTypes` is the fourth map and the odd one out: `core.*` types
 * the package does NOT ship, registered here so the spike can show what one
 * would look like. It is spread here rather than merged into `coreTypes`
 * precisely so that `coreRegistry()` and `spikeRegistry()` keep answering
 * "what ships" honestly - see the header of `proposed-core.js`.
 */
const registry = createRegistry({
  ...coreTypes,
  ...proposedCoreTypes,
  ...demoTypes,
  ...fixtureTypes,
});

const canvas = document.getElementById("sb-canvas");
const emptyState = document.getElementById("sb-canvas-empty");
const countChip = document.getElementById("sb-canvas-count");
const depthChip = document.getElementById("sb-canvas-depth");
const docTitle = document.getElementById("sb-doc-title");
const docSubtitle = document.getElementById("sb-doc-subtitle");
const documentSelect = document.getElementById("sb-document");

/*
 * The palette renders itself from the registry, so a host that registers a
 * block type gets a palette entry with no markup anywhere - which is what
 * ADR-0002 decision 5 promises and what hand-written markup here could never
 * actually deliver.
 */
const paletteMount = document.getElementById("sb-palette");

if (paletteMount) {
  createPalettePane({ mount: paletteMount, registry });
}

/*
 * The datamodel document, fetched once. Top-level `await` in a module rather
 * than a load-time race: the condition pane's known/unknown treatment is a
 * lookup against this index, and a pane that renders before the index arrives
 * would flag every path in the document as undeclared for one frame - which is
 * the one wrong answer this affordance must never give, even briefly.
 *
 * A failed fetch is not fatal. `datamodel` stays null, the Datamodel tab says
 * so, and the condition pane degrades to tokenizing without the lookup - the
 * same state a host that ships no datamodel document is in.
 */
const datamodelDoc = await fetch("fixtures/datamodel.json")
  .then((response) => (response.ok ? response.json() : null))
  .catch(() => null);

const datamodelMount = document.getElementById("sb-datamodel-panel");

const datamodelPane =
  datamodelMount && datamodelDoc
    ? createDatamodelPane({ mount: datamodelMount, doc: datamodelDoc })
    : null;

if (datamodelMount && !datamodelDoc) {
  datamodelMount.textContent =
    "The datamodel document could not be loaded, so there is no tree to show.";
  datamodelMount.className = "sb-empty";
}

/*
 * The cross-pane affordance's other half: a path clicked in a condition has to
 * SWITCH TABS before the datamodel pane can scroll anything into view, and the
 * tab strip is the shell's, not the editor's. So the shell composes the two -
 * select the tab, then let the pane unfold and flash - and hands the result
 * down as one function.
 */
const datamodelSeam = datamodelPane
  ? {
      index: indexPaths(datamodelDoc),
      reveal: (path) => {
        const tab = document.getElementById("sb-tab-datamodel");
        if (tab) selectTab(tab);
        return datamodelPane.reveal(path);
      },
    }
  : null;

/*
 * The editor owns the canvas, the selection, the history and the drag; the
 * shell owns the frame around it and the fixture fetch. `chrome` is the list
 * of elements the editor is allowed to write to, named here rather than
 * discovered there, so the shell's markup stays the shell's business.
 */
const editor = canvas
  ? createEditor({
      canvas,
      registry,
      datamodel: datamodelSeam,
      /*
       * The truth-table seam (sb-054). Declared here, resolved later: the
       * drawer needs the editor (it follows the selection) and the editor
       * needs the drawer (the condition pane opens it), so one of the two has
       * to be reached through a closure. The editor is built first because the
       * drawer is the cheaper thing to defer - it renders nothing until an
       * author opens it.
       */
      tables: {
        countFor: (blockId) => tableCountFor(fixturesPane?.fixtures() ?? null, blockId),
        open: (blockId) => tableDrawer?.open(blockId),
      },
      chrome: {
        undoButton: document.getElementById("sb-undo"),
        redoButton: document.getElementById("sb-redo"),
        revision: docSubtitle,
        count: countChip,
        depth: depthChip,
        blockType: document.getElementById("sb-block-type"),
        blockId: document.getElementById("sb-block-id"),
        blockSlot: document.getElementById("sb-block-slot"),
        selectionChip: document.getElementById("sb-selection-chip"),
        dragBar: document.getElementById("sb-dragbar"),
        status: document.getElementById("sb-status"),
        palette: document.querySelector(".sb-pane--palette"),
        configForm: document.getElementById("sb-config-form"),
        findingsPanel: document.getElementById("sb-findings-panel"),
        findingsBadge: document.getElementById("sb-findings-count"),
        conditionPanel: document.getElementById("sb-condition-panel"),
        // The canvas zoom cluster (sb-bl1). Named here like every other
        // element the editor writes to, so the shell's markup stays the
        // shell's business and `interact.js` never queries the document.
        zoomOut: document.getElementById("sb-zoom-out"),
        zoomIn: document.getElementById("sb-zoom-in"),
        zoomLabel: document.getElementById("sb-zoom-level"),
        zoomFit: document.getElementById("sb-zoom-fit"),
        zoomFitActive: document.getElementById("sb-zoom-fit-active"),
      },
    })
  : null;

/* --------------------------------------------------------- pane collapse */

/*
 * Folding a side pane to a rail, which is the narrow-embed answer that does
 * not depend on a breakpoint (sb-bl1).
 *
 * The state is written in TWO places because two different things need it,
 * and it is written by one function so they cannot disagree: the pane carries
 * `data-collapsed` for what happens inside it, and the grid carries
 * `data-palette` / `data-inspector` because a column TRACK is the grid's and
 * no rule on a child can change one. The button's `aria-expanded` is the same
 * fact a third time, for a reader who cannot see either.
 *
 * The shell's, not the editor's. `interact.js` owns the canvas and the session;
 * which panes are folded is frame furniture, and the editor has no opinion
 * about it - the same division the tab strip and the theme selector are on.
 */
const shellBody = document.querySelector(".sb-editor__body");

function wireCollapse(button, pane, key, noun) {
  if (!button || !pane || !shellBody) return;

  const set = (collapsed) => {
    pane.dataset.collapsed = String(collapsed);
    shellBody.dataset[key] = collapsed ? "collapsed" : "open";
    button.setAttribute("aria-expanded", String(!collapsed));

    // The label names what the NEXT press will do, not what the pane is now.
    // A control that describes its effect survives an author who arrived at
    // the pane already folded; one that describes its state does not.
    const label = `${collapsed ? "Expand" : "Collapse"} the ${noun}`;
    button.setAttribute("aria-label", label);
    button.title = label;
  };

  set(false);
  button.addEventListener("click", () => set(pane.dataset.collapsed !== "true"));
}

wireCollapse(
  document.getElementById("sb-collapse-palette"),
  document.querySelector(".sb-pane--palette"),
  "palette",
  "palette"
);

wireCollapse(
  document.getElementById("sb-collapse-inspector"),
  document.querySelector(".sb-pane--inspector"),
  "inspector",
  "inspector"
);

/* ------------------------------------------------------------- fixtures */


/*
 * The run/table fixtures (sb-9z3), fetched the same way and with the same
 * degradation as the datamodel document: a failed fetch leaves the pane saying
 * so rather than throwing, because a spike whose whole Fixtures tab is a stack
 * trace when one static file 404s teaches nothing.
 *
 * A SIBLING file rather than a section inside each document fixture. The
 * reasons are in the file's own header comment; the short one is that a
 * document fixture is an ADR-0001 envelope and the decoder refuses keys the
 * encoder would never have written, so a `runs` key would be a second thing to
 * strip on every load - and the strict check is what keeps the round trip
 * honest.
 */
const runsDoc = await fetch("fixtures/runs.json")
  .then((response) => (response.ok ? response.json() : null))
  .catch(() => null);

const fixturesMount = document.getElementById("sb-fixtures-panel");

/*
 * The pane reads the editor rather than the other way round. It needs three
 * things the editor owns - which document is open, what is selected, and the
 * canvas - and it gets them as functions rather than as values, for the reason
 * every other seam in this shell takes a function: the session is replaced by
 * every command, so anything holding one holds a stale value.
 */
const fixturesPane = fixturesMount
  ? createFixturesPane({
      mount: fixturesMount,
      data: runsDoc,
      host: {
        documentId: () => editor?.session?.document.id ?? null,
        selectedId: () => editor?.selectedId ?? null,
        markActive: (ids) => editor?.markActive(ids),
        markInvoking: (block, outcome) => editor?.markInvoking(block, outcome),
        revealBlocks: (ids) => editor?.revealBlocks(ids) ?? false,
        revealBlock: (id) => editor?.revealBlock(id) ?? false,
        labelFor: (id) => blockLabel(id),
        // Apply and Revert replace the whole fixture set, and the drawer is
        // rendering out of the same copy.
        fixturesChanged: () => tableDrawer?.fixturesChanged(),
      },
    })
  : null;

/* --------------------------------------------------- truth-table drawer */

/*
 * The drawer (sb-054). Mounted by the shell rather than by the inspector,
 * because it is not in the inspector: it is row three of the shell grid, the
 * full width of the editor, which is the whole reason the tables moved out of
 * a 21rem column.
 *
 * The editor's seam above closes over this binding rather than holding the
 * value: both are module-scoped consts and the calls all happen after this
 * line runs, so the cycle costs a closure and nothing else.
 */
const drawerRoot = document.getElementById("sb-drawer");
const drawerMount = document.getElementById("sb-drawer-panel");

const tableDrawer =
  drawerRoot && drawerMount
    ? createTableDrawer({
        root: drawerRoot,
        mount: drawerMount,
        title: document.getElementById("sb-drawer-title"),
        close: document.getElementById("sb-drawer-close"),
        host: {
          fixtures: () => fixturesPane?.fixtures() ?? null,
          selectedId: () => editor?.selectedId ?? null,
          labelFor: (id) => blockLabel(id),
          revealBlock: (id) => editor?.revealBlock(id) ?? false,
        },
      })
    : null;

if (editor) {
  /*
   * The selection follower, now the drawer alone. The Fixtures pane wanted
   * this callback only for its tables sub-view; with the tables in the drawer
   * the pane's two remaining surfaces - a recorded run and the raw fixture
   * JSON - are about the document rather than about the selection, so it no
   * longer has a `selectionChanged` to call. The editor holds exactly one
   * handler, deliberately, so if a second follower ever appears the shell
   * composes them here rather than the editor growing subscribers.
   */
  editor.onSelectionChange = () => tableDrawer?.selectionChanged();
}

/*
 * A block's own title, the way the canvas card reads it: the `label` an author
 * typed, falling back to the block type's palette label and then to the raw id.
 * A chip reading `blk_cp_three_ds_wait` is an id; a chip reading "Wait" beside
 * that id in the tooltip is a block.
 */
function blockLabel(id) {
  const session = editor?.session;
  if (!session) return id;

  const node = findBlock(session.document, id);
  if (!node) return id;

  const label = node.config?.label;
  if (typeof label === "string" && label !== "") return label;

  const { descriptor, unresolved } = describe(session.registry, node);
  return unresolved ? node.type : (descriptor.paletteEntry?.label ?? descriptor.name ?? node.type);
}

/*
 * The fixtures carry `_comment` keys - their own documentation, additive and
 * explicitly not part of the ADR-0001 node shape. `Decode` refuses a block
 * carrying a key the encoder would never have written, and the spike's
 * `fromJson` mirrors that refusal exactly, so the comments have to come off
 * before decoding rather than being tolerated by a laxer decoder. Stripping
 * here rather than relaxing there is the point: the strict check is the one
 * that keeps `encode(decode(bytes)) == bytes` honest.
 *
 * Only block objects and the envelope are stripped. `config` is walked past
 * untouched, because a config key is the host's to name and this function has
 * no business editing one.
 */
function stripComments(raw) {
  if (Array.isArray(raw)) return raw.map(stripComments);
  if (raw === null || typeof raw !== "object") return raw;

  const out = {};

  for (const [key, value] of Object.entries(raw)) {
    if (key === "_comment") continue;
    out[key] = key === "config" || key === "metadata" ? value : stripComments(value);
  }

  return out;
}

/*
 * Every load takes a generation token before its first `await` and re-checks
 * it after, so the LAST REQUESTED document wins rather than the last fetch to
 * resolve. Two switches in one frame used to leave the picker and the canvas
 * disagreeing until the next switch (sb-3kf, sb-ea4's F5); now the superseded
 * load discards its own result and writes nothing.
 *
 * The token is taken for the empty-name branch too, even though that branch
 * never awaits: picking "None" while a fetch is in flight has to supersede it
 * as firmly as picking another document does.
 */
const documentLoads = createSequence();

async function loadDocument(name) {
  const token = documentLoads.begin();

  if (!name) {
    editor.clear();
    canvas.hidden = true;
    emptyState.hidden = false;
    countChip.textContent = "0 blocks";
    depthChip.hidden = true;
    docTitle.textContent = "No document";
    docSubtitle.textContent = "pick a demo document to load";
    fixturesPane?.documentChanged();
    tableDrawer?.documentChanged();
    return;
  }

  const response = await fetch(`fixtures/documents/${name}.json`);
  const raw = await response.json();

  // The one gate. Past here the function only writes to the DOM, so a load
  // that has been superseded stops here and leaves the winner's canvas alone.
  // The fetch itself is not cancelled - it cannot be - it is only ignored.
  if (!documentLoads.isCurrent(token)) return;

  const decoded = fromJson(stripComments(raw));

  if (!decoded.ok) {
    // A refusal is a typed value, not an exception, so it renders as one.
    canvas.hidden = true;
    emptyState.hidden = false;
    docTitle.textContent = "Could not load";
    docSubtitle.textContent = JSON.stringify(decoded.error);
    return;
  }

  const doc = decoded.value;

  emptyState.hidden = true;
  canvas.hidden = false;

  // The chips, the revision line and the inspector's Block section are all
  // written by the editor from the session it just built, so the shell sets
  // only the one thing the editor has no opinion about: the document's name.
  docTitle.textContent = doc.metadata.name ?? doc.id;
  editor.open(doc);

  // After `open`, not before: a run left open from the previous document would
  // otherwise mark blocks that are no longer on the canvas.
  fixturesPane?.documentChanged();
  tableDrawer?.documentChanged();
}

/*
 * The picker's options come from `fixture-documents.js` rather than from the
 * markup, because they are now read twice: here, where a choice is fetched and
 * opened, and in `proposed-core.js`, where `core.subchart`'s chart reference
 * offers the same list (D11). Two hand-kept copies is how a reference ends up
 * naming a document the shell has no file for.
 *
 * Appended after the markup's empty option, so "None" stays first.
 */
if (documentSelect) {
  for (const doc of fixtureDocuments) {
    documentSelect.append(new Option(doc.label, doc.file));
  }
}

if (documentSelect && canvas && emptyState) {
  documentSelect.addEventListener("change", () => {
    loadDocument(documentSelect.value);
  });

  // `?doc=signup-wizard` opens a named fixture, so a screenshot or a bug
  // report can name the exact state it is about. Anything unrecognized falls
  // back to the gnarly document, which is the acceptance fixture for this
  // wave: a canvas that only ever looks right on the easy case is not
  // evidence of anything.
  const requested = new URLSearchParams(window.location.search).get("doc");
  const known = Array.from(documentSelect.options).map((option) => option.value);

  documentSelect.value = known.includes(requested) ? requested : "card-processing";
  loadDocument(documentSelect.value);
}
