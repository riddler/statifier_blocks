defmodule StatifierBlocks.BlockType.ExplainTest do
  @moduledoc """
  A type's one paragraph (ADR-0017 decision 1): the optional `explain/0`
  callback, and `StatifierBlocks.BlockType.explain/1`, the resolver every
  consumer reads it through - the type's paragraph, else its palette entry's
  `description`, else `nil`, reached through the palette's one seam.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{BlockType, Palette}

  doctest StatifierBlocks.BlockType, only: [explain: 1]

  defmodule Declares do
    @moduledoc "Declares a paragraph and a palette description."
    use StatifierBlocks.BlockType

    @impl true
    def palette_entry, do: %{label: "Declares", description: "The palette line."}

    @impl true
    def explain, do: "The type's own paragraph, which wins over the palette line."

    @impl true
    def emit(_block, _context), do: {:error, :not_compiled}
  end

  defmodule DescriptionOnly do
    @moduledoc "Declares no paragraph; its palette entry has a description."
    use StatifierBlocks.BlockType

    @impl true
    def palette_entry, do: %{label: "Description only", description: "Checks a book out."}

    @impl true
    def emit(_block, _context), do: {:error, :not_compiled}
  end

  defmodule LabelOnly do
    @moduledoc "Declares no paragraph; its palette entry has no description."
    use StatifierBlocks.BlockType

    @impl true
    def palette_entry, do: %{label: "Label only"}

    @impl true
    def emit(_block, _context), do: {:error, :not_compiled}
  end

  defmodule NoEntry do
    @moduledoc "Declares neither a paragraph nor a palette entry."
    use StatifierBlocks.BlockType

    @impl true
    def emit(_block, _context), do: {:error, :not_compiled}
  end

  defmodule Refused do
    @moduledoc """
    A paragraph read from the process dictionary so one module can answer
    every refused shape in turn. Test-only: a real type is pure.
    """
    use StatifierBlocks.BlockType

    @impl true
    def palette_entry, do: %{label: "Refused", description: "Renews a loan."}

    @impl true
    def explain do
      case Process.get(:explain_answer) do
        {:raise, message} -> raise message
        {:throw, value} -> throw(value)
        {:exit, reason} -> exit(reason)
        answer -> answer
      end
    end

    @impl true
    def emit(_block, _context), do: {:error, :not_compiled}
  end

  defmodule Stateful do
    @moduledoc """
    A host's stateful type: each callback one arity higher, state first, and
    no `@behaviour` - the behaviour's arities are the declared ones.
    """

    def palette_entry(state), do: state.entry
    def explain(state), do: state.paragraph
  end

  defmodule StatefulNoParagraph do
    @moduledoc "A stateful type that declares no paragraph."

    def palette_entry(state), do: state.entry
  end

  describe "the callback" do
    # Sabotage: dropped `explain: 0` from `@optional_callbacks` - red on the
    # optional membership (the callback would then be required).
    test "explain/0 is declared, and declared optional" do
      assert {:explain, 0} in BlockType.behaviour_info(:callbacks)
      assert {:explain, 0} in BlockType.behaviour_info(:optional_callbacks)
    end

    # Sabotage: injected `def explain, do: nil` from `__using__` - red,
    # because `declares?/3` would answer true for a type that declares none.
    test "use StatifierBlocks.BlockType does not inject one" do
      refute Palette.declares?(DescriptionOnly, :explain, 0)
      refute Palette.declares?(NoEntry, :explain, 0)
      assert Palette.declares?(Declares, :explain, 0)
    end
  end

  describe "every core type explains itself" do
    # Sabotage: removed `explain/0` from `StatifierBlocks.Core.Sequence` -
    # red, because the resolver then answers the palette description, which
    # is not the module's own paragraph.
    test "the core palette's every type answers its own non-empty, one-line paragraph" do
      types = Palette.core_types()

      assert map_size(types) > 0

      for {type_name, module} <- types do
        assert Palette.declares?(module, :explain, 0), "#{type_name} declares no explain/0"

        text = BlockType.explain(module)

        assert is_binary(text), "#{type_name} answers no explanation"
        assert String.trim(text) != "", "#{type_name} answers a blank explanation"
        refute String.contains?(text, ["\n", "\r", "\t"]), "#{type_name} is not one line"
        assert text == module.explain(), "#{type_name} answers something other than its paragraph"
      end
    end

    # Sabotage: made `StatifierBlocks.Core.Group.explain/0` answer its
    # palette description - red on the distinctness assertion.
    test "no core type's paragraph is its palette description, and no two share one" do
      paragraphs =
        for {_type_name, module} <- Palette.core_types() do
          %{description: description} = module.palette_entry()
          refute module.explain() == description
          module.explain()
        end

      assert paragraphs == Enum.uniq(paragraphs)
    end
  end

  describe "the resolver" do
    # Sabotage: answered the description before the paragraph - red.
    test "a declared, usable paragraph wins, verbatim" do
      assert BlockType.explain(Declares) ==
               "The type's own paragraph, which wins over the palette line."
    end

    # Sabotage: answered `nil` instead of falling to the description - red.
    test "a type without the callback answers its palette description" do
      assert BlockType.explain(DescriptionOnly) == "Checks a book out."
    end

    # Sabotage: fell back to the palette label - red on both.
    test "a type without the callback and without a description answers nil" do
      assert BlockType.explain(LabelOnly) == nil
      assert BlockType.explain(NoEntry) == nil
    end

    # Sabotage: dropped the `Code.ensure_loaded?/1` guard's use (called the
    # module directly) - red with an UndefinedFunctionError.
    test "a module that is not loadable answers nil" do
      assert BlockType.explain(NoSuchExplainModule) == nil
      assert BlockType.explain({NoSuchExplainModule, %{}}) == nil
    end

    # Sabotage: removed `line/1` from the declared arm - red on the blank,
    # multiline and non-string answers.
    test "a refused paragraph falls to the palette description" do
      for answer <- [
            "",
            "   ",
            "two\nlines",
            "a\rreturn",
            "a\ttab",
            nil,
            :atom,
            42,
            {:raise, "boom"},
            {:throw, :boom},
            {:exit, :boom}
          ] do
        Process.put(:explain_answer, answer)
        assert BlockType.explain(Refused) == "Renews a loan.", "answer #{inspect(answer)}"
      end
    after
      Process.delete(:explain_answer)
    end

    # Sabotage: called `module.explain()` rather than going through
    # `Palette.call/4` - red, the stateful module exports no `explain/0`.
    test "a {module, state} reference resolves through the palette seam" do
      state = %{
        paragraph: "A stateful type's paragraph.",
        entry: %{label: "Stateful", description: "A stateful description."}
      }

      assert BlockType.explain({Stateful, state}) == "A stateful type's paragraph."

      assert BlockType.explain({StatefulNoParagraph, state}) == "A stateful description."

      assert BlockType.explain({StatefulNoParagraph, %{entry: %{label: "No description"}}}) ==
               nil
    end

    # Sabotage: dropped `line/1` from `description/1` - red, a multiline
    # description is then answered.
    test "an unusable palette description is nil, not an answer" do
      assert BlockType.explain({StatefulNoParagraph, %{entry: %{description: "a\nb"}}}) == nil
      assert BlockType.explain({StatefulNoParagraph, %{entry: %{description: 7}}}) == nil
    end
  end
end
