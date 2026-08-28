/*
 * spike/js/fixtures-pane.js - the Fixtures tab, rendered.
 *
 * The DOM half of sb-9z3. `fixtures.js` decides what a run at a cursor IS and
 * what a truth table flattens to; this file turns those values into elements
 * and the resulting gestures back into calls on the editor. Same split as
 * `datamodel-pane.js`: the pane owns its own view state - which run is open,
 * where the cursor is, which sub-view is showing, the unapplied editor text -
 * and nothing else.
 *
 * ## What this pane is allowed to claim
 *
 * The campaign's D4 ruling makes every number here fixture data. A run is a
 * script someone wrote, a check's pass or fail is a value in the file, and a
 * truth table's cells are typed in. Nothing is interpreted and nothing is
 * evaluated. That is stated ON SCREEN rather than only in a comment, because a
 * green "pass" chip beside a step list is exactly the shape of a UI that has
 * just run something, and an author who believes this pane executed their chart
 * would be wrong in a way that costs them a production incident. Every view
 * carries the word "replay" or "recorded" where a reader will meet it.
 *
 * ## Three sub-views, and why they are not a tab strip
 *
 * Runs, Tables and JSON are three whole surfaces rather than three stacked
 * sections: the pane is 21rem wide and a step list plus a truth table plus a
 * textarea stacked would be a scroll with no map. They are buttons with
 * `aria-pressed`, NOT `role="tab"` - `shell.js` selects the inspector's tab
 * strip with `document.querySelectorAll('[role="tab"]')`, so a nested tablist
 * would be adopted by it and the inspector's own tabs would start hiding this
 * pane's panels. Worth knowing before someone "fixes" the ARIA here.
 *
 * ## The transport and the canvas
 *
 * The current step's blocks are marked on the canvas through the editor
 * (`markActive`), never by this pane writing classes: a command rebuilds the
 * canvas and anything painted from outside would vanish on the next undo. The
 * reveal is separate from the mark and only fires on a deliberate gesture -
 * auto-scrolling the canvas on every "step forward" fights an author who has
 * parked the viewport somewhere on purpose.
 *
 * ## The one exception to that rule, and its price (sb-ig4)
 *
 * The invoke mark - the badge highlight on the card a step is calling out to -
 * IS written from here, by `paintInvoke` below. There is no `markInvoking` on
 * the host seam to route it through, and adding one reaches into files another
 * bead owns this week, so the pane paints the class itself.
 *
 * The price is exactly the one the paragraph above names: a canvas rebuild
 * drops the mark, because it is not part of the editor's own re-render. That
 * is survivable here and would not be for the active highlight, for one
 * reason - the mark is repainted on EVERY `draw`, and every gesture that moves
 * the replay goes through `draw`. What it cannot survive is a rebuild that no
 * `draw` follows, which is an author editing the document mid-replay. The mark
 * comes back on their next transport press.
 *
 * Promoting this to a host member alongside `markActive` is the right shape
 * and is a Phase-B note, not something to do from inside this file.
 */

import {
  NOT_STARTED,
  endCursor,
  fixturesFor,
  fixturesText,
  moveCursor,
  parseFixtures,
  resetCursor,
  runById,
  runSummary,
  runView,
  tableBlockIds,
  tableView,
  tablesForBlock,
} from "./fixtures.js";
import { el } from "./render.js";

/** How long the "Play" transport waits between steps. */
const PLAY_INTERVAL_MS = 900;

/** The class the invoke mark writes onto a card. See the header comment. */
const INVOKE_MARK = "sb-card--invoking";

/*
 * The invoke mark, painted onto the canvas card the current step is calling
 * out to and cleared everywhere else. `null` clears it entirely.
 *
 * Cards are walked and compared rather than selected by id: a block id is
 * author-controlled text, and building a selector out of it needs escaping
 * that is one forgotten call away from a silent no-op. One pass over the cards
 * costs nothing at spike sizes and cannot be got wrong that way.
 *
 * A page with no canvas mounted is not a special case: `querySelectorAll`
 * finds no cards, the loop does nothing, and the pane renders its runner
 * exactly as it does with one. The `document` guard is for a non-browser
 * caller reaching the module at all.
 */
