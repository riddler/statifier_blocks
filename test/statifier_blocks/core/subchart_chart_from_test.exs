defmodule StatifierBlocks.Core.SubchartChartFromTest do
  @moduledoc """
  `core.subchart` naming its child by `chart_from`, a datamodel path
  (ADR-0004's Amendment of 2026-11-19): J1's config rule and emission, J2's
  outcomes carrier, J4's self-reference reach and J5's absent reference.

  The literal form's bytes are `StatifierBlocks.Core.SubchartBytesTest`'s;
  the run-time half is `StatifierBlocks.Runtime.SubchartChartFromTest`'s.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Compiler, Document, Environment, Palette}
  alias StatifierBlocks.Compiler.Context
  alias StatifierBlocks.Core.Subchart

  @setup %{"chart_from" => "onboarding.setup_document", "outcomes" => "done\nskipped"}

  describe "the typed environment reads chart_from and never writes it" do
    # sabotage: declared `chart_from` as `{:path, %{}}` again -> the path is
    # listed among the write signatures as `:unknown`, it leaves the read
    # signatures, and both assertions go red (verified)
    test "the path is a read expecting a string, and no write" do
      block = Block.new("core.subchart", id: "blk_SETUP", config: @setup)
      document = Document.new(block, id: "bdoc_ONBOARD")
      palette = Palette.core()

      assert {"chart_from", "onboarding.setup_document", "string"} in Environment.read_signatures(
               palette,
               document,
               block
             )

      refute Enum.any?(
               Environment.write_signatures(palette, document, block),
               fn {key, _path, _type} -> key == "chart_from" end
             )
    end
  end

  describe "validate_config/1 (J1)" do
    # sabotage: let `child_source/1` ignore `chart_from` and fall through to
    # the literal rule -> a config with only `chart_from` raises the `chart`
    # finding and the first assertion goes red (verified)
    test "a datamodel path in chart_from names the child on its own" do
      assert Subchart.validate_config(@setup) == :ok
      assert Subchart.validate_config(%{"chart_from" => "next"}) == :ok
      assert Subchart.validate_config(Map.put(@setup, "chart", "")) == :ok
    end

    # sabotage: dropped the both-present clause from `child_source/1` ->
    # the config with both keys validates and this goes red (verified)
    test "chart and chart_from together is one finding, on chart_from" do
      assert {:error, [{"chart_from", message}]} =
               Subchart.validate_config(Map.put(@setup, "chart", "bdoc_CHILD"))

      assert message =~ "never both"
    end

    # sabotage: accepted any non-empty string as a path -> the whitespace
    # value validates and this goes red (verified)
    test "chart_from is a datamodel path, in assign_to's grammar" do
      assert {:error, [{"chart_from", message}]} =
               Subchart.validate_config(%{"chart_from" => "onboarding setup"})

      assert message =~ "datamodel path"

      assert {:error, [{"chart_from", _message}]} =
               Subchart.validate_config(%{"chart_from" => 42})
    end

    test "neither key is the finding chart has always raised, and an empty chart_from is absent" do
      assert {:error, [{"chart", message}]} = Subchart.validate_config(%{})
      assert message =~ "names the document to run"

      assert {:error, [{"chart", ^message}]} =
               Subchart.validate_config(%{"chart_from" => "", "chart" => ""})

      assert Subchart.validate_config(%{"chart_from" => "", "chart" => "bdoc_CHILD"}) == :ok
    end
  end

  describe "emit/2 (J1 and J2)" do
    # sabotage: wrote the path as `src` rather than `srcexpr` -> the
    # element carries `src="onboarding.setup_document"` and this goes red
    # (verified)
    test "the path is written verbatim as srcexpr, and no src is emitted" do
      scxml = compile!(@setup).scxml

      assert scxml =~
               ~s(<invoke id="blk_SETUP" srcexpr="onboarding.setup_document" type="statifier_blocks:subchart">)

      refute scxml =~ ~s( src=")
    end

    # sabotage: appended the carrier before the author's rows -> the order
    # check goes red (verified)
    test "the reserved outcomes param follows the author's params, carrying outcome_names/1 in order" do
      scxml = compile!(Map.put(@setup, "params", "branch=onboarding.branch")).scxml

      assert scxml =~
               ~s(<param expr="onboarding.branch" name="branch"/>) <>
                 ~s(<param expr="'done skipped error'" name="statifier_blocks:outcomes"/>)

      assert Subchart.outcome_names(@setup) == ["done", "skipped", "error"]
    end

    # sabotage: emitted the carrier from `child_outcomes/1` instead of
    # `outcome_names/1` -> the appended `error` is lost and this goes red
    # (verified)
    test "the carrier holds done and error when the author listed no outcomes" do
      scxml = compile!(%{"chart_from" => "onboarding.next"}).scxml
      assert scxml =~ ~s(<param expr="'done error'" name="statifier_blocks:outcomes"/>)
    end

    # sabotage: stamped `srcexpr` as coming from `chart` -> the owner
    # reads `chart` and this goes red (verified)
    test "srcexpr is stamped as coming from chart_from, and the carrier from no field" do
      {:ok, emission} =
        Subchart.emit(
          Block.new("core.subchart", id: "blk_SETUP", config: @setup),
          context()
        )

      invoke = find_element(emission, "invoke")
      assert invoke.attribute_owners == [{"srcexpr", "chart_from"}]

      [carrier] = Enum.filter(invoke.children, &(is_map(&1) and &1.name == "param"))
      assert carrier.attribute_owners == []
    end

    test "the engine accepts what is emitted" do
      for config <- [@setup, Map.put(@setup, "assign_to", "onboarding.result")] do
        assert {:ok, _machine} = Statifier.compile(compile!(config).scxml)
      end
    end
  end

  describe "the publish-time checks (J4 and J5)" do
    # sabotage: removed the `chart != ""` guard from the compiler's
    # reference clause -> a `chart_from` block that carries an empty
    # `chart` records a reference to the empty id and this goes red
    # (verified)
    test "a chart_from block records no child reference" do
      assert compile!(@setup).interface.references == []
      assert compile!(Map.put(@setup, "chart", "")).interface.references == []
    end

    test "a path that names the document's own id raises no self-reference finding" do
      document =
        Document.new(
          Block.new("core.subchart", id: "blk_SETUP", config: %{"chart_from" => "bdoc_ONBOARD"}),
          id: "bdoc_ONBOARD"
        )

      assert {:ok, _compiled} = Compiler.compile(document, Palette.core())
    end
  end

  describe "config_schema/1 (J1)" do
    # sabotage: dropped the chart_from declaration from `config_schema/1` ->
    # the keys read chart, outcomes, assign_to, params and this goes red
    test "lists chart_from after chart, as a path field, for every config" do
      for config <- [%{}, @setup, %{"chart" => "bdoc_CATALOGUE_SYNC"}] do
        fields = Subchart.config_schema(config)

        assert Enum.map(fields, & &1.key) == [
                 "chart",
                 "chart_from",
                 "outcomes",
                 "assign_to",
                 "params"
               ]

        assert %{type: {:path, %{}}, default: ""} = Enum.find(fields, &(&1.key == "chart_from"))
      end
    end

    # sabotage: restored `required?: true` on chart -> this goes red
    test "neither chart nor chart_from is required; validate_config/1 owns the one-of rule" do
      fields = Subchart.config_schema(%{})

      assert %{required?: false} = Enum.find(fields, &(&1.key == "chart"))
      assert %{required?: false} = Enum.find(fields, &(&1.key == "chart_from"))
    end

    test "a fresh block carries both keys empty, and validate_config/1 asks for one" do
      {:ok, block} = Palette.new_block(Palette.core(), "core.subchart")

      assert %{"chart" => "", "chart_from" => ""} = block.config

      assert {:error, [{"chart", _names_the_document}]} =
               Subchart.validate_config(block.config)
    end
  end

  describe "sentence/1" do
    # sabotage: had `sentence/1` read chart only -> a chart_from block reads
    # "Run a chart and wait" and this goes red
    test "a chart_from block names the path its child is read from" do
      assert Subchart.sentence(@setup) ==
               "Run the chart named at onboarding.setup_document and wait"

      assert Subchart.sentence(%{"chart" => "", "chart_from" => " onboarding.next "}) ==
               "Run the chart named at onboarding.next and wait"
    end

    # sabotage: let chart_from win over a non-empty chart -> the literal
    # line changes for a config carrying both and this goes red
    test "a chart block reads as before, and a chart holding a value wins" do
      assert Subchart.sentence(%{"chart" => "bdoc_CATALOGUE_SYNC", "chart_from" => ""}) ==
               "Run bdoc_CATALOGUE_SYNC and wait"

      assert Subchart.sentence(%{"chart" => "bdoc_CATALOGUE_SYNC", "chart_from" => "a.b"}) ==
               "Run bdoc_CATALOGUE_SYNC and wait"

      for config <- [%{"chart" => " ", "chart_from" => ""}, %{"chart_from" => 42}] do
        assert Subchart.sentence(config) == "Run a chart and wait"
      end
    end
  end

  defp compile!(config) do
    document =
      Document.new(Block.new("core.subchart", id: "blk_SETUP", config: config),
        id: "bdoc_ONBOARD"
      )

    {:ok, compiled} = Compiler.compile(document, Palette.core())
    compiled
  end

  defp context, do: Context.new("blk_SETUP", "bdoc_ONBOARD")

  defp find_element(%{name: name} = element, name), do: element

  defp find_element(%{children: children}, name) do
    Enum.find_value(children, fn
      %{} = child -> find_element(child, name)
      _other -> nil
    end)
  end

  defp find_element(_other, _name), do: nil
end
