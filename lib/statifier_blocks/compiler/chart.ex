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

  ## The sub-expression span (decision 9's last refinement)

  A content finding routes to a field. Decision 9 goes one step further:
  the predicator parse error carries a span *within the expression
  string*, so an editor can underline the offending sub-expression inside
  the field rather than the whole field. That span is composed here and
  lands on the finding as `config_value_span`.

  The composition is three steps, and the middle one is upstream's:

    1. Upstream reports the failure against the **attribute value's** span
       in the generated SCXML (`Statifier.Compiler.Error`'s `location`),
       and carries predicator's own `{line, column}` span over the
       expression string it compiled.
    2. `Statifier.Parser.Location.resolve_span/4` composes the two into an
       absolute span over the generated document, walking the raw bytes
       and the entity-expanded string in lockstep so a `&gt;` earlier in
       the expression cannot shift the answer.
    3. That absolute span is run **backwards** through the same
       correspondence the provenance map is built from: subtract the
       attribute value's own start, and unescape the prefix, which turns
       generated-document bytes back into bytes of the value the author
       typed.

  Step 3's unescape is not decoration. A `cond` is emitted through
  `StatifierBlocks.Compiler.Serializer`'s XML escaping, so the canonical
  `amount > > 5000` reaches the document as `amount &gt; &gt; 5000`, where
  the offending second `>` sits at byte 12 rather than at byte 9 - one
  entity reference ahead of it is already enough to move it. The offsets
  this field carries are into the author's value, so they are the ones an
  editor can use without knowing that a serializer exists.

  ### When a finding gets one

  All four have to hold, and the field is `nil` otherwise:

    * the finding's owning span carries a **config key** - the same test
      the fault split above turns on, and the reason a canonicalised
      attribute (`core.wait`'s `delay`, whose bytes the block type
      rebuilt rather than passed through) is never annotated and so never
      offered an in-value offset;
    * the diagnostic is an `:expression_compile_error`, the only upstream
      reason that carries an expression string at all;
    * predicator supplied a **span** for the failure (`ParseError`'s
      `:span` is optional, and `nil` on an error built through `new/3`);
    * the resolved span lies inside the attribute value's own span - the
      guard that keeps a degraded resolution honest rather than turning it
      into an offset into somebody else's bytes.

  `resolve_span/4` degrades rather than raising: an expression whose
  expanded text does not describe the raw slice resolves to the value's
  whole span, which arrives here as "underline the entire field" - the
  same answer a consumer would have reached with no span at all, which is
  why it is passed through rather than discarded.

  ### Why "carries a config key" is enough

  The first bullet reads "carries a config key", where decision 9's
  annotation rule means "was written verbatim from that config value".
  Those coincide because the annotation is only ever left on a verbatim
  value: a block type that *composes* an attribute leaves it
  unannotated, so its bytes have no config key and a finding inside them
  is the package's. `core.subchart` was the one exception - it annotated
  a `cond` it builds from an outcome name with the config key
  `outcomes` - and that annotation was dropped rather than this
  criterion widened.
  """

  alias Statifier.Machine
  alias Statifier.Parser.Location
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
        {:ok, Enum.map(warnings, &finding(&1, provenance, document, scxml, :warning))}

      {:error, errors} ->
        {:error, Enum.map(errors, &finding(&1, provenance, document, scxml, :error))}
    end
  end

  @spec finding(struct(), Provenance.t(), Document.t(), binary(), :error | :warning) ::
          Finding.t()
  defp finding(diagnostic, provenance, document, scxml, severity) do
    owner = owner(provenance, offset(diagnostic), document)

    Finding.new(:chart, diagnostic.reason, diagnostic.message,
      block_id: owner.block_id,
      config_key: owner.config_key,
      config_value_span: config_value_span(diagnostic, owner, scxml),
      severity: severity
    )
  end

  # Decision 9's last refinement; the moduledoc owns the criterion. The
  # first clause is the one that fires almost always: a finding with no
  # config key is about the package's own emission, and there is no
  # author's value for an offset to be inside of.
  @spec config_value_span(struct(), Provenance.owner(), binary()) ::
          Finding.config_value_span() | nil
  defp config_value_span(_diagnostic, %{config_key: nil}, _scxml), do: nil

  defp config_value_span(
         %{
           reason:
             {:expression_compile_error, _owner_ref, value, %{span: {_start, _stop} = span}},
           location: %Location{} = value_location
         },
         _owner,
         scxml
       )
       when is_binary(value) do
    value_location
    |> Location.resolve_span(span, value, scxml)
    |> in_value_span(value_location, scxml)
  end

  defp config_value_span(_diagnostic, _owner, _scxml), do: nil

  # The backwards step. `resolve_span/4` is documented to degrade rather
  # than raise, so its answer is bounds-checked against the value it was
  # anchored at before any arithmetic runs on it: decision 1 requires
  # `compile/3` never to raise, and a `binary_part/3` on an out-of-range
  # slice is exactly how that promise would break.
  @spec in_value_span(Location.t(), Location.t(), binary()) ::
          Finding.config_value_span() | nil
  defp in_value_span(%Location{} = resolved, %Location{} = value_location, scxml) do
    if resolved.start_offset >= value_location.start_offset and
         resolved.end_offset <= value_location.end_offset and
         resolved.end_offset >= resolved.start_offset do
      {value_offset(value_location, resolved.start_offset, scxml),
       value_offset(value_location, resolved.end_offset, scxml)}
    end
  end

  # How many bytes of the *author's* value the generated bytes up to
  # `offset` account for. `unescape/1` is the exact inverse of
  # `StatifierBlocks.Compiler.Serializer`'s escaping, and the two must
  # stay a pair: `&` is undone last because it is escaped first, so an
  # author's literal `&lt;` round-trips as itself rather than collapsing
  # into a `<`.
  @spec value_offset(Location.t(), non_neg_integer(), binary()) :: non_neg_integer()
  defp value_offset(%Location{start_offset: start}, offset, scxml) do
    scxml
    |> binary_part(start, offset - start)
    |> unescape()
    |> byte_size()
  end

  @spec unescape(binary()) :: binary()
  defp unescape(escaped) do
    escaped
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&amp;", "&")
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
