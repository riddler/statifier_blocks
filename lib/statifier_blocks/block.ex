defmodule StatifierBlocks.Block do
  @moduledoc """
  One node of a block document (ADR-0001).

  A block is `{type, id, config, slots}`, plus the `type_version` axis
  decision 4 adds and an optional author-written `note` - and nothing else
  (decision 2, read with ADR-0001's Amendment of 2026-09-28, `2a`). No
  field is added for layout, selection, collapse state, validation results,
  generated SCXML, or a provenance map: every one of those is a function of
  the document plus a block-type registry, and this layer stores none of
  them.

  The `note` is prose for a person reading the document, never for the
  chart: the compiler and the provenance map never read it, so a note
  changes the document's bytes and `StatifierBlocks.Document.content_hash/1`
  but not the compiled SCXML (`2f`). The empty string is the absent note:
  an absent key decodes to `""`, and `""` is omitted from canonical form
  (`2b`). A note is a field of the block, so it moves with the block, and
  any copy of the struct keeps it (`2e`).
  """

  @typedoc "Any value expressible in canonical JSON. Note: no floats."
  @type json ::
          nil
          | boolean()
          | integer()
          | String.t()
          | [json()]
          | %{optional(String.t()) => json()}

  @typedoc ~S(Document-unique, stable, never reused. `"blk_" <> uxid`.)
  @type id :: String.t()

  @typedoc ~S(Namespaced block-type name, e.g. `"core.branch"`, `"myapp.authorize"`.)
  @type type_name :: String.t()

  @type slot_name :: String.t()

  @typedoc "Owned and interpreted by the block type; opaque to this layer."
  @type config :: %{optional(String.t()) => json()}

  @type t :: %__MODULE__{
          id: id(),
          type: type_name(),
          type_version: pos_integer(),
          config: config(),
          slots: %{optional(slot_name()) => [t()]},
          note: String.t()
        }

  defstruct [:id, :type, type_version: 1, config: %{}, slots: %{}, note: ""]

  @doc """
  Builds a block of the given `type`.

  Options: `:id` (default a freshly minted `StatifierBlocks.Id.block/0`),
  `:type_version` (default `1`), `:config` (default `%{}`), `:slots`
  (default `%{}`), `:note` (default `""`, no note).
  """
  @spec new(type_name(), keyword()) :: t()
  def new(type, opts \\ []) do
    %__MODULE__{
      id: Keyword.get_lazy(opts, :id, &StatifierBlocks.Id.block/0),
      type: type,
      type_version: Keyword.get(opts, :type_version, 1),
      config: Keyword.get(opts, :config, %{}),
      slots: Keyword.get(opts, :slots, %{}),
      note: Keyword.get(opts, :note, "")
    }
  end
end
