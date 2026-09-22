defmodule StatifierBlocks.Graph do
  @moduledoc """
  The publish-time check between a parent document and the children it
  names (ADR-0008's amendment of 2026-09-22).

  A compile of one document cannot see the child a `core.subchart` or a
  `core.map` names, and at runtime a disagreement between the two is not
  refused: a child outcome the parent routes on but the child no longer
  finishes with leaves the parent's conditioned arm dead, and the child's
  answer falls to the parent's unconditioned arm. The document graph is the
  host's, so the host is what walks it. This module ships the **pairwise**
  check the walk calls, over two `StatifierBlocks.Compiled` artifacts, in
  the two directions A2 names:

    * `check/2` - forward, when a parent is published: every child the
      parent names is resolved through the host's resolver and judged
      against the parent.
    * `consumers_broken/2` - reverse, when a child is republished: the
      next child artifact is judged against every parent the host says
      currently names it (A3).

  Both read only `StatifierBlocks.Compiled`'s `interface` field (A5). They
  hold no store, start no process and perform no IO; the resolver is the
  host's function and the only IO either direction touches.

  ## The three checks

    1. **Every child the parent names resolves** (A4). A resolver answering
       `{:error, :not_published}` is a finding on the referencing block's
       `chart` field.
    2. **Every outcome the parent routes on is declared by the child** (A1,
       A2). A `core.subchart` routes on the outcomes its author listed, or
       on `done` when the author listed none. `error` is exempt: the
       parent routes on it whether or not the author listed it, and a
       child reports it without declaring it. Anchored on the block's
       `outcomes` field.
    3. **Every done-data key the parent reads is declared by the child**
       (A1, A2). A `core.map` reads the members its `collect_type` marks
       required; a `core.subchart` reads none. Anchored on the block's
       `collect_type` field. Only presence is checked: whether a declared
       key has the type the parent expects stays
       `StatifierBlocks.BlockType.agrees?/3`'s dormant advisory.

  The other direction of the outcome rule - a child outcome the parent has
  **no** arm for, such as one a child revision adds - is not refused here.
  It falls to the parent's unconditioned arm, and
  `StatifierBlocks.ViewModel.outcome_findings/3` stays the editor's
  `:warning` about it.

  ## The findings

  Every finding is a `StatifierBlocks.Finding` with source `:graph` and
  severity `:error`, anchored `{:config, block_id, key}` on the parent's
  referencing block, under the field its author would change. The anchor
  has no document arm, so `consumers_broken/2` returns each finding paired
  with the parent's document id, and its message names that document.
  """

  alias StatifierBlocks.{Compiled, Finding}

  # A1: `core.subchart` appends this outcome to every parent's routes
  # whether or not the author listed it, and a child reports an unhandled
  # failure under it without its root declaring it.
  @exempt_outcome "error"

  @typedoc """
  The host's publish-time resolver: a document id to that document's
  currently published artifact, or `{:error, :not_published}`. It is not
  the durable handler's start-time `resolve_chart/2`, and it is the only IO
  `check/2` performs. `check/2` calls it once per distinct document id the
  parent names, in the order the parent first names each.
  """
  @type resolver :: (String.t() -> {:ok, Compiled.t()} | {:error, :not_published})

  @doc """
  The forward check (ADR-0008 amendment A2, A4): judges `parent` against
  every child it names, each resolved through `resolver`.

  Returns `[]` when every child resolves, declares every outcome the parent
  routes on and every done-data key the parent reads. Otherwise one
  `:error` finding, source `:graph`, per failed rule, in the parent's
  document order:

    * a child the resolver answers `{:error, :not_published}` for -
      anchored `{:config, block_id, "chart"}`;
    * an outcome the parent routes on that the child does not declare,
      `error` exempt - anchored `{:config, block_id, "outcomes"}`;
    * a done-data key the parent reads that the child does not declare -
      anchored `{:config, block_id, "collect_type"}`.

  `block_id` is always the parent's referencing block. A resolver answering
  anything else breaks its contract, and the call raises rather than
  guessing what the host meant.
  """
  @spec check(Compiled.t(), resolver()) :: [Finding.t()]
  def check(%Compiled{interface: %{references: references}}, resolver)
      when is_function(resolver, 1) do
    children =
      references
      |> Enum.map(& &1.document_id)
      |> Enum.uniq()
      |> Map.new(fn document_id -> {document_id, resolve(resolver, document_id)} end)

    Enum.flat_map(references, fn reference ->
      case Map.fetch!(children, reference.document_id) do
        {:ok, child} -> pair(reference, child.interface, &forward_message/3)
        {:error, :not_published} -> [unpublished(reference)]
      end
    end)
  end

  @doc """
  The reverse check (ADR-0008 amendment A2, A3): judges `child_next`, the
  child revision about to be published, against each of `parents`, the
  published artifacts the host says currently name that child.

  The child's document id is `child_next.record.document_id`, and only a
  parent's references to that id are judged, so a parent that names other
  documents only contributes nothing. Returns `[]` when every such parent
  still finds every outcome it routes on and every done-data key it reads
  declared by `child_next`; otherwise one `{parent_document_id, finding}`
  pair per failed rule, parents in the order given and each parent's
  findings in its document order. Each finding is source `:graph`,
  severity `:error`, anchored on the parent's referencing block -
  `{:config, block_id, "outcomes"}` for an outcome, `{:config, block_id,
  "collect_type"}` for a done-data key - and its message names the parent
  document. The resolver plays no part: both sides are in hand.
  """
  @spec consumers_broken(Compiled.t(), [Compiled.t()]) :: [{String.t(), Finding.t()}]
  def consumers_broken(%Compiled{} = child_next, parents) when is_list(parents) do
    child_id = child_next.record.document_id

    Enum.flat_map(parents, fn %Compiled{} = parent ->
      parent_id = parent.record.document_id

      parent.interface.references
      |> Enum.filter(&(&1.document_id == child_id))
      |> Enum.flat_map(&pair(&1, child_next.interface, reverse_message(parent_id)))
      |> Enum.map(&{parent_id, &1})
    end)
  end

  @spec resolve(resolver(), String.t()) :: {:ok, Compiled.t()} | {:error, :not_published}
  defp resolve(resolver, document_id) do
    case resolver.(document_id) do
      {:ok, %Compiled{}} = found -> found
      {:error, :not_published} = missing -> missing
    end
  end

  # The two rules A1 names, over one reference and the child's interface.
  @spec pair(
          Compiled.child_reference(),
          Compiled.interface(),
          (Compiled.child_reference(), :outcome | :key, String.t() -> String.t())
        ) :: [Finding.t()]
  defp pair(reference, child, message) do
    outcomes =
      for outcome <- reference.routes_on,
          outcome != @exempt_outcome,
          outcome not in child.declared_outcomes do
        finding(reference, "outcomes", message.(reference, :outcome, outcome))
      end

    keys =
      for key <- reference.reads, key not in child.declared_donedata_keys do
        finding(reference, "collect_type", message.(reference, :key, key))
      end

    outcomes ++ keys
  end

  @spec unpublished(Compiled.child_reference()) :: Finding.t()
  defp unpublished(reference) do
    finding(
      reference,
      "chart",
      ~s(no published document "#{reference.document_id}" to run)
    )
  end

  @spec finding(Compiled.child_reference(), String.t(), String.t()) :: Finding.t()
  defp finding(reference, key, message) do
    Finding.new({:config, reference.block_id, key}, :graph, message)
  end

  @spec forward_message(Compiled.child_reference(), :outcome | :key, String.t()) :: String.t()
  defp forward_message(reference, :outcome, outcome),
    do: ~s("#{reference.document_id}" does not declare the outcome "#{outcome}" routed on here)

  defp forward_message(reference, :key, key),
    do: ~s("#{reference.document_id}" does not declare the done-data key "#{key}" read here)

  @spec reverse_message(String.t()) ::
          (Compiled.child_reference(), :outcome | :key, String.t() -> String.t())
  defp reverse_message(parent_id) do
    fn
      reference, :outcome, outcome ->
        ~s("#{parent_id}" routes on the outcome "#{outcome}", which the next revision ) <>
          ~s(of "#{reference.document_id}" does not declare)

      reference, :key, key ->
        ~s("#{parent_id}" reads the done-data key "#{key}", which the next revision ) <>
          ~s(of "#{reference.document_id}" does not declare)
    end
  end
end
