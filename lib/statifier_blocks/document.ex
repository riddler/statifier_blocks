defmodule StatifierBlocks.Document.DatamodelEntry do
  @moduledoc """
  One root the document itself declares (ADR-0001 decision 11).

  A document-declared root is a top-level `datamodel` entry: an `id` the
  document's own guards and assigns read, an optional `expr` the root
  starts with, and an optional `description` for a human reading the
  document rather than for the chart - it is prose, never compiled and
  never emitted (`StatifierBlocks.Compiler.DeclaredRoots.document_declarations/1`
  drops it). This is the document's own declaration surface, distinct from
  the compile call's `:declare` option, which leads it
  (`StatifierBlocks.Compiler`'s moduledoc).
  """

  @type t :: %__MODULE__{
          id: String.t(),
          expr: String.t() | nil,
          description: String.t() | nil
        }

  @enforce_keys [:id]
  defstruct [:id, :expr, :description]
end

defmodule StatifierBlocks.Document do
  @moduledoc """
  A block document: one tree, one envelope (ADR-0001).

  This module is the package's single public entry point over the tree:
  construction, the shared pre-order walk, and path lookup live here.
  Canonical encoding, content identity, and structural decoding land in
  later phases of the same bead.

  The document also carries its own `datamodel` key: a list of
  `StatifierBlocks.Document.DatamodelEntry` structs naming the `<data>`
  roots the document's own guards and assigns read (ADR-0001 decision 11).
  It follows, never leads, the compile call's `:declare` option - see
  `StatifierBlocks.Compiler`'s moduledoc for the precedence rule.

  `committed_config/2` and `effective_config/3` are the two config readers
  a surface asks the document, public because the reference embedder's Plan
  view - the first consumer of both - had written them out privately in
  order to draw a config form over a document at all. They are lookups over
  `blocks/1`: what the document says, and what a held draft says instead.
  """

  alias StatifierBlocks.{Block, CanonicalJson, Decode, Validation}
  alias StatifierBlocks.Document.DatamodelEntry

  @typedoc ~S(`"bdoc_" <> uxid`.)
  @type id :: String.t()

  @type t :: %__MODULE__{
          schema_version: pos_integer(),
          id: id(),
          revision: non_neg_integer(),
          root: Block.t(),
          metadata: %{optional(String.t()) => Block.json()},
          datamodel: [DatamodelEntry.t()]
        }

  defstruct [:id, :root, schema_version: 1, revision: 0, metadata: %{}, datamodel: []]

  @typedoc "Derived, never stored. Identifies a position, not a block."
  @type path :: [{Block.id(), Block.slot_name(), non_neg_integer()}]

  @typedoc """
  ADR-0001's typespec block: everything `validate/1` and `from_json/1` can
  reject, defined once.
  """
  @type validation_error ::
          :not_a_block_document
          | {:unsupported_schema_version, pos_integer()}
          | {:duplicate_block_id, Block.id()}
          | {:malformed_block, Block.id() | nil, term()}
          | {:malformed_envelope, term()}

  @doc """
  Wraps `root` in a document envelope.

  Options: `:id` (default a freshly minted `StatifierBlocks.Id.document/0`),
  `:revision` (default `0`), `:metadata` (default `%{}`), `:datamodel`
  (default `[]`, a list of `StatifierBlocks.Document.DatamodelEntry`
  structs - ADR-0001 decision 11). `:schema_version` is not an option -
  decision 7 fixes it at `1` for this ADR's envelope.
  """
  @spec new(Block.t(), keyword()) :: t()
  def new(%Block{} = root, opts \\ []) do
    %__MODULE__{
      id: Keyword.get_lazy(opts, :id, &StatifierBlocks.Id.document/0),
      root: root,
      revision: Keyword.get(opts, :revision, 0),
      metadata: Keyword.get(opts, :metadata, %{}),
      datamodel: Keyword.get(opts, :datamodel, [])
    }
  end

  @doc """
  Every block in `document`, pre-order, root first.

  Within a block, slots are visited in UTF-8-sorted slot-name order so
  every consumer of this walk sees one deterministic order regardless of
  how the `slots` map happened to be built. Later phases (encoding,
  validation) build on this walk rather than re-deriving their own.
  """
  @spec blocks(t()) :: [Block.t()]
  def blocks(%__MODULE__{root: root}), do: walk(root)

  @spec walk(Block.t()) :: [Block.t()]
  defp walk(%Block{slots: slots} = block) do
    children =
      slots
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.flat_map(fn {_slot_name, children} -> children end)
      |> Enum.flat_map(&walk/1)

    [block | children]
  end

  @doc """
  The path from the root to the block carrying `id`.

  A path names the `{parent block id, slot name, index}` steps taken from
  the root, so the root's own path is `{:ok, []}` - it has taken none.
  Returns `:error` when no block in `document` carries `id`.
  """
  @spec fetch_path(t(), Block.id()) :: {:ok, path()} | :error
  def fetch_path(%__MODULE__{root: %Block{id: id}}, id), do: {:ok, []}

  def fetch_path(%__MODULE__{root: root}, id) do
    find_path(root, id)
  end

  @spec find_path(Block.t(), Block.id()) :: {:ok, path()} | :error
  defp find_path(%Block{slots: slots} = block, id) do
    slots
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.find_value(:error, fn {slot_name, children} ->
      find_in_slot(block.id, slot_name, children, id, 0)
    end)
  end

  @spec find_in_slot(Block.id(), Block.slot_name(), [Block.t()], Block.id(), non_neg_integer()) ::
          {:ok, path()} | false
  defp find_in_slot(_parent_id, _slot_name, [], _id, _index), do: false

  defp find_in_slot(parent_id, slot_name, [%Block{id: id} | _rest], id, index) do
    {:ok, [{parent_id, slot_name, index}]}
  end

  defp find_in_slot(parent_id, slot_name, [child | rest], id, index) do
    case find_path(child, id) do
      {:ok, path} -> {:ok, [{parent_id, slot_name, index} | path]}
      :error -> find_in_slot(parent_id, slot_name, rest, id, index + 1)
    end
  end

  @doc """
  The config the document holds for the block carrying `id`, or `%{}` when
  no block in `document` carries it.

  A lookup over `blocks/1` and nothing else: what the document says, with
  no draft, no palette and no schema anywhere near the answer. The first
  consumer is the reference embedder's Plan view, which needs the
  committed config in order to show what an editor's unaccepted draft would
  change; the package's own editor asks the same question for the same
  reason.

  `%{}` for an absent block rather than `nil`, because every caller is
  about to read config keys out of the answer and a block that is not there
  has none of them - the same shape as a block that carries no config at
  all.

      iex> alias StatifierBlocks.{Block, Document}
      iex> root =
      ...>   Block.new("core.sequence",
      ...>     id: "root",
      ...>     slots: %{"body" => [Block.new("core.wait", id: "wait", config: %{"duration" => "30s"})]}
      ...>   )
      iex> document = Document.new(root)
      iex> Document.committed_config(document, "wait")
      %{"duration" => "30s"}
      iex> Document.committed_config(document, "absent")
      %{}
  """
  @spec committed_config(t(), Block.id()) :: Block.config()
  def committed_config(%__MODULE__{} = document, id) do
    case Enum.find(blocks(document), &(&1.id == id)) do
      %Block{config: config} -> config
      nil -> %{}
    end
  end

  @doc """
  The config a surface should act on for the block carrying `id`: the
  draft `drafts` holds for it, else `committed_config/2`.

  A draft is config the document refused, held so the author keeps their
  keystrokes (ADR-0002 decision 9). Reading a form back, or offering a
  value to a field control, has to start from the draft where one exists
  or the author's second edit is applied to the value their first one
  replaced.

  `drafts` is the map a surface keeps of block id to unaccepted config.

      iex> alias StatifierBlocks.{Block, Document}
      iex> root =
      ...>   Block.new("core.sequence",
      ...>     id: "root",
      ...>     slots: %{"body" => [Block.new("core.wait", id: "wait", config: %{"duration" => "30s"})]}
      ...>   )
      iex> document = Document.new(root)
      iex> Document.effective_config(document, "wait", %{"wait" => %{"duration" => "48h"}})
      %{"duration" => "48h"}
      iex> Document.effective_config(document, "wait", %{})
      %{"duration" => "30s"}
  """
  @spec effective_config(t(), Block.id(), %{optional(Block.id()) => Block.config()}) ::
          Block.config()
  def effective_config(%__MODULE__{} = document, id, drafts) when is_map(drafts) do
    case Map.fetch(drafts, id) do
      {:ok, draft} -> draft
      :error -> committed_config(document, id)
    end
  end

  @doc """
  `effective_config/3` for a caller holding no drafts: `committed_config/2`.

  It exists so that a surface that has not grown drafts yet, and a test
  that is not about them, need not invent an empty map in order to say
  there are none.

      iex> alias StatifierBlocks.{Block, Document}
      iex> root =
      ...>   Block.new("core.sequence",
      ...>     id: "root",
      ...>     slots: %{"body" => [Block.new("core.wait", id: "wait", config: %{"duration" => "30s"})]}
      ...>   )
      iex> Document.effective_config(Document.new(root), "wait")
      %{"duration" => "30s"}
  """
  @spec effective_config(t(), Block.id()) :: Block.config()
  def effective_config(%__MODULE__{} = document, id), do: committed_config(document, id)

  @doc """
  Checks `document` against ADR-0001's structural rules: schema version,
  envelope shape (including the `datamodel` key's own entry shape and id
  uniqueness - decision 11), per-block shape (id, type, type_version,
  config, slots), and document-wide id uniqueness. Never consults a
  block-type registry - `config` is opaque here and `type` is never
  resolved against anything.
  """
  @spec validate(t()) :: :ok | {:error, validation_error()}
  def validate(%__MODULE__{} = document), do: Validation.validate(document)

  @doc """
  Canonical JSON per ADR-0001 decision 8. Deterministic: sorted object keys,
  no insignificant whitespace, empty `slots`/`config`/`metadata`/`datamodel`
  omitted, no floats.

  Runs `validate/1` first and raises `ArgumentError` carrying the validation
  reason when it fails, so an invalid document can never produce bytes that
  claim to be canonical.
  """
  @spec to_json(t()) :: binary()
  def to_json(%__MODULE__{} = document) do
    case validate(document) do
      :ok ->
        document
        |> CanonicalJson.encode()
        |> IO.iodata_to_binary()

      {:error, reason} ->
        raise ArgumentError, "cannot encode an invalid document: #{inspect(reason)}"
    end
  end

  @doc "SHA-256 over `to_json/1`. Stable document identity."
  @spec content_hash(t()) :: binary()
  def content_hash(%__MODULE__{} = document) do
    "sha256:" <> Base.encode16(:crypto.hash(:sha256, to_json(document)), case: :lower)
  end

  @doc """
  Structural decode. Never consults the block-type registry (ADR-0001
  decision 9); unknown `type` names decode successfully.

  Decoding is total and ordered: bytes that are not a JSON object carrying
  a `"schema_version"` key are `:not_a_block_document`; a recognizable
  document that is wrong in a specific way gets an envelope-, block-, or
  id-level arm instead. Nothing is rescued to a default and nothing raises.

  An envelope key outside the known set (`id`, `revision`, `root`,
  `schema_version`, `metadata`, `datamodel` - decision 11 added the last)
  is refused rather than silently dropped, the same discipline the
  block-level decode already applies to an unrecognized block key.
  """
  @spec from_json(binary()) :: {:ok, t()} | {:error, validation_error()}
  def from_json(binary) when is_binary(binary), do: Decode.decode(binary)
end
