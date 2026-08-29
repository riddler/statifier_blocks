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
        assert has_element?(view, ~s(input[type="text"][name="config[duration]"][value="PT1H"]))
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
          |> form(~s(#sb-form-blk_email_step), %{"config" => %{"duration" => "PT45M"}})
          |> render_change()

        assert config(latest_document(), "blk_email_step") == %{"duration" => "PT45M"}
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
          "config" => %{"duration" => "PT45M"}
        })
        |> render_change()

        view
        |> form(~s(#sb-form-blk_email_step), %{
          "config" => %{"duration" => "x"}
        })
        |> render_change()

        html = view |> element(~s(button[phx-click="undo"])) |> render_click()

        assert config(latest_document(), "blk_email_step") == %{"duration" => "PT1H"}
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
                "arm_second" => [EditorFixtures.wait("blk_second_step", "PT5M")],
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
      # `core.send` is the block type that reads both spellings today, so it
      # is what a predicator string can be committed through.
      #
      # Sabotage: canonicalised the typed value through `Core.Duration.to_iso/1`
      # in `Field.decode/2` -> `1h30m` was stored as `PT1H30M` and the second
      # assertion went red (verified).
      test "stores the author's string verbatim, in either spelling", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: sending_document())
        view = select(view, "blk_abandon")

        for typed <- ["1h30m", "PT2H", "3d8h"] do
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
               "a cleared duration is an absent key, not PT0S and not an empty string"

        assert has_element?(view, ~s(input[name="config[delay]"][value=""])),
               "and a never-set field renders exactly as the cleared one does"
      end

      # The inline check is EARLIER than decision 9's gate, not a second one:
      # it says which spelling the author is failing while they are still
      # typing, and the gate still decides what reaches the document.
      #
      # Sabotage: dropped the refusal paragraph from `Field.control/1` -> the
      # sentence never rendered, this test went red on its first case, and the
      # gate's own refusal stayed green beside it (verified).
      test "refuses a bad format inline, with the limit that was hit", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: sending_document())
        view = select(view, "blk_abandon")

        for {typed, sentence} <- [
              {"soon", "Not a duration. Try 30s, 15m, 1h30m, 2d, 3d8h"},
              {"500ms", "Milliseconds are not stored here"},
              {"1.5s", "leaves milliseconds"}
            ] do
          html =
            view
            |> form(~s(#sb-form-blk_abandon), %{"config" => %{"delay" => typed}})
            |> render_change()

          assert html =~ sentence, typed
          assert html =~ ~s(data-duration-refusal), typed
        end
      end

      # Sabotage: hard-coded the control's `value` to `""` -> the stored `P1Y`
      # vanished from the form rather than being shown, and 3 tests went red
      # including this one (verified).
      test "a stored duration the control did not author is still shown", %{conn: conn} do
        document =
          Document.new(
            Block.new("core.wait", id: "blk_odd", config: %{"duration" => "P1Y"}),
            id: "doc_odd"
          )

        {:ok, view, _html} = mount_editor(conn, document: document)
        view = select(view, "blk_odd")

        assert has_element?(view, ~s(input[name="config[duration]"][value="P1Y"]))
        refute has_element?(view, ~s(input[name="config[duration][value]"]))
      end
    end

    describe "ConfigForm.decode/2" do
      # Sabotage: `decode/2` keying off the params rather than the schema - the
      # injected key would land in the config.
      test "carries the base config forward, so an unschema'd key is not deleted" do
        fields = [field("duration", :duration, "PT1H")]
        base = %{"duration" => "PT1H", "arms" => [%{"slot" => "arm_b", "cond" => "x"}]}
        params = %{"config" => %{"duration" => "PT5M"}}

        assert ConfigForm.decode(fields, params, base) == %{
                 "duration" => "PT5M",
                 "arms" => [%{"slot" => "arm_b", "cond" => "x"}]
               }
      end

      test "is keyed off the schema, so a param the schema does not name cannot land" do
        fields = [field("duration", :duration, "PT1H")]

        params = %{
          "config" => %{
            "duration" => "PT5M",
            "injected" => "not a field"
          }
        }

        assert ConfigForm.decode(fields, params, %{}) == %{"duration" => "PT5M"}
      end

      # Sabotage: `decode/2`'s `:error` arm falling back to the field's default
      # rather than its current value - a control that did not post would reset.
      test "a field whose control did not post keeps the value it already had" do
        fields = [field("duration", :duration, "PT2H"), field("label", :string, "Welcome")]
        params = %{"config" => %{"duration" => "PT5M"}}

        assert ConfigForm.decode(fields, params, %{}) == %{
                 "duration" => "PT5M",
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
        fields = [field("delay", :duration, "PT1H")]
        base = %{"event" => "signup.abandoned", "delay" => "PT1H"}

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
        fields = [field("arm_wait", :duration, "PT1H", ["arms", 0, "delay"])]
        base = %{"delay" => "PT9H", "arms" => [%{"slot" => "arm_b", "delay" => "PT1H"}]}

        assert ConfigForm.decode(fields, %{"config" => %{"arm_wait" => ""}}, base) ==
                 %{"delay" => "PT9H", "arms" => [%{"slot" => "arm_b"}]}
      end

      test "a path naming something that is not there leaves the config alone" do
        fields = [field("arm_wait", :duration, "PT1H", ["arms", 3, "delay"])]

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
