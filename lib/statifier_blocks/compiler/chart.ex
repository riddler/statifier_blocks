defmodule StatifierBlocks.Compiler.Chart do
  @moduledoc """
  The Chart stage: run the generated SCXML through statifier's own
  pipeline and route every finding back to a block (ADR-0004 decisions 9
  and 10).

  This package ships **no** reachability analysis, no transition-target
  check, no id-uniqueness check and no expression well-formedness check.
  Statifier's validator already runs those against a conformance corpus
  with a regression ratchet behind it (st-ADR-0006), and a second semantic
  validator written against block documents would be a second
  implementation of the same rules that must agree with the first - every
  disagreement surfacing as a document the editor accepts and the engine
  then rejects. So: generate the SCXML, run it through
  `Statifier.compile/2`, and map the findings back through provenance.
  Adding a chart-semantic check here is a change to ADR-0004 decision 9.

  ## How the routing works

  Upstream findings carry no element reference. Every diagnostic in the
  pipeline - `Statifier.Parser.ParseError`, `Statifier.Lowering.Error`,
  `Statifier.Validator.Error`, `Statifier.Validator.Warning`,
  `Statifier.Compiler.Error` - is `{reason, message, location}`, where
  `location` is a `%Statifier.Parser.Location{}` over the source bytes.
  So the route is `location.start_offset` through
  `StatifierBlocks.Provenance.owner_at/2`, and decision 5's totality is
  what makes it a total function rather than one with an `:unmapped` arm.

  Upstream's `message` survives verbatim, and its `reason` tag becomes the
  finding's `code`. Upstream's document-order sort survives as document
  order over blocks, which `StatifierBlocks.Compiler` applies to every
  stage's findings alike.

  ## The fault split (decision 9)

  Two kinds of chart-stage finding, distinguished by exactly one thing -
  whether the owning span carries a config key:

    * **Structural findings are bugs in this package or in a host's block
      type, never the author's doing.** `{:unresolved_target, id}`,
      `{:initial_not_descendant, id, parent}`, a malformed namespace: an
      author cannot express any of these, because the block vocabulary has
      no way to name them. Their owning span has `config_key: nil`, and
      `fault: :package` is the actionable part - "this cannot be fixed
      here" is the only honest message.
    * **Content findings are the author's, and they carry a config key.**
      An `:expression` config field is a predicator source string passed
      verbatim into a `cond`; if it does not parse, upstream returns
      `{:expression_compile_error, owner_ref, source, parse_error}` located
      at the attribute value - a span this package recorded with the config
      key the value came from. That is squarely the author's typo, and the
      config key is what lets an editor put the error on the field they
      typed into rather than on the block as a whole.

  An upstream **error** of either kind fails the compile; a warning does
  not, and rides on `StatifierBlocks.Compiled`.

  ## Deferred: the sub-expression caret

  Decision 9 names one further refinement - composing a predicator parse
  error's own span into the attribute value's span, so an editor can
  underline the offending sub-expression inside the field rather than the
  whole field. It is not implemented here: the finding routes to the block
  and the config key, which is what the record's acceptance property
  requires, and the composition needs `Statifier.Parser.Location`'s
  span-resolution seam, whose arity the record and upstream currently
  spell differently. Raising that is a separate piece of work.
  """

  alias Statifier.Machine
  alias StatifierBlocks.Compiler.Finding
  alias StatifierBlocks.{Document, Provenance}

  @doc """
  Compiles `scxml` upstream and maps what comes back.

  `{:ok, warnings}` when the chart is valid - upstream's warnings
  (st-ADR-0033 made `Machine.warnings/1` their only surfacing seam),
  mapped the same way errors are. `{:error, findings}` otherwise.
  """
  @spec validate(binary(), Provenance.t(), Document.t()) ::
          {:ok, [Finding.t()]} | {:error, [Finding.t()]}
  def validate(scxml, %Provenance{} = provenance, %Document{} = document) do
    case Statifier.compile(scxml, chart_name: document.id) do
      {:ok, %Machine{warnings: warnings}} ->
        {:ok, Enum.map(warnings, &finding(&1, provenance, document, :warning))}

      {:error, errors} ->
        {:error, Enum.map(errors, &finding(&1, provenance, document, :error))}
    end
  end

  @spec finding(struct(), Provenance.t(), Document.t(), :error | :warning) :: Finding.t()
  defp finding(diagnostic, provenance, document, severity) do
    owner = owner(provenance, offset(diagnostic), document)

    Finding.new(:chart, diagnostic.reason, diagnostic.message,
      block_id: owner.block_id,
      config_key: owner.config_key,
      severity: severity
    )
  end

  # `%Statifier.Parser.ParseError{}` is the one diagnostic whose `location`
  # can be `nil`; it carries a raw `byte_offset` in that case, and when
  # even that is absent the failure is at the top of the document, which
  # the root block owns.
  @spec offset(struct()) :: non_neg_integer()
  defp offset(%{location: %{start_offset: offset}}), do: offset
  defp offset(%{byte_offset: offset}) when is_integer(offset), do: offset
  defp offset(_diagnostic), do: 0

  # Decision 5 makes the map total over the emission, so the fallback is a
  # compiler bug rather than a supported route. It still has to be total:
  # falling back to the root block, which ADR-0001 decision 1 guarantees
  # exists, keeps "every finding names a block" true without inventing an
  # `:unmapped` arm every consumer would have to handle.
  @spec owner(Provenance.t(), non_neg_integer(), Document.t()) :: Provenance.owner()
  defp owner(provenance, offset, %Document{root: root}) do
    case Provenance.owner_at(provenance, offset) do
      {:ok, owner} -> owner
      {:error, {:unmapped_offset, _offset}} -> Provenance.owner(root.id)
    end
  end
end
