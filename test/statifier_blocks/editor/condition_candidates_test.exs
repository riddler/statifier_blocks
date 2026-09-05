# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. What these assert the
# *rendering* of is pure and lives in `StatifierBlocks.DatamodelTest`, which
# is deliberately outside this guard.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.ConditionCandidatesTest do
    @moduledoc """
    sb-0vt: the declared datamodel paths reach an `:expression` control.

    The set itself is `StatifierBlocks.Datamodel.candidates/3`'s and is
    asserted with LiveView absent. What only exists once there is markup is
    the half here: that the three declaring surfaces reach the datalist
    through the editor's own assigns, that a supplied `expression_component`
    is handed the same list and is not decorated by the package, and that
    none of it constrains what an author may type - ADR-0005 decision 9 keeps
    the gate at `validate_config/1` and 11e keeps an undeclared path an
    `:info` advisory.
    """

    use StatifierBlocks.EditorLiveCase

    alias StatifierBlocks.Document.DatamodelEntry
    alias StatifierBlocks.Editor.Field
    alias StatifierBlocks.ViewModel

    @declared ["signup.step", "signup.variant_id"]

    defp branch_document(datamodel_entries) do
      Document.new(
        Block.new("core.branch",
          id: "blk_route",
          config: %{"arms" => [%{"slot" => "arm_beta", "cond" => "signup.step == 2"}]},
          slots: %{
            "arm_beta" => [EditorFixtures.wait("blk_beta_step", "5m")],
            "otherwise" => []
          }
        ),
        id: "doc_route",
        datamodel: datamodel_entries
      )
    end

    defp select(view, id) do
      view
      |> element(~s([data-block-id="#{id}"] > .sb-node__chrome > .sb-node__label))
      |> render_click()

      view
    end

    defp branch_view(conn, opts) do
      {:ok, view, _html} =
        mount_editor(conn, [document: branch_document(Keyword.get(opts, :entries, []))] ++ opts)

      select(view, "blk_route")
    end

    describe "the :expression path suggestion list" do
      # sb-m6e0 made statifier-ui's expression editor the DEFAULT control for
      # an `:expression`, so the plain input with its `<datalist>` is now what
      # renders when that package is absent. These tests are about that
      # control, so they name the tree they are about rather than depending on
      # which packages happen to be resolvable on the machine running them.
      # Pointing the key at a module that does not exist is the supported way
      # to spell "statifier-ui is not here"; see `Field`'s moduledoc.
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

      # Sabotage: dropped `list={@list_id}` from the expression input -> 1
      # failure, on the binding assertion alone. The datalist can exist and be
      # attached to nothing, which is the defect worth catching and the one a
      # "does the markup contain the paths" assertion would miss.
      test "the declared paths render as a datalist the input is bound to", %{conn: conn} do
        view = branch_view(conn, datamodel: @declared)

        assert has_element?(
                 view,
                 ~s(input[name="config[arm_beta]"][list="sb-field-arm_beta-paths"])
               )

        assert has_element?(view, ~s(datalist#sb-field-arm_beta-paths[data-path-candidates="2"]))

        for path <- @declared do
          assert has_element?(view, ~s(datalist#sb-field-arm_beta-paths option[value="#{path}"]))
        end
      end

      # Sabotage: widened the clause's `[_first | _rest]` to `_any` -> 1
      # failure here. An empty list rendered an empty `<datalist>`, which is
      # markup that suggests nothing and only adds an element to trip over -
      # the same rule the `invoke_type` list follows.
      test "no declaring surface is the plain input, with no list to bind to", %{conn: conn} do
        view = branch_view(conn, [])

        assert has_element?(view, ~s(input[name="config[arm_beta]"][placeholder="an expression"]))
        refute has_element?(view, "datalist")
        refute has_element?(view, ~s(input[name="config[arm_beta]"][list]))
      end

      # 11k's three surfaces, proven to reach the markup and not just the pure
      # function: the datamodel is supplied here by neither the host's
      # `datamodel` nor its `declare`, but by the document's own key.
      #
      # Sabotage: `path_candidates/1` in `Editor` passing `assigns.declared_paths`
      # alone instead of the document -> this goes red while the first test
      # stays green, which is the split it is drawn to make.
      test "the document's own declarations reach the list", %{conn: conn} do
        view = branch_view(conn, entries: [%DatamodelEntry{id: "signup"}])

        assert has_element?(view, ~s(datalist#sb-field-arm_beta-paths[data-path-candidates="1"]))
        assert has_element?(view, ~s(datalist#sb-field-arm_beta-paths option[value="signup"]))
      end

      # The third surface, and the one a markup test is the only guard for:
      # the compile call's `:declare` roots, which the editor takes as an
      # assign because it has no compile call of its own to read (11k).
      #
      # Sabotage: `path_candidates/1` in `Editor` passing `[]` instead of
      # `assigns.host_roots` -> this goes red and NOTHING ELSE DOES, in the
      # pure suite included. That mutation survived the first draft of this
      # file, which is why this test exists.
      test "the compile call's declare roots reach the list", %{conn: conn} do
        view = branch_view(conn, declare: ["ambient"])

        assert has_element?(view, ~s(datalist#sb-field-arm_beta-paths[data-path-candidates="1"]))
        assert has_element?(view, ~s(datalist#sb-field-arm_beta-paths option[value="ambient"]))
      end

      # Sabotage: rendered the candidates as a `<select>` instead - the control
      # a constraint would use -> this goes red with "value for select
      # config[arm_beta] must be one of ...". A datalist suggests; the gate on
      # what reaches the document stays `validate_config/1`'s (decision 9) and
      # an undeclared path stays an `:info` advisory (11e).
      test "an expression using no offered path still reaches the document", %{conn: conn} do
        view = branch_view(conn, datamodel: @declared)

        view
        |> form(~s(#sb-form-blk_route), %{"config" => %{"arm_beta" => "merchant.risk_tier > 2"}})
        |> render_change()

        assert [%{"slot" => "arm_beta", "cond" => "merchant.risk_tier > 2"}] =
                 latest_document()
                 |> Document.blocks()
                 |> Enum.find(&(&1.id == "blk_route"))
                 |> Map.fetch!(:config)
                 |> Map.fetch!("arms"),
               "a datalist suggests; it never constrains (ADR-0005 decision 9)"
      end

      # Sabotage: dropped the `type: :expression` guard from the new clause so
      # it keyed on `path_candidates` alone -> the `:string` and `:duration`
      # fields on the same form picked up the list and this goes red. The
      # suggestion is a property of the field TYPE, which is the rule the
      # `invoke_type` list is the deliberate exception to.
      test "the list is on the expression field alone", %{conn: conn} do
        view = branch_view(conn, datamodel: @declared)

        refute has_element?(view, ~s(input[name="config[arms]"][list]))
        refute has_element?(view, ~s(.sb-field[data-field-type="string"] input[list]))
      end
    end

    describe "the expression_component seam" do
      defp expression_field do
        %ViewModel.Field{
          key: "cond",
          type: :expression,
          label: "Condition",
          required?: false,
          default: nil,
          value: "signup.step == 2",
          value_path: ["cond"]
        }
      end

      defp render_expression(candidates, component) do
        render_component(&Field.field/1, %{
          field: expression_field(),
          target: "#sb-editor",
          path_candidates: candidates,
          expression_component: component
        })
      end

      # The seam's map is what a host reads, so the assertion is on the map
      # and not on markup the host chose.
      #
      # Sabotage: dropped `candidates:` from the call -> KeyError on
      # `assigns.candidates` and this goes red (verified).
      test "an override is handed the same candidates the datalist would show" do
        component = fn assigns ->
          Phoenix.HTML.raw(~s(<b data-seen="#{Enum.join(assigns.candidates, ",")}"></b>))
        end

        html = render_expression(@declared, component)

        assert html =~ ~s(data-seen="signup.step,signup.variant_id")
      end

      # Sabotage: put the datalist clause ahead of the override clause -> the
      # package's suggestion markup renders beside a host's own control and
      # this goes red. A host that supplied a component asked for its own
      # control; stapling markup beside it would be the package overriding
      # the override.
      test "an override wins over the datalist, and is not decorated" do
        component = fn _assigns -> Phoenix.HTML.raw(~s(<b class="host-editor"></b>)) end

        html = render_expression(@declared, component)

        assert html =~ ~s(class="host-editor")
        refute html =~ "<datalist"
        refute html =~ "sb-field__input--expression"
      end

      # The seam is additive (sb-0vt): an override written before candidates
      # existed takes a map and reads the keys it knows.
      #
      # Sabotage: passed the assigns as a keyword list instead of a map -> the
      # existing one-argument-map contract breaks and this goes red.
      test "an override that ignores candidates still renders" do
        component = fn assigns -> Phoenix.HTML.raw(~s(<i>#{assigns.value}</i>)) end

        assert render_expression(@declared, component) =~ "<i>signup.step == 2</i>"
      end
    end

    # ADR-0005's 2026-09-05 note: a path's value candidates default from the
    # datamodel's declared `one_of`, and the host's map is merged over them
    # per path. The merge itself is pure and is asserted in
    # `StatifierBlocks.DatamodelTest`; what only exists once there is markup
    # is the claim here - that the merged map, and not the host's raw assign,
    # is what the control was handed.
    #
    # The condition these drive is written against a string value, because
    # statifier-ui builds an option only for a candidate it can write at the
    # clause's own value kind: a string candidate offered against `== 2` is
    # not a value that clause could hold, and it is dropped there rather than
    # here. What this file is about is which candidates arrive, so the clause
    # is one that can hold them.
    describe "a condition's value picker" do
      @one_of %{
        "version" => 1,
        "scopes" => [
          %{
            "scope" => "local",
            "entries" => [
              %{
                "path" => "signup.step",
                "type" => "string",
                "one_of" => ["details", "payment", "review"]
              }
            ]
          }
        ]
      }

      @no_one_of %{
        "version" => 1,
        "scopes" => [
          %{
            "scope" => "local",
            "entries" => [%{"path" => "signup.step", "type" => "string"}]
          }
        ]
      }

      defp value_branch_view(conn, opts) do
        document =
          Document.new(
            Block.new("core.branch",
              id: "blk_route",
              config: %{"arms" => [%{"slot" => "arm_beta", "cond" => "signup.step == 'details'"}]},
              slots: %{
                "arm_beta" => [EditorFixtures.wait("blk_beta_step", "5m")],
                "otherwise" => []
              }
            ),
            id: "doc_route"
          )

        {:ok, view, _html} = mount_editor(conn, [document: document] ++ opts)

        select(view, "blk_route")
      end

      defp option(value),
        do: ~s(select[data-role="value"] option[value="signup.step == '#{value}'"])

      # Sabotage: the inspector call in `Editor.render/1` passing the host's
      # raw `@value_candidates` again instead of `@offered_values` -> the map
      # is empty, the control falls back to free text, and this is the test
      # that goes red. It is the one hop the pure suite cannot see.
      test "offers the declared values with no host map supplied", %{conn: conn} do
        view = value_branch_view(conn, datamodel: @one_of)

        assert has_element?(view, ~s(select[data-role="value"][data-value-kind="select"]))

        for value <- ~w(details payment review) do
          assert has_element?(view, option(value))
        end
      end

      # The precedence, at the control: replacement at the path, so a value
      # the host left out is gone rather than merged back in. The author's own
      # value stays whatever the host says, which is statifier-ui's rule and
      # not this package's - hence the refutation on `payment` rather than on
      # the `details` the clause currently holds.
      #
      # Sabotage: `Datamodel.value_candidates/2` unioning the two lists
      # instead of merging the host's over the derived -> the refutation goes
      # red while the assertion above it stays green, which is the split this
      # test is drawn to make.
      test "a host entry for that path replaces the declared values", %{conn: conn} do
        view =
          value_branch_view(conn,
            datamodel: @one_of,
            value_candidates: %{"signup.step" => ["review"]}
          )

        assert has_element?(view, option("review"))
        refute has_element?(view, option("payment"))
      end

      # The third criterion, and the one that says nothing changed for anyone
      # who declares no enumeration: an entry with no `one_of` contributes
      # nothing at all, so the value control is the free-text one it was.
      #
      # Sabotage: `options/1` answering a value for an entry that declares
      # none -> the path acquires a candidate it never declared, the control
      # becomes a picker, and both assertions here go red. Mapping the empty
      # case to `[]` instead of leaving the path out does NOT reach here:
      # statifier-ui reads an empty candidate list as no candidates and draws
      # the same text control, so the pure suite is what guards that one.
      test "a path with no declared values keeps its free-text control", %{conn: conn} do
        view = value_branch_view(conn, datamodel: @no_one_of)

        assert has_element?(view, ~s(input[data-role="value"][data-value-kind="text"]))
        refute has_element?(view, ~s(select[data-role="value"][data-value-kind="select"]))
      end
    end
  end
end
