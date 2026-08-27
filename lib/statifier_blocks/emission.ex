defmodule StatifierBlocks.Emission do
  @moduledoc """
  One SCXML subtree, structurally (ADR-0004 decision 4).

  `emit/2` returns one of these, never a string. A block type building XML
  text would own escaping, namespace handling and attribute-value
  normalization, all easy to get subtly wrong, none of them a block-type
  author's business, and all of them - per st-ADR-0052's whitespace
  sensitivity - able to change chart identity by accident. The compiler
  serializes the whole tree once, at the end, through
  `StatifierBlocks.Compiler.Serializer`.

  ## Attributes are a sorted list, not a map

  `attributes` is a list of `{name, value}` pairs kept in sorted order by
  `element/3`, because ADR-0004 decision 6 forbids iterating a bare map
  anywhere in the pipeline: two maps that are `==` can enumerate in
  different orders, and the serializer's output is identity-bearing.
  Sorting at construction rather than at serialization means the sort
  happens once, where the pairs are known.

  ## Children, and the child placeholder

  A parent never receives its children's emitted SCXML (decision 4: a
  parent that could read it would be a parent that could depend on it).
  What it receives is a summary - block id, state id, done event - and what
  it emits in a child's place is `child_ref/1`, a placeholder naming that
  child's block id. The compiler splices each child's own emission in
  afterwards.

  That is what buys decision 6's per-block byte stability: a parent's own
  bytes are a function of its config and its children's *ids*, never of
  their contents, so an unedited subtree compiles to unchanged bytes even
  when a sibling changes.
  """

  alias StatifierBlocks.Block

  @typedoc "A child of an element: another element, or a placeholder for a compiled child block."
  @type node_t :: t() | {:child, Block.id()}

  @type t :: %__MODULE__{
          name: String.t(),
          attributes: [{String.t(), String.t()}],
          children: [node_t()]
        }

  @enforce_keys [:name]
  defstruct name: nil, attributes: [], children: []

  @doc """
  Builds an element.

  `attributes` is a list of `{name, value}` pairs; it is sorted by name
  here, and an attribute whose value is `nil` is dropped, so a caller can
  write an optional attribute without a conditional around it.
  """
  @spec element(String.t(), [{String.t(), String.t() | nil}], [node_t()]) :: t()
  def element(name, attributes \\ [], children \\ [])
      when is_binary(name) and is_list(attributes) and is_list(children) do
    %__MODULE__{name: name, attributes: normalize(attributes), children: children}
  end

  @doc """
  A placeholder for the compiled emission of the child block `block_id`.

  The compiler replaces it with that child's own subtree; a placeholder
  naming a block the compiler did not compile in this slot is a compiler
  bug, not a document error, and `StatifierBlocks.Compiler` reports it as
  one rather than emitting a hole.
  """
  @spec child_ref(Block.id()) :: {:child, Block.id()}
  def child_ref(block_id) when is_binary(block_id), do: {:child, block_id}

  @spec normalize([{String.t(), String.t() | nil}]) :: [{String.t(), String.t()}]
  defp normalize(attributes) do
    attributes
    |> Enum.reject(fn {_name, value} -> is_nil(value) end)
    |> Enum.sort_by(fn {name, _value} -> name end)
  end
end
