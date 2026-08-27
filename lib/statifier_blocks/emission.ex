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

  ## Provenance hints (ADR-0004 decision 5)

  Two of the three fields below carry no bytes at all. They are hints the
  compiler reads while building the provenance map, and the serializer
  never writes them:

    * `owner` - an **attribution judgment**. By default every element a
      block emits belongs to that block, which is right almost everywhere.
      ADR-0004 decision 5 names the exceptions: the `done.state` transition
      a sequence emits belongs to *the child it leaves*, because "what
      happens after the enrich step" is the fact an author would recognise.
      `attributed_to/2` records that. `from_config/2` records the other
      half - an element written out of one config field, so a finding
      against it is the author's rather than a bug.
    * `attribute_owners` - the same, one attribute value at a time. A
      `cond` built verbatim from an author's `:expression` field is the
      motivating case: the *element* is the block type's, the *attribute
      value* is the author's, and only the second should carry a config
      key. `attribute_from_config/3` records it.

  A hint is never required. A block type that sets none gets the default
  attribution, which is what every leaf wants.
  """

  alias StatifierBlocks.Block

  @typedoc "A child of an element: another element, or a placeholder for a compiled child block."
  @type node_t :: t() | {:child, Block.id()}

  @typedoc """
  An attribution hint, and - once
  `StatifierBlocks.Compiler.Attribution.stamp/3` has run over the tree -
  the resolved `t:StatifierBlocks.Provenance.owner/0` itself, which is
  this type with `block_id` known.

  `block_id` is `nil` for "the block that emitted this", which is the
  default and the common case. `role` is never set by a block type: the
  compiler derives it from the state ids the block minted, because a block
  type naming its own role twice - once in an id and once in a hint - is a
  place for the two to disagree.
  """
  @type hint :: %{
          block_id: Block.id() | nil,
          role: String.t() | nil,
          config_key: String.t() | nil
        }

  @type t :: %__MODULE__{
          name: String.t(),
          attributes: [{String.t(), String.t()}],
          children: [node_t()],
          owner: hint() | nil,
          attribute_owners: [{String.t(), String.t()}]
        }

  @enforce_keys [:name]
  defstruct name: nil, attributes: [], children: [], owner: nil, attribute_owners: []

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

  @doc """
  Attributes `emission` and everything under it to `block_id` rather than
  to the block that emitted it (ADR-0004 decision 5).

  Reserved for the cases the record names, where the block an author would
  recognise is not the block whose `emit/2` wrote the element. Attributing
  an element to a block that is not in this document at all is a bug in the
  block type, and the compiler reports it as an Emit finding rather than
  writing an owner nothing can resolve.
  """
  @spec attributed_to(t(), Block.id()) :: t()
  def attributed_to(%__MODULE__{} = emission, block_id) when is_binary(block_id) do
    %{emission | owner: hint(block_id, config_key(emission))}
  end

  @doc """
  Records that `emission` was written out of the config field `config_key`,
  so a finding landing inside it is the author's rather than a bug.
  """
  @spec from_config(t(), String.t()) :: t()
  def from_config(%__MODULE__{owner: owner} = emission, config_key) when is_binary(config_key) do
    block_id = if is_map(owner), do: owner.block_id, else: nil
    %{emission | owner: hint(block_id, config_key)}
  end

  @doc """
  Records that one attribute's **value** came verbatim from the config
  field `config_key`, leaving the element itself attributed as it was.

  This is the finer of the two grains, and the one the fault split
  (ADR-0004 decision 9) actually turns on: an upstream finding whose
  location falls inside the value is the author's typo, while one against
  the element around it is not. A `config_key` for an attribute the
  element does not carry is dropped, so an optional attribute can be
  annotated unconditionally.
  """
  @spec attribute_from_config(t(), String.t(), String.t()) :: t()
  def attribute_from_config(%__MODULE__{} = emission, attribute, config_key)
      when is_binary(attribute) and is_binary(config_key) do
    if List.keymember?(emission.attributes, attribute, 0) do
      owners = List.keystore(emission.attribute_owners, attribute, 0, {attribute, config_key})
      %{emission | attribute_owners: Enum.sort_by(owners, &elem(&1, 0))}
    else
      emission
    end
  end

  # A hint always carries all three keys, so the resolved owner the
  # compiler stamps in its place is the same shape with `block_id` known.
  # One shape means one type, and no field that is a map of two keys here
  # and three keys one pass later.
  @spec hint(Block.id() | nil, String.t() | nil) :: hint()
  defp hint(block_id, config_key) do
    %{block_id: block_id, role: nil, config_key: config_key}
  end

  @spec config_key(t()) :: String.t() | nil
  defp config_key(%__MODULE__{owner: %{config_key: key}}), do: key
  defp config_key(%__MODULE__{}), do: nil

  @spec normalize([{String.t(), String.t() | nil}]) :: [{String.t(), String.t()}]
  defp normalize(attributes) do
    attributes
    |> Enum.reject(fn {_name, value} -> is_nil(value) end)
    |> Enum.sort_by(fn {name, _value} -> name end)
  end
end
