/*
 * spike/js/inspector.js - the Config and Findings panes, rendered.
 *
 * The DOM half of sb-8cm. `panes.js` decides what a form and a finding list
 * ARE; this file turns those values into elements and the resulting gestures
 * back into calls on the editor. It owns no state beyond the focus it puts
 * back after a re-render, which is the same division `interact.js` keeps
 * against `session.js`.
 *
 * ## Two rules this file exists to keep
 *
 * **An edit is an `:update_config` command, never a write into the document.**
 * Every control below funnels through `host.updateConfig`, which is
 * `session.js`'s `updateBlockConfig` - so every keystroke that lands is
 * undoable, bumps the revision, and passes ADR-0005 decision 9's gate. There
 * is no path from a control to `block.config`.
 *
 * **A control commits on `change`, not on `input`.** Decision 9 is explicit
 * that in-progress form state lives in transient assigns and never on the undo
 * stack: "undo steps back to the last config that validated, not through
 * individual keystrokes". `change` fires on blur and on Enter, which is
 * exactly that boundary, and it is why typing four characters into a condition
 * produces one undo step rather than four.
 *
 * A refusal - decision 9's gate turning down config `validate_config/1`
 * rejects - deliberately does NOT re-render. The author's text stays in the
 * field, the field is marked, and the reason appears under it. Snapping the
 * input back to the last valid value is the behaviour that makes a form feel
 * like it is fighting you.
 */

import {
  addRow,
  anchorLabel,
  canonicalJson,
  configFormFor,
  durationFrom,
  durationParts,
  durationUnits,
  moveRow,
  removeRow,
  seedRow,
  severityCounts,
  writeAtPath,
} from "./panes.js";
import { findBlock } from "./document.js";
import { el } from "./render.js";

const SEVERITY_LABELS = { error: "Error", warning: "Warning", info: "Note" };

/**
 * Wires the two panes to one editor.
 *
 *     mounts  { config, findings, findingsBadge }
 *     host    { state(), updateConfig(id, config), reveal(finding) }
 *
 * `state()` returns `{ session, findings }` or `null` when no document is
 * open. `updateConfig` returns `true` when the command was applied, which is
 * what tells a control whether to expect a re-render or to mark itself.
 */
export function createInspector({ mounts, host }) {
  function refresh() {
    const state = host.state();

    renderConfig(mounts.config, state, host);
    renderFindings(mounts.findings, state, host);
    renderBadge(mounts.findingsBadge, state);
  }

  return { refresh };
}

/* ================================================================== badge */

function renderBadge(badge, state) {
  if (!badge) return;

  const counts = state ? severityCounts(state.findings) : { total: 0, error: 0 };

  if (counts.total === 0) {
    badge.hidden = true;
    badge.textContent = "";
    return;
  }

  badge.hidden = false;
  badge.textContent = String(counts.total);
  // Errors get the loud badge and everything else the quiet one, so the count
  // on the tab answers "is anything broken" and not merely "is anything here".
  badge.dataset.severity = counts.error > 0 ? "error" : "muted";
  badge.title = `${counts.total} finding${counts.total === 1 ? "" : "s"} in this document`;
}

/* ============================================================ config pane */

function renderConfig(mount, state, host) {
  if (!mount) return;

  const node = state?.session ? selected(state.session) : null;

  if (!node) {
    mount.replaceChildren(
      el("p", {
        class: "sb-empty",
        text: "Select a block on the canvas to edit its configuration.",
      })
    );
    return;
  }

  const form = configFormFor(state.session.registry, node, state.findings);

  if (form.readOnly) {
    mount.replaceChildren(...readOnlyConfig(form));
    return;
  }

  if (form.empty) {
    mount.replaceChildren(
      el("p", {
        class: "sb-empty",
        text: "This block type declares no configuration of its own.",
      })
    );
    return;
  }

  const memo = focusMemo(mount);

  mount.replaceChildren(
    el(
      "div",
      { class: "sb-form" },
      form.fields.map((field) => fieldElement(field, form, host))
    )
  );

  restoreFocus(mount, memo);
}

