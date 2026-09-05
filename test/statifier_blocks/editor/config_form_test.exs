# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. The `:liveview` tag on
# `StatifierBlocks.EditorLiveCase` excludes these from a headless *run*; this
# guard is what keeps them out of a headless *compile*, which is the earlier
# of the two problems.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.ConfigFormTest do
    @moduledoc """
    ADR-0005 decision 9 rendered: a form generated from `config_schema/1`, and
    an invalid form that never reaches the document.

    The gate itself is `Edit.check_config/3`'s and was tested with LiveView
    absent. What is asserted here is the shell's half of it: that in-progress
    form state lives in transient assigns, that the author keeps their
    keystrokes while the document keeps the last config that validated, and that
    the findings on screen are about the value being typed rather than the one
    already committed.
    """

    use StatifierBlocks.EditorLiveCase

    alias StatifierBlocks.CoreFixtures
    alias StatifierBlocks.Editor.ConfigForm
    alias StatifierBlocks.ViewModel

    defp select(view, id) do
      view
      |> element(~s([data-block-id="#{id}"] > .sb-node__chrome > .sb-node__label))
      |> render_click()

      view
    end

    defp config(document, id) do
      document |> Document.blocks() |> Enum.find(&(&1.id == id)) |> Map.fetch!(:config)
    end

    describe "generated controls" do
      # ADR-0005 decision 9 as amended 2026-08-29: one text control, and the
      # examples on screen because they are what replaces the affordance the
      # retired unit dropdown carried.
      #
      # Sabotage: dropped the examples paragraph from `Field.control/1`'s
      # `:duration` clause -> 1 failure, on the last assertion alone, with the
      # first three green: the split this test is drawn to make (verified).
      test "a :duration field is one text control with the examples on screen", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)
        view = select(view, "blk_email_step")

        assert has_element?(view, ~s([data-field="duration"][data-field-type="duration"]))
        assert has_element?(view, ~s(input[type="text"][name="config[duration]"][value="1h"]))
        refute has_element?(view, ~s(select[name="config[duration][unit]"]))
        assert render(view) =~ "Try 30s, 15m, 1h30m, 2d, 3d8h"
      end

      # Sabotage: `ViewModel.build_fields/3` caching the schema instead of
      # re-deriving it - the branch's per-arm field would not appear at all.
      test "a branch's per-arm field is derived from its current config", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)
        view = select(view, "blk_variant")

        assert has_element?(view, ~s([data-field="arm_variant_b"][data-field-type="expression"]))
      end

      test "an unresolvable block has no form to generate", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)
        view = select(view, "blk_track_conversion")

        refute has_element?(view, ".sb-form")
      end
    end

    describe "the invoke_type suggestion list" do
      @types ["myapp:authorize", "myapp:capture", "myapp:signup"]

      defp invoke_view(conn, opts) do
        {:ok, view, _html} =
          mount_editor(conn, [document: EditorFixtures.invoke_step()] ++ opts)

        select(view, "blk_authorize")
      end

      # Sabotage: dropped `list={@list_id}` from the invoke_type input -> 1
      # failure, on the binding assertion alone: the datalist can exist and
      # still be attached to nothing, which is the defect worth catching.
      test "the host's types render as a datalist the input is bound to", %{conn: conn} do
        view = invoke_view(conn, invoke_types: @types)

        assert has_element?(
                 view,
                 ~s(input[name="config[invoke_type]"][list="sb-field-invoke_type-types"])
               )

        assert has_element?(view, ~s(datalist#sb-field-invoke_type-types[data-invoke-types="3"]))

        for type <- @types do
          assert has_element?(
                   view,
                   ~s(datalist#sb-field-invoke_type-types option[value="#{type}"])
                 )
        end
      end

      # Sabotage: widened the clause's `[_first | _rest]` to `_any` -> 1
      # failure here: an empty list rendered an empty `<datalist>`, which is
      # markup that suggests nothing and only adds an element to trip over.
      test "no types supplied is a plain input, with no list to bind to", %{conn: conn} do
        view = invoke_view(conn, [])

        assert has_element?(view, ~s(input[name="config[invoke_type]"]))
        refute has_element?(view, "datalist")
        refute has_element?(view, ~s(input[name="config[invoke_type]"][list]))
      end

      # Sabotage: rendered the types as a `<select>` instead - the control a
      # constraint would use -> this goes red with "value for select
      # config[invoke_type] must be one of ...", which is decision 8's whole
      # point stated by the failure.
      test "a type that is on no list still reaches the document", %{conn: conn} do
        view = invoke_view(conn, invoke_types: @types)

        view
        |> form(~s(#sb-form-blk_authorize), %{
          "config" => %{"invoke_type" => "myapp:refund"}
        })
        |> render_change()

        assert config(latest_document(), "blk_authorize")["invoke_type"] == "myapp:refund",
               "a datalist suggests; it never constrains (ADR-0004 decision 8)"
      end

      # Sabotage: dropped `key: "invoke_type"` from the clause head -> 1
      # failure here: every string field on the block picked up the list.
      test "the list is keyed on invoke_type alone, not on every string field", %{conn: conn} do
        view = invoke_view(conn, invoke_types: @types)

        refute has_element?(view, ~s(input[name="config[assign_to]"][list])),
               "a sibling :string field on the same block carries no suggestion list"
      end
    end

    describe "the fixture hint (ADR-0005's 2026-09-05 note)" do
      defp decision_view(conn, opts) do
        {:ok, view, _html} =
          mount_editor(conn, [document: EditorFixtures.credit_card()] ++ opts)

        select(view, "blk_cc_decision")
      end

      defp hint(view, key) do
        element(view, ~s([data-field="#{key}"] .sb-field__fixture-hint))
      end

      # `credit_card_tables/0`'s four rows bind `amount` as 120, 900, 900 and
      # 120. The first row in declaration order is the small one, so the
      # exemplar is 120 - not the most common value, which is a tie, and not
      # the most recent, which is the fourth row's.
      #
      # Sabotage: passed `fixtures={nil}` from `Inspector.config_panel/1`
      # instead of `@fixtures` - this test and the title one below both went
      # red, which is what makes this the threading test as well as the
      # exemplar one: the two positive assertions in this describe are the
      # two that can tell a broken thread from an absent hint.
      test "the exemplar is the first fixture row's value for the path the source names",
           %{conn: conn} do
        view = decision_view(conn, fixtures: EditorFixtures.credit_card_tables())

        assert has_element?(view, ~s([data-field="arm_review"] [data-fixture-hint="amount"]))
        assert render(hint(view, "arm_review")) =~ "120"

        assert has_element?(view, ~s([data-field="arm_declined"] [data-fixture-hint="risk_band"]))
        assert render(hint(view, "arm_declined")) =~ "&#39;low&#39;"
      end

      # The whole set, de-duplicated: `amount` takes 120 twice and 900 twice
      # across the four rows and the title lists two values, and `risk_band`
      # is bound by three of the four rows and lists two.
      #
      # Sabotage: dropped `Enum.uniq/1` from `Shell.hint_values/2`, so the
      # title joined the raw row values and read "120, 900, 900, 120" - four
      # entries for two values, which is the summary the `title` exists to be
      # instead of. This went red.
      test "the title lists every distinct value, once each", %{conn: conn} do
        view = decision_view(conn, fixtures: EditorFixtures.credit_card_tables())

        assert has_element?(
                 view,
                 ~s([data-field="arm_review"] .sb-field__fixture-hint[title="120, 900"])
               )

        assert has_element?(
                 view,
                 ~s([data-field="arm_declined"] .sb-field__fixture-hint[title="'low', 'high'"])
               )
      end

      # The record's silence rather than an empty affordance: no element at
      # all, so there is no empty title and no empty text for a reader or a
      # screen reader to trip over.
      #
      # Sabotage: `Shell.fixture_hint/3` answering `%{path: "", value: "",
      # values: []}` instead of nil for a block with no rows - the element was
      # drawn with an empty `title` and no value, which is precisely the empty
      # affordance the record calls silence instead. This went red.
      test "a block with no fixture rows draws no hint at all", %{conn: conn} do
        no_source = decision_view(conn, [])
        refute has_element?(no_source, ".sb-field__fixture-hint")
        refute render(no_source) =~ "title=\"\""

        empty_source = decision_view(conn, fixtures: %{"blk_cc_decision" => []})
        refute has_element?(empty_source, ".sb-field__fixture-hint")

        other_block = decision_view(conn, fixtures: %{"blk_other" => []})
        refute has_element?(other_block, ".sb-field__fixture-hint")
      end

      # A hint is never an option. The values reach the page as text and as a
      # `title`, and nowhere else: not as an `<option>` in the field's own
      # `<datalist>`, not as a `<select>` choice, not merged into the
      # `value_candidates` the expression seam is handed.
      # Sabotage: drew the hint's values as a `<datalist>` of options beside
      # the element as well - the shortest possible route from hint to option,
      # and the one an author reading only the bead title might take. This
      # went red, which is what makes the refutation load-bearing rather than
      # a restatement of the implementation.
      test "no fixture value is selectable anywhere on the form", %{conn: conn} do
        view = decision_view(conn, fixtures: EditorFixtures.credit_card_tables())

        html = render(view)

        refute html =~ ~s(<option value="120")
        refute html =~ ~s(<option value="900")
        refute html =~ ~s(<option value="&#39;low&#39;")
        refute html =~ ~s(<option value="&#39;high&#39;")
      end

      # The hint is an `:expression` field's alone. `blk_cc_capture_pause` is
      # a wait, so its `:duration` control keeps the placeholder rule the
      # `Field` moduledoc closes and gains nothing beside it.
      #
      # Sabotage: dropped the `type: :expression` guard from `ConfigForm`'s
      # own `fixture_hint/3`, so every field type got one - the wait's
      # duration control grew a hint about a path it does not read. This went
      # red.
      test "a field that is not an :expression draws no hint", %{conn: conn} do
        {:ok, view, _html} =
          mount_editor(conn,
            document: EditorFixtures.credit_card(),
            fixtures: %{
              "blk_cc_capture_pause" => EditorFixtures.credit_card_tables()["blk_cc_decision"]
            }
          )

        view = select(view, "blk_cc_capture_pause")

        assert has_element?(view, ~s([data-field="duration"][data-field-type="duration"]))
        refute has_element?(view, ".sb-field__fixture-hint")
      end
    end

    describe "the d9 gate" do
      # Sabotage: `Editor.change_config/3` committing on the `:invalid_config`
      # arm - the unparseable duration reaches the document and this goes red.
      test "config that does not validate never reaches the document", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)
        view = select(view, "blk_email_step")

        view
        |> form(~s(#sb-form-blk_email_step), %{
          "config" => %{"duration" => "x"}
        })
        |> render_change()

        refute latest_document(), "an invalid change is not a document change"
      end

      # Sabotage: `Editor.apply_draft/3` returning the node unchanged - the
      # author's in-progress value is replaced by the committed one on the next
      # render, which is the keystroke-eating bug this overlay exists to avoid.
      test "the author keeps their keystrokes while the document keeps the last valid config",
           %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)
        view = select(view, "blk_email_step")

        html =
          view
          |> form(~s(#sb-form-blk_email_step), %{
            "config" => %{"duration" => "x"}
          })
          |> render_change()

        assert html =~ ~s(name="config[duration]" value="x"),
               "the draft is what renders, in the one control the field now has"

        assert html =~ "must be a duration",
               "the finding is about the value being typed, not the one committed"
      end

      # Sabotage: `Editor.change_config/3` not deleting the draft on a
      # successful commit - the stale draft keeps overlaying the committed value.
      test "a change that validates commits, and clears the draft", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)
        view = select(view, "blk_email_step")

        view
        |> form(~s(#sb-form-blk_email_step), %{
          "config" => %{"duration" => "x"}
        })
        |> render_change()

        html =
          view
          |> form(~s(#sb-form-blk_email_step), %{"config" => %{"duration" => "45m"}})
          |> render_change()

        assert config(latest_document(), "blk_email_step") == %{"duration" => "45m"}
        refute html =~ "must be a duration"
      end

      # Sabotage: `Editor.replay/2` keeping `drafts` across a history move - the
      # undone document would render with a draft belonging to a state it just
      # stepped out of.
      test "undo drops drafts, because a draft belongs to a document state", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)
        view = select(view, "blk_email_step")

        view
        |> form(~s(#sb-form-blk_email_step), %{
          "config" => %{"duration" => "45m"}
        })
        |> render_change()

        view
        |> form(~s(#sb-form-blk_email_step), %{
          "config" => %{"duration" => "x"}
        })
        |> render_change()

        html = view |> element(~s(button[phx-click="undo"])) |> render_click()

        assert config(latest_document(), "blk_email_step") == %{"duration" => "1h"}
        refute html =~ "must be a duration"
      end

      # Sabotage: `ConfigForm.decode/3` starting from `%{}` instead of `base` -
      # the branch's "arms" key is deleted by the very first form change, which
      # is silent data loss and the reason this test exists. The arm's `"slot"`
      # is the witness: it sits beside the one value the form does edit, and
      # nothing in the schema names it.
      test "a config key the schema does not name survives an edit", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)
        view = select(view, "blk_variant")

        view
        |> form(~s(#sb-form-blk_variant), %{"config" => %{"arm_variant_b" => "variant == 'c'"}})
        |> render_change()

        assert config(latest_document(), "blk_variant") == %{
                 "arms" => [%{"slot" => "arm_variant_b", "cond" => "variant == 'c'"}]
               }
      end
    end

    describe "a field whose value lives elsewhere (ADR-0002 d7's value_path)" do
      # sabotage: `ViewModel.build_fields/3` reading `Map.get(config, key, default)`
      # rather than the declared path - the condition input renders empty.
      test "a branch arm's condition renders its stored value", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)
        view = select(view, "blk_variant")

        assert has_element?(
                 view,
                 ~s(input[name="config[arm_variant_b]"][value="variant == 'b'"])
               )
      end

      # sabotage: `ConfigForm.decode/3` writing `Map.put(config, field.key, value)`
      # - the arm keeps its old condition and a junk top-level key appears.
      test "editing it writes into the arm and creates no top-level key", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)
        view = select(view, "blk_variant")

        view
        |> form(~s(#sb-form-blk_variant), %{"config" => %{"arm_variant_b" => "variant == 'c'"}})
        |> render_change()

        config = config(latest_document(), "blk_variant")

        assert config == %{"arms" => [%{"slot" => "arm_variant_b", "cond" => "variant == 'c'"}]}
        refute Map.has_key?(config, "arm_variant_b")
      end

      # sabotage: `Core.Branch.config_schema/1` numbering arms by their position
      # among the well-formed ones - the second arm renders the first's junk.
      # The config here is one `validate_config/1` rejects, which is exactly
      # when the two numberings diverge and exactly what an author is looking
      # at mid-edit.
      test "the path names the arm's stored index, not its filtered one", %{conn: conn} do
        document =
          Document.new(
            Block.new("core.branch",
              id: "blk_skewed",
              config: %{
                "arms" => [
                  %{"slot" => "not_an_arm", "cond" => "junk"},
                  %{"slot" => "arm_second", "cond" => "x == 1"}
                ]
              },
              slots: %{
                "arm_second" => [EditorFixtures.wait("blk_second_step", "5m")],
                "otherwise" => []
              }
            ),
            id: "doc_skewed"
          )

        {:ok, view, _html} = mount_editor(conn, document: document)
        view = select(view, "blk_skewed")

        assert has_element?(view, ~s(input[name="config[arm_second]"][value="x == 1"]))
        refute has_element?(view, ~s(input[name="config[arm_second]"][value="junk"]))
      end
    end

    describe "a :duration control" do
      # The amendment's "the stored form is the author's string verbatim".
      # `3h2h` is the witness: it normalises to `5h` at emit time, so a
      # control that canonicalised on the way in would store the wrong
      # bytes.
      #
      # Sabotage: normalised the typed value through `Core.Duration` in
      # `Field.decode/2` -> `3h2h` was stored as `5h` and the assertion
      # went red (verified).
      test "stores the author's string verbatim, whatever it normalises to", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: sending_document())
        view = select(view, "blk_abandon")

        for typed <- ["1h30m", "2h", "3d8h", "3h2h", "1.5s"] do
          view
          |> form(~s(#sb-form-blk_abandon), %{"config" => %{"delay" => typed}})
          |> render_change()

          assert config(latest_document(), "blk_abandon") ==
                   %{"event" => "signup.abandoned", "delay" => typed}
        end
      end

      # Sabotage: made `omitted?/2` return false for every value -> the
      # committed config grew a `"delay" => ""` key and 4 tests went red, the
      # decode/3 cases below among them (verified).
      test "an empty field omits the key, and never-set reads the same", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: sending_document())
        view = select(view, "blk_abandon")

        view
        |> form(~s(#sb-form-blk_abandon), %{"config" => %{"delay" => ""}})
        |> render_change()

        assert config(latest_document(), "blk_abandon") == %{"event" => "signup.abandoned"},
               "a cleared duration is an absent key, not a zero and not an empty string"

        assert has_element?(view, ~s(input[name="config[delay]"][value=""])),
               "and a never-set field renders exactly as the cleared one does"
      end

      # The inline check is EARLIER than decision 9's gate, not a second one:
      # it tells the author the text is not a duration while they are still
      # typing, and the gate still decides what reaches the document. Clause
      # 9d is why there is one sentence rather than a family of them: with
      # one grammar there is one thing to be wrong about, and the sentence
      # names what is accepted rather than what was retired.
      #
      # Sabotage: dropped the refusal paragraph from `Field.control/1` -> the
      # sentence never rendered, this test went red on its first case, and the
      # gate's own refusal stayed green beside it (verified).
      test "refuses a bad format inline, naming only what is accepted", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: sending_document())
        view = select(view, "blk_abandon")

        for typed <- ["soon", "2dx", "60"] ++ CoreFixtures.retired_durations() do
          html =
            view
            |> form(~s(#sb-form-blk_abandon), %{"config" => %{"delay" => typed}})
            |> render_change()

          assert html =~ "Not a duration. Try 30s, 15m, 1h30m, 2d, 3d8h.", typed
          assert html =~ ~s(data-duration-refusal), typed
        end
      end

      # The two spellings the retired intermediate form could not express
      # are accepted now, and the control shows no refusal for either.
      #
      # Sabotage: reinstated the sub-second refusal in `DurationInput` ->
      # both values below grew a refusal paragraph (verified).
      test "a sub-second or fractional duration is accepted inline", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: sending_document())
        view = select(view, "blk_abandon")

        for typed <- ["500ms", "1.5s"] do
          html =
            view
            |> form(~s(#sb-form-blk_abandon), %{"config" => %{"delay" => typed}})
            |> render_change()

          refute html =~ ~s(data-duration-refusal), typed
        end
      end

      # Sabotage: hard-coded the control's `value` to `""` -> the stored `1y`
      # vanished from the form rather than being shown, and 3 tests went red
      # including this one (verified).
      test "a stored duration the control did not author is still shown", %{conn: conn} do
        document =
          Document.new(
            Block.new("core.wait", id: "blk_odd", config: %{"duration" => "1y"}),
            id: "doc_odd"
          )

        {:ok, view, _html} = mount_editor(conn, document: document)
        view = select(view, "blk_odd")

        assert has_element?(view, ~s(input[name="config[duration]"][value="1y"]))
        refute has_element?(view, ~s(input[name="config[duration][value]"]))
      end
    end

    describe "ConfigForm.decode/2" do
      # Sabotage: `decode/2` keying off the params rather than the schema - the
      # injected key would land in the config.
      test "carries the base config forward, so an unschema'd key is not deleted" do
        fields = [field("duration", :duration, "1h")]
        base = %{"duration" => "1h", "arms" => [%{"slot" => "arm_b", "cond" => "x"}]}
        params = %{"config" => %{"duration" => "5m"}}

        assert ConfigForm.decode(fields, params, base) == %{
                 "duration" => "5m",
                 "arms" => [%{"slot" => "arm_b", "cond" => "x"}]
               }
      end

      test "is keyed off the schema, so a param the schema does not name cannot land" do
        fields = [field("duration", :duration, "1h")]

        params = %{
          "config" => %{
            "duration" => "5m",
            "injected" => "not a field"
          }
        }

        assert ConfigForm.decode(fields, params, %{}) == %{"duration" => "5m"}
      end

      # Sabotage: `decode/2`'s `:error` arm falling back to the field's default
      # rather than its current value - a control that did not post would reset.
      test "a field whose control did not post keeps the value it already had" do
        fields = [field("duration", :duration, "2h"), field("label", :string, "Welcome")]
        params = %{"config" => %{"duration" => "5m"}}

        assert ConfigForm.decode(fields, params, %{}) == %{
                 "duration" => "5m",
                 "label" => "Welcome"
               }
      end

      # Sabotage: `Field.decode/2`'s `:integer` arm coercing a bad parse to 0 -
      # the author's text would be silently replaced by a value they never typed.
      test "an integer that does not parse stays the text the author typed" do
        fields = [field("attempts", :integer, 3)]

        assert ConfigForm.decode(fields, %{"config" => %{"attempts" => "three"}}, %{}) ==
                 %{"attempts" => "three"}

        assert ConfigForm.decode(fields, %{"config" => %{"attempts" => "4"}}, %{}) == %{
                 "attempts" => 4
               }
      end

      test "a checkbox posts its hidden false and its checked true, and true wins" do
        fields = [field("shuffle_variants", :boolean, false)]

        assert ConfigForm.decode(fields, %{"config" => %{"shuffle_variants" => "true"}}, %{}) ==
                 %{"shuffle_variants" => true}

        assert ConfigForm.decode(fields, %{"config" => %{"shuffle_variants" => "false"}}, %{}) ==
                 %{"shuffle_variants" => false}
      end

      test "a list decodes each row through its element type" do
        fields = [field("weights", {:list, :integer}, [])]

        assert ConfigForm.decode(fields, %{"config" => %{"weights" => ["50", "50"]}}, %{}) ==
                 %{"weights" => [50, 50]}
      end

      # sabotage: `decode/3` writing `Map.put(config, field.key, value)` - the
      # arm keeps "x" and a top-level "arm_b" appears beside it.
      test "a field with a value_path writes through the path, not the key" do
        fields = [field("arm_b", :expression, "x", ["arms", 0, "cond"])]
        base = %{"arms" => [%{"slot" => "arm_b", "cond" => "x"}]}

        assert ConfigForm.decode(fields, %{"config" => %{"arm_b" => "y"}}, base) ==
                 %{"arms" => [%{"slot" => "arm_b", "cond" => "y"}]}
      end

      # sabotage: `BlockType.put_value/3` requiring the last segment to exist -
      # an arm that has no condition yet could never be given one.
      test "a value_path writes a value the config did not have yet" do
        fields = [field("arm_b", :expression, "", ["arms", 0, "cond"])]
        base = %{"arms" => [%{"slot" => "arm_b"}]}

        assert ConfigForm.decode(fields, %{"config" => %{"arm_b" => "y"}}, base) ==
                 %{"arms" => [%{"slot" => "arm_b", "cond" => "y"}]}
      end

      # sabotage: `put_value/3` creating the intermediate structure it did not
      # find - a form control would invent a shape the block type never wrote.
      test "a value_path that leads nowhere leaves the config alone" do
        fields = [field("arm_b", :expression, "", ["arms", 3, "cond"])]

        assert ConfigForm.decode(fields, %{"config" => %{"arm_b" => "y"}}, %{"other" => 1}) ==
                 %{"other" => 1}
      end
    end

    describe "an omitted :duration key" do
      # Sabotage: made `omitted?/2` return false for every value -> the empty
      # duration landed as `""` and 4 tests went red, this file's two other
      # omission cases among them (verified).
      test "an empty duration deletes its key rather than storing an emptiness" do
        fields = [field("delay", :duration, "1h")]
        base = %{"event" => "signup.abandoned", "delay" => "1h"}

        assert ConfigForm.decode(fields, %{"config" => %{"delay" => ""}}, base) ==
                 %{"event" => "signup.abandoned"}
      end

      test "a key that was never there stays absent, rather than being created" do
        fields = [field("delay", :duration, "")]

        assert ConfigForm.decode(fields, %{"config" => %{"delay" => ""}}, %{"event" => "x"}) ==
                 %{"event" => "x"}
      end

      # The omission follows `value_path`, like every other write. Deleting a
      # top-level key of the same name would be silent data loss beside the
      # value the author actually cleared.
      test "a nested duration deletes only its own key at its own path" do
        fields = [field("arm_wait", :duration, "1h", ["arms", 0, "delay"])]
        base = %{"delay" => "9h", "arms" => [%{"slot" => "arm_b", "delay" => "1h"}]}

        assert ConfigForm.decode(fields, %{"config" => %{"arm_wait" => ""}}, base) ==
                 %{"delay" => "9h", "arms" => [%{"slot" => "arm_b"}]}
      end

      test "a path naming something that is not there leaves the config alone" do
        fields = [field("arm_wait", :duration, "1h", ["arms", 3, "delay"])]

        assert ConfigForm.decode(fields, %{"config" => %{"arm_wait" => ""}}, %{"other" => 1}) ==
                 %{"other" => 1}
      end

      # Only `:duration` omits. A `:string` that is emptied is a stored empty
      # string, which is a value its type may well accept.
      test "no other field type omits its key when it is emptied" do
        fields = [field("label", :string, "Welcome")]

        assert ConfigForm.decode(fields, %{"config" => %{"label" => ""}}, %{}) ==
                 %{"label" => ""}
      end
    end

    # A `core.send` whose delay the author edits. `core.send` is the block
    # type that already reads both stored spellings, so it is where a
    # predicator string can be committed without waiting on `core.wait`.
    defp sending_document do
      Document.new(
        Block.new("core.send", id: "blk_abandon", config: %{"event" => "signup.abandoned"}),
        id: "doc_abandon"
      )
    end

    defp field(key, type, value, value_path \\ nil) do
      %ViewModel.Field{
        key: key,
        type: type,
        label: key,
        required?: false,
        default: value,
        value: value,
        value_path: value_path
      }
    end
  end
end
