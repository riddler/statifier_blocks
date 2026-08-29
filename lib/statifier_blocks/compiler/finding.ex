defmodule StatifierBlocks.Compiler.Finding do
  @moduledoc """
  One thing the compiler has to say about one block (ADR-0004 decision 10).

  Every finding names a block. There is no chart-level finding without an
  owner, which is what lets an editor render findings as annotations on the
  tree with no fallback presentation, and decision 5's totality is what
  buys it for the `:chart` stage - the one stage whose findings arrive with
  no idea that blocks exist.

  ## The pipeline, and which stage produces what

  | Stage | Errors it produces |
  |---|---|
  | `:document` | `:invalid_document` - `Document.validate/1`'s reason |
  | `:resolve` | `:unknown_block_type`, `:block_type_too_new`, `:migration_failed` |
  | `:config` | `validate_config/1` findings, one per `{key, message}` pair |
  | `:structure` | `:slot_arity_violated`, `:undeclared_slot` (ADR-0002 decision 6); assignability (ADR-0003) |
  | `:emit` | `emit/2` findings, `:invalid_role`, `:reserved_role`, `:invalid_outcome`, `:duplicate_binding` (ADR-0004's foreach amendment, F6), `:unspliced_child`, `:unknown_attribution` |
  | `:chart` | mapped statifier findings, both faults (decision 9) |

  The pipeline stops at the first stage that produces errors and reports
  every error from that stage. Stopping rather than accumulating across
  stages is deliberate: a document with an unresolvable block type has no
  meaningful structural check to run, and reporting a cascade of
  consequences beside the cause is how an error panel becomes noise. Within
  a stage every finding is reported, because those are siblings rather than
  consequences.

  The `:document` stage is not in decision 10's table, and it is not a new
  decision either: decision 1 requires `compile/3` never to raise, and
  `Document.to_json/1` raises on a document that fails ADR-0001's
  structural rules. Checking first and reporting it as a finding is what
  totality costs. It runs before `:resolve` because a document that is not
  structurally a document has no blocks worth resolving.

  ## `fault`: whose problem is this?

  Decision 9 states the split for the `:chart` stage, where it is subtle
  because the finding was raised against generated SCXML by a validator
  that has never heard of blocks. The rule generalizes, and this module
  applies the generalized form at every stage:

    * `:author` - a document edit fixes it. Every `:config` finding, every
      `:structure` finding (an author placed the block), and every `:chart`
      finding whose owning span carries a config key.
    * `:package` - a bug in this package or in a host's block type, and no
      edit to the document will help. `:resolve` findings (the palette is
      the host's, not the author's), every `:emit` finding that names no
      config key, and every `:chart` finding whose owning span carries no
      config key: an author cannot express `{:unresolved_target, id}`,
      because the block vocabulary has no way to name a state id.

  The editor renders the two differently, and "this cannot be fixed here"
  is the only honest message for the second.

  ## `severity`

  `:error` fails the compile; `:warning` rides on
  `StatifierBlocks.Compiled`'s `warnings` and does not. Upstream warnings
  (st-ADR-0033) and decision 8's optional invoke-type lint are the two
  sources of warnings, and decision 8 is explicit that the lint is never
  an error.
  """

  alias StatifierBlocks.{Block, Document}

  @typedoc "The pipeline stage that produced this finding."
  @type stage :: :document | :resolve | :config | :structure | :emit | :chart

  @typedoc "Whose problem this is. See the moduledoc."
  @type fault :: :package | :author

  @type t :: %__MODULE__{
          stage: stage(),
          block_id: Block.id() | nil,
          path: Document.path() | nil,
          config_key: String.t() | nil,
          severity: :error | :warning,
          fault: fault(),
          code: atom(),
          reason: term(),
          message: String.t()
        }

  @enforce_keys [:stage, :reason, :message]
  defstruct [
    :stage,
    :block_id,
    :path,
    :config_key,
    :reason,
    :message,
    :code,
    severity: :error,
    fault: :package
  ]

  @doc """
  Builds a finding.

  `opts` carries `:block_id`, `:path`, `:config_key`, `:severity`,
  `:fault` and `:code`. `code` defaults to `reason`'s own tag, which is the
  stable atom an editor switches on while `reason` keeps carrying the
  offending ids as data - the same split
  `Statifier.Validator.Error.code/1` makes upstream. `fault` defaults to
  the stage's own rule, refined by whether a config key is present.
  """
  @spec new(stage(), term(), String.t(), keyword()) :: t()
  def new(stage, reason, message, opts \\ []) do
    config_key = Keyword.get(opts, :config_key)

    %__MODULE__{
      stage: stage,
      block_id: Keyword.get(opts, :block_id),
      path: Keyword.get(opts, :path),
      config_key: config_key,
      severity: Keyword.get(opts, :severity, :error),
      fault: Keyword.get_lazy(opts, :fault, fn -> fault(stage, config_key) end),
      code: Keyword.get_lazy(opts, :code, fn -> code(reason) end),
      reason: reason,
      message: message
    }
  end

  @doc """
  `reason`'s stable tag: the tuple's first element, or the reason itself
  when it is already an atom.
  """
  @spec code(term()) :: atom()
  def code(reason) when is_tuple(reason) and tuple_size(reason) > 0 do
    case elem(reason, 0) do
      tag when is_atom(tag) -> tag
      _other -> :unknown
    end
  end

  def code(reason) when is_atom(reason), do: reason
  def code(_reason), do: :unknown

  # The stage's default fault, refined by whether the finding lands on a
  # config field the author typed into. `:config` and `:structure` are the
  # author's by construction; the rest are the package's unless a config
  # key says otherwise.
  @spec fault(stage(), String.t() | nil) :: fault()
  defp fault(stage, _config_key) when stage in [:config, :structure], do: :author
  defp fault(_stage, nil), do: :package
  defp fault(_stage, _config_key), do: :author
end