/*
 * ADR-0005 decision 12, in the one place an author goes looking for a form.
 * The bytes, verbatim and read-only, plus a sentence saying they are safe -
 * "an editor that quietly dropped it would turn a missing palette entry into
 * silent data loss" cuts both ways, and an author who is not told the bytes
 * survive will assume they did not.
 */
function readOnlyConfig(form) {
  return [
    el("p", { class: "sb-inspector__note", text: unresolvedNote(form) }),
    el("div", { class: "sb-form__readonly-head" }, [
      el("span", { class: "sb-chip sb-chip--readonly", text: "read-only" }),
      el("span", { class: "sb-form__readonly-label", text: "stored config, as decoded" }),
    ]),
    el("pre", { class: "sb-code sb-form__raw", text: form.rawConfig ?? canonicalJson({}) }),
  ];
}

function unresolvedNote(form) {
  const why =
    form.reason?.tag === "block_type_too_new"
      ? "was authored by a newer version of its block type"
      : `is not registered here (${form.typeName})`;

  return `This block's type ${why}. It can be selected, moved and deleted; its config is read-only and its stored bytes are preserved.`;
}

/* ------------------------------------------------------------ one field */

function fieldElement(field, form, host) {
  const id = `sb-field-${form.blockId}-${cssSafe(field.key)}`;

  const label = el("label", { class: "sb-field__label", for: id }, [
    el("span", { class: "sb-field__label-text", text: field.label }),
    field.required ? el("span", { class: "sb-field__required", text: "required" }) : null,
  ]);

  const wrapper = el(
    "div",
    {
      class: "sb-field",
      "data-field-key": field.key,
      "data-control": field.control,
    },
    [label]
  );

  const commit = (value) => {
    const config = writeAtPath(currentConfig(host, form.blockId), field.path, value);
    const refusal = host.updateConfig(form.blockId, config);

    if (refusal) markRefused(wrapper, refusal, field.key);
    return refusal === null;
  };

  wrapper.append(control(field, id, commit, host, form));

  // ADR-0005 decision 11: "a `:config` finding renders inline beneath its
  // field". Routed by the anchor's key, which is the key `validate_config/1`
  // reports against - the reason `core.branch` keys an arm by its slot name.
  for (const finding of field.findings) {
    wrapper.append(
      el("p", {
        class: "sb-field__finding",
        "data-severity": finding.severity ?? "error",
        text: finding.message,
      })
    );
  }

  return wrapper;
}

function control(field, id, commit, host, form) {
  switch (field.control) {
    case "boolean":
      return booleanControl(field, id, commit);
    case "integer":
      return integerControl(field, id, commit);
    case "select":
      return selectControl(field, id, commit);
    case "duration":
      return durationControl(field, id, commit);
    case "list":
      return listControl(field, id, commit, host, form);
    case "expression":
      return textControl(field, id, commit, { mono: true, placeholder: "an expression" });
    default:
      // Also where a decimal lands: ADR-0001 decision 6 forbids floats in
      // config, so a decimal is a `string` field holding "12.50", and the
      // text control stores and round-trips it unchanged.
      return textControl(field, id, commit, {});
  }
}

function textControl(field, id, commit, { mono = false, placeholder = "" }) {
  const input = el("input", {
    class: mono ? "sb-input sb-input--mono" : "sb-input",
    type: "text",
    id,
    value: field.value === undefined || field.value === null ? "" : String(field.value),
    placeholder,
  });

  input.value = field.value === undefined || field.value === null ? "" : String(field.value);
  input.addEventListener("change", () => commit(input.value));

  return el("div", { class: "sb-field__control" }, [input]);
}

