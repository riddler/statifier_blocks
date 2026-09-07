defmodule StatifierBlocks.Core.TypeExprMigrationTest do
  @moduledoc """
  The migration clause 8 of `ADR-0002`'s amendment of 2026-09-06 states:
  `core.map`'s `collect_type` and `core.on_event`'s `payload` are
  `{:type_expr, opts}` fields now, and **a stored string is the name arm**.

  `StatifierBlocks.Compiler.ByteCorpusTest` pins the family's own documents
  against goldens captured before any of this. This file pins the two
  fields themselves, which no corpus entry carries: one document holding a
  string in each, asserted byte for byte against the same document with the
  keys absent, and asserted to be read as a name rather than merely
  tolerated - the declaration reaching `collect`'s envelope, and the
  declaration resolving for the `capture` refusal.

  The inline arm's own behaviour is each block type's test. What is here is
  the half a migration can get wrong: the documents that already exist.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, BlockType, Compiler, Document, Palette}
  alias StatifierBlocks.Core.{Map, OnEvent}

  @datamodel %{
    "types" => [
      %{
        "name" => "cards.chunk_result",
        "kind" => "record",
        "label" => "Chunk result",
        "fields" => [%{"name" => "amount_minor", "type" => "integer"}]
      },
      %{
        "name" => "cards.declined",
        "kind" => "record",
        "label" => "Declined authorization",
        "fields" => [%{"name" => "reason", "type" => "string"}]
      }
    ]
  }

  @map_config %{
    "items" => "cards.chunks",
    "chart" => "bdoc_CHUNK",
    "item_as" => "chunk",
    "collect" => "cards.answers"
  }

  @handler_config %{
    "event" => "cards.declined",
    "outcome" => "abandon",
    "capture" => %{"cards.why" => "reason"}
  }

  describe "a stored string compiles to the bytes it compiled to before" do
    # sabotage: had `core.map`'s `emit/2` write a `<param>` for
    # `collect_type` - the field stops producing no bytes, the stored
    # string moves the compile, and this goes red (verified)
    test "collect_type produces no bytes, declared or absent" do
      declared = compile!(map_block(%{"collect_type" => "cards.chunk_result"}))

      assert declared == compile!(map_block(%{}))
      assert declared == compile!(map_block(%{"collect_type" => ""}))
    end

    # sabotage: had `core.on_event`'s `emit/2` carry the payload name into
    # the transition - the declaration stops being a declaration and this
    # goes red (verified)
    test "payload produces no bytes, declared or absent" do
      declared = compile!(handler_block(%{"payload" => "cards.declined"}))

      assert declared == compile!(handler_block(%{}))
      assert declared == compile!(handler_block(%{"payload" => ""}))
    end
  end

  describe "a stored string is the name arm, and is read as one" do
    # sabotage: dropped `:name` from either field's declared `arms` - the
    # shared check refuses the stored string every document already holds,
    # and this goes red on that field (verified)
    test "the shared check admits the text both fields store today" do
      assert BlockType.type_expr_findings(Map, map_config(%{"collect_type" => "cards.settle"})) ==
               []

      assert BlockType.type_expr_findings(Map, map_config(%{"collect_type" => ""})) == []
      assert BlockType.type_expr_findings(Map, map_config(%{})) == []

      assert BlockType.type_expr_findings(
               OnEvent,
               handler_config(%{"payload" => "cards.declined"})
             ) == []

      assert BlockType.type_expr_findings(OnEvent, handler_config(%{"payload" => ""})) == []
      assert BlockType.type_expr_findings(OnEvent, handler_config(%{})) == []
    end

    # sabotage: had `declared_summary/1` answer `:unknown` for a binary -
    # the stored name stops typing the envelope's member and this goes red
    # (verified)
    test "a stored collect_type still types the envelope's donedata member" do
      %{type: {:path, %{writes: {:list, {:shape, members}}}}} =
        %{"collect_type" => "cards.chunk_result"}
        |> map_config()
        |> Map.config_schema()
        |> Enum.find(&(&1.key == "collect"))

      assert Enum.find(members, &(&1.name == "donedata")).type == "cards.chunk_result"
    end

    # sabotage: dropped `declared_payload/2`'s binary clause - a stored
    # payload name stops resolving, the refusal stops firing, and the
    # second assertion goes red (verified)
    test "a stored payload still resolves for the capture refusal" do
      assert {:ok, _read} =
               compile(handler_block(%{"payload" => "cards.declined"}), datamodel: @datamodel)

      assert {:error, [finding]} =
               handler_block(%{
                 "payload" => "cards.declined",
                 "capture" => %{"cards.why" => "code"}
               })
               |> compile(datamodel: @datamodel)

      assert finding.config_key == "capture"
      assert finding.message =~ "cards.declined"
    end
  end

  # -- helpers ---------------------------------------------------------------

  defp map_config(extra), do: Elixir.Map.merge(@map_config, extra)

  defp handler_config(extra), do: Elixir.Map.merge(@handler_config, extra)

  defp map_block(extra), do: Block.new("core.map", id: "blk_MAP", config: map_config(extra))

  defp handler_block(extra) do
    Block.new("core.group",
      id: "blk_GRP",
      slots: %{
        "body" => [Block.new("core.sequence", id: "blk_SEQ")],
        "interrupts" => [
          Block.new("core.on_event", id: "blk_OE", config: handler_config(extra))
        ]
      }
    )
  end

  defp compile(%Block{} = root, opts) do
    Compiler.compile(Document.new(root, id: "bdoc_MIGRATION"), Palette.core(), opts)
  end

  defp compile!(%Block{} = root) do
    assert {:ok, compiled} = compile(root, datamodel: @datamodel)
    compiled.scxml
  end
end
