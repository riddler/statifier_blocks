/*
 * spike/js/render.js - the layout tree as DOM, and the connectors as SVG.
 *
 * Two passes, in this order, and the order is the whole design:
 *
 *   1. **Emit.** Walk the layout tree from `layout.js` and build nested DOM.
 *      Nesting in the tree is nesting in the DOM, so the browser's own layout
 *      engine does the auto-layout - columns for a fan, a rail beside a body,
 *      a stack for a sequence - and nothing here computes a coordinate.
 *   2. **Route.** Measure the anchors the first pass left behind and write SVG
 *      path data over the top. Connectors are therefore derived from where
 *      the blocks ACTUALLY landed rather than from where a layout algorithm
 *      predicted they would, which is what keeps them correct when a config
 *      summary wraps to two lines or a theme changes the type scale.
 *
 * The second pass re-runs on resize. It never writes to the tree, only to the
 * `<svg>`, so it can never fight the first pass for ownership of an element -
 * the same discipline ADR-0005 decision 7 imposes on the shipped drag hook.
 *
 * ## Connectors are rendered, never authored
 *
 * Every edge drawn here is derived from adjacency inside a slot or from the
 * nesting of a slot inside a block. There is no edge in the document, no edge
 * in the layout tree, and nothing an author can point at to change one. Three
 * kinds:
 *
 *   flow       between adjacent children of one slot, and from a container's
 *              header into the first child of its body
 *   fan/join   from a container that arranges its primary slots side by side,
 *              out to each column and back
 *   interrupt  from a rule on a secondary rail, out to its group's exit
 *
 * ## What this file deliberately does not do
 *
 * Selection, drag, collapse, and the "+" insertion affordances are sb-ad2's.
 * The DOM they need is emitted here and left inert: `data-block-id` on every
 * card, `data-slot` and `data-index` on every gap, `data-drop` unset,
 * `aria-selected="false"`, and a `.sb-node__children` wrapper a collapse can
 * hide without disturbing the header it hangs from.
 */

import { fanPath, flowPath, interruptPath, inlet, joinPath, outlet } from "./layout.js";
import { accentTokenFor, blockAccentStyle } from "./theme.js";

/* ================================================================ icons */

/*
 * ADR-0005 decision 10 is emphatic that `icon` is a NAME and never markup:
 * the editor takes an icon component as an attr and passes the name to it, so
 * that a host renders its own set and a host with no set gets a neutral
 * glyph. This map is the spike playing the part of that host component. It is
 * not part of the editor's contract and it is not what any host will use.
 *
 * Stroke paths on a 24-box, all of them `currentColor`, so an icon costs one
 * colour token and inherits the card's.
 */
const ICONS = {
  "bars-3": "M4 7h16M4 12h16M4 17h16",
  "rectangle-group": "M4 5h7v6H4zM13 5h7v6h-7zM4 13h16v6H4z",
  "arrow-path": "M20 12a8 8 0 1 1-2.6-5.9M20 4v4h-4",
  "arrows-right-left": "M4 8h13M14 5l3 3-3 3M20 16H7M10 13l-3 3 3 3",
  "view-columns": "M4 5h4v14H4zM10 5h4v14h-4zM16 5h4v14h-4z",
  clock: "M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18zM12 7v5l3 2",
  "clock-alert": "M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18zM12 7v5M12 16h.01",
  bolt: "M13 3 5 14h6l-1 7 8-11h-6z",
  "credit-card": "M3 7h18v10H3zM3 11h18",
  banknotes: "M3 7h18v8H3zM12 11h.01M6 17h12",
  "user-plus": "M10 11a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7zM3 20a7 7 0 0 1 14 0M18 8v6M15 11h6",
  inbox: "M4 13V6h16v7M4 13h4l1 3h6l1-3h4v5H4z",
  shield: "M12 3 5 6v5c0 4 3 7.4 7 9 4-1.6 7-5 7-9V6z",
  flag: "M6 21V4M6 5h11l-2 3.5L17 12H6",
  scale: "M12 4v16M7 20h10M5 9h14M5 9 3 14h4zM19 9l-2 5h4z",
  "device-phone": "M8 3h8v18H8zM11 18h2",
  pause: "M9 5v14M15 5v14",
  check: "M5 13l4 4L19 7",
  receipt: "M6 3h12v18l-2-1.5-2 1.5-2-1.5-2 1.5-2-1.5zM9 8h6M9 12h6",
  megaphone: "M4 10v4h3l7 4V6l-7 4zM18 9a4 4 0 0 1 0 6",
  sparkles: "M12 4l1.6 4.4L18 10l-4.4 1.6L12 16l-1.6-4.4L6 10l4.4-1.6zM18 15l.8 2.2L21 18l-2.2.8L18 21l-.8-2.2L15 18l2.2-.8z",
  /* An arrow leaving the box: the proposed `core.invoke`, which is the one
   * step in the vocabulary whose work happens somewhere else. */
  "arrow-up-right": "M6 18 18 6M9 6h9v9",
};

