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

  ## Recognising the pair again at delete time

  `members/2` (ADR-0005's 2026-09-07 amendment, clause `2D`) is `insert/2`
  read backwards. It is handed a block id and the document and answers the
  ids of the pair that block is half of, so the editor can take the
  arrangement out in the one gesture it went in as.

  It recognises the **shape**, not the origin. Nothing in the document says
  a send is a deadline's send (clause `11u`), so the recipe looks for what
  `insert/2` writes: a `core.send` carrying an `event` and a `delay` in a
  group's `body`, and a `core.on_event` on **that same group's**
  `interrupts` rail whose `event` is the same string. Three consequences
  follow, and each is the amendment's:

    * a **hand-built** pair is claimed - an author who put both halves down
      themselves built the arrangement, and the recipe cannot tell the
      difference;
    * a **renamed** event still matches, because the test is that the two
      halves AGREE, not that either matches `event_name/1`'s generated form.
      The config form writes one half at a time, so a pair renamed apart is
      no longer a pair and is not claimed;
    * nothing outside the enclosing group is ever named. The rail is read
      off the group the asked-about block sits in and off no other block,
      which is clause `3C`'s bound arriving by construction the way
      `insert/2`'s does.

  The answer includes the asked-about id, and is `[]` for everything else -
  a block of another type, a half whose partner is absent, and a half whose
  partner disagrees. The last of those is the amendment's conservative
  reading of a partial arrangement, which it records as the behaviour in the
  absence of a decision rather than as the decision.
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
      order: 17
    }

  @doc """
  Both ids of the deadline pair `block_id` is half of, or `[]`.

  The send first and the handler second, whichever half was asked about, so
  one arrangement answers one list however the author reached it.
  """
  @impl true
  def members(block_id, %Document{} = document) do
    with {:ok, [{parent_id, slot, _index} | _up]} <- reversed_path(document, block_id),
         {:ok, group} <- enclosing_group(document, parent_id),
         %Block{} = block <- block_by_id(document, block_id) do
      pair(group, slot, block)
    else
      _not_an_arrangement -> []
    end
  end

  # The path runs root-first, so the LAST step is the one that names the
  # block's own parent and slot. The root itself has taken no steps and is
  # half of nothing.
  @spec reversed_path(Document.t(), Block.id()) :: {:ok, Document.path()} | :error
  defp reversed_path(document, block_id) do
    with {:ok, path} <- Document.fetch_path(document, block_id) do
      {:ok, Enum.reverse(path)}
    end
  end

  @spec block_by_id(Document.t(), Block.id()) :: Block.t() | nil
  defp block_by_id(document, block_id) do
    document |> Document.blocks() |> Enum.find(&(&1.id == block_id))
  end

  # Asked about the timer, look down the rail; asked about the handler, look
  # into the body. Both clauses require the send's `delay`, because a send
  # without one is not the arrangement `insert/2` writes.
  @spec pair(Block.t(), Block.slot_name(), Block.t()) :: [Block.id()]
  defp pair(group, @body, %Block{type: "core.send", id: id, config: config}) do
    with event when is_binary(event) and event != "" <- Map.get(config, "event"),
         delay when is_binary(delay) and delay != "" <- Map.get(config, "delay"),
         %Block{id: handler_id} <- partner(group, @interrupts, "core.on_event", event) do
      [id, handler_id]
    else
      _no_partner -> []
    end
  end

  defp pair(group, @interrupts, %Block{type: "core.on_event", id: id, config: config}) do
    with event when is_binary(event) and event != "" <- Map.get(config, "event"),
         %Block{id: timer_id, config: timer_config} <-
           partner(group, @body, "core.send", event),
         delay when is_binary(delay) and delay != "" <- Map.get(timer_config, "delay") do
      [timer_id, id]
    else
      _no_partner -> []
    end
  end

  defp pair(_group, _slot, _block), do: []

  @spec partner(Block.t(), Block.slot_name(), String.t(), String.t()) :: Block.t() | nil
  defp partner(%Block{slots: slots}, slot, type, event) do
    slots
    |> Map.get(slot, [])
    |> Enum.find(fn %Block{type: block_type, config: config} ->
      block_type == type and Map.get(config, "event") == event
    end)
  end

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
