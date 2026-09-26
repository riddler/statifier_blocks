defmodule StatifierBlocks.ViewModel.SentenceTest do
  @moduledoc """
  A block as one line of prose: the reader's four declaration states
  (ADR-0002's 2026-09-07 amendment) and the view model's three-way chain
  over it (ADR-0005's amendment of the same date).

  Both are pure functions of a module and a config, so they are asserted
  here with LiveView absent from the dependency tree - the same split the
  card face and the rail partition are asserted under, and the reason the
  markup test beside them only has to check that nothing new is drawn.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, BlockType, Document, Palette, ViewModel}

  doctest StatifierBlocks.BlockType, only: [sentence: 2]

  doctest StatifierBlocks.Core.Wait, only: [sentence: 1]
  doctest StatifierBlocks.Core.Branch, only: [sentence: 1]
  doctest StatifierBlocks.Core.Subchart, only: [sentence: 1]
  doctest StatifierBlocks.Core.Foreach, only: [sentence: 1]
  doctest StatifierBlocks.Core.Parallel, only: [sentence: 1]
  doctest StatifierBlocks.Core.Send, only: [sentence: 1]
  doctest StatifierBlocks.Core.Assign, only: [sentence: 1]
  doctest StatifierBlocks.Core.OnEvent, only: [sentence: 1]
  doctest StatifierBlocks.Core.Sequence, only: [sentence: 1]
  doctest StatifierBlocks.Core.Group, only: [sentence: 1]
  doctest StatifierBlocks.Core.Await, only: [sentence: 1]

  # The core types that declare a `sentence/1` of their own. The generated
  # configs below are run through each, so a type added here is held to the
  # callback's contract without a test of its own.
  @speaking_core [
    StatifierBlocks.Core.Sequence,
    StatifierBlocks.Core.Group,
    StatifierBlocks.Core.Await
  ]

  defmodule Speaking do
    @moduledoc "A host type with words of its own, and a name an author may override."

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1

    @impl true
    def slots(_config), do: []

    @impl true
    def config_schema(_config),
      do: [%{key: "label", type: :string, label: "Name", required?: false, default: ""}]

    @impl true
    def validate_config(_config), do: :ok

    @impl true
    def emit(%Block{id: id}, _context), do: {:ok, {:emitted, id}}

    @impl true
    def palette_entry, do: %{label: "Charge the card"}

    @impl true
    def sentence(config), do: "Charge #{Map.get(config, "amount", "the card")}"
  end

  defmodule Silent do
    @moduledoc "The same type with no `sentence/1` at all: the chain's other two rows."

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1

    @impl true
    def slots(_config), do: []

    @impl true
    def config_schema(_config),
      do: [%{key: "label", type: :string, label: "Name", required?: false, default: ""}]

    @impl true
    def validate_config(_config), do: :ok

    @impl true
    def emit(%Block{id: id}, _context), do: {:ok, {:emitted, id}}

    @impl true
    def palette_entry, do: %{label: "Charge the card"}
  end

  defmodule Raising do
    @moduledoc "A host callback with a bug in it. B3's bounded degradation, three ways."

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1

    @impl true
    def slots(_config), do: []

    @impl true
    def config_schema(_config),
      do: [%{key: "label", type: :string, label: "Name", required?: false, default: ""}]

    @impl true
    def validate_config(_config), do: :ok

    @impl true
    def emit(%Block{id: id}, _context), do: {:ok, {:emitted, id}}

    @impl true
    def palette_entry, do: %{label: "Charge the card"}

    @impl true
    def sentence(%{"how" => "throw"}), do: throw(:nope)
    def sentence(%{"how" => "exit"}), do: exit(:nope)
    def sentence(%{"how" => "blank"}), do: "   "
    def sentence(%{"how" => "multiline"}), do: "one\ntwo"
    def sentence(%{"how" => "not a string"}), do: :nope
    def sentence(_config), do: raise("boom")
  end

  defmodule Nameless do
    @moduledoc "A type with no `palette_entry/0`: the reader has no label to answer."

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1

    @impl true
    def slots(_config), do: []

    @impl true
    def config_schema(_config), do: []

    @impl true
    def validate_config(_config), do: :ok

    @impl true
    def emit(%Block{id: id}, _context), do: {:ok, {:emitted, id}}
  end

  defmodule Using do
    @moduledoc "A type that `use`s the behaviour and overrides nothing: the injected default."

    use StatifierBlocks.BlockType

    @impl true
    def emit(%Block{id: id}, _context), do: {:ok, {:emitted, id}}

    @impl true
    def palette_entry, do: %{label: "Charge the card"}
  end

  defmodule UsingNameless do
    @moduledoc "The injected default with no label to read: a blank string the reader refuses."

    use StatifierBlocks.BlockType

    @impl true
    def emit(%Block{id: id}, _context), do: {:ok, {:emitted, id}}
  end

  describe "BlockType.sentence/2" do
    # sabotage: drop the `line/1` guard from `sentence/2` -> the blank and
    # multiline configs come back as themselves instead of the label -> red
    test "is total: a raise, a throw and an exit all answer the type's label" do
      assert BlockType.sentence(Raising, %{}) == "Charge the card"
      assert BlockType.sentence(Raising, %{"how" => "throw"}) == "Charge the card"
      assert BlockType.sentence(Raising, %{"how" => "exit"}) == "Charge the card"
    end

    # sabotage: widen `line/1` to accept a blank string -> the first
    # assertion comes back "   " -> red
    test "a blank, a multiline and a non-string return all answer the type's label" do
      assert BlockType.sentence(Raising, %{"how" => "blank"}) == "Charge the card"
      assert BlockType.sentence(Raising, %{"how" => "multiline"}) == "Charge the card"
      assert BlockType.sentence(Raising, %{"how" => "not a string"}) == "Charge the card"
    end

    # sabotage: apply `@presentation_cap` to the return -> the long sentence
    # is refused and comes back as the label -> red
    test "carries no cap: a sentence longer than a chip comes back verbatim" do
      long = String.duplicate("a", 200)

      assert BlockType.sentence(Speaking, %{"amount" => long}) == "Charge " <> long
    end

    # sabotage: answer the type name instead of `nil` -> red, and the
    # type-name arm belongs to the view model, which knows the name
    test "a module with no label, and one that is not loadable, answer nil" do
      assert BlockType.sentence(Nameless, %{}) == nil
      assert BlockType.sentence(UsingNameless, %{}) == nil
      assert BlockType.sentence(NoSuchModuleAnywhere, %{}) == nil
    end

    # sabotage: drop the injected `sentence/1` from `__using__` -> the
    # answer is the same label by the not-declared row, so this test pins
    # the injection's SHAPE by asking a config-carrying block instead
    test "the injected default answers the type's own palette label" do
      assert BlockType.sentence(Using, %{"amount" => "ignored"}) == "Charge the card"
    end
  end

  describe "ViewModel.Node.sentence" do
    # sabotage: drop `sentence:` from `build_resolved_node/4` -> nil -> red
    test "is the type's own sentence where it declares a usable one" do
      assert node_sentence(Speaking, %{"amount" => "$40", "label" => "Take the money"}) ==
               "Charge $40"
    end

    # sabotage: take the declared arm unconditionally in
    # `SentenceChain.sentence/5` - drop the `Palette.declares?(ref,
    # :sentence, 1)` test and always answer `BlockType.sentence(ref, config)
    # || label` -> the reader's label comes back instead of the author's
    # title -> red (verified)
    test "is the author's title where the type declares no sentence" do
      assert node_sentence(Silent, %{"label" => "Take the money"}) == "Take the money"
    end

    # sabotage: return `title || label` unconditionally -> "Take the money"
    # comes back for a callback that raised -> red
    test "is the type's label, never the title, when a declared callback degrades" do
      assert node_sentence(Raising, %{"label" => "Take the money"}) == "Charge the card"
    end

    # sabotage: drop the `|| label` tail -> nil for a type with no
    # palette entry and no title -> red
    test "is the type's label, then the type name, when there is neither" do
      assert node_sentence(Silent, %{}) == "Charge the card"
      assert node_sentence(Nameless, %{}, "host.nameless") == "host.nameless"
    end

    # sabotage: resolve an unresolvable node's sentence to nil -> red; a
    # list view would draw a blank line for a block that is in the document
    test "is the type name for a block whose type the palette cannot resolve" do
      document = Document.new(Block.new("host.gone", id: "blk"), id: "doc")
      view_model = ViewModel.build(document, Palette.new(%{}), [])

      assert view_model.root.sentence == "host.gone"
    end

    # sabotage: drop `sentence/1` from `Core.OnEvent` -> the reader falls
    # back to the palette label "On event" -> red. The core type is asserted
    # through the view model as well as in its doctest because the line a
    # handler draws in an `interrupts` slot is what the seam is for.
    test "is core.on_event's own line for a handler in the document" do
      config = %{"event" => "card.authz_timed_out", "outcome" => "abandon"}
      document = Document.new(Block.new("core.on_event", id: "blk", config: config), id: "doc")
      view_model = ViewModel.build(document, Palette.core(), [])

      assert ViewModel.sentence(view_model.root) == "When card.authz_timed_out, abandon"
    end

    # sabotage: answer the palette label ("Group") from `Core.Group`'s
    # `sentence/1` -> the group node's line is the old one -> red
    # (verified). The shape is a loan desk's: a sequence holding a group
    # holding an await with a deadline.
    test "is core.sequence's, core.group's and core.await's own line in a document" do
      await =
        Block.new("core.await",
          id: "awt",
          config: %{"event" => "copy.returned", "timeout" => "14d"}
        )

      group = Block.new("core.group", id: "grp", slots: %{"body" => [await]})
      root = Block.new("core.sequence", id: "seq", slots: %{"body" => [group]})
      view_model = ViewModel.build(Document.new(root, id: "doc"), Palette.core(), [])

      [group_node] = view_model.root.slots |> Enum.flat_map(& &1.children)
      [await_node] = group_node.slots |> Enum.flat_map(& &1.children)

      assert ViewModel.sentence(view_model.root) == "Run its steps in order"
      assert ViewModel.sentence(group_node) == "Run interruptible steps"
      assert ViewModel.sentence(await_node) == "Wait for copy.returned, giving up after 14d"
    end
  end

  describe "the core types' sentence/1 over generated configs" do
    # sabotage: interpolate the stored `timeout` unchecked in
    # `Core.Await.sentence/1` -> a generated "14d\n" or a non-binary
    # reaches the line (a newline, or a raise on interpolation) -> red
    test "is total, never raises and answers one non-blank line for any config" do
      for index <- 0..499, module <- @speaking_core do
        config = generated_config(index)

        line =
          try do
            module.sentence(config)
          rescue
            error ->
              flunk(
                "#{inspect(module)}.sentence/1 raised #{inspect(error)} on config #{index}: " <>
                  inspect(config)
              )
          end

        assert is_binary(line), "config #{index}: #{inspect(config)}"
        assert String.trim(line) != "", "config #{index}: #{inspect(config)}"
        refute line =~ ~r/[\n\r\t]/, "config #{index}: #{inspect(config)}"
        assert BlockType.sentence(module, config) == line
      end
    end
  end

  @config_keys ["event", "timeout", "label", "duration", "outcome", "lanes", ""]
  @config_values [
    "copy.returned",
    "email.verified",
    "guardian.consented",
    "14d",
    "1h30m",
    "30s",
    "14d\n",
    " 14d",
    "1h 30m",
    "copy.returned\n",
    "copy returned",
    "line1\nline2",
    "col1\ttab",
    "",
    "   ",
    <<0xFF, 0xFE>>,
    "café ☃ 日本語",
    nil,
    true,
    0,
    -1,
    14,
    1.5,
    :copy_returned,
    [],
    ["copy.returned"],
    %{},
    %{"event" => "copy.returned"},
    {:tuple, "14d"}
  ]

  # Deterministic from `index` alone, so a failure names the one config
  # that produced it and is regenerable from that integer.
  defp generated_config(index) do
    :rand.seed(:exsss, {index, index * 3 + 1, index * 7 + 2})

    for _ <- 1..:rand.uniform(4), into: %{} do
      {Enum.random(@config_keys), Enum.random(@config_values)}
    end
  end

  defp node_sentence(module, config) do
    document = Document.new(Block.new("host.step", id: "blk", config: config), id: "doc")
    palette = Palette.new(%{"host.step" => module})

    ViewModel.build(document, palette, []).root.sentence
  end

  defp node_sentence(module, config, type) when is_binary(type) do
    document = Document.new(Block.new(type, id: "blk", config: config), id: "doc")
    palette = Palette.new(%{type => module})

    ViewModel.build(document, palette, []).root.sentence
  end
end