/* The neutral glyph a name with no drawing gets - never nothing. */
const NEUTRAL_ICON = "M8 12h8";

export function iconElement(name) {
  const svg = svgEl("svg", {
    class: "sb-icon",
    viewBox: "0 0 24 24",
    "aria-hidden": "true",
    focusable: "false",
  });
  svg.append(svgEl("path", { d: ICONS[name] ?? NEUTRAL_ICON }));
  return svg;
}

/* ============================================================== helpers */

const SVG_NS = "http://www.w3.org/2000/svg";

export function el(tag, attrs = {}, children = []) {
  const node = document.createElement(tag);
  for (const [key, value] of Object.entries(attrs)) {
    if (value === null || value === undefined) continue;
    if (key === "text") node.textContent = String(value);
    else node.setAttribute(key, String(value));
  }
  node.append(...children.filter(Boolean));
  return node;
}

function svgEl(tag, attrs = {}) {
  const node = document.createElementNS(SVG_NS, tag);
  for (const [key, value] of Object.entries(attrs)) {
    if (value === null || value === undefined) continue;
    node.setAttribute(key, String(value));
  }
  return node;
}

/* ================================================================ emit */

/**
 * Renders one layout tree into `mount`, replacing whatever was there, and
 * returns a handle whose `route()` redraws the connectors and whose
 * `destroy()` unhooks the resize observer.
 *
 * `mount` is the canvas viewport; the stage it builds inside is what scrolls
 * and what the SVG covers.
 */
export function renderCanvas(mount, tree, { center = true } = {}) {
  mount.replaceChildren();

  const stage = el("div", { class: "sb-stage" });
  const edges = svgEl("svg", { class: "sb-connectors", "aria-hidden": "true" });
  edges.append(markerDefs());

  const edgeLayer = svgEl("g", { class: "sb-connectors__edges" });
  edges.append(edgeLayer);

  const treeRoot = el("div", { class: "sb-tree-root" }, [renderNode(tree.root)]);

  stage.append(edges, treeRoot);
  mount.append(stage);

  const handle = {
    stage,
    edges,
    edgeLayer,
    route: () => routeConnectors(stage, edges, edgeLayer),
    destroy: () => observer.disconnect(),
  };

  // Measure after the browser has laid the tree out. Two frames rather than
  // one: the first is when the DOM is live, the second is after any font
  // swap or scrollbar has settled, and routing against a pre-swap measurement
  // is the classic way connectors end up a few pixels off their cards.
  requestAnimationFrame(() => {
    handle.route();

    // The tree is centred in a stage as wide as its widest fan, so on a
    // document with a deep parallel the interesting part starts off-screen.
    // Opening scrolled to the middle is the difference between "here is your
    // workflow" and "here is some empty grid".
    //
    // Only when OPENING, though. An edit re-renders the whole canvas, and
    // re-centring on every insert would yank the view away from the block the
    // author just placed - the one thing they are looking at.
    if (center) {
      mount.scrollLeft = Math.max(0, (mount.scrollWidth - mount.clientWidth) / 2);
    }

    requestAnimationFrame(handle.route);
  });

  const observer = new ResizeObserver(() => handle.route());
  observer.observe(stage);

  return handle;
}

