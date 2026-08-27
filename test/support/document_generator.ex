defmodule StatifierBlocks.DocumentGenerator do
  @moduledoc """
  Deterministic generator for valid `StatifierBlocks.Document.t()` values,
  used to build `decode_test.exs`'s round-trip corpus.

  `generate/2` seeds `:rand` explicitly from `{base_seed, index}` before
  drawing anything, so document `index` is reproducible on its own - a
  failing property test can print `index` and the corpus is regenerable
  from that one integer, with no dependence on iteration order or the
  clock.

  Block and document ids are minted with `StatifierBlocks.Id`, which uses
  `:crypto.strong_rand_bytes/1` rather than `:rand` - the tree shape and
  content are deterministic from the seed, but ids are always fresh, which
  is fine: decision 3 treats ids as opaque and never requires them to be
  reproducible, only unique within a document.

  This module now serves two consumers: `decode_test.exs`'s round-trip
  corpus (`generate/2`) and `edit_property_test.exs`'s generated command
  sequences (`commands/3`). `commands/3` folds `StatifierBlocks.Edit.apply/2`
  over the document it builds so each generated command is drawn against the
  tree as it stands after the previous one - applicable rather than
  mostly-refused - while still fabricating a deliberate minority of commands
  that `apply/2` must refuse, so the property that consumes this generator
  covers the error paths too.
  """

  alias StatifierBlocks.{Block, Document, Edit}

  @max_depth 4
  @escape_strings [
    ~s(say "hi"),
    ~s(a\\b),
    "line1\nline2",
    "col1\ttab",
    <<1>>,
    "café ☃ 日本語",
    "",
    "plain"
  ]
  @large_integers [
    -9_223_372_036_854_775_808,
    9_223_372_036_854_775_807,
    -1,
    0,
    1,
    123_456_789_012_345
  ]
  @type_names ~w(core.sequence core.branch core.parallel core.wait
                 core.resumable_group myapp.enrich myapp.crm_push
                 myapp.notify myapp.on_event nobody.knows.this)

  @doc "Generates document `index`, deterministically from `base_seed`."
  @spec generate(non_neg_integer(), non_neg_integer()) :: Document.t()
  def generate(base_seed, index) do
    :rand.seed(:exsss, {base_seed, index, index * 7 + 1})

    root = gen_block(@max_depth)

    Document.new(root,
      revision: Enum.random(0..100),
      metadata: gen_json_object(1)
    )
  end

  # A small, closed vocabulary for command generation. It does not need to
  # match `@type_names` above (`Edit.apply/2` is a structural rewrite, never
  # palette-aware) but stays legible rather than exercising the corpus's
  # deliberately weird strings.
  @command_type_names ~w(core.wait core.sequence core.branch core.parallel)

  @doc """
  Generates a sequence of `count` commands against the document `generate/2`
  builds from the same `{base_seed, index}` pair, returning `{document,
  commands}`. Reseeds `:rand` again afterward so the sequence is reproducible
  from the same one integer `index`, independent of how many draws building
  the document itself consumed.

  Each command is drawn against the document as it stands after the previous
  command in the sequence - folded internally via `StatifierBlocks.Edit.apply/2`,
  discarding a refusal's non-effect and keeping a success's result - so a
  real parent and one of its slot keys (or, roughly a third of the time, a
  fresh slot name, exercising rule 2), a real index in range, and a real
  block id for `:remove`, `:move` and `:update_config` are the common case.
  A deliberate minority of commands are built to be refused instead - a
  malformed slot name, a duplicate id, an out-of-range index, a move onto
  the dragged block itself, a removal of the root - so a property folding
  over this sequence covers `apply/2`'s error arms too, not only its happy
  path.
  """
  @spec commands(non_neg_integer(), non_neg_integer(), pos_integer()) ::
          {Document.t(), [Edit.t()]}
  def commands(base_seed, index, count) do
    document = generate(base_seed, index)
    :rand.seed(:exsss, {base_seed, index * 13 + 5, index})

    {reversed_commands, _final_document} =
      Enum.reduce(1..count, {[], document}, fn _step, {acc, current} ->
        command = gen_command(current)

        next =
          case Edit.apply(current, command) do
            {:ok, updated, _inverse} -> updated
            {:error, _reason} -> current
          end

        {[command | acc], next}
      end)

    {document, Enum.reverse(reversed_commands)}
  end

  @spec gen_command(Document.t()) :: Edit.t()
  defp gen_command(document) do
    blocks = Document.blocks(document)

    case Enum.random(1..4) do
      1 -> gen_insert(document, blocks)
      2 -> gen_remove(document, blocks)
      3 -> gen_move(document, blocks)
      4 -> gen_update_config(blocks)
    end
  end

  @spec gen_target(Document.t()) :: Edit.target()
  defp gen_target(document) do
    parent = document |> Document.blocks() |> Enum.random()
    slot_name = gen_slot_name(parent)
    children = Map.get(parent.slots, slot_name, [])
    {parent.id, slot_name, Enum.random(0..length(children))}
  end

  # Reuses one of the parent's own slot keys two thirds of the time; the
  # rest of the time (and always when the parent carries none yet) mints a
  # fresh slot name, exercising rule 2 - an absent slot key is created by an
  # insert or a move into it.
  @spec gen_slot_name(Block.t()) :: Block.slot_name()
  defp gen_slot_name(%Block{slots: slots}) do
    case {Map.keys(slots), Enum.random(1..3)} do
      {[], _roll} -> gen_word()
      {keys, roll} when roll <= 2 -> Enum.random(keys)
      {_keys, _roll} -> gen_word()
    end
  end

  @spec gen_insert(Document.t(), [Block.t()]) :: Edit.t()
  defp gen_insert(document, blocks) do
    case Enum.random(1..5) do
      1 ->
        # Refusable: a malformed (empty) slot name -> {:no_such_slot, ...}.
        parent = Enum.random(blocks)
        {:insert, {parent.id, "", 0}, gen_new_block()}

      2 ->
        # Refusable: an id already present in the document -> {:duplicate_block_id, ...}.
        dup = Enum.random(blocks)
        parent = Enum.random(blocks)
        {:insert, {parent.id, gen_word(), 0}, gen_new_block(id: dup.id)}

      3 ->
        # Refusable: an index past the slot's length -> {:index_out_of_range, ...}.
        {parent_id, slot_name, index} = gen_target(document)
        {:insert, {parent_id, slot_name, index + Enum.random(1..10)}, gen_new_block()}

      _ ->
        {:insert, gen_target(document), gen_new_block()}
    end
  end

  @spec gen_new_block(keyword()) :: Block.t()
  defp gen_new_block(opts \\ []) do
    defaults = [type_version: Enum.random(1..3), config: gen_json_object(1)]
    Block.new(Enum.random(@command_type_names), Keyword.merge(defaults, opts))
  end

  @spec gen_remove(Document.t(), [Block.t()]) :: Edit.t()
  defp gen_remove(document, blocks) do
    removable = Enum.reject(blocks, &(&1.id == document.root.id))

    case Enum.random(1..5) do
      1 ->
        # Refusable: a block id not in the document -> {:no_such_block, ...}.
        {:remove, "blk_ghost_" <> gen_word()}

      2 ->
        # Refusable: the document root -> {:cannot_remove_root, ...}.
        {:remove, document.root.id}

      _ when removable == [] ->
        {:remove, document.root.id}

      _ ->
        {:remove, Enum.random(removable).id}
    end
  end

  @spec gen_move(Document.t(), [Block.t()]) :: Edit.t()
  defp gen_move(document, blocks) do
    moved = Enum.random(blocks)

    cond do
      moved.id == document.root.id and Enum.random(1..3) == 1 ->
        # Refusable: moving the root -> {:cannot_remove_root, ...}.
        {:move, moved.id, {document.root.id, gen_word(), 0}}

      Enum.random(1..5) == 1 ->
        # Refusable: dropping a block onto itself -> {:would_cycle, ...}.
        {:move, moved.id, {moved.id, gen_word(), 0}}

      true ->
        {:move, moved.id, gen_move_target(document, blocks, moved)}
    end
  end

  # Half the time, when `moved` isn't the root, targets the slot `moved`
  # already occupies - a same-slot move - with a valid index computed
  # against the slot as it will stand once `moved` is detached from it
  # (`length(children) - 1`, per rule 4). The rest of the time targets a
  # freshly drawn slot anywhere in the document - a cross-slot move.
  @spec gen_move_target(Document.t(), [Block.t()], Block.t()) :: Edit.target()
  defp gen_move_target(document, blocks, moved) do
    case {Document.fetch_path(document, moved.id), Enum.random(1..2)} do
      {{:ok, path}, 1} when path != [] ->
        {parent_id, slot_name, _index} = List.last(path)
        parent = Enum.find(blocks, &(&1.id == parent_id))
        children = Map.get(parent.slots, slot_name, [])
        {parent_id, slot_name, Enum.random(0..(length(children) - 1))}

      _ ->
        gen_target(document)
    end
  end

  @spec gen_update_config([Block.t()]) :: Edit.t()
  defp gen_update_config(blocks) do
    case Enum.random(1..5) do
      1 ->
        # Refusable: a block id not in the document -> {:no_such_block, ...}.
        {:update_config, "blk_ghost_" <> gen_word(), gen_json_object(1)}

      _ ->
        {:update_config, Enum.random(blocks).id, gen_json_object(1)}
    end
  end

  @spec gen_block(non_neg_integer()) :: Block.t()
  defp gen_block(depth) do
    Block.new(Enum.random(@type_names),
      type_version: Enum.random(1..5),
      config: gen_json_object(1),
      slots: gen_slots(depth)
    )
  end

  @spec gen_slots(non_neg_integer()) :: %{optional(String.t()) => [Block.t()]}
  defp gen_slots(depth) when depth <= 0, do: %{}

  defp gen_slots(depth) do
    slot_count = Enum.random(0..3)

    for i <- 1..slot_count//1, into: %{} do
      {"slot_#{i}_#{gen_word()}", gen_children(depth)}
    end
  end

  # A slot that is present in the map always carries at least one child.
  # `to_json/1` omits an empty slot list entirely (ADR-0001 decision 8), so
  # a present-but-empty slot here would make `decode(encode(d)) == d` fail
  # structurally even though the encoded bytes would still round-trip.
  @spec gen_children(non_neg_integer()) :: [Block.t()]
  defp gen_children(depth) do
    for _ <- 1..Enum.random(1..3), do: gen_block(depth - 1)
  end

  @spec gen_json_object(non_neg_integer()) :: %{optional(String.t()) => Block.json()}
  defp gen_json_object(depth) do
    key_count = Enum.random(0..3)

    for _ <- 1..key_count//1, into: %{} do
      {gen_word(), gen_json_value(depth)}
    end
  end

  @spec gen_json_value(non_neg_integer()) :: Block.json()
  defp gen_json_value(depth) when depth <= 0, do: gen_scalar()

  defp gen_json_value(depth) do
    case Enum.random([:scalar, :scalar, :scalar, :list, :object]) do
      :scalar -> gen_scalar()
      :list -> for _ <- 1..Enum.random(0..3)//1, do: gen_json_value(depth - 1)
      :object -> gen_json_object(depth - 1)
    end
  end

  @spec gen_scalar() :: Block.json()
  defp gen_scalar do
    case Enum.random([:nil_or_bool, :integer, :string]) do
      :nil_or_bool -> Enum.random([nil, true, false])
      :integer -> gen_integer()
      :string -> gen_string()
    end
  end

  @spec gen_integer() :: integer()
  defp gen_integer do
    Enum.random(@large_integers ++ [Enum.random(-1_000..1_000)])
  end

  @spec gen_string() :: String.t()
  defp gen_string do
    Enum.random(@escape_strings ++ [gen_word()])
  end

  @spec gen_word() :: String.t()
  defp gen_word do
    1..Enum.random(3..8)
    |> Enum.map(fn _ -> Enum.random(~c"abcdefghijklmnopqrstuvwxyz") end)
    |> List.to_string()
  end
end
