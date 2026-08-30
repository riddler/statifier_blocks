// statifier_blocks' client-side surface: the package's entry point, which
// defines the command half - the drag hook - and re-exports the measurement
// half so the default export carries both.
//
// ADR-0005 decision 7. The hook translates pointer and drag events into
// pushEvent calls and does nothing else. In particular it never moves a node
// in the DOM: the server re-renders after every command, so a hook that
// patched the tree itself would be fighting LiveView's DOM patching for
// ownership of the same elements, which is the standard way drag-and-drop
// integrations break.
//
// ADDING A HOOK REQUIRES AMENDING ADR-0005, and one amendment has been made:
// "decision 7, a second hook that only measures" (2026-08-29, accepted). It
// admits `StatifierBlocksMeasure` in statifier_blocks_measure.js and nothing
// else, and it replaces the count with the invariant the count was a proxy
// for - ONE HOOK PUSHES COMMANDS, and this is it. A measuring hook moves no
// behaviour to the client because it produces an input rather than a
// decision: feed it a different measurement and the same document comes back;
// feed this hook a different drop and a different document does.
//
// The bar is still enforced mechanically as well as socially:
// test/statifier_blocks/assets_test.exs reads assets/js/, asserts the exported
// hooks are exactly the two the record names, and fails with a message naming
// it. A third hook, or a hook that pushes anything but geometry or a command,
// is a thing this record does not have.
//
// Delivery is source, per sui-ADR-0009: a host adds
//
//   "statifier_blocks": "file:../deps/statifier_blocks"
//
// to assets/package.json and imports the hooks in app.js. This repository
// bundles nothing and has no Node toolchain. The entry point, the export names
// and the hook names are versioned public API.
//
// THE DEFAULT EXPORT CARRIES BOTH HOOKS, so `hooks: { ...StatifierBlocks }`
// registers both and a host cannot get one without the other. That shape is
// the point: the measurement hook is what feeds the server the geometry the
// connector layer draws from, so a host that registered only the drag hook
// got an editor with no flow lines and no error to explain it. The two named
// exports and the `statifier_blocks/measure` entry point are unchanged, so a
// host that wants only measurement still has a way to say so - the amendment's
// "a host that wants connectors adds one more import" is now the default
// rather than a step to remember.
//
// The sibling import below is the only import in this file, and it is a
// relative path inside this package. sui-ADR-0009's bar is that a
// source-shipped hook pulls no DEPENDENCIES; assets_test.exs enforces exactly
// that, on both files.
//
// The DOM contract this depends on is part of the package's contract:
//   data-block-id       on each block's root element
//   data-slot           on each gap, with data-parent-id and data-index
//   data-drop           on each slot during a drag session ("ok" or "no")
//   data-sb-drag-type   on each palette entry, naming the type it inserts
//   data-sb-reveal      on the canvas, "<n>:<block id>", when the server has
//                       just been asked to bring that block into view
//
// TWO GESTURES, ONE HOOK, ONE COMMAND SET (sb-4nep). A card dragged between
// gaps is a move; a palette entry dragged onto a gap is an insert - the same
// `:insert` a "+" and a pick already produce (ADR-0005 decision 8), reached by
// a different gesture. So this adds hook EVENTS ("insert-dragstart",
// "insert-drop") and no command, and ADR-0005's command set is unchanged.
//
// The palette lives OUTSIDE the canvas, and the canvas root is the one element
// carrying this hook (decision 7's element rule, which the connector layer
// depends on). A dragstart on a palette entry therefore never reaches
// `this.el`, so the insert half listens on the owning document and scopes
// itself back to this editor through the `.sb-editor` root that contains both
// panes. Two editors on one page keep their own sessions, and the listeners
// are removed in `destroyed()`. The drop half needs nothing new: a palette
// drop lands on a gap inside `this.el` like any other.

import { StatifierBlocksMeasure } from "./statifier_blocks_measure.js";

export { StatifierBlocksMeasure };