/*
 * Two arrowheads rather than one, because a marker's fill cannot inherit the
 * stroke of the path that references it in every browser that matters yet.
 * Both read their colour from a token, so a theme still moves them.
 */
function markerDefs() {
  const defs = svgEl("defs");

  for (const [id, cls] of [
    ["sb-arrow", "sb-arrow--flow"],
    ["sb-arrow-interrupt", "sb-arrow--interrupt"],
  ]) {
    const marker = svgEl("marker", {
      id,
      class: cls,
      viewBox: "0 0 8 8",
      refX: "6.5",
      refY: "4",
      markerWidth: "7",
      markerHeight: "7",
      orient: "auto-start-reverse",
      markerUnits: "userSpaceOnUse",
    });
    marker.append(svgEl("path", { d: "M0 0.5 L7 4 L0 7.5 z" }));
    defs.append(marker);
  }

  return defs;
}

/** One layout node: its card, and - when it has children - its body. */
function renderNode(node) {
  const wrapper = el("div", {
    class: `sb-node sb-node--${node.shape}`,
    "data-block-id": node.id,
    "data-shape": node.shape,
    "data-arrangement": node.arrangement,
    "data-depth": node.depth,
    // A container that declares a secondary slot is a BOUNDARY: an interrupt
    // rule can only fire against a region with an edge. The stylesheet draws
    // the box off this, so the distinction stays derived from ADR-0005
    // decision 10's `slot_style` rather than from a type name.
    "data-boundary": node.secondary.length > 0 ? "true" : "false",
    "data-collapsed": node.collapsed ? "true" : "false",
  });

  wrapper.append(renderCard(node));

  // A folded container emits NO body at all rather than a hidden one. Hiding
  // it would leave the routing pass measuring elements with zero-sized
  // rectangles and drawing connectors to the origin; not emitting it means the
  // fold is simply a smaller tree, and pass two is correct without knowing
  // that collapse exists.
  if (node.shape === "container" && !node.collapsed) {
    wrapper.append(renderBody(node));
  }

  // The outlet is a zero-height anchor at the very bottom of everything this
  // node contains, so a flow edge leaving a CONTAINER leaves the container
  // rather than its header. It is measured, never seen.
  wrapper.append(el("div", { class: "sb-node__outlet", "aria-hidden": "true" }));

  return wrapper;
}

