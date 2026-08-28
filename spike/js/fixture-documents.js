/*
 * spike/js/fixture-documents.js - the spike's fixture documents, named once.
 *
 * There are now two things in the spike that have to know which documents
 * exist: the shell's document picker, which fetches
 * `fixtures/documents/<file>.json` and opens it, and `core.subchart`'s chart
 * reference, whose whole proposal is that an author PICKS a chart rather than
 * typing an identifier at it.
 *
 * Campaign D11 says the subchart picker offers only the spike's own fixture
 * documents. That could have been a hard-coded option list in
 * `proposed-core.js`, and it would have been wrong within one bead: the moment
 * a fixture document is added, renamed or dropped, the picker and the shell
 * disagree, and the disagreement renders as a chart reference that resolves to
 * nothing. So the list lives here, once, and both readers derive from it.
 *
 * ## The two names a fixture document has, and why both are here
 *
 *   - `file` is the loader's key: the basename under `fixtures/documents/`,
 *     the value the topbar `<select>` carries, and the `?doc=` parameter. It
 *     is a fact about where the file sits on disk.
 *   - `id` is the DOCUMENT's own id out of the ADR-0001 envelope. It is what
 *     `fixtures/runs.json` keys its sections by, and it is what a chart
 *     reference stores - a reference to a document, never to a filename.
 *
 * A real reference would not be either of these. Chart identity is
 * statifier-ex's (ADR-0052/0057), and a compiled child chart is identified by
 * that record's rules rather than by a block document id; the spike stores the
 * document id because that is the only identity a spike with no compiler has.
 * `proposed-core.js`'s compile sketch says so at the point it matters.
 *
 * Pure data and pure functions on purpose: `proposed-core.js` imports this and
 * must stay renderable outside a browser, so nothing here touches the DOM.
 */

/**
 * Every fixture document the spike ships, in the order the picker lists them.
 *
 *     [{ file, id, label }]
 */
export const fixtureDocuments = [
  { file: "card-processing", id: "bdoc_cp_demo", label: "Card processing" },
  { file: "signup-wizard", id: "bdoc_signup_demo", label: "Signup wizard" },
  { file: "signup-invitations", id: "bdoc_su_invites_demo", label: "Signup invitations" },
];

/** The document ids, for a validator that has to refuse everything else. */
export const fixtureDocumentIds = () => fixtureDocuments.map((doc) => doc.id);

/**
 * The `{ select: [{ value, label }] }` options a chart-reference field
 * declares - values are document ids, for the reason in the header.
 */
export const fixtureDocumentOptions = () =>
  fixtureDocuments.map((doc) => ({ value: doc.id, label: doc.label }));

/** One document's entry by its document id, or `null`. */
export const fixtureDocumentById = (id) =>
  fixtureDocuments.find((doc) => doc.id === id) ?? null;
