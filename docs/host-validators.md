# How to write a host advisory finding

This guide shows you how to put one of your own rules on the author's screen
as a warning, without teaching this package anything about it and without
stopping the document from compiling.

The channel is `StatifierBlocks.DocumentValidator`: a module of yours, listed
on the palette under `:validators`, handed the whole document as authored and
answering with whatever it objects to.
[`docs/adr/0005-liveview-editor.md`](adr/0005-liveview-editor.md) clauses `11p`
to `11t` are the record; everything below is the moves.

## Before you start

You need a palette you build yourself - `StatifierBlocks.Palette.new/2` or
`from_modules/2` - because `:validators` is an option on that call. A host
that renders `StatifierBlocks.Editor` already builds one.

Your rule has to be answerable from the document alone. The callback is pure
and it is handed one value; a rule that needs the datamodel, a fixture or a
network call is yours to evaluate before you build the palette, and what you
learned rides into the module as data (below, `@dropped` is exactly that).

## The rule

Take a card-processing document. Your datamodel document redefined the `card`
record and dropped `risk_band` from it, so every config value in every open
draft that still reads that member now reads a path the datamodel no longer
covers. The compiler will not say so - the member's absence is a fact about
your datamodel, not about this document - but an author looking at the branch
should see it.

Which members went away is the half you work out yourself, before the palette
exists. The rule is the half that finds them in the document:

```elixir
defmodule MyApp.Rules.RecordCoverage do
  @moduledoc """
  Warns where a config value still reads a member the `card` record lost.
  """

  @behaviour StatifierBlocks.DocumentValidator

  alias StatifierBlocks.Document

  # What redefining `card` dropped. Derived from your own datamodel diff and
  # baked in here as data, because the callback itself is pure.
  @dropped ~w(risk_band)

  @impl true
  def validate_document(%Document{} = document) do
    document |> Document.blocks() |> Enum.flat_map(&block_findings/1)
  end

  defp block_findings(block) do
    for {key, value} <- block.config, member <- @dropped, reads?(value, member) do
      {{:config, block.id, key},
       "`card.#{member}` is no longer a member of the `card` record, so this " <>
         "reads a path the datamodel no longer covers", severity: :warning}
    end
  end

  defp reads?(value, member) when is_binary(value), do: String.contains?(value, member)
  defp reads?(value, member) when is_list(value), do: Enum.any?(value, &reads?(&1, member))

  defp reads?(value, member) when is_map(value),
    do: value |> Map.values() |> Enum.any?(&reads?(&1, member))

  defp reads?(_value, _member), do: false
end
```

Two things about the return value are worth naming, because they are what make
the finding land where an author can act on it:

- **The anchor is `{:config, block_id, key}`**, not `{:block, block_id}`. Both
  are legal (`t:StatifierBlocks.Finding.anchor/0` also has `{:slot, id, name}`),
  but a config anchor names the field somebody typed the value into, and that
  is what carries the message into the inspector for that block instead of
  leaving it only on the card - under the control itself when the key names a
  form field, and in the block's Findings panel either way.
- **`severity: :warning`** is the default, so you may leave it off. It is
  written out here because a rule that means `:info` or `:error` says so in
  the same place, and because the severity is the one thing about the finding
  a host actually chooses. The *source* is not: this package stamps `:lint` on
  everything a validator returns, and nothing you put in the keyword list
  changes that.

## Registering it

`:validators` is a list, and every module in it runs, in list order:

```elixir
palette =
  StatifierBlocks.Palette.new(my_types,
    recipes: my_recipes,
    validators: [MyApp.Rules.RecordCoverage]
  )
```

It is a list rather than a `name => module` map on purpose: nothing resolves a
validator by name, so there is no key to hold one, and a second entry does not
replace a first. A palette that declares none pays nothing.

## Where the finding shows

Once the palette carries the rule, the finding travels the routes decision 11
already had. Nothing in the editor was taught about validators.

| Surface | What you see |
|---|---|
| The drawer's **Findings** tab | one row, stamped `data-anchor="config:<block id>:<key>"`, `data-source="lint"`, `data-severity="warning"` |
| The inspector's **Findings** tab | the same row, for the selected block, on the same anchor |
| The inspector's config form | under the control, when the key names a form field |
| The Findings tab's **count** | includes it |
| `StatifierBlocks.Editor.findings_count/3` | includes it |

The count is the part worth being explicit about, because
`StatifierBlocks.Editor`'s moduledoc section *the findings number a host may
show* names three producers and a validator is a
fourth. There is only one number: `StatifierBlocks.Shell.findings_count/1`
counts `ViewModel.findings`, the validator findings are appended into that
same list by `StatifierBlocks.ViewModel.build/3`, and `findings_count/3` reads
it through the same code the tab chip does. So a host header that reports the
count moves when your rule fires, and it cannot disagree with the drawer.

## It survives the author's next edit

You register the rule once, on the palette. You do not re-register it, and
nothing you do keeps it alive: the finding is re-derived on every build rather
than delivered once at mount.

That is a property of where validators run. `ViewModel.build/3` runs the
palette's validators as part of deriving the findings, the editor rebuilds its
view model on every gesture that changes anything, and the palette it rebuilds
from is the assign you handed in. So an author can select a block, retype a
value, delete a step, and your warning is still on the block it was on -
recomputed each time from the document as it now reads, which also means it
goes away by itself the moment the author fixes what it objected to.

`StatifierBlocks.Editor.HostValidatorRefreshTest` is that claim as a test: the
rule above, a mounted editor over the card-processing document, a config edit
on an unrelated block, the same row still in the drawer afterwards, and then
the row gone once the block it objected to is deleted.

## What this channel will not do

- **It cannot stop a compile.** A validator finding is advisory; the severity
  the package defaults to is `:warning` for that reason, and even `:error`
  from a host rule is a rendering, not a refusal. If your rule is really about
  whether one block's config is well-formed, it belongs in that block type's
  `validate_config/1`, where a refusal is available.
- **It is not validated back at you.** A return that is not a list, and a
  member that is neither `{anchor, message}` nor `{anchor, message, opts}`, is
  read as no finding rather than raised at. A `:severity` outside the enum
  falls back to `:warning`. Unrecognised keys in `opts` are ignored.
- **It does not rescue your bugs.** A raise inside `validate_document/1` is
  not caught. That is deliberate: it is your bug, and the moment it is visible
  is the moment to see it.
- **It sees the document, not the run.** The callback is handed the document
  as authored. Anything about a compiled chart, a fixture run or the datamodel
  is yours to compute outside and carry in.

## Related

- [`docs/typing-a-palette.md`](typing-a-palette.md) - the declarations that
  make the *compiler* refuse a document, which is the other half of this.
- `StatifierBlocks.DocumentValidator` - the callback and its return types.
- `StatifierBlocks.Palette` - `:validators` beside the palette's other seams.