function renderCard(node) {
  const card = el("div", {
    class: [
      "sb-card",
      `sb-card--${node.shape}`,
      node.unresolved ? "sb-card--unresolved" : null,
      // Flagged is for ERRORS. A card carrying only an advisory finding gets
      // the quieter treatment, because a canvas where an informational note
      // and a broken config look identical teaches an author to ignore both.
      !node.unresolved && node.findings.some((one) => one.severity === "error")
        ? "sb-card--flagged"
        : null,
      !node.unresolved &&
      node.findings.length > 0 &&
      !node.findings.some((one) => one.severity === "error")
        ? "sb-card--noted"
        : null,
    ]
      .filter(Boolean)
      .join(" "),
    "data-block-id": node.id,
    // sb-957's per-block-type accent. The renderer knows the token's NAME
    // and never its value, so which colour this is remains the theme's call
    // and no block type is named anywhere in the editor's CSS or JS.
    "data-sb-block-accent": accentTokenFor(node),
    style: blockAccentStyle(node),
    // Selection is a chrome-only attribute flip that `interact.js` writes
    // straight onto the DOM: a click that re-laid-out and re-routed the whole
    // canvas would make the cheapest gesture in the editor the most expensive
    // one, for no change to a single rectangle.
    "aria-selected": "false",
    // Reachable by keyboard once selected, and skipped by Tab otherwise -
    // roving tabindex, which is what a tree of dozens of cards needs.
    tabindex: "-1",
    role: "treeitem",
    "aria-expanded": node.shape === "container" ? String(!node.collapsed) : null,
  });

  card.append(el("span", { class: "sb-card__icon" }, [iconElement(node.icon)]));

  const text = el("span", { class: "sb-card__text" });
  text.append(el("span", { class: "sb-card__title", text: node.title }));

  // The caption and the config chips share one row, and that row is INSIDE
  // the text column rather than beside it. Putting the chips beside the text
  // steals width from the title, which is the one thing on the card a reader
  // is actually looking for - "Collect the company details" wrapping to three
  // lines so that a mode chip can sit next to it is the wrong trade.
  if (node.caption !== node.title || node.badge !== null || node.chips.length > 0) {
    const meta = el("span", { class: "sb-card__meta" });

    if (node.caption !== node.title) {
      meta.append(el("span", { class: "sb-card__caption", text: node.caption }));
    }

    // sb-p0k's badge, between the caption and the config chips. It answers a
    // different question from either neighbour - the caption says what type
    // this is and the chips say how it is configured, while the badge says
    // what the type DOES that its label does not admit to ("calls the host",
    // "timer"). Reading order puts it right after the type name, which is the
    // clause it modifies.
    //
    // Generic, like the accent: `layout.js` hands over a string a descriptor
    // declared, and nothing here or in `editor.css` names a block type. A
    // type that declares no badge produces no element, not an empty one.
    if (node.badge !== null) {
      meta.append(el("span", { class: "sb-chip sb-chip--badge", text: node.badge }));
    }

    for (const chip of node.chips) {
      meta.append(
        el("span", {
          class: "sb-chip sb-chip--config",
          text: chip.value,
          title: `${chip.label}: ${chip.value}`,
        })
      );
    }

    text.append(meta);
  }

  // One summary item needs no label - "2m" under a card captioned "Wait"
  // says everything "Wait for 2m" does and takes half the width, and at
  // depth 7 that difference is the whole legibility budget. Two or more do
  // need labels, because then the reader is telling them apart.
  if (node.summary.length > 0) {
    const labelled = node.summary.length > 1;
    text.append(
      el("span", {
        class: "sb-card__summary",
        text: node.summary
          .map((item) => (labelled ? `${item.label} ${item.value}` : item.value))
          .join("  ·  "),
        title: node.summary.map((item) => `${item.label}: ${item.value}`).join("\n"),
      })
    );
  }

  if (node.collapsed) text.append(renderFolded(node));

  card.append(text);

  if (node.unresolved) card.append(renderUnresolved(node));

  card.append(renderCardActions(node));

  return card;
}

/*
 * The fold indicator and the delete affordance, in that order, pinned to the
 * card's trailing edge.
 *
 * Both are real `<button>`s carrying a `data-action`, which is the whole
 * contract `interact.js` reads: one delegated listener on the canvas matches
 * on the attribute, so adding an affordance never means adding a listener.
 * Buttons rather than clickable spans because they have to answer Enter and
 * Space, and because "delete this block" is exactly the kind of thing a
 * screen-reader user should not have to discover by hovering.
 */
function renderCardActions(node) {
  const actions = el("span", { class: "sb-card__actions" });
  const container = node.shape === "container";

  if (container) {
    actions.append(
      el("button", {
        class: "sb-card__action sb-card__action--fold",
        type: "button",
        "data-action": "toggle-collapsed",
        "data-block-id": node.id,
        // The label says what the click DOES, not what the state is: "Collapse"
        // on an open group and "Expand" on a folded one.
        "aria-label": `${node.collapsed ? "Expand" : "Collapse"} ${node.title}`,
        title: node.collapsed ? "Expand" : "Collapse",
        text: node.collapsed ? "+" : "−",
      })
    );
  }

  // No delete on the root. `Edit.apply/2` refuses `cannot_remove_root`, so
  // offering the button would be offering a gesture the algebra will always
  // turn down - and a control that never works is worse than an absent one.
  if (node.parentId !== null) {
    actions.append(
      el("button", {
        class: "sb-card__action sb-card__action--delete",
        type: "button",
        "data-action": "delete-block",
        "data-block-id": node.id,
        "aria-label": `Delete ${node.title}`,
        title: "Delete",
        text: "×",
      })
    );
  }

  return actions;
}

