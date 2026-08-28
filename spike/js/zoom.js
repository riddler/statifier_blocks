/*
 * spike/js/zoom.js - the pure half of canvas zoom.
 *
 * WHY THIS FILE EXISTS AT ALL, given that sb-vhu said it should not.
 *
 * The W5 polish pass declined to build a zoom, and wrote down why: "a
 * canvas-wide zoom is not a stylesheet change - it is a transform whose scale
 * every pointer coordinate in `interact.js` would have to be divided by, and a
 * drag hit-test that is subtly wrong is worse than no zoom at all." The
 * reasoning is right. The premise turned out to be wrong, and finding that out
 * is most of what this bead is.
 *
 * `interact.js` HAS no pointer coordinates to divide. Its hit-test is
 * `document.elementFromPoint(clientX, clientY)` plus, for the nearest-gap
 * fallback, distances between that same client point and `getBoundingClientRect()`
 * boxes. Both sides of every comparison are in VIEWPORT space, and both
 * `elementFromPoint` and `getBoundingClientRect` are defined on the rendered
 * geometry - they already account for any transform between the element and the
 * viewport. Two viewport quantities compared against each other need no scale
 * factor, so there is no division to get subtly wrong. The same is true of the
 * reveal arithmetic: `centerUnion` adds a viewport-space DELTA to `scrollLeft`,
 * and a delta between two viewport points is scale-independent.
 *
 * So a transform-scaled stage is correct BY CONSTRUCTION for interaction,
 * provided two things hold, and they are the two this bead had to check rather
 * than assume:
 *
 *   1. The overlays stay outside the transform. The ghost and the "+" picker
 *      are `position: fixed` and are appended to `.sb-spike`, which is an
 *      ANCESTOR of the stage - so the stage's transform cannot become their
 *      containing block. (A transform makes the transformed element the
 *      containing block for fixed descendants; an overlay parked inside the
 *      stage would silently start scaling and mispositioning.)
 *
 *   2. The connector layer is corrected. This is the one place in the spike
 *      that genuinely crosses coordinate spaces, and therefore the one place
 *      that genuinely needs the division: `routeConnectors` subtracts a
 *      post-transform origin from post-transform boxes and writes the result
 *      into an `<svg>` that lives INSIDE the stage, whose own coordinate space
 *      is untransformed. One `rect()` helper, one divide. `scaleOf` and
 *      `unscaleRect` below are that divide, extracted so it is covered by
 *      `dev/selftest.html` rather than only by looking at the screen.
 *
 * The honest revision of the sb-vhu note is therefore: the cost estimate was
 * one division per pointer coordinate across a whole interaction module, and
 * the real cost is one division in one rendering helper. The spike's own
 * design - hit-test through the browser rather than through arithmetic - is
 * what bought that, and it is the finding worth carrying into the shipped
 * editor: an editor that hit-tests with `elementFromPoint` can be zoomed, and
 * an editor that hit-tests with its own coordinate math cannot be, cheaply.
 *
 * Nothing here touches the DOM. Callers pass numbers in and get numbers back,
 * which is what lets the self-test cover it with no browser paint.
 */

/*
 * The ladder, not a continuous range.
 *
 * A continuous zoom is a slider, and a slider on a canvas is a control an
 * author drags until the thing they were reading is a size they did not
 * choose. Rungs mean the "-" and "+" buttons are repeatable and reversible: a
 * press and its opposite land back exactly where they started, which a
 * multiply-by-1.2 zoom does not (0.833 * 1.2 is not 1).
 *
 * Bounded at 1.5 above rather than higher, because the cards carry text at a
 * fixed token size and the reason to zoom IN on this canvas is legibility of
 * a dense region, not magnification; and at 0.4 below, because a card whose
 * label is unreadable is a rectangle, and a canvas of rectangles is a
 * minimap - a different feature with a different design.
 */
export const ZOOM_STEPS = Object.freeze([0.4, 0.5, 0.67, 0.8, 1, 1.25, 1.5]);

export const ZOOM_MIN = ZOOM_STEPS[0];
export const ZOOM_MAX = ZOOM_STEPS[ZOOM_STEPS.length - 1];

/** Anything closer together than this is the same scale, for our purposes. */
const EPSILON = 0.001;

/**
 * A usable scale from whatever was passed.
 *
 * Nullish, NaN and non-finite all become 1 rather than throwing: this value
 * reaches a `transform`, and a canvas that vanishes because a caller passed
 * `undefined` is a worse failure than a canvas that ignores it.
 */
export function clampZoom(value) {
  /*
   * Nullish and empty BEFORE `Number`, which is the trap this guard exists
   * for: `Number(null)` and `Number("")` are both 0, so a missing value would
   * otherwise arrive as "as far out as the ladder goes" rather than as
   * "nothing was asked for". The self-test caught this one; it would have
   * shown up on screen as a canvas that shrank to 40% when a caller forgot an
   * argument, which is exactly the class of quiet wrongness this file's whole
   * argument depends on not having.
   */
  if (value === null || value === undefined || value === "") return 1;

  const scale = Number(value);
  if (!Number.isFinite(scale)) return 1;
  return Math.min(ZOOM_MAX, Math.max(ZOOM_MIN, scale));
}

/** True when two scales are the same to within the epsilon above. */
export function sameZoom(a, b) {
  return Math.abs(Number(a) - Number(b)) < EPSILON;
}

