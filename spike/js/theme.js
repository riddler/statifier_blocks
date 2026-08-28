/*
 * spike/js/theme.js - the pure half of theming.
 *
 * Two jobs, and neither of them touches the DOM:
 *
 *   1. The per-block-type accent hook. A block type may declare an accent
 *      TOKEN NAME in its palette entry; the renderer stamps that name onto
 *      the card and the palette row as a `--sb-block-accent` reference. The
 *      editor therefore never learns a type name, and a host restyles one
 *      of its own block types by declaring one more `--sb-*` property in its
 *      theme file - which is the whole bargain ADR-0005 decision 14 strikes,
 *      extended from "the editor" to "one block type in it".
 *
 *   2. The audit arithmetic - contrast ratios and token coverage - that
 *      `dev/theme-audit.html` runs against the real stylesheets and that
 *      `dev/selftest.html` checks the logic of against fixtures. Themes are
 *      the one part of the spike where "it looks right on my screen" is the
 *      only test anyone ever runs; this file is what makes some of it
 *      machine-checkable instead.
 *
 * Nothing here reads a stylesheet from disk or from the document. Callers
 * pass text in and get values back, which is what lets the self-test cover
 * it without a network and without a browser paint.
 */

/* ==================================================== the block accent hook */

/*
 * What a descriptor is allowed to name. Deliberately narrow: the value is
 * interpolated into a `style` attribute, so anything that is not obviously a
 * custom-property name is refused rather than escaped. A host that mistypes
 * its token gets the default accent and a silent no-op, never an injection.
 *
 * `--sb-` rather than `--`, because the property has to survive alongside
 * whatever the host page's own custom properties are called, and the prefix
 * is the same one d14 already requires of every class the editor emits.
 */
const ACCENT_TOKEN = /^--sb-[a-z0-9]+(-[a-z0-9]+)*$/;

/** True when `name` is a custom-property name a block type may point at. */
export function isAccentToken(name) {
  return typeof name === "string" && ACCENT_TOKEN.test(name);
}

/**
 * The accent token a palette entry declares, or `null`.
 *
 * `null` is the ordinary case and means "use the editor's own accent". A
 * malformed name is also `null`: a typo in a host's registry must degrade to
 * the default, never to a broken card.
 */
export function accentTokenFor(entry) {
  const name = entry && typeof entry === "object" ? entry.accentToken : null;
  return isAccentToken(name) ? name : null;
}

/**
 * The inline `style` value that binds one element to its type's accent, or
 * `null` when the type declares none (in which case the element gets no
 * inline style at all and inherits the editor's default).
 *
 * The value is a `var()` REFERENCE, never a colour. That is what keeps the
 * theme in charge: the token the reference names is resolved by whichever
 * theme is active, so the same rendered DOM is warm under host-brand and
 * cool under dark without the renderer knowing either exists. The fallback
 * arm means a host that names a token and forgets to declare it still gets
 * the editor's accent rather than an unstyled card.
 */
export function blockAccentStyle(entry) {
  const token = accentTokenFor(entry);
  return token === null ? null : `--sb-block-accent: var(${token}, var(--sb-accent));`;
}

/* ============================================================== contrast */

