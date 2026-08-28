/*
 * spike/js/datamodel-pane.js - the Datamodel tab, rendered.
 *
 * Structured like `palette-pane.js` on purpose: a pane that owns its own query
 * and its own expansion state, mounts once, and exposes a handle. Both are
 * searchable typed lists an author scans rather than edits, so they should feel
 * like one idiom - the same search row in the same place, the same
 * "n of m match" line under it, the same highlighted runs in the labels, and
 * the same empty state with a clear button.
 *
 * ## The design decisions this pane is making
 *
 * There is no accepted record for a datamodel document (see `datamodel.js`), so
 * every question below was answered here for the first time. Each one is
 * written at the point it is made and collected in the bead note.
 *
 *   1. **A scope is a section with a lifetime, not a folder.** The header says
 *      what writes the values and when they exist - "the same for every run",
 *      "one per run" - because that is the fact that decides which of two
 *      identically named paths an author wants. Sections do not collapse away
 *      to a single line; the scope chrome is the thing that has to stay on
 *      screen.
 *   2. **The `event.` prefix is stated on the scope, not on every row.** It is
 *      how the scope is ADDRESSED, and repeating it thirty times would turn the
 *      one structural fact about that scope into visual noise. The rows still
 *      carry their full path in the copy affordance, so nothing is lost.
 *   3. **An example is shown as a value, quoted the way it would be written.**
 *      Not "e.g." prose. The example is there so an author can see the SHAPE
 *      they are comparing against - `"USD"` vs `USD` is the difference between
 *      a condition that works and one that does not - and quoting is what
 *      carries that.
 *   4. **`one_of` is the closed set spelled out, not a count.** Three chips is
 *      the whole answer; "3 values" is a promise to go look somewhere else.
 *   5. **A list of objects is not rendered as a sub-tree.** The fixture has no
 *      such entry and the honest reason is that a list-of-object needs an index
 *      or a wildcard in the path before a row means anything, and the spike has
 *      no evidence for which. The type chip reads "list of string" and stops -
 *      see the bead note, this is the open question the pane found.
 */

import { ancestorPaths, datamodelView, exampleText, typeLabel } from "./datamodel.js";
import { el } from "./render.js";

/**
 * Mounts the datamodel tree into `mount` and returns a handle.
 *
 *     { redraw(), reveal(path), expandAll(), collapseAll(), query }
 *
 * `onPick` is called with a path when a row's name is activated, so a caller
 * can route a selection somewhere else; the pane does nothing with it itself.
 */
