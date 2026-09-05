# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. Nothing here is pure - the
# subject is which control an `:expression` renders, which only exists once
# there is markup.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.ExpressionComponentTest do
    @moduledoc """
    sb-m6e0: an `:expression` renders statifier-ui's expression editor.

    Decision 9 deferred rich expression editing to statifier-ui and left the
    `expression_component` seam behind for it. This is the seam being filled
    from inside the package: with `statifier_ui` on the load path an
    `:expression` gets its editor, with the package absent it gets the plain
    source input it has always had, and a host's own override still wins over
    both.

    The three arms are asserted separately because they are three different
    claims, and the middle one is the one a machine with statifier-ui
    installed would otherwise never exercise: it is reached by pointing
    `:statifier_blocks, :expression_component_module` at a module that does
    not exist, which is `Field`'s documented way to spell the absent tree.
    """

    use StatifierBlocks.EditorLiveCase

    alias StatifierBlocks.Editor.Field
    alias StatifierBlocks.ViewModel

    @value_candidates %{"step" => ["payment", "review"], "plan" => ["pro", "free"]}

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

    defp render_field(value, assigns \\ %{}) do
      render_component(
        &Field.field/1,
        Map.merge(
          %{
            field: expression_field(value),
            target: "#sb-editor",
            path_candidates: ["step", "plan"],
            value_candidates: @value_candidates
          },
          assigns
        )
      )
    end

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

    describe "statifier-ui present" do
      # Sabotage: made `resolve_expression_component/1` answer a nil override
      # with nil, so the plain input rendered -> 6 of this file's 11 go red,
      # this one included. That mutation is the whole feature being absent,
      # which is what the first test of it should catch.
      test "an :expression renders statifier-ui's editor, not the plain input" do
        html = render_field("step == 'payment'")

        assert html =~ ~s(class="statifier-ui-expression )
        assert html =~ ~s(data-mode="picklist")
        assert html =~ ~s(data-subset="inside")
        refute html =~ "sb-field__input--expression"
      end

      # A single clause is the base case and is inside the subset - the
      # component draws one row, not two, and there is no connective to pick.
      #
      # Sabotage: shares mutation 1's fate above - with the seam unfilled
      # there is no clause row at all and this goes red. What it adds over
      # that test is the count: one clause is the base case, and a renderer
      # that assumed a connective would need two.
      test "a single-clause guard draws one clause row" do
        html = render_field("plan == 'pro'")

        assert html =~ ~s(data-clause-count="1")
        assert html =~ ~s(data-clause-index="0")
        refute html =~ ~s(data-clause-index="1")
      end

      # Sabotage: dropped `value_candidates:` from the seam's map -> the
      # component raises `KeyError` on the key it declares an attr for and
      # this goes red (3 of 11 do). The whole point of the new assign is that
      # the host's own value set reaches the picker.
      test "value_candidates reach the clause's value control" do
        html = render_field("step == 'payment'")

        assert html =~ ~s(data-role="value")
        assert html =~ ~s(data-value-kind="select")
        assert html =~ "payment"
        assert html =~ "review"
      end

      # The complement, and the reason `value_candidates` is a map rather than
      # a list: a path the host said nothing about is free text, never an
      # empty dropdown that offers the author nothing.
      #
      # Sabotage: the pair is the guard - dropping the assign takes the
      # previous test red while this one stays green, because free text is
      # exactly what a path with nothing offered for it should get.
      test "a path with no entry gets a free-text value control" do
        html = render_field("amount >= 500")

        assert html =~ ~s(data-value-kind="text")
        refute html =~ ~s(data-value-kind="select")
      end

      # Never refuses, never rewrites: source the picklists cannot draw is
      # still the author's own string, in a text input.
      #
      # Sabotage: none available in this repo - the arm is statifier-ui's.
      # What this asserts about THIS repo is that the source string reaches
      # the seam verbatim; dropping `to_text/1` from the map's `value` key
      # takes it red.
      test "source outside the subset stays text, and stays the author's own" do
        html = render_field("len(plan) > 0")

        assert html =~ ~s(data-mode="text")
        assert html =~ ~s(data-subset="outside")
        assert html =~ "value=\"len(plan) &gt; 0\""
      end

      # The input keeps the name the package gave it, so an edit is still the
      # editor's own `config-change` event with every other field on it. This
      # is the property that keeps the document the source of truth.
      #
      # Sabotage: dropped `name:` from the seam's map -> KeyError, red.
      test "the rendered input posts under the package's own field name" do
        html = render_field("step == 'payment'")

        assert html =~ ~s(name="config[cond]")
      end
    end

    describe "statifier-ui absent" do
      # Sabotage: replaced the whole guard with `true` -> the capture was made
      # against a module that does not exist and rendering raised
      # `UndefinedFunctionError`. Red, along with the datalist test below.
      test "the plain source input is what renders" do
        html = without_statifier_ui(fn -> render_field("step == 'payment'") end)

        assert html =~ "sb-field__input--expression"
        assert html =~ ~s(placeholder="an expression")
        refute html =~ "statifier-ui-expression"
      end

      # The datalist clause is still reachable, which is the sb-0vt behaviour
      # this change is additive to rather than replacing.
      #
      # Sabotage: shares the guard mutation above - with the resolution
      # unguarded there is no absent tree to fall back into and this goes red
      # with it.
      test "the declared paths still bind as a datalist" do
        html = without_statifier_ui(fn -> render_field("step == 'payment'") end)

        assert html =~ ~s(list="sb-field-cond-paths")
        assert html =~ ~s(data-path-candidates="2")
      end
    end

    describe "a host override" do
      # Clause 1 of the ordering: a host that supplied a component asked for
      # its own control and gets it, statifier-ui installed or not.
      #
      # Sabotage: made `resolve_expression_component/1` ignore its argument
      # and answer with `statifier_ui_component/0` -> the picklists render
      # over the host's own control and this goes red, with the next test.
      test "wins over statifier-ui's editor" do
        component = fn _assigns -> Phoenix.HTML.raw(~s(<b class="host-editor"></b>)) end

        html = render_field("step == 'payment'", %{expression_component: component})

        assert html =~ ~s(class="host-editor")
        refute html =~ "statifier-ui-expression"
      end

      # The seam's map grew a key (sb-m6e0), the same way it grew `candidates`
      # (sb-0vt): additive, so an override that reads it gets it.
      #
      # Sabotage: shares mutation 4 above - a host override that never runs
      # is never handed anything, and this goes red with it. Dropping
      # `value_candidates:` from the seam's map takes it red too.
      test "is handed the host's value_candidates" do
        component = fn assigns ->
          Phoenix.HTML.raw(
            ~s(<b data-seen="#{Enum.join(Map.keys(assigns.value_candidates), ",")}"></b>)
          )
        end

        html = render_field("step == 'payment'", %{expression_component: component})

        assert html =~ ~s(data-seen="plan,step")
      end
    end

    describe "the editor threads value_candidates" do
      # The five-hop path - editor -> inspector -> config panel -> config form
      # -> field -> the seam - proven end to end through a connected mount,
      # because every hop is a place the assign silently arrives as its
      # default instead.
      #
      # Sabotage: dropped `value_candidates={@value_candidates}` from the
      # `ConfigForm.config_form` call in `Inspector` -> the form's default
      # `%{}` reached the field, the value control fell back to free text, and
      # this is the ONLY test in the file that goes red (verified). The other
      # hops are the same shape, and this is the one test that guards them.
      test "from the host assign to the clause's value control", %{conn: conn} do
        {:ok, view, _html} =
          mount_editor(conn,
            document: branch_document(),
            datamodel: ["step"],
            value_candidates: %{"step" => ["payment", "review"]}
          )

        view
        |> element(~s([data-block-id="blk_route"] > .sb-node__chrome > .sb-node__label))
        |> render_click()

        assert has_element?(view, ~s(select[data-role="value"][data-value-kind="select"]))
        assert has_element?(view, ~s(select[data-role="value"] option[value="step == 'review'"]))
      end
    end

    defp branch_document do
      Document.new(
        Block.new("core.branch",
          id: "blk_route",
          config: %{"arms" => [%{"slot" => "arm_beta", "cond" => "step == 'payment'"}]},
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