function integerControl(field, id, commit) {
  const input = el("input", {
    class: "sb-input",
    type: "number",
    step: "1",
    inputmode: "numeric",
    id,
  });

  input.value = Number.isInteger(field.value) ? String(field.value) : "";

  input.addEventListener("change", () => {
    // An empty box is "no value", not zero. `null` is a config value ADR-0001
    // decision 6 admits, and it is what makes an optional integer clearable.
    if (input.value.trim() === "") return commit(null);

    const parsed = Number(input.value);
    commit(Number.isInteger(parsed) ? parsed : input.value);
  });

  return el("div", { class: "sb-field__control" }, [input]);
}

function booleanControl(field, id, commit) {
  const input = el("input", { class: "sb-checkbox", type: "checkbox", id });
  input.checked = field.value === true;
  input.addEventListener("change", () => commit(input.checked));

  return el("div", { class: "sb-field__control sb-field__control--inline" }, [
    input,
    el("label", { class: "sb-field__check-label", for: id, text: input.checked ? "Yes" : "No" }),
  ]);
}

function selectControl(field, id, commit) {
  const select = el(
    "select",
    { class: "sb-select sb-select--block", id },
    field.choices.map((choice) =>
      el("option", { value: choice.value, text: choice.label ?? choice.value })
    )
  );

  // A stored value the type no longer offers keeps its own option rather than
  // silently snapping to the first choice - the document said what it said,
  // and a form that rewrites it on render is a form that loses data on focus.
  if (!field.choices.some((choice) => choice.value === field.value) && field.value !== undefined) {
    select.prepend(
      el("option", { value: String(field.value), text: `${field.value} (not offered)` })
    );
  }

  select.value = field.value === undefined ? "" : String(field.value);
  select.addEventListener("change", () => commit(select.value));

  return el("div", { class: "sb-field__control" }, [select]);
}

/*
 * ADR-0005 decision 9's duration control: "a structured value/unit control
 * emitting an ISO-8601 string ... The control exists so the author does not
 * have to know that."
 *
 * Two shapes, and the second is the honest half. A single-component duration
 * (`PT30S`, `P1D`) round-trips losslessly through a number and a unit, so it
 * gets the structured control. `PT1H30M` does not, and rather than rewriting
 * an author's stored value to `90 minutes` on first render, the control falls
 * back to editing the ISO string with the humanized readout beside it. Both
 * shapes show the readout, because the readout is what makes the ISO string
 * legible and that is the whole point of the control.
 */
function durationControl(field, id, commit) {
  const parts = field.duration ?? durationParts(field.value);
  const box = el("div", { class: "sb-duration" });

  // The structured control cannot express `PT1H30M`, and an author who needs
  // one has no way to type it - the value/unit pair is a projection that
  // rounds every two-component duration away. So the escape hatch is offered
  // rather than hidden: one button swaps the control for the ISO string, in
  // place and without committing anything. A control that CANNOT express a
  // legal value is worse than a slightly busier one.
  const wrapper = el("div", { class: "sb-field__control" });
  let iso = !parts.simple;

  if (parts.simple) {
    const amount = el("input", {
      class: "sb-input sb-duration__amount",
      type: "number",
      min: "0",
      step: "1",
      id,
    });
    amount.value = String(parts.amount);

    const unit = el(
      "select",
      { class: "sb-select sb-duration__unit", "aria-label": `${field.label} unit` },
      durationUnits().map((one) => el("option", { value: one.unit, text: one.label }))
    );
    unit.value = parts.unit;

    const fire = () => commit(durationFrom(amount.value, unit.value));
    amount.addEventListener("change", fire);
    unit.addEventListener("change", fire);

    box.append(amount, unit);
  } else {
    const raw = el("input", {
      class: "sb-input sb-input--mono",
      type: "text",
      id,
      placeholder: "PT1H30M",
    });
    raw.value = parts.iso;
    raw.addEventListener("change", () => commit(raw.value));

    box.append(raw);
  }

  const readout = el("span", { class: "sb-duration__readout" }, [
    el("span", { class: "sb-duration__human", text: parts.human || "—" }),
    el("code", { class: "sb-duration__iso", text: parts.iso || "—" }),
  ]);

  if (iso && parts.iso !== "") {
    readout.append(
      el("span", {
        class: "sb-duration__note",
        text: "more than one unit - edited as ISO-8601",
      })
    );
  }

  wrapper.append(box, readout);

  if (!iso) {
    const escape = el("button", {
      class: "sb-button sb-button--quiet sb-duration__escape",
      type: "button",
      text: "Edit as ISO-8601",
    });

    escape.addEventListener("click", () => {
      const raw = el("input", {
        class: "sb-input sb-input--mono",
        type: "text",
        id,
        placeholder: "PT1H30M",
      });
      raw.value = parts.iso;
      raw.addEventListener("change", () => commit(raw.value));

      iso = true;
      box.replaceChildren(raw);
      escape.remove();
      raw.focus();
    });

    wrapper.append(escape);
  }

  return wrapper;
}