export function createDatamodelPane({ mount, doc, onPick = () => {} }) {
  let query = "";
  const expanded = new Set();

  const search = el("input", {
    class: "sb-input sb-datamodel__search",
    type: "search",
    placeholder: "Search paths, labels, types",
    "aria-label": "Search the datamodel",
    "aria-controls": "sb-datamodel-results",
  });

  const count = el("p", { class: "sb-palette__count", role: "status" });
  const results = el("div", { class: "sb-datamodel__results", id: "sb-datamodel-results" });

  const expandButton = el("button", {
    class: "sb-button sb-button--quiet sb-datamodel__toggle-all",
    type: "button",
    text: "Expand all",
  });

  const collapseButton = el("button", {
    class: "sb-button sb-button--quiet sb-datamodel__toggle-all",
    type: "button",
    text: "Collapse all",
  });

  expandButton.addEventListener("click", () => expandAll());
  collapseButton.addEventListener("click", () => collapseAll());

  /*
   * The search row and the controls stick together, as ONE header. Sticking
   * only the input - which is what reusing the palette's search row alone did
   * - leaves the count and the expand buttons to scroll away, and the gap they
   * leave above the sticky input shows scrolled rows through it. A header that
   * is half stuck looks like a rendering bug, which is worse than one that
   * does not stick at all.
   */
  mount.replaceChildren(
    el("div", { class: "sb-datamodel__head" }, [
      el("div", { class: "sb-datamodel__search-row" }, [search]),
      el("div", { class: "sb-datamodel__controls" }, [count, expandButton, collapseButton]),
    ]),
    results
  );

  /*
   * A filter expands what it found. Leaving the matches folded inside collapsed
   * objects would make a search that says "4 of 71 match" show four closed
   * folders, which is the least useful possible answer - the author searched
   * for `verdict`, and `fraud` is not what they asked to see.
   */
  function draw() {
    const view = datamodelView(doc, query);

    count.textContent =
      view.query === ""
        ? `${view.total} entr${view.total === 1 ? "y" : "ies"} in ${view.scopes.length} scopes`
        : `${view.matched} of ${view.total} match “${view.query}”`;
    count.dataset.filtering = String(view.query !== "");

    const forced = view.query === "" ? null : new Set();
    if (forced) collectContainers(view, forced);

    results.replaceChildren(
      ...view.scopes.map((scope) => scopeElement(scope, forced)),
      ...(view.empty ? [emptyState(view)] : [])
    );
  }

  function isOpen(path, forced) {
    return forced ? forced.has(path) : expanded.has(path);
  }

  function scopeElement(scope, forced) {
    const section = el("section", { class: "sb-datamodel__scope", "data-scope": scope.scope });

    const head = el("header", { class: "sb-datamodel__scope-head" }, [
      el("h4", { class: "sb-datamodel__scope-name" }, [
        el("span", { text: scope.label }),
        scope.prefix
          ? el("code", { class: "sb-datamodel__prefix", text: scope.prefix, title: "how this scope is addressed in a condition" })
          : null,
      ]),
      el("span", {
        class: "sb-datamodel__scope-count",
        text: scope.matched === scope.total ? String(scope.total) : `${scope.matched}/${scope.total}`,
      }),
    ]);

    section.append(
      head,
      el("p", { class: "sb-datamodel__scope-note", text: scope.description })
    );

    if (scope.nodes.length === 0) {
      section.append(
        el("p", { class: "sb-datamodel__none", text: "Nothing in this scope matches." })
      );
      return section;
    }

    section.append(
      el("ul", { class: "sb-datamodel__list" }, scope.nodes.map((node) => nodeElement(node, forced)))
    );

    return section;
  }

  function nodeElement(node, forced) {
    const open = node.container && isOpen(node.path, forced);

    const item = el("li", {
      class: "sb-datamodel__item",
      "data-path": node.path,
      "data-depth": String(node.depth),
      "data-type": node.type,
    });

    const row = el("div", { class: "sb-datamodel__row" });
    if (node.matched) row.dataset.matched = "true";

    // The twisty is a real button on a container and a spacer on a leaf, so
    // every row's name starts on the same x - a tree whose leaves and folders
    // sit at different indents reads as two lists.
    if (node.container) {
      const twisty = el("button", {
        class: "sb-datamodel__twisty",
        type: "button",
        "aria-expanded": String(open),
        "aria-label": `${open ? "Collapse" : "Expand"} ${node.label}`,
        text: open ? "▾" : "▸",
      });

      twisty.addEventListener("click", () => {
        if (expanded.has(node.path)) expanded.delete(node.path);
        else expanded.add(node.path);
        // A click while a filter is running is an explicit override of the
        // filter's auto-expansion, so it drops the query rather than being
        // silently ignored on the next keystroke.
        if (query !== "") {
          search.value = "";
          query = "";
        }
        draw();
      });

      row.append(twisty);
    } else {
      row.append(el("span", { class: "sb-datamodel__twisty sb-datamodel__twisty--leaf" }));
    }

    /*
     * Two lines, not four columns. The first iteration put the label, the
     * name, the type and the example on one row and the pane is 21rem wide:
     * every example clipped and every two-word label wrapped, which made a
     * tidy tree look like a broken table. So the identity line carries what an
     * author has to type and its type, and the gloss line carries the sentence
     * and the example - each with the whole width to itself.
     */
    const name = el("button", {
      class: "sb-datamodel__name",
      type: "button",
      title: node.path,
    });

    appendSegments(name, node.nameSegments);
    name.addEventListener("click", () => onPick(node.path));

    row.append(
      name,
      el("span", { class: "sb-datamodel__type", "data-type": node.type, text: typeLabel(node) })
    );

    item.append(row);

    const example = exampleText(node);
    const gloss = el("div", { class: "sb-datamodel__gloss" });

    // The label is dropped when it is only the name in title case - "Card" over
    // `card` is a row of noise, and the gloss line should earn its height.
    if (!echoes(node.label, node.name)) {
      const label = el("span", { class: "sb-datamodel__label" });
      appendSegments(label, node.labelSegments);
      gloss.append(label);
    }

    if (example !== null) {
      gloss.append(el("code", { class: "sb-datamodel__example", text: example }));
    }

    if (gloss.childNodes.length > 0) item.append(gloss);

    if (node.oneOf) {
      item.append(
        el(
          "div",
          { class: "sb-datamodel__one-of" },
          node.oneOf.map((value) =>
            el("code", {
              class: "sb-datamodel__one-of-value",
              text: value === "" ? '""' : value,
            })
          )
        )
      );
    }

    if (node.note) {
      item.append(el("p", { class: "sb-datamodel__note", text: node.note }));
    }

    if (node.container && open) {
      item.append(
        el(
          "ul",
          { class: "sb-datamodel__list sb-datamodel__list--nested" },
          node.children.map((child) => nodeElement(child, forced))
        )
      );
    }

    return item;
  }

  function emptyState(view) {
    const clear = el("button", {
      class: "sb-button sb-palette__clear",
      type: "button",
      text: "Clear search",
    });

    clear.addEventListener("click", () => {
      search.value = "";
      query = "";
      draw();
      search.focus();
    });

    return el("div", { class: "sb-palette__empty" }, [
      el("p", {
        class: "sb-palette__empty-title",
        text: `No datamodel entry matches “${view.query}”.`,
      }),
      el("p", {
        class: "sb-palette__empty-body",
        text: "Search matches an entry's name, its label, its full path, and its type.",
      }),
      clear,
    ]);
  }

  function expandAll() {
    const view = datamodelView(doc, "");
    collectContainers(view, expanded);
    draw();
  }

  function collapseAll() {
    expanded.clear();
    draw();
  }

  /*
   * Reveal, the mirror of `interact.js`'s finding reveal and for the same
   * reason: a cross-pane jump that lands on something still folded is worse
   * than no jump at all. Unfold every ancestor, unfold the target when it is a
   * container, drop any filter that would hide it, then scroll and flash.
   *
   * Returns false when the path is not in the datamodel - which is the whole
   * point of the advisory treatment in the condition pane, and the case the
   * caller has to be able to say something about.
   */
  function reveal(path) {
    if (query !== "") {
      search.value = "";
      query = "";
    }

    for (const ancestor of ancestorPaths(path)) expanded.add(ancestor);
    expanded.add(path);
    draw();

    const item = Array.from(results.querySelectorAll("[data-path]")).find(
      (one) => one.dataset.path === path
    );

    if (!item) return false;

    item.scrollIntoView({ block: "center", behavior: "smooth" });

    const row = item.querySelector(".sb-datamodel__row") ?? item;
    row.classList.remove("sb-flash");
    void row.offsetWidth;
    row.classList.add("sb-flash");
    row.addEventListener("animationend", () => row.classList.remove("sb-flash"), { once: true });

    return true;
  }

  /*
   * Typing scrolls back to the top. Without it a filter run after a reveal
   * leaves the pane parked wherever the reveal left it, so the first scope's
   * matches are above the fold and the count says three while one is visible -
   * which reads as the filter having missed them.
   */
  search.addEventListener("input", () => {
    query = search.value;
    draw();

    const scroller = scrollParent(mount);
    if (scroller) scroller.scrollTop = 0;
  });

  // Nothing is expanded on load. Three fully open scopes is seventy rows,
  // which is a wall rather than a tree; the top level is twenty-four and reads
  // as a map of the chart's vocabulary, which is what an author opening this
  // tab is actually asking for. "Expand all" is one click away for the times
  // it is not.
  draw();

  return {
    get query() {
      return query;
    },
    redraw: draw,
    reveal,
    expandAll,
    collapseAll,
    focusSearch: () => search.focus(),
  };
}

