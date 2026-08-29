/*
 * spike/js/palette-pane.js - the left pane, rendered from the registry.
 *
 * The palette used to be hand-written markup in `index.html`, which meant the
 * list an author reads and the registry the canvas validates against were two
 * separate transcriptions of the same vocabulary. They had already drifted:
 * seven `core.*` entries and three `myapp.*` ones were listed, while the shell
 * registers eighteen types. This file renders from `paletteView`, so the pane
 * shows exactly what the editor knows and a host that registers a type gets a
 * palette entry for free - which is ADR-0002 decision 5's whole promise.
 *
 * What it must not break: every entry stays a `[data-block-type]` element
 * carrying an `.sb-palette__name`, because that is the contract `interact.js`
 * reads to start a palette drag. Re-rendering the list on every keystroke is
 * safe against that listener for the same reason the canvas's is - the
 * listener is delegated from the pane, never bound to an entry.
 */

import { paletteView } from "./panes.js";
import { el, iconElement } from "./render.js";
import { accentTokenFor, blockAccentStyle } from "./theme.js";

/**
 * Mounts the palette into `mount` and returns a handle.
 *
 * `onQueryChange` is optional and exists only so a caller can observe the
 * filter; the pane owns the query itself, because a search box whose value
 * lives somewhere else is a search box that fights the author's cursor.
 */
export function createPalettePane({ mount, registry, onQueryChange = () => {} }) {
  let query = "";

  const search = el("input", {
    class: "sb-input sb-palette__search",
    type: "search",
    placeholder: "Search blocks",
    "aria-label": "Search block types",
    "aria-controls": "sb-palette-results",
  });

  const count = el("p", { class: "sb-palette__count", role: "status" });
  const results = el("div", { class: "sb-palette__results", id: "sb-palette-results" });

  const hint = el("p", {
    class: "sb-palette__hint",
    text: "Drag an entry onto the canvas, or use a + on any slot.",
  });

  /*
   * The narrow-layout strip (sb-3l1, ruling 7A): "below 780px the palette
   * collapses to a strip (search + '+') that opens as a sheet, so the
   * inspector gets the full row".
   *
   * Which of the two arrangements is on screen is CSS's call, not this
   * file's - it is a container query on the shell, and a JS breakpoint beside
   * it would be a second source of truth that drifts the first time one of
   * them is edited. All JS owns is whether the sheet is open, written as
   * `data-sheet` on the pane and read by the query's rules. Above 780 the
   * strip is `display: none` and the attribute means nothing, which is why it
   * is safe to leave it set.
   *
   * The shipped editor's PaletteBrowser (sb-832) renders the same two
   * elements under the same class names, so the graduation this spike feeds
   * is a transcription rather than a re-derivation.
   */
  const stripPlus = el("span", { class: "sb-palette__strip-plus", "aria-hidden": "true", text: "+" });

  const strip = el("button", {
    class: "sb-palette__strip",
    type: "button",
    "aria-expanded": "false",
    "aria-controls": "sb-palette-body",
  });

  strip.append(el("span", { class: "sb-palette__strip-label", text: "Blocks" }), stripPlus);

  const body = el("div", { class: "sb-palette__body", id: "sb-palette-body" }, [
    el("div", { class: "sb-palette__search-row" }, [search]),
    count,
    results,
    hint,
  ]);

  function setSheet(open) {
    mount.dataset.sheet = open ? "open" : "closed";
    strip.setAttribute("aria-expanded", String(open));
    if (open) search.focus();
  }

  strip.addEventListener("click", () => setSheet(mount.dataset.sheet !== "open"));

  mount.replaceChildren(strip, body);
  setSheet(false);

  function draw() {
    const view = paletteView(registry, query);

    count.textContent =
      view.query === ""
        ? `${view.total} block type${view.total === 1 ? "" : "s"}`
        : `${view.matched} of ${view.total} match “${view.query}”`;
    count.dataset.filtering = String(view.query !== "");

    results.replaceChildren(
      ...(view.empty ? [emptyState(view)] : view.groups.map(groupElement))
    );

    onQueryChange(view);
  }

  /*
   * An empty state that says what was searched for and offers the one gesture
   * that fixes it. An empty list with no words is the single most common way a
   * search box makes a user think a tool is broken rather than that they
   * mistyped, and it costs four elements not to do that.
   */
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
        text: `No block type matches “${view.query}”.`,
      }),
      el("p", {
        class: "sb-palette__empty-body",
        text: "Search matches a type's name, its description, and the keywords it declares.",
      }),
      clear,
    ]);
  }

  search.addEventListener("input", () => {
    query = search.value;
    draw();
  });

  draw();

  return {
    get query() {
      return query;
    },
    focusSearch() {
      search.focus();
    },
    /** Whether the narrow-layout sheet is open. Meaningless above 780, where
     * the strip that toggles it is not rendered. */
    get sheetOpen() {
      return mount.dataset.sheet === "open";
    },
    closeSheet() {
      setSheet(false);
    },
    redraw: draw,
  };
}

function groupElement(group) {
  return el("div", { class: "sb-palette__group" }, [
    el("h3", { class: "sb-palette__group-name" }, [
      el("span", { text: group.name }),
      el("span", { class: "sb-palette__group-count", text: String(group.entries.length) }),
    ]),
    el(
      "ul",
      { class: "sb-palette__entries" },
      group.entries.map((entry) => el("li", {}, [entryElement(entry)]))
    ),
  ]);
}

/*
 * One entry: an icon slot, the highlighted label, the plain-language caption
 * the descriptor declares, and - only when the entry matched on something the
 * author cannot see - a line saying which. `title` carries the type name, so
 * the machine-readable identity is one hover away without ever competing with
 * the caption for the reader's attention.
 */
function entryElement(entry) {
  const name = el("span", { class: "sb-palette__name" });

  for (const segment of entry.segments) {
    name.append(
      segment.match
        ? el("mark", { class: "sb-palette__match", text: segment.text })
        : document.createTextNode(segment.text)
    );
  }

  const text = el("span", { class: "sb-palette__text" }, [name]);

  if (entry.description) {
    text.append(el("span", { class: "sb-palette__description", text: entry.description }));
  }

  const hidden = entry.matchedOn.filter((where) => where === "keywords" || where === "type");

  if (entry.matchedOn.length > 0 && !entry.matchedOn.includes("label") && hidden.length > 0) {
    text.append(
      el("span", {
        class: "sb-palette__matched",
        text: hidden.includes("keywords") ? "matched a keyword" : "matched the type name",
      })
    );
  }

  /* The accent hook, written from the registry and from nothing else. The
   * attribute is the CSS's selector and the inline property is the binding;
   * a type that declares no token gets neither, which is what keeps a core
   * block's row exactly the row it was. */
  return el(
    "button",
    {
      class: "sb-palette__pick",
      type: "button",
      "data-block-type": entry.type,
      "data-sb-block-accent": accentTokenFor(entry),
      style: blockAccentStyle(entry),
      title: entry.type,
    },
    [el("span", { class: "sb-palette__icon" }, [iconElement(entry.icon)]), text]
  );
}
