# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. The field type's own claims -
# what it stores, which arm a value is, and what the shared check refuses -
# are pure and live in `StatifierBlocks.TypeExprFieldTest`, deliberately
# outside this guard.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.TypeExprControlTest do
    @moduledoc """
    The `{:type_expr, opts}` control: ADR-0005 decision 9's row of
    2026-09-06, drawn in the **inspector's** Config tab, because a config
    field is about the selected block.

    What only exists once there is markup is the half here - that the
    document's declared type names reach a datalist the name arm's input is
    bound to, that the inline arm draws a member row per member with the
    control recursing on a member's own type, that a field admitting both
    arms draws a toggle and one admitting a single arm draws none, and that
    a value the control cannot read is drawn raw rather than blank.
    """

    use StatifierBlocks.EditorLiveCase

    @datamodel %{
      "version" => 1,
      "scopes" => [%{"scope" => "local", "label" => "This run", "entries" => []}],
      "types" => [
        %{
          "name" => "cards.settlement",
          "kind" => "record",
          "label" => "Settlement",
          "fields" => [%{"name" => "amount_minor", "type" => "integer", "required?" => true}]
        },
        %{
          "name" => "Settleable",
          "kind" => "shape",
          "label" => "Settleable",
          "fields" => [%{"name" => "amount_minor", "type" => "integer", "required?" => true}]
        }
      ]
    }

    @members [
      %{"name" => "amount_minor", "type" => "integer", "required?" => true},
      %{"name" => "note", "type" => "string"}
    ]

    defmodule Typed do
      @moduledoc "A block type whose one field is a type expression."

      @behaviour StatifierBlocks.BlockType

      @impl true
      def current_version, do: 1

      @impl true
      def slots(_config), do: []

      @impl true
      def config_schema(config) do
        [
          %{
            key: "summary",
            type: {:type_expr, arms(Map.get(config, "arms"))},
            label: "Each answer is a",
            required?: false,
            default: ""
          }
        ]
      end

      defp arms(names) when is_list(names),
        do: %{arms: Enum.map(names, &String.to_existing_atom/1)}

      defp arms(_absent), do: %{}

      @impl true
      def validate_config(_config), do: :ok

      @impl true
      def io(_config), do: %{kinds: [:step]}

      @impl true
      def palette_entry, do: %{label: "Typed"}

      @impl true
      def emit(%StatifierBlocks.Block{id: id}, _context), do: {:error, {:not_implemented, id}}
    end

    # The value the document holds for the field, off the `on_change` seam:
    # what the control renders is one question and what it stores is
    # another, and a gesture that draws right and stores wrong is exactly
    # the failure a rendering assertion cannot see.
    defp summary do
      assert_receive {:document, document}

      %StatifierBlocks.Block{config: config} =
        document.root.slots["body"] |> Enum.find(&(&1.id == "blk_TYP"))

      Elixir.Map.get(config, "summary")
    end

    defp view(conn, config) do
      document =
        Document.new(
          Block.new("core.sequence",
            id: "blk_ROOT",
            slots: %{"body" => [Block.new("myapp.typed", id: "blk_TYP", config: config)]}
          ),
          id: "bdoc_type_expr"
        )

      palette = Palette.new(Map.put(Palette.core_types(), "myapp.typed", Typed))

      {:ok, view, _html} =
        mount_editor(conn, document: document, palette: palette, datamodel: @datamodel)

      view
      |> element(~s([data-block-id="blk_TYP"] > .sb-node__chrome > .sb-node__label))
      |> render_click()

      view
    end

    describe "the name arm" do
      # Sabotage: fed the control `path_candidates` instead of
      # `type_candidates` - the datalist offers the document's paths rather
      # than its declared type names, which for this document is nothing at
      # all, and both assertions go red (verified).
      test "the declared type names reach the datalist the input is bound to", %{conn: conn} do
        view = view(conn, %{"summary" => "cards.settlement"})

        assert has_element?(view, ~s(.sb-field[data-field-type="type_expr"] input[list]))

        assert has_element?(
                 view,
                 ~s(datalist#sb-field-summary-types[data-type-candidates="2"])
               )

        assert has_element?(
                 view,
                 ~s(datalist#sb-field-summary-types option[value="cards.settlement"])
               )
      end

      # Sabotage: `type_expr_name_text/1` answering `""` for a value that is
      # neither arm - the bytes vanish from the control and this goes red
      # (verified). Decision 9's reason: a control that showed nothing would
      # invite the author to save over a value they never saw.
      test "a value that is neither arm renders raw, with its finding beneath it", %{conn: conn} do
        view = view(conn, %{"summary" => 7})

        assert view |> element(~s(input#sb-field-summary)) |> render() =~ ~s(value="7")

        assert view
               |> element(~s(.sb-field[data-field-type="type_expr"] .sb-finding))
               |> render() =~ "holds neither"
      end
    end

    describe "the inline arm" do
      # Sabotage: `type_expr_members/1` answering `[]` for a stored list -
      # the rows disappear and every assertion here goes red (verified).
      test "one row per member, with the control recursing on a member's type", %{conn: conn} do
        view = view(conn, %{"summary" => @members})

        assert has_element?(view, ~s(.sb-type-expr[data-arm="inline"]))
        assert has_element?(view, ~s(.sb-type-expr__member[data-member="0"]))
        assert has_element?(view, ~s(.sb-type-expr__member[data-member="1"]))

        assert view
               |> element(~s(input#sb-field-summary-0-name))
               |> render() =~ ~s(value="amount_minor")

        # The member's own type is the same control, one level down, over
        # the same feed.
        assert has_element?(view, ~s(datalist#sb-field-summary-0-type-types))
      end

      # Sabotage: `type_expr_value/1` passing `@path` rather than
      # `@path ++ [index]` to the nested control - the inner add gesture
      # names the outer member list, adding a member to the wrong shape,
      # and the path assertion goes red (verified).
      test "a member holding a member list nests, and its gestures name it", %{conn: conn} do
        nested = [
          %{"name" => "amount_minor", "type" => "integer", "required?" => true},
          %{"name" => "inner", "type" => [%{"name" => "x", "type" => "string"}]}
        ]

        view = view(conn, %{"summary" => nested})

        assert has_element?(view, ~s(input#sb-field-summary-1-type-0-name))
        assert has_element?(view, ~s(button.sb-field__add[phx-value-path="1"]))

        view |> element(~s(button.sb-field__add[phx-value-path="1"])) |> render_click()

        assert has_element?(view, ~s(input#sb-field-summary-1-type-1-name))
        refute has_element?(view, ~s(input#sb-field-summary-2-name))
      end

      # Sabotage: `member_required?/1` answering `false` for `true` - the
      # promised member stops being checked and this goes red (verified).
      test "a promised member is checked and an unpromised one is not", %{conn: conn} do
        view = view(conn, %{"summary" => @members})

        assert view |> element(~s(input#sb-field-summary-0-required)) |> render() =~ "checked"
        refute view |> element(~s(input#sb-field-summary-1-required)) |> render() =~ "checked"
      end

      # Sabotage: `apply_gesture/4` appending `""` rather than a blank
      # member - the row the document gains is a string where a member
      # belongs, and the stored-value assertion goes red (verified).
      test "add appends a member row and remove takes one away", %{conn: conn} do
        view = view(conn, %{"summary" => @members})

        view |> element(~s(button.sb-field__add[phx-value-path=""])) |> render_click()

        assert has_element?(view, ~s(input#sb-field-summary-2-name))
        assert summary() == @members ++ [%{"name" => "", "type" => "", "required?" => false}]

        view
        |> element(~s(.sb-type-expr__member[data-member="0"] button.sb-field__remove))
        |> render_click()

        assert view |> element(~s(input#sb-field-summary-0-name)) |> render() =~ ~s(value="note")
      end
    end

    describe "the toggle" do
      # Sabotage: `type_expr_arms/1` answering both arms whatever the
      # declaration says - the single-arm field grows a toggle and the
      # second half goes red (verified).
      test "a field admitting both arms draws one, and a single-arm field draws none", %{
        conn: conn
      } do
        both = view(conn, %{"summary" => "cards.settlement"})

        assert has_element?(both, ~s(input#sb-field-summary-arm-name[checked]))
        assert has_element?(both, ~s(input#sb-field-summary-arm-inline))

        one = view(conn, %{"arms" => ["name"], "summary" => "cards.settlement"})

        refute has_element?(one, ~s(input#sb-field-summary-arm-name))
        assert has_element?(one, ~s(input#sb-field-summary))
      end

      # Sabotage: `decode_type_expr/1` reading the posted `name` on the
      # inline arm - switching arms translates the value instead of
      # replacing it, and the empty-list assertion goes red (verified).
      test "switching arms replaces the value rather than translating it", %{conn: conn} do
        view = view(conn, %{"summary" => "cards.settlement"})

        view
        |> form(~s(form#sb-form-blk_TYP), %{
          "config" => %{"summary" => %{"__arm" => "inline", "name" => "cards.settlement"}}
        })
        |> render_change()

        assert has_element?(view, ~s(.sb-type-expr[data-arm="inline"]))
        refute has_element?(view, ~s(.sb-type-expr__member[data-member="0"]))
      end

      # Sabotage: `decode_members/1` keeping a row whose name and type are
      # both blank - the trailing empty row reaches the document and the
      # stored list stops being the two the author wrote (verified).
      test "the inline arm posts a member list, and a blank row costs nothing", %{conn: conn} do
        # Two rows in the DOM to post through: the form's params are read
        # off the controls the arm is drawing.
        view =
          view(conn, %{
            "summary" => [%{"name" => "amount_minor"}, %{"name" => "note"}]
          })

        view
        |> form(~s(form#sb-form-blk_TYP), %{
          "config" => %{
            "summary" => %{
              "__arm" => "inline",
              "members" => %{
                "0" => %{
                  "name" => "amount_minor",
                  "required?" => "true",
                  "type" => %{"__arm" => "name", "name" => "integer"}
                },
                "1" => %{"name" => "", "type" => %{"__arm" => "name", "name" => ""}}
              }
            }
          }
        })
        |> render_change()

        assert has_element?(view, ~s(.sb-type-expr__member[data-member="0"]))
        refute has_element?(view, ~s(.sb-type-expr__member[data-member="1"]))

        assert view
               |> element(~s(input#sb-field-summary-0-type))
               |> render() =~ ~s(value="integer")
      end
    end
  end
end
