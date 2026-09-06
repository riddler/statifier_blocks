defmodule StatifierBlocks.Core.MapTest do
  @moduledoc """
  What `core.map` means and what it compiles to: ADR-0009's decisions 2
  (the type name), 3 (one `<invoke>` of a constant handler type, carrying
  the list's *path*), 4 (the declaration surface, and the two fixed
  outcomes), 5 (one write, at the invocation's completion) and 6 (the two
  aggregation policies, with everything else refused).

  Two things this file deliberately does **not** assert, because they are
  not this package's:

    * anything about N. The compiler never sees the list, so there is no
      count to bound and no bound to check (campaign-031 ruling `D31-9`,
      ADR-0009's 2026-09-05 Tier A note). A test here that pinned a cap
      would pin a claim the type does not make.
    * what the empty fan-out answers. `sb-kha0` owns that question, and a
      test asserting either reading would decide it by accident.

  The shape assertions every core type shares live in
  `conformance_test.exs`; nothing here repeats them.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Compiler, Document, Palette}
  alias StatifierBlocks.Core.{Map, Subchart}

  @lines %{
    "items" => "order.line_ids",
    "chart" => "bdoc_LINE",
    "item_as" => "line",
    "index_as" => "position",
    "collect" => "line_results",
    "on" => "all"
  }

  describe "validate_config/1 (ADR-0002 decision 7, ADR-0009 decision 4)" do
    # sabotage: made `items` optional - a fan-out with nothing to fan out
    # over validates, and this goes red (verified)
    test "items names the datamodel list, and is required" do
      assert Map.validate_config(@lines) == :ok

      assert {:error, findings} = Map.validate_config(%{"chart" => "bdoc_LINE"})
      assert {"items", message} = List.keyfind(findings, "items", 0)
      assert message =~ "datamodel list"

      assert {:error, findings} =
               Map.validate_config(%{"items" => "order.line ids", "chart" => "bdoc_LINE"})

      assert List.keyfind(findings, "items", 0)
    end

    # sabotage: made `chart` optional - an invocation with no `src` at all
    # validates and this goes red (verified)
    test "chart names one document, and is required" do
      assert {:error, findings} = Map.validate_config(%{"items" => "order.line_ids"})
      assert {"chart", message} = List.keyfind(findings, "chart", 0)
      assert message =~ "names the document to run"

      assert {:error, findings} =
               Map.validate_config(%{"items" => "order.line_ids", "chart" => "a b"})

      assert List.keyfind(findings, "chart", 0)
    end

    # Both values are emitted inside a quoted expression literal, because
    # the handler evaluates the path rather than the parent (decision 3),
    # so a value carrying a quote would close the literal early.
    #
    # sabotage: dropped the quote clause from `reference?/1` - the emitted
    # `<param expr="'order.line_ids'...">` becomes an expression the author
    # never wrote, and this goes red on both assertions (verified)
    test "neither items nor chart may carry a single quote" do
      assert {:error, findings} =
               Map.validate_config(%{"items" => "order.line_ids' or x", "chart" => "bdoc_LINE"})

      assert List.keyfind(findings, "items", 0)

      assert {:error, findings} =
               Map.validate_config(%{"items" => "order.line_ids", "chart" => "bdoc'"})

      assert List.keyfind(findings, "chart", 0)
    end

    # `collect` keeps the one grammar `assign_to` already has, refused with
    # the same wording, because an author meeting it on a subchart and on a
    # map is meeting one field (decision 4).
    #
    # sabotage: loosened the check to any non-empty string - the dotted
    # value validates and the refusal assertion goes red (verified)
    test "collect is optional, and a bare lowercase identifier when present" do
      assert Map.validate_config(%{"items" => "order.line_ids", "chart" => "bdoc_LINE"}) == :ok

      assert Map.validate_config(%{
               "items" => "order.line_ids",
               "chart" => "bdoc_LINE",
               "collect" => ""
             }) == :ok

      assert {:error, findings} =
               Map.validate_config(%{
                 "items" => "order.line_ids",
                 "chart" => "bdoc_LINE",
                 "collect" => "order.results"
               })

      assert {"collect", message} = List.keyfind(findings, "collect", 0)
      assert message =~ "bare lowercase identifier"
    end

    # Decision 6: `quorum` is reserved by refusing everything outside the
    # two permitted values, so no host can establish a private meaning for
    # it before its own walk happens.
    #
    # sabotage: accepted any binary for `on` - "quorum" validates, the word
    # stops being reserved, and this goes red (verified)
    test "on takes all or first_error, and refuses every other word" do
      for value <- ["all", "first_error"] do
        assert Map.validate_config(%{@lines | "on" => value}) == :ok
      end

      for value <- ["quorum", "any", "ALL", ""] do
        assert {:error, findings} = Map.validate_config(%{@lines | "on" => value})
        assert {"on", message} = List.keyfind(findings, "on", 0)
        assert message =~ "first_error"
      end
    end

    # `core.parallel`'s G7a shape: an absent key reads as the default
    # everywhere, and a stored `null` is not an absent key (ADR-0001
    # decision 6).
    #
    # sabotage: read the key with `Map.get(config, "on") || "all"` - the
    # stored `null` reads as "all" and the second assertion goes red
    # (verified)
    test "an absent on reads as all; a stored null does not" do
      assert Map.validate_config(%{"items" => "order.line_ids", "chart" => "bdoc_LINE"}) == :ok

      assert {:error, findings} = Map.validate_config(%{@lines | "on" => nil})
      assert List.keyfind(findings, "on", 0)
    end

    # ADR-0011 decision 11's two names, on `on`'s read-through-default
    # shape rather than `core.foreach`'s required-key one: a `core.map`
    # stored before either key existed reads as `item` and validates
    # exactly as it did, so nothing has an older shape to migrate from.
    #
    # sabotage: read `item_as` with `Map.get(config, "item_as")` - an
    # absent key becomes `nil`, every map authored before this field
    # existed stops validating, and the first assertion goes red
    # (verified)
    test "an absent item_as reads as item; an empty or null one does not" do
      assert Map.validate_config(%{"items" => "order.line_ids", "chart" => "bdoc_LINE"}) == :ok

      for value <- ["", nil, "Invitee", "line id"] do
        assert {:error, findings} = Map.validate_config(Elixir.Map.put(@lines, "item_as", value))
        assert {"item_as", message} = List.keyfind(findings, "item_as", 0)
        assert message =~ "bare lowercase identifier"
      end
    end

    # `core.foreach`'s optional-field idiom for the same key, and the one
    # cross-field check that survives the move: there is no root to
    # collide with here, but the handler binding the position over the
    # item is still two bindings and one name.
    #
    # sabotage: dropped `check_distinct/2` - a map naming both the same
    # validates, the child sees its position where its item should be,
    # and the last assertion goes red (verified)
    test "index_as is optional, an identifier when present, and never the item's name" do
      assert Map.validate_config(Elixir.Map.put(@lines, "index_as", "")) == :ok
      assert Map.validate_config(Elixir.Map.put(@lines, "index_as", "position")) == :ok

      assert {:error, findings} = Map.validate_config(Elixir.Map.put(@lines, "index_as", "P 1"))
      assert {"index_as", message} = List.keyfind(findings, "index_as", 0)
      assert message =~ "bare lowercase identifier"

      assert {:error, findings} =
               Map.validate_config(%{@lines | "item_as" => "line", "index_as" => "line"})

      assert {"index_as", collision} = List.keyfind(findings, "index_as", 0)
      assert collision =~ "cannot share one name"
    end
  end

  describe "the declaration surface (ADR-0009 decision 4)" do
    # sabotage: reordered the fields - the form an author reads no longer
    # opens on what the block runs over, and this goes red (verified)
    test "config_schema/1 declares exactly the six fields, in order" do
      assert Enum.map(Map.config_schema(@lines), & &1.key) ==
               ["items", "chart", "item_as", "index_as", "collect", "on"]
    end

    # ADR-0011 decision 11 keeps the two names with the defaults `item`
    # and `index`. The `item` half is this schema's, applied by
    # `validate_config/1` and `emit/2` when the config carries no name;
    # the `index` half is the *walk's*, applied inside a body, and a
    # `core.map` has no body (ADR-0009 decision 3), so the field's own
    # default is the empty string that means "the author named none".
    #
    # sabotage: gave `index_as` the default "index" - every map emits a
    # position name its author never asked for, and this goes red
    # (verified)
    test "item_as and index_as are plain identifier fields, not datamodel paths" do
      names = Enum.filter(Map.config_schema(@lines), &(&1.key in ["item_as", "index_as"]))

      assert [
               %{
                 key: "item_as",
                 type: :string,
                 label: "Call the item",
                 required?: true,
                 default: "item"
               },
               %{
                 key: "index_as",
                 type: :string,
                 label: "Call the position (optional)",
                 required?: false,
                 default: ""
               }
             ] = names

      # The editor generates both controls from these declarations alone -
      # one text control each, the first badged Required - and neither is
      # offered path candidates, because neither names a path in this
      # document.
      for field <- names, do: refute(StatifierBlocks.BlockType.datamodel_path?(field))
    end

    # sabotage: dropped the `writes` key back off `collect` (`{:path, %{}}`)
    # - the block after a `core.map` stops seeing a list and this goes red
    # (verified)
    test "items and collect are {:path, opts} fields, and collect declares what it writes" do
      opts = fn key ->
        %{type: {:path, opts}} = Map.config_schema(@lines) |> Enum.find(&(&1.key == key))
        opts
      end

      # `items` says where without saying what, which ADR-0011 decision 2
      # reads as writing `:unknown` there; `collect` carries decision 12's
      # type, and says nothing about an element of the list.
      assert opts.("items") == %{}
      assert opts.("collect") == %{writes: {:list, :unknown}}
    end

    # sabotage: same revert - `datamodel_path?/1` answers false for the
    # field, it is filtered out of the editor's path findings, and this
    # goes red (verified)
    test "exactly the two path fields read back through BlockType.datamodel_path?/1" do
      for field <- Map.config_schema(@lines) do
        assert StatifierBlocks.BlockType.datamodel_path?(field) ==
                 field.key in ["items", "collect"]
      end
    end

    # sabotage: added a third choice to the select - the reserved word is
    # offered in the editor before its walk happened, and this goes red
    # (verified)
    test "on is a select over the two permitted values, defaulting to all" do
      declaration = Map.config_schema(@lines) |> Enum.find(&(&1.key == "on"))

      assert %{type: {:select, choices}, required?: false, default: "all"} = declaration
      assert Enum.map(choices, &elem(&1, 0)) == ["all", "first_error"]
    end

    # sabotage: derived the outcomes from a config key - a fan-out starts
    # claiming it can route on what N children answered, which decision 4
    # refuses, and this goes red (verified)
    test "two outcomes and two slots, fixed, whatever the config says" do
      assert Map.outcomes(@lines) == [{"done", "Done"}, {"error", "Error"}]
      assert Map.outcomes(%{}) == Map.outcomes(@lines)

      assert Map.slots(@lines) == [
               {"on_done", :zero_or_one, "When the batch is done"},
               {"on_error", :zero_or_one, "If the batch fails"}
             ]

      assert %{kinds: [:step], produces: :unknown, slot_accepts: accepts} = Map.io(@lines)
      assert accepts == %{"on_done" => [:step], "on_error" => [:step]}
    end

    # ADR-0009 decision 2: the type name is engineer-facing and the palette
    # label is not.
    #
    # sabotage: labelled the entry "Map" - the palette says jargon where the
    # record says a sentence, and this goes red (verified)
    test "the palette entry says what the block does, in the author's words" do
      entry = Map.palette_entry()

      assert entry.label == "For every item, run a chart"
      assert entry.group == "Structure"
      assert entry.order == 16
      assert entry.slot_style == %{"on_error" => :failure}
      assert entry.description =~ "every item"
    end
  end

  describe "invoke_type/0 (ADR-0009 decision 3)" do
    # A host that wired a single-child subchart handler has not thereby
    # wired a fan-out handler, and a document that reached such a host
    # should fail to find a handler rather than start one child.
    #
    # sabotage: returned `Subchart.invoke_type()` - a map silently resolves
    # to the single-child handler and this goes red (verified)
    test "is a constant, and a different string from a subchart's" do
      assert Map.invoke_type() == "statifier_blocks:map"
      refute Map.invoke_type() == Subchart.invoke_type()
    end

    # sabotage: emitted the type through `typeexpr` - there is no literal
    # string for a host to compare against its registration, the compiled
    # set loses the entry, and this goes red (verified)
    test "the compiled chart publishes it for a host to compare at deploy time" do
      assert "statifier_blocks:map" in compile!(order()).invoke_types
    end
  end

  describe "emit/2 (ADR-0009 decisions 3 and 5)" do
    setup do
      %{scxml: compile!(order(fallout: true, receipt: true)).scxml}
    end

    # There is no mutation that makes the emitted bytes scale with N, and
    # that is the point of decision 3: the compiler never sees the list.
    # What this asserts is the invariant that makes it so - exactly one
    # `<invoke>`, carrying the block's own id (ADR-0004 C3) and the
    # document id as `src`.
    #
    # sabotage: dropped the explicit `id` attribute - `_event.invokeid` is
    # no longer a value the parent knows at compile time and this goes red
    # (verified)
    test "one <invoke>, with the block's own id and the document id as src", %{scxml: scxml} do
      assert scxml
             |> String.split("<invoke ")
             |> length() == 2

      assert scxml =~
               ~s(<invoke id="blk_LINES" src="bdoc_LINE" type="statifier_blocks:map">)
    end

    # Decision 3: the params carry the list's *path*, once, not the list
    # and not N copies of an item - which is what keeps ADR-0004 decision
    # 6's byte determinism intact.
    #
    # sabotage: emitted `items` as a bare expression rather than a quoted
    # literal - the parent evaluates the path and hands the handler a list
    # it was supposed to resolve itself, and this goes red (verified)
    test "the six params carry literals: the path, the chart, the names, the location, the policy",
         %{scxml: scxml} do
      assert scxml =~ ~s(<param expr="'order.line_ids'" name="items"/>)
      assert scxml =~ ~s(<param expr="'bdoc_LINE'" name="chart"/>)
      assert scxml =~ ~s(<param expr="'line'" name="item_as"/>)
      assert scxml =~ ~s(<param expr="'position'" name="index_as"/>)
      assert scxml =~ ~s(<param expr="'line_results'" name="collect"/>)
      assert scxml =~ ~s(<param expr="'all'" name="on"/>)
    end

    # ADR-0009 decision 3: what the child sees its item and its position
    # under travels in the param list, because the handler is what binds
    # them - one document away from anything this compile can check. So
    # the names are emitted, and nothing here declares a `<data>` root for
    # either, the way `core.foreach` does for the names it binds itself.
    #
    # sabotage: dropped the default from `emit/2`'s read of the key
    # (`Map.get(config, "item_as")`) - a map whose author never opened the
    # field reaches the handler with no name at all, and the first
    # assertion goes red (verified)
    test "an absent item_as still reaches the handler, as the default name" do
      scxml = compile!(order(names: %{})).scxml

      assert scxml =~ ~s(<param expr="'item'" name="item_as"/>)
      refute scxml =~ ~s(name="index_as")
      refute scxml =~ "<datamodel"
    end

    # RQ-031-4: the fan-out scheduler reads the aggregation policy off this
    # param, so the word has to reach it verbatim.
    #
    # sabotage: normalised the value ("first-error", say) - the runtime
    # refuses a word it does not know and this goes red (verified)
    test "first_error reaches the param verbatim" do
      scxml = compile!(order(on: "first_error")).scxml

      assert scxml =~ ~s(<param expr="'first_error'" name="on"/>)
    end

    # Decision 7 clause 3: a fan-out whose answers the parent does not need
    # declares no `collect` and accumulates nothing, and nothing else about
    # the block changes.
    #
    # sabotage: emitted `<param expr="''" name="collect"/>` for an absent
    # field - the handler reads an empty location name as a location, and
    # this goes red (verified)
    test "an absent collect emits neither the param nor the assign" do
      scxml = compile!(order(collect: nil)).scxml

      refute scxml =~ ~s(name="collect")
      refute scxml =~ "<assign"
      assert scxml =~ ~s(<param expr="'order.line_ids'" name="items"/>)
    end

    # Decision 5: the write happens once, at the invocation's completion,
    # on the success transition rather than in a `<finalize>`.
    #
    # sabotage: moved the `<assign>` into a `<finalize>` - it runs for every
    # event the invocation delivers, including the failure, and this goes
    # red (verified)
    test "the collected answer is written on the success transition", %{scxml: scxml} do
      assert scxml =~
               ~s(<transition event="done.invoke" target="s_blk_RECEIPT">) <>
                 ~s(<assign expr="_event.data" location="line_results"/></transition>)

      refute scxml =~ "<finalize"
    end

    # sabotage: pointed the failure transition at the error final rather
    # than at the slot's child - the on_error subtree never runs and this
    # goes red (verified)
    test "error.communication.invoke reaches the on_error subtree", %{scxml: scxml} do
      assert scxml =~ ~s(<transition event="error.communication.invoke" target="s_blk_FALLOUT"/>)

      assert scxml =~
               ~s(<transition event="done.state.s_blk_FALLOUT" ) <>
                 ~s(target="s_blk_LINES__o_error" type="internal"/>)
    end

    # sabotage: dropped the outcome finals - a parent wiring
    # `done.outcome.s_blk_LINES.done` never hears from the block and this
    # goes red (verified)
    test "one <final> per outcome, each raising its own completion event", %{scxml: scxml} do
      for outcome <- ["done", "error"] do
        assert scxml =~
                 ~s(<final id="s_blk_LINES__o_#{outcome}"><onentry>) <>
                   ~s(<raise event="done.outcome.s_blk_LINES.#{outcome}"/></onentry></final>)
      end
    end

    # sabotage: emitted the failure transition with both slots empty - it
    # targets a state nothing emitted, the engine refuses the compile, and
    # this goes red (verified)
    test "the whole thing is a chart the engine accepts", %{scxml: scxml} do
      assert {:ok, _machine} = Statifier.compile(scxml)
    end
  end

  describe "emit/2 with both slots empty" do
    setup do
      %{scxml: compile!(order()).scxml}
    end

    # sabotage: emitted the failure transition unconditionally - it targets
    # a state that was never emitted, the engine refuses the compile, and
    # this goes red (verified)
    test "emits no failure transition and no error final", %{scxml: scxml} do
      refute scxml =~ "error.communication.invoke"
      refute scxml =~ "s_blk_LINES__o_error"
      assert {:ok, _machine} = Statifier.compile(scxml)
    end

    # sabotage: routed an empty `on_done` slot at a state nothing emitted -
    # the engine refuses the compile and this goes red (verified)
    test "done.invoke routes straight to the done final", %{scxml: scxml} do
      assert scxml =~
               ~s(<transition event="done.invoke" target="s_blk_LINES__o_done">) <>
                 ~s(<assign expr="_event.data" location="line_results"/></transition>)
    end
  end

  describe "the seams a map inherits by emitting an ordinary <invoke src=...>" do
    # `StatifierBlocks.Compiler.SelfReference` classifies by SCXML's own
    # semantics rather than by block type, so a map naming the document it
    # sits in is refused with no edit there.
    #
    # sabotage: emitted the chart id as `srcexpr` - the pass has no id to
    # compare, the recursion compiles, and this goes red (verified)
    test "a map may not name the document it sits in" do
      block = Block.new("core.map", id: "blk_LINES", config: %{@lines | "chart" => "bdoc_ORDER"})

      assert {:error, findings} =
               Compiler.compile(Document.new(block, id: "bdoc_ORDER"), Palette.core())

      assert Enum.any?(findings, &match?({:self_reference, "bdoc_ORDER"}, &1.reason))
    end

    # sabotage: dropped the emitted type from the lint's reach - a host
    # that wired no fan-out handler is told nothing at the one moment it
    # holds both registries, and this goes red (verified)
    test "a host with no fan-out handler registered is warned, not refused" do
      {:ok, compiled} =
        Compiler.compile(Document.new(order(), id: "bdoc_ORDER"), Palette.core(),
          known_invoke_types: ["statifier_blocks:subchart"]
        )

      assert Enum.any?(compiled.warnings, fn finding ->
               finding.severity == :warning and
                 finding.reason == {:no_registered_invoke_handler, "statifier_blocks:map"}
             end)
    end
  end

  # One `core.map` over an order's line ids, optionally with a subtree on
  # each outcome. The two continuation subtrees are always-done containers,
  # so a test can watch a completion travel from the slot child to its
  # outcome without a second event.
  defp order(opts \\ []) do
    named =
      case Keyword.fetch(opts, :names) do
        {:ok, names} ->
          @lines |> Elixir.Map.drop(["item_as", "index_as"]) |> Elixir.Map.merge(names)

        :error ->
          @lines
      end

    config =
      case Keyword.fetch(opts, :collect) do
        {:ok, nil} ->
          %{named | "on" => Keyword.get(opts, :on, "all")} |> Elixir.Map.delete("collect")

        _otherwise ->
          %{named | "on" => Keyword.get(opts, :on, "all")}
      end

    slots =
      %{}
      |> put_slot("on_done", Keyword.get(opts, :receipt, false) && receipt())
      |> put_slot("on_error", Keyword.get(opts, :fallout, false) && fallout())

    Block.new("core.map", id: "blk_LINES", config: config, slots: slots)
  end

  defp put_slot(slots, _name, false), do: slots
  defp put_slot(slots, name, block), do: Elixir.Map.put(slots, name, [block])

  defp receipt, do: Block.new("core.sequence", id: "blk_RECEIPT")
  defp fallout, do: Block.new("core.sequence", id: "blk_FALLOUT")

  defp compile!(root) do
    {:ok, compiled} = Compiler.compile(Document.new(root, id: "bdoc_ORDER"), Palette.core())
    compiled
  end
end
