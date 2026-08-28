# Editor spike

**Status: exploratory. This is a laboratory, not the product.**

A pure client-side prototype of the `statifier_blocks` editor: plain HTML,
CSS, JavaScript and SVG, served from disk. No LiveView, no Elixir, no build
step, no bundler, and no external CSS or JS library.

It exists to work through layout, visual design, styling architecture and
panel composition on their own, without the round trip through a server-side
component tree. What it learns comes back as ADR amendments and as CSS and
DOM that graduate into `assets/`; the spike itself is never the shipped
editor.

## What it is not

- **Not part of the Hex package.** `mix.exs` lists the package's `files:`
  explicitly and `spike/` is not among them, so nothing here reaches a
  release tarball.
- **Not a second implementation of the editor.** ADR-0005's shipped
  architecture - server-side commands, one drag hook, function components
  over a view model - is untouched by anything in this directory.
- **Not authoritative.** Where this directory and an accepted ADR disagree,
  the ADR is the contract and the spike is an experiment that has not been
  written up yet.

## What it deliberately mirrors

So the learnings transfer rather than having to be re-derived:

- A nested **tree**, never a flat graph. Connector lines are *rendered* from
  adjacency and nesting; they are never *authored*.
- The ADR-0005 command algebra semantics: insert, remove, move,
  update_config, inverses for undo, per-slot drop validity, and the "+"
  button as the no-drag path.
- ADR-0005 d10 presentation metadata (`layout: :columns` for parallel lanes,
  a secondary slot style for interrupt rails). The editor never branches on
  a type name.
- ADR-0005 d11 findings: anchored, with count badges on collapsed groups.
- **ADR-0005 d14 theming**, which is the contract the styling here is built
  on and is stress-testing: every emitted class is prefixed `sb-`, and every
  colour, space, radius and drag treatment is a `--sb-*` custom property.

## Layout

```
spike/
  README.md      this file
  serve.rb       static file server, Ruby stdlib only
  index.html     the editor shell
  css/
    reset.css    scoped element reset (everything under .sb-spike)
    tokens.css   the --sb-* surface: light default, dark theme block
    editor.css   structure and default treatment, all sb- prefixed
    themes/
      host-brand.css   the third theme, as a pure token override
  js/
    document.js    the block document model, mirrored (ADR-0001)
    palette.js     the block-type registry + the core.* vocabulary (ADR-0002)
    demo-types.js  the host vocabulary the demo documents are written against
    edit.js        the command algebra and undo stacks (ADR-0005 d2-d4)
    targets.js     drop-target enumeration (ADR-0005 d5)
    layout.js      the layout model, and connector geometry as pure functions
    render.js      the layout model as DOM, and the connectors as SVG
    shell.js       the shell's own behaviour: tabs, theme, document loader
  fixtures/
    documents/     the two demo documents
    datamodel.json typed, scoped datamodel for the panel and the conditions
  dev/
    selftest.html  browser-run assertions over every pure module above
```

Open `index.html?doc=signup-wizard` to load a named fixture directly; the
default is `card-processing`, the deep one.

## The canvas, in two passes

`layout.js` turns `{document, registry}` into a layout tree - a shape and an
arrangement per block, its slots partitioned into primary and secondary, and
each arm's guard read off the block type's config schema. `render.js` emits
that tree as nested DOM and *then* measures what the browser laid out and
draws the connectors over it. Nothing computes a coordinate: the browser does
the layout, and the connectors are derived from where the cards actually
landed.

Three derivations do the structural work, and every one of them reads
ADR-0005 decision 10's presentation metadata rather than a type name:

| Rendering | Derived from |
|---|---|
| primary slots side by side | `layout: :columns`, or more than one primary slot |
| lanes ("all of") vs arms ("one of") | `layout: :columns` distinguishes the two |
| an interrupt rail with exit edges | a slot whose `slot_style` is `:secondary` |
| a boundary box around a body | the same - a rule needs a region with an edge |
| an arm's condition pill | an `:expression` config field keyed by the slot name |
| a compact chip instead of a card | a leaf whose whole schema is one `:duration` |

Later waves add `js/` modules proper (document model, palette registry, edit
algebra, drop targets, layout and connector routing, rendering, panels) and a
`fixtures/` directory of demo documents. They are not scaffolded here: an
empty directory is not committable, and a placeholder file that does nothing
is worse than its absence.

## The three themes

One mechanism, exercised three ways:

| Theme | How it is selected |
|---|---|
| Light | the default, declared on `.sb-spike` |
| Dark | `data-sb-theme="dark"` on the container or any ancestor |
| Host brand | `data-sb-theme="host-brand"`, from `css/themes/host-brand.css` |

`host-brand.css` is the proof, and it holds itself to a hard rule: a theme
file may set `--sb-*` properties and may do nothing else. No structural rule,
no `sb-` class, no layout. If a restyle turns out to need something that file
is not allowed to do, that is a finding about the token surface and the fix
goes in `tokens.css`.

The theme selector in the top bar switches between all three at runtime.

## Serving it

The spike is served as static files. Anything that serves this directory over
HTTP will do; opening `index.html` from the filesystem will not, because the
shell is an ES module and `file://` blocks module loading.

From inside `spike/`:

```sh
ruby serve.rb . 8642
```

Then open <http://localhost:8642>.

`serve.rb` is about fifty lines of Ruby stdlib `socket`: it serves files under
the document root it is given, refuses paths that escape it, and sends
`Cache-Control: no-store` so a reload always shows the current file.

**Why not `ruby -run -e httpd`.** The one-liner is the obvious answer and it
does not work here: `-run -e httpd` is a front end for webrick, which stopped
being a bundled standard library gem. On the Ruby this repository is
developed against (4.0.5) the one-liner fails outright rather than falling
back to anything. `serve.rb` has no such dependency, which is the whole reason
it exists.

To serve on a different port, pass it: `ruby serve.rb . 8080`. Stop the server
with Ctrl-C.
