defmodule StatifierBlocks.Runtime.RunValuesTest do
  @moduledoc """
  `StatifierBlocks.Runtime.RunValues` with a stand-in for statifier-ui's
  datamodel fold.

  `async: false`, because the stand-in is installed in application config and
  that is global. Not tagged `:liveview` and naming no `StatifierUI` module at
  compile time, which is what lets this file run in the headless tree and prove
  that the cut and the flattening work with the package absent.

  The stand-in records the message list it was handed, which is the only way to
  assert the half this module actually owns: the fold is statifier-ui's and is
  not re-tested here, but *which prefix of the stream is folded* is this
  module's decision and is what a selection changes.
  """

  use ExUnit.Case, async: false

  alias StatifierBlocks.Runtime.RunValues

  defmodule StubExplorer do
    @moduledoc """
    Test-only stand-in for `StatifierUI.DatamodelExplorer.build_live/1`.

    A "message" here is a map carrying the envelope's `macrostep` and the
    entries the fold would have produced from it, so a test says which writes
    are in view rather than building a wire stream to imply them. The pane the
    stand-in returns holds every entry from every message it was handed, which
    makes the cut visible in the result.
    """

    def build_live(messages) do
      send(self(), {:folded, Enum.map(messages, &Map.get(&1, :macrostep))})

      case Enum.find(messages, &Map.get(&1, :refuse)) do
        nil -> {:ok, %{entries: Enum.flat_map(messages, &Map.get(&1, :entries, []))}}
        _refused -> {:error, {:mixed_sessions, ["a", "b"]}}
      end
    end
  end

  defmodule NoExplorer do
    @moduledoc "A module with no `build_live/1` at all: the absent-package branch."
  end

  setup do
    Application.put_env(:statifier_blocks, :trace_datamodel_module, StubExplorer)
    on_exit(fn -> Application.delete_env(:statifier_blocks, :trace_datamodel_module) end)
    :ok
  end

  defp entry(name, tier, value, children \\ []) do
    %{name: name, tier: tier, value: value, children: children}
  end

  defp message(macrostep, entries), do: %{macrostep: macrostep, entries: entries}

  describe "what a run is holding" do
    # Sabotage: had `put_value/3` write the value straight through instead of
    # `inspect/1` - the string came back unquoted and this went red on the
    # quotes, which is the difference between the text `settled` and a value
    # that is the word (verified).
    test "is display text keyed by path" do
      state = %{
        messages: [message(2, [entry("settlement", :data, "settled")])],
        selection: :live
      }

      assert RunValues.at(state) == %{"settlement" => ~s("settled")}
    end

    # Sabotage: had `paths/2` ignore `entry.children` - the nested path
    # disappeared and this went red (verified).
    test "flattens a nested value into dotted paths" do
      children = [entry("brand", :data, "visa"), entry("last4", :data, "4242")]

      state = %{
        messages: [message(2, [entry("card", :data, %{}, children)])],
        selection: :live
      }

      assert RunValues.at(state) == %{
               "card" => "%{}",
               "card.brand" => ~s("visa"),
               "card.last4" => ~s("4242")
             }
    end

    # Sabotage: dropped the `:undefined` clause from `put_value/3` - a
    # declared-but-unwritten path came back holding the text `:undefined`,
    # which the drawer would then draw as a held value (verified).
    test "drops a path the run has not written" do
      state = %{
        messages: [message(2, [entry("settlement", :data, :undefined)])],
        selection: :live
      }

      assert RunValues.at(state) == %{}
    end

    # Sabotage: added `:system` and `:function` to `@kept_tiers` - every
    # provider function and system variable joined the map, and this went red
    # on the extra keys (verified).
    test "keeps only what the document's datamodel holds" do
      entries = [
        entry("settlement", :data, "settled"),
        entry("idlocation", :runtime, "inv_1"),
        entry("_sessionid", :system, "sess_1"),
        entry("Math.abs", :function, :undefined)
      ]

      state = %{messages: [message(2, entries)], selection: :live}

      assert RunValues.at(state) == %{
               "settlement" => ~s("settled"),
               "idlocation" => ~s("inv_1")
             }
    end
  end

  describe "the cut" do
    setup do
      messages = [
        %{macrostep: nil, entries: [entry("settlement", :data, :undefined)]},
        message(1, [entry("settlement", :data, "pending")]),
        message(2, [entry("settlement", :data, "settled")]),
        message(3, [entry("settlement", :data, "reconciled")])
      ]

      {:ok, messages: messages}
    end

    # Sabotage: had `in_view/2` compare with `<` instead of `<=` - the
    # selected macrostep's own writes fell out of the fold and the value came
    # back as the one BEFORE the step the scrubber is on (verified).
    test "keeps the selected macrostep's own writes", %{messages: messages} do
      state = %{messages: messages, selection: {:macrostep, 2}}

      assert RunValues.at(state) == %{"settlement" => ~s("settled")}
      assert_received {:folded, [nil, 1, 2]}
    end

    # Sabotage: had `in_view/2` drop a message whose macrostep is `nil` - the
    # manifest and the starting snapshot left the prefix, which is what the
    # real fold seeds its names from (verified).
    test "keeps every message the envelope stamps with no macrostep", %{messages: messages} do
      state = %{messages: messages, selection: {:macrostep, 1}}

      assert RunValues.at(state) == %{"settlement" => ~s("pending")}
      assert_received {:folded, [nil, 1]}
    end

    # Sabotage: made the `in_view/2` catch-all cut at macrostep 0 rather than
    # returning the list - the live tip stopped showing anything the run had
    # written and this went red (verified).
    test "is not a cut at all on the live tip", %{messages: messages} do
      state = %{messages: messages, selection: :live}

      assert RunValues.at(state) == %{"settlement" => ~s("reconciled")}
      assert_received {:folded, [nil, 1, 2, 3]}
    end
  end

  describe "the gaps" do
    # Sabotage: removed the `function_exported?/3` check from
    # `explorer_module/0` - the call reached a module with no `build_live/1`
    # and raised `UndefinedFunctionError` instead of answering nothing
    # (verified).
    test "a tree with no resolvable explorer holds nothing" do
      Application.put_env(:statifier_blocks, :trace_datamodel_module, NoExplorer)

      assert RunValues.at(%{messages: [message(1, [])], selection: :live}) == %{}
    end

    # A fold that refuses is a fact about the stream, not about this module,
    # and the caller's question - what is there to draw beside a type - has
    # the same answer either way.
    test "a stream the fold refuses holds nothing" do
      state = %{messages: [%{macrostep: 1, refuse: true, entries: []}], selection: :live}

      assert RunValues.at(state) == %{}
    end

    test "a shape that is not a read model holds nothing" do
      assert RunValues.at(%{}) == %{}
      assert RunValues.at(%{messages: "not a list"}) == %{}
    end
  end
end