/* The nearest ancestor that actually scrolls. Found rather than named, so the
 * pane does not have to know which of the shell's containers is the scroller -
 * it is mounted into a tab panel here and could be mounted anywhere. */
function scrollParent(node) {
  for (let at = node.parentElement; at; at = at.parentElement) {
    const overflow = getComputedStyle(at).overflowY;
    if ((overflow === "auto" || overflow === "scroll") && at.scrollHeight > at.clientHeight) {
      return at;
    }
  }

  return null;
}

/* Highlighted runs as elements. Data in, elements out - a renderer that built
 * markup from a query string is the one habit this spike must not teach. */
function appendSegments(into, segments) {
  for (const segment of segments) {
    into.append(
      segment.match
        ? el("mark", { class: "sb-palette__match", text: segment.text })
        : document.createTextNode(segment.text)
    );
  }

  return into;
}

/* "Card" over `card`, "Merchant id" over `id`: a label that is only its name
 * re-cased says nothing the row above it did not. */
const echoes = (label, name) =>
  String(label).toLowerCase().replace(/[\s_]+/g, "") ===
  String(name).toLowerCase().replace(/[\s_]+/g, "");

/** Every container path in a view - what "expand all" and a filter both want. */
function collectContainers(view, into) {
  const visit = (nodes) => {
    for (const node of nodes) {
      if (node.container) into.add(node.path);
      visit(node.children);
    }
  };

  for (const scope of view.scopes) visit(scope.nodes);

  return into;
}
