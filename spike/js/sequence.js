/*
 * spike/js/sequence.js - the generation token an async loader needs so that
 * the LAST REQUEST wins rather than the last response.
 *
 * The shell's document loader is async: it fetches a fixture, decodes it, and
 * only then writes the canvas, the chips and the title. Two switches inside
 * one frame therefore race, and without a guard the fetch that happens to
 * resolve last is the one that paints - so the picker can read
 * `signup-wizard` while the canvas shows `card-processing`, and stay that way
 * until the next switch. Spaced switches always looked right, which is why
 * this went unnoticed for a wave (sb-3kf, from sb-ea4's F5).
 *
 * The fix is the smallest one that is also honest about what it guarantees:
 * every load takes a token before its first `await`, and after every `await`
 * it asks whether that token is still the current one. A stale load discards
 * its own result and touches nothing. It does not cancel the fetch - there is
 * no cancellation here, and pretending otherwise would be a lie about the
 * network - it only refuses to let a superseded answer reach the DOM.
 *
 * Pure and DOM-free on purpose: the interesting half of the guard is the
 * token arithmetic, and keeping it here is what lets `dev/selftest.html`
 * assert it without a fetch, a timer or a stub.
 */

/*
 * A monotonic generation counter. `begin()` opens a new generation and hands
 * back its token; `isCurrent(token)` answers whether that generation is still
 * the one in force.
 *
 * Tokens are compared with `===` against the current generation, so a token
 * from an earlier generation is stale, and a token from another sequence is
 * foreign and reads as stale too. Before the first `begin()` the current
 * generation is `null`, which no issued token can equal - so a fresh sequence
 * declares nothing current rather than accidentally blessing `0`. There is no
 * `end()`: a generation is superseded, never finished, which is exactly the
 * lifecycle a fire-and-forget loader has.
 */
export function createSequence() {
  let issued = 0;
  let current = null;

  return {
    begin() {
      issued += 1;
      current = issued;
      return current;
    },

    isCurrent(token) {
      return token === current;
    },

    // Read-only, for assertions and for a debugger. Nothing in the shell
    // branches on it.
    get generation() {
      return current;
    },
  };
}
