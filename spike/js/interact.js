/*
 * spike/js/interact.js - pointer and key events, translated into commands.
 *
 * The counterpart to `session.js`, and the division between them is the same
 * one ADR-0005 decision 7 draws around the shipped `StatifierBlocksDrag` hook:
 * "its entire job is to translate pointer and drag events into pushEvent
 * calls, reading `data-block-id`, `data-slot` and `data-index` off the DOM."
 * Swap `pushEvent` for a call into `session.js` and that sentence describes
 * this file exactly. Nothing here decides whether a drop is legal, what a
 * command means, or which types a "+" may offer; it reads the DOM contract,
 * asks, and re-renders.
 *
 * ## Re-render after every command, never patch
 *
 * A command produces a new document, the whole canvas is rebuilt from it, and
 * the scroll position is put back. That is not a shortcut - it is decision 7's
 * "it never mutates the block tree in the DOM", which exists because a hook
 * that moves nodes itself ends up fighting the renderer for ownership of the
 * same elements. The spike has no LiveView to fight, and it still does not
 * move a node, because the moment it did, every later bead would inherit two
 * sources of truth for where a block is.
 *
 * The one exception is SELECTION, which flips `aria-selected` in place. It
 * changes no rectangle, so re-laying-out and re-routing a forty-block canvas
 * to answer a click would be pure cost.
 *
 * ## Pointer events, not HTML5 drag-and-drop
 *
 * HTML5 DnD cannot show what this bead exists to show. Its drag image is a
 * browser-owned snapshot, `dragover` is throttled, and on a touch device it
 * does not fire at all. Pointer events give a real element following the
 * cursor, a drop seam that arms on approach rather than on exact hit, and the
 * same code path on mouse, pen and touch. Decision 7 says "pointer and drag
 * events" and names neither mechanism, so this stays inside the record - but
 * it is a decision the shipped hook will have to make again, and the reasons
 * are here rather than in a commit message.
 */

import { layoutDocument } from "./layout.js";
import { renderCanvas } from "./render.js";
import {
  beginDrag,
  canRedoSession,
  canUndoSession,
  createSession,
  deselect,
  dropAt,
  dropStateFor,
  droppableCount,
  endDrag,
  insertTypeAt,
  isDropAllowed,
  redoSession,
  removeBlock,
  select,
  selectionSummary,
  toggleCollapsed,
  typesForSlot,
  undoSession,
  blockForType,
} from "./session.js";

/** How far a pointer travels before a press becomes a drag rather than a click. */
const DRAG_THRESHOLD = 4;

/**
 * Wires one canvas and its chrome to one session.
 *
 * `chrome` names the elements outside the canvas this editor writes to; every
 * one is optional, so the same module drives the full shell and a bare canvas
 * in a test page.
 */
