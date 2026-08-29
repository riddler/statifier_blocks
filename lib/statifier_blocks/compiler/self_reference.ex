defmodule StatifierBlocks.Compiler.SelfReference do
  @moduledoc """
  The direct self-reference refusal: a document may not run itself
  (ADR-0004's 2026-08-29 amendment on what `core.subchart`'s `src`
  resolves against).

  A subchart names another document by its **document id** and the host's
  handler resolves that id to a chart at run time. When the id it names is
  the id of the document the block sits in, the run the handler starts is
  a fresh session of the same chart, which starts the same subchart, which
  starts another session. Nothing downstream can tell that apart from work
  the author meant to do, so the compiler refuses it here, where the two
  ids are both in hand and no session has been spent.

  ## The criterion, and why it is not a block-type name

  The pass never asks which block type emitted anything, for
  `StatifierBlocks.Compiler.SensitivePaths`' reason: a hard-coded list of
  `core.*` types would have to be edited every time the vocabulary grew,
  and a type added without that edit would recurse silently. It walks the
  **emission** and classifies by SCXML's own semantics: `src` on
  `<invoke>` is the attribute that names the resource an invocation runs,
  so an `<invoke>` whose `src` is this document's id is a document
  invoking itself, whichever type wrote it.

  `srcexpr` is deliberately not checked. It names a source computed at run
  time out of the datamodel, so there is no id here to compare against the
  document's, and refusing an expression because the document id appears
  somewhere inside it would refuse charts that are correct.

  ## Cross-document cycles are host-side, and named rather than built

  A -> B -> A is the same defect one document further out, and this
  package cannot see it. `emit/2` is a pure function of one block and its
  context (ADR-0004 decision 4); a compile is handed one document and a
  palette, and neither carries another document. Deciding a cycle needs
  the **document graph** - who references whom across the host's whole
  library - which only the host has. So the host's resolver owns that
  check, under the same st-ADR-0051 registry key that resolves a document
  id to a chart, and this module owns exactly the half a single compile
  can decide. Refusing the case in reach is worth more than declining both
  because one of them is out of reach.

  ## Stage and fault

  The finding carries the `:emit` stage, like every other refusal that
  reads the assembled emission, and it adds no stage to decision 10's
  table. It anchors on the offending block with `config_key: "chart"` -
  the author's verbatim value, stamped onto the attribute by
  `StatifierBlocks.Emission.attribute_from_config/3` - so decision 9's
  split reads it as `fault: :author`, which is right: a one-field edit
  fixes it.

  Severity is `:error`. A warning would let the document through and
  publish the recursion it exists to prevent.

  ## Presenting one

  `StatifierBlocks.Finding.from_compiler/2`'s default derivation cannot
  reach this finding, for the reason `SensitivePaths` records: its rule 2
  maps only a non-error to `:lint`, and an `:emit` stage has no default
  source, so a bare adaptation refuses with `:no_presentation_source`.
  That is what `opts[:source]` exists for, and a caller adapting these for
  the editor passes it:

      {presentation, []} =
        StatifierBlocks.Finding.from_compiler_all(findings, source: :lint)

  Widening the default derivation would mean switching on `code`, which
  `StatifierBlocks.Finding` forbids by construction; the seam is named
  here rather than bent, exactly as the sensitive-path refusal named it.
  """

  alias StatifierBlocks.{Block, Document, Emission}
  alias StatifierBlocks.Compiler.Finding

  # SCXML's attribute for the resource an `<invoke>` runs, on the element
  # that runs one. Both halves are checked: `src` means something else on
  # other elements, and this pass makes no claim about those.
  @element "invoke"
  @attribute "src"

  @doc """
  Every self-reference `emission` earns against `document_id`, in the
  order the emission is walked.

  Returns `[]` when nothing invokes the document itself, which is the
  overwhelming majority of compiles.
  """
  @spec check(Emission.t(), Document.id()) :: [Finding.t()]
  def check(%Emission{} = emission, document_id) when is_binary(document_id) do
    walk(emission, document_id)
  end

  @spec walk(Emission.node_t(), Document.id()) :: [Finding.t()]
  defp walk(%Emission{} = emission, document_id) do
    element_findings(emission, document_id) ++
      Enum.flat_map(emission.children, &walk(&1, document_id))
  end

  # A `{:child, id}` placeholder is a hole the compiler has already filled
  # with that child's own stamped subtree by the time this pass runs; one
  # surviving here is a compiler bug the Emit stage reports.
  defp walk({:child, _block_id}, _document_id), do: []

  @spec element_findings(Emission.t(), Document.id()) :: [Finding.t()]
  defp element_findings(%Emission{name: @element} = emission, document_id) do
    case List.keyfind(emission.attributes, @attribute, 0) do
      {@attribute, ^document_id} -> [finding(emission, document_id)]
      _other -> []
    end
  end

  defp element_findings(%Emission{}, _document_id), do: []

  @spec finding(Emission.t(), Document.id()) :: Finding.t()
  defp finding(emission, document_id) do
    Finding.new(
      :emit,
      {:self_reference, document_id},
      ~s(runs "#{document_id}", which is the document this block is in, so the run would ) <>
        "start a fresh session of the same chart and that session would start another. A " <>
        "subchart names another document by its id and the host's handler resolves that id " <>
        "at run time, so a document cannot name itself. A cycle through two or more " <>
        "documents is the same defect one document further out and is the host resolver's " <>
        "to refuse: it needs the document graph, which a compile of one document does not " <>
        "have.",
      block_id: block_id(emission),
      config_key: config_key(emission),
      severity: :error
    )
  end

  # The attribute's own annotation is the finer grain and wins; an element
  # with no annotation on `src` falls back to the element's own key. Both
  # come from ADR-0004 decision 9's split.
  @spec config_key(Emission.t()) :: String.t() | nil
  defp config_key(%Emission{attribute_owners: owners} = emission) do
    case List.keyfind(owners, @attribute, 0) do
      {@attribute, key} -> key
      nil -> owner_config_key(emission)
    end
  end

  @spec owner_config_key(Emission.t()) :: String.t() | nil
  defp owner_config_key(%Emission{owner: %{config_key: key}}), do: key
  defp owner_config_key(%Emission{}), do: nil

  @spec block_id(Emission.t()) :: Block.id() | nil
  defp block_id(%Emission{owner: %{block_id: id}}), do: id
  defp block_id(%Emission{}), do: nil
end