/**
 * The next rung up (`+1`) or down (`-1`) from `current`.
 *
 * `current` need not be a rung - a fit-width lands between two - and then the
 * step moves to the first rung strictly beyond it in the direction asked for.
 * That is what makes "fit, then press +" do something visible rather than
 * snapping back to the rung the fit happened to sit next to.
 */
export function stepZoom(current, direction) {
  const from = clampZoom(current);
  if (direction > 0) {
    return ZOOM_STEPS.find((step) => step > from + EPSILON) ?? ZOOM_MAX;
  }
  if (direction < 0) {
    return [...ZOOM_STEPS].reverse().find((step) => step < from - EPSILON) ?? ZOOM_MIN;
  }
  return from;
}

/**
 * The scale at which `content` fits inside `viewport`, on both axes.
 *
 * Never larger than 1: fitting is about bringing something oversized into
 * view, and a "fit" that MAGNIFIES a small document is a control that moves
 * the canvas when the author asked it to stop moving. `fitZoom` for the
 * width-only case, `fitBoxZoom` when both axes matter.
 *
 * A non-positive or non-finite content or viewport measurement returns 1. Those
 * arrive for real - a hidden canvas measures zero - and the honest answer to
 * "fit nothing into nothing" is "change nothing".
 */
export function fitZoom({ content, viewport, padding = 0 }) {
  const space = Number(viewport) - Number(padding) * 2;
  const size = Number(content);

  if (!Number.isFinite(space) || !Number.isFinite(size)) return 1;
  if (space <= 0 || size <= 0) return 1;

  return clampZoom(Math.min(1, space / size));
}

/** The same, for a box: the tighter of the two axes wins. */
export function fitBoxZoom({ content, viewport, padding = 0 }) {
  return Math.min(
    fitZoom({ content: content?.width, viewport: viewport?.width, padding }),
    fitZoom({ content: content?.height, viewport: viewport?.height, padding })
  );
}

/**
 * The scale a transform is ACTUALLY applying, read off two measurements of the
 * same element: its rendered width (`getBoundingClientRect().width`, which is
 * post-transform) over its layout width (`offsetWidth`, which is not).
 *
 * Derived rather than remembered on purpose. The renderer that needs this
 * number is `render.js`, which does not own the zoom state and should not have
 * to be told about it; asking the DOM what the browser is doing cannot drift
 * from what the browser is doing. It also means the connector correction is
 * right for any transform, including one a HOST applied to an ancestor for
 * reasons of its own - which no piece of editor state would have known about.
 *
 * Returns 1 for a zero or unmeasurable layout width, and snaps to exactly 1
 * inside the epsilon, so the unscaled case does no floating-point work at all.
 */
export function scaleOf(renderedWidth, layoutWidth) {
  const rendered = Number(renderedWidth);
  const layout = Number(layoutWidth);

  if (!Number.isFinite(rendered) || !Number.isFinite(layout) || layout <= 0) return 1;

  const scale = rendered / layout;
  if (!Number.isFinite(scale) || scale <= 0) return 1;
  return sameZoom(scale, 1) ? 1 : scale;
}

/**
 * A measured viewport-space box, in the untransformed coordinate space of the
 * element it was measured against.
 *
 * This is the whole cost of a transform-based zoom, and it is here rather than
 * inline in `render.js` so that it is a covered function rather than a line
 * someone has to re-derive. `origin` is the stage's own post-transform box; the
 * subtraction puts the box in stage space at the rendered scale, and the divide
 * takes it back to the scale the stage's `<svg>` is drawn in.
 */
export function unscaleRect(box, origin, scale) {
  const factor = scale === 0 || !Number.isFinite(scale) ? 1 : scale;

  return {
    x: (box.left - origin.left) / factor,
    y: (box.top - origin.top) / factor,
    width: box.width / factor,
    height: box.height / factor,
  };
}

/**
 * Where the scroller has to be after a zoom change for the viewport to keep
 * showing the same part of the document.
 *
 * Without this a zoom is a teleport: the transform origin is the stage's top
 * left, so scaling from 1 to 0.5 halves every content coordinate and whatever
 * the author was looking at moves to somewhere between there and the corner.
 * Holding the viewport's CENTRE fixed is the behaviour every canvas editor
 * has, and it is three lines of arithmetic rather than a scroll-anchoring
 * heuristic.
 *
 * Clamped at zero only. The upper clamp belongs to the scroller, which knows
 * its own `scrollWidth` after the transform has been applied and will clamp
 * anyway; guessing it here would be a second, staler answer.
 */
export function rescaleScroll({ scroll, viewport, from, to }) {
  const before = Number(from);
  const after = Number(to);

  if (!Number.isFinite(before) || before <= 0) return Number(scroll) || 0;
  if (!Number.isFinite(after) || after <= 0) return Number(scroll) || 0;

  const centre = (Number(scroll) || 0) + (Number(viewport) || 0) / 2;
  return Math.max(0, (centre * after) / before - (Number(viewport) || 0) / 2);
}

/**
 * The label the zoom readout wears: a whole percentage.
 *
 * Rounded rather than truncated, and with no decimal, because the number is
 * read at a glance to answer "am I at 100%" and "67.0%" answers it slower than
 * "67%" does.
 */
export function formatZoom(scale) {
  return `${Math.round(clampZoom(scale) * 100)}%`;
}
