/*
 * spike/js/table-drawer.js - the truth tables, in a bottom drawer (sb-054).
 *
 * The DOM half of `drawerView`. Same split the rest of the spike takes:
 * `fixtures.js` decides which tables a state shows and what each one flattens
 * to, this file turns that into elements.
 *
 * ## Why the tables left the inspector
 *
 * They were the Fixtures pane's middle sub-view, and the pane wrote down what
 * was wrong with that in three places before anyone filed it: the inspector is
 * `--sb-inspector-width` (21rem), a truth table is a bindings column per
 * referenced path plus one column per arm, and the two do not reconcile. The
 * pane's answers were to scroll the grid sideways, to invert the conventional
 * column order so the verdicts were the part on screen, and to say in a
 * sentence under the table that the values were off to the right. Three
 * workarounds for one missing 40rem.
 *
 * The operator's ruling is a BOTTOM DRAWER, over keeping it in the inspector
 * until the shipped editor graduates the pattern. A drawer is the full width
 * of the shell, which is the axis a truth table actually needs, and it is the
 * axis the inspector can never give it however the panes are tuned.
 *
 * ## What the drawer does not do
 *
 * It does not own a selection. The tables it shows are the SELECTED block's,
 * and it follows the canvas: selecting another guarded block re-draws it in
 * place. A drawer that pinned its own subject would be a second cursor in the
 * editor, and an author who selected a block and saw the drawer keep showing
 * a different one would be right to call it broken.
 *
 * It is also not a tab panel and not a pane. It has no `role="tab"` anywhere
 * near it, deliberately: `shell.js` selects the inspector's tab strip with
 * `document.querySelectorAll('[role="tab"]')`, and anything wearing that role
 * outside the strip is adopted by it. The drawer is a `<section>`, and its
 * state is one boolean.
 *
 * ## The collapsed strip (sb-3l1, ruling 5A)
 *
 * The drawer used to be open-or-gone: `hidden` when closed, and the only way
 * to open it was the Condition pane's per-block button, which a block owning
 * no table does not render. So the cold start was unreachable - an author who
 * had not already selected a block that owns a table had no way in, and no
 * way to discover which blocks did.
 *
 * Closed is now a STRIP carrying the noun and a count ("Truth tables 3"),
 * present whenever a document is open, count and all, even at zero. Pressing
 * it opens the drawer on the current selection; when that block owns no
 * table the drawer comes up on the miss-state list, which IS its index page -
 * every block in the document that does own one, each a press away.
 */

import { drawerStripView, drawerView, tablesForBlock } from "./fixtures.js";
import { el } from "./render.js";

/**
 * Mounts the truth-table drawer and returns a handle.
 *
 *     root    the drawer `<section>` - hidden entirely only when no document
 *             is open; otherwise either collapsed to its strip or expanded
 *     mount   the element inside it the tables render into
 *     title   the element carrying the drawer's heading text
 *     close   the drawer's close button, or null
 *     strip   the collapsed strip's button, or null
 *     stripLabel / stripCount  the two spans inside that button, or null
 *     host    { fixtures(), selectedId(), labelFor(id), revealBlock(id),
 *               announce(message) }
 *
 * Every `host` member is optional in the sense that the drawer degrades rather
 * than throws: it is mounted before a document is open and it is useful in a
 * bare test page with no canvas at all.
 */
