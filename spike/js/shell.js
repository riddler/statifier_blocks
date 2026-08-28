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

import { fromJson } from "./document.js";
import { coreTypes, createRegistry, demoTypes } from "./palette.js";
import { fixtureTypes } from "./demo-types.js";
import { createEditor } from "./interact.js";

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
 */
const registry = createRegistry({ ...coreTypes, ...demoTypes, ...fixtureTypes });

const canvas = document.getElementById("sb-canvas");
const emptyState = document.getElementById("sb-canvas-empty");
const countChip = document.getElementById("sb-canvas-count");
const depthChip = document.getElementById("sb-canvas-depth");
const docTitle = document.getElementById("sb-doc-title");
const docSubtitle = document.getElementById("sb-doc-subtitle");
const documentSelect = document.getElementById("sb-document");

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
      chrome: {
        undoButton: document.getElementById("sb-undo"),
        redoButton: document.getElementById("sb-redo"),
        revision: docSubtitle,
        count: countChip,
        depth: depthChip,
        blockType: document.getElementById("sb-block-type"),
        blockId: document.getElementById("sb-block-id"),
        blockSlot: document.getElementById("sb-block-slot"),
        blockNote: document.getElementById("sb-block-readonly"),
        selectionChip: document.getElementById("sb-selection-chip"),
        dragBar: document.getElementById("sb-dragbar"),
        status: document.getElementById("sb-status"),
        palette: document.querySelector(".sb-pane--palette"),
      },
    })
  : null;

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

async function loadDocument(name) {
  if (!name) {
    canvas.replaceChildren();
    canvas.hidden = true;
    emptyState.hidden = false;
    countChip.textContent = "0 blocks";
    depthChip.hidden = true;
    docTitle.textContent = "No document";
    docSubtitle.textContent = "pick a demo document to load";
    return;
  }

  const response = await fetch(`fixtures/documents/${name}.json`);
  const decoded = fromJson(stripComments(await response.json()));

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