/*
 * `{:list, t}`: "repeatable rows of `t`'s renderer, with add and remove".
 * Reorder is here too, because a list whose order is meaningful - a
 * parallel's lanes read left to right on the canvas - is a list an author
 * will want to reorder, and dragging rows is a whole other bead.
 *
 * Every gesture is ONE `:update_config` carrying the whole new list, which is
 * what keeps a reorder a single undo step. Note what a lane rename or removal
 * does downstream: it changes the block's SLOT set, so the canvas re-renders
 * with a column gone and any children it held rendered under their raw slot
 * name as a stranded slot. That is decision 12's machinery doing its job on a
 * resolvable type, and it is visible from this control.
 */
function listControl(field, id, commit, host, form) {
  const rows = field.rows.map((row) => row.value);

  const list = el("div", { class: "sb-rows", id });

  field.rows.forEach((row, index) => {
    const input = el("input", { class: "sb-input sb-rows__input", type: "text" });
    input.value = row.value === undefined || row.value === null ? "" : String(row.value);
    input.setAttribute("aria-label", `${field.label} row ${index + 1}`);
    input.addEventListener("change", () => {
      const next = rows.slice();
      next[index] = coerceRow(field.itemType, input.value);
      commit(next);
    });

    list.append(
      el("div", { class: "sb-rows__row", "data-row-index": String(index) }, [
        el("span", { class: "sb-rows__ordinal", text: String(index + 1) }),
        input,
        rowButton("↑", `Move ${field.label} row ${index + 1} up`, index === 0, "up", () =>
          moveAndFollow(field, rows, index, -1, commit)
        ),
        rowButton(
          "↓",
          `Move ${field.label} row ${index + 1} down`,
          index === rows.length - 1,
          "down",
          () => moveAndFollow(field, rows, index, 1, commit)
        ),
        rowButton("×", `Remove ${field.label} row ${index + 1}`, false, "remove", () =>
          commit(removeRow(rows, index))
        ),
      ])
    );
  });

  if (rows.length === 0) {
    list.append(el("p", { class: "sb-rows__empty", text: "No rows yet." }));
  }

  const add = el("button", {
    class: "sb-button sb-button--quiet sb-rows__add",
    type: "button",
    text: "Add row",
  });
  add.addEventListener("click", () => commit(addRow(rows, seedRow(field.itemType))));

  return el("div", { class: "sb-field__control" }, [list, add]);
}

function rowButton(glyph, label, disabled, dir, onClick) {
  const button = el("button", {
    class: "sb-rows__action",
    type: "button",
    "data-dir": dir,
    "aria-label": label,
    title: label,
    text: glyph,
  });

  button.disabled = disabled;
  button.addEventListener("click", onClick);

  return button;
}

/*
 * Reordering moves the row, so the keyboard should follow it. The generic
 * focus memo restores position WITHIN a field, which is right for a text edit
 * and wrong here: it would leave the caret on whatever row slid into the old
 * index. Committing re-renders synchronously, so the row's new home exists by
 * the time this runs.
 */
