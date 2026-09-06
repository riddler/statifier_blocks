# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. The projection itself is
# pure and is asserted in `StatifierBlocks.DatamodelTest`, deliberately
# outside this guard; what is here only exists once there is markup.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.PathTypesTest do
    @moduledoc """
    sb-23e0: the datamodel's declared kinds reach the condition editor.

    `StatifierDatamodel.Index.path_types/1` projects the document to the
    expression language's own vocabulary, and statifier-ui 0.8's
    `ExpressionInput` takes that map as `:path_types` and reads it as *which
    operators a clause offers and which control it draws*. This package is
    the courier between the two, so what is asserted here is the courier's
    job: that a document declaring a path reaches the operator picker for it,
    and that a document declaring nothing leaves the picker exactly as it was.

    The discriminating case is a clause whose OWN source implies a narrower
    operator set than the declaration does - `amount_cents == true` observes
    `boolean` and offers five operators, where the declared `integer` offers
    the numeric nine. A source already agreeing with its declaration proves
    nothing about whether the map arrived.
    """

    use StatifierBlocks.EditorLiveCase

    alias StatifierBlocks.Editor.Field
    alias StatifierBlocks.ViewModel

    # The card-processing domain's amount, declared as ADR-0006 spells it.
    @document %{
      "version" => 1,
      "scopes" => [
        %{
          "scope" => "local",
          "entries" => [%{"path" => "amount_cents", "type" => "integer"}]
        }
      ]
    }

    # A boolean-valued clause on the declared path: predicator offers five
    # operators for what it observes and nine for what the document declares,
    # and `>=` is in the second set only.
    @source "amount_cents == true"
    @numeric_only ~w(> >= < <=)

    defp expression_field(value) do
      %ViewModel.Field{
        key: "cond",
        type: :expression,
        label: "Condition",
        required?: false,
        default: nil,
        value: value,
        value_path: ["cond"]
      }
    end

    defp render_field(assigns) do
      render_component(
        &Field.field/1,
        Map.merge(
          %{
            field: expression_field(@source),
            target: "#sb-editor",
            path_candidates: ["amount_cents"]
          },
          assigns
        )
      )
    end

    # Every operator the picker offers, as the source each option writes.
    defp offered_operators(html) do
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(~s(select[data-role="operator"] option))
      |> LazyHTML.attribute("value")
    end

    describe "a declared kind at the seam" do
      # Sabotage: substituted `%{}` for `@path_types` at the seam's map in
      # `Field` -> 4 of this file's 6 go red, this one included (verified).
      # Reaching the seam is the precondition for everything below it.
      test "the declared kind is what the clause row reports" do
        html = render_field(%{path_types: %{"amount_cents" => :number}})

        assert html =~ ~s(data-declared-kind="number")
      end

      # The criterion itself: the numeric set, on a clause whose own source
      # would not have offered it.
      #
      # Sabotage: substituted `%{}` for `@path_types` at the seam -> the row
      # falls back to the five operators its boolean value implies and every
      # assertion here goes red.
      test "the operator picker offers the numeric set" do
        offered = render_field(%{path_types: %{"amount_cents" => :number}}) |> offered_operators()

        for operator <- @numeric_only do
          assert Enum.any?(offered, &String.contains?(&1, " #{operator} ")),
                 "a declared integer offers #{operator}; got #{inspect(offered)}"
        end

        # And it is the numeric set rather than a superset of both: the row
        # offers what its own source implies plus exactly the four comparisons
        # the declaration adds, which pins the count without this file
        # restating predicator's operator tables.
        assert length(offered) == length(offered_operators(render_field(%{}))) + 4
      end

      # The complement, and the whole of "absent a document, behaviour is
      # unchanged": with nothing declared the row is what it was before this
      # existed - the operators its own source implies, and no declared kind.
      #
      # Sabotage: the pair is the guard. Defaulting `path_types` to a kind
      # rather than `%{}` anywhere along the five hops takes this red while
      # the test above stays green.
      test "with nothing declared the row offers only what its source implies" do
        html = render_field(%{})
        offered = offered_operators(html)

        refute html =~ "data-declared-kind"

        for operator <- @numeric_only do
          refute Enum.any?(offered, &String.contains?(&1, " #{operator} ")),
                 "an undeclared path offers no #{operator}; got #{inspect(offered)}"
        end
      end

      # The seam's map grew a key the same way it grew `candidates` (sb-0vt)
      # and `value_candidates` (sb-m6e0): additive, so a host that supplied
      # its own control is handed the map too rather than having to re-derive
      # it from a datamodel this component never gives it.
      #
      # Sabotage: substituted `%{}` at the seam -> the override is handed an
      # empty map and this goes red with the first test. Dropping the key
      # outright raises `KeyError` here rather than in the component, which
      # normalizes a missing `:path_types` to `%{}` itself.
      test "a host's own expression component is handed the same map" do
        component = fn assigns ->
          Phoenix.HTML.raw(~s(<b data-seen="#{inspect(assigns.path_types)}"></b>))
        end

        html =
          render_field(%{
            expression_component: component,
            path_types: %{"amount_cents" => :number}
          })

        assert html =~ ~s(amount_cents)
        assert html =~ ~s(:number)
      end
    end

    describe "the editor threads the declaration" do
      # The five-hop path - editor -> inspector -> config panel -> config form
      # -> field -> the seam - through a connected mount, because every hop is
      # a place the assign silently arrives as its `%{}` default instead. The
      # host supplies a DOCUMENT here and not a map of kinds: deriving the map
      # from it is `Editor`'s own half of the bead.
      #
      # Sabotage: dropped `path_types={@path_types}` from the
      # `ConfigForm.config_form` call in `Inspector` -> the form's default
      # `%{}` reached the field and this is the only test in the file that
      # goes red. The other hops are the same shape and this is their guard.
      test "from the host's datamodel document to the operator picker", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: branch_document(), datamodel: @document)

        select_route(view)

        assert has_element?(view, ~s([data-declared-kind="number"]))

        offered =
          view
          |> render()
          |> offered_operators()

        for operator <- @numeric_only do
          assert Enum.any?(offered, &String.contains?(&1, " #{operator} ")),
                 "the declaration reached the picker; got #{inspect(offered)}"
        end
      end

      # `nil` is a host that supplied no datamodel at all, which is the case
      # "absent a document, behaviour is unchanged" names. Asserted through
      # the same mount, so the two differ in the datamodel and nothing else.
      #
      # Sabotage: `declared_path_types/1` in `Editor` reading anything but
      # the `datamodel` assign - the declared-path SET, say, which carries no
      # per-path shape -> the derivation raises or answers wrongly, and this
      # or its sibling above goes red.
      test "and with no document supplied, the picker is unchanged", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: branch_document())

        select_route(view)

        refute has_element?(view, "[data-declared-kind]")

        offered =
          view
          |> render()
          |> offered_operators()

        for operator <- @numeric_only do
          refute Enum.any?(offered, &String.contains?(&1, " #{operator} ")),
                 "no declaration, no widening; got #{inspect(offered)}"
        end
      end
    end

    defp select_route(view) do
      view
      |> element(~s([data-block-id="blk_route"] > .sb-node__chrome > .sb-node__label))
      |> render_click()

      view
    end

    defp branch_document do
      Document.new(
        Block.new("core.branch",
          id: "blk_route",
          config: %{"arms" => [%{"slot" => "arm_beta", "cond" => @source}]},
          slots: %{
            "arm_beta" => [EditorFixtures.wait("blk_beta_step", "5m")],
            "otherwise" => []
          }
        ),
        id: "doc_route"
      )
    end
  end
end
