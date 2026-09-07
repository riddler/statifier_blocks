# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. There is no pure half of this
# one to place outside the guard - what it asserts is markup.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.DebounceTest do
    @moduledoc """
    The `debounce` attr on `ConfigForm.config_form/1` and `Field.field/1`.

    The form posts `phx-change` on every change event, so a host that
    persists what it decodes writes once per keystroke. The controls are
    this package's markup, so a host cannot reach them to say otherwise -
    which is what the attr is for, and why the interesting claim is
    coverage: not that *an* input carries the value, but that **no** control
    the form draws is missing it. A control that quietly kept posting per
    keystroke would be the whole bug, and it would be invisible in a test
    that named one field.

    So the block type below declares one field of every type in ADR-0002
    decision 7's closed set, the document carries a capture map, and the
    assertions scan every opening `<input>`, `<select>` and `<textarea>` tag
    in the rendered form rather than a chosen few. The `:path` and
    `:expression` fields are rendered **with** a host candidate list as well
    as without, because those two route through a different control when a
    host offered one (sb-uw3a), which is exactly the kind of second input a
    per-field assertion would walk past.

    One control is deliberately outside the claim: an `:expression` field
    renders through ADR-0005 decision 9's `expression_component` seam, and
    when `statifier_ui` resolves the input the author types into is that
    package's markup rather than this one's. This component cannot write an
    attribute onto markup it does not render, so the scans below run with
    the seam unresolved - the same `NoSuchModule` shim
    `StatifierBlocks.Editor.ExpressionComponentTest` uses - and the seam
    case gets a test of its own that says plainly what a host does and does
    not get there.

    The other half is the default. `nil` renders no attribute at all, and
    what proves it is not a `refute` but a comparison: the markup a caller
    passing nothing gets is the markup a caller passing a value gets with
    the attribute deleted, byte for byte.
    """

    use StatifierBlocks.EditorLiveCase

    alias StatifierBlocks.Editor.{ConfigForm, Field}
    alias StatifierBlocks.ViewModel

    defmodule EveryControl do
      @moduledoc "One field of every type in the closed set, so nothing is missed."

      @behaviour StatifierBlocks.BlockType

      @impl true
      def current_version, do: 1

      @impl true
      def slots(_config), do: []

      @impl true
      def config_schema(_config) do
        [
          decl("name", :string, "Name"),
          decl("attempts", :integer, "Attempts"),
          decl("required", :boolean, "Required"),
          decl("mode", {:select, [{"fast", "Fast"}, {"careful", "Careful"}]}, "Mode"),
          decl("guard", :expression, "Only when"),
          decl("wait", :duration, "Wait"),
          decl("tags", {:list, :string}, "Tags"),
          decl("flags", {:list, :boolean}, "Flags"),
          decl("account", {:path, %{}}, "Account"),
          decl("summary", {:type_expr, %{}}, "Each answer is a")
        ]
      end

      defp decl(key, type, label),
        do: %{key: key, type: type, label: label, required?: false, default: ""}

      @impl true
      def validate_config(_config), do: :ok

      @impl true
      def io(_config), do: %{kinds: [:step]}

      @impl true
      def palette_entry, do: %{label: "Every control"}

      @impl true
      def emit(%StatifierBlocks.Block{id: id}, _context), do: {:error, {:not_implemented, id}}
    end

    @config %{
      "name" => "Authorize",
      "attempts" => 2,
      "required" => true,
      "mode" => "fast",
      "guard" => "amount_minor > 0",
      "wait" => "1h",
      "tags" => ["card", "retry"],
      "flags" => [true],
      "account" => "order.account_id",
      "summary" => [%{"name" => "amount_minor", "type" => "integer", "required?" => true}]
    }

    @capture_pairs [{"order.reference", "reference"}]

    defp every_node do
      document =
        Document.new(
          Block.new("core.sequence",
            id: "blk_ROOT",
            slots: %{"body" => [Block.new("myapp.every", id: "blk_EVERY", config: @config)]}
          ),
          id: "bdoc_debounce"
        )

      palette = Palette.new(Elixir.Map.put(Palette.core_types(), "myapp.every", EveryControl))

      document
      |> ViewModel.build(palette, [])
      |> Elixir.Map.fetch!(:root)
      |> find_node("blk_EVERY")
    end

    defp find_node(%ViewModel.Node{block_id: id} = node, id), do: node

    defp find_node(%ViewModel.Node{} = node, id) do
      node.slots |> Enum.flat_map(& &1.children) |> Enum.find_value(&find_node(&1, id))
    end

    # Every field this host offers a candidate list for, in both spellings:
    # a closed list on the `:string`, an open one on the `:expression`, and a
    # closed one on the `{:path, opts}` - the two spellings crossed with the
    # two types that draw a suggestion control rather than the control their
    # type alone would draw.
    @field_candidates %{
      {"myapp.every", "name"} => [{"Authorize", "Authorize"}, {"Capture", "Capture"}],
      {"myapp.every", "guard"} => {:open, [{"amount_minor > 0", "Any amount"}]},
      {"myapp.every", "account"} => [{"order.account_id", "The order's account"}]
    }

    defp form(opts) do
      render_component(
        &ConfigForm.config_form/1,
        [
          node: every_node(),
          target: "#editor",
          capture_pairs: @capture_pairs,
          capture_sources: ["reference", "amount_minor"]
        ] ++ opts
      )
    end

    # Every opening form-control tag in the markup, as text. A regex rather
    # than a parser on purpose: what is being asserted is the attribute a
    # browser will read off each tag, and the tag text is what carries it.
    defp control_tags(html) do
      ~r/<(?:input|select|textarea)\b[^>]*>/
      |> Regex.scan(html)
      |> Enum.map(&hd/1)
    end

    defp without_debounce(tags), do: Enum.reject(tags, &String.contains?(&1, "phx-debounce="))

    # The `expression_component` seam, unresolved: `:expression` falls to the
    # plain source input this package renders itself, which is the control the
    # coverage claim is about. The shape is
    # `StatifierBlocks.Editor.ExpressionComponentTest`'s.
    defp without_statifier_ui(fun) do
      previous = Application.get_env(:statifier_blocks, :expression_component_module)
      Application.put_env(:statifier_blocks, :expression_component_module, NoSuchModule)

      try do
        fun.()
      after
        if previous do
          Application.put_env(:statifier_blocks, :expression_component_module, previous)
        else
          Application.delete_env(:statifier_blocks, :expression_component_module)
        end
      end
    end

    describe "every control a form draws" do
      # Sabotage: dropped `phx-debounce={@debounce}` from `Field.control/1`'s
      # last clause - the fall-through text input alone - and this goes red
      # naming that one tag, together with the `:blur` scan below (verified).
      # A test written against a single named field stays green through that
      # mutation, which is why the assertion here is a scan.
      test "carries the attr when the form is given one" do
        tags = without_statifier_ui(fn -> control_tags(form(debounce: 300)) end)

        assert tags != []
        assert without_debounce(tags) == []
        assert Enum.all?(tags, &String.contains?(&1, ~s(phx-debounce="300")))
      end

      # sb-uw3a's residue, and the reason this file exists as a scan: a
      # `:path` or an `:expression` a host offered candidates for renders
      # through `suggestion_control/4`, which draws its OWN input. A debounce
      # threaded onto the clauses that were there before that control existed
      # would miss both of these and nothing else would say so.
      #
      # Sabotage: dropped the attr from `suggestion_control/4` alone - red
      # here and on the seam test below, which is the other assertion that
      # feeds a candidate list; green everywhere else in this file
      # (verified).
      test "carries it on the suggestion controls a host's candidate list draws" do
        tags =
          without_statifier_ui(fn ->
            control_tags(form(debounce: 300, field_candidates: @field_candidates))
          end)

        assert without_debounce(tags) == []

        # The two suggestion controls themselves, named: an input bound to a
        # `<datalist>` of the offered values, on both types.
        for key <- ["guard", "account"] do
          assert Enum.any?(tags, fn tag ->
                   String.contains?(tag, ~s(id="sb-field-#{key}")) and
                     String.contains?(tag, ~s(list="sb-field-#{key}-candidates")) and
                     String.contains?(tag, ~s(phx-debounce="300"))
                 end)
        end

        # And the `<select>` a closed list draws on a `:string`.
        assert Enum.any?(tags, fn tag ->
                 String.starts_with?(tag, "<select") and
                   String.contains?(tag, ~s(id="sb-field-name")) and
                   String.contains?(tag, ~s(phx-debounce="300"))
               end)
      end

      # The capture rows are drawn from config the editor holds rather than
      # from a `config_schema/1` declaration, so they are reached by their own
      # pass-through and would be missed by one that only walked the fields.
      #
      # Sabotage: dropped the attr from `capture_rows/1`'s two inputs - red
      # here and on every other scan in this file, because the rows are on
      # every form this test draws (5 failures, verified).
      test "carries it on the capture rows" do
        tags = without_statifier_ui(fn -> control_tags(form(debounce: 300)) end)

        for which <- ["target", "source"] do
          assert Enum.any?(tags, fn tag ->
                   String.contains?(tag, ~s(sb-capture__#{which})) and
                     String.contains?(tag, ~s(phx-debounce="300"))
                 end)
        end
      end

      # `:blur` is LiveView's own spelling for "post when the control loses
      # focus", and it is written through unchanged rather than being
      # normalised into a number this component would have had to invent.
      test "writes :blur through as LiveView spells it" do
        tags = without_statifier_ui(fn -> control_tags(form(debounce: :blur)) end)

        assert without_debounce(tags) == []
        assert Enum.all?(tags, &String.contains?(&1, ~s(phx-debounce="blur")))
      end
    end

    describe "a caller that passes nothing" do
      # The default is not "300ms because that is LiveView's default": it is
      # NO attribute, which is the behaviour every host mounted on this
      # package already has. A package that started debouncing on its own
      # would change the event stream under a host that never asked.
      #
      # Sabotage: gave the attr `default: 300` on both components - red here
      # and on the field-level assertion below, and on nothing else, because
      # the only thing that changes is the markup a caller who said nothing
      # gets (verified).
      test "renders markup identical to the pre-attr markup, byte for byte" do
        plain = without_statifier_ui(fn -> form([]) end)
        debounced = without_statifier_ui(fn -> form(debounce: 300) end)

        refute plain =~ "phx-debounce"
        assert String.replace(debounced, ~s( phx-debounce="300"), "") == plain
      end

      # Same claim one level down, where the attr is declared: a host that
      # renders a field on its own gets what it rendered before.
      test "renders a field on its own unchanged" do
        field = %ViewModel.Field{
          key: "name",
          label: "Name",
          type: :string,
          value: "Authorize",
          default: "",
          required?: false,
          findings: []
        }

        plain =
          without_statifier_ui(fn ->
            render_component(&Field.field/1, field: field, target: "#editor")
          end)

        debounced =
          without_statifier_ui(fn ->
            render_component(&Field.field/1, field: field, target: "#editor", debounce: 300)
          end)

        refute plain =~ "phx-debounce"
        assert String.replace(debounced, ~s( phx-debounce="300"), "") == plain
      end
    end

    describe "the expression_component seam" do
      # The boundary, said plainly rather than left for a host to discover.
      # With `statifier_ui` resolved, an `:expression` field's control is that
      # package's markup: this component hands the seam the assigns ADR-0005
      # decision 9 names and renders whatever comes back, so there is no tag
      # of its own to write the attribute onto. Every OTHER control on the
      # same form still carries it, which is the half a host can rely on.
      #
      # Sabotage: added a `debounce` key to the seam's assigns map - all 8
      # tests stayed green (verified), which is the point rather than a gap:
      # a key the component behind the seam does not read changes no markup
      # and debounces nothing. Only that package can close this, so the key
      # is not added - an unread key would read as a promise this side
      # cannot keep.
      test "leaves the seam's own controls alone, and every other control carries it" do
        tags = control_tags(form(debounce: 300, field_candidates: @field_candidates))

        seam = Enum.filter(tags, &String.contains?(&1, "statifier-ui-expression"))
        ours = tags -- seam

        assert seam != []
        assert Enum.all?(seam, &(not String.contains?(&1, "phx-debounce")))
        assert without_debounce(ours) == []
      end
    end

    describe "a read-only form" do
      # A read-only form draws no controls at all (ADR-0005's 2026-09-07
      # profile amendment, `read_only?` clause 3), so there is nothing for a
      # debounce to sit on and nothing that posts to debounce. Asserted so
      # that a later change which gives the readonly branch a control has to
      # come past this line.
      test "draws no control for the attr to reach" do
        html =
          render_component(&ConfigForm.config_form/1,
            node: every_node(),
            target: "#editor",
            read_only: true,
            debounce: 300
          )

        assert control_tags(html) == []
        refute html =~ "phx-debounce"
      end
    end
  end
end
