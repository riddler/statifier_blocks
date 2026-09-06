defmodule StatifierBlocks.BlockType.DefaultConfigTest do
  use ExUnit.Case, async: true

  @moduledoc """
  `StatifierBlocks.BlockType.default_config/1`: the palette entry's answer
  to what a probe of this type is asked about with (sb-1c7g).

  A pure test file rather than a case in the editor's, because the reader
  is inert data with no LiveView in it - the headless run compiles and runs
  this one, and the editor test that consumes it is excluded there.
  """

  alias StatifierBlocks.BlockType

  doctest StatifierBlocks.BlockType, only: [default_config: 1]

  describe "what it reads" do
    # Sabotage: `default_config/1` returning the declared map unfiltered -
    # this goes red, because the atom-keyed pair survives into a config no
    # `config_schema/1` field could ever name.
    test "keeps the string-keyed pairs and drops every other key" do
      entry = %{
        default_config: %{
          "subject" => "cards.current_txn",
          :subject => "cards.current_txn",
          1 => "cards.current_txn"
        }
      }

      assert BlockType.default_config(entry) == %{"subject" => "cards.current_txn"}
    end

    # Sabotage: dropping the `is_map(declared)` guard - this goes red on
    # the binary, which `Map.merge/2` would then raise on at the probe.
    test "reads every declaration that is not a map as absent" do
      for declared <- ["cards.current_txn", :cards, 1, ["cards.current_txn"], nil] do
        assert BlockType.default_config(%{default_config: declared}) == %{}
      end
    end

    # Sabotage: removing the `default_config(_entry)` catch-all - this goes
    # red, because a palette entry that is not a map raises where every
    # other decision-10 reader answers.
    test "is total over an entry that is not a map at all" do
      assert BlockType.default_config(nil) == %{}
      assert BlockType.default_config("Final settlement") == %{}
    end

    # Sabotage: `Map.get(entry, :default_config, %{"subject" => ""})` -
    # this goes red, and so does every existing type, which is the point:
    # the key is optional and absent means the schema's defaults stand.
    test "an entry that never heard of the key declares nothing" do
      assert BlockType.default_config(%{label: "Final settlement"}) == %{}
    end
  end
end
