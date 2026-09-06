defmodule StatifierBlocks.Core.Assign do
  @moduledoc """
  `core.assign`: a leaf step that writes one literal to one datamodel path.

  ADR-0002 decision 10 carries the row, through its 2026-08-29 amendment
  (section G): `slots(config)` is `[]`, the config is `path` and `value`, and
  the type has the single default outcome.

  Two config fields: `path`, the datamodel location to write; `value`, the
  literal to write there.

  ## `value` is SOURCE TEXT

  `value` stores the literal exactly as an author would type it - `false`,
  `42350`, `"manual_review"`, quotes included for a string - which is why
  it lands in the compiled `expr` attribute unchanged. This is not a
  shortcut around ADR-0002 decision 7's closed field-type set; it is the
  same string-of-source-text rule this package already applies wherever a
  literal has to survive verbatim.

  Expressions are deliberately **not** supported in V1. The obvious next
  `value` is one computed from datamodel state, and this module does not
  build it: which expression language, how it would be stored, and whether
  a block document may carry an expression that must be evaluated to
  compile are jointly predicator-ex's and statifier-ex's calls, not this
  package's. Literals only, said out loud here rather than discovered by a
  reader.

  ## The declaration check is not here, and cannot be

  `validate_config/1` is handed a config, not a document, so "is `path`
  declared in the datamodel?" is a question this callback has no document
  to answer against. That check, if a host wants one, is a document-level
  pass over the whole tree - not this type's business.

  It exists now, and this type reaches it by declaration rather than by
  checking anything: `path` is declared `datamodel_path?: true` (ADR-0002
  decision 7, amended 2026-08-29, which names this field as the key's
  first consumer). `StatifierBlocks.Datamodel` is the document-level pass,
  and it produces an `:info` advisory anchored on `path` when a host
  supplies a datamodel that does not declare the value - and nothing at
  all when the host supplies no datamodel. The verdict is unchanged
  either way: an assign to an undeclared location still compiles.

  What an assign to an undeclared location means, and how the write is
  ordered against a state's other `onentry` content, are both statifier-ex's
  and both open.
  """

  @behaviour StatifierBlocks.BlockType

  alias StatifierBlocks.Block
  alias StatifierBlocks.Compiler.Context
  alias StatifierBlocks.Core.{Config, Emit}
  alias StatifierBlocks.Emission

  @impl true
  def current_version, do: 1

  @impl true
  def slots(_config), do: []

  @impl true
  def config_schema(_config),
    do: [
      %{
        key: "path",
        type: :string,
        label: "Write to",
        required?: true,
        default: "",
        datamodel_path?: true
      },
      %{key: "value", type: :string, label: "This literal", required?: true, default: ""}
    ]

  @impl true
  def validate_config(config) do
    []
    |> check_path(config)
    |> check_value(config)
    |> Config.verdict()
  end

  # `Config.datamodel_path?/1`: non-empty and no whitespace, and
  # deliberately NOT a dotted-identifier grammar. The rule is spelled once
  # there because `core.subchart`'s `assign_to` writes the same datamodel
  # through the same `<assign>` element and has to admit the same paths.
  defp check_path(findings, config) do
    path = Map.get(config, "path")

    if Config.datamodel_path?(path) do
      findings
    else
      [{"path", "must be a datamodel path, like review.parked"} | findings]
    end
  end

  # An empty `value` is refused, and the source-text rule is why it can be:
  # the stored form is source text, so writing an empty string is spelled
  # `""` - two characters - and nothing legitimate is spelled with nothing
  # at all.
  defp check_value(findings, config) do
    if Config.non_empty_string?(Map.get(config, "value")) do
      findings
    else
      [
        {"value", ~s(must be a literal, written as source text - false, 42350, "manual_review")}
        | findings
      ]
    end
  end

  @doc """
  `core.raise`'s `io/1` exactly, for `core.raise`'s reason: one outcome, so
  there is no join to refuse and `produces` is absent rather than
  `:unknown`. An assign reads nothing through the type flow either - its
  input is a literal it carries - so there is no `consumes`.
  """
  @impl true
  def io(_config), do: %{kinds: [:step]}

  @impl true
  def palette_entry,
    do: %{
      label: "Assign",
      group: "Structure",
      description: "Writes a literal to a datamodel path.",
      icon: "inbox",
      keywords: ["assign", "set", "write", "datamodel", "variable", "flag"],
      order: 9
    }

  @doc """
  A compound state whose entry writes `expr` to `location` and immediately
  goes final.

      <state id="s_blk_ASN" initial="s_blk_ASN__done">
        <onentry><assign expr="false" location="review.parked"/></onentry>
        <final id="s_blk_ASN__done"/>
      </state>

  `Emission.element/3` normalizes attribute order alphabetically, so the
  written attribute order is `expr` then `location` regardless of the
  order they are passed here.

  Both attributes are annotated: `location` from the `"path"` config
  field, `expr` from the `"value"` field, verbatim - the `<assign>`
  element is this block's own, but each attribute *value* is the author's
  (ADR-0004 decision 9).
  """
  @impl true
  def emit(%Block{config: config}, context) do
    done = Context.done_id(context)

    with {:ok, location} <- path(Map.get(config, "path")),
         {:ok, expr} <- literal(Map.get(config, "value")) do
      assign_element =
        "assign"
        |> Emission.element([{"expr", expr}, {"location", location}])
        |> Emission.attribute_from_config("location", "path")
        |> Emission.attribute_from_config("expr", "value")

      onentry = Emission.element("onentry", [], [assign_element])

      {:ok, Emit.state(context.state_id, done, [onentry, Emit.final(done)])}
    end
  end

  # `emit/2` has to answer for a config `validate_config/1` would reject
  # rather than raising on it - the compiler's Config stage makes that arm
  # unreachable in practice, never impossible (see `core.on_event`).
  defp path(path) do
    if Config.datamodel_path?(path) do
      {:ok, path}
    else
      {:error, [{"path", "must be a datamodel path, like review.parked"}]}
    end
  end

  defp literal(value) do
    if Config.non_empty_string?(value) do
      {:ok, value}
    else
      {:error,
       [{"value", ~s(must be a literal, written as source text - false, 42350, "manual_review")}]}
    end
  end
end
