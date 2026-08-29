defmodule StatifierBlocks.Compiler.SensitivePathsTest do
  @moduledoc """
  The secrets rule as a compile-time refusal: ADR-0002's accepted
  2026-08-29 amendment "decision 7, an optional `sensitive?` key, and the
  secrets rule behind it".

  Credit-card processing throughout, which is the record's own worked
  example: `card.last_four` and `card.token_id` are declared and not
  sensitive, `card.number` and `processor.api_key` are declared
  `sensitive?: true`, and the correct document reads the token and lets
  the handler exchange it at effect time.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Compiler, Document, Emission, Finding, Palette}
  alias StatifierBlocks.Compiler.SensitivePaths

  doctest StatifierBlocks.Compiler.SensitivePaths

  @datamodel %{
    declared: ["card.last_four", "card.token_id", "card.number", "processor.api_key"],
    sensitive: ["card.number", "processor.api_key"]
  }

  describe "the refused positions (the record's four)" do
    # sabotage: dropped "expr" from the datamodel-position criterion (left
    # the `*expr` suffix rule matching nothing by making it an equality on
    # "eventexpr") -> the param read compiles and this goes red (verified)
    test "a core.invoke param reading the whole sensitive path is refused" do
      block =
        invoke(%{
          "invoke_type" => "myapp:capture",
          "params" => "pan=card.number\namount=order.amount"
        })

      assert [finding] = refuse(block)
      assert finding.block_id == "blk_INV"
      assert finding.config_key == "params"
      assert finding.severity == :error
      assert finding.fault == :author
      assert finding.code == :sensitive_path_read
      assert finding.reason == {:sensitive_path_read, "card.number"}
      assert finding.message =~ ~s("card.number")
      assert finding.message =~ "traces, telemetry, job payloads"
    end

    # sabotage: dropped the prefix arm of `match/2`, keeping only the exact
    # and under-the-path arms -> reading `card` compiles and this goes red
    # (verified). A prefix drags the sensitive leaf along with it, so a
    # prefix read is the same leak spelled shorter.
    test "a core.invoke param reading a prefix of the sensitive path is refused" do
      assert [finding] =
               refuse(invoke(%{"invoke_type" => "myapp:capture", "params" => "c=card"}))

      assert finding.reason == {:sensitive_path_read, "card.number"}
      assert finding.message =~ ~s("card")
      assert finding.message =~ ~s("card.number")
      assert finding.message =~ "spelled shorter"
    end

    # sabotage: dropped "location" from the criterion -> the write target
    # compiles and this goes red (verified)
    test "a core.assign target is refused, anchored on the path field" do
      block =
        Block.new("core.assign",
          id: "blk_ASN",
          config: %{
            "path" => "card.number",
            "value" => "42350"
          }
        )

      assert [finding] = refuse(block)
      assert finding.block_id == "blk_ASN"
      assert finding.config_key == "path"
      assert finding.message =~ "location"
    end

    # sabotage: matched only the `location` attribute and ignored `expr` on
    # <assign> -> reading a secret out into another path compiles and this
    # goes red (verified). Either direction leaks: writing spreads it,
    # reading publishes it.
    test "a core.assign source is refused, anchored on the value field" do
      block =
        Block.new("core.assign",
          id: "blk_ASN",
          config: %{
            "path" => "audit.pan",
            "value" => "card.number"
          }
        )

      assert [finding] = refuse(block)
      assert finding.config_key == "value"
      assert finding.reason == {:sensitive_path_read, "card.number"}
    end

    # sabotage: dropped "cond" from the criterion -> the arm predicate
    # compiles and this goes red (verified)
    test "a core.branch arm predicate is refused, anchored on the arm key" do
      block =
        Block.new("core.branch",
          id: "blk_BR",
          config: %{"arms" => [%{"slot" => "arm_present", "cond" => "processor.api_key != ''"}]},
          slots: %{"arm_present" => [captured()]}
        )

      assert [finding] = refuse(block)
      assert finding.block_id == "blk_BR"
      assert finding.config_key == "arm_present"
      assert finding.reason == {:sensitive_path_read, "processor.api_key"}
      assert finding.message =~ "cond"
    end
  end

  describe "core.invoke's assign_to, classified" do
    # sabotage: special-cased "assign_to" out of the walk on the argument
    # that it names a result rather than a read -> a document banking the
    # handler's answer over the secret's own subtree compiles and this goes
    # red (verified).
    #
    # The classification the record's reviewer asked for: `assign_to` emits
    # <assign expr="_event.data" location="authorization"/>, and `location`
    # is a datamodel WRITE target - the exact analogue of core.assign's
    # target, on the refused side, for the record's own core.assign reason
    # ("either direction"). Nothing in the pass distinguishes the two.
    test "assign_to is a datamodel write target and is refused like core.assign's target" do
      assert [finding] =
               refuse(invoke(%{"invoke_type" => "myapp:capture", "assign_to" => "card"}))

      assert finding.config_key == "assign_to"
      assert finding.reason == {:sensitive_path_read, "card.number"}
      assert finding.message =~ "location"

      target =
        Block.new("core.assign", id: "blk_ASN", config: %{"path" => "card", "value" => "1"})

      assert [analogue] = refuse(target)
      assert analogue.severity == finding.severity
      assert analogue.fault == finding.fault
      assert analogue.code == finding.code
    end
  end

  describe "no datamodel supplied, nothing produced (ADR-0005 11f)" do
    # sabotage: made `check/2` treat an absent option as "every path is
    # sensitive" -> every document with a param stops compiling and this
    # goes red (verified). Absence is not unknown-ness.
    test "a document that would be refused compiles when no datamodel is supplied" do
      block = invoke(%{"invoke_type" => "myapp:capture", "params" => "pan=card.number"})

      assert {:ok, _compiled} = compile(block, [])
      assert {:ok, _compiled} = compile(block, datamodel: nil)
    end

    # sabotage: read the `declared` set instead of `sensitive` -> a host
    # that declared paths and annotated none refuses every read of them and
    # this goes red (verified)
    test "a datamodel that declares paths but annotates none produces nothing" do
      block = invoke(%{"invoke_type" => "myapp:capture", "params" => "pan=card.number"})

      assert {:ok, _compiled} =
               compile(block, datamodel: %{declared: ["card.number", "card.token_id"]})

      assert {:ok, _compiled} = compile(block, datamodel: ["card.number"])
    end
  end

  describe "what is not refused" do
    # sabotage: matched a sensitive path by shared prefix without the dot
    # boundary (String.starts_with?/2 on the bare strings) -> `card.token_id`
    # is read as a `card.t...` neighbour of `card.number`, the prescribed
    # identifier pattern is refused, and this goes red (verified)
    test "the identifier pattern the rule prescribes is not a read of a secret" do
      block =
        invoke(%{
          "invoke_type" => "myapp:capture",
          "params" => "token=card.token_id\nlast_four=card.last_four"
        })

      assert {:ok, _compiled} = compile(block, datamodel: @datamodel)
    end

    # sabotage: stopped stripping quoted spans before tokenizing -> a
    # core.assign storing the literal text "card.number" is refused as a
    # read of it and this goes red (verified). `value` holds source text,
    # quotes included.
    test "a quoted literal that spells a sensitive path is not a read" do
      block =
        Block.new("core.assign",
          id: "blk_ASN",
          config: %{"path" => "audit.note", "value" => ~s("card.number")}
        )

      assert {:ok, _compiled} = compile(block, datamodel: @datamodel)
    end

    # sabotage: made `datamodel_position?/1` return true for every
    # attribute -> the invoke type, which merely contains no path at all
    # but is literal chart text either way, becomes a checked position and
    # a `type` attribute spelling a declared path would be refused; the
    # criterion assertions below go red (verified)
    test "only attributes the chart evaluates against the datamodel are positions" do
      assert SensitivePaths.datamodel_position?("expr")
      assert SensitivePaths.datamodel_position?("cond")
      assert SensitivePaths.datamodel_position?("location")
      assert SensitivePaths.datamodel_position?("namelist")
      assert SensitivePaths.datamodel_position?("idlocation")
      assert SensitivePaths.datamodel_position?("eventexpr")
      assert SensitivePaths.datamodel_position?("delayexpr")

      refute SensitivePaths.datamodel_position?("event")
      refute SensitivePaths.datamodel_position?("type")
      refute SensitivePaths.datamodel_position?("name")
      refute SensitivePaths.datamodel_position?("id")
      refute SensitivePaths.datamodel_position?("target")
      refute SensitivePaths.datamodel_position?("delay")
    end
  end

  describe "the criterion, not a list of block types" do
    # sabotage: replaced the criterion with a lookup of the four core types
    # the record names -> this element, which belongs to no shipped type,
    # is not checked and this goes red (verified).
    #
    # `core.send`'s payload is one of the record's four refused positions
    # and its vocabulary row has not landed. The clause binds on arrival
    # with no edit here, which is what this asserts: an element carrying an
    # `expr` is checked without the pass having heard of the type that
    # wrote it.
    test "an unknown type's expr-bearing element is refused with no edit to this pass" do
      emission =
        "content"
        |> Emission.element([{"expr", "processor.api_key"}])
        |> owned("blk_FUTURE", "payload")

      assert [finding] = SensitivePaths.check(emission, @datamodel)
      assert finding.block_id == "blk_FUTURE"
      assert finding.config_key == "payload"
      assert finding.reason == {:sensitive_path_read, "processor.api_key"}
    end

    # sabotage: read only the element owner's config key and ignored
    # `attribute_owners` -> an element whose two attributes came from two
    # different fields anchors both findings on the same key and this goes
    # red (verified)
    test "the attribute-level config key wins over the element's own" do
      emission =
        "assign"
        |> Emission.element([{"expr", "card.number"}, {"location", "processor.api_key"}])
        |> owned("blk_X", "whole_element")
        |> Emission.attribute_from_config("expr", "source")
        |> Emission.attribute_from_config("location", "target")

      assert [source, target] = SensitivePaths.check(emission, @datamodel)
      assert source.config_key == "source"
      assert target.config_key == "target"
    end
  end

  describe "datamodel/1" do
    # sabotage: dropped the non-binary filter -> a nil or an atom in a
    # supplied list becomes a "path" that matches nothing but sits in the
    # set, and the size assertions go red (verified)
    test "normalizes the shapes a host may supply, and keeps only real paths" do
      assert %{declared: declared, sensitive: sensitive} =
               SensitivePaths.datamodel(%{
                 declared: ["card.number", "", nil, :atom],
                 sensitive: MapSet.new(["card.number"])
               })

      assert MapSet.to_list(declared) == ["card.number"]
      assert MapSet.to_list(sensitive) == ["card.number"]

      assert SensitivePaths.datamodel(nil) == %{declared: MapSet.new(), sensitive: MapSet.new()}
      assert MapSet.to_list(SensitivePaths.datamodel(["a.b"]).declared) == ["a.b"]
      assert SensitivePaths.datamodel("nonsense").declared == MapSet.new()
    end

    # sabotage: intersected `sensitive` with `declared` -> a host that
    # annotated a path without repeating it in the declared set silently
    # loses the refusal and this goes red (verified)
    test "a sensitive path absent from the declared set is still sensitive" do
      block = invoke(%{"invoke_type" => "myapp:capture", "params" => "pan=card.number"})

      assert [_finding] =
               compile(block, datamodel: %{declared: [], sensitive: ["card.number"]})
               |> refusal()
    end
  end

  describe "presentation (ADR-0005 decision 11)" do
    # sabotage: passed no `source:` override -> the adapter's default rule
    # refuses an :error at the :emit stage with {:no_presentation_source,
    # _} and this goes red (verified). The default derivation cannot reach
    # {:lint, :error}; `opts[:source]` is the documented seam and this is
    # the wiring a host uses.
    test "adapts to an anchored :lint finding at :error severity" do
      block = invoke(%{"invoke_type" => "myapp:capture", "params" => "pan=card.number"})

      assert {[presented], []} =
               block
               |> refuse()
               |> Finding.from_compiler_all(source: :lint)

      assert presented.anchor == {:config, "blk_INV", "params"}
      assert presented.source == :lint
      assert presented.severity == :error
      assert presented.message =~ ~s("card.number")
    end

    # sabotage: none needed in lib - this asserts the seam the moduledoc
    # names, and it goes red if `StatifierBlocks.Finding`'s default
    # derivation is ever widened to reach {:lint, :error} without this
    # module's docs being updated to match (verified by widening rule 2 to
    # map the :emit stage to :lint)
    test "the default derivation refuses these, which is why the override is passed" do
      block = invoke(%{"invoke_type" => "myapp:capture", "params" => "pan=card.number"})

      assert {[], [{_finding, {:no_presentation_source, _same}}]} =
               block
               |> refuse()
               |> Finding.from_compiler_all()
    end
  end

  # -- helpers ---------------------------------------------------------------

  defp invoke(config), do: Block.new("core.invoke", id: "blk_INV", config: config)

  defp captured,
    do:
      Block.new("core.assign",
        id: "blk_CAP",
        config: %{"path" => "card.last_four", "value" => "\"1234\""}
      )

  defp compile(root, opts),
    do: Compiler.compile(Document.new(root, id: "bdoc_SEC"), Palette.core(), opts)

  defp refuse(root) do
    root
    |> compile(datamodel: @datamodel)
    |> refusal()
  end

  defp refusal({:error, findings}), do: findings

  defp owned(emission, block_id, config_key) do
    %{emission | owner: %{block_id: block_id, role: nil, config_key: config_key}}
  end
end