export const StatifierBlocksDrag = {
  mounted() {
    this.dragged = null;
    this.draggedType = null;
    this.editor = this.el.closest(".sb-editor");

    this.el.addEventListener("dragstart", (event) => {
      const block = event.target.closest("[data-block-id]");
      if (!block || !this.el.contains(block)) return;

      this.dragged = block.dataset.blockId;
      if (event.dataTransfer) {
        event.dataTransfer.effectAllowed = "move";
        // Firefox refuses to start a drag without data on the transfer.
        event.dataTransfer.setData("text/plain", this.dragged);
      }
      this.pushEventTo(this.el, "dragstart", { "block-id": this.dragged });
    });

    // A gap is a drop target only while its slot is stamped data-drop="ok",
    // which the server decided. The client holds no validity logic of its
    // own, so it cannot fall out of sync with the server's answer.
    this.el.addEventListener("dragover", (event) => {
      if (this.gapFor(event.target)) event.preventDefault();
    });

    this.el.addEventListener("drop", (event) => {
      const gap = this.gapFor(event.target);
      if (!gap) return;

      const position = {
        "parent-id": gap.dataset.parentId,
        slot: gap.dataset.slot,
        index: gap.dataset.index,
      };

      if (this.draggedType) {
        event.preventDefault();
        this.pushEventTo(this.el, "insert-drop", {
          type: this.draggedType,
          ...position,
        });
        this.draggedType = null;
        return;
      }

      if (!this.dragged) return;

      event.preventDefault();
      this.pushEventTo(this.el, "drop", { "block-id": this.dragged, ...position });
      this.dragged = null;
    });

    this.el.addEventListener("dragend", () => this.endSession());

    // The insert half. `dragstart` fires on the palette entry and `dragend`
    // fires there too, so both are listened for on the document and both are
    // filtered back down to this editor's own palette.
    this.onInsertDragStart = (event) => {
      const entry = this.entryFor(event.target);
      if (!entry) return;

      this.dragged = null;
      this.draggedType = entry.dataset.sbDragType;
      if (event.dataTransfer) {
        event.dataTransfer.effectAllowed = "copy";
        // Firefox refuses to start a drag without data on the transfer.
        event.dataTransfer.setData("text/plain", this.draggedType);
      }
      this.pushEventTo(this.el, "insert-dragstart", { type: this.draggedType });
    };

    this.onInsertDragEnd = (event) => {
      if (this.entryFor(event.target)) this.endSession();
    };

    const doc = this.el.ownerDocument;
    doc.addEventListener("dragstart", this.onInsertDragStart);
    doc.addEventListener("dragend", this.onInsertDragEnd);

    this.reveal();
  },

  updated() {
    this.reveal();
  },

  // `Fit active` has two halves and only one of them is a number. The step
  // that fits the selected card is decided on the server off the measurement
  // (`Shell.fit_zoom/3`); bringing that card into view is a scroll position,
  // which no server holds and no stylesheet can set.
  //
  // So the server states the intent and this carries it out: it stamps
  // `data-sb-reveal="<n>:<block id>"` on the canvas, and the counter is what
  // makes the gesture one-shot. Without it every re-render would re-centre
  // the card and an author could not scroll away from their own selection.
  // This is a view position, not a document command: decision 2's command set
  // is untouched, nothing is pushed, and an editor whose author never presses
  // `Fit active` never runs a line of it.
  reveal() {
    const stamp = this.el.getAttribute("data-sb-reveal");

    if (stamp && stamp !== this.revealed) {
      this.revealed = stamp;
      this.revealing = stamp.slice(stamp.indexOf(":") + 1);
      this.extent = null;
    }

    if (!this.revealing) return;

    const card = this.el.querySelector(`[data-block-id="${CSS.escape(this.revealing)}"]`);
    const panel = this.el.closest('[data-sb-anchor="viewport"]');

    if (!card || !panel) {
      this.revealing = null;
      return;
    }

    // The scroller is moved directly rather than through `scrollIntoView`,
    // which walks every scrollable ancestor and takes the whole page with it.
    // A host embedding the editor in a longer page had `Fit active` scroll the
    // page out from under the editor, which is not a fit.
    const cardBox = card.getBoundingClientRect();
    const panelBox = panel.getBoundingClientRect();

    const extent = `${panel.scrollWidth}x${panel.scrollHeight}`;

    panel.scrollLeft += cardBox.left - panelBox.left - (panelBox.width - cardBox.width) / 2;
    panel.scrollTop += cardBox.top - panelBox.top - (panelBox.height - cardBox.height) / 2;

    // A zoom and its scroll extent do not land in the same render: the wrapper
    // is sized from the measurement the zoomed layout produces, which is a
    // round trip away. So the request stays alive until a re-render arrives
    // with the extent unchanged, and the last of those is the one that centres
    // the card against the size it is actually drawn at.
    if (extent === this.extent) this.revealing = null;
    this.extent = extent;
  },

  destroyed() {
    const doc = this.el.ownerDocument;
    doc.removeEventListener("dragstart", this.onInsertDragStart);
    doc.removeEventListener("dragend", this.onInsertDragEnd);
  },

  // Both gestures end the same way: the client forgets what it was carrying
  // and the server drops the session that stamped `data-drop`.
  endSession() {
    this.dragged = null;
    this.draggedType = null;
    this.pushEventTo(this.el, "dragend", {});
  },

  // The palette entry under this node, if it belongs to the same editor as
  // the canvas this hook is mounted on.
  entryFor(node) {
    if (!node || !node.closest || !this.editor) return null;
    const entry = node.closest("[data-sb-drag-type]");
    return entry && this.editor.contains(entry) ? entry : null;
  },

  // The gap under this node, if the slot it belongs to is one the server
  // marked as accepting what is being dragged.
  //
  // THE GAP'S OWN SLOT, not the nearest ACCEPTING ancestor (sb-4nep). Slots
  // nest - a container in a slot has slots of its own - so asking for the
  // closest ancestor already stamped accepting walked straight past the gap's
  // own refused slot to whatever accepting slot happened to contain it, and
  // every gap in a refused slot inside an accepting one became a live drop
  // target that pushed the REFUSED slot's coordinates. The server then applied
  // it: `Edit.apply/2` deliberately permits arity-violating documents and
  // reports them as findings (decision 5), so the stamp is the enforcement
  // point for exactly the refusals that were being skipped. Found by driving
  // the two gestures in a real browser, which is the half of this interaction
  // no ExUnit test reaches.
  gapFor(node) {
    if (!node || !node.closest) return null;
    const gap = node.closest("[data-slot][data-index]");
    if (!gap) return null;

    const slot = gap.closest("[data-drop]");
    return slot && slot.getAttribute("data-drop") === "ok" ? gap : null;
  },
};

export default { StatifierBlocksDrag, StatifierBlocksMeasure };
