defmodule StatifierBlocks.Core.Config do
  @moduledoc false

  # Shared config predicates and finding helpers for the `core.*` types.
  #
  # These are the rules `validate_config/1` is the authority for (ADR-0002
  # decision 7) factored out of seven modules that would otherwise spell
  # them seven times. Every function is pure and total - decision 4 applies
  # to anything a callback calls, not only to the callback itself.

  alias StatifierBlocks.BlockType

  # A bare lowercase identifier: what a lane name has to be for
  # `"lane_" <> name` to be a usable slot name.
  @identifier ~r/\A[a-z][a-z0-9_]*\z/

  # An arm's stored slot name. ADR-0002 decision 10 calls it a suffix; the
  # ADR-0001 worked example stores the whole slot name (`"arm_qualified"`),
  # and the stored bytes win.
  @arm_slot ~r/\Aarm_[a-z][a-z0-9_]*\z/

  # An event name, in the dotted-token style statifier uses. No whitespace,
  # because an event name with a space in it never matches anything.
  @event_name ~r/\A[A-Za-z_][A-Za-z0-9_.\-]*\z/

  # ISO-8601 duration, integer components only - ADR-0001 decision 6 forbids
  # floats in `config`, so `PT1.5S` is not expressible here either. `P` on
  # its own, and a `T` with nothing after it, are both rejected.
  @duration ~r/\AP(?!\z)(\d+Y)?(\d+M)?(\d+W)?(\d+D)?(T(?!\z)(\d+H)?(\d+M)?(\d+S)?)?\z/

  @spec non_empty_string?(term()) :: boolean()
  def non_empty_string?(value) when is_binary(value) and value != "", do: String.valid?(value)
  def non_empty_string?(_value), do: false

  @spec identifier?(term()) :: boolean()
  def identifier?(value), do: non_empty_string?(value) and Regex.match?(@identifier, value)

  @spec arm_slot?(term()) :: boolean()
  def arm_slot?(value), do: non_empty_string?(value) and Regex.match?(@arm_slot, value)

  @spec event_name?(term()) :: boolean()
  def event_name?(value), do: non_empty_string?(value) and Regex.match?(@event_name, value)

  @spec duration?(term()) :: boolean()
  def duration?(value), do: non_empty_string?(value) and Regex.match?(@duration, value)

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
