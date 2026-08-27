defmodule StatifierBlocks.CompilationRecord do
  @moduledoc """
  The join between a block document and the chart it compiled to (ADR-0004
  decision 7).

  Document identity hashes what an author *wrote*; chart identity hashes
  what the compiler *generated*; decision 6's determinism is the function
  between them:

      document bytes + palette + compiler version  --compile-->  SCXML bytes
              |                                                       |
           sha256                                                  sha256
              v                                                       v
       document identity                                      chart identity

  Neither is derived from the other, and neither should be. Deriving chart
  identity from the document hash would be hashing the wrong bytes: two
  documents differing only in `metadata` generate identical SCXML and must
  get the same chart identity, or a metadata edit would break resume for
  every running session. Deriving document identity from chart identity is
  not even a function - the mapping is many-to-one in exactly that case.

  Hashes do not invert, so the compiler emits the join as a fact. The
  record is the artifact's primary key: given a running session, which
  names a chart identity, look up by `chart_identity` and get back the
  document, the revision, and (once sb-qz0 lands it) the provenance map
  that explains it.

  ## `chart_name` carries the document id and `chart_version` stays `nil`

  `Statifier.Machine.Identity.matches?/2` is struct equality across all
  three fields, and st-ADR-0060's resume refuses on
  `{:identity_mismatch, expected, actual}`. So putting the document
  `revision` in `chart_version` would break resume on every save, and
  putting the document hash there would break it on a metadata-only edit -
  precisely the case decision 6 established as a non-event. The document id
  is constant across revisions and is safe; the revision is not, and lives
  in this record instead, where nothing compares it.

  ## `palette_hash` is a hygiene aid, not a commitment

  It digests the sorted `{type_name, module, current_version}` triples of
  the entries the compile actually resolved. It is **not** a cryptographic
  commitment to those modules' behaviour - nothing short of hashing
  compiled beam would be - and this module does not pretend otherwise. It
  exists so the common cause of a surprising recompile, a host adding or
  swapping a palette entry, is visible in the record instead of invisible.
  A host that changes an `emit/2` without bumping `current_version/0` has
  moved a compile input without moving the record; that is a palette-hygiene
  obligation on the host, stated here so it is not discovered later.
  """

  alias Statifier.Machine.Identity
  alias StatifierBlocks.Document

  @type t :: %__MODULE__{
          document_id: Document.id(),
          revision: non_neg_integer(),
          document_hash: binary(),
          palette_hash: binary(),
          compiler_version: String.t(),
          chart_identity: Identity.t()
        }

  @enforce_keys [
    :document_id,
    :revision,
    :document_hash,
    :palette_hash,
    :compiler_version,
    :chart_identity
  ]
  defstruct [
    :document_id,
    :revision,
    :document_hash,
    :palette_hash,
    :compiler_version,
    :chart_identity
  ]
end
