# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. The pure half of these flags -
# the two declaration refusals, the view model's two booleans, and a hidden
# value's route to the SCXML - lives in
# `StatifierBlocks.Compiler.FieldDeclarationTest`, deliberately outside this
# guard.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.FieldFlagsTest do
    @moduledoc """
    `hidden?` and `readonly?` at the form (ADR-0002 decision 7, amended
    2026-09-07, sections F1 and F6, with campaign-SF036 ruling `RQ-SF036-15`).

    The document is the amendment's own worked example in the signup domain:
    a step name the host owns and a variant seed the host assigns, beside one
    ordinary field so there is something for an author to change.

    Three claims only exist once there is markup and a socket. A readonly
    field draws its value where a control would sit and posts nothing. A
    hidden field draws nothing at all. And a crafted payload posting under
    either key changes nothing, because the decode takes the unposted branch
    for a flagged field whatever the params carry - which is the one decode
    change F6 names, on top of the three properties it says are already
    enough to *keep* the value.
    """

    use StatifierBlocks.EditorLiveCase

    alias StatifierBlocks.Editor.{ConfigForm, Field}
    alias StatifierBlocks.{Palette, ViewModel}

    defmodule Seeded do
      @moduledoc """
      The amendment's worked example, plus an ordinary `note` field: a
      readonly step name, a hidden variant seed, and one control an author
      can actually type into.
      """
      @behaviour StatifierBlocks.BlockType

      alias StatifierBlocks.Compiler.Context
      alias StatifierBlocks.Core.Emit

      @impl true
      def current_version, do: 1
      @impl true
      def slots(_config), do: []

      @impl true
      def config_schema(_config) do
        [
          %{
            key: "step_name",
            type: :string,
            label: "Step",
            required?: true,
            default: "Collect email",
            readonly?: true
          },
          %{
            key: "variant_seed",
            type: :string,
            label: "Variant seed",
            required?: false,
            default: "control",
            hidden?: true
          },
          %{key: "note", type: :string, label: "Note", required?: false, default: ""}
        ]
      end

      @impl true
      def validate_config(_config), do: :ok

      @impl true
      def emit(_block, %Context{} = context) do
        done = Context.done_id(context)
        {:ok, Emit.state(context.state_id, done, [Emit.final(done)])}
      end
    end

    @config %{"step_name" => "Collect email", "variant_seed" => "cohort_b", "note" => "first"}

    defp document do
      Document.new(
        Block.new("core.sequence",
          id: "blk_wizard",
          slots: %{"body" => [Block.new("signup.seeded", id: "blk_seed", config: @config)]}
        ),
        id: "doc_signup_seeded"
      )
    end

    defp palette do
      Palette.new(Map.merge(Palette.core_types(), %{"signup.seeded" => Seeded}))
    end

    defp select_seed(conn) do
      {:ok, view, _html} = mount_editor(conn, document: document(), palette: palette())

      view
      |> element(~s([data-block-id="blk_seed"] > .sb-node__chrome > .sb-node__label))
      |> render_click()

      view
    end

    defp config(document, id) do
      document |> Document.blocks() |> Enum.find(&(&1.id == id)) |> Map.fetch!(:config)
    end

    defp field(key, value, flags \\ []) do
      %ViewModel.Field{
        key: key,
        type: :string,
        label: key,
        required?: false,
        default: "",
        value: value,
        hidden?: Keyword.get(flags, :hidden?, false),
        readonly?: Keyword.get(flags, :readonly?, false)
      }
    end

    describe "Field.field/1 on its own" do
      # Sabotage: dropped the `hidden?: true` clause from `Field.field/1` -
      # red here. It is not red through the mounted form, because
      # `ConfigForm`'s own filter withholds the field before the renderer
      # sees it; this is the renderer's half asserted where the form is not
      # in the way.
      test "renders nothing at all for a hidden field" do
        assert render_component(&Field.field/1,
                 field: field("variant_seed", "cohort_b", hidden?: true),
                 target: self()
               ) =~
                 ~r/\A\s*\z/
      end

      # Sabotage: dropped the `readonly?: true` clause - red, because the
      # ordinary renderer draws an input rather than the value.
      test "renders label and value, and no control, for a readonly field" do
        html =
          render_component(&Field.field/1,
            field: field("step_name", "Collect email", readonly?: true),
            target: self()
          )

        assert html =~ "Collect email"
        assert html =~ ~s(data-field-readonly="true")
        refute html =~ "<input"
        refute html =~ "<select"
      end
    end

    describe "a readonly field" do
      # Sabotage: dropped the `readonly?: true` clause from `Field.field/1` so
      # the ordinary renderer runs - red on both halves: the value paragraph
      # is gone and a text input appears under the key an author must not be
      # able to type into.
      test "renders its value beside its label, and no control at all", %{conn: conn} do
        view = select_seed(conn)

        assert has_element?(view, ~s([data-field="step_name"][data-field-readonly="true"]))
        assert has_element?(view, ~s([data-field="step_name"] .sb-field__value), "Collect email")
        assert has_element?(view, ~s([data-field="step_name"] .sb-field__label-text), "Step")

        refute has_element?(view, ~s(input[name="config[step_name]"]))
        refute has_element?(view, ~s([data-field="step_name"] input))
        refute has_element?(view, ~s([data-field="step_name"] select))
      end

      # Sabotage: rendered the value as a `readonly` attribute on the ordinary
      # input instead - red, because a `readonly` input is still a form
      # control and still posts, which F1 says this is not.
      test "is not a disabled or readonly input", %{conn: conn} do
        view = select_seed(conn)

        refute has_element?(view, ~s([data-field="step_name"] input[readonly]))
        refute has_element?(view, ~s([data-field="step_name"] input[disabled]))
      end
    end

    describe "a hidden field" do
      # Sabotage: dropped BOTH `ConfigForm`'s `rendered_fields/1` filter and
      # `Field.field/1`'s `hidden?: true` clause - red. Either one alone
      # leaves this markup unchanged, because each withholds the field on its
      # own; the record states the rule on both surfaces (F1 for the
      # renderer, F7 for the form that filters what it draws), and the
      # renderer's half is asserted alone in the component tests above.
      test "renders nothing: no row, no label, no control", %{conn: conn} do
        view = select_seed(conn)

        refute has_element?(view, ~s([data-field="variant_seed"]))
        refute has_element?(view, ~s(input[name="config[variant_seed]"]))
        refute render(view) =~ "Variant seed"
      end

      # Sabotage: had `ViewModel.build_fields/3` drop hidden fields - red in
      # `FieldDeclarationTest`, which is where the projection is asserted.
      # This test is only that a form drawing no hidden row still draws the
      # ordinary ones.
      test "is still in the view model the form was handed", %{conn: conn} do
        view = select_seed(conn)

        refute has_element?(view, ~s([data-field="variant_seed"]))
        assert has_element?(view, ~s([data-field="note"] input))
      end
    end

    describe "ConfigForm.decode/3 with a flagged field" do
      # Sabotage: restored `Map.fetch(posted, field.key)` in place of
      # `posted_value/2` - red, because the crafted value then lands in the
      # config through a control no form ever drew.
      test "ignores a value posted under a hidden field's key" do
        fields = [field("note", "first"), field("variant_seed", "cohort_b", hidden?: true)]
        base = %{"note" => "first", "variant_seed" => "cohort_b"}

        params = %{"config" => %{"note" => "second", "variant_seed" => "tampered"}}

        assert ConfigForm.decode(fields, params, base) == %{
                 "note" => "second",
                 "variant_seed" => "cohort_b"
               }
      end

      # Sabotage: gave `posted_value/2` only the `hidden?` clause - red, since
      # `RQ-SF036-15` names both flags and a readonly field posts nothing
      # either.
      test "ignores a value posted under a readonly field's key" do
        fields = [field("step_name", "Collect email", readonly?: true)]
        params = %{"config" => %{"step_name" => "Renamed by hand"}}

        assert ConfigForm.decode(fields, params, %{"step_name" => "Collect email"}) ==
                 %{"step_name" => "Collect email"}
      end

      # Sabotage: `decode/3` building a fresh map instead of starting from
      # `base` - red, which is F6's point that keeping the value needed no
      # decoder change at all.
      test "keeps a hidden value that was simply not posted" do
        fields = [field("note", "first"), field("variant_seed", "cohort_b", hidden?: true)]
        params = %{"config" => %{"note" => "second"}}

        assert ConfigForm.decode(fields, params, %{"variant_seed" => "cohort_b"}) == %{
                 "note" => "second",
                 "variant_seed" => "cohort_b"
               }
      end
    end

    describe "a commit through the live form" do
      # Sabotage: either half of the decode change - red, because the seed is
      # then rewritten to the crafted value or dropped on the first edit the
      # author makes.
      test "keeps the hidden and readonly values across an edit", %{conn: conn} do
        view = select_seed(conn)

        # `form/3` refuses to post a name the rendered form has no control
        # for, which is itself the flags working - so the crafted payload
        # goes through the form element instead, which is exactly what a
        # hand-rolled POST from outside the page can do.
        view
        |> element(~s(#sb-form-blk_seed))
        |> render_change(%{
          "config" => %{
            "note" => "second",
            "variant_seed" => "tampered",
            "step_name" => "Renamed by hand"
          }
        })

        assert config(latest_document(), "blk_seed") == %{
                 "step_name" => "Collect email",
                 "variant_seed" => "cohort_b",
                 "note" => "second"
               }
      end
    end
  end
end
