# Mounting the editor for one audience

This guide shows you how to say which of the editor's surfaces a mount draws,
and how to mount it read-only.

One host often serves two audiences out of one codebase: its own engineers,
who want the whole editor, and staff who should see a canvas, some findings
and nothing else - or a rendering they cannot type into. The `profile` assign
is how a mount says which of the two it is.
[`docs/adr/0005-liveview-editor.md`](adr/0005-liveview-editor.md)'s 2026-09-07
amendment is the record; everything below is the moves.

## The default

`profile` is optional, and a mount that passes none gets the editor it would
have got before the assign existed:

```elixir
%{
  drawer_tabs: :all,
  inspector_tabs: :all,
  palette_groups: :all,
  toolbar: :all,
  read_only?: false
}
```

Every key is optional, and `:all` is a member of every list type rather than a
separate flag, so a key you do not mention resolves to the default. There is no
arrangement of this map - `%{}` included - that removes a surface you did not
name.

**There are no named profiles.** No `:operations`, no `:reviewer`, no
`:minimal`. Which audiences exist is yours to know, so if you want a name for a
profile you write the map into a module attribute of your own and name it
there.

A profile is not persisted and it is not a document property. It is what you
say about the mount, supplied on every render like `palette` or `datamodel`.

## The ids each list draws from

| Key | The ids it draws from |
|---|---|
| `drawer_tabs` | `:tables`, `:findings`, `:declarations`, `:fixtures`, `:datamodel`, `:source`, and the string `id` of each of your own `drawer_tabs` entries |
| `inspector_tabs` | `:config`, `:findings`, `:condition`, `:fixtures` |
| `palette_groups` | the `group` name of each palette entry, as strings; the core types all declare `"Structure"` |
| `toolbar` | `:history` (Undo and Redo), `:zoom` (the segmented zoom control), `:fits` (`Fit width` and `Fit active`), `:metrics` (the two right-aligned read chips) |

Two of them need a word.

**A palette group name is an open set of strings.** It is a block type's own
word rather than a member of a closed list this package keeps, so a profile that
names `"Structure"` is naming a string your palette may or may not contain.

**The `Canvas` heading and the `nested tree` chip are not addressable.** They
are what makes the canvas read as a pane beside the other two, so a profile that
could remove them could produce an editor whose middle pane has no name.

Tab order is this package's, not yours: a tab list is an intersection with the
order the shell already keeps, so two hosts that name the same tabs in
different orders draw the same strip.

**`palette_groups` is the exception, and it is the one list that reads as an
order.** A tab has a place in a strip this package designed; a palette group
has only the name a block type gave it, and the order the package can produce
for a set of names it has never seen is alphabetical - which is an order about
spelling, not about work. So the list you write is the reading order you get:

```elixir
palette_groups: ["Authorization", "Timing", "Structure"]
```

draws those three headings in that order, whatever their names sort as. The
list is still a set as well: a group you do not name is not drawn at all, and a
name your palette does not carry is dropped like any other unresolvable id. If
you want the order without the filtering - your own palette column, drawing
every group your palette has - call
`StatifierBlocks.ViewModel.order_palette_groups/2` with the same list: it puts the groups you named first, in your order, and
every group you did not name after them by name.

Naming no list still draws every group by name, exactly as it always did.

## An id the package does not know is dropped

A list member the package cannot resolve is dropped, and the mount renders.
Not an argument error, not a finding, not a refusal: the surface that id would
have named is simply not there, and every id in the list that did resolve is.

You are relying on this whenever a profile outlives the thing it names. A
profile is written once, in your code, against the tab set of the version it
was written for; if an unknown id raised, then removing a tab from this package
- or you removing one of your own drawer tabs - would turn every mount whose
profile still names it into a crash at render.

The same reasoning covers a malformed value. A key whose value is neither a
list nor `:all` resolves to that key's default, which is the surface you had
before you named anything. There is no `validate_profile/1` and a profile list
is never checked against the shell's ids at declaration.

An empty list is not malformed - it is a list naming nothing, and it removes
the surface. `palette_groups: []` renders the palette column with no groups in
it; `drawer_tabs: []` leaves a drawer with an empty strip.

## A minimal mount

Operations staff investigating settlement documents need the canvas, the
findings and the fixture runs, and have no business inserting blocks:

```elixir
<.live_component
  module={StatifierBlocks.Editor}
  id="ops-editor"
  document={@document}
  palette={@palette}
  fixtures={@fixtures}
  profile={%{
    drawer_tabs: [:findings, :fixtures],
    inspector_tabs: [:findings, :fixtures],
    palette_groups: [],
    toolbar: [:zoom, :fits, :metrics]
  }}
/>
```

The drawer's strip carries two tabs; the inspector's carries two; the palette
column renders with no groups in it; the toolbar keeps zoom, the fits and the
metrics and drops Undo and Redo. `read_only?` is absent, so it is `false` and
**this mount still edits**. Scoping the surfaces and withholding editing are
two separate settings, and you may want either without the other.

## A read-only mount

The same document, opened by a reviewer who signs off on it:

```elixir
<.live_component
  module={StatifierBlocks.Editor}
  id="review-editor"
  document={@document}
  palette={@palette}
  fixtures={@fixtures}
  on_select={&JS.push("reviewing", value: &1)}
  profile={%{
    drawer_tabs: [:findings, :fixtures, :source],
    read_only?: true
  }}
/>
```

`inspector_tabs`, `palette_groups` and `toolbar` are unmentioned, so all three
are `:all` - and then `read_only?` withholds the palette column and hides Undo
and Redo regardless. The reviewer selects blocks, reads their config as values,
reads findings and fixture runs and the compiled source, and cannot change a
character.

`read_only?: true` is six clauses, and they are a set:

1. **No palette column.** Not a collapsed palette - a mount with no palette at
   all. `palette_groups` still parses and is simply moot for that mount. The
   other way into the palette goes with it: the "+" button on the gaps between
   blocks is not drawn either, so the canvas offers no insertion point. The
   gaps themselves stay, because a gap is also where an empty arm says it is
   an arm, and that is a reading.
2. **No drag hook.** The canvas does not mount the drag hook. The measurement
   hook is unaffected: it reads nothing you can change.
3. **Config fields render as values.** The inspector's Config tab draws each
   field's label and its current value, not a control. A disabled `<input>` is
   a control that refuses, and what is wanted here is a reading. The
   declarations panel in the drawer draws its rows the same way, for the same
   reason, and drops its Add and Order controls.
4. **Selection and findings stay.** Selecting a block still works, `on_select`
   still fires, the inspector still follows the selection, and every findings
   surface draws exactly what it draws in an editing mount.
5. **Undo and Redo are hidden.** Not disabled: hidden, whatever `toolbar` says.
   Zoom, the fits and the metrics are untouched - all four are ways of reading.
6. **`on_change` never fires.** No edit reaches the document, so there is no
   new document to hand back. You may pass `on_change` alongside
   `read_only?: true`; it simply never runs.

Every gesture that would reach the document is answered with the socket
unchanged, so a crafted payload posting to a read-only mount changes nothing
either.

**A document is never refused for being read-only.** Every document that
renders in an editing mount renders in a read-only one. `read_only?` narrows
what a mount *offers*, never what it *accepts*.

**It is not an authorization boundary.** A read-only mount withholds
affordances; it is not a permission check. If you must prevent a write, enforce
that where you handle the write, not by trusting a rendering.
