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
  """

  alias StatifierBlocks.{Block, Document}

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