/*
 * ADR-0005 decision 11's last sentence, made visible: "a collapsed subtree
 * carries a count badge so a finding can never hide inside something folded
 * shut - which is the failure mode that makes tree editors feel unreliable."
 *
 * Two numbers, and they are different questions. The block count says how much
 * is folded away; the finding count says whether any of it needs attention,
 * and it is drawn only when it is non-zero, because a "0 findings" badge on
 * every folded card trains an author to stop reading badges.
 */
function renderFolded(node) {
  const hidden = node.descendantCount;
  const flagged = node.findings.length + node.descendantFindings;

  const box = el("span", { class: "sb-folded" });

  box.append(
    el("span", {
      class: "sb-folded__count",
      text: `${hidden} block${hidden === 1 ? "" : "s"} hidden`,
    })
  );

  if (flagged > 0) {
    box.append(
      el("span", {
        class: "sb-folded__findings",
        "data-severity": "error",
        title: `${flagged} finding${flagged === 1 ? "" : "s"} inside this folded block`,
        text: `${flagged} finding${flagged === 1 ? "" : "s"}`,
      })
    );
  }

  return box;
}

/*
 * ADR-0005 decision 12's chrome. Three things the record asks for and one it
 * does not: the unavailable badge, the `:block` finding, and the config
 * read-only as canonical JSON - and, not in the record but the reason the
 * case exists at all, a line saying the bytes are safe. An author who opens a
 * document and sees a block they cannot edit needs to be told the difference
 * between "unavailable" and "lost".
 */
function renderUnresolved(node) {
  const box = el("span", { class: "sb-unresolved" });

  // No second copy of the type name here: an unresolvable block has no
  // palette label to fall back to, so its title IS the type name already.
  box.append(el("span", { class: "sb-unresolved__badge", text: "Unavailable" }));

  for (const finding of node.findings) {
    box.append(el("span", { class: "sb-unresolved__message", text: finding.message }));
  }

  box.append(
    el("span", {
      class: "sb-unresolved__note",
      text: "Config is read-only and its stored bytes are preserved.",
    })
  );

  if (node.rawConfig) {
    box.append(el("pre", { class: "sb-unresolved__config", text: node.rawConfig }));
  }

  return box;
}

/** A container's body: its primary slots, arranged, plus any rails beside. */
function renderBody(node) {
  const body = el("div", { class: "sb-node__body" });
  const children = el("div", {
    class: "sb-node__children",
    // A collapse hides this element; the header card above it stays put, and
    // the count badge it would carry is already computable (sb-ad2 owns both).
    "data-collapsed": "false",
  });

  if (node.arrangement === "stack") {
    for (const slot of node.primary) children.append(renderStackSlot(node, slot));
  } else {
    children.append(renderColumns(node));
  }

  body.append(children);

  if (node.secondary.length > 0) body.append(renderRail(node));

  return body;
}

/*
 * A stacked slot. Its header is drawn only when the block has more than one
 * primary slot to tell apart, or when the slot is one the type did not
 * declare - a lone `body` labelled "Steps" above a sequence is noise, and
 * noise at depth 7 is what makes a canvas unreadable.
 */
function renderStackSlot(node, slot) {
  const wrapper = el("div", {
    class: "sb-slot sb-slot--stack",
    "data-block-id": node.id,
    "data-slot": slot.name,
    "data-drop": slot.dropState,
  });

  if (node.primary.length > 1 || slot.undeclared) {
    wrapper.append(renderSlotHeader(slot));
  }

  wrapper.append(renderChildren(node, slot));

  return wrapper;
}

function renderSlotHeader(slot) {
  return el("div", { class: "sb-slot__header" }, [
    el("span", { class: "sb-slot__label", text: slot.label }),
    slot.undeclared
      ? el("span", { class: "sb-slot__tag", text: "undeclared" })
      : null,
  ]);
}

/**
 * The children of one slot, with a gap before each and one after. The gaps
 * are the "+" insertion points and the drop seams sb-ad2 will animate; here
 * they are measured spacing that happens to carry the coordinates.
 */
