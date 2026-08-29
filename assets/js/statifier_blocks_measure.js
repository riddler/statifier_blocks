// The editor's second LiveView hook, and its entire job is measurement.
//
// ADR-0005 decision 7, as amended 2026-08-29 ("decision 7, a second hook that
// only measures", accepted). Decision 7 ships one hook and says a second one
// requires amending the record; the amendment admits exactly this one and
// states its whole contract in clause 7a:
//
//   * it READS laid-out boxes after render - geometry the browser produced,
//     off elements the server rendered;
//   * it PUSHES that geometry, and that push is the only thing it sends;
//   * it ISSUES NO COMMANDS. No :insert, :move, :remove or :update, no
//     selection, no collapse, no drag event. Decision 2's closed command set
//     is untouched by it;
//   * it NEVER MUTATES THE DOM. No node, no attribute, no style, no class.
//     It does not draw the connectors it makes drawable - the server does,
//     from the numbers this sends;
//   * it HOLDS NO BEHAVIOUR. No validity rule, no layout rule, no routing
//     rule, and no state that survives a re-render.
//
// The fifth clause is why there is no "last payload" memo here, which would
// otherwise be the obvious way to avoid re-sending an unchanged measurement.
// It is not needed: the server's `StatifierBlocks.Connectors.edges/2` is a
// pure function of the tree and the measurement, so an unchanged measurement
// renders unchanged markup, LiveView sends no patch, and nothing re-triggers
// `updated()`. The loop closes on the server's purity rather than on the
// client's memory.
//
// The editor is FULLY USABLE with this file never imported (clause 7b.3):
// nothing is measured, `edges/2` returns an empty list, and the connector
// layer renders nothing at all. Every other affordance is unchanged. That is
// the standing test of the amendment, not a graceful-degradation nicety.
//
// Delivery is source, per sui-ADR-0009 and decision 7's own rule: this file
// is `assets/`'s second entry point, and the entry point, the export name and
// the hook name are versioned public API. A host that wants connectors adds
//
//   import { StatifierBlocksMeasure } from "statifier_blocks/measure";
//
// to its app.js; a host that does not, does not.
//
// The DOM contract it reads is decision 7's, extended by one attribute:
//   data-sb-anchor  on every element whose box the server wants measured,
//                   its value being the anchor key the server stamped and
//                   the key this pushes the rectangle back under. The value
//                   is opaque here: nothing below composes or parses one.
//
// The three wire choices clause 7d left open, and why:
//
//   PAYLOAD SHAPE. One push carries the whole stage - every anchor, flat,
//   each keyed by the server's own string - never a delta. A delta would
//   need a memory of the previous measurement, which 7a forbids, and a whole
//   stage is what makes 7c's test literal: the push is reconstructible from
//   the rendering alone.
//
//   PUSH CADENCE. On mount, on every update, and on a resize of the stage,
//   each scheduled through TWO animation frames and coalesced into one push.
//   Two rather than one because the first frame is merely when the DOM is
//   live and the second is after a font swap or a scrollbar has settled;
//   routing against a pre-swap measurement is the classic way connectors end
//   up a few pixels off their cards, and the spike found exactly this.
//
//   COORDINATE SPACE. The stage's own UNTRANSFORMED pixels: each rectangle
//   has the stage's origin subtracted and is divided by the scale read off
//   the stage. The <svg> the server writes these into is a child of the
//   stage, drawn in the stage's own space and sized from scrollWidth - a
//   layout measurement no transform touches - so rendered coordinates would
//   be scaled twice and every line would detach from the card it joins. The
//   scale is READ from the element rather than passed in, which is also
//   correct for a transform some host applied to an ancestor, something no
//   editor state would have known about.

export const StatifierBlocksMeasure = {
  mounted() {
    this.frames = [];
    this.observer = new ResizeObserver(() => this.schedule());

    const stage = this.stage();
    if (stage) this.observer.observe(stage);

    this.schedule();
  },

  updated() {
    this.schedule();
  },

  destroyed() {
    this.cancel();
    if (this.observer) this.observer.disconnect();
  },

  // The stage: the element the anchors are measured against, and the one
  // whose scroll extent sizes the connector layer. Found by walking up from
  // this hook's own element rather than by an id, so a host that renders two
  // editors on one page measures each against its own stage.
  stage() {
    return this.el.closest('[data-sb-anchor="stage"]');
  },

  // Two frames, coalesced. A second schedule while one is pending replaces
  // it rather than queueing a second push, so a burst of updates measures
  // once.
  schedule() {
    this.cancel();

    this.frames.push(
      requestAnimationFrame(() => {
        this.frames.push(requestAnimationFrame(() => this.measure()));
      })
    );
  },

  cancel() {
    for (const frame of this.frames) cancelAnimationFrame(frame);
    this.frames = [];
  },

  measure() {
    this.frames = [];

    const stage = this.stage();
    if (!stage) return;

    const origin = stage.getBoundingClientRect();

    // Rendered geometry divided by the scale the stage is actually drawn at.
    // It snaps to exactly 1 at the default, so the unscaled case - which is
    // every editor nobody has zoomed - does no arithmetic at all.
    const scale = this.scaleOf(origin.width, stage.offsetWidth);

    const anchors = [];

    for (const element of stage.querySelectorAll("[data-sb-anchor]")) {
      const key = element.getAttribute("data-sb-anchor");
      if (!key || key === "stage") continue;

      const box = element.getBoundingClientRect();

      anchors.push({
        k: key,
        x: (box.left - origin.left) / scale,
        y: (box.top - origin.top) / scale,
        w: box.width / scale,
        h: box.height / scale,
      });
    }

    // `scrollWidth` and `scrollHeight` are layout measurements in the stage's
    // own space, which is why they are sent as they are while every box above
    // is unscaled first.
    this.pushEventTo(this.el, "measure", {
      stage: { w: stage.scrollWidth, h: stage.scrollHeight },
      anchors: anchors,
    });
  },

  scaleOf(rendered, laid) {
    if (!laid || !rendered) return 1;

    const ratio = rendered / laid;
    return Math.abs(ratio - 1) < 0.001 ? 1 : ratio;
  },
};

export default { StatifierBlocksMeasure };
