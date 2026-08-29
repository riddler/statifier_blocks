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
//   data-block-id  on each block's root element
//   data-slot      on each gap, with data-parent-id and data-index
//   data-drop      on each slot during a drag session ("ok" or "no")

import { StatifierBlocksMeasure } from "./statifier_blocks_measure.js";

export { StatifierBlocksMeasure };

export const StatifierBlocksDrag = {
  mounted() {
    this.dragged = null;

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
      if (!gap || !this.dragged) return;

      event.preventDefault();
      this.pushEventTo(this.el, "drop", {
        "block-id": this.dragged,
        "parent-id": gap.dataset.parentId,
        slot: gap.dataset.slot,
        index: gap.dataset.index,
      });
      this.dragged = null;
    });

    this.el.addEventListener("dragend", () => {
      this.dragged = null;
      this.pushEventTo(this.el, "dragend", {});
    });
  },

  // The gap under this node, if it is inside a slot the server marked as
  // accepting the block currently being dragged.
  gapFor(node) {
    if (!node || !node.closest) return null;
    const gap = node.closest("[data-slot][data-index]");
    if (!gap) return null;

    const slot = gap.closest('[data-drop="ok"]');
    return slot ? gap : null;
  },
};

export default { StatifierBlocksDrag, StatifierBlocksMeasure };
