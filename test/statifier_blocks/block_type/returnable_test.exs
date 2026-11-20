defmodule StatifierBlocks.BlockType.ReturnableTest do
  @moduledoc """
  A block type may declare its instances returnable steps (ADR-0002's
  2026-11-20 amendment): the optional `returnable?/1` callback (`C12`), the
  resolver every consumer reads it through, the two refusals `Palette.new/2`
  makes when a palette is built (`C12b`), and the one fact the view model's
  palette entry carries (`C12c`). The browser's drawing of that fact is
  `StatifierBlocks.Editor.PaletteBodyTest`'s, because it needs LiveView.

  The fixtures are test-only types for a library's patron registration; no
  core type declares the callback.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, BlockType, Document, Palette, ViewModel}

  doctest StatifierBlocks.BlockType, only: [returnable?: 2]

  defmodule Collect do
    @moduledoc "Returnable unless the author says the patron may not come back to it."
    use StatifierBlocks.BlockType

    @impl true
    def config_schema(_config) do
      [
        %{key: "prompt", type: :string, label: "What to collect", required?: true, default: ""},
        %{
          key: "revisable",
          type: :boolean,
          label: "The patron may come back to this",
          required?: false,
          default: true
        }
      ]
    end

    @impl true
    def returnable?(config), do: Map.get(config, "revisable", true) == true

    @impl true
    def emit(_block, _context), do: {:error, :not_compiled}
  end

  defmodule OptionalRevisable do
    @moduledoc """
    Answers its `revisable` field as it stands. The field is not required and
    defaults to `true`, so a fresh block's config carries `true` only when
    every schema default is taken, required or not.
    """
    use StatifierBlocks.BlockType

    @impl true
    def config_schema(_config),
      do: [
        %{key: "revisable", type: :boolean, label: "Revisable", required?: false, default: true}
      ]

    @impl true
    def returnable?(config), do: config["revisable"]

    @impl true
    def emit(_block, _context), do: {:error, :not_compiled}
  end

  defmodule ReturnableRecipe do
    @moduledoc "A recipe that happens to export `returnable?/1`; a recipe entry is never marked."
    @behaviour StatifierBlocks.Recipe

    @impl true
    def insert(_target, _document), do: {:error, :never}

    @impl true
    def palette_entry, do: %{label: "Renewal", group: "Library", order: 1}

    def returnable?(_config), do: true
  end

  defmodule NeverReturnable do
    @moduledoc "Declares the callback and answers `false` for every config."
    use StatifierBlocks.BlockType

    @impl true
    def returnable?(_config), do: false

    @impl true
    def emit(_block, _context), do: {:error, :not_compiled}
  end

  defmodule IssueCard do
    @moduledoc "Uses the behaviour and declares nothing about returning."
    use StatifierBlocks.BlockType

    @impl true
    def emit(_block, _context), do: {:error, :not_compiled}
  end

  defmodule AnswersPrompt do
    @moduledoc "Answers its `prompt` string, which is not a boolean."
    use StatifierBlocks.BlockType

    @impl true
    def config_schema(_config),
      do: [%{key: "prompt", type: :string, label: "Prompt", required?: true, default: ""}]

    @impl true
    def returnable?(config), do: config["prompt"]

    @impl true
    def emit(_block, _context), do: {:error, :not_compiled}
  end

  defmodule AnswersNil do
    @moduledoc "Answers `nil` for a config with no `revisable` key."
    use StatifierBlocks.BlockType

    @impl true
    def returnable?(config), do: Map.get(config, "revisable")

    @impl true
    def emit(_block, _context), do: {:error, :not_compiled}
  end

  defmodule Raises do
    @moduledoc "Raises from the callback."
    use StatifierBlocks.BlockType

    @impl true
    def returnable?(_config), do: raise(ArgumentError, "the agreement is not loaded")

    @impl true
    def emit(_block, _context), do: {:error, :not_compiled}
  end

  defmodule Throws do
    @moduledoc "Throws from the callback."
    use StatifierBlocks.BlockType

    @impl true
    def returnable?(_config), do: throw(:not_sure)

    @impl true
    def emit(_block, _context), do: {:error, :not_compiled}
  end

  defmodule Exits do
    @moduledoc "Exits from the callback."
    use StatifierBlocks.BlockType

    @impl true
    def returnable?(_config), do: exit(:gone)

    @impl true
    def emit(_block, _context), do: {:error, :not_compiled}
  end

  defmodule SchemaRaises do
    @moduledoc "Raises while its fresh config is built, before the callback is asked."
    use StatifierBlocks.BlockType

    @impl true
    def config_schema(_config), do: raise(RuntimeError, "no schema today")

    @impl true
    def returnable?(_config), do: true

    @impl true
    def emit(_block, _context), do: {:error, :not_compiled}
  end

  defmodule Stateful do
    @moduledoc """
    A stateful entry's module: it declares `returnable?/1` at one higher
    arity, `(state, config)`, and its state decides the answer.
    """

    def returnable?(state, _config), do: state
    def current_version(_state), do: 1
  end

  defmodule Checkout do
    @moduledoc "A module composite that declares the callback, which no composite may."

    use StatifierBlocks.Composite,
      name: "library.checkout",
      params: [],
      palette_entry: %{label: "Checkout"},
      version: 1

    @impl StatifierBlocks.Composite
    def subtree(_params), do: [Block.new("core.wait", id: "pause")]

    def returnable?(_config), do: true
  end

  describe "the declaration (C12)" do
    # Sabotage: dropped `returnable?: 1` from `@optional_callbacks` - every
    # `use`-ing fixture above warns of a missing callback and this goes red.
    test "is an optional callback of arity one" do
      assert {:returnable?, 1} in BlockType.behaviour_info(:callbacks)
      assert {:returnable?, 1} in BlockType.behaviour_info(:optional_callbacks)
    end

    # Sabotage: injected `def returnable?(_config), do: false` (and its
    # `defoverridable`) in `__using__/1` - red here, and the view model marks
    # every `use`-ing type below.
    test "is not injected by use StatifierBlocks.BlockType" do
      refute Palette.declares?(IssueCard, :returnable?, 1)
      assert Palette.declares?(Collect, :returnable?, 1)
    end
  end

  describe "BlockType.returnable?/2" do
    # Sabotage: `Palette.call(ref, :returnable?, [config], false) == true`
    # replaced by `Palette.call(ref, :returnable?, [config], true) == true` -
    # red on the absent callback and the unloadable module.
    test "is false for a type that does not declare the callback, or cannot be loaded" do
      refute BlockType.returnable?(IssueCard, %{})
      refute BlockType.returnable?(NoSuchLibraryModule, %{})
    end

    # Sabotage: dropped the `== true` - the non-boolean answers come back as
    # themselves and the `false` assertions go red on "" and nil.
    test "is true only for an answer of exactly true" do
      assert BlockType.returnable?(Collect, %{"revisable" => true})
      refute BlockType.returnable?(Collect, %{"revisable" => false})
      refute BlockType.returnable?(NeverReturnable, %{})
      assert BlockType.returnable?(AnswersPrompt, %{"prompt" => ""}) == false
      assert BlockType.returnable?(AnswersNil, %{}) == false
    end

    # Sabotage: wrapped the resolver's call in `try ... rescue _ -> false` -
    # the raise is swallowed and `assert_raise` goes red.
    test "does not rescue a raise" do
      assert_raise ArgumentError, "the agreement is not loaded", fn ->
        BlockType.returnable?(Raises, %{})
      end
    end

    # Sabotage: called `module.returnable?(config)` directly instead of through
    # `Palette.call/4` - the stateful entry is asked at the wrong arity and
    # raises `UndefinedFunctionError`.
    test "asks a stateful entry through the call seam, with its state first" do
      assert BlockType.returnable?({Stateful, true}, %{})
      refute BlockType.returnable?({Stateful, false}, %{})
      refute BlockType.returnable?({Stateful, "yes"}, %{})
    end
  end

  describe "Palette.new/2 at registration (C12b)" do
    # Sabotage: dropped `refute_bad_returnables!(types)` from `new/2` - every
    # palette below builds and the `assert_raise`s in this describe go red;
    # the admissions here stay green, which is what pins them as admissions.
    #
    # Sabotage: `fresh_config/1` keeping only required fields' defaults -
    # `OptionalRevisable` is asked with no `revisable` key, answers nil, and
    # this goes red on the raise.
    test "admits a type whose answer for a fresh block is a boolean" do
      types = %{
        "library.collect" => Collect,
        "library.never" => NeverReturnable,
        "library.optional" => OptionalRevisable,
        "library.issue_card" => IssueCard,
        "library.stateful" => {Stateful, false}
      }

      built =
        try do
          {:ok, Palette.new(types)}
        rescue
          error in ArgumentError -> {:refused, Exception.message(error)}
        end

      assert {:ok, %Palette{types: ^types}} = built
    end

    # One config is asked, not every config: `AnswersNil` answers nil for a
    # config with no `revisable` key, and a fresh block of it has none, so it
    # is refused; `OptionalRevisable` answers nil the same way for such a
    # config, but its fresh config carries the key from its optional field's
    # default, so it is admitted above.
    #
    # Sabotage: `fresh_returnable_answer/1` asking `%{}` instead of the
    # fresh config - `Collect`'s fresh answer is unchanged, so the probe here
    # is `AnswersPrompt`: asked with `%{}` it answers nil, not "", and the
    # message assertion on `""` goes red.
    test "refuses a non-boolean answer for a fresh block's config, naming the entry" do
      assert_raise ArgumentError,
                   ~r/"library.answers_nil".*answered nil for a fresh block's config, which is not a boolean/,
                   fn -> Palette.new(%{"library.answers_nil" => AnswersNil}) end

      assert_raise ArgumentError,
                   ~r/"library.prompt".*answered "" for a fresh block's config/,
                   fn ->
                     Palette.new(%{"library.prompt" => AnswersPrompt})
                   end
    end

    # Sabotage: the `{step, kind, reason}` arm collapsed to one fixed message
    # ("returnable?/1 failed") - each of the three message assertions goes red.
    test "refuses a raise, a throw or an exit from the callback, saying which" do
      assert_raise ArgumentError,
                   ~r/"library.raises".*raised in returnable\?\/1 for a fresh block's config: the agreement is not loaded/,
                   fn -> Palette.new(%{"library.raises" => Raises}) end

      assert_raise ArgumentError, ~r/"library.throws".*threw in returnable\?\/1.*:not_sure/, fn ->
        Palette.new(%{"library.throws" => Throws})
      end

      assert_raise ArgumentError, ~r/"library.exits".*exited in returnable\?\/1.*:gone/, fn ->
        Palette.new(%{"library.exits" => Exits})
      end
    end

    # Sabotage: building the fresh config outside the `try` - the schema's
    # raise escapes as a `RuntimeError` and `assert_raise ArgumentError` goes red.
    test "refuses a raise while building the fresh config, saying so" do
      assert_raise ArgumentError,
                   ~r/"library.schema_raises".*raised while building a fresh block's config for returnable\?\/1: no schema today/,
                   fn -> Palette.new(%{"library.schema_raises" => SchemaRaises}) end
    end

    # Sabotage: dropped the `Composite.composite?/1` check - the composite's
    # answer, `true`, is a boolean, so it is admitted and this goes red.
    test "refuses a composite that declares the callback" do
      assert_raise ArgumentError,
                   ~r/"library.checkout".*is a composite and declares returnable\?\/1/,
                   fn -> Palette.new(%{"library.checkout" => Checkout}) end
    end

    # Sabotage: dropped `refute_bad_returnables!(types)` from `new/2` - the
    # stateful entry is admitted and this goes red (verified).
    test "refuses a stateful entry whose answer is not a boolean" do
      assert_raise ArgumentError, ~r/"library.stateful".*answered "yes"/, fn ->
        Palette.new(%{"library.stateful" => {Stateful, "yes"}})
      end
    end

    # Sabotage: dropped `refute_bad_returnables!(types)` from `new/2` -
    # `from_modules/2` admits the bad entry and this goes red (verified).
    test "is reached through from_modules/2, and the core palette meets neither refusal" do
      assert_raise ArgumentError, ~r/"library.prompt"/, fn ->
        Palette.from_modules([{"library.prompt", AnswersPrompt}], core: true)
      end

      core = Palette.core()
      refute Enum.any?(core.types, fn {_name, ref} -> Palette.declares?(ref, :returnable?, 1) end)
    end
  end

  describe "the view model's palette entry (C12c)" do
    defp palette_entries(types, recipes \\ %{}) do
      root = Block.new("core.sequence", id: "root")

      root
      |> Document.new()
      |> ViewModel.build(
        Palette.new(Map.put(types, "core.sequence", StatifierBlocks.Core.Sequence),
          recipes: recipes
        ),
        []
      )
      |> Map.fetch!(:palette_groups)
      |> Enum.flat_map(& &1.entries)
      |> Map.new(&{&1.name, &1})
    end

    # Sabotage: `put_returnable/2` reading `BlockType.returnable?(ref, %{})`
    # instead of declaredness - `NeverReturnable` loses the key and the
    # second assertion goes red.
    test "carries returnable: true for a type that declares the callback, whatever it answers" do
      entries =
        palette_entries(%{
          "library.collect" => Collect,
          "library.never" => NeverReturnable,
          "library.stateful" => {Stateful, false}
        })

      assert %{returnable: true} = entries["library.collect"]
      assert %{returnable: true} = entries["library.never"]
      assert %{returnable: true} = entries["library.stateful"]
    end

    # Sabotage: `Map.put(entry, :returnable, false)` in the else arm - the
    # key appears and `refute Map.has_key?/2` goes red.
    test "carries no :returnable key otherwise" do
      entries = palette_entries(%{"library.issue_card" => IssueCard})

      refute Map.has_key?(entries["library.issue_card"], :returnable)
      refute Map.has_key?(entries["core.sequence"], :returnable)
    end

    # Sabotage: `put_returnable/2` also piped onto each recipe entry in
    # `palette_groups/1` - the recipe that exports `returnable?/1` gains the
    # key and this goes red.
    test "never carries a :returnable key on a recipe entry" do
      entries = palette_entries(%{}, %{"library.renewal" => ReturnableRecipe})

      assert %{kind: :recipe} = entries["library.renewal"]
      refute Map.has_key?(entries["library.renewal"], :returnable)
    end
  end

  describe "the moduledoc's counts read true" do
    @numbers ~w(zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen)

    defp moduledoc do
      {:docs_v1, _anno, :elixir, _format, %{"en" => doc}, _meta, _docs} =
        Code.fetch_docs(BlockType)

      doc
    end

    # Sabotage: the moduledoc back to "Ten are optional" - red.
    test "the optional count and list match @optional_callbacks" do
      optional = BlockType.behaviour_info(:optional_callbacks)
      word = String.capitalize(Enum.at(@numbers, length(optional)))

      assert moduledoc() =~ ~r/#{word} are\s+optional/

      for {name, arity} <- optional do
        assert moduledoc() =~ "| `#{name}/#{arity}` | no |"
        assert moduledoc() =~ ~r/#{Regex.escape("#{name}: #{arity}")}/
      end
    end

    # Sabotage: the moduledoc back to "all nine callbacks" - red.
    test "the injected count matches what use injects" do
      injected =
        Enum.count(BlockType.behaviour_info(:callbacks), fn {name, arity} ->
          function_exported?(IssueCard, name, arity) and {name, arity} != {:emit, 2}
        end)

      assert moduledoc() =~ ~r/all\s+#{Enum.at(@numbers, injected)}\s+injected\s+callbacks/
    end

    # Sabotage: the opening back to "is not present yet" - red.
    test "the opening names the core vocabulary as shipped" do
      refute moduledoc() =~ ~r/not\s+present\s+yet/
      assert moduledoc() =~ "StatifierBlocks.Palette.core/0"
      assert map_size(Palette.core().types) > 0
    end
  end
end
