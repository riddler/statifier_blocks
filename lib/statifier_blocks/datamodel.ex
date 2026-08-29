defmodule StatifierBlocks.Datamodel do
  @moduledoc """
  The host's datamodel as the editor consumes it, and the one check it
  makes against it (ADR-0005 decision 11, amended 2026-08-29 as 11e-11g).

  A block type may declare that one of its config fields holds a path into
  the host's datamodel - ADR-0002 decision 7's optional
  `datamodel_path?: true` key, amended the same day. This module is what
  reads that declaration: given a document, a palette and a datamodel, it
  returns one `:info` finding per annotated field whose value the datamodel
  does not declare, anchored `{:config, block_id, key}` with source
  `:lint`.

  Deliberately pure, and outside `StatifierBlocks.Editor.*`: the editor's
  job is translation (ADR-0005 decision 1), so the rule lives here and is
  asserted with `phoenix_live_view` absent from the dependency tree.

  ## Absence is not unknown-ness

  11f states the qualifier as a condition on production, and so does this
  module: **with no datamodel supplied, the check does not run.** Not a
  quieter severity, not an empty pane, not an "unknown" row - nothing.

  The reason is 11d's objection, which 11f answers rather than overrules: a
  host may legitimately carry values it has never described, so an
  undeclared-path claim is unfounded precisely when nothing was described.
  A host that hands the editor a datamodel is making the claim itself - it
  is saying *these are the paths this document may address* - and a path
  outside that set is then worth the author's attention, which is what
  `:info` means.

  An **empty** declared set is not the same as no datamodel. A host that
  supplies `[]` has said its documents may address nothing, and every
  annotated path is then undeclared. That is a real claim and it is
  reported; only `nil` suppresses the check.

  ## What counts as a datamodel

  `declared_paths/1` is the whole input contract, and it is deliberately
  small: a **set of declared dotted paths**. It accepts

    * `nil` - no datamodel, so no check;
    * a list of strings - the declared paths, blanks and non-strings
      dropped;
    * a `MapSet` of strings - the normalized form, idempotently;
    * a decoded **datamodel document** - sb ADR-0006's typed three-scope
      shape, of which `spike/fixtures/datamodel.json` is an instance -
      projected to its declared-path set.

  It accepts nothing else. The document arm is the one 11f promised and
  `sb-oiq` built: ADR-0006 (accepted 2026-08-29) defines the shape and its
  decision 6 gives the projection, and
  `StatifierBlocks.Predicates.Datamodel` implements both, so this module
  reads a document through that one total function rather than growing a
  second reader of a schema. Nothing else here moved - the set is still the
  whole contract this check needs, which is what 11e says: "This section is
  written against the set, so it holds under either."

  An **empty document** - one whose scopes declare no entries - projects to
  `MapSet.new()`, not to `nil`. Decision 6 states that distinction in the
  same words this module's own "absence is not unknown-ness" section does:
  a host that supplied a document declaring nothing has made a claim, and
  `nil` is reserved for the host that supplied no datamodel at all.

  [Correction 2026-08-29, sb-l0g: this paragraph read "no accepted record
  defines that shape, it is filed as a Proposed record (`sb-g8m`) still
  being checked against statifier-ui's ADR-0006 datasets, and a normalizer
  written against it here would ship an unratified document schema as a
  side effect of a lint. When that record is accepted, the derivation is
  ...". The record landed: sb ADR-0006, "The datamodel document is a typed,
  three-scope declaration, and the declared-path set is its projection",
  accepted 2026-08-29 (PR 101), and the sui-ADR-0006 cross-check it was
  waiting on was done in that record. Stale status only. What this module
  accepts is unchanged - `declared_paths/1` still takes exactly the three
  shapes listed above - and building ADR-0006's projection is separate
  work, not this correction's.]

  [Note 2026-08-29, sb-oiq: the "separate work" that correction named is
  this one, and the list above now carries a fourth shape. The three
  sb-l0g left unchanged are unchanged still: the document arm is additive
  and reads ADR-0006's projection rather than a second schema of its own.]

  Anything else - a map with no `scopes` list, a struct, a number -
  normalizes to `nil`, so a host that passes a shape this package does not
  know gets the behaviour it had before it passed anything, rather than a
  document suddenly covered in advisories. That is ADR-0002 amendment B3's total-normalizer
  discipline, reaching one more input.

  ## What this check is not

  It changes no verdict. A document whose only findings are these compiles
  exactly as it did before (11c), and any consumer gating on findings gates
  on `:error` as it always has.

  It is also not `validate_config/1`'s job and cannot be:
  `StatifierBlocks.Core.Assign`'s moduledoc says why - that callback is
  handed a config, not a document, and "is this path declared?" is a
  question about something outside the block entirely. This is the
  document-level pass it names.

  ## The uncommitted-draft gap, stated rather than discovered

  The check reads the **document**, so an advisory follows a config that
  has validated and been committed. While the author has an uncommitted
  draft on a field (ADR-0005 decision 9's draft, held in the editor and
  never in the document), the form shows the draft's own findings and this
  advisory is not among them. Whether an advisory should be recomputed
  against a draft is a decision-9 question no record answers, so this
  module does not answer it either.
  """

  alias StatifierBlocks.{Block, BlockType, Document, Finding, Palette, Predicates}

  @typedoc """
  The normalized datamodel: the set of paths the host declares, or `nil`
  when the host supplied none.
  """
  @type declared :: MapSet.t(String.t()) | nil

  @doc """
  Normalizes a host-supplied datamodel to a declared-path set, or `nil`.

  Total: every input has an answer and none of them raise. See the
  moduledoc for what is accepted and why the list is short.

      iex> StatifierBlocks.Datamodel.declared_paths(nil)
      nil

      iex> StatifierBlocks.Datamodel.declared_paths(["signup.step", "signup.variant_id"])
      MapSet.new(["signup.step", "signup.variant_id"])

      iex> StatifierBlocks.Datamodel.declared_paths(["signup.step", "", 42])
      MapSet.new(["signup.step"])

      iex> StatifierBlocks.Datamodel.declared_paths(%{"scopes" => []})
      MapSet.new([])

      iex> StatifierBlocks.Datamodel.declared_paths(%{"version" => 1, "scopes" => [
      ...>   %{"scope" => "local", "entries" => [
      ...>     %{"name" => "step", "path" => "signup.step", "type" => "string",
      ...>       "label" => "Step"}]}]})
      MapSet.new(["signup.step"])

      iex> StatifierBlocks.Datamodel.declared_paths(%{"scopes" => "not a list"})
      nil
  """
  @spec declared_paths(term()) :: declared()
  def declared_paths(nil), do: nil

  def declared_paths(%MapSet{} = set) do
    set |> MapSet.to_list() |> declared_paths()
  end

  def declared_paths(paths) when is_list(paths) do
    paths
    |> Enum.filter(&declared_path?/1)
    |> MapSet.new()
  end

  # The ADR-0006 arm, additive over the three above: `index/1` is the
  # record's admission step, and a map it declines is still an
  # unrecognized shape rather than an empty claim.
  def declared_paths(%{"scopes" => _scopes} = document) do
    case Predicates.Datamodel.index(document) do
      nil -> nil
      index -> Predicates.Datamodel.declared_paths(index)
    end
  end

  def declared_paths(_unrecognized), do: nil

  @doc """
  Every undeclared-path advisory in the document (11e), or `[]` when the
  host supplied no datamodel (11f).

  `datamodel` is normalized through `declared_paths/1`, so a raw list and
  an already-normalized set behave identically.

  A block whose type the palette cannot resolve produces nothing here - it
  already has a `:resolution` finding from `StatifierBlocks.ViewModel`, and
  a block with no schema declares no datamodel path. A field annotated
  `datamodel_path?: true` whose value is missing or is not a non-empty
  string produces nothing either: that is `validate_config/1`'s to refuse,
  at `:error`, and an advisory beside it would say the same thing twice in
  two voices.
  """
  @spec findings(Document.t(), Palette.t(), term()) :: [Finding.t()]
  def findings(%Document{} = document, %Palette{} = palette, datamodel) do
    case declared_paths(datamodel) do
      nil -> []
      declared -> undeclared_findings(document, palette, declared)
    end
  end

  @spec undeclared_findings(Document.t(), Palette.t(), MapSet.t(String.t())) :: [Finding.t()]
  defp undeclared_findings(document, palette, declared) do
    document
    |> Document.blocks()
    |> Enum.flat_map(fn block ->
      case Palette.resolve(palette, block) do
        {:ok, module, resolved} -> block_findings(block, module, resolved.config, declared)
        {:error, _reason} -> []
      end
    end)
  end

  @spec block_findings(Block.t(), module(), Block.config(), MapSet.t(String.t())) :: [Finding.t()]
  defp block_findings(%Block{id: id}, module, config, declared) do
    config
    |> module.config_schema()
    |> Enum.filter(&BlockType.datamodel_path?/1)
    |> Enum.flat_map(fn decl ->
      case BlockType.fetch_value(config, BlockType.value_path(decl)) do
        {:ok, path} -> advisory(id, decl.key, path, declared)
        :error -> []
      end
    end)
  end

  @spec advisory(Block.id(), String.t(), Block.json(), MapSet.t(String.t())) :: [Finding.t()]
  defp advisory(block_id, key, path, declared) do
    if declared_path?(path) and not MapSet.member?(declared, path) do
      [
        Finding.new(
          {:config, block_id, key},
          :lint,
          "#{path} is not declared in the datamodel",
          severity: :info
        )
      ]
    else
      []
    end
  end

  @spec declared_path?(term()) :: boolean()
  defp declared_path?(path), do: is_binary(path) and path != ""
end
