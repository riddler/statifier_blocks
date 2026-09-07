# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. The pure half of this feed -
# the compile-side lint, and the fact that a candidate list decides no value -
# lives in `StatifierBlocks.Compiler.FieldCandidatesTest`, deliberately
# outside this guard.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.FieldCandidatesTest do
    @moduledoc """
    The `field_candidates` feed ADR-0011 names beside `{:path, opts}`'s two
    keys: the values a host offers for one field, keyed
    `{type_name, field_key}`.

    What only exists once there is markup is the half here - that on a
    `:string` a closed list draws a `<select>` and an open one a
    `<datalist>`, that no list at all draws the input the field already had,
    that a picked value reaches the document, and that a stored value the
    list does not offer is drawn rather than rewritten.

    Two more field types read the feed: a `{:path, opts}` and an
    `:expression` draw *either* spelling as a `<datalist>` and keep typing
    the value, ahead of the declared datamodel paths. Their half is here
    too, and what it asserts is that the control still suggests - a path is
    still checked as a path, an expression is still source the author types,
    and a host's `expression_component` still wins over both.
    """

    use StatifierBlocks.EditorLiveCase

    alias StatifierBlocks.Editor.Field
    alias StatifierBlocks.ViewModel

    @key {"core.subchart", "chart"}

    @charts [
      {"bdoc_CREDIT", "Credit check"},
      {"bdoc_KYC", "Identity check"},
      {"bdoc_FRAUD", "Fraud review"}
    ]

    defp document(chart) do
      Document.new(
        Block.new("core.sequence",
          id: "blk_wizard",
          slots: %{
            "body" => [
              Block.new("core.subchart",
                id: "blk_check",
                config: %{"chart" => chart, "outcomes" => "approved"},
                slots: %{"on_approved" => [], "on_error" => []}
              )
            ]
          }
        ),
        id: "doc_signup_wizard"
      )
    end

    defp view(conn, opts) do
      {:ok, view, _html} =
        mount_editor(conn,
          document: document(Keyword.get(opts, :chart, "bdoc_CREDIT")),
          field_candidates: Keyword.get(opts, :field_candidates, %{})
        )

      view
      |> element(~s([data-block-id="blk_check"] > .sb-node__chrome > .sb-node__label))
      |> render_click()

      view
    end

    describe "a closed list" do
      # Sabotage: reordered the two `:string` clauses so the open one is
      # tried first -> a closed list falls through to the text input and
      # every assertion here goes red (verified).
      test "renders a select over the offered values, in declared order", %{conn: conn} do
        view = view(conn, field_candidates: %{@key => @charts})

        assert has_element?(view, ~s(select[name="config[chart]"][data-field-candidates="3"]))

        for {value, label} <- @charts do
          assert has_element?(
                   view,
                   ~s(select[name="config[chart]"] option[value="#{value}"]),
                   label
                 )
        end

        refute has_element?(view, ~s(input[name="config[chart]"]))
      end

      # The picked value is stored, which is the only thing a control is
      # actually for.
      #
      # Sabotage: named the option's `value` after its label -> the picked
      # value reaches the document as the label and this goes red (verified).
      test "picking a value stores it", %{conn: conn} do
        view = view(conn, field_candidates: %{@key => @charts})

        view
        |> element(~s(form[data-block-id="blk_check"]))
        |> render_change(%{"block-id" => "blk_check", "config" => %{"chart" => "bdoc_KYC"}})

        assert has_element?(view, ~s(option[value="bdoc_KYC"][selected]))
      end

      # A `<select>` whose stored value is not among its options posts the
      # FIRST option on the next change, so opening a form would rewrite a
      # value nobody touched. The stored value gets an option of its own.
      #
      # Sabotage: made `unoffered_value/2` answer `nil` always -> the
      # stored value has no option, the browser would select the first one,
      # and this goes red (verified).
      test "a stored value the list does not offer is drawn, not rewritten", %{conn: conn} do
        view = view(conn, chart: "bdoc_LEGACY", field_candidates: %{@key => @charts})

        assert has_element?(view, ~s(select[name="config[chart]"] option[value="bdoc_LEGACY"]))
        refute has_element?(view, ~s(option[value="bdoc_CREDIT"][selected]))
      end
    end

    describe "an open list" do
      # Sabotage: dropped `list={@list_id}` from the open control's input ->
      # the datalist is attached to nothing, which renders identically and
      # suggests nothing, and this goes red on the binding (verified).
      test "renders the text input bound to a datalist", %{conn: conn} do
        view = view(conn, field_candidates: %{@key => {:open, @charts}})

        assert has_element?(
                 view,
                 ~s(input[name="config[chart]"][list="sb-field-chart-candidates"])
               )

        assert has_element?(
                 view,
                 ~s(datalist#sb-field-chart-candidates[data-field-candidates="3"])
               )

        refute has_element?(view, ~s(select[name="config[chart]"]))
      end
    end

    describe "no list supplied" do
      # Sabotage: widened the closed clause's `[_ | _]` to `_any` -> an
      # empty list draws a `<select>` with no options, which offers an
      # author nothing and refuses them everything, and this goes red
      # (verified).
      test "renders the plain input the field already had", %{conn: conn} do
        for candidates <- [%{}, %{@key => []}] do
          view = view(conn, field_candidates: candidates)

          assert has_element?(view, ~s(input[name="config[chart]"]))
          refute has_element?(view, ~s(select[name="config[chart]"]))
          refute has_element?(view, ~s(datalist#sb-field-chart-candidates))
        end
      end

      # Sabotage: keyed the lookup on the field key alone -> a list meant
      # for another type's `chart` field reaches this one and this goes red
      # (verified).
      test "a list keyed on another type does not reach this field", %{conn: conn} do
        view = view(conn, field_candidates: %{{"host.step", "chart"} => @charts})

        assert has_element?(view, ~s(input[name="config[chart]"]))
        refute has_element?(view, ~s(select[name="config[chart]"]))
      end
    end

    describe "a :path field (sb-uw3a)" do
      @path_key {"core.subchart", "assign_to"}
      @offered_paths [{"eligibility", "Eligibility"}, {"signup.step", "Step"}]
      @declared_paths ["eligibility", "signup.step"]

      defp path_document(assign_to) do
        Document.new(
          Block.new("core.sequence",
            id: "blk_wizard",
            slots: %{
              "body" => [
                Block.new("core.subchart",
                  id: "blk_check",
                  config: %{
                    "chart" => "bdoc_CREDIT",
                    "outcomes" => "approved",
                    "assign_to" => assign_to
                  },
                  slots: %{"on_approved" => [], "on_error" => []}
                )
              ]
            }
          ),
          id: "doc_signup_wizard"
        )
      end

      defp path_view(conn, opts) do
        {:ok, view, _html} =
          mount_editor(
            conn,
            [document: path_document(Keyword.get(opts, :assign_to, "eligibility"))] ++
              Keyword.drop(opts, [:assign_to])
          )

        view
        |> element(~s([data-block-id="blk_check"] > .sb-node__chrome > .sb-node__label))
        |> render_click()

        view
      end

      # A `:path` types its value, so a CLOSED list is drawn as a datalist
      # here and not as the `<select>` a `:string` draws.
      #
      # Sabotage: made `suggestion_control/4` render a `<select>` over the
      # offered values instead of the input-plus-datalist -> 9 of this file's
      # 19 go red, this one included (verified).
      test "a closed list renders the datalist, not a select", %{conn: conn} do
        view = path_view(conn, field_candidates: %{@path_key => @offered_paths})

        assert has_element?(
                 view,
                 ~s(input[name="config[assign_to]"][list="sb-field-assign_to-candidates"])
               )

        assert has_element?(
                 view,
                 ~s(datalist#sb-field-assign_to-candidates[data-field-candidates="2"])
               )

        for {value, _label} <- @offered_paths do
          assert has_element?(
                   view,
                   ~s(datalist#sb-field-assign_to-candidates option[value="#{value}"])
                 )
        end

        refute has_element?(view, ~s(select[name="config[assign_to]"]))
      end

      # Sabotage: dropped both `{:open, [_ | _] = offered}` clauses -> the
      # open spelling falls through to the declared-paths clause, the bound
      # list is `-paths`, and 4 go red on the binding, this one included
      # (verified).
      test "an open list renders the same datalist", %{conn: conn} do
        view = path_view(conn, field_candidates: %{@path_key => {:open, @offered_paths}})

        assert has_element?(
                 view,
                 ~s(input[name="config[assign_to]"][list="sb-field-assign_to-candidates"])
               )

        assert has_element?(
                 view,
                 ~s(datalist#sb-field-assign_to-candidates[data-field-candidates="2"])
               )
      end

      # The control suggests, and the value is still a PATH: an undeclared
      # value keeps ADR-0005 clause 11e's `:info` advisory whether or not a
      # host offered a list.
      #
      # Sabotage: made `suggestion_control/4` render a `<select>` -> the
      # datalist assertion goes red first, and with it the guarantee that
      # keeps the stored `risk_tier` from being rewritten to an offered
      # value on the next change (verified).
      test "the value is still validated as a path", %{conn: conn} do
        view =
          path_view(conn,
            assign_to: "risk_tier",
            datamodel: @declared_paths,
            field_candidates: %{@path_key => @offered_paths}
          )

        assert has_element?(view, ~s(datalist#sb-field-assign_to-candidates))

        assert has_element?(
                 view,
                 ~s(.sb-field[data-field="assign_to"] .sb-finding),
                 "risk_tier is not declared"
               )
      end

      # Sabotage: rendered the host list as a `<select>` -> this goes red
      # with LiveView refusing a value the select does not offer, which is
      # the whole reason a closed list is a datalist on this type (verified).
      test "a path the list does not offer still reaches the document", %{conn: conn} do
        view =
          path_view(conn,
            datamodel: @declared_paths,
            field_candidates: %{@path_key => @offered_paths}
          )

        view
        |> form(~s(#sb-form-blk_check), %{"config" => %{"assign_to" => "merchant.risk_tier"}})
        |> render_change()

        assert %{"assign_to" => "merchant.risk_tier"} =
                 latest_document()
                 |> Document.blocks()
                 |> Enum.find(&(&1.id == "blk_check"))
                 |> Map.fetch!(:config)
      end

      # A list keyed on THIS field is the narrower claim than the document's
      # declarations, so it is read ahead of them.
      #
      # Sabotage: moved the new clauses below the `path_candidates` ones ->
      # the declared paths win, the bound list is `-paths`, and 7 go red,
      # this one included (verified).
      test "the host list is read ahead of the declared paths", %{conn: conn} do
        view =
          path_view(conn,
            datamodel: @declared_paths,
            field_candidates: %{@path_key => @offered_paths}
          )

        assert has_element?(
                 view,
                 ~s(input[name="config[assign_to]"][list="sb-field-assign_to-candidates"])
               )

        refute has_element?(view, ~s(datalist#sb-field-assign_to-paths))
      end

      # Sabotage: widened the new clauses' `[_ | _]` to a bare variable -> an
      # empty list draws an empty datalist over the declared paths, and this
      # goes red on the `-paths` binding (verified; 2 failures, both of the
      # "no list supplied" pair).
      test "no list supplied renders the declared-paths datalist it already had", %{conn: conn} do
        view = path_view(conn, datamodel: @declared_paths, field_candidates: %{@path_key => []})

        assert has_element?(
                 view,
                 ~s(input[name="config[assign_to]"][list="sb-field-assign_to-paths"])
               )

        refute has_element?(view, ~s(datalist#sb-field-assign_to-candidates))
      end
    end

    describe "an :expression field (sb-uw3a)" do
      @expression_key {"core.branch", "arm_beta"}
      @offered_conditions [
        {"signup.step == 2", "At the second step"},
        {"eligibility == 'approved'", "Eligible"}
      ]

      # sb-m6e0 made statifier-ui's expression editor the default control for
      # an `:expression`, so the plain input these tests are about renders
      # only with that package absent. Pointing the key at a module that does
      # not exist is `Field`'s documented way to spell the absent tree.
      setup do
        previous = Application.get_env(:statifier_blocks, :expression_component_module)
        Application.put_env(:statifier_blocks, :expression_component_module, NoSuchModule)

        on_exit(fn ->
          if previous do
            Application.put_env(:statifier_blocks, :expression_component_module, previous)
          else
            Application.delete_env(:statifier_blocks, :expression_component_module)
          end
        end)

        :ok
      end

      defp branch_view(conn, opts) do
        document =
          Document.new(
            Block.new("core.branch",
              id: "blk_route",
              config: %{"arms" => [%{"slot" => "arm_beta", "cond" => "signup.step == 2"}]},
              slots: %{
                "arm_beta" => [EditorFixtures.wait("blk_beta_step", "5m")],
                "otherwise" => []
              }
            ),
            id: "doc_route"
          )

        {:ok, view, _html} = mount_editor(conn, [document: document] ++ opts)

        view
        |> element(~s([data-block-id="blk_route"] > .sb-node__chrome > .sb-node__label))
        |> render_click()

        view
      end

      # Sabotage: moved the new clauses below the `path_candidates` ones ->
      # the plain input renders with no list bound and this goes red, one of
      # 7 (verified).
      test "a closed list renders the datalist on the expression input", %{conn: conn} do
        view = branch_view(conn, field_candidates: %{@expression_key => @offered_conditions})

        assert has_element?(
                 view,
                 ~s(input.sb-field__input--expression[name="config[arm_beta]"][list="sb-field-arm_beta-candidates"])
               )

        assert has_element?(
                 view,
                 ~s(datalist#sb-field-arm_beta-candidates[data-field-candidates="2"])
               )

        refute has_element?(view, ~s(select[name="config[arm_beta]"]))
      end

      # Sabotage: dropped both `{:open, [_ | _] = offered}` clauses -> the
      # open spelling falls through to the plain input and this goes red,
      # one of 4 (verified).
      test "an open list renders the same datalist", %{conn: conn} do
        view =
          branch_view(conn, field_candidates: %{@expression_key => {:open, @offered_conditions}})

        assert has_element?(
                 view,
                 ~s(input[name="config[arm_beta]"][list="sb-field-arm_beta-candidates"])
               )
      end

      # The value is still an EXPRESSION: source the author types, not a
      # value picked from a set.
      #
      # Sabotage: rendered the closed list as a `<select>` -> LiveView
      # refuses a value the select does not offer and this goes red, which
      # is why a closed list is a datalist on this type too (verified).
      test "an expression the list does not offer still reaches the document", %{conn: conn} do
        view = branch_view(conn, field_candidates: %{@expression_key => @offered_conditions})

        view
        |> form(~s(#sb-form-blk_route), %{"config" => %{"arm_beta" => "merchant.risk_tier > 2"}})
        |> render_change()

        assert [%{"slot" => "arm_beta", "cond" => "merchant.risk_tier > 2"}] =
                 latest_document()
                 |> Document.blocks()
                 |> Enum.find(&(&1.id == "blk_route"))
                 |> Map.fetch!(:config)
                 |> Map.fetch!("arms")
      end

      # Sabotage: put the new clauses after the `path_candidates` clause ->
      # the declared paths win and this goes red on the binding.
      test "the host list is read ahead of the declared paths", %{conn: conn} do
        view =
          branch_view(conn,
            datamodel: ["signup.step"],
            field_candidates: %{@expression_key => @offered_conditions}
          )

        assert has_element?(
                 view,
                 ~s(input[name="config[arm_beta]"][list="sb-field-arm_beta-candidates"])
               )

        refute has_element?(view, ~s(datalist#sb-field-arm_beta-paths))
      end

      # Sabotage: widened the new clauses' `[_ | _]` to a bare variable -> an
      # empty list draws an empty datalist and this goes red (verified).
      test "no list supplied renders the input it already had", %{conn: conn} do
        view = branch_view(conn, field_candidates: %{@expression_key => []})

        assert has_element?(view, ~s(input[name="config[arm_beta]"][placeholder="an expression"]))
        refute has_element?(view, ~s(input[name="config[arm_beta]"][list]))
      end

      # Sabotage: dropped `expression_component: nil` from the new expression
      # clauses -> the package's suggestion markup renders in place of a
      # host's own control and this goes red on both assertions (verified: 1
      # failure, this one - the mutation survives every other test in this
      # file, which is why this one exists).
      test "a host's expression_component still wins, undecorated" do
        component = fn _assigns -> Phoenix.HTML.raw(~s(<b class="host-editor"></b>)) end

        html =
          render_component(&Field.field/1, %{
            field: %ViewModel.Field{
              key: "cond",
              type: :expression,
              label: "Only when",
              required?: false,
              default: nil,
              value: "signup.step == 2",
              value_path: ["cond"]
            },
            target: "#sb-editor",
            expression_component: component,
            candidates: @offered_conditions
          })

        assert html =~ ~s(class="host-editor")
        refute html =~ "<datalist"
      end
    end

    describe "the field types that read no candidate list (sb-uw3a)" do
      # `:string`, `{:path, opts}` and `:expression` read it; a control that
      # already knows what to draw ignores it, and a second source of options
      # on top of one would be two answers to one question.
      #
      # Sabotage: dropped the field-type guard from a new clause, leaving
      # `candidates` alone to select it -> a `:duration` picks up the
      # datalist and this goes red (verified: 2 failures, this one and the
      # `expression_component` test above, and nothing else in this file
      # notices).
      test "a :duration offered a list renders the control it already had" do
        html =
          render_component(&Field.field/1, %{
            field: %ViewModel.Field{
              key: "after",
              type: :duration,
              label: "Wait for",
              required?: false,
              default: nil,
              value: "5m",
              value_path: ["after"]
            },
            target: "#sb-editor",
            candidates: [{"5m", "Five minutes"}, {"1h", "An hour"}]
          })

        refute html =~ "sb-field-after-candidates"
        refute html =~ "<datalist"
      end
    end
  end
end
