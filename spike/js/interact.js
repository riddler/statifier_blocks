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

import { createInspector } from "./inspector.js";
import { layoutDocument } from "./layout.js";
import { collectFindings, demoFindings, resolveAnchor } from "./panes.js";
import { renderCanvas } from "./render.js";
import {
  ZOOM_MAX,
  ZOOM_MIN,
  clampZoom,
  fitBoxZoom,
  fitZoom,
  formatZoom,
  rescaleScroll,
  sameZoom,
  scaleOf,
  stepZoom,
} from "./zoom.js";
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
  updateBlockConfig,
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
export function createEditor({ canvas, registry, chrome = {}, datamodel = null }) {
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
  let findings = [];

  /*
   * The blocks a fixture run's current step lights up (sb-9z3). Held here
   * rather than written onto the DOM by the pane, because every command
   * rebuilds the canvas from scratch - a class the pane painted itself would
   * survive exactly until the next undo. The editor owns the canvas, so the
   * editor owns the mark, and re-applying it is one line inside `render`.
   *
   * Deliberately NOT the selection. A step activating three lanes cannot be
   * expressed as a selection, which is single-valued and is also the author's
   * own cursor - hijacking it to show a replay would lose their place.
   */
  let activeMarks = new Set();

  /*
   * The block a fixture run's current step is calling out to, and how that call
   * came back: `{ block, outcome }`, or `null` for no call (sb-foh).
   *
   * Here for the same reason `activeMarks` is here, arrived at the expensive
   * way. The Fixtures pane used to paint this class onto the cards itself,
   * because the seam had `markActive` and nothing for the invoke mark; the
   * price was a canvas rebuild with no `draw` after it - an author editing the
   * document mid-replay - silently dropping the mark until the next transport
   * press. State the editor holds and re-applies in `render` cannot be dropped
   * that way, because the rebuild IS the thing that re-applies it.
   *
   * Single-valued, unlike `activeMarks`: a step calls out to one host at a
   * time. If that ever stops being true, this becomes a Map of block to
   * outcome and `paintInvokeMark` below grows a lookup; nothing else moves.
   */
  let invokeMark = null;

  /*
   * A pane that renders something about the SELECTED block needs to know when
   * it changes, and the inspector's own panes learn that by being refreshed.
   * The Fixtures pane is mounted by the shell rather than by `createInspector`
   * - it reads a fixture file the editor knows nothing about - so it gets a
   * callback instead of a refresh. One handler, set by the shell; the editor
   * does not accumulate subscribers it would then have to unsubscribe.
   */
  let onSelectionChange = null;

  /*
   * The two inspector panes this bead builds. They are given a `state()` rather
   * than the session itself for the reason every other seam here is: the
   * session is replaced by every command, so anything holding one holds a
   * stale value the moment an author does something.
   */
  const inspector = createInspector({
    mounts: {
      config: chrome.configForm ?? null,
      findings: chrome.findingsPanel ?? null,
      findingsBadge: chrome.findingsBadge ?? null,
      condition: chrome.conditionPanel ?? null,
    },
    host: {
      state: () => (session ? { session, findings } : null),
      /*
       * The datamodel seam, handed in by the shell. The editor knows nothing
       * about the datamodel document beyond passing it through: the pane that
       * owns the tree owns the reveal, and this is only the wire that lets a
       * path in a condition reach it. `announce` carries the outcome, because
       * a click on an undeclared path must say something rather than appear
       * to do nothing.
       */
      datamodel: datamodel
        ? {
            index: datamodel.index,
            reveal: (path) => {
              const found = datamodel.reveal(path);
              announce(
                found
                  ? `Revealed ${path} in the datamodel.`
                  : `${path} is not declared in the datamodel document.`
              );
              return found;
            },
          }
        : null,
      // `null` when the edit landed, the refusal otherwise - the form needs
      // the reason, not just the verdict, so it can say WHY under the field
      // the author is standing in rather than only in the canvas's status
      // line, which is three panes away from where they are looking.
      updateConfig: (id, config) => {
        const result = updateBlockConfig(session, id, config);
        return apply(result) ? null : result.error;
      },
      reveal: (finding) => revealFinding(finding),
    },
  });

  /* ------------------------------------------------------------- rendering */

  function render({ center = false } = {}) {
    const scrollLeft = canvas.scrollLeft;
    const scrollTop = canvas.scrollTop;

    if (rendered) rendered.destroy();

    const tree = layoutDocument(session.document, session.registry, {
      collapsed: session.collapsed,
      dropState: (parentId, slot) => dropStateFor(session, parentId, slot),
      // The demo half of the findings set, folded into the layout rather than
      // added beside it, so a folded card's count badge and the findings
      // panel's list are two readings of ONE set (ADR-0005 d11's last
      // sentence, which a second source would quietly falsify).
      extraFindings: demoFindings(session.document.id),
      // sb-c2o's declaration check, wired to the live canvas (sb-e2x). The
      // index is the one `shell.js` already built and already handed this
      // editor for the condition surface - passed through rather than rebuilt,
      // so the canvas's warnings and the datamodel pane's answers cannot
      // disagree about what the document declares. `null` when no datamodel
      // document is in reach, which produces no declaration findings at all.
      datamodelIndex: datamodel?.index ?? null,
    });

    findings = collectFindings(tree, session.document);

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
    applyActiveMarks();
    applyInvokeMark();
    syncChrome(tree);

    return tree;
  }

  function applyActiveMarks() {
    for (const card of canvas.querySelectorAll(".sb-card")) {
      if (activeMarks.has(card.dataset.blockId)) card.dataset.runActive = "true";
      else delete card.dataset.runActive;
    }
  }

  function applyInvokeMark() {
    paintInvokeMark(canvas.querySelectorAll(".sb-card"), invokeMark);
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

    // Decision 12's read-only note used to be a static element flipped here.
    // The config pane now renders it from the actual resolution failure, so it
    // can distinguish `unknown_block_type` from `block_type_too_new` - and one
    // accurate sentence beats two, one of them vague.
    inspector.refresh();
    if (onSelectionChange) onSelectionChange(session?.selectedId ?? null);
  }

  /* ------------------------------------------------------- finding reveal */

  /*
   * ADR-0005 decision 11: "a document-level panel lists all findings;
   * selecting one selects and reveals its anchor."
   *
   * Reveal is four things, and skipping any one of them makes the panel feel
   * broken rather than merely terse: unfold every collapsed ancestor (a
   * finding that navigates to something still hidden is worse than no
   * navigation), select the block, scroll it into view, and flash it so the
   * eye lands where the click sent it. The unfold is the half the count badge
   * on a folded card exists to promise, and this is where the promise is kept.
   */
  function revealFinding(finding) {
    const anchor = resolveAnchor(session.document, finding.anchor);

    if (!anchor.ok) {
      announce("That finding's block is no longer in the document.");
      return;
    }

    const collapsed = new Set(session.collapsed);
    let unfolded = 0;

    for (const id of anchor.ancestorIds) {
      if (collapsed.delete(id)) unfolded += 1;
    }

    // A slot or field anchor is INSIDE the block, so the block itself has to
    // open too; a `:block` anchor is about the card, which a fold does not
    // hide.
    if (anchor.slot !== null || anchor.key !== null) {
      if (collapsed.delete(anchor.blockId)) unfolded += 1;
    }

    session = select({ ...session, collapsed }, anchor.blockId);

    if (unfolded > 0) render();
    else applySelection();

    const card = canvas.querySelector(
      `.sb-card[data-block-id="${cssEscape(anchor.blockId)}"]`
    );

    if (card) {
      centerOn([card]);
      flash(card);
    }

    if (anchor.slot !== null) {
      const slot = canvas.querySelector(
        `[data-block-id="${cssEscape(anchor.blockId)}"][data-slot="${cssEscape(anchor.slot)}"]`
      );
      if (slot) flash(slot);
    }

    announce(
      unfolded === 0
        ? `Revealed ${anchor.blockId}.`
        : `Revealed ${anchor.blockId}, unfolding ${unfolded} block${unfolded === 1 ? "" : "s"}.`
    );
  }

  /*
   * The same reveal, for a SET of blocks (sb-9z3's runner: a step in a parallel
   * region activates two or three lanes at once).
   *
   * Three differences from the single-anchor case, each one a decision the
   * finding reveal did not have to make. Every id's ancestors unfold, so a step
   * whose blocks sit in different collapsed subtrees shows all of them. Only the
   * FIRST is scrolled to - scrolling to each in turn would leave the viewport on
   * the last one and animate past the rest - and every one flashes, which is
   * what says "these three, together" rather than "this one". And the selection
   * is left alone: a replay is not the author's cursor, and moving their
   * selection to follow a step would lose the block they were editing.
   */
  function revealBlocks(ids) {
    const wanted = ids.filter((id) => resolveAnchor(session.document, { blockId: id }).ok);
    if (wanted.length === 0) return false;

    const collapsed = new Set(session.collapsed);
    let unfolded = 0;

    for (const id of wanted) {
      for (const ancestor of resolveAnchor(session.document, { blockId: id }).ancestorIds) {
        if (collapsed.delete(ancestor)) unfolded += 1;
      }
    }

    if (unfolded > 0) {
      session = { ...session, collapsed };
      render();
    }

    const cards = wanted
      .map((id) => canvas.querySelector(`.sb-card[data-block-id="${cssEscape(id)}"]`))
      .filter(Boolean);

    if (cards.length > 0) {
      centerOn(cards);
      for (const card of cards) flash(card);
      announceSpread(cards);
    }

    return true;
  }

  /*
   * The one case centring the union cannot rescue (sb-9z3's note, item 10).
   *
   * Two lanes of a wide parallel region can sit further apart than the canvas
   * is wide, and then no scroll position shows both: centring the union puts
   * the middle of the gap on screen and both cards off the edges, which is the
   * worst of the three available answers except that the other two are worse
   * still. Zooming out is the answer a canvas with a zoom control gives, and
   * this one deliberately does not have one - see the wrap note on sb-vhu.
   *
   * What is cheap, and what the runner was missing, is SAYING so. A step that
   * lights three blocks and shows one looks like a step that lit one block,
   * and an author reading it that way misreads the run rather than merely
   * missing a card. The live region already exists for exactly this kind of
   * statement, and a sentence costs nothing to render and nothing to maintain.
   *
   * Silence when they all fit, on purpose: a message on every step of a replay
   * is a message nobody reads by step four.
   */
  function announceSpread(cards) {
    if (cards.length < 2) return;

    const view = canvas.getBoundingClientRect();
    const box = unionOf(cards);
    if (box.width <= view.width && box.height <= view.height) return;

    const offScreen = cards.filter((card) => {
      const rect = card.getBoundingClientRect();
      return rect.right <= view.left || rect.left >= view.right || rect.bottom <= view.top || rect.top >= view.bottom;
    }).length;

    announce(
      `${cards.length} blocks are active and they do not fit on screen together` +
        (offScreen > 0 ? ` - ${offScreen} ${offScreen === 1 ? "is" : "are"} off the edge.` : ".")
    );
  }

  /*
   * Scrolls so the BOUNDING BOX of a set of cards is centred, rather than
   * scrolling to the first one.
   *
   * Centring the first is what a single-anchor reveal does and it is wrong for
   * a set: a step that lights two parallel lanes centres the left-hand lane and
   * pushes the right-hand one off the far edge, so the author sees one
   * highlighted card and no reason to believe there is another. Centring the
   * union puts both on screen whenever both can fit, and when they cannot it at
   * least splits the difference instead of picking a side.
   */
  function centerOn(cards) {
    if (cards.length === 1) {
      centerSmoothly(cards[0]);
      return;
    }

    /*
     * Two passes, both INSTANT.
     *
     * Instant because a rectangle read while a previous smooth scroll is still
     * animating is a rectangle from halfway through it, and this gesture is
     * pressed repeatedly - once per step of a replay. The first version
     * animated, and stepping twice in a second computed the second target from
     * the first animation's midpoint and landed nowhere near either.
     *
     * Two passes because a card far outside the viewport still reports a real
     * rectangle, but rounding and the stage's own transforms make one pass land
     * short on a forty-block canvas. The first pass gets into the neighbourhood
     * through `scrollIntoView`, which knows about nesting and clamping; the
     * second re-reads the rectangles from there and centres the union exactly.
     */
    cards[0].scrollIntoView({ block: "center", inline: "center", behavior: "instant" });
    centerUnion(cards);
  }

  /** The union rectangle of a set of cards, in viewport coordinates. */
  function unionOf(cards) {
    let left = Infinity;
    let right = -Infinity;
    let top = Infinity;
    let bottom = -Infinity;

    for (const card of cards) {
      const box = card.getBoundingClientRect();
      left = Math.min(left, box.left);
      right = Math.max(right, box.right);
      top = Math.min(top, box.top);
      bottom = Math.max(bottom, box.bottom);
    }

    return { left, right, top, bottom, width: right - left, height: bottom - top };
  }

  /** Puts the centre of that union on the centre of the canvas, at once. */
  function centerUnion(cards) {
    const view = canvas.getBoundingClientRect();
    const box = unionOf(cards);

    canvas.scrollTo({
      left: canvas.scrollLeft + (box.left + box.right) / 2 - (view.left + view.width / 2),
      top: canvas.scrollTop + (box.top + box.bottom) / 2 - (view.top + view.height / 2),
      behavior: "instant",
    });
  }

  /*
   * A smooth scroll that checks where it landed, and corrects it if it landed
   * somewhere else.
   *
   * `scrollIntoView({ behavior: "smooth" })` is a request, not a guarantee.
   * Anything that scrolls the canvas while the animation is running cancels
   * it - a wheel tick, a trackpad flick, a second reveal, the focus ring
   * moving - and the browser simply stops where it is. The reported symptom
   * (sb-84k) is a revealed card sitting at the very bottom edge of the canvas
   * instead of in the middle of it, which is the animation being interrupted a
   * few frames in, and it is worse than not scrolling at all: the flash draws
   * the eye to a card that is half cut off by the pane edge.
   *
   * So the smooth scroll keeps a receipt. `scrollend` fires once the canvas
   * has actually stopped moving, however it stopped, and the card's distance
   * from the centre is then a fact rather than an intention. Off by more than
   * a tolerance means the animation did not finish, and an INSTANT correction
   * puts the card where the reveal promised - instant because a second
   * animation would be interruptible in exactly the same way, and because by
   * this point the author has already waited for one.
   *
   * `scrollend` is not universal, so a timeout is the fallback path and the
   * two are made idempotent by a `settled` flag rather than by trusting either
   * to be the one that runs. The token is what stops an old reveal correcting
   * the viewport out from under a newer one: reveals are clicked in quick
   * succession down a findings list, and a stale correction firing after the
   * next reveal has landed is the same defect in a new place.
   */
  const SETTLE_TOLERANCE_PX = 24;
  const SETTLE_TIMEOUT_MS = 700;
  let settleToken = 0;

  function centerSmoothly(card) {
    const token = ++settleToken;
    card.scrollIntoView({ block: "center", inline: "center", behavior: "smooth" });

    let settled = false;

    const settle = () => {
      if (settled) return;
      settled = true;
      canvas.removeEventListener("scrollend", settle);
      if (token !== settleToken) return;

      const view = canvas.getBoundingClientRect();
      const box = card.getBoundingClientRect();
      const offBy = Math.max(
        Math.abs((box.top + box.bottom) / 2 - (view.top + view.height / 2)),
        Math.abs((box.left + box.right) / 2 - (view.left + view.width / 2))
      );

      if (offBy > SETTLE_TOLERANCE_PX) centerUnion([card]);
    };

    canvas.addEventListener("scrollend", settle);
    window.setTimeout(settle, SETTLE_TIMEOUT_MS);
  }

  /*
   * The flash is a class the element wears for one animation. Removed on
   * `animationend` rather than on a timer, so a reduced-motion user - whose
   * animation the stylesheet shortens to nothing - is not left wearing it.
   */
  function flash(element) {
    element.classList.remove("sb-flash");
    // Reading `offsetWidth` restarts the animation when the same element is
    // revealed twice in a row; without it the second click does nothing.
    void element.offsetWidth;
    element.classList.add("sb-flash");
    element.addEventListener("animationend", () => element.classList.remove("sb-flash"), {
      once: true,
    });
  }

  /* ------------------------------------------------------------------ zoom */

  /*
   * The zoom sb-vhu declined to build, built, and the reason it is now cheap
   * is in the header of `zoom.js`: the drag hit-test has no coordinates of its
   * own to divide. `elementFromPoint` and `getBoundingClientRect` are both
   * defined on rendered geometry, `gapUnder` compares one against the other,
   * and two viewport quantities need no scale factor between them. So the
   * interaction layer below this comment is UNCHANGED by zoom, and that is the
   * claim the selftest and the drag-at-67% pass exist to hold it to.
   *
   * The scale lives as `--sb-zoom` on the CANVAS - the scroller - rather than
   * as an inline transform on the stage. The stage is destroyed and rebuilt by
   * every command; a transform written onto it would be lost on the next
   * insert, and re-applying it would be one more thing `render` has to
   * remember. A property on the scroller is inherited by whatever stage is
   * current, so the zoom simply survives, and the stylesheet keeps the rule
   * that reads it - which is where a visual decision belongs.
   */
  let zoom = 1;

  const stageEl = () => canvas.querySelector(".sb-stage");

  /**
   * Sets the scale, keeping whatever was in the middle of the viewport in the
   * middle of the viewport, and re-routes the connectors afterwards.
   *
   * The re-route is not optional and it is not automatic. `renderCanvas`
   * observes the stage with a `ResizeObserver`, but a transform changes no
   * LAYOUT box, so the observer never fires - the connectors would keep the
   * path data computed at the old scale until the next edit. Asking for the
   * route explicitly, after a frame so the transform has been applied and
   * `getBoundingClientRect` reports the new geometry, is the whole fix.
   */
  function setZoom(next, { announceAs = null } = {}) {
    const to = clampZoom(next);
    const from = zoom;
    if (sameZoom(to, from)) {
      if (announceAs) announce(announceAs);
      syncZoomChrome();
      return to;
    }

    const left = rescaleScroll({ scroll: canvas.scrollLeft, viewport: canvas.clientWidth, from, to });
    const top = rescaleScroll({ scroll: canvas.scrollTop, viewport: canvas.clientHeight, from, to });

    /*
     * Invalidate any reveal that is still holding a receipt.
     *
     * `centerSmoothly` promises to correct the viewport once the canvas has
     * stopped moving, and it keeps that promise for up to `SETTLE_TIMEOUT_MS`
     * after the reveal - which is longer than it takes an author to press a
     * fixture step and then Fit active. Without this line the sequence is:
     * fit, centre, and then a correction from the PREVIOUS reveal fires and
     * scrolls a different card back to the middle, throwing the fit away. It
     * cost an afternoon to see, because the zoom was right and only the scroll
     * was wrong, which reads as a centring bug rather than as a stale receipt.
     *
     * The token already exists for exactly this - "an old reveal must not
     * correct the viewport out from under a newer one" - and a deliberate zoom
     * is a newer gesture in precisely that sense. Bumping it is the whole fix.
     */
    settleToken += 1;

    zoom = to;
    canvas.style.setProperty("--sb-zoom", String(to));
    canvas.dataset.zoomed = sameZoom(to, 1) ? "false" : "true";

    requestAnimationFrame(() => {
      canvas.scrollTo({ left, top, behavior: "instant" });
      rendered?.route();
    });

    syncZoomChrome();
    if (announceAs) announce(announceAs);
    return to;
  }

  /**
   * The scale at which the whole stage fits the pane's width.
   *
   * Measured off `offsetWidth`, which is a LAYOUT width and therefore the same
   * number at every zoom - so pressing Fit width twice is idempotent, and
   * pressing it after zooming in does not compound. `fitZoom` refuses to go
   * above 1, so a document narrower than the pane leaves the canvas alone
   * instead of magnifying it, which is the one thing a "fit" must never do to
   * an author who pressed it to stop hunting.
   */
  function fitWidth() {
    const stage = stageEl();
    if (!stage) return zoom;

    const to = fitZoom({ content: stage.offsetWidth, viewport: canvas.clientWidth });

    /*
     * The third case, and the one the first version of this got wrong: a
     * document wider than the ladder reaches. The deep demo document is 2380px
     * of stage in a 902px pane, which wants 38% and gets the 40% floor - and
     * the control announced "Fitted to width at 40%" while a third of the tree
     * was still off the edge. A control that reports success it did not have
     * is worse than one that cannot do the job, because the author stops
     * looking for the rest of their document.
     *
     * The exact ratio is recomputed here rather than teased back out of the
     * clamp: `fitZoom` returning `ZOOM_MIN` is ambiguous between "the floor is
     * what fits" and "the floor is as close as I can get", and only the
     * unclamped number tells them apart.
     */
    const exact = stage.offsetWidth > 0 ? canvas.clientWidth / stage.offsetWidth : 1;

    const announceAs =
      exact >= 1
        ? "The document already fits the canvas width."
        : exact < ZOOM_MIN
          ? `This document is too wide to fit - ${formatZoom(ZOOM_MIN)} is as far out as the canvas goes, and some of it is still off the edge.`
          : `Fitted to width at ${formatZoom(to)}.`;

    return setZoom(to, { announceAs });
  }

  /**
   * Brings the ACTIVE set into view: zoom out far enough that the union of the
   * blocks a replayed step lit fits the pane, then centre it.
   *
   * The composition is the point, and it is the answer to the case sb-9z3
   * recorded and sb-vhu could only announce. `centerOn` alone puts the middle
   * of a too-wide union on screen with both ends off the edges; a zoom alone
   * leaves the union wherever it was. Together they are the gesture an author
   * means by "show me the step".
   *
   * Degrades in both directions honestly. A union that already fits gets the
   * centre and no zoom change - re-scaling a canvas that did not need it is
   * the same broken promise as magnifying on fit. A union that cannot be made
   * to fit even at `ZOOM_MIN` gets the closest scale there is and keeps
   * `announceSpread`'s sentence, which is what says so out loud rather than
   * leaving the author to conclude the step lit fewer blocks than it did.
   */
  function fitActive() {
    const cards = [...activeMarks]
      .map((id) => canvas.querySelector(`.sb-card[data-block-id="${cssEscape(id)}"]`))
      .filter(Boolean);

    if (cards.length === 0) {
      announce("No replayed step is active, so there is nothing to fit to.");
      return false;
    }

    const box = unionOf(cards);
    const stage = stageEl();
    // The union is measured in RENDERED pixels; the fit has to be computed
    // against the size it would be at scale 1, or every press would compound
    // the last one. One divide, and it is the same `scaleOf` the connector
    // correction uses rather than a second reading of the same fact.
    const current = stage ? scaleOf(stage.getBoundingClientRect().width, stage.offsetWidth) : 1;

    const to = fitBoxZoom({
      content: { width: box.width / current, height: box.height / current },
      viewport: { width: canvas.clientWidth, height: canvas.clientHeight },
      padding: 24,
    });

    setZoom(to);

    /*
     * Two frames, not one, and it is the same two `renderCanvas` takes for the
     * same reason: the first is when the new geometry is live, the second is
     * after everything else that wanted to move has moved.
     *
     * One frame was enough only when the canvas was already still. An author
     * pressing Fit active immediately after a fixture step - which is when
     * they press it - lands inside that step's own reveal, whose scroll is
     * applied in the frame this one shares, and the centring then computes
     * against a viewport that is about to move again. The measured symptom was
     * the right zoom with the second lane 240px off the edge: an answer that
     * looks like a centring bug and is really a race. Deferring one more frame
     * costs 16ms and makes the gesture timing-independent, which a control an
     * author mashes has to be.
     */
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        const live = [...activeMarks]
          .map((id) => canvas.querySelector(`.sb-card[data-block-id="${cssEscape(id)}"]`))
          .filter(Boolean);
        if (live.length === 0) return;
        centerOn(live);
        announceSpread(live);
      });
    });

    return true;
  }

  function syncZoomChrome() {
    if (chrome.zoomLabel) chrome.zoomLabel.textContent = formatZoom(zoom);
    if (chrome.zoomOut) chrome.zoomOut.disabled = sameZoom(zoom, ZOOM_MIN);
    if (chrome.zoomIn) chrome.zoomIn.disabled = sameZoom(zoom, ZOOM_MAX);
    if (chrome.zoomFitActive) chrome.zoomFitActive.disabled = activeMarks.size === 0;
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
    syncZoomChrome();
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
    // A refusal that stays on screen after the next gesture succeeds is a
    // refusal the author will read as being about the gesture that worked.
    announce("");
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

  /*
   * The zoom controls. Every one is optional, like the rest of `chrome`, so a
   * bare canvas in a test page still works with none of them present - and
   * `syncZoomChrome` is null-safe for the same reason.
   */
  if (chrome.zoomOut) {
    chrome.zoomOut.addEventListener("click", () => setZoom(stepZoom(zoom, -1)));
  }
  if (chrome.zoomIn) {
    chrome.zoomIn.addEventListener("click", () => setZoom(stepZoom(zoom, +1)));
  }
  if (chrome.zoomLabel) {
    // The readout is the reset. A percentage that is also the way back to
    // 100% is one control instead of two, and "click the number to get back
    // to normal" is the idiom every canvas editor already taught the author.
    chrome.zoomLabel.addEventListener("click", () =>
      setZoom(1, { announceAs: "Zoom reset to 100%." })
    );
  }
  if (chrome.zoomFit) {
    chrome.zoomFit.addEventListener("click", () => fitWidth());
  }
  if (chrome.zoomFitActive) {
    chrome.zoomFitActive.addEventListener("click", () => fitActive());
  }

  syncZoomChrome();

  return {
    /** Loads a decoded document, replacing whatever the editor held. */
    open(doc) {
      cancelDrag();
      closePicker();
      session = createSession(doc, registry);
      announce("");
      return render({ center: true });
    },

    /**
     * Drops the open document. The shell calls it for the "None" option, so
     * the inspector empties with the canvas rather than going on describing a
     * block nothing is showing.
     */
    clear() {
      cancelDrag();
      closePicker();
      session = null;
      findings = [];
      activeMarks = new Set();
      invokeMark = null;
      if (rendered) rendered.destroy();
      rendered = null;
      canvas.replaceChildren();
      announce("");
      inspector.refresh();
    },

    /** The live session - the read handle a test or a console poke needs. */
    get session() {
      return session;
    },

    /* --------------------------------------------- the fixture-runner seam */

    /** Lights up the blocks one replayed step activates. `[]` clears it. */
    markActive(ids) {
      activeMarks = new Set(ids ?? []);
      if (session) applyActiveMarks();
      // Fit to active is only meaningful while something is active, and a
      // control that is enabled when it can do nothing is a control that
      // teaches an author to distrust the toolbar.
      syncZoomChrome();
    },

    /**
     * Marks the block a replayed step is calling out to, and how the call came
     * back - `"done"` or `"error"`, the values the stylesheet keys off, or null
     * for a call with no answer yet. A null block clears the mark.
     *
     * Beside `markActive` rather than folded into it: the two marks answer
     * different questions - "where is the run now" and "who is it waiting on" -
     * they are set from different parts of a step view, and a step can have
     * either without the other. One call that took both would make every caller
     * that has one of them pass a placeholder for the other.
     */
    markInvoking(block, outcome = null) {
      invokeMark = block == null ? null : { block, outcome };
      if (session) applyInvokeMark();
    },

    /** Unfolds, scrolls to and flashes a set of blocks. Selection untouched. */
    revealBlocks(ids) {
      return session ? revealBlocks(ids ?? []) : false;
    },

    /** Selects and reveals one block, the way a findings row does. */
    revealBlock(id) {
      if (!session) return false;
      revealFinding({ anchor: { kind: "block", blockId: id } });
      return true;
    },

    /* ------------------------------------------------------------- zoom */

    /** The canvas scale. 1 is unzoomed; the range is `zoom.js`'s ladder. */
    get zoom() {
      return zoom;
    },

    /** Sets it, clamped to the ladder's bounds, keeping the centre fixed. */
    setZoom(value) {
      return setZoom(value);
    },

    /** Scales so the whole stage fits the pane's width. Never magnifies. */
    fitWidth() {
      return fitWidth();
    },

    /** Scales and centres so the replayed step's active blocks fit. */
    fitActive() {
      return fitActive();
    },

    /** The selected block id, or null - what the truth tables key off. */
    get selectedId() {
      return session?.selectedId ?? null;
    },

    /** Called after every selection change, so a pane can follow it. */
    set onSelectionChange(handler) {
      onSelectionChange = handler;
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

/** The class and the data attribute the invoke mark writes onto a card. */
export const INVOKE_MARK_CLASS = "sb-card--invoking";

/**
 * Paints the invoke mark over a list of cards: `mark` is `{ block, outcome }`
 * or `null`, and every card that is not the marked one is cleared.
 *
 * Exported and pure over what it is handed, which is what makes the contract
 * testable without a mounted editor - a suite can hand it three plain elements
 * and read the result. It takes an iterable of cards rather than reaching for
 * `document` for the same reason.
 *
 * Cards are walked and compared rather than selected by id: a block id is
 * author-controlled text, and building a selector out of it needs escaping that
 * is one forgotten call away from a silent no-op. One pass over the cards costs
 * nothing at spike sizes and cannot be got wrong that way.
 */
export function paintInvokeMark(cards, mark) {
  const target = mark == null ? null : mark.block;

  for (const card of cards) {
    if (target !== null && card.dataset.blockId === target) {
      card.classList.add(INVOKE_MARK_CLASS);
      if (mark.outcome == null) delete card.dataset.invokeOutcome;
      else card.dataset.invokeOutcome = mark.outcome;
    } else if (card.classList.contains(INVOKE_MARK_CLASS)) {
      card.classList.remove(INVOKE_MARK_CLASS);
      delete card.dataset.invokeOutcome;
    }
  }
}

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
