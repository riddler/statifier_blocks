defmodule StatifierBlocks.DocumentValidator do
  @moduledoc """
  A host's own whole-document rule (ADR-0005 clauses `11p` to `11t`).

  A block type answers "is this block's config right", one block at a time,
  and it is handed that block's config and nothing else. Some rules are not
  about a block: "a model step needs a decision before an act" is about type
  names and order across the whole tree, and there was no seam for it.
  This behaviour is that seam. A host writes a module implementing
  `c:validate_document/1`, puts it in the palette's `validators` list
  (`StatifierBlocks.Palette.new/2`), and every finding it returns joins the
  ones this package derives, on the routes decision 11 already has.

  ## What it is handed, and what it returns

  The argument is the `Document.t()` **as authored** - every block, its
  `type`, its config and its position in its parent's slots. It is not
  handed the palette (the host built that value), not the view model (it is
  being built when the callback runs), and not a compiled chart: a document
  is briefly wrong in the middle of every arrangement built by hand, and a
  rule that only spoke after a successful compile would be silent at exactly
  the moments the author needs it. Clause `11q` records all three reasons.

  A validator returns a list of `t:finding_spec/0`:

      [{{:block, "blk_root"}, "a decision step must precede an act step"},
       {{:config, "blk_7", "chart"}, "this chart is retired", severity: :info}]

  It says **where** and **what**; the package says **which source**. That is
  `c:StatifierBlocks.BlockType.validate_config/1`'s division of labour one
  level up, with one difference: a document rule names its own anchor,
  because its subject is not the single block whose config it was handed.

  ## The package stamps `:lint`, and the default severity is `:warning`

  Every finding from a validator carries source `:lint` - the enum member
  that already means "the editor applied a rule" rather than "a declared
  shape says so" (clause `11r`). A host cannot claim `:compile` or
  `:resolution` for its own rule, which is the point of stamping rather than
  accepting.

  Severity defaults to `:warning` rather than to `StatifierBlocks.Finding`'s
  own `:error`, because decision 11 defines `:error` as "the document does
  not compile" and a host rule cannot make a document not compile - the
  compiler never calls a validator. A host may still pass
  `severity: :error`, and it means what a host means by it: *my* gate
  refuses this document.

  ## Total on its own data, and not on the host's code

  A returned term that is not a list, and a member that is neither of the
  two shapes above, is read as **no finding** - decision 10's normalizer
  discipline, applied to a host's return value. An exception raised inside
  the callback is **not** caught, exactly as `validate_config/1`'s is not: a
  host's code raising is that host's bug, and swallowing it would hide it at
  the only moment it is visible.

  ## What a validator is not

  It is not a block type and not a recipe. It implements one callback of its
  own, it appears in no palette browser, it has no `palette_entry/0`, and it
  can appear in no document. It returns findings and nothing else: it cannot
  edit the document, and no `StatifierBlocks.Edit` command is reachable from
  it (clause `11t`, "a finding, never a fix-up").

  Validators run in the palette's list order, every one of them, and a later
  entry does not replace an earlier one - the list is not a lookup, so
  nothing collides and nothing is overridden. A rule of a host's may
  contradict a `singleton` declaration of the same host's, and both findings
  are emitted, unreconciled: the package cannot reconcile them without
  understanding the host's rule, which is the thing this seam exists because
  it cannot do. The two are distinguishable where it matters - the declared
  one is `:config`, the written one is `:lint`.

  ## Example

      defmodule MyApp.Rules.DecideBeforeAct do
        @behaviour StatifierBlocks.DocumentValidator

        alias StatifierBlocks.Document

        @impl true
        def validate_document(%Document{} = document) do
          types = document |> Document.blocks() |> Enum.map(& &1.type)

          if "myapp.act" in types and "myapp.decide" not in types do
            [{{:block, document.root.id}, "an act step needs a decision before it"}]
          else
            []
          end
        end
      end

      Palette.new(types, validators: [MyApp.Rules.DecideBeforeAct])
  """

  alias StatifierBlocks.{Document, Finding}

  @typedoc """
  What a validator may say about a finding beyond where and what.

  `:severity` only, and it defaults to `:warning`. Anything else in the
  keyword list is ignored rather than refused, for the same reason an
  unrecognised member of the returned list is: a host's return value is
  normalized, never validated back at it.
  """
  @type opts :: [severity: Finding.severity()]

  @typedoc """
  One finding as a validator states it: decision 11's anchor, a message, and
  optionally `t:opts/0`. The source is the package's to stamp (`11r`).
  """
  @type finding_spec ::
          {Finding.anchor(), String.t()} | {Finding.anchor(), String.t(), opts()}

  @doc """
  The host's rule, run once per `StatifierBlocks.ViewModel.build/3` on the
  document as authored.

  It is pure and it is handed one value. A rule needing the datamodel, a
  fixture or a network call is a host's own concern, evaluated before it
  builds the palette or after it reads `on_change`.
  """
  @callback validate_document(document :: Document.t()) :: [finding_spec()]
end