function renderChildren(node, slot) {
  const list = el("div", { class: "sb-slot__children" });

  if (slot.children.length === 0) {
    list.append(renderGap(node, slot, 0));
    list.append(
      el("div", { class: "sb-slot__empty", text: `no ${slot.label.toLowerCase()} yet` })
    );
    return list;
  }

  slot.children.forEach((child, index) => {
    list.append(renderGap(node, slot, index));
    list.append(renderNode(child));
  });
  list.append(renderGap(node, slot, slot.children.length));

  return list;
}

/*
 * One insertion point: the drop seam, and the "+" that makes it reachable
 * without a pointer at all (ADR-0005 decision 8).
 *
 * The button is always emitted, never conditionally on a drag. Emitting it
 * only for highlighted slots would be the obvious optimisation and it is the
 * wrong one: decision 8 is an accessibility guarantee, and a control that
 * exists only while a drag is running is a control a keyboard user cannot
 * reach. What the "+" offers is filtered instead - the picker asks the same
 * predicate the highlight does, so an author never opens it onto an empty list
 * without being told why.
 */
function renderGap(node, slot, index) {
  const gap = el("div", {
    class: "sb-gap",
    "data-block-id": node.id,
    "data-slot": slot.name,
    "data-index": index,
  });

  gap.append(
    el("button", {
      class: "sb-gap__add",
      type: "button",
      "data-action": "open-picker",
      "data-block-id": node.id,
      "data-slot": slot.name,
      "data-index": index,
      "aria-label": `Insert into ${slot.label} at position ${index + 1}`,
      "aria-haspopup": "menu",
      "aria-expanded": "false",
      title: "Insert a block here",
      text: "+",
    })
  );

  return gap;
}

/**
 * The side-by-side arrangement: a fan marker, the columns, and a join marker.
 *
 * `fan` and `lanes` differ here only in what the two markers say and in the
 * class the edges carry. Both derive from ADR-0005 decision 10's `layout`
 * metadata (see layout.js) and neither knows what block type it is drawing.
 */
function renderColumns(node) {
  const exclusive = node.arrangement === "fan";

  const wrapper = el("div", {
    class: `sb-fan sb-fan--${node.arrangement}`,
  });

  wrapper.append(
    el("div", { class: "sb-fan__marker sb-fan__marker--hub" }, [
      el("span", {
        class: "sb-fan__label",
        text: exclusive ? "one of" : "all of",
      }),
    ])
  );

  const columns = el("div", { class: "sb-fan__columns" });

  // If ANY arm of this fan carries a guard, every arm reserves the guard's
  // line. Without it an unguarded `otherwise` starts one line higher than its
  // siblings and the whole fan reads as misaligned - the reader sees a
  // layout bug where there is only an absent condition.
  const anyGuarded = node.primary.some((slot) => slot.guard);

  for (const slot of node.primary) {
    columns.append(renderColumn(node, slot, anyGuarded));
  }

  wrapper.append(columns);
  wrapper.append(
    el("div", { class: "sb-fan__marker sb-fan__marker--join" }, [
      el("span", { class: "sb-fan__label", text: "continue" }),
    ])
  );

  return wrapper;
}

function renderColumn(node, slot, reserveGuardLine = false) {
  const column = el("div", {
    class: [
      "sb-column",
      slot.children.length === 0 ? "sb-column--empty" : null,
      slot.guard ? null : "sb-column--unguarded",
    ]
      .filter(Boolean)
      .join(" "),
    "data-block-id": node.id,
    "data-slot": slot.name,
    "data-drop": slot.dropState,
  });

  const header = el("div", { class: "sb-column__header" }, [
    el("span", { class: "sb-column__label", text: slot.label }),
  ]);

  // The guard pill is where "many conditioned transitions" become readable:
  // one condition, on the arm it belongs to, in monospace, truncated with the
  // whole expression on hover. Drawing it as DOM rather than as SVG text is
  // deliberate - text along a path is unreadable and unselectable, and this
  // way the expression is copyable.
  if (slot.guard) {
    header.append(
      el("code", { class: "sb-guard", text: slot.guard, title: slot.guard })
    );
  } else if (reserveGuardLine) {
    header.append(
      // A non-breaking space, so the empty line actually has a line box to
      // take up the height; an empty span collapses and reserves nothing.
      el("span", { class: "sb-guard sb-guard--none", "aria-hidden": "true", text: " " })
    );
  }

  column.append(header);
  column.append(renderChildren(node, slot));

  return column;
}

