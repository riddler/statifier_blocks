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

    # sabotage: drop the `declares_sentence?/1` arm -> the reader's label
    # comes back instead of the author's title -> red
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
