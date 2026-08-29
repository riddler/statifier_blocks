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
  addMapRow,
  addRow,
  anchorLabel,
  canonicalJson,
  configFormFor,
  createDraftStore,
  durationFrom,
  durationParts,
  durationUnits,
  moveRow,
  pendingKeys,
  removeMapRow,
  removeRow,
  renameMapRow,
  seedRow,
  setMapValue,
  severityCounts,
  writeAtPath,
} from "./panes.js";
import { annotateCondition, conditionFields, conditionPaths } from "./datamodel.js";
import { findBlock } from "./document.js";
import { el } from "./render.js";

const SEVERITY_LABELS = { error: "Error", warning: "Warning", info: "Note" };

/**
 * Wires the inspector's panes to one editor.
 *
 *     mounts  { config, findings, findingsBadge, condition }
 *     host    { state(), updateConfig(id, config), reveal(finding),
 *               datamodel: { index, reveal(path) },
 *               tables: { countFor(blockId), open(blockId) } }
 *
 * `state()` returns `{ session, findings }` or `null` when no document is
 * open. `updateConfig` returns `true` when the command was applied, which is
 * what tells a control whether to expect a re-render or to mark itself.
 *
 * `host.tables` is optional the same way `host.datamodel` is: without it the
 * condition pane renders exactly as it did before sb-054, minus the one button
 * that opens the truth-table drawer.
 *
 * `host.datamodel` is optional: without it the condition pane still renders and
 * still edits, it simply says nothing about whether a path is declared. That is
 * the honest degradation - a host with no datamodel document has no basis for
 * the affirmative treatment, and inventing one would be the pane claiming to
 * know something it does not.
 */
