defmodule StatifierBlocks.Core.Config do
  @moduledoc false

  # Shared config predicates and finding helpers for the `core.*` types.
  #
  # These are the rules `validate_config/1` is the authority for (ADR-0002
  # decision 7) factored out of the modules that would otherwise spell
  # them once each. Every function is pure and total - decision 4 applies
  # to anything a callback calls, not only to the callback itself.

  alias StatifierBlocks.BlockType

  # A bare lowercase identifier: what a lane name has to be for
  # `"lane_" <> name` to be a usable slot name.
  @identifier ~r/\A[a-z][a-z0-9_]*\z/

  # An arm's stored slot name. ADR-0002 decision 10 calls it a suffix; the
  # ADR-0001 worked example stores the whole slot name (`"arm_approved"`),
  # and the stored bytes win.
  @arm_slot ~r/\Aarm_[a-z][a-z0-9_]*\z/

  # An event name, in the dotted-token style statifier uses. No whitespace,
  # because an event name with a space in it never matches anything.
  @event_name ~r/\A[A-Za-z_][A-Za-z0-9_.\-]*\z/

  # An invoke type: `namespace:name`, both halves bare lowercase
  # identifiers. `core.invoke` and `StatifierBlocks.InvokeStep` read the
  # same grammar out of here so a host meeting the field on a core block
  # and on its own step is meeting one rule.
  @invoke_type ~r/\A[a-z][a-z0-9_]*:[a-z][a-z0-9_]*\z/

  @spec non_empty_string?(term()) :: boolean()
  def non_empty_string?(value) when is_binary(value) and value != "", do: String.valid?(value)
  def non_empty_string?(_value), do: false

  @spec identifier?(term()) :: boolean()
  def identifier?(value), do: non_empty_string?(value) and Regex.match?(@identifier, value)

  @spec invoke_type?(term()) :: boolean()
  def invoke_type?(value), do: non_empty_string?(value) and Regex.match?(@invoke_type, value)

  @spec arm_slot?(term()) :: boolean()
  def arm_slot?(value), do: non_empty_string?(value) and Regex.match?(@arm_slot, value)

  @spec event_name?(term()) :: boolean()
  def event_name?(value), do: non_empty_string?(value) and Regex.match?(@event_name, value)

  @doc """
  Turns an accumulated finding list into `validate_config/1`'s return.
  Findings accumulate head-first, so this reverses them back into the order
  they were checked in - the order the editor renders them in.
  """
  @spec verdict([BlockType.finding()]) :: :ok | {:error, [BlockType.finding()]}
  def verdict([]), do: :ok
  def verdict(findings), do: {:error, Enum.reverse(findings)}

  @doc """
  A `:select` field's value check: present, and one of the declared option
  values.
  """
  @spec one_of(term(), [String.t()]) :: boolean()
  def one_of(value, options), do: is_binary(value) and value in options
end