/** sRGB channels 0..1 from a `#rgb` or `#rrggbb` string. Throws on garbage. */
export function channels(color) {
  const hex = String(color ?? "").trim().replace(/^#/, "");

  const full =
    hex.length === 3
      ? hex
          .split("")
          .map((c) => c + c)
          .join("")
      : hex;

  if (!/^[0-9a-fA-F]{6}$/.test(full)) throw new Error(`not a hex colour: ${color}`);

  return [0, 2, 4].map((at) => parseInt(full.slice(at, at + 2), 16) / 255);
}

/** WCAG relative luminance. */
export function relativeLuminance(color) {
  const [r, g, b] = channels(color).map((c) =>
    c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4
  );

  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/**
 * WCAG contrast ratio, 1..21, order-independent.
 *
 * Rounded to two places, because the numbers this produces are read by a
 * human against a threshold and 4.4999 printing as 4.5 while failing is the
 * kind of thing that costs an afternoon.
 */
export function contrastRatio(a, b) {
  const [high, low] = [relativeLuminance(a), relativeLuminance(b)].sort((x, y) => y - x);
  return Math.round(((high + 0.05) / (low + 0.05)) * 100) / 100;
}

/* ========================================================= token coverage */

/*
 * A deliberately small CSS reader. It finds `--sb-*: value;` declarations and
 * the selector of the block they sit in, and it knows nothing else about CSS
 * - no at-rules, no nesting, no shorthand. That is enough for tokens.css and
 * for a theme file, and a real parser here would be a dependency the spike
 * exists to avoid.
 *
 * Comments are stripped first, so a commented-out token is not a declared one
 * and a token NAME mentioned in prose does not count as a declaration.
 */
export function stripComments(css) {
  return String(css ?? "").replace(/\/\*[\s\S]*?\*\//g, "");
}

/**
 * `[{ selector, tokens: Map<name, value> }]`, one entry per rule block that
 * declares at least one `--sb-*` property, in source order.
 */
export function declarationBlocks(css) {
  const source = stripComments(css);
  const blocks = [];

  for (const match of source.matchAll(/([^{}]+)\{([^{}]*)\}/g)) {
    const selector = match[1].trim().replace(/\s+/g, " ");
    const tokens = new Map();

    for (const decl of match[2].matchAll(/(--sb-[a-z0-9-]+)\s*:\s*([^;]+);/g)) {
      tokens.set(decl[1], decl[2].trim());
    }

    if (tokens.size > 0) blocks.push({ selector, tokens });
  }

  return blocks;
}

/** Every `--sb-*` name declared anywhere in `css`. */
export function declaredTokens(css) {
  const names = new Set();
  for (const block of declarationBlocks(css)) for (const name of block.tokens.keys()) names.add(name);
  return names;
}

/** Every `--sb-*` name READ by a `var()` anywhere in `css`. */
export function usedTokens(css) {
  const names = new Set();
  for (const match of stripComments(css).matchAll(/var\(\s*(--sb-[a-z0-9-]+)/g)) names.add(match[1]);
  return names;
}

/**
 * The two lists a token surface can be wrong in.
 *
 *   undeclared  a structural rule reads a token nothing declares - a silent
 *               unstyled surface, and the failure mode a host hits first
 *   unused      a token is declared and nothing consumes it - a promise the
 *               surface makes and does not keep, which is worse than an
 *               absent token because a host will set it and see nothing
 *
 * `ignoreUnused` is for names a theme file is expected to declare for a
 * consumer that lives outside the stylesheets it was given (the per-block
 * accents the registry points at, for instance, which are read from an
 * inline `var()` reference the renderer writes).
 */
export function coverage({ tokensCss, structuralCss, ignoreUnused = [] }) {
  const declared = declaredTokens(tokensCss);
  const used = usedTokens(`${tokensCss}\n${structuralCss}`);
  const exempt = new Set(ignoreUnused);

  return {
    undeclared: [...used].filter((name) => !declared.has(name)).sort(),
    unused: [...declared].filter((name) => !used.has(name) && !exempt.has(name)).sort(),
  };
}

/**
 * Which tokens a theme block leaves at their default.
 *
 * Not every unset token is a defect - a theme that keeps the default radius
 * is making a choice - so this reports rather than judges, and the caller
 * decides which names it wanted covered. What it is FOR is the failure the
 * dark theme is one missed token away from at all times: a surface colour
 * that stays light because its token was never overridden.
 */
export function themeGaps({ baseCss, themeCss, only = null }) {
  const base = declaredTokens(baseCss);
  const covered = declaredTokens(themeCss);
  const wanted = only === null ? [...base] : [...base].filter((name) => only.includes(name));

  return wanted.filter((name) => !covered.has(name)).sort();
}

/**
 * True when the CSS is a PURE token override: every declaration it makes is
 * a `--sb-*` custom property. This is the rule themes/host-brand.css lives
 * under, and the one the spike would otherwise only be able to assert in a
 * comment.
 *
 * A structural declaration is any property that is not a custom property. A
 * theme that needs one has found a hole in the token surface, which is a
 * finding about tokens.css rather than a licence to write the rule.
 */
export function structuralDeclarations(css) {
  const source = stripComments(css);
  const found = [];

  for (const match of source.matchAll(/([^{}]+)\{([^{}]*)\}/g)) {
    const selector = match[1].trim().replace(/\s+/g, " ");

    for (const decl of match[2].matchAll(/([a-zA-Z-]+)\s*:\s*([^;]*);/g)) {
      if (!decl[1].startsWith("--")) found.push({ selector, property: decl[1] });
    }
  }

  return found;
}
