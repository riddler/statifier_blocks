defmodule StatifierBlocks.ViewModel.CardFaceTest do
  @moduledoc """
  What a card says about itself (parity item 1.4): the author's own name for a
  block, the type's label underneath it, and the invoke type on the third line.

  All three are derived from a declared field or a config key, never from a
  type name, so they are asserted here with LiveView absent from the dependency
  tree - the same split the accent and the rail partition are asserted under,
  and the reason the markup tests beside them only have to check placement.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Document, Palette, ViewModel}

  doctest StatifierBlocks.ViewModel, only: [title: 1, subtitle: 1]

  defmodule NamedStep do
    @moduledoc """
    A host type whose instances are worth naming: it declares a `:string`
    field keyed `label`, which is the whole seam the title override reads.
    """

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
    def palette_entry, do: %{label: "Intake"}
  end

  defmodule NamedElsewhere do
    @moduledoc """
    The same declaration with a `value_path`: the name lives under
    `presentation.label`, which is what separates "reads the declared field"
    from "reads `config["label"]`".
    """

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1

    @impl true
    def slots(_config), do: []

    @impl true
    def config_schema(_config),
      do: [
        %{
          key: "label",
          type: :string,
          label: "Name",
          required?: false,
          default: "",
          value_path: ["presentation", "label"]
        }
      ]

    @impl true
    def validate_config(_config), do: :ok

    @impl true
    def emit(%Block{id: id}, _context), do: {:ok, {:emitted, id}}

    @impl true
    def palette_entry, do: %{label: "Intake"}
  end

  defmodule NumericLabel do
    @moduledoc """
    A type that declares `label` as something other than a `:string` - the
    case that separates "a declared string field keyed label" from "any field
    keyed label at all".
    """

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1

    @impl true
    def slots(_config), do: []

    @impl true
    def config_schema(_config),
      do: [%{key: "label", type: :integer, label: "Number", required?: false, default: 0}]

    @impl true
    def validate_config(_config), do: :ok

    @impl true
    def emit(%Block{id: id}, _context), do: {:ok, {:emitted, id}}

    @impl true
    def palette_entry, do: %{label: "Intake"}
  end

  defp root(type, module, config) do
    document = Document.new(Block.new(type, id: "blk_1", config: config), id: "doc_1")
    palette = Palette.new(%{type => module})

    ViewModel.build(document, palette, []).root
  end

  describe "the title and the subtitle" do
    # Sabotage: `title_override/2` returning the field's `default` when the
    # config holds nothing - every unnamed block of a naming type then titles
    # itself with an empty string and the card loses its name entirely.
    test "a declared label the config does not fill leaves the type's own label" do
      node = root("host.named", NamedStep, %{})

      assert node.title == nil
      assert ViewModel.title(node) == "Intake"
      assert ViewModel.subtitle(node) == nil
    end

    # Sabotage: `title_override/2` dropping the `non_empty_string/1` call - a
    # block whose name was cleared to "" titles itself blank, which is the one
    # state a card cannot recover from by looking at it.
    test "a blank name is no name" do
      assert root("host.named", NamedStep, %{"label" => "   "}).title == nil
    end

    # Sabotage: `ViewModel.subtitle/1` returning the entry label for every
    # node - every core card says its type twice, which is the duplicate the
    # two-line rule exists to remove.
    test "a named block reads as its name over its type" do
      node = root("host.named", NamedStep, %{"label" => "Collect the details"})

      assert node.title == "Collect the details"
      assert ViewModel.title(node) == "Collect the details"
      assert ViewModel.subtitle(node) == "Intake"
    end

    # Sabotage: `title_override/2` reading `Map.get(config, "label")` instead
    # of the declared `value_path` - a type that stores its name somewhere
    # else loses it, silently, on the card only.
    test "the name is read where the type said it lives" do
      node = root("host.elsewhere", NamedElsewhere, %{"presentation" => %{"label" => "Intake B"}})

      assert ViewModel.title(node) == "Intake B"
      assert ViewModel.subtitle(node) == "Intake"
    end

    # The value is a STRING under a field the type declared `:integer`, which
    # is the only shape that tells the two readings apart: a genuinely
    # numeric value is refused by `non_empty_string/1` whether or not the
    # declaration is consulted, so a fixture holding `7` would pass against a
    # match that had stopped looking at the field's type at all.
    # Sabotage: dropping `and &1.type == :string` from the field match - a
    # `:integer` field keyed `label` is then read as a name, and a card whose
    # author typed a number into a number field titles itself "7".
    test "only a string field keyed label is a name" do
      assert root("host.numeric", NumericLabel, %{"label" => "7"}).title == nil
      assert root("host.numeric", NumericLabel, %{"label" => 7}).title == nil
    end

    # Sabotage: `ViewModel.subtitle/1` dropping its equality clause - a block
    # an author happened to name exactly what its type is called says the same
    # word on both lines.
    test "a name identical to the type's label draws no second line" do
      node = root("host.named", NamedStep, %{"label" => "Intake"})

      assert ViewModel.title(node) == "Intake"
      assert ViewModel.subtitle(node) == nil
    end
  end

  describe "the invoke line" do
    # Sabotage: `invoke_type/1` reading `Map.get(config, "type")` - the line
    # goes blank on every invoke in the document at once, which is the fact an
    # author checks most on a card that calls out.
    test "a block whose config carries one" do
      assert root("core.invoke", StatifierBlocks.Core.Invoke, %{
               "invoke_type" => "myapp:authorize"
             }).invoke_type == "myapp:authorize"
    end

    # Sabotage: dropping the `non_empty_string/1` guard - a block whose invoke
    # type is unset renders an empty mono line, which reads as a rendering bug
    # rather than as an unfinished block.
    test "a block whose config does not is nil, not blank" do
      assert root("core.invoke", StatifierBlocks.Core.Invoke, %{}).invoke_type == nil

      assert root("core.invoke", StatifierBlocks.Core.Invoke, %{"invoke_type" => ""}).invoke_type ==
               nil
    end

    # The value's SHAPE is `validate_config/1`'s question and its answer
    # arrives as a finding on the same card. Sabotage: filtering the value
    # through the invoke-type regex here - the card then hides the string the
    # form is complaining about, and the two halves of the editor disagree
    # about what the block says.
    test "a malformed one still renders, because a finding already says so" do
      assert root("core.invoke", StatifierBlocks.Core.Invoke, %{"invoke_type" => "nope"}).invoke_type ==
               "nope"
    end

    # Sabotage: passing `nil` for `invoke_type` in `build_unresolvable_node/3`
    # - the one card in the document that most needs to say which handler it
    # called stops saying it.
    test "an unresolvable block still says which handler it called" do
      document =
        Document.new(
          Block.new("myapp.retired", id: "blk_1", config: %{"invoke_type" => "myapp:authorize"}),
          id: "doc_1"
        )

      node = ViewModel.build(document, Palette.new(%{}), []).root

      assert {:unresolvable, _reason} = node.status
      assert node.invoke_type == "myapp:authorize"
      assert ViewModel.title(node) == "myapp.retired"
      assert ViewModel.subtitle(node) == nil
    end
  end
end