export function createEditor({ canvas, registry, chrome = {} }) {
  /*
   * The ghost and the "+" picker are `position: fixed`, so they escape the
   * canvas's `overflow: auto` wherever they hang in the DOM - but they hang
   * inside `.sb-spike` rather than off `<body>` so that every `--sb-*` token
   * still resolves for them. ADR-0005 decision 14 scopes the whole visual
   * surface to that container; an overlay parked outside it would have to
   * name literal colours, and would then be the one thing in the editor a
   * host theme could not touch.
   */
  const overlayHost = canvas.closest(".sb-spike") ?? document.body;

  let session = null;
  let rendered = null;
  let press = null;
  let ghost = null;
  let armed = null;
  let picker = null;

  /* ------------------------------------------------------------- rendering */

  function render({ center = false } = {}) {
    const scrollLeft = canvas.scrollLeft;
    const scrollTop = canvas.scrollTop;

    if (rendered) rendered.destroy();

    const tree = layoutDocument(session.document, session.registry, {
      collapsed: session.collapsed,
      dropState: (parentId, slot) => dropStateFor(session, parentId, slot),
    });

    rendered = renderCanvas(canvas, tree, { center });

    if (!center) {
      canvas.scrollLeft = scrollLeft;
      canvas.scrollTop = scrollTop;
    }

    canvas.dataset.dragging = session.drag ? "true" : "false";

    // The block being MOVED is marked so its card can dim: an author needs to
    // see where the thing came from as well as where it is going, and the
    // ghost under the cursor only answers half of that. Marked on the node and
    // dimmed on the card alone, never on the subtree - see the stylesheet on
    // why `opacity` over a nested region is a trap.
    if (session.drag && session.drag.kind === "move") {
      const source = canvas.querySelector(
        `.sb-node[data-block-id="${cssEscape(session.drag.id)}"]`
      );
      if (source) source.dataset.dragSource = "true";
    }

    applySelection();
    syncChrome(tree);

    return tree;
  }

  /*
   * Selection as an attribute flip. `tabindex` moves with it - a roving
   * tabindex, so Tab lands on the selected card rather than walking through
   * forty of them, and the card can then answer Delete and the arrow keys.
   */
  function applySelection() {
    for (const card of canvas.querySelectorAll(".sb-card")) {
      const selected = card.dataset.blockId === session.selectedId;
      card.setAttribute("aria-selected", String(selected));
      card.tabIndex = selected ? 0 : -1;
    }

    syncInspector();
  }

  function syncInspector() {
    const summary = selectionSummary(session);
    const dash = "\u2014";

    setText(chrome.blockType, summary ? summary.type : dash);
    setText(chrome.blockId, summary ? summary.id : dash);
    setText(chrome.blockSlot, summary ? summary.slot : dash);
    setText(chrome.selectionChip, summary ? summary.type : "no selection");

    // The read-only note decision 12 promises, surfaced where an author looks
    // for the config form rather than only on the card.
    if (chrome.blockNote) {
      chrome.blockNote.hidden = !(summary && summary.unresolved);
    }
  }

  function syncChrome(tree) {
    if (chrome.undoButton) chrome.undoButton.disabled = !canUndoSession(session);
    if (chrome.redoButton) chrome.redoButton.disabled = !canRedoSession(session);

    setText(chrome.revision, `revision ${session.document.revision} \u00b7 ${session.document.id}`);

    const stored = tree.blockCount;
    setText(chrome.count, `${stored} block${stored === 1 ? "" : "s"}`);

    if (chrome.depth) {
      chrome.depth.hidden = false;
      chrome.depth.textContent = `depth ${tree.maxDepth}`;
    }

    syncDragBar();
  }

  /*
   * The drag banner. It exists because pre-hover validity is invisible if the
   * author cannot tell a drag is running: the slots light up, but "why is my
   * canvas suddenly striped" is not a question a good editor makes anyone ask.
   * It also names the count, which is the one number that says whether the
   * thing being dragged has anywhere to go at all.
   */
  function syncDragBar() {
    if (!chrome.dragBar) return;

    if (!session.drag) {
      chrome.dragBar.hidden = true;
      chrome.dragBar.textContent = "";
      return;
    }

    const count = droppableCount(session);
    chrome.dragBar.hidden = false;
    chrome.dragBar.textContent =
      count === 0
        ? `Dragging ${session.drag.label} \u00b7 nowhere it can go`
        : `Dragging ${session.drag.label} \u00b7 ${count} slot${count === 1 ? "" : "s"} will take it`;
  }

  /* ---------------------------------------------------------- the mutations */

  /*
   * Every command flows through here, so "apply it, or say why not, then
   * re-render exactly once" is written down once. A refusal is a value from
   * `session.js`, never an exception, and it reaches the author as a message
   * rather than as nothing happening.
   */
  function apply(result) {
    if (!result.ok) {
      announce(describeRefusal(result.error));
      return false;
    }

    session = result.value;
    closePicker();
    render();
    return true;
  }

  function announce(message) {
    if (!chrome.status) return;
    chrome.status.textContent = message ?? "";
  }

  /* -------------------------------------------------------------- selection */

  function selectBlock(id) {
    session = select(session, id);
    applySelection();

    const card = canvas.querySelector(`.sb-card[data-block-id="${cssEscape(id)}"]`);
    if (card) card.focus({ preventScroll: true });
  }

  function clearSelection() {
    session = deselect(session);
    applySelection();
  }

  /* ------------------------------------------------------------------ drag */

  function startDrag(source, pointer) {
    session = beginDrag(session, source);
    if (!session.drag) return;

    ghost = document.createElement("div");
    ghost.className = "sb-ghost";
    ghost.textContent = session.drag.label;
    overlayHost.append(ghost);
    moveGhost(pointer);

    render();
  }

  function moveGhost({ clientX, clientY }) {
    if (!ghost) return;
    ghost.style.transform = `translate(${clientX + 12}px, ${clientY + 12}px)`;
  }

  /*
   * The armed seam: the one gap a release would drop into.
   *
   * Nearest-gap-within-an-accepting-slot rather than strict hit-testing. A gap
   * is a few pixels tall, and requiring the pointer to land inside one turns a
   * drop into a test of mouse precision - which is the failure mode that makes
   * people say a canvas editor "feels fiddly". Widening the seam visually
   * during a drag is the other half of the same fix, and it is CSS.
   */
  function gapUnder(clientX, clientY) {
    const under = document.elementFromPoint(clientX, clientY);
    if (!under) return null;

    const direct = under.closest(".sb-gap");
    if (direct && gapAccepts(direct)) return direct;

    const slot = under.closest("[data-drop]");
    if (!slot || slot.dataset.drop !== "ok") return null;

    const gaps = Array.from(slot.querySelectorAll(".sb-gap")).filter(
      (gap) =>
        gap.dataset.blockId === slot.dataset.blockId && gap.dataset.slot === slot.dataset.slot
    );

    let best = null;
    let bestDistance = Infinity;

    for (const gap of gaps) {
      const box = gap.getBoundingClientRect();
      const distance = Math.hypot(
        clientX - (box.left + box.width / 2),
        clientY - (box.top + box.height / 2)
      );

      if (distance < bestDistance) {
        best = gap;
        bestDistance = distance;
      }
    }

    return best;
  }

  function gapAccepts(gap) {
    return isDropAllowed(session, gap.dataset.blockId, gap.dataset.slot);
  }

  function armGap(gap) {
    if (armed === gap) return;
    if (armed) armed.classList.remove("sb-gap--armed");
    armed = gap;
    if (armed) armed.classList.add("sb-gap--armed");
  }

  /*
   * Safe before the first document is open, which is the state `open()` calls
   * it in. The overlays and the pending press are cleared unconditionally; the
   * session is only touched when there is one.
   */
  function cancelDrag() {
    if (ghost) ghost.remove();
    ghost = null;
    armGap(null);
    press = null;

    if (session?.drag) {
      session = endDrag(session);
      render();
    }
  }

  function finishDrag() {
    const gap = armed;

    if (!gap) {
      announce("Drop cancelled - that is not a slot this block can go in.");
      cancelDrag();
      return;
    }

    const to = {
      parentId: gap.dataset.blockId,
      slot: gap.dataset.slot,
      index: Number(gap.dataset.index),
    };

    if (ghost) ghost.remove();
    ghost = null;
    armGap(null);
    press = null;

    apply(dropAt(session, to));
  }

  /* ---------------------------------------------------------- the "+" picker */

  function openPicker(button) {
    closePicker();

    const parentId = button.dataset.blockId;
    const slot = button.dataset.slot;
    const index = Number(button.dataset.index);
    const offered = typesForSlot(session, parentId, slot);

    picker = document.createElement("div");
    picker.className = "sb-picker";
    picker.setAttribute("role", "menu");
    picker.dataset.blockId = parentId;
    picker.dataset.slot = slot;
    picker.dataset.index = String(index);

    const heading = document.createElement("p");
    heading.className = "sb-picker__title";
    heading.textContent =
      offered.length === 0
        ? "Nothing fits here"
        : `Insert into ${slot} · ${offered.length} type${offered.length === 1 ? "" : "s"}`;
    picker.append(heading);

    if (offered.length === 0) {
      // Saying WHY beats an empty menu. The four rules are the only reason a
      // list comes back empty, and naming them is what stops an author
      // concluding the editor is broken.
      const note = document.createElement("p");
      note.className = "sb-picker__empty";
      note.textContent =
        "This slot is full, or it accepts no block type this document knows about.";
      picker.append(note);
    }

    // Grouped exactly the way the palette groups (`paletteGroups`'s rule:
    // group name, then order, then label), because the picker IS the palette
    // filtered to one slot. An author who has learned where "Wait" lives in
    // the left-hand list should find it in the same place here.
    let group = null;

    for (const entry of offered) {
      if (entry.group !== group) {
        group = entry.group;
        const heading = document.createElement("p");
        heading.className = "sb-picker__group";
        heading.textContent = group;
        picker.append(heading);
      }

      const item = document.createElement("button");
      item.type = "button";
      item.className = "sb-picker__item";
      item.setAttribute("role", "menuitem");
      item.dataset.action = "pick-type";
      item.dataset.type = entry.type;

      const label = document.createElement("span");
      label.className = "sb-picker__label";
      label.textContent = entry.label;

      const description = document.createElement("span");
      description.className = "sb-picker__description";
      description.textContent = entry.description;

      item.append(label, description);
      picker.append(item);
    }

    // The picker hangs off `.sb-spike`, not off the canvas, so the canvas's
    // delegated click listener does not see it. It gets its own listener onto
    // the SAME handler rather than a second implementation - one `data-action`
    // switch, two elements it is delegated from.
    picker.addEventListener("click", onClick);

    overlayHost.append(picker);
    placePicker(picker, button);

    button.setAttribute("aria-expanded", "true");
    picker.dataset.owner = button.dataset.blockId;
    picker.__button = button;

    const first = picker.querySelector(".sb-picker__item");
    if (first) first.focus();
  }

  function placePicker(element, button) {
    const box = button.getBoundingClientRect();
    const width = element.offsetWidth;
    const height = element.offsetHeight;

    // Flip rather than overflow. A menu opened near the bottom of a tall canvas
    // otherwise renders half off-screen, and the item an author wants is
    // always the one that got clipped.
    const left = Math.min(Math.max(8, box.left), window.innerWidth - width - 8);
    const below = box.bottom + 6;
    const top = below + height > window.innerHeight - 8 ? box.top - height - 6 : below;

    element.style.left = `${left}px`;
    element.style.top = `${Math.max(8, top)}px`;
  }

  function closePicker() {
    if (!picker) return;

    if (picker.__button) picker.__button.setAttribute("aria-expanded", "false");
    picker.remove();
    picker = null;
  }

  /* --------------------------------------------------------------- listeners */

  function onPointerDown(event) {
    if (event.button !== 0) return;

    const action = event.target.closest("[data-action]");
    if (action) return;

    const card = event.target.closest(".sb-card");
    if (!card) return;

    // The root is selectable but not draggable: it is the document, and a
    // document cannot be a child of anything.
    const draggable = card.dataset.blockId !== session.document.root.id;

    press = {
      id: card.dataset.blockId,
      source: { kind: "move", id: card.dataset.blockId, label: cardLabel(card) },
      draggable,
      startX: event.clientX,
      startY: event.clientY,
      moved: false,
    };
  }

  function onClick(event) {
    const action = event.target.closest("[data-action]");

    if (!action) {
      // A click on the canvas background - not on a card, not on a gap - is
      // the deselect gesture. `closest(".sb-card")` rather than a check on the
      // target itself, because a click always lands on the title or the icon.
      if (!event.target.closest(".sb-card") && !event.target.closest(".sb-picker")) {
        clearSelection();
        closePicker();
      }
      return;
    }

    event.preventDefault();
    event.stopPropagation();

    switch (action.dataset.action) {
      case "toggle-collapsed":
        session = toggleCollapsed(session, action.dataset.blockId);
        render();
        break;

      case "delete-block":
        apply(removeBlock(session, action.dataset.blockId));
        break;

      case "open-picker":
        openPicker(action);
        break;

      case "pick-type": {
        const host = action.closest(".sb-picker");
        apply(
          insertTypeAt(session, action.dataset.type, {
            parentId: host.dataset.blockId,
            slot: host.dataset.slot,
            index: Number(host.dataset.index),
          })
        );
        break;
      }

      default:
        break;
    }
  }

  function onKeyDown(event) {
    if (event.key === "Escape") {
      if (session.drag) cancelDrag();
      else if (picker) closePicker();
      else clearSelection();
      return;
    }

    const undoKey = (event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "z";

    if (undoKey) {
      event.preventDefault();
      apply(event.shiftKey ? redoSession(session) : undoSession(session));
      return;
    }

    if (event.key === "Delete" || event.key === "Backspace") {
      // Only when the canvas owns the keystroke. Backspace inside the document
      // selector or a future config field must still delete a character.
      const inField = event.target.closest("input, textarea, select, [contenteditable]");
      if (inField || !session.selectedId) return;

      event.preventDefault();
      apply(removeBlock(session, session.selectedId));
    }
  }

  /* --------------------------------------------------------- palette drags */

  /*
   * A palette entry is a drag SOURCE for a block that does not exist yet, so
   * the drag carries a freshly-minted block rather than an id. `session.js`
   * takes both through one function, which is why a palette drag and a
   * rearrange drag highlight identically.
   */
  /*
   * An open menu closes when the next press lands anywhere that is not the
   * menu or the button that opened it - the palette, the inspector, the top
   * bar. The canvas's own background click closes it too, but only inside the
   * canvas, and a menu that survives a click on the inspector is a menu the
   * author has to dismiss twice.
   */
  function onWindowPointerDownForPicker(event) {
    if (!picker) return;
    if (event.target.closest(".sb-picker")) return;
    if (event.target.closest('[data-action="open-picker"]')) return;

    closePicker();
  }

  function onPaletteDown(event) {
    if (event.button !== 0) return;

    const pick = event.target.closest("[data-block-type]");
    if (!pick) return;

    const typeName = pick.dataset.blockType;

    press = {
      id: null,
      draggable: true,
      startX: event.clientX,
      startY: event.clientY,
      moved: false,
      source: null,
      typeName,
      label: pick.querySelector(".sb-palette__name")?.textContent?.trim() ?? typeName,
    };
  }

  /*
   * ONE move handler and ONE up handler, on the window rather than on the
   * canvas, and they serve a card press and a palette press alike.
   *
   * The window is the right host for both: a drag that leaves the canvas -
   * over the inspector, past the window edge - must keep tracking, and a
   * pointer released outside must still end the drag rather than leave a ghost
   * stuck to the cursor. Listening on the canvas instead is how a drag
   * implementation ends up with a "stuck drag" bug it can never quite
   * reproduce.
   */
  function onWindowPointerMove(event) {
    if (session?.drag) {
      moveGhost(event);
      armGap(gapUnder(event.clientX, event.clientY));
      return;
    }

    if (!press || press.moved) return;

    const far =
      Math.abs(event.clientX - press.startX) > DRAG_THRESHOLD ||
      Math.abs(event.clientY - press.startY) > DRAG_THRESHOLD;

    if (!far) return;

    if (press.typeName) {
      press.moved = true;
      const node = blockForType(session.registry, press.typeName);
      if (node) startDrag({ kind: "insert", block: node, label: press.label }, event);
      return;
    }

    if (!press.draggable) return;

    press.moved = true;
    startDrag(press.source, event);
  }

  function onWindowPointerUp() {
    if (session?.drag) {
      finishDrag();
      return;
    }

    // A press that never travelled is a click, and a click on a card selects
    // it. Doing it on release rather than on press is what keeps "press and
    // drag away" from leaving the dragged block selected mid-flight.
    if (press && !press.moved && press.id) selectBlock(press.id);
    press = null;
  }

  /* ------------------------------------------------------------------ wiring */

  canvas.addEventListener("pointerdown", onPointerDown);
  canvas.addEventListener("click", onClick);
  window.addEventListener("keydown", onKeyDown);
  window.addEventListener("pointermove", onWindowPointerMove);
  window.addEventListener("pointerup", onWindowPointerUp);
  window.addEventListener("pointerdown", onWindowPointerDownForPicker);

  if (chrome.palette) chrome.palette.addEventListener("pointerdown", onPaletteDown);
  if (chrome.undoButton) {
    chrome.undoButton.addEventListener("click", () => apply(undoSession(session)));
  }
  if (chrome.redoButton) {
    chrome.redoButton.addEventListener("click", () => apply(redoSession(session)));
  }

  return {
    /** Loads a decoded document, replacing whatever the editor held. */
    open(doc) {
      cancelDrag();
      closePicker();
      session = createSession(doc, registry);
      announce("");
      return render({ center: true });
    },

    /** The live session - the read handle a test or a console poke needs. */
    get session() {
      return session;
    },

    destroy() {
      cancelDrag();
      closePicker();
      if (rendered) rendered.destroy();
      rendered = null;
      canvas.removeEventListener("pointerdown", onPointerDown);
      canvas.removeEventListener("click", onClick);
      window.removeEventListener("keydown", onKeyDown);
      window.removeEventListener("pointermove", onWindowPointerMove);
      window.removeEventListener("pointerup", onWindowPointerUp);
      window.removeEventListener("pointerdown", onWindowPointerDownForPicker);
    },
  };
}

/* ================================================================= helpers */

function setText(element, value) {
  if (element) element.textContent = value;
}

function cardLabel(card) {
  return card.querySelector(".sb-card__title")?.textContent?.trim() ?? "block";
}

/*
 * The refusals `session.js` and `edit.js` can produce, in the author's
 * vocabulary. A tag with no sentence here still reaches the author as its tag
 * rather than as silence - an unexplained refusal is worse than an ugly one.
 */
const REFUSALS = {
  no_drag: "Nothing is being dragged.",
  not_droppable: "That slot will not take this block.",
  nothing_selected: "Select a block first.",
  cannot_remove_root: "The root block cannot be deleted.",
  cannot_remove_row: "The root block cannot be deleted.",
  would_cycle: "A block cannot be moved inside itself.",
  nothing_to_undo: "Nothing to undo.",
  nothing_to_redo: "Nothing to redo.",
  index_out_of_range: "That position no longer exists.",
  duplicate_block_id: "A block with that id is already in the document.",
  no_such_block: "That block is no longer in the document.",
  no_such_slot: "That slot does not exist.",
  invalid_config: "That configuration is not valid, so it was not applied.",
};

function describeRefusal(error) {
  return REFUSALS[error?.tag] ?? `Refused: ${error?.tag ?? "unknown"}`;
}

/*
 * `CSS.escape` where it exists, and a conservative fallback where it does not.
 * Block ids are minted here and contain nothing exotic, but an id also arrives
 * from a fixture's bytes, and building a selector out of unescaped foreign
 * text is the wrong habit to leave in a file other beads will copy from.
 */
function cssEscape(value) {
  if (typeof CSS !== "undefined" && CSS.escape) return CSS.escape(value);
  return String(value).replace(/["\\]/g, "\\$&");
}