function moveAndFollow(field, rows, index, step, commit) {
  if (!commit(moveRow(rows, index, step))) return;

  const to = index + step;
  const owner = Array.from(document.querySelectorAll("[data-field-key]")).find(
    (one) => one.dataset.fieldKey === field.key
  );

  const button = owner
    ?.querySelector(`[data-row-index="${to}"]`)
    ?.querySelector(`[data-dir="${step < 0 ? "up" : "down"}"]`);

  // The row that just reached an end has its own button disabled; the other
  // direction is where the author can still go, so focus lands there instead
  // of nowhere.
  if (button && !button.disabled) button.focus();
  else
    owner
      ?.querySelector(`[data-row-index="${to}"]`)
      ?.querySelector(`[data-dir="${step < 0 ? "down" : "up"}"]`)
      ?.focus();
}

function coerceRow(itemType, raw) {
  if (itemType === "integer") {
    const parsed = Number(raw);
    return Number.isInteger(parsed) ? parsed : raw;
  }
  if (itemType === "boolean") return raw === "true";
  return raw;
}

/* =========================================================== findings pane */

function renderFindings(mount, state, host) {
  if (!mount) return;

  if (!state) {
    mount.replaceChildren(
      el("p", { class: "sb-empty", text: "Load a document to see its findings." })
    );
    return;
  }

  const findings = state.findings;

  if (findings.length === 0) {
    mount.replaceChildren(
      el("p", {
        class: "sb-empty",
        text: "No findings. Every block resolves and every config validates.",
      })
    );
    return;
  }

  const counts = severityCounts(findings);

  const summary = el("div", { class: "sb-findings__summary" }, [
    counts.error > 0 ? severityChip("error", counts.error) : null,
    counts.warning > 0 ? severityChip("warning", counts.warning) : null,
    counts.info > 0 ? severityChip("info", counts.info) : null,
  ]);

  const list = el(
    "ul",
    { class: "sb-findings__list" },
    findings.map((finding) => el("li", {}, [findingRow(finding, host)]))
  );

  mount.replaceChildren(
    summary,
    list,
    el("p", {
      class: "sb-hint",
      text: "Click a finding to select and reveal what it is about. Rows marked demo are a static set; the rest come from validation.",
    })
  );
}

function severityChip(severity, count) {
  return el("span", {
    class: "sb-severity-chip",
    "data-severity": severity,
    text: `${count} ${SEVERITY_LABELS[severity].toLowerCase()}${count === 1 ? "" : "s"}`,
  });
}

/*
 * A finding is a BUTTON, not a list row with a click handler. "Selecting one
 * selects and reveals its anchor" is a real navigation gesture, so it has to
 * answer Enter and Space and appear in the tab order - and a screen reader has
 * to be told it is actionable rather than left to infer it from a cursor.
 */
function findingRow(finding, host) {
  const button = el("button", {
    class: `sb-finding sb-finding--${finding.severity}`,
    type: "button",
    "data-origin": finding.origin ?? "validation",
  });

  // The message gets the full width. Severity, source and origin are all
  // one-word facts that read fine on a footer line, and hanging them beside
  // the message squeezed it into a three-word-per-line column.
  const meta = el("span", { class: "sb-finding__meta" }, [
    el("span", { class: "sb-finding__anchor", text: anchorLabel(finding.anchor) }),
    el("span", { class: "sb-finding__source", text: finding.source }),
    finding.origin === "demo" ? el("span", { class: "sb-finding__origin", text: "demo" }) : null,
  ]);

  button.append(
    el("span", {
      class: "sb-finding__severity",
      "data-severity": finding.severity,
      text: SEVERITY_LABELS[finding.severity] ?? finding.severity,
    }),
    el("span", { class: "sb-finding__body" }, [
      el("span", { class: "sb-finding__message", text: finding.message }),
      meta,
    ])
  );

  button.addEventListener("click", () => host.reveal(finding));

  return button;
}

