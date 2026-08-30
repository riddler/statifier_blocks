### Changed

- An unresolvable block's card reads its type and one short reason; its
  findings and its stored config moved to the inspector, so the card is the
  same width as its siblings.
- The inspector's Block section shows an unresolvable block's stored config
  as canonical JSON, wrapping mid-token rather than spilling past the pane.
- The stored-config `<pre>` moved from the card to the inspector, and its class
  with it: `.sb-node__raw-config` is now `.sb-inspector__raw-config`. A host
  styling the old class should restyle the new one.
