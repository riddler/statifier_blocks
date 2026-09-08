### Changed

- The compiled chart of every document holding an interruptible group changes:
  a group's two interrupt transitions, and the `<raise>` of the interrupt pair
  inside its rail, now carry that group's own emitted state id
  (`statifier_blocks.interrupt.resume.<group state id>`), so a stored compiled
  chart or a pinned chart identity for such a document must be re-captured. The
  spelling an author configures and the pair a host block type raises do not
  change: the salt is applied at emit, and a raise outside any rail is emitted
  unchanged. A railed composite can now be nested inside a resumable group's
  body without the two rails contending for one event name.
