// The entire client-side surface of statifier_blocks: one LiveView hook.
//
// ADR-0005 decision 7. The hook translates pointer and drag events into
// pushEvent calls and does nothing else. In particular it never moves a node
// in the DOM: the server re-renders after every command, so a hook that
// patched the tree itself would be fighting LiveView's DOM patching for
// ownership of the same elements, which is the standard way drag-and-drop
// integrations break.
//
// ADDING A SECOND HOOK REQUIRES AMENDING ADR-0005. That is deliberately a
// high bar - a second hook is the signal that some behaviour has started
// living on the client, and this design exists to prevent exactly that.
// The bar is enforced mechanically as well as socially: test/statifier_blocks/
// assets_test.exs reads this file, counts the hooks it exports, and fails
// with a message naming the record.
//
// Delivery is source, per sui-ADR-0009: a host adds
//
//   "statifier_blocks": "file:../deps/statifier_blocks"
//
// to assets/package.json and imports the hook in app.js. This repository
// bundles nothing and has no Node toolchain. The entry point, the export name
// and the hook name are versioned public API.
//
// The DOM contract this depends on is part of the package's contract:
//   data-block-id  on each block's root element
//   data-slot      on each gap, with data-parent-id and data-index
//   data-drop      on each slot during a drag session ("ok" or "no")

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

export default { StatifierBlocksDrag };
