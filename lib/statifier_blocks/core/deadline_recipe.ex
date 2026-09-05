defmodule StatifierBlocks.Core.DeadlineRecipe do
  @moduledoc """
  The core `"deadline"` recipe: one palette pick puts down the `core.send`
  and `core.on_event` pair that ADR-0010 decision 1 spells (ADR-0005
  clause 4C).

  A clock interrupt on a group is two blocks, and which two and where is
  knowledge an author otherwise has to hold in their head:

    * a `core.send` carrying the deadline event and a `delay`, at **index 0
      of the enclosing group's `body`** - first, so the deadline starts when
      the group starts; and
    * a `core.on_event` naming **the same event**, on that same group's
      `interrupts` rail.

  Both halves are ordinary blocks of ordinary core types. The recipe is the
  knowledge of how they go together and nothing more: it adds no vocabulary,
  no row to ADR-0002 decision 10's table, and nothing a document holds that
  it could not have held before.

  The event name is generated rather than asked for, and it is written twice
  by the recipe rather than twice by the author - which is the coupling
  ADR-0010 decision 5 records as the family rule, and the half of it that
  was most easily got wrong by hand. It is derived from the send block's own
  minted id, so two deadlines in one group never name the same event.

  ## What it refuses, and why that is a refusal rather than a finding

  The pair only means anything on a block with an `interrupts` rail, which
  in the core vocabulary is `core.group` and `core.resumable_group` and
  nothing else - `core.sequence`'s moduledoc says so in terms. Armed
  anywhere else, `insert/2` answers `{:error, {:no_interrupts_slot, id}}`
  and nothing is written, so there is no document for the view model to say
  anything about. A refused gesture is not a finding (clause 3C).

  `insert/2` is handed the armed position and the document and nothing else
  (clause 2C), so the enclosing block's **declared** slots are out of its
  reach - a palette is not one of its arguments. It reads the two core type
  names instead. That is core knowledge about core types inside a core
  recipe, not the editor learning what a block is called: a host whose own
  group type carries an `interrupts` rail registers its own recipe under
  this name, which is exactly what clause 1C's collision rule is for.
  """

  @behaviour StatifierBlocks.Recipe

  alias StatifierBlocks.{Block, Document}
  alias StatifierBlocks.Core.{OnEvent, Send}

  @groups ["core.group", "core.resumable_group"]

  @body "body"
  @interrupts "interrupts"

  @doc """
  The default deadline. `core.wait`'s own default, for `core.wait`'s reason:
  a duration the author will almost always change, but a real one, so the
  pair the pick produces compiles before it is touched.
  """
  @spec default_delay() :: String.t()
  def default_delay, do: "1h"

  @doc """
  The pair, as two `:insert` commands, or a refusal.

  The armed position names its parent, and that parent is the enclosing
  group both halves land in - the send at the head of `body`, the handler at
  the end of `interrupts`. Clause 3C's bound is therefore met by
  construction: neither command names a block above the group the author is
  already inside.
  """
  @impl true
  def insert({parent_id, _slot, _index}, %Document{} = document) do
    with {:ok, group} <- enclosing_group(document, parent_id) do
      armed = Block.new("core.send", type_version: Send.current_version())
      event = event_name(armed)
      timer = %{armed | config: config(Send, %{"event" => event, "delay" => default_delay()})}

      {:ok,
       [
         {:insert, {group.id, @body, 0}, timer},
         {:insert, {group.id, @interrupts, rail_length(group)}, handler_block(event)}
       ]}
    end
  end

  @impl true
  def palette_entry,
    do: %{
      label: "Deadline",
      group: "Structure",
      description: "Puts a timer on this group, and a rule for when it runs out.",
      icon: "clock",
      keywords: ["deadline", "timeout", "timer", "expire", "interrupt", "sla"],
      order: 7
    }

  @spec enclosing_group(Document.t(), Block.id()) ::
          {:ok, Block.t()} | {:error, {:no_interrupts_slot, Block.id()}}
  defp enclosing_group(document, parent_id) do
    document
    |> Document.blocks()
    |> Enum.find(&(&1.id == parent_id))
    |> case do
      %Block{type: type} = block when type in @groups -> {:ok, block}
      _no_rail_here -> {:error, {:no_interrupts_slot, parent_id}}
    end
  end

  @spec rail_length(Block.t()) :: non_neg_integer()
  defp rail_length(%Block{slots: slots}), do: length(Map.get(slots, @interrupts, []))

  @spec handler_block(String.t()) :: Block.t()
  defp handler_block(event) do
    Block.new("core.on_event",
      type_version: OnEvent.current_version(),
      config: config(OnEvent, %{"event" => event})
    )
  end

  # The type's own schema defaults, with the keys this recipe decides
  # written over them - the same shape `StatifierBlocks.Editor` mints a
  # palette pick's config in, so a block a recipe puts down and a block a
  # pick puts down differ only in the keys the recipe filled in.
  @spec config(module(), Block.config()) :: Block.config()
  defp config(module, overrides) do
    %{}
    |> module.config_schema()
    |> Map.new(fn %{key: key, default: default} -> {key, default} end)
    |> Map.merge(overrides)
  end

  # The event name both halves carry. `Config.event_name?/1` admits letters,
  # digits, `_`, `-` and `.`, and a minted block id's characters are all of
  # the first three, so the derived name is well formed without being
  # sanitized.
  #
  # The TAIL of the id rather than the whole of it, and the length is not
  # arbitrary. `StatifierBlocks.BlockType`'s presentation cap refuses a
  # summary chip longer than 24 characters rather than truncating it, so a
  # name built from a whole id would leave BOTH halves of a fresh pair
  # drawing a card with no event on it and a lint finding beside it - the
  # arrangement working and looking broken. `"deadline."` plus eight
  # characters is seventeen, and those eight come from the id's random tail
  # (ADR-0008's entropy half), so two deadlines in one document do not
  # collide in practice.
  @spec event_name(Block.t()) :: String.t()
  defp event_name(%Block{id: id}), do: "deadline." <> String.slice(id, -8, 8)
end