export function createTableDrawer({
  root,
  mount,
  title = null,
  close = null,
  strip = null,
  stripLabel = null,
  stripCount = null,
  host = {},
}) {
  let open = false;

  function state() {
    return drawerView({
      open,
      fixtures: host.fixtures?.() ?? null,
      selectedId: host.selectedId?.() ?? null,
    });
  }

  function stripState() {
    return drawerStripView({ fixtures: host.fixtures?.() ?? null, open });
  }

  function draw() {
    const view = state();
    const bar = stripState();

    /*
     * Three states, not two (sb-3l1). `hidden` is now reserved for "there is
     * no document", which is the only case with nothing to say; a document
     * with no tables still gets a strip reading 0, because a strip that
     * vanishes when the count is zero is a cold start that cannot be found.
     */
    root.hidden = !bar.present;
    root.dataset.collapsed = String(!view.open);

    if (strip) {
      strip.setAttribute("aria-expanded", String(bar.expanded));
      strip.title = view.open ? "Collapse the truth tables" : "Open the truth tables";
    }
    if (stripLabel) stripLabel.textContent = bar.label;
    if (stripCount) stripCount.textContent = String(bar.count);

    if (title) title.textContent = view.title;

    // Nothing is rendered into a closed drawer. `hidden` already keeps it off
    // screen and out of the accessibility tree; leaving a stale grid mounted
    // under it would also leave every cell of it in the DOM for a find-in-page
    // to land on, which is the reading of "hidden" a browser does not take.
    if (!view.open) {
      mount.replaceChildren();
      return;
    }

    mount.replaceChildren(...bodyElements(view));
  }

  function bodyElements(view) {
    if (view.status === "ready") {
      return [
        el("p", {
          class: "sb-hint",
          text: `Precomputed truth tables for ${host.labelFor?.(view.subjectId) ?? view.subjectId}. Every expected value is fixture data - the drawer renders them, it does not evaluate the expressions beside them.`,
        }),
        ...view.tables.map(tableElement),
      ];
    }

    return emptyElements(view);
  }

  /*
   * The four miss states, each said in its own words. They were one sentence
   * with a ternary in the pane, and the ternary could not tell "no document is
   * open" from "this document has no fixtures" - so a freshly loaded page said
   * "no truth table is written for this block" about a block that did not
   * exist. `drawerView` splits them; this reads the split back out.
   */
  function emptyElements(view) {
    const said = {
      "no-document": "Load a document to see the condition fixtures written for it.",
      "no-fixtures":
        "Nothing in the fixture file mentions this document. A document with no fixtures is not a failing document - it is one nobody has written a table for yet.",
      "no-selection": "Select a guarded block to see the condition fixtures written for it.",
      "none-for-block":
        "No truth table is written for this block. The blocks in this document that do have one are listed below.",
    };

    const out = [el("p", { class: "sb-empty", text: said[view.status] ?? said["no-selection"] })];

    if (view.jumps.length === 0) {
      if (view.status !== "no-document") {
        out.push(
          el("p", {
            class: "sb-hint",
            text: "This document has no condition fixtures at all. Tables live on branch arms and on guarded interrupt rules.",
          })
        );
      }

      return out;
    }

    /*
     * The empty state's second job, kept from the pane: an author who selected
     * the wrong block needs to know which blocks DO have tables, and a list of
     * them that selects and reveals on click is worth more than a sentence
     * telling them to go looking.
     */
    out.push(
      el("p", {
        class: "sb-hint",
        text: `${view.jumps.length} block${view.jumps.length === 1 ? " has" : "s have"} a table in this document:`,
      })
    );

    const list = el("ul", { class: "sb-fixtures__table-jumps" });
    const fixtures = host.fixtures?.() ?? null;

    for (const id of view.jumps) {
      const mine = fixtures ? tablesForBlock(fixtures, id) : [];

      // The TABLE's name, not the block's. A branch and an interrupt rule
      // carry no `label` in their config, so the block label falls back to the
      // palette entry - and a list reading "Branch", "On event, when",
      // "Branch" tells an author nothing about which one they want.
      const button = el("button", {
        class: "sb-fixtures__table-jump",
        type: "button",
        title: `${id} · select and reveal`,
      });

      button.append(
        el("span", { class: "sb-fixtures__table-jump-name" }, [
          el("span", {
            text: mine.length === 1 ? (mine[0].name ?? id) : `${mine.length} tables`,
          }),
          el("span", {
            class: "sb-fixtures__table-jump-block",
            text: host.labelFor?.(id) ?? id,
          }),
        ]),
        el("span", { class: "sb-fixtures__table-jump-count", text: "reveal" })
      );

      button.addEventListener("click", () => {
        host.revealBlock?.(id);
        draw();
      });

      list.append(el("li", {}, [button]));
    }

    out.push(list);

    return out;
  }

  /*
   * The table itself, transplanted from the Fixtures pane unchanged except for
   * the sentence under it, which used to apologise for the width.
   *
   * sb-3l1 / ruling 4A: "the truth-table grid orders Case, inputs, then
   * verdicts, the verdict block separated by a heavier left rule".
   *
   * The Fixtures pane put the verdicts BEFORE the bound values because in a
   * 21rem inspector the conventional order pushed every answer off the right
   * edge. The drawer took the width constraint away and sb-054 deliberately
   * left the inversion in place, as its own readability bead - this one. A
   * truth table is read left to right as "given these inputs, this verdict",
   * so the inputs go first and the verdict block is what the eye lands on
   * last, marked off by the heavier rule rather than by a colour.
   *
   * The per-arm "n/6 true" summaries stay ABOVE the grid, where 4A keeps
   * them: they are about a column across all rows, which is not something a
   * row-shaped footer can say.
   */
  function tableElement(table) {
    const box = el("section", { class: "sb-fixtures__table", "data-table-id": table.id });

    box.append(
      el("header", { class: "sb-fixtures__table-head" }, [
        el("h4", { class: "sb-fixtures__table-name", text: table.name }),
        el("p", { class: "sb-fixtures__table-description", text: table.description }),
      ])
    );

    box.append(
      el(
        "ul",
        { class: "sb-fixtures__exprs" },
        table.columns.map((column, index) =>
          el("li", { class: "sb-fixtures__expr" }, [
            el("span", { class: "sb-fixtures__expr-label", text: column.label }),
            el("code", { class: "sb-code sb-fixtures__expr-source", text: column.expr }),
            el("span", {
              class: "sb-fixtures__expr-count",
              text: `${table.trueCounts[index]}/${table.rows.length} true`,
            }),
          ])
        )
      )
    );

    const scroller = el("div", { class: "sb-fixtures__table-scroll" });
    const grid = el("table", { class: "sb-fixtures__grid" });

    const head = el("tr", {}, [
      el("th", { class: "sb-fixtures__grid-corner", scope: "col", text: "Case" }),
      ...table.paths.map((path) =>
        el("th", {
          class: "sb-fixtures__grid-path",
          scope: "col",
          title: path,
          text: path,
        })
      ),
      ...table.columns.map((column, index) =>
        el("th", {
          class: "sb-fixtures__grid-arm",
          scope: "col",
          // The seam between the values and the answers they produce, marked
          // in the markup because both families are cells and CSS cannot tell
          // them apart by position. It sits on the FIRST VERDICT column, which
          // is where the heavier rule belongs now that the verdicts come last.
          "data-column": index === 0 ? "first-arm" : null,
          title: column.expr,
          text: column.label,
        })
      ),
    ]);

    grid.append(el("thead", {}, [head]));

    const rows = el("tbody", {});

    for (const row of table.rows) {
      const tr = el("tr", { class: "sb-fixtures__grid-row" });

      const name = el("th", { class: "sb-fixtures__grid-name", scope: "row" }, [
        el("span", { text: row.name }),
      ]);

      if (row.note) name.append(el("span", { class: "sb-fixtures__grid-note-mark", text: "*" }));

      tr.append(
        name,
        ...row.bindings.map((binding) =>
          el("td", { class: "sb-fixtures__grid-binding" }, [
            el("code", { text: String(binding.value) }),
          ])
        ),
        ...row.cells.map((cell, index) =>
          el(
            "td",
            {
              class: "sb-fixtures__grid-cell",
              "data-column": index === 0 ? "first-arm" : null,
            },
            [
              el("span", {
                class: "sb-fixtures__bool",
                "data-value": cell.expected === null ? "unset" : String(cell.expected),
                text: cell.expected === null ? "–" : cell.expected ? "true" : "false",
              }),
            ]
          )
        )
      );

      rows.append(tr);
    }

    grid.append(rows);
    scroller.append(grid);

    box.append(
      scroller,
      el("p", {
        class: "sb-hint",
        text: `Bound values: ${table.paths.join(", ")}. Every cell is fixture data.`,
      })
    );

    const notes = table.rows.filter((row) => row.note);

    if (notes.length > 0) {
      box.append(
        el(
          "ul",
          { class: "sb-fixtures__table-notes" },
          notes.map((row) =>
            el("li", { class: "sb-fixtures__table-note" }, [
              el("span", { class: "sb-fixtures__table-note-name", text: row.name }),
              el("span", { text: row.note }),
            ])
          )
        )
      );
    }

    return box;
  }

  if (close) {
    close.addEventListener("click", () => setOpen(false));
  }

  // The strip is the cold-start affordance (5A): it toggles, so the same
  // control an author found the drawer with is the one that puts it away.
  if (strip) {
    strip.addEventListener("click", () => setOpen(!open));
  }

  function setOpen(next) {
    if (open === next) return;
    open = next;
    draw();
  }

  draw();

  return {
    /** Opens the drawer. `blockId` is revealed first when it is not already
     * the selection, so the affordance that opened it and the table that comes
     * up are about the same block. */
    open(blockId = null) {
      if (blockId !== null && blockId !== (host.selectedId?.() ?? null)) {
        host.revealBlock?.(blockId);
      }

      setOpen(true);
      host.announce?.("Truth table drawer opened.");
    },
    close() {
      setOpen(false);
      host.announce?.("Truth table drawer closed.");
    },
    isOpen: () => open,
    redraw: draw,
    /** Called by the shell when the canvas selection moves. */
    selectionChanged() {
      if (open) draw();
    },
    /** Called when a document loads: the drawer closes rather than carrying a
     * table from the last document across the switch. */
    documentChanged() {
      open = false;
      draw();
    },
    /** Called when the Fixtures pane applies or reverts edited fixture JSON -
     * the tables on screen came from the copy that just changed. Unconditional
     * since sb-3l1: the collapsed strip carries a COUNT off the same copy, so
     * a redraw only while open would leave a stale number on screen in the
     * state the drawer spends most of its life in. */
    fixturesChanged() {
      draw();
    },
    /** The drawer's state, for a test page and for the shell's own asserts. */
    state,
  };
}