export function createInspector({ mounts, host }) {
  /*
   * sb-5ow's draft store. Held by the inspector rather than by the session,
   * because a draft is in-progress FORM state: ADR-0005 decision 9 puts it in
   * transient assigns explicitly, and a draft that lived on the session would
   * be a config the document model knows about but the gate never saw.
   */
  const drafts = createDraftStore();
  let lastDocumentId = null;

  function refresh() {
    const state = host.state();

    // A different document is a different set of block ids, so every
    // outstanding draft is about blocks that are no longer on screen. The
    // only automatic clear the store has.
    const documentId = state?.session?.document?.id ?? null;
    if (documentId !== lastDocumentId) {
      drafts.reset();
      lastDocumentId = documentId;
    }

    renderConfig(mounts.config, state, host, { drafts, refresh });
    renderFindings(mounts.findings, state, host);
    renderBadge(mounts.findingsBadge, state);
    renderCondition(mounts.condition, state, host, { drafts, refresh });
  }

  // `drafts` is returned so a caller can ask whether anything is outstanding -
  // the self-test does, and a shell that wanted to warn before closing a
  // document could. Nothing outside this file may stage or clear one.
  return { refresh, drafts };
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

function renderConfig(mount, state, host, ctx) {
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

  /*
   * The form is built over the DRAFT when one is outstanding, so the fields an
   * author already filled in keep showing what they typed after a re-render -
   * a selection that went away and came back, an edit to a different block, an
   * undo elsewhere in the document. Without this the draft would accumulate
   * correctly and the screen would still show the stored config, which is the
   * same lie the bug reported, one layer further in.
   *
   * The findings are the document's, computed against the STORED config. That
   * is honest rather than convenient: they are what the canvas and the
   * findings panel are showing, and a draft that has not been offered to the
   * gate yet has no findings of its own. The refusal the gate DID return is
   * rendered separately, under the field, by `markRefused`.
   */
  const draftConfig = ctx.drafts.read(node.id, node.config);
  const formNode = draftConfig === node.config ? node : { ...node, config: draftConfig };

  const form = configFormFor(state.session.registry, formNode, state.findings);

  if (form.readOnly) {
    mount.replaceChildren(...readOnlyConfig(form));
    return;
  }

  /*
   * There used to be a `form.empty` arm here, reading "This block type
   * declares no configuration of its own." It is gone with sb-jvz: the
   * editor injects `label` into every resolvable type's schema, so every
   * resolvable block has at least that one field to edit and the empty arm
   * became unreachable. `core.sequence` and `core.group` are the types that
   * used to land in it, and naming your sequence is the thing an author most
   * wanted to do there. The read-only arm above still handles decision 12,
   * which is the case that genuinely has no form.
   */
  const memo = focusMemo(mount);
  const scope = { ...ctx, mount };

  mount.replaceChildren(
    el(
      "div",
      { class: "sb-form", "data-pending-config": String(ctx.drafts.pending(node.id)) },
      [
        pendingNotice(form, host, scope),
        ...form.fields.map((field) => fieldElement(field, form, host, scope)),
      ]
    )
  );

  restoreFocus(mount, memo);
}

/* ------------------------------------------------ the uncommitted-edits affordance */

/*
 * sb-5ow's affordance. A draft that accumulates silently is worse than the bug
 * it fixes: the author would type two fields, see no revision move, and have
 * no way to tell "held, waiting for the rest" from "dropped on the floor".
 *
 * So the pane says which fields are outstanding, says WHY nothing is stored
 * yet in the vocabulary of the gate, and offers the one gesture that is
 * otherwise unreachable - throwing the draft away and going back to what the
 * document actually holds. The discard is not undo: a draft was never on the
 * undo stack, because it was never a command.
 */
function pendingNotice(form, host, scope) {
  if (!scope.drafts.pending(form.blockId)) return null;

  const stored = storedConfig(host, form.blockId);
  const keys = pendingKeys(scope.drafts.read(form.blockId, stored), stored);
  const named = keys.map((key) => labelForKey(form, key));

  const discard = el("button", {
    class: "sb-button sb-button--quiet sb-form__pending-discard",
    type: "button",
    text: "Discard edits",
  });

  discard.addEventListener("click", () => {
    scope.drafts.clear(form.blockId);
    scope.refresh();
  });

  return el("div", { class: "sb-form__pending", "data-refusal-scope": "form", role: "status" }, [
    el("div", { class: "sb-form__pending-head" }, [
      el("span", { class: "sb-chip sb-chip--pending", text: "not stored yet" }),
      el("div", { class: "sb-topbar__spacer" }),
      discard,
    ]),
    el("p", {
      class: "sb-form__pending-text",
      text:
        named.length === 0
          ? "This block has edits that have not been stored yet."
          : `${named.join(", ")} ${named.length === 1 ? "has" : "have"} been edited but not stored. ` +
            "A config is stored whole and only when it validates, so keep filling the form in - " +
            "everything you have typed lands as one edit the moment the block is valid.",
    }),
  ]);
}

/*
 * Re-draws the notice WITHOUT a re-render, which is the constraint the whole
 * config pane is built under: a refusal must not replace the controls, or the
 * text the author is standing in disappears. See the file header.
 */
function syncPendingNotice(form, host, scope) {
  const container = scope.mount?.querySelector(".sb-form");
  if (!container) return;

  for (const stale of container.querySelectorAll(".sb-form__pending")) stale.remove();

  container.dataset.pendingConfig = String(scope.drafts.pending(form.blockId));

  const notice = pendingNotice(form, host, scope);
  if (notice) container.prepend(notice);
}

/*
 * The field label for a config key, falling back to the key itself. A key with
 * no field is possible - a draft can carry a value the type stopped declaring
 * - and naming it raw beats dropping it from the sentence.
 */
function labelForKey(form, key) {
  return form.fields.find((field) => field.key === key)?.label ?? key;
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

function fieldElement(field, form, host, scope) {
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

  const commit = (value) => commitField(field, form, host, scope, wrapper, value);

  wrapper.append(control(field, id, commit, host, form));

  // ADR-0005 decision 11: "a `:config` finding renders inline beneath its
  // field". Routed by the anchor's key, which is the key `validate_config/1`
  // reports against - the reason `core.branch` keys an arm by its slot name.
  //
  // sb-e2x: a map control has already drawn the findings that name one of its
  // rows, on that row, and hands back `fieldFindings` for what is left. Every
  // other control has no `fieldFindings` and renders the whole set here, which
  // is exactly the behaviour this loop had before.
  for (const finding of field.fieldFindings ?? field.findings) {
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
    case "map":
      return mapControl(field, id, commit);
    case "expression":
      return textControl(field, id, commit, { mono: true, placeholder: "an expression" });
    default:
      // Also where a decimal lands: ADR-0001 decision 6 forbids floats in
      // config, so a decimal is a `string` field holding "12.50", and the
      // text control stores and round-trips it unchanged.
      return textControl(field, id, commit, {});
  }
}

/*
 * `placeholder` here is the CONTROL TYPE's hint - what any expression field
 * should say, what any bare string field should say (nothing). sb-ed7: a
 * field that declares its own wins over it, because a declared hint is about
 * that one field and a control-type hint is a fallback for every field that
 * did not bother. The editor's injected `label` field is the only declarer
 * today; this code does not know that, and does not name a key or a type.
 */
function textControl(field, id, commit, { mono = false, placeholder = "" }) {
  const hint = field.placeholder ?? placeholder;

  const input = el("input", {
    class: mono ? "sb-input sb-input--mono" : "sb-input",
    type: "text",
    id,
    value: field.value === undefined || field.value === null ? "" : String(field.value),
    placeholder: hint,
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

  // An ABSENT optional whose type declares a default is not "no answer" - the
  // block behaves as the default, and every other surface already reads it
  // that way (the canvas draws `core.parallel`'s join marker from
  // `configGet(config, "complete", "all")` whether or not the key is stored).
  // Left alone the control renders EMPTY, because no option matches `""`, and
  // a blank select next to a filled-in form says "you have not answered this"
  // about a field that is in fact answered. Found by looking at it: sb-dxs
  // added the first optional select in the spike and routed the blank here.
  //
  // The placeholder is `disabled`, so it can be READ but not chosen. Choosing
  // it would have to mean "go back to storing nothing", and for this field
  // that is not the same edit: `complete` reads through its default for an
  // absent key and refuses a stored `null` (ADR-0001 decision 6), so there is
  // no value the control could commit to get absence back. Naming the state
  // is the whole fix; authoring over it is what the real options are for.
  //
  // It borrows the declared choice's own label rather than restating the
  // default in words of its own - the same field should not be described
  // twice in one menu.
  if (field.value === undefined && field.default !== undefined) {
    const declared = field.choices.find((choice) => choice.value === field.default);

    select.prepend(
      el("option", {
        value: "",
        disabled: "",
        text: `${declared ? (declared.label ?? declared.value) : field.default} (default)`,
      })
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

/*
 * sb-e2x's key/path row control, for the proposed `{ map: T }` field type.
 *
 * Two columns and three gestures - rename a key, edit a value, remove a row -
 * plus "add row". There is deliberately no reorder: a map has no row order, and
 * a control that offered to change one would be promising the author something
 * the document cannot store. The list control's ordinals are gone for the same
 * reason; the key IS the row's name.
 *
 * Nothing here knows what field it is drawing. `keyLabel` and `valueLabel` come
 * off the declaration, the row findings come off `validate_config/1` routed by
 * `row` in `panes.js`, and the value control is `controlFor(field.type.map)` -
 * so `core.invoke` and `core.subchart` get this control by declaring the type,
 * and a host type that declares it gets the same one.
 *
 * A key commits on `change`, which is blur: rows sort by key, so committing per
 * keystroke would make a row jump out from under the cursor mid-word.
 */
function mapControl(field, id, commit) {
  // The map as the form last derived it. `fromEntries` defines own properties
  // rather than assigning them, so a `"__proto__"` row is a key here and not a
  // prototype - the same rule `writeAtPath` states for a path segment.
  const current = () =>
    Object.fromEntries(field.rows.map((row) => [row.key, row.value]));

  const list = el("div", { class: "sb-rows sb-rows--map", id });

  list.append(
    el("div", { class: "sb-rows__head" }, [
      el("span", { class: "sb-rows__head-cell", text: field.keyLabel }),
      el("span", { class: "sb-rows__head-cell", text: field.valueLabel }),
      el("span", { class: "sb-rows__head-spacer" }),
    ])
  );

  for (const row of field.rows) {
    list.append(mapRow(field, row, current, commit));
  }

  if (field.rows.length === 0) {
    list.append(el("p", { class: "sb-rows__empty", text: "No rows yet." }));
  }

  const unnamed = field.rows.some((row) => row.key === "");
  const add = el("button", {
    class: "sb-button sb-button--quiet sb-rows__add",
    type: "button",
    text: "Add row",
    title: unnamed ? `Name the empty ${field.keyLabel.toLowerCase()} first` : "",
  });

  // A map cannot hold two unnamed rows. Said with a disabled button and a
  // title rather than with a click that appears to do nothing.
  add.disabled = unnamed;
  add.addEventListener("click", () => commit(addMapRow(current())));

  return el("div", { class: "sb-field__control" }, [list, add]);
}

function mapRow(field, row, current, commit) {
  const name = row.key === "" ? "unnamed row" : row.key;

  const key = el("input", { class: "sb-input sb-rows__input sb-rows__key", type: "text" });
  key.value = row.key;
  key.setAttribute("aria-label", `${field.keyLabel} for ${name}`);

  const value = el("input", { class: "sb-input sb-rows__input", type: "text" });
  value.value = row.value === undefined || row.value === null ? "" : String(row.value);
  value.setAttribute("aria-label", `${field.valueLabel} for ${name}`);

  const wrapper = el("div", { class: "sb-rows__row", "data-row-key": row.key }, [
    key,
    value,
    rowButton("×", `Remove ${name}`, false, "remove", () =>
      commit(removeMapRow(current(), row.key))
    ),
  ]);

  key.addEventListener("change", () => {
    const attempted = key.value.trim();
    const renamed = renameMapRow(current(), row.key, attempted);

    if (renamed === null) {
      // The one gesture a map makes destructive, refused where the author can
      // see it: nothing is stored and the old key goes back in the box.
      key.value = row.key;
      collision(wrapper, attempted);
      return;
    }

    commit(renamed);
  });

  value.addEventListener("change", () =>
    commit(setMapValue(current(), row.key, coerceRow(field.valueType, value.value)))
  );

  for (const finding of row.findings ?? []) {
    wrapper.append(
      el("p", {
        class: "sb-field__finding sb-rows__finding",
        "data-severity": finding.severity ?? "error",
        text: finding.message,
      })
    );
  }

  return wrapper;
}

function collision(wrapper, key) {
  for (const stale of wrapper.querySelectorAll("[data-collision]")) stale.remove();

  wrapper.append(
    el("p", {
      class: "sb-field__finding sb-rows__finding",
      "data-severity": "error",
      "data-collision": "true",
      text: `Another row is already named "${key}", so the rename was not stored.`,
    })
  );
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

/* ========================================================== condition pane */

/*
 * The Condition tab: the selected block's condition-bearing fields, shown as
 * source rather than as a form control.
 *
 * ## Why this is not just the config form's expression control again
 *
 * The config form renders an expression as a one-line mono `<input>`, which is
 * right for a form: it sits in a column of other fields and it must not tower
 * over them. A condition read on its own is a different job - it is the one
 * value in a workflow document an author will get wrong, and reading it is most
 * of the work. So this pane gives it the whole width, tokenizes it, and says
 * which of the paths it names the datamodel actually declares. Both write
 * through the SAME `:update_config` command path, so an edit here is one undo
 * step exactly like an edit there, and the two never disagree about what is
 * stored.
 *
 * ## Display first, edit on request
 *
 * The default state is the highlighted, non-editable rendering, because the
 * paths in it are the cross-pane affordance - a `<textarea>` cannot have a
 * clickable token inside it, and making the path clickable is worth more than
 * making the caret land one click sooner. "Edit" swaps in a monospace textarea
 * over the same value; `change` commits it, which is decision 9's boundary and
 * the reason four typed characters are one undo step.
 *
 * ## Known and unknown, not valid and invalid
 *
 * A path the datamodel declares gets a quiet affirmative underline; one it does
 * not gets a dotted advisory one and a line naming it. This is a STATIC LOOKUP
 * and nothing here evaluates anything (D4: the real evaluator is stretch-only).
 * A host may legitimately carry values its datamodel document does not
 * describe, so an unknown path is a question and never an error - which is why
 * it is not routed through the findings machinery, where every entry is a claim
 * that something is wrong.
 */

function renderCondition(mount, state, host, ctx) {
  if (!mount) return;

  if (!state?.session) {
    mount.replaceChildren(
      el("p", { class: "sb-empty", text: "Load a document and select a block to see its condition." })
    );
    return;
  }

  const node = selected(state.session);

  if (!node) {
    mount.replaceChildren(
      el("p", {
        class: "sb-empty",
        text: "Select a block on the canvas to see the conditions it carries.",
      })
    );
    return;
  }

  // Over the draft too (sb-5ow). The condition surface edits the same block's
  // config through the same command, so a pane that read the stored config
  // while the config pane read the draft would give the same block two
  // different answers about what it currently says.
  const draftConfig = ctx.drafts.read(node.id, node.config);
  const formNode = draftConfig === node.config ? node : { ...node, config: draftConfig };

  const form = configFormFor(state.session.registry, formNode, state.findings);
  const fields = conditionFields(form);

  if (fields.length === 0) {
    mount.replaceChildren(...conditionEmptyState(form));
    return;
  }

  const index = host.datamodel?.index ?? new Map();

  mount.replaceChildren(
    el("div", { class: "sb-conditions" }, [
      ...tableAffordance(node.id, host),
      ...fields.map((field) => conditionElement(field, form, host, index, { ...ctx, mount })),
    ])
  );
}

/*
 * The anchored open-from-condition affordance (sb-054).
 *
 * The truth table for a condition now lives in the bottom drawer, and this is
 * the way in from the surface an author is standing on when they want it: they
 * are reading a condition, they want to know what it answers for which inputs,
 * and the drawer is one press away rather than a tab strip and a sub-view
 * away.
 *
 * ONE button for the block, not one per field. A branch's arms are separate
 * condition fields and a single table covers all of them - its columns ARE the
 * arms - so a button per field would be three buttons opening the same table.
 *
 * It is rendered only when a table exists. A button that opens a drawer saying
 * "nothing here" is the affordance teaching an author to stop pressing it, and
 * the drawer's own empty states are for arriving there some other way.
 */
function tableAffordance(blockId, host) {
  const count = host.tables?.countFor?.(blockId) ?? 0;
  if (count === 0) return [];

  const button = el("button", {
    class: "sb-button sb-button--quiet sb-condition__tables",
    type: "button",
    text: count === 1 ? "Truth table" : `${count} truth tables`,
  });

  button.addEventListener("click", () => host.tables.open(blockId));

  return [
    el("div", { class: "sb-condition__tables-bar" }, [
      el("span", {
        class: "sb-hint",
        text: "Recorded cases for this block's conditions:",
      }),
      el("div", { class: "sb-topbar__spacer" }),
      button,
    ]),
  ];
}

/*
 * The empty state does the second half of its job: an author who selected the
 * wrong block needs to know where conditions DO live, and "no condition" alone
 * teaches them nothing. The unresolvable case gets its own sentence, because
 * "carries no condition" would be a false statement about a block whose stored
 * bytes may well hold one - decision 12 keeps them, and there is no schema here
 * to say which key it is.
 */
function conditionEmptyState(form) {
  if (form?.readOnly) {
    return [
      el("p", {
        class: "sb-empty",
        text: `This block's type is not registered here, so nothing declares which of its stored values is a condition. Its bytes are preserved and shown read-only on the Config tab.`,
      }),
    ];
  }

  return [
    el("p", { class: "sb-empty", text: "This block carries no condition." }),
    el("p", {
      class: "sb-hint sb-condition__where",
      text: "Conditions live on a branch's arms - one per arm, deciding which way the chart goes - and on the guarded interrupt rules that sit on a group's secondary rail. Select one of those to read or edit its condition here.",
    }),
  ];
}

function conditionElement(field, form, host, index, scope) {
  const source = typeof field.value === "string" ? field.value : "";
  const tokens = annotateCondition(source, index);
  const paths = conditionPaths(source, index);
  const unknown = paths.filter((one) => !one.known);

  const box = el("section", { class: "sb-condition", "data-field-key": field.key });

  const edit = el("button", {
    class: "sb-button sb-button--quiet sb-condition__edit",
    type: "button",
    text: source === "" ? "Write a condition" : "Edit",
  });

  box.append(
    el("header", { class: "sb-condition__head" }, [
      el("h4", { class: "sb-condition__label", text: field.label }),
      el("span", { class: "sb-condition__key", text: field.key }),
      el("div", { class: "sb-topbar__spacer" }),
      edit,
    ])
  );

  const surface = el("div", { class: "sb-condition__surface" });

  // Same funnel as the config pane's fields, so a condition typed into a block
  // whose other required fields are still empty accumulates into the same
  // draft rather than being refused and lost (sb-5ow).
  const commit = (value) => commitField(field, form, host, scope, box, value);

  function showEditor() {
    const input = el("textarea", {
      class: "sb-input sb-input--mono sb-condition__input",
      rows: "3",
      spellcheck: "false",
      "aria-label": field.label,
    });
    input.value = source;

    // No completion, by settled input 3. The one keyboard nicety kept is that
    // Escape abandons the edit and returns to the reading view, because a
    // surface an author opened by accident should close the way every other
    // one does.
    input.addEventListener("keydown", (event) => {
      if (event.key !== "Escape") return;
      event.stopPropagation();
      showDisplay();
    });

    input.addEventListener("change", () => {
      if (!commit(input.value)) input.focus();
    });

    surface.replaceChildren(input);
    surface.dataset.mode = "edit";
    input.focus();
    input.setSelectionRange(input.value.length, input.value.length);
  }

  function showDisplay() {
    surface.replaceChildren(displayElement(tokens, source, host));
    surface.dataset.mode = "read";
  }

  edit.addEventListener("click", () => {
    if (surface.dataset.mode === "edit") showDisplay();
    else showEditor();
  });

  showDisplay();
  box.append(surface);

  for (const finding of field.findings) {
    box.append(
      el("p", {
        class: "sb-field__finding",
        "data-severity": finding.severity ?? "error",
        text: finding.message,
      })
    );
  }

  box.append(pathSummary(paths, unknown, index, host));

  return box;
}

/*
 * The tokens, rendered. Every token contributes its own text verbatim and
 * nothing is rebuilt from parts, so what is on screen is byte-for-byte the
 * stored condition - which is the property that makes a coloured rendering
 * safe to trust as a reading of the document.
 */
function displayElement(tokens, source, host) {
  if (source.trim() === "") {
    return el("p", {
      class: "sb-condition__blank",
      text: "No expression yet. This arm cannot be taken until it has one.",
    });
  }

  const code = el("pre", { class: "sb-code sb-condition__code" });

  for (const token of tokens) {
    if (token.kind !== "path") {
      code.append(
        el("span", { class: "sb-tok", "data-tok": token.kind, text: token.text })
      );
      continue;
    }

    // A path is a button: revealing it in the datamodel is a real navigation
    // gesture, so it answers Enter and Space and lands in the tab order, the
    // same way a findings row does.
    const button = el("button", {
      class: "sb-tok sb-tok--path",
      type: "button",
      "data-tok": "path",
      "data-known": String(token.known),
      title: token.known
        ? `${token.entry.scopeLabel} · ${token.entry.type} · click to reveal in the datamodel`
        : "not declared in the datamodel document",
      text: token.text,
    });

    button.addEventListener("click", () => host.datamodel?.reveal?.(token.path));
    code.append(button);
  }

  return code;
}

/*
 * The footer: what this condition depends on, and which of it the datamodel has
 * never heard of. Counting rather than only colouring, because the colour on a
 * dotted underline is exactly the sort of thing a reader is not sure they saw.
 */
function pathSummary(paths, unknown, index, host) {
  const foot = el("div", { class: "sb-condition__paths" });

  if (paths.length === 0) {
    foot.append(el("p", { class: "sb-hint", text: "This condition names no datamodel path." }));
    return foot;
  }

  foot.append(
    el("p", {
      class: "sb-condition__paths-title",
      text: `${paths.length} path${paths.length === 1 ? "" : "s"} referenced${
        index.size === 0 ? " · no datamodel document loaded" : ""
      }`,
    })
  );

  const list = el("ul", { class: "sb-condition__path-list" });

  for (const one of paths) {
    const button = el("button", {
      class: "sb-condition__path",
      type: "button",
      "data-known": String(one.known),
      text: one.path,
      title: one.known ? `Reveal ${one.path} in the datamodel` : `${one.path} is not declared`,
    });

    button.addEventListener("click", () => host.datamodel?.reveal?.(one.path));

    list.append(
      el("li", {}, [
        button,
        one.known
          ? el("span", { class: "sb-condition__path-type", text: typeOf(one.entry) })
          : el("span", { class: "sb-condition__path-type", text: "not declared" }),
      ])
    );
  }

  foot.append(list);

  if (unknown.length > 0 && index.size > 0) {
    foot.append(
      el("p", {
        class: "sb-condition__advisory",
        text: `${unknown.map((one) => one.path).join(", ")} ${
          unknown.length === 1 ? "is" : "are"
        } not declared in the datamodel document. That is not necessarily wrong - a host can carry values it has not described - but it is the usual shape of a typo.`,
      })
    );
  }

  return foot;
}

const typeOf = (entry) =>
  entry.type === "list" && entry.itemType ? `list of ${entry.itemType}` : entry.type;

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
function storedConfig(host, blockId) {
  const node = findBlock(host.state().session.document, blockId);
  return node ? node.config : {};
}

/*
 * The config the NEXT edit is written through: the draft when one is
 * outstanding, the stored config otherwise. sb-5ow, and the whole fix in one
 * function - the old code read `storedConfig` here unconditionally, which is
 * why filling the second required field discarded the first.
 */
function editBase(host, scope, blockId) {
  return scope.drafts.read(blockId, storedConfig(host, blockId));
}

/*
 * One field edit, offered to ADR-0005 decision 9's gate as a WHOLE config.
 *
 * The draft is cleared BEFORE the gate is asked, not after. `host.updateConfig`
 * re-renders synchronously when the edit lands, and that re-render reads the
 * store; a draft still sitting there would draw the "not stored yet" notice
 * over a config that had just been stored. Clearing first and re-staging on a
 * refusal is the ordering that makes the accepted path draw exactly once.
 *
 * The refusal path deliberately does NOT re-render (see the file header), so
 * the notice is patched in place rather than rebuilt with the form.
 *
 * Exported for `dev/selftest.html`. It is the one piece of this file that is
 * not "turn a value into an element", and the accumulation bug it fixes is a
 * sequencing bug across two edits - the kind a rendered page demonstrates and
 * an assertion pins down. `wrapper` needs only `dataset`, `append` and
 * `querySelectorAll`, and `scope.mount` may be `null`, so a caller can drive
 * it with a stub.
 */
export function commitField(field, form, host, scope, wrapper, value) {
  const config = writeAtPath(editBase(host, scope, form.blockId), field.path, value);

  scope.drafts.clear(form.blockId);

  const refusal = host.updateConfig(form.blockId, config);

  if (refusal) {
    scope.drafts.stage(form.blockId, config);
    markRefused(wrapper, refusal, field.key);
    syncPendingNotice(form, host, scope);
  }

  return refusal === null;
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
