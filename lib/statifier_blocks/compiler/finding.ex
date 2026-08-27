defmodule StatifierBlocks.Compiler.Finding do
  @moduledoc """
  One thing the compiler has to say about one block (ADR-0004 decision 10).

  Every finding names a block. There is no chart-level finding without an
  owner, which is what lets an editor render findings as annotations on the
  tree with no fallback presentation.

  ## What this bead fixes, and what sb-qz0 adds

  Decision 10 is **sb-qz0's** record to implement in full: the block path,
  the config-key refinement, the severity split, and the `Chart` stage's
  mapped statifier findings all land there. What sb-ort needs, and all it
  fixes here, is the shape a finding has and the stages that can produce
  one before provenance exists:

  | Stage | Errors it produces here |
  |---|---|
  | `:document` | `:invalid_document` - `Document.validate/1`'s reason |
  | `:resolve` | `:unknown_block_type`, `:block_type_too_new`, `:migration_failed` |
  | `:config` | `validate_config/1` findings, one per `{key, message}` pair |
  | `:emit` | `emit/2` findings, `:invalid_role`, `:unspliced_child` |

  The `:document` stage is not in decision 10's table, and it is not a new
  decision either: decision 1 requires `compile/3` never to raise, and
  `Document.to_json/1` raises on a document that fails ADR-0001's
  structural rules. Checking first and reporting it as a finding is what
  totality costs. It runs before `:resolve` because a document that is not
  structurally a document has no blocks worth resolving.

  The pipeline stops at the first stage that produces errors and reports
  every error from that stage. Stopping rather than accumulating across
  stages is deliberate: a document with an unresolvable block type has no
  meaningful config check to run, and reporting a cascade of consequences
  beside the cause is how an error panel becomes noise.
  """

  alias StatifierBlocks.Block

  @typedoc "The pipeline stage that produced this finding."
  @type stage :: :document | :resolve | :config | :emit

  @type t :: %__MODULE__{
          stage: stage(),
          block_id: Block.id() | nil,
          config_key: String.t() | nil,
          reason: term(),
          message: String.t()
        }

  @enforce_keys [:stage, :reason, :message]
  defstruct [:stage, :block_id, :config_key, :reason, :message]

  @doc "Builds a finding. `opts` carries `:block_id` and `:config_key`."
  @spec new(stage(), term(), String.t(), keyword()) :: t()
  def new(stage, reason, message, opts \\ []) do
    %__MODULE__{
      stage: stage,
      block_id: Keyword.get(opts, :block_id),
      config_key: Keyword.get(opts, :config_key),
      reason: reason,
      message: message
    }
  end
end
