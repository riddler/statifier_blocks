defmodule StatifierBlocks.SubchartByteFixtures do
  @moduledoc """
  Every `core.subchart` document the suite compiles from a shared fixture,
  plus a matrix over every config key the block admitted before
  `chart_from` existed, for the byte pin in
  `StatifierBlocks.Core.SubchartBytesTest`.

  The enumeration, in order:

    * the byte corpus's subchart entry (`StatifierBlocks.ByteCorpus`);
    * the graph fixture `patron_registration-parent.json`, a subchart and
      a map side by side;
    * `StatifierBlocks.RuntimeFixtures.parent_document/1` over the outcome
      lists and occupied slots the runtime tests use;
    * a subchart placed inside a sequence before another step, and one
      nested in another subchart's outcome slot, so the block is pinned
      where it is not the root;
    * the matrix: `outcomes` (absent, empty, one name, two names, a list
      naming `error` itself) by `assign_to` (absent, a name, a dotted path)
      by `params` (absent, one row, two rows) by the slot occupied (none,
      `on_error`, the first declared outcome's).

  Every config here names its child by `chart`, the literal form, so each
  one must keep the bytes and the chart identity it had before the
  data-driven form was added.
  """

  alias StatifierBlocks.{Block, ByteCorpus, Document, Palette, RuntimeFixtures}
  alias StatifierBlocks.Core.Subchart

  @graph_parent Path.join([__DIR__, "..", "fixtures", "graph", "patron_registration-parent.json"])

  @doc "The fixtures, as `{name, document, palette}` triples."
  @spec entries() :: [{String.t(), Document.t(), Palette.t()}]
  def entries do
    core = Palette.new(Palette.core_types())

    corpus =
      ByteCorpus.entries()
      |> Enum.filter(fn {name, _document, _palette} -> name == "subchart_handled" end)
      |> Enum.map(fn {name, document, palette} -> {"corpus_" <> name, document, palette} end)

    corpus ++
      [{"graph_patron_registration_parent", graph_parent(), core}] ++
      runtime_parents(core) ++
      placed(core) ++
      matrix(core)
  end

  @doc "The compile option sets every entry is pinned under."
  @spec modes() :: [{String.t(), keyword()}]
  def modes, do: ByteCorpus.modes()

  @doc "Where the pinned digests live."
  @spec golden_path() :: String.t()
  def golden_path, do: "test/fixtures/subchart_bytes/literal_chart.json"

  defp graph_parent do
    {:ok, document} = @graph_parent |> File.read!() |> Document.from_json()
    document
  end

  defp runtime_parents(palette) do
    for {outcomes, on} <- [
          {[], []},
          {[], ["error"]},
          {["done"], ["done"]},
          {["approved", "declined"], []},
          {["approved", "declined"], ["approved", "error"]}
        ] do
      name =
        "runtime_parent_" <> label(outcomes, "none") <> "_on_" <> label(on, "none")

      {name, RuntimeFixtures.parent_document(chart: "bdoc_CHILD", outcomes: outcomes, on: on),
       palette}
    end
  end

  defp placed(palette) do
    in_sequence =
      Document.new(
        Block.new("core.sequence",
          id: "blk_SEQ",
          slots: %{
            "body" => [
              Block.new("core.subchart",
                id: "blk_SUB",
                config: %{"chart" => "bdoc_CHILD", "outcomes" => "done\nabandoned"}
              ),
              Block.new("core.sequence", id: "blk_AFTER")
            ]
          }
        ),
        id: "bdoc_PLACED"
      )

    nested =
      Document.new(
        Block.new("core.subchart",
          id: "blk_OUTER",
          config: %{"chart" => "bdoc_FIRST", "outcomes" => "done\nretry"},
          slots: %{
            "on_retry" => [
              Block.new("core.subchart",
                id: "blk_INNER",
                config: %{"chart" => "bdoc_SECOND", "assign_to" => "retry.outcome"}
              )
            ]
          }
        ),
        id: "bdoc_NESTED"
      )

    [{"placed_in_sequence", in_sequence, palette}, {"placed_nested", nested, palette}]
  end

  @outcomes [
    {"absent", nil},
    {"empty", ""},
    {"one", "done"},
    {"two", "done\nabandoned"},
    {"with_error", "approved\nerror"}
  ]

  @assign_to [{"absent", nil}, {"name", "eligibility"}, {"path", "signup.step"}]

  @params [
    {"absent", nil},
    {"one", "email=signup.email"},
    {"two", "email=signup.email\nname=signup.name"}
  ]

  @slots ["none", "on_error", "first"]

  defp matrix(palette) do
    for {outcomes_name, outcomes} <- @outcomes,
        {assign_name, assign_to} <- @assign_to,
        {params_name, params} <- @params,
        slot <- @slots do
      config =
        [
          {"chart", "bdoc_CHILD"},
          {"outcomes", outcomes},
          {"assign_to", assign_to},
          {"params", params}
        ]
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)
        |> Map.new()

      name =
        Enum.join(
          [
            "matrix",
            "outcomes",
            outcomes_name,
            "assign",
            assign_name,
            "params",
            params_name,
            slot
          ],
          "_"
        )

      block =
        Block.new("core.subchart", id: "blk_SUB", config: config, slots: slots(slot, config))

      {name, Document.new(block, id: "bdoc_MATRIX"), palette}
    end
  end

  defp slots("none", _config), do: %{}

  defp slots("on_error", _config),
    do: %{"on_error" => [Block.new("core.sequence", id: "blk_ON_ERROR")]}

  defp slots("first", config) do
    [first | _rest] = Subchart.outcome_names(config)
    %{("on_" <> first) => [Block.new("core.sequence", id: "blk_ON_FIRST")]}
  end

  defp label([], empty), do: empty
  defp label(names, _empty), do: Enum.join(names, "_")
end