/**
 * A secondary slot as an attached rail (ADR-0005 decision 10's
 * `slot_style: :secondary`). It sits beside the group's body rather than
 * under it, which is what makes "these rules watch that body" legible without
 * an arrow having to say so - and the exit edges then say where the rules go.
 */
function renderRail(node) {
  const rail = el("aside", { class: "sb-rail" });

  for (const slot of node.secondary) {
    const group = el("div", {
      class: "sb-rail__slot",
      "data-block-id": node.id,
      "data-slot": slot.name,
      "data-drop": slot.dropState,
    });

    group.append(
      el("div", { class: "sb-rail__header" }, [
        el("span", { class: "sb-rail__label", text: slot.label }),
      ])
    );

    if (slot.children.length === 0) {
      group.append(renderGap(node, slot, 0));
      group.append(el("div", { class: "sb-slot__empty", text: "no rules" }));
    } else {
      slot.children.forEach((child, index) => {
        group.append(renderGap(node, slot, index));
        group.append(renderNode(child));
      });
      group.append(renderGap(node, slot, slot.children.length));
    }

    rail.append(group);
  }

  return rail;
}

/* ============================================================== route */

/**
 * Pass two. Measures every anchor the emit pass left and rewrites the whole
 * edge layer. Idempotent and side-effect-free outside the `<svg>`, so calling
 * it again after a resize is always safe.
 */
function routeConnectors(stage, svg, edgeLayer) {
  const origin = stage.getBoundingClientRect();
  const width = stage.scrollWidth;
  const height = stage.scrollHeight;

  svg.setAttribute("width", String(width));
  svg.setAttribute("height", String(height));
  svg.setAttribute("viewBox", `0 0 ${width} ${height}`);

  const rect = (element) => {
    const box = element.getBoundingClientRect();
    return {
      x: box.left - origin.left,
      y: box.top - origin.top,
      width: box.width,
      height: box.height,
    };
  };

  const edges = [];

  for (const node of stage.querySelectorAll(".sb-node")) {
    collectEdges(node, rect, edges);
  }

  edgeLayer.replaceChildren(
    ...edges.map((edge) =>
      svgEl("path", {
        class: `sb-edge sb-edge--${edge.kind}`,
        d: edge.d,
        "marker-end": edge.marker,
        fill: "none",
      })
    )
  );
}

/*
 * Every edge one node contributes. Each is read off the DOM the emit pass
 * produced, which is to say off adjacency and nesting and nothing else.
 */
