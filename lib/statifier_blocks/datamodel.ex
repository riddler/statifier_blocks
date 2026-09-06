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
  decision 6 gives the projection, and the `statifier_datamodel` package
  implements both, so this module reads a document through that one total
  function rather than growing a second reader of a schema. ADR-0006's
  2026-09-06 note records the re-homing: the document is `sd-ADR-0001`'s
  now, and `StatifierDatamodel.Index` and `StatifierDatamodel.Document` are
  where its reads live. Nothing else here moved - the set is still the
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

  ## What counts as declared (11k-11m)

  A datamodel is not the only thing that declares. Two more surfaces do,
  and the 2026-08-31 amendment 11k folds them into the same set this check
  reads:

    * the **compile call's `:declare` roots**, which the editor takes as its
      `declare` assign because it has no compile call of its own to read;
    * the **document's own `datamodel` key** (ADR-0001 decision 11), which
      this module reads straight off the `%StatifierBlocks.Document{}` it is
      already handed - no plumbing, and no way for a caller to forget it.

  Both name **bare roots**, so 11l matches them by root segment: a declared
  root `signup` declares `signup` and everything beneath it. The datamodel's
  own paths are unchanged and still match whole, because the two are
  different claims - a datamodel enumerates the paths a document may
  address, so a path it omits is a path it excluded; a root declaration says
  storage exists at a name and says nothing about what is under it.

  11m widens 11f's precondition to match: the check runs when a datamodel
  was supplied **or** when either surface declares a root, and produces
  nothing at all when nothing anywhere was declared. Precedence does not
  reach here (11k): ADR-0001 11f's host-wins rule decides which `<data>`
  element is emitted for a colliding id, and a root shadowed under it is
  still a declared root.

  ## What this check is not

  It changes no verdict. A document whose only findings are these compiles
  exactly as it did before (11c), and any consumer gating on findings gates
  on `:error` as it always has.

  It is also not `validate_config/1`'s job and cannot be:
  `StatifierBlocks.Core.Assign`'s moduledoc says why - that callback is
  handed a config, not a document, and "is this path declared?" is a
  question about something outside the block entirely. This is the
  document-level pass it names.

  ## The same set, offered forwards (sb-0vt)

  `candidates/3` and `candidates_under/2` read these very surfaces to
  answer the other question an author has about them: not "is the path I
  wrote declared?" but "what is there to write?". They are deliberately in
  this module and not in a new one, because the alternative is two readers
  of three surfaces that would drift - an editor could then offer a path it
  would immediately flag, or flag one it had just offered.

  Offering is not evaluating and it is not editing. ADR-0005 decision 9
  still keeps rich expression editing in statifier-ui behind the
  `expression_component` seam; what changed is that the seam, and the plain
  input the package ships beside it, are now handed the declared paths
  instead of each caller re-deriving them. See `candidates/3` for what is
  deliberately absent from the list.

  ## The uncommitted-draft gap, stated rather than discovered

  The check reads the **document**, so an advisory follows a config that
  has validated and been committed. While the author has an uncommitted
  draft on a field (ADR-0005 decision 9's draft, held in the editor and
  never in the document), the form shows the draft's own findings and this
  advisory is not among them. Whether an advisory should be recomputed
  against a draft is a decision-9 question no record answers, so this
  module does not answer it either.
  """

  alias StatifierBlocks.{Block, BlockType, Document, Finding, Palette}
  alias StatifierBlocks.Document.DatamodelEntry

  # `StatifierDatamodel.Index` is the datamodel document's reader. It is
  # aliased and `StatifierDatamodel.Document` is not, deliberately: `Document`
  # is already this package's own block document above, and two modules of
  # that name in one file is exactly the confusion an alias is supposed to
  # remove. The document-level reads below are spelled out in full.
  alias StatifierDatamodel.Index

  @typedoc """
  The normalized datamodel: the set of paths the host declares, or `nil`
  when the host supplied none.
  """
  @type declared :: MapSet.t(String.t()) | nil

  @typedoc """
  One value a picker offers for a path: a bare string, or the
  `%{label:, value:}` shape a host may write in its own `value_candidates`
  map. Values derived from a datamodel's `one_of` are always bare strings.
  """
  @type candidate :: String.t() | %{optional(atom()) => term()}

  @typedoc """
  Which of the three declaring surfaces 11k names contributed a path.

    * `:datamodel` - the host's datamodel, a set or an ADR-0006 document;
    * `:declare` - the compile call's declared roots;
    * `:document` - the document's own `datamodel` key.
  """
  @type source :: :datamodel | :declare | :document

  @typedoc """
  One row of the read-only declared-path view: a path, every surface that
  declared it, and whatever shape the ADR-0006 projection carries for it.

  `type`, `item_type`, `scope`, `label` and `sensitive?` come from the
  document entry at that path and are `nil` (`false` for the flag) when no
  entry describes it. A bare declared root is exactly that case, and 11l is
  why it is a row with no shape rather than no row: a root says storage
  exists at a name and says nothing about what is under it.
  """
  @type declared_row :: %{
          path: String.t(),
          sources: [source()],
          type: Index.type() | nil,
          item_type: Index.type() | nil,
          scope: Index.scope() | nil,
          label: String.t() | nil,
          sensitive?: boolean()
        }

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

  # The ADR-0006 arm, additive over the three above. The projection is
  # `statifier_datamodel`'s, and its `nil` means the same thing here as it
  # does there: a map carrying a `scopes` key that the record's admission
  # step still declines is an unrecognized shape rather than an empty claim.
  def declared_paths(%{"scopes" => _scopes} = document) do
    StatifierDatamodel.Document.declared_paths(document)
  end

  def declared_paths(_unrecognized), do: nil

  @doc """
  Normalizes the compile call's `:declare` roots to a set of root names.

  11k's second source. The input is the shape
  `StatifierBlocks.Compiler.compile/3` takes - a list of `{id, expr}` pairs
  in declaration order - so a host passes the editor the same list it passes
  the compiler rather than a second spelling of it. A bare id is accepted
  too, and an already-normalized `MapSet` passes through idempotently.

  Total, like `declared_paths/1`, and for the same reason: a shape this
  package does not know normalizes to the empty set, which per 11m declares
  nothing rather than declaring that nothing exists. There is no `nil` here -
  a root set is never a claim about paths, so it has no "no datamodel
  supplied" state to distinguish.

      iex> StatifierBlocks.Datamodel.declared_roots([{"signup", nil}, {"card", "0"}])
      MapSet.new(["card", "signup"])

      iex> StatifierBlocks.Datamodel.declared_roots(["signup"])
      MapSet.new(["signup"])

      iex> StatifierBlocks.Datamodel.declared_roots(nil)
      MapSet.new([])

      iex> StatifierBlocks.Datamodel.declared_roots([{"signup", nil}, 42, {"", nil}])
      MapSet.new(["signup"])
  """
  @spec declared_roots(term()) :: MapSet.t(String.t())
  def declared_roots(nil), do: MapSet.new()

  def declared_roots(%MapSet{} = set) do
    set |> MapSet.to_list() |> declared_roots()
  end

  def declared_roots(declare) when is_list(declare) do
    declare
    |> Enum.map(fn
      {id, _expr} -> id
      id when is_binary(id) -> id
      _other -> nil
    end)
    |> Enum.filter(&declared_path?/1)
    |> MapSet.new()
  end

  def declared_roots(_unrecognized), do: MapSet.new()

  @doc """
  Every undeclared-path advisory in the document (11e), or `[]` when nothing
  anywhere declared anything (11f as 11m widens it).

  `datamodel` is normalized through `declared_paths/1` and `declare` through
  `declared_roots/1`, so a raw list and an already-normalized set behave
  identically in both. The document's own roots are read off `document` and
  take no argument.

  A path is declared when the datamodel holds it whole or when either
  declaration surface holds its root segment (11k, 11l).

  A block whose type the palette cannot resolve produces nothing here - it
  already has a `:resolution` finding from `StatifierBlocks.ViewModel`, and
  a block with no schema declares no datamodel path. A field annotated
  `datamodel_path?: true` whose value is missing or is not a non-empty
  string produces nothing either: that is `validate_config/1`'s to refuse,
  at `:error`, and an advisory beside it would say the same thing twice in
  two voices.
  """
  @spec findings(Document.t(), Palette.t(), term(), term()) :: [Finding.t()]
  def findings(%Document{} = document, %Palette{} = palette, datamodel, declare \\ []) do
    declared = declared_paths(datamodel)
    roots = MapSet.union(declared_roots(declare), document_roots(document))

    if is_nil(declared) and MapSet.size(roots) == 0 do
      []
    else
      undeclared_findings(document, palette, declared || MapSet.new(), roots)
    end
  end

  @doc """
  The declared datamodel paths an expression control offers as candidates,
  sorted and deduplicated - the data half of sb-0vt, and nothing else.

  This reads the same three declaring surfaces `findings/4` does, by the
  same normalizers, so the set an author is offered and the set that
  decides whether they get an advisory cannot drift apart: the host's
  datamodel through `declared_paths/1`, the compile call's roots through
  `declared_roots/1`, and the document's own `datamodel` key read straight
  off `document`, which is why that surface takes no argument here either.

  Absence collapses to `[]` rather than to `nil`. That is a deliberate
  difference from the advisory above, and it is not a rescue-to-default:
  `nil` is load-bearing for `findings/4` because "nobody described
  anything" and "somebody described nothing" are different claims about a
  *path the author already wrote*. A candidate list makes no claim about
  anything - it either has something to offer or it does not - so both
  cases are one empty list, and the caller renders no control for it.

  A root and a path are both offered whole. A declared root means storage
  exists at a name and says nothing about what is under it (11l), so
  `signup` is the only candidate it can contribute; the datamodel document
  is what contributes `signup.email`.

  ## What this is not

  It is not the completion feature. ADR-0005 decision 9 keeps rich
  expression editing - completion against the datamodel as an affordance,
  inline evaluation against a dataset - in statifier-ui behind the
  `expression_component` seam, and this function does not move it. It
  supplies the one part of that affordance this package owns the data for,
  so the seam's implementer does not have to re-derive it and the shipped
  plain input can offer a `<datalist>` in the meantime.

  Operators, keywords and literals are **not** here and cannot be yet.
  Predicator exposes no public enumeration of its grammar - operator and
  keyword tokens live inside `Predicator.Lexer` - and copying that
  vocabulary into this package would be a second, silently drifting copy
  of a contract predicator owns. That half is px-15q's.

      iex> alias StatifierBlocks.{Block, Datamodel, Document}
      iex> document = Document.new(Block.new("core.sequence", id: "blk_root"), id: "doc_x")
      iex> Datamodel.candidates(document, ["card.brand", "card"], ["signup"])
      ["card", "card.brand", "signup"]

      iex> alias StatifierBlocks.{Block, Datamodel, Document}
      iex> document = Document.new(Block.new("core.sequence", id: "blk_root"), id: "doc_x")
      iex> Datamodel.candidates(document, nil, [])
      []
  """
  @spec candidates(Document.t(), term(), term()) :: [String.t()]
  def candidates(%Document{} = document, datamodel, declare \\ []) do
    (declared_paths(datamodel) || MapSet.new())
    |> MapSet.union(declared_roots(declare))
    |> MapSet.union(document_roots(document))
    |> Enum.sort()
  end

  @doc """
  The candidates strictly under `prefix`, in the datamodel document's own
  order - ADR-0006 decision 6's completion query, reached through
  `StatifierDatamodel.Document.candidates_under/2` rather than restated
  here.

  This is the narrowing query the `expression_component` seam needs and the
  shipped `<datalist>` does not: a datalist is handed the whole set once and
  the browser filters it, while a component that re-renders per keystroke
  wants only the branch the author is inside. Both read the same document,
  through the same one implementation of the projection.

  `prefix` itself is not among the results, matching `under/2`; a datamodel
  that is not an ADR-0006 document has no order to query and returns `[]`,
  which is the same total-normalizer discipline `declared_paths/1` applies
  to the same input.

      iex> alias StatifierBlocks.Datamodel
      iex> Datamodel.candidates_under(
      ...>   %{"scopes" => [%{"scope" => "local", "entries" => [
      ...>     %{"path" => "card", "type" => "object", "fields" => [
      ...>       %{"path" => "card.brand"}, %{"path" => "card.last4"}]}]}]},
      ...>   "card")
      ["card.brand", "card.last4"]

      iex> StatifierBlocks.Datamodel.candidates_under(["card.brand"], "card")
      []
  """
  @spec candidates_under(term(), term()) :: [String.t()]
  def candidates_under(datamodel, prefix) do
    StatifierDatamodel.Document.candidates_under(datamodel, prefix)
  end

  @doc """
  The value candidates a picker offers per datamodel path: the ADR-0006
  `one_of` enumerations the datamodel declares, with the host's own map
  merged over them per path.

  ADR-0005's 2026-09-05 note is the record for this, and its own summary is
  that `value_candidates` "narrows in meaning and not in shape": it is still
  the same `%{path => [candidate]}` a host has always been able to supply,
  and what changed is that supplying nothing is no longer the same as there
  being nothing.

  **Merged over, per path, means replacement at the path.** A path the
  host's map names uses the host's list and only the host's list; a path it
  does not name keeps the declared enumeration; a path with neither is
  absent from the result entirely and gets a free-text value control. Not a
  union, and the reason is that a union has no author: if a host lists three
  values for a path whose datamodel declares five, the host is correcting
  the datamodel for this editor, and a control answering eight would be
  showing a set nobody declared. An empty list is therefore a suppression a
  host can write, and it is carried through as one.

  The enumeration is read off the ADR-0006 index through
  `StatifierDatamodel.Document.declared_values/1`, which is the only reader
  that has it: `candidates/3` answers path strings and carries no per-path shape at
  all, and `declared_view/3`'s rows carry `type`, `item_type`, `scope`,
  `label` and `sensitive?` and not `one_of`.

  A declared value is offered when it can be drawn as an option - a string
  as itself, a number or a boolean as its printed form. Anything else, a
  list or an object or a `null`, is dropped, and a path whose whole
  enumeration drops out is absent rather than present and empty.

  ## This does not promote the hint

  Nothing here validates and nothing refuses. ADR-0006 carries `one_of` as
  "a completion hint listing the values a host expects" and leaves whether
  it is a hint or a claim as an open question; defaulting a picker from it
  is a *use* of the hint rather than an answer to that question, and a value
  control fed from it still admits anything the author types. That is the
  same suggests-never-constrains posture the path `<datalist>` takes and
  that the 11e advisory takes on an undeclared path.

  Both arguments are read totally, like every other normalizer here: a
  datamodel that is not an ADR-0006 document declares no enumerations, and a
  host map that is not a plain map supplies no entries.

      iex> alias StatifierBlocks.Datamodel
      iex> datamodel = %{"scopes" => [%{"scope" => "local", "entries" => [
      ...>   %{"path" => "signup.step", "type" => "string",
      ...>     "one_of" => ["details", "payment", "review"]},
      ...>   %{"path" => "signup.email", "type" => "string"}]}]}
      iex> Datamodel.value_candidates(datamodel)
      %{"signup.step" => ["details", "payment", "review"]}

      iex> alias StatifierBlocks.Datamodel
      iex> datamodel = %{"scopes" => [%{"scope" => "local", "entries" => [
      ...>   %{"path" => "signup.step", "one_of" => ["details", "payment"]},
      ...>   %{"path" => "card.brand", "one_of" => ["visa", "amex"]}]}]}
      iex> datamodel
      ...> |> Datamodel.value_candidates(%{"signup.step" => ["payment"]})
      ...> |> Enum.sort()
      [{"card.brand", ["visa", "amex"]}, {"signup.step", ["payment"]}]

      iex> StatifierBlocks.Datamodel.value_candidates(nil, %{"card.brand" => ["visa"]})
      %{"card.brand" => ["visa"]}

      iex> StatifierBlocks.Datamodel.value_candidates(["card.brand"])
      %{}
  """
  @spec value_candidates(term(), term()) :: %{optional(String.t()) => [candidate()]}
  def value_candidates(datamodel, host \\ %{}) do
    datamodel
    |> StatifierDatamodel.Document.declared_values()
    |> Map.merge(host_values(host))
  end

  @doc """
  Every declared path, with the surfaces that declared it and the shape the
  ADR-0006 projection carries for it - the read-only view of what the 11e
  advisory reads.

  The rows are `candidates/3`'s set, in `candidates/3`'s order, and that is
  the point rather than a convenience: the advisory decides "is the path
  this author wrote declared?" against the union of 11k's three surfaces,
  so a view that showed only one of them would answer a different question
  than the one the author is looking at a finding about. Reading the three
  through the same normalizers here is the same anti-drift rule
  `candidates/3` is written under.

  `sources` is a list because the surfaces overlap legitimately: a host
  that declares a root and also enumerates it in its datamodel document has
  said the same thing twice, and a row that named only the first would hide
  the second.

  Shape comes from the ADR-0006 document alone, through
  `StatifierDatamodel.Index.fetch/2`, and is absent for
  everything else. A set of paths carries no types, and a declared root
  carries none by 11l, so those rows are shapeless rather than guessed at.

      iex> alias StatifierBlocks.{Block, Datamodel, Document}
      iex> document = Document.new(Block.new("core.sequence", id: "blk_root"), id: "doc_x")
      iex> datamodel = %{"scopes" => [%{"scope" => "local", "entries" => [
      ...>   %{"path" => "card.brand", "type" => "string", "label" => "Brand"}]}]}
      iex> Datamodel.declared_view(document, datamodel, ["signup"])
      [
        %{path: "card.brand", sources: [:datamodel], type: :string, item_type: nil,
          scope: :local, label: "Brand", sensitive?: false},
        %{path: "signup", sources: [:declare], type: nil, item_type: nil,
          scope: nil, label: nil, sensitive?: false}
      ]

      iex> alias StatifierBlocks.{Block, Datamodel, Document}
      iex> document = Document.new(Block.new("core.sequence", id: "blk_root"), id: "doc_x")
      iex> Datamodel.declared_view(document, nil, [])
      []
  """
  @spec declared_view(Document.t(), term(), term()) :: [declared_row()]
  def declared_view(%Document{} = document, datamodel, declare \\ []) do
    index = Index.index(datamodel)

    surfaces = [
      datamodel: declared_paths(datamodel) || MapSet.new(),
      declare: declared_roots(declare),
      document: document_roots(document)
    ]

    surfaces
    |> Enum.reduce(MapSet.new(), fn {_name, set}, acc -> MapSet.union(acc, set) end)
    |> Enum.sort()
    |> Enum.map(&row(&1, surfaces, index))
  end

  @spec row(String.t(), keyword(MapSet.t(String.t())), Index.t() | nil) ::
          declared_row()
  defp row(path, surfaces, index) do
    entry = entry_at(index, path)

    %{
      path: path,
      sources: for({name, set} <- surfaces, MapSet.member?(set, path), do: name),
      type: Map.get(entry, :type),
      item_type: Map.get(entry, :item_type),
      scope: Map.get(entry, :scope),
      label: Map.get(entry, :label),
      sensitive?: Map.get(entry, :sensitive?) == true
    }
  end

  # An empty map rather than `nil`, so the row above reads every field the
  # same way whether an entry describes the path or nothing does.
  @spec entry_at(Index.t() | nil, String.t()) :: map()
  defp entry_at(nil, _path), do: %{}

  defp entry_at(index, path) do
    case Index.fetch(index, path) do
      {:ok, entry} -> entry
      :error -> %{}
    end
  end

  # A struct is a map and is not a candidate map, so the shape check is
  # narrower than `is_map/1`. Same total-normalizer discipline as
  # `declared_paths/1`: an unrecognized shape behaves as though nothing was
  # passed.
  @spec host_values(term()) :: %{optional(String.t()) => [candidate()]}
  defp host_values(host) when is_map(host) and not is_struct(host), do: host
  defp host_values(_unrecognized), do: %{}

  # The document declares its own roots, and this module is handed the
  # document, so 11k source 3 needs no argument: a caller cannot pass the
  # wrong one or forget it. An `id` is a bare identifier by the time a
  # document validates (ADR-0001 decision 11), so the filter here is the
  # same total discipline the rest of this module applies rather than a
  # second place for that schema rule to live.
  @spec document_roots(Document.t()) :: MapSet.t(String.t())
  defp document_roots(%Document{datamodel: entries}) when is_list(entries) do
    entries
    |> Enum.map(fn
      %DatamodelEntry{id: id} -> id
      _other -> nil
    end)
    |> Enum.filter(&declared_path?/1)
    |> MapSet.new()
  end

  defp document_roots(_document), do: MapSet.new()

  @spec undeclared_findings(
          Document.t(),
          Palette.t(),
          MapSet.t(String.t()),
          MapSet.t(String.t())
        ) :: [Finding.t()]
  defp undeclared_findings(document, palette, declared, roots) do
    document
    |> Document.blocks()
    |> Enum.flat_map(fn block ->
      case Palette.resolve(palette, block) do
        {:ok, module, resolved} ->
          block_findings(block, module, resolved.config, declared, roots)

        {:error, _reason} ->
          []
      end
    end)
  end

  @spec block_findings(
          Block.t(),
          module(),
          Block.config(),
          MapSet.t(String.t()),
          MapSet.t(String.t())
        ) :: [Finding.t()]
  defp block_findings(%Block{id: id}, module, config, declared, roots) do
    config
    |> module.config_schema()
    |> Enum.filter(&BlockType.datamodel_path?/1)
    |> Enum.flat_map(fn decl ->
      case BlockType.fetch_value(config, BlockType.value_path(decl)) do
        {:ok, path} -> advisory(id, decl.key, path, declared, roots)
        :error -> []
      end
    end)
  end

  @spec advisory(
          Block.id(),
          String.t(),
          Block.json(),
          MapSet.t(String.t()),
          MapSet.t(String.t())
        ) :: [Finding.t()]
  defp advisory(block_id, key, path, declared, roots) do
    if declared_path?(path) and not declared?(path, declared, roots) do
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

  # 11l, the two membership rules in one place. The datamodel matches a path
  # whole; a declared root matches the segment before the first dot, so a
  # root declares itself and everything beneath it.
  @spec declared?(String.t(), MapSet.t(String.t()), MapSet.t(String.t())) :: boolean()
  defp declared?(path, declared, roots) do
    MapSet.member?(declared, path) or MapSet.member?(roots, root_segment(path))
  end

  @spec root_segment(String.t()) :: String.t()
  defp root_segment(path), do: path |> String.split(".", parts: 2) |> hd()

  @spec declared_path?(term()) :: boolean()
  defp declared_path?(path), do: is_binary(path) and path != ""
end