/* ================================================================ helpers */

function selected(session) {
  return session.selectedId === null ? null : findBlock(session.document, session.selectedId);
}

/*
 * Read from the LIVE session rather than closing over the config the form was
 * built from. Two edits in a row - type a lane name, then add a row - would
 * otherwise have the second one write through a config the first had already
 * replaced, and silently undo it.
 */
function currentConfig(host, blockId) {
  const node = findBlock(host.state().session.document, blockId);
  return node ? node.config : {};
}

/*
 * The gate's refusal, said where the author is standing. No re-render, so the
 * text they typed stays put; the pane just grows a line explaining why it has
 * not been stored yet. Findings the refusal reports against OTHER fields are
 * shown too, because "two arms cannot share one slot" is about this edit even
 * though `validate_config/1` keyed it elsewhere.
 */
function markRefused(wrapper, refusal, key) {
  wrapper.dataset.refused = "true";

  for (const stale of wrapper.querySelectorAll("[data-refusal]")) stale.remove();

  const findings = Array.isArray(refusal?.findings) ? refusal.findings : [];
  const mine = findings.filter((one) => one.key === key);

  for (const finding of mine.length > 0 ? mine : findings) {
    wrapper.append(
      el("p", {
        class: "sb-field__finding",
        "data-severity": "error",
        "data-refusal": "true",
        text: finding.message,
      })
    );
  }

  if (findings.length === 0) {
    wrapper.append(
      el("p", {
        class: "sb-field__finding",
        "data-severity": "error",
        "data-refusal": "true",
        text: "That value is not valid, so it was not stored.",
      })
    );
  }
}

const cssSafe = (value) => String(value).replace(/[^a-zA-Z0-9_-]/g, "_");

/*
 * A re-render replaces every control, which would drop focus mid-form. The
 * memo is the field key and the caret, put back afterwards - not because a
 * spike needs polish, but because a config form that loses focus on every
 * committed edit is unusable for the one thing it exists to demonstrate.
 */
function focusMemo(mount) {
  const active = document.activeElement;
  if (!active || !mount.contains(active)) return null;

  const field = active.closest("[data-field-key]");
  const row = active.closest("[data-row-index]");
  const scope = row ?? field;

  return {
    key: field?.dataset.fieldKey ?? null,
    row: row?.dataset.rowIndex ?? null,
    // WHICH control, not merely which field. Pressing a row's "move down" and
    // landing back on that row's text box is the small wrongness that makes
    // reordering three lanes take six clicks instead of three.
    at: scope ? Array.from(scope.querySelectorAll(FOCUSABLE)).indexOf(active) : -1,
    start: typeof active.selectionStart === "number" ? active.selectionStart : null,
  };
}

const FOCUSABLE = "input, select, textarea, button";

function restoreFocus(mount, memo) {
  if (!memo?.key) return;

  // Matched on the dataset rather than through a selector: a field key is an
  // arm's slot name off a document's bytes, and building a selector out of
  // foreign text is the habit this spike should not teach.
  const field = Array.from(mount.querySelectorAll("[data-field-key]")).find(
    (one) => one.dataset.fieldKey === memo.key
  );

  if (!field) return;

  const scope =
    memo.row === null ? field : (field.querySelector(`[data-row-index="${memo.row}"]`) ?? field);
  const controls = Array.from(scope.querySelectorAll(FOCUSABLE));
  const control = controls[memo.at] ?? controls[0];
  if (!control || control.disabled) return;

  control.focus();

  if (memo.start !== null && typeof control.setSelectionRange === "function") {
    try {
      control.setSelectionRange(memo.start, memo.start);
    } catch {
      // A number input refuses a selection range in some browsers. Focus is
      // the part that matters; the caret is a bonus.
    }
  }
}