function collectEdges(node, rect, edges) {
  const card = child(node, ":scope > .sb-card");
  if (!card) return;

  const body = child(node, ":scope > .sb-node__body");
  const outletAnchor = child(node, ":scope > .sb-node__outlet");

  // --- 1. flow between adjacent children of one slot -------------------
  for (const list of node.querySelectorAll(":scope .sb-slot__children")) {
    if (closestNode(list) !== node) continue;

    const siblings = Array.from(list.children).filter((element) =>
      element.classList.contains("sb-node")
    );

    for (let index = 0; index + 1 < siblings.length; index += 1) {
      const from = child(siblings[index], ":scope > .sb-node__outlet");
      const to = child(siblings[index + 1], ":scope > .sb-card");
      if (!from || !to) continue;
      edges.push({
        kind: "flow",
        d: flowPath(outlet(rect(from)), inlet(rect(to))),
        marker: "url(#sb-arrow)",
      });
    }
  }

  if (!body) return;

  const fan = child(body, ":scope > .sb-node__children > .sb-fan");

  if (fan) {
    // --- 2. the fan and the rejoin ------------------------------------
    const hub = child(fan, ":scope > .sb-fan__marker--hub");
    const join = child(fan, ":scope > .sb-fan__marker--join");
    const columns = Array.from(fan.querySelectorAll(":scope > .sb-fan__columns > .sb-column"));

    const kind = node.dataset.arrangement === "lanes" ? "lane" : "fan";

    edges.push({
      kind: "flow",
      d: flowPath(outlet(rect(card)), inlet(rect(hub))),
      marker: null,
    });

    for (const column of columns) {
      // A fan edge lands on the column's HEADER, not on its first card. The
      // header carries the arm's name and its guard, so an edge that ran past
      // it to the card would cross the very condition the edge is subject to
      // - and a connector drawn over a monospace expression is the fastest
      // way to make a canvas look broken.
      const first = child(column, ":scope > .sb-column__header") ?? firstAnchorIn(column);
      const last = lastAnchorIn(column);
      if (!first || !last) continue;

      edges.push({
        kind,
        d: fanPath(outlet(rect(hub)), inlet(rect(first))),
        marker: "url(#sb-arrow)",
      });
      edges.push({
        kind,
        d: joinPath(outlet(rect(last)), inlet(rect(join))),
        marker: null,
      });
    }

    if (outletAnchor) {
      edges.push({
        kind: "flow",
        d: flowPath(outlet(rect(join)), inlet(rect(outletAnchor))),
        marker: null,
      });
    }
  } else {
    // --- 3. a container's header into the first child of its body -----
    const first = firstAnchorIn(child(body, ":scope > .sb-node__children"));
    if (first) {
      edges.push({
        kind: "flow",
        d: flowPath(outlet(rect(card)), inlet(rect(first))),
        marker: "url(#sb-arrow)",
      });
    }
  }

  // --- 4. interrupt exit edges -----------------------------------------
  const rail = child(body, ":scope > .sb-rail");
  if (!rail || !outletAnchor) return;

  const bodyRect = rect(body);
  const exitRect = rect(outletAnchor);
  // The channel sits outside the group's own box, so an exit edge has nothing
  // to cross on its way down however deep the group is nested.
  const channelX = bodyRect.x + bodyRect.width + 10;

  // Each rule gets its own lane in the channel. Two rules on one rail
  // otherwise share every pixel of their exit path, and two edges drawn
  // exactly on top of each other look like one edge - which is the opposite
  // of what a group with two ways out needs to communicate.
  let lane = 0;

  for (const rule of rail.querySelectorAll(".sb-node")) {
    if (closestNode(rule) !== node) continue;

    const ruleCard = child(rule, ":scope > .sb-card");
    if (!ruleCard) continue;

    const from = rect(ruleCard);

    edges.push({
      kind: "interrupt",
      d: interruptPath(
        { x: from.x + from.width, y: from.y + from.height / 2 },
        inlet(exitRect),
        channelX + lane * 6
      ),
      marker: "url(#sb-arrow-interrupt)",
    });

    lane += 1;
  }
}

function child(parent, selector) {
  return parent ? parent.querySelector(selector) : null;
}

/** The nearest enclosing `.sb-node`, so a walk never claims a grandchild's edges. */
function closestNode(element) {
  return element.parentElement ? element.parentElement.closest(".sb-node") : null;
}

/*
 * A column's entry and exit anchors.
 *
 * An EMPTY column still gets both, falling back to its own placeholder: an
 * arm with nothing in it yet is a real arm of the branch, and a fan that
 * silently skipped it would tell an author their empty arm does not exist.
 */
function firstAnchorIn(container) {
  if (!container) return null;
  const node = container.querySelector(".sb-node");
  if (node) return child(node, ":scope > .sb-card");
  return container.querySelector(".sb-slot__empty");
}

function lastAnchorIn(column) {
  const list = column.querySelector(":scope > .sb-slot__children");
  if (!list) return null;

  const nodes = Array.from(list.children).filter((element) =>
    element.classList.contains("sb-node")
  );
  const last = nodes[nodes.length - 1];
  if (last) return child(last, ":scope > .sb-node__outlet");

  return list.querySelector(".sb-slot__empty");
}
