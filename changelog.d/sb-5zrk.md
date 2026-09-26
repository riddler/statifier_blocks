### Changed

- `core.sequence` declares `sentence/1`: its card line, and its name in `StatifierBlocks.Describe`'s lines, is "Run its steps in order" where it was the label "Sequence".
- `core.group` declares `sentence/1`: its card line, and its name in `StatifierBlocks.Describe`'s lines, is "Run interruptible steps" where it was the label "Group".
- `core.await` declares `sentence/1`: its card line, and its name in `StatifierBlocks.Describe`'s lines, is "Wait for <event>", followed by ", giving up after <timeout>" when a deadline is set, where it was the label "Wait for event".