function paintInvoke(invoke) {
  if (typeof document === "undefined") return;

  const target = invoke === null ? null : invoke.block;

  for (const card of document.querySelectorAll(".sb-card")) {
    if (target !== null && card.dataset.blockId === target) {
      card.classList.add(INVOKE_MARK);
      card.dataset.invokeOutcome = invoke.outcome;
    } else if (card.classList.contains(INVOKE_MARK)) {
      card.classList.remove(INVOKE_MARK);
      delete card.dataset.invokeOutcome;
    }
  }
}

const VERDICT_LABELS = {
  "not-run": "not run",
  running: "replaying",
  failing: "a check failed",
  pass: "passed",
  fail: "failed",
};

/**
 * Mounts the Fixtures pane and returns a handle.
 *
 *     mount   the element to render into
 *     data    the parsed fixture file, or null when it could not be fetched
 *     host    { documentId(), selectedId(), markActive(ids), revealBlocks(ids),
 *               revealBlock(id), labelFor(id) }
 *
 * Every `host` member is optional in the sense that the pane degrades rather
 * than throws - it is mounted by the shell before a document is open, and it is
 * useful in a bare test page with no canvas at all.
 */
export function createFixturesPane({ mount, data, host = {} }) {
  /*
   * The applied fixture data is the pane's own copy, and edits replace it here
   * and nowhere else (deliverable 4: "applied edits live only in memory,
   * documents on disk untouched"). The fetched original is kept so Revert has
   * something to go back to that is not merely the last thing that parsed.
   */
  const original = data;
  let applied = data;

  let view = "runs";
  let openRunId = null;
  let cursor = NOT_STARTED;
  let playing = null;
  let editorText = null;
  let editorError = null;
  let notice = null;

  const body = el("div", { class: "sb-fixtures__body" });
  const nav = el("div", { class: "sb-fixtures__nav", role: "group", "aria-label": "Fixture views" });

  const buttons = [
    ["runs", "Runs"],
    ["tables", "Tables"],
    ["json", "JSON"],
  ].map(([key, label]) => {
    const button = el("button", {
      class: "sb-fixtures__nav-button",
      type: "button",
      "data-view": key,
      text: label,
    });

    button.addEventListener("click", () => {
      view = key;
      draw();
    });

    return button;
  });

  nav.append(...buttons);
  mount.replaceChildren(nav, body);

  /*
   * The run as the APPLIED data currently holds it, looked up fresh rather than
   * closed over. An Apply between two presses of "step forward" replaces the
   * whole fixture set, and a transport holding the run it was rendered from
   * would go on stepping through a document nobody can see any more.
   */
  const liveRun = (id) =>
    runById(fixturesFor(applied, host.documentId?.() ?? null), id) ?? { steps: [] };

  /* ------------------------------------------------------------- drawing */

  function draw() {
    // Cleared up front and re-painted by `runnerElement` if the draw lands on
    // a step that carries a call. Every path out of `draw` therefore leaves
    // the mark correct, including the two early returns below and every
    // sub-view that is not the runner.
    paintInvoke(null);

    for (const button of buttons) {
      button.setAttribute("aria-pressed", String(button.dataset.view === view));
    }

    const documentId = host.documentId?.() ?? null;

    if (applied === null) {
      body.replaceChildren(
        el("p", {
          class: "sb-empty",
          text: "The fixture file could not be loaded, so there are no runs or tables to show.",
        })
      );
      return;
    }

    if (documentId === null) {
      body.replaceChildren(
        el("p", { class: "sb-empty", text: "Load a document to see the fixtures written for it." })
      );
      return;
    }

    const fixtures = fixturesFor(applied, documentId);

    body.replaceChildren(
      ...(notice ? [noticeElement()] : []),
      ...(view === "runs"
        ? runsView(fixtures, documentId)
        : view === "tables"
          ? tablesView(fixtures)
          : jsonView())
    );

    updateCounts(fixtures);
  }

  function updateCounts(fixtures) {
    const counts = { runs: fixtures.runs.length, tables: fixtures.tables.length, json: null };

    for (const button of buttons) {
      const count = counts[button.dataset.view];
      button.dataset.count = count === null ? "" : String(count);
    }
  }

  function noticeElement() {
    const box = el("p", { class: "sb-fixtures__notice", role: "status", text: notice });
    // One gesture, one notice. Left standing it would read as being about
    // whatever the author did next.
    notice = null;
    return box;
  }

  /* ============================================================== the runs */

  function runsView(fixtures, documentId) {
    if (!fixtures.known) {
      return [
        el("p", {
          class: "sb-empty",
          text: `Nothing in the fixture file mentions ${documentId}. A document with no fixtures is not a failing document - it is one nobody has written a run for yet.`,
        }),
        el("p", {
          class: "sb-hint",
          text: "Add a section under `documents` in the JSON view to start one.",
        }),
      ];
    }

    if (fixtures.runs.length === 0) {
      return [
        el("p", {
          class: "sb-empty",
          text: "This document has a fixture section, but no runs in it yet.",
        }),
      ];
    }

    const open = openRunId === null ? null : runById(fixtures, openRunId);

    return open === null ? [runList(fixtures)] : runnerElement(open);
  }

  function runList(fixtures) {
    const list = el("ul", { class: "sb-fixtures__runs" });

    for (const run of fixtures.runs) {
      const summary = runSummary(run);

      const button = el("button", {
        class: "sb-fixtures__run",
        type: "button",
        "data-run-id": summary.id,
      });

      // The declared expectation rides on the meta line rather than in a chip.
      // Four rows all carrying an identical "expects pass" pill is four pills
      // of noise; on the meta line it is one word, and the row that says
      // "expects fail" stands out for being different rather than for being
      // coloured.
      button.append(
        el("span", { class: "sb-fixtures__run-head" }, [
          el("span", { class: "sb-fixtures__run-name", text: summary.name }),
        ]),
        el("span", { class: "sb-fixtures__run-description", text: summary.description }),
        el("span", { class: "sb-fixtures__run-meta" }, [
          // The host-call count only when there is one. A "0 host calls" on
          // every other row is the count badge mistake in text form.
          el("span", {
            text:
              `${summary.stepCount} steps · ${summary.checkCount} checks · ` +
              (summary.invokeCount > 0
                ? `${summary.invokeCount} host call${summary.invokeCount === 1 ? "" : "s"} · `
                : ""),
          }),
          el("span", {
            class: "sb-fixtures__expect",
            "data-expected": summary.expected,
            text: summary.expected === "pass" ? "expects pass" : "expects fail",
          }),
        ])
      );

      button.addEventListener("click", () => openRun(summary.id));
      list.append(el("li", {}, [button]));
    }

    return el("div", { class: "sb-fixtures__section" }, [
      el("p", {
        class: "sb-hint",
        text: "Recorded runs. Opening one steps through a scripted sequence and lights its blocks on the canvas; nothing here executes the chart.",
      }),
      list,
    ]);
  }

  function openRun(id) {
    openRunId = id;
    cursor = NOT_STARTED;
    stopPlaying();
    host.markActive?.([]);
    draw();
  }

  function closeRun() {
    openRunId = null;
    stopPlaying();
    host.markActive?.([]);
    draw();
  }

  /* --------------------------------------------------------- the runner */

  function runnerElement(run) {
    const state = runView(run, cursor);

    host.markActive?.(state.activeIds);
    // After `markActive` rather than before. The two marks are independent -
    // the editor's sets `data-run-active`, this one sets a class and
    // `data-invoke-outcome` - but the editor is the one allowed to rebuild the
    // canvas, so the pane's paint goes last and reads whatever cards exist
    // when it runs.
    paintInvoke(state.invoke);

    const back = el("button", {
      class: "sb-button sb-button--quiet sb-fixtures__back",
      type: "button",
      text: "← All runs",
    });
    back.addEventListener("click", closeRun);

    return [
      el("div", { class: "sb-fixtures__runner-head" }, [
        back,
        el("h4", { class: "sb-fixtures__runner-name", text: state.name }),
        el("p", { class: "sb-fixtures__run-description", text: state.description }),
      ]),
      verdictBar(state),
      transport(state),
      currentPanel(state),
      stepList(state),
      bindingsPanel(state),
    ];
  }

  /*
   * The verdict bar carries three facts that are easy to confuse and expensive
   * to conflate: how far the replay has got, what the recorded checks say so
   * far, and what the fixture's author expected of the whole thing. The third
   * is the one that makes a fixture worth having - a run that finishes green
   * when its author wrote `expects fail` has caught something, and a UI that
   * only showed the verdict would hide exactly that.
   */
  function verdictBar(state) {
    const bar = el("div", { class: "sb-fixtures__verdict" }, [
      el("span", {
        class: "sb-fixtures__verdict-chip",
        "data-verdict": state.verdict,
        text: VERDICT_LABELS[state.verdict] ?? state.verdict,
      }),
      el("span", { class: "sb-fixtures__progress", text: state.progress }),
    ]);

    if (state.agrees === false) {
      bar.append(
        el("p", {
          class: "sb-fixtures__disagree",
          text: `This fixture says it expects to ${state.expected}, and the recorded steps ${state.verdict === "fail" ? "fail" : "pass"}. One of the two is out of date.`,
        })
      );
    } else if (state.agrees === true) {
      bar.append(
        el("p", {
          class: "sb-fixtures__agree",
          text: `As expected: the fixture declares it should ${state.expected}.`,
        })
      );
    }

    return bar;
  }

  function transport(state) {
    const row = el("div", { class: "sb-fixtures__transport", role: "group", "aria-label": "Replay transport" });

    const step = (delta) => {
      cursor = moveCursor(liveRun(state.id), cursor, delta);
      draw();
    };

    row.append(
      transportButton("Reset", "reset", state.cursor === NOT_STARTED, () => {
        stopPlaying();
        cursor = resetCursor();
        draw();
      }),
      transportButton("◀", "back", state.cursor === NOT_STARTED, () => {
        stopPlaying();
        step(-1);
      }, "Step back"),
      transportButton("▶", "forward", state.finished, () => {
        stopPlaying();
        step(1);
      }, "Step forward"),
      transportButton(playing ? "Pause" : "Play", "play", false, () => togglePlay(state)),
      transportButton("End", "end", state.finished, () => {
        stopPlaying();
        cursor = endCursor(liveRun(state.id));
        draw();
      })
    );

    return row;
  }

  function transportButton(glyph, kind, disabled, onClick, label) {
    const button = el("button", {
      class: "sb-button sb-fixtures__transport-button",
      type: "button",
      "data-transport": kind,
      text: glyph,
      "aria-label": label ?? glyph,
      title: label ?? glyph,
    });

    button.disabled = disabled;
    button.addEventListener("click", onClick);

    return button;
  }

  /*
   * Play is a timer that presses "step forward", and it stops itself at the
   * end rather than sitting on a finished run pressing a disabled button. It is
   * also stopped by every other transport gesture: a Play still running after
   * an author stepped back by hand would take the canvas away from them a
   * second later.
   */
  function togglePlay(state) {
    if (playing) {
      stopPlaying();
      draw();
      return;
    }

    const runId = state.id;

    playing = window.setInterval(() => {
      const fixtures = fixturesFor(applied, host.documentId?.() ?? null);
      const run = runById(fixtures, runId);

      if (!run) {
        stopPlaying();
        draw();
        return;
      }

      const next = moveCursor(run, cursor, 1);

      if (next === cursor) {
        stopPlaying();
        draw();
        return;
      }

      cursor = next;
      draw();
    }, PLAY_INTERVAL_MS);

    draw();
  }

  function stopPlaying() {
    if (playing === null) return;
    window.clearInterval(playing);
    playing = null;
  }

  /*
   * The current step, given the whole width. The step list below is a map and
   * this is the detail: the event that arrived, what it wrote, and the check
   * the fixture recorded. Repeating the label at the top rather than making the
   * reader match a highlighted row to a detail box three inches away.
   */
  function currentPanel(state) {
    const panel = el("div", { class: "sb-fixtures__current" });

    if (state.current === null) {
      panel.append(
        el("p", {
          class: "sb-fixtures__current-idle",
          text: state.finished
            ? "The replay has finished. Reset to run it again."
            : "Not started. Step forward to begin the replay.",
        })
      );
      return panel;
    }

    const step = state.current;

    panel.append(
      el("p", { class: "sb-fixtures__current-label" }, [
        el("span", { class: "sb-fixtures__current-ordinal", text: `${step.index + 1}` }),
        el("span", { text: step.label }),
      ])
    );

    if (step.event) {
      panel.append(
        el("p", { class: "sb-fixtures__event" }, [
          el("span", { class: "sb-fixtures__event-label", text: "event" }),
          el("code", { class: "sb-code sb-fixtures__event-name", text: step.event }),
        ])
      );
    }

    if (step.invoke) panel.append(...invokeElements(step.invoke));

    if (step.note) panel.append(el("p", { class: "sb-fixtures__note", text: step.note }));

    panel.append(activeChips(step.active));

    if (step.deltas.length > 0) {
      panel.append(
        el("p", { class: "sb-fixtures__subhead", text: "writes" }),
        el(
          "ul",
          { class: "sb-fixtures__deltas" },
          step.deltas.map((delta) =>
            el("li", { class: "sb-fixtures__delta" }, [
              el("code", { class: "sb-fixtures__delta-path", text: delta.path }),
              el("code", { class: "sb-fixtures__delta-value", text: String(delta.value) }),
            ])
          )
        )
      );
    }

    if (step.check) panel.append(checkElement(step.check));

    return panel;
  }

  /*
   * The step's host call, rendered out of the classes the event line and the
   * delta list already use rather than out of new ones. That is not thrift for
   * its own sake: a call's outcome and a call's payload are the same two kinds
   * of fact the pane already shows - a name that arrived, and lines a script
   * wrote - and giving them a treatment of their own would say they are a
   * third kind.
   *
   * The sentence under an error outcome is the load-bearing part of this
   * whole bead. A reader watching a red badge light up on the canvas and the
   * next step land inside the failure subtree will conclude the runner routed
   * it there, because that is what it looks like. It did not. It is written
   * where they are looking, not only in the fixture file's comment.
   */
  function invokeElements(invoke) {
    const out = [
      el("p", { class: "sb-fixtures__event" }, [
        el("span", { class: "sb-fixtures__event-label", text: "host call" }),
        el("code", {
          class: "sb-code sb-fixtures__event-name",
          text: `${host.labelFor?.(invoke.block) ?? invoke.block} · ${
            invoke.outcome === "error" ? "failed" : "answered"
          }`,
        }),
      ]),
    ];

    if (invoke.payload.length > 0) {
      out.push(
        el("p", {
          class: "sb-fixtures__subhead",
          text: invoke.outcome === "error" ? "what came back" : "what the host answered",
        }),
        el(
          "ul",
          { class: "sb-fixtures__deltas" },
          invoke.payload.map((entry) =>
            el("li", { class: "sb-fixtures__delta" }, [
              el("code", { class: "sb-fixtures__delta-path", text: entry.name }),
              el("code", { class: "sb-fixtures__delta-value", text: entry.value }),
            ])
          )
        )
      );
    }

    out.push(
      el("p", {
        class: "sb-hint",
        text:
          invoke.outcome === "error"
            ? "Recorded, not routed: the steps after this one are block ids the fixture's author wrote after reading the document. Nothing here walked the failure path."
            : "Recorded, not called: the badge on the canvas marks the block this step calls out to, and the answer above is a value in the fixture file.",
      })
    );

    return out;
  }

  /*
   * The active blocks as chips, each one a reveal. Labelled by the block's own
   * title where the host can supply one, because `blk_cp_three_ds_wait` is an
   * id and an author reads titles - but the id is kept in the tooltip, since it
   * is what they will grep the fixture file for.
   */
  function activeChips(ids) {
    const box = el("div", { class: "sb-fixtures__active" });

    if (ids.length === 0) {
      box.append(el("p", { class: "sb-hint", text: "This step activates no block." }));
      return box;
    }

    box.append(
      el("p", {
        class: "sb-fixtures__subhead",
        text: ids.length === 1 ? "active block" : `${ids.length} blocks active at once`,
      })
    );

    const row = el("div", { class: "sb-fixtures__active-row" });

    for (const id of ids) {
      const chip = el("button", {
        class: "sb-fixtures__active-chip",
        type: "button",
        title: `${id} · reveal on the canvas`,
        text: host.labelFor?.(id) ?? id,
      });

      chip.addEventListener("click", () => {
        const found = host.revealBlocks?.([id]);
        notice = found ? `Revealed ${id}.` : `${id} is not in this document.`;
        draw();
      });

      row.append(chip);
    }

    const all = el("button", {
      class: "sb-button sb-button--quiet sb-fixtures__reveal-all",
      type: "button",
      text: ids.length === 1 ? "Show on canvas" : "Show all on canvas",
    });

    all.addEventListener("click", () => {
      const found = host.revealBlocks?.(ids);
      notice = found ? "Revealed on the canvas." : "None of those blocks are in this document.";
      draw();
    });

    box.append(row, all);

    return box;
  }

  function checkElement(check) {
    const box = el("div", { class: "sb-fixtures__check", "data-result": check.result });

    box.append(
      el("p", { class: "sb-fixtures__check-head" }, [
        el("span", {
          class: "sb-fixtures__check-chip",
          "data-result": check.result,
          text: check.result === "pass" ? "recorded pass" : "recorded fail",
        }),
        el("span", { class: "sb-fixtures__check-label", text: check.label }),
      ])
    );

    if (check.detail) {
      box.append(el("p", { class: "sb-fixtures__check-detail", text: check.detail }));
    }

    return box;
  }

  function stepList(state) {
    const list = el("ol", { class: "sb-fixtures__steps" });

    for (const step of state.steps) {
      const row = el("button", {
        class: "sb-fixtures__step",
        type: "button",
        "data-state": step.state,
        "data-check": step.check?.result ?? "",
        "aria-current": step.state === "current" ? "step" : "false",
      });

      // Filtered rather than appended one by one: `Element.append(null)` puts
      // the string "null" in the document, which is the sort of thing that
      // survives review because it only shows up on the rows without a check.
      const parts = [
        el("span", { class: "sb-fixtures__step-ordinal", text: String(step.index + 1) }),
        el("span", { class: "sb-fixtures__step-label", text: step.label }),
        step.active.length > 1
          ? el("span", {
              class: "sb-fixtures__step-lanes",
              title: `${step.active.length} blocks active at once`,
              text: `×${step.active.length}`,
            })
          : null,
        // A check the cursor has not reached is not shown as passing or
        // failing - that would be the step list spoiling its own ending. It
        // keeps its slot with a neutral mark so the row does not change width
        // when the replay arrives.
        step.check
          ? el("span", {
              class: "sb-fixtures__step-check",
              "data-result": step.consumed ? step.check.result : "pending",
              "aria-label": step.consumed
                ? step.check.result === "pass"
                  ? "check passed"
                  : "check failed"
                : "this step carries a check",
              text: step.consumed ? (step.check.result === "pass" ? "✓" : "✗") : "·",
            })
          : null,
      ];

      row.append(...parts.filter(Boolean));

      // Clicking a row scrubs to it, which is the gesture a step list invites
      // and the one a transport alone cannot offer: "show me the moment it went
      // wrong" is one click on the red row rather than six presses of forward.
      row.addEventListener("click", () => {
        stopPlaying();
        cursor = step.index;
        draw();
      });

      list.append(el("li", {}, [row]));
    }

    return el("div", { class: "sb-fixtures__section" }, [
      el("p", { class: "sb-fixtures__subhead", text: "steps" }),
      list,
    ]);
  }

  function bindingsPanel(state) {
    const box = el("div", { class: "sb-fixtures__section" });

    if (state.bindings.length === 0) return box;

    box.append(
      el("p", {
        class: "sb-fixtures__subhead",
        text: `datamodel after step ${state.finished ? state.stepCount : state.cursor + 1}`,
      }),
      el(
        "ul",
        { class: "sb-fixtures__deltas sb-fixtures__deltas--accumulated" },
        state.bindings.map((binding) =>
          el("li", { class: "sb-fixtures__delta" }, [
            el("code", { class: "sb-fixtures__delta-path", text: binding.path }),
            el("code", { class: "sb-fixtures__delta-value", text: String(binding.value) }),
          ])
        )
      ),
      el("p", {
        class: "sb-hint",
        text: "Written by the script, not by an interpreter - these are the values the fixture's author says the run establishes.",
      })
    );

    return box;
  }

  /* ============================================================ the tables */

  function tablesView(fixtures) {
    const selectedId = host.selectedId?.() ?? null;
    const mine = tablesForBlock(fixtures, selectedId);

    if (mine.length === 0) return tablesEmptyState(fixtures, selectedId);

    return [
      el("p", {
        class: "sb-hint",
        text: "Precomputed truth tables. Every expected value is fixture data - the pane renders them, it does not evaluate the expressions beside them.",
      }),
      ...mine.map((table) => tableElement(tableView(table))),
    ];
  }

  /*
   * The empty state's second job, same as the condition pane's: an author who
   * selected the wrong block needs to know which blocks DO have tables, and a
   * list of them that selects and reveals on click is worth more than a
   * sentence telling them to go looking.
   */
  function tablesEmptyState(fixtures, selectedId) {
    const ids = tableBlockIds(fixtures);

    const out = [
      el("p", {
        class: "sb-empty",
        text:
          selectedId === null
            ? "Select a guarded block to see the condition fixtures written for it."
            : "No truth table is written for this block.",
      }),
    ];

    if (ids.length === 0) {
      out.push(
        el("p", {
          class: "sb-hint",
          text: "This document has no condition fixtures at all. Tables live on branch arms and on guarded interrupt rules.",
        })
      );
      return out;
    }

    out.push(
      el("p", {
        class: "sb-hint",
        text: `${ids.length} block${ids.length === 1 ? " has" : "s have"} a table in this document:`,
      })
    );

    const list = el("ul", { class: "sb-fixtures__table-jumps" });

    for (const id of ids) {
      const mine = tablesForBlock(fixtures, id);

      // The TABLE's name, not the block's. A branch and an interrupt rule
      // carry no `label` in their config, so the block label falls back to the
      // palette entry - and the first pass rendered three rows reading
      // "Branch", "On event, when", "Branch", which is a list that tells an
      // author nothing about which one they want. The table is the thing being
      // offered, so the table names it; the block's own label is the second
      // line, and its id is in the tooltip.
      const button = el("button", {
        class: "sb-fixtures__table-jump",
        type: "button",
        title: `${id} · select and reveal`,
      });

      button.append(
        el("span", { class: "sb-fixtures__table-jump-name" }, [
          el("span", { text: mine.length === 1 ? (mine[0].name ?? id) : `${mine.length} tables` }),
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
   * The table itself. It is wider than the pane and it is allowed to be: the
   * bindings column plus one column per arm does not fit in 21rem and never
   * will, so the table scrolls inside its own box rather than being squeezed
   * into an unreadable one. Whether a truth table wants a wider home than the
   * inspector is the design question this pane found - see the bead note.
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

    /*
     * Expected results BEFORE the bound values, which inverts how a truth table
     * is conventionally read.
     *
     * The reason is the pane's width. Convention puts the inputs on the left
     * and the answers on the right, and in `--sb-inspector-width` that puts
     * every answer off the right edge behind a horizontal scroll - so the one
     * thing the table exists to show is the one thing not on screen. Each case
     * carries a name that says what it is ("Rated high", "Low but unverified"),
     * so name-plus-verdict is a complete reading on its own and the exact
     * bindings are the detail a reader scrolls for. Whether a truth table wants
     * a wider home than the inspector is the open question this pane found; in
     * the home it has, this is the ordering that works.
     */
    const head = el("tr", {}, [
      el("th", { class: "sb-fixtures__grid-corner", scope: "col", text: "Case" }),
      ...table.columns.map((column) =>
        el("th", {
          class: "sb-fixtures__grid-arm",
          scope: "col",
          title: column.expr,
          text: column.label,
        })
      ),
      ...table.paths.map((path, index) =>
        el("th", {
          class: "sb-fixtures__grid-path",
          scope: "col",
          // The seam between the answers and the values behind them, marked in
          // the markup because both families are cells and CSS cannot tell
          // them apart by position.
          "data-column": index === 0 ? "first-arm" : null,
          title: path,
          text: path,
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
        ...row.cells.map((cell) =>
          el("td", { class: "sb-fixtures__grid-cell" }, [
            el("span", {
              class: "sb-fixtures__bool",
              "data-value": cell.expected === null ? "unset" : String(cell.expected),
              text: cell.expected === null ? "–" : cell.expected ? "true" : "false",
            }),
          ])
        ),
        ...row.bindings.map((binding, index) =>
          el(
            "td",
            {
              class: "sb-fixtures__grid-binding",
              "data-column": index === 0 ? "first-arm" : null,
            },
            [el("code", { text: String(binding.value) })]
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
        text: `Scroll the table sideways for the bound values behind each verdict: ${table.paths.join(", ")}.`,
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

  /* ============================================================== the JSON */

  /*
   * Deliverable 4, deliberately plain: a textarea, Apply, Revert, and the parse
   * error where the author is standing. Polish over ambition - a JSON editor
   * with folding and a schema is a different bead, and the affordance this
   * spike has to prove is that a fixture is EDITABLE and that a bad edit says
   * why rather than disappearing.
   *
   * Applied edits live in `applied` and nowhere else. The file on disk is never
   * written; the note under the buttons says so, because an author who typed
   * into a box and pressed Apply has every right to assume otherwise.
   */
  function jsonView() {
    const text = editorText ?? fixturesText(applied);

    const area = el("textarea", {
      class: "sb-input sb-input--mono sb-fixtures__editor",
      spellcheck: "false",
      "aria-label": "Fixture JSON",
      rows: "18",
    });
    area.value = text;

    area.addEventListener("input", () => {
      editorText = area.value;
    });

    const apply = el("button", {
      class: "sb-button sb-button--primary",
      type: "button",
      text: "Apply",
    });

    const revert = el("button", {
      class: "sb-button sb-button--quiet",
      type: "button",
      text: "Revert",
    });

    apply.addEventListener("click", () => {
      const result = parseFixtures(area.value);

      if (!result.ok) {
        editorText = area.value;
        editorError = result;
        draw();
        return;
      }

      applied = result.value;
      editorText = null;
      editorError = null;
      // A run that no longer exists in the applied data must not stay open on
      // a stale copy; dropping to the list is the honest reset.
      openRunId = null;
      cursor = NOT_STARTED;
      stopPlaying();
      host.markActive?.([]);
      notice = "Applied. These fixtures live in memory only - the file on disk is unchanged.";
      draw();
    });

    revert.addEventListener("click", () => {
      applied = original;
      editorText = null;
      editorError = null;
      openRunId = null;
      cursor = NOT_STARTED;
      stopPlaying();
      host.markActive?.([]);
      notice = "Reverted to the fixtures as fetched.";
      draw();
    });

    const out = [
      el("p", {
        class: "sb-hint",
        text: "The whole fixture file, editable. Apply parses it and re-renders the runs and tables; nothing is written to disk.",
      }),
      area,
    ];

    if (editorError) {
      out.push(
        el("div", { class: "sb-fixtures__parse-error" }, [
          el("p", { class: "sb-fixtures__parse-error-head" }, [
            el("span", { class: "sb-fixtures__parse-error-chip", text: "not applied" }),
            el("span", {
              class: "sb-fixtures__parse-error-where",
              text:
                editorError.line === null
                  ? "the text is not valid JSON"
                  : `line ${editorError.line}, column ${editorError.column}`,
            }),
          ]),
          el("p", { class: "sb-fixtures__parse-error-message", text: editorError.message }),
        ])
      );
    }

    out.push(
      el("div", { class: "sb-fixtures__editor-actions" }, [apply, revert]),
      el("p", {
        class: "sb-hint",
        text: "Edits are in memory for this page only. Reloading brings back the file as it is on disk.",
      })
    );

    return out;
  }

  /* ------------------------------------------------------------- handle */

  draw();

  return {
    redraw: draw,
    /** Called by the shell when the canvas selection moves. */
    selectionChanged() {
      if (view === "tables") draw();
    },
    /** Called when a document loads, so a run from the last one does not linger. */
    documentChanged() {
      openRunId = null;
      cursor = NOT_STARTED;
      editorError = null;
      stopPlaying();
      draw();
    },
    destroy() {
      stopPlaying();
      // The canvas outlives this pane, so a mark left behind would sit on a
      // card claiming a call is in flight with nothing left to clear it.
      paintInvoke(null);
    },
  };
}
