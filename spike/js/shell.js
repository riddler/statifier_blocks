/*
 * spike/js/shell.js - the shell frame's own behaviour, and nothing else.
 *
 * Two things only: the inspector tab strip, and the theme selector that
 * proves the three-theme mechanism from one attribute. The editor's real
 * modules (document model, edit algebra, drop targets, layout, render, the
 * panels) are later beads and do not belong here.
 *
 * Kept as an ES module served straight from disk. No build step, no bundler,
 * no dependency, ever.
 */

const root = document.getElementById("sb-spike");

/* ------------------------------------------------------------------ tabs */

const tabs = Array.from(document.querySelectorAll('[role="tab"]'));

function selectTab(tab) {
  for (const candidate of tabs) {
    const selected = candidate === tab;
    const panel = document.getElementById(
      candidate.getAttribute("aria-controls")
    );

    candidate.setAttribute("aria-selected", String(selected));
    candidate.tabIndex = selected ? 0 : -1;

    if (panel) {
      panel.hidden = !selected;
    }
  }
}

for (const [index, tab] of tabs.entries()) {
  tab.tabIndex = tab.getAttribute("aria-selected") === "true" ? 0 : -1;

  tab.addEventListener("click", () => selectTab(tab));

  // Arrow-key movement is what makes a tab strip a tab strip to a screen
  // reader; it costs four lines and the shell is the right place to get it
  // right once.
  tab.addEventListener("keydown", (event) => {
    const step =
      event.key === "ArrowRight" ? 1 : event.key === "ArrowLeft" ? -1 : 0;
    if (step === 0) return;

    event.preventDefault();
    const next = tabs[(index + step + tabs.length) % tabs.length];
    selectTab(next);
    next.focus();
  });
}

/* ----------------------------------------------------------------- theme */

const themeSelect = document.getElementById("sb-theme");

if (root && themeSelect) {
  themeSelect.addEventListener("change", () => {
    if (themeSelect.value === "") {
      root.removeAttribute("data-sb-theme");
    } else {
      root.setAttribute("data-sb-theme", themeSelect.value);
    }
  });
}
