defmodule StatifierBlocks.Compiled do
  @moduledoc """
  What one successful compile produced (ADR-0004 decision 1).

  Nothing in here is written back into the document. ADR-0001 decision 2
  forbade storing derived data in the document and named the provenance map
  specifically. A host stores this artifact beside the document or
  recomputes it - both are correct, and decision 6's determinism is what
  makes them equivalent.

  ## Two fields now, three more from sb-qz0

  Decision 1 lists five things the artifact carries: the generated SCXML,
  the provenance map, the compilation record, the emitted invoke types, and
  any warnings. This bead (sb-ort) implements decisions 1-4 and 6-7 and so
  ships the two that are functions of those: `scxml` and `record`.

  `provenance` (decision 5), `invoke_types` (decision 8) and `warnings`
  (decisions 8-9) are **sb-qz0's**, and are deliberately absent rather than
  present-and-always-empty: a field that is always `%{}` reads as "this
  document had no provenance", which is never true, and a consumer written
  against it would have to be rewritten when the field started carrying
  data anyway.
  """

  alias StatifierBlocks.CompilationRecord

  @type t :: %__MODULE__{
          scxml: binary(),
          record: CompilationRecord.t()
        }

  @enforce_keys [:scxml, :record]
  defstruct [:scxml, :record]
end
