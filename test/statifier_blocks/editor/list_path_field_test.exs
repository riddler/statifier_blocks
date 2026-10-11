# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. The advisory's own rule - that
# each row of a `{:list, {:path, opts}}` field is checked - is pure and lives
# in `StatifierBlocks.DatamodelTest`, deliberately outside this guard.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.ListPathFieldTest do
    @moduledoc """
    A `{:list, {:path, opts}}` field: each row is a datamodel path, so each
    row's input is bound to the same `<datalist>` of declared paths a single
    `{:path, opts}` field offers, and an undeclared row's `:info` advisory
    is drawn beneath the field.
    """

    use StatifierBlocks.EditorLiveCase

    alias StatifierBlocks.Editor.Field
    alias StatifierBlocks.ViewModel

    defmodule OverdueNotice do
      @moduledoc false
      # A library-loan host type: an overdue notice copied to a list of
      # datamodel paths, and a list of plain labels beside it.
      use StatifierBlocks.BlockType

      @impl true
      def config_schema(_config) do
        [
          %{
            key: "copy_to",
            type: {:list, {:path, %{}}},
            label: "Copy to",
            required?: false,
            default: []
          },
          %{
            key: "shelves",
            type: {:list, :string},
            label: "Shelves",
            required?: false,
            default: []
          }
        ]
      end

      @impl true
      def io(_config), do: %{kinds: [:step]}

      @impl true
      def palette_entry, do: %{label: "Overdue notice"}

      @impl true
      def emit(%Block{id: id}, _context), do: {:error, {:not_implemented, id}}
    end

    @declared ["branch", "patron.email"]

    defp notice_document(copy_to) do
      Document.new(
        Block.new("core.sequence",
          id: "blk_loan",
          slots: %{
            "body" => [
              Block.new("library.overdue_notice",
                id: "blk_overdue",
                config: %{"copy_to" => copy_to, "shelves" => ["returns"]}
              )
            ]
          }
        ),
        id: "doc_library_loan"
      )
    end

    defp notice_view(conn, copy_to, opts) do
      palette =
        Palette.new(Map.put(Palette.core_types(), "library.overdue_notice", OverdueNotice))

      {:ok, view, _html} =
        mount_editor(conn, [document: notice_document(copy_to), palette: palette] ++ opts)

      view
      |> element(~s([data-block-id="blk_overdue"] > .sb-node__chrome > .sb-node__label))
      |> render_click()

      view
    end

    describe "the rows' candidate list" do
      # Sabotage: dropped `list={@row_list_id}` from the list control's
      # `row_control` call -> the rows fall to the fallback input, carry no
      # `list` attribute, and this goes red on the binding while the
      # datalist itself still renders.
      test "every row's input is bound to one datalist of the declared paths", %{conn: conn} do
        view = notice_view(conn, ["patron.email", "branch.desk_email"], datamodel: @declared)

        for index <- [0, 1] do
          assert has_element?(
                   view,
                   ~s(input#sb-field-copy_to-#{index}[name="config[copy_to][]"][list="sb-field-copy_to-paths"])
                 )
        end

        assert has_element?(view, ~s(datalist#sb-field-copy_to-paths[data-path-candidates="2"]))

        for path <- @declared do
          assert has_element?(view, ~s(datalist#sb-field-copy_to-paths option[value="#{path}"]))
        end
      end

      # Sabotage: made `row_path_candidates/2` answer the candidates for every
      # inner type -> the `{:list, :string}` field gains a datalist and its
      # row a `list` attribute, and this goes red.
      test "a list of another type is offered nothing", %{conn: conn} do
        view = notice_view(conn, ["patron.email"], datamodel: @declared)

        refute has_element?(view, ~s(input[name="config[shelves][]"][list]))
        refute has_element?(view, "datalist#sb-field-shelves-paths")
      end

      # Sabotage: dropped the `:if` from the rows' `<datalist>` -> an empty
      # list renders, and the refute below goes red. No candidates is the
      # plain row input a list row always drew.
      test "no declaring surface is the plain row input, with no list", %{conn: conn} do
        view = notice_view(conn, ["patron.email"], [])

        assert has_element?(view, ~s(input#sb-field-copy_to-0[name="config[copy_to][]"]))
        refute has_element?(view, ~s(input[name="config[copy_to][]"][list]))
        refute has_element?(view, "datalist")
      end
    end

    describe "the undeclared-row advisory" do
      # Sabotage: dropped `Datamodel`'s list-of-paths clause in
      # `field_findings/5` -> no advisory is produced and this goes red.
      test "an undeclared row draws the advisory on the list field", %{conn: conn} do
        view = notice_view(conn, ["patron.email", "patron.phone"], datamodel: @declared)

        assert has_element?(
                 view,
                 ~s(.sb-field[data-field="copy_to"] .sb-finding),
                 "patron.phone is not declared"
               )
      end

      test "declared rows draw no advisory", %{conn: conn} do
        view = notice_view(conn, ["patron.email", "branch"], datamodel: @declared)

        refute has_element?(view, ~s(.sb-field[data-field="copy_to"] .sb-finding))
      end
    end

    describe "the component alone" do
      # The same binding with no editor around it: `Field.field/1` is public,
      # and a host that places it reaches the rows' list through
      # `path_candidates` alone.
      test "path_candidates reach the rows of a list-of-paths field" do
        field = %ViewModel.Field{
          key: "copy_to",
          type: {:list, {:path, %{}}},
          label: "Copy to",
          required?: false,
          default: [],
          value: ["patron.email"]
        }

        html =
          render_component(&Field.field/1,
            field: field,
            target: "#editor",
            path_candidates: @declared
          )

        assert html =~ ~s(list="sb-field-copy_to-paths")
        assert html =~ ~s(<datalist id="sb-field-copy_to-paths" data-path-candidates="2">)
      end
    end
  end
end
