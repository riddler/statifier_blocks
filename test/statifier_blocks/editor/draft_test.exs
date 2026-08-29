# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. The `:liveview` tag on
# `StatifierBlocks.EditorLiveCase` excludes these from a headless *run*; this
# guard is what keeps them out of a headless *compile*, which is the earlier
# of the two problems.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.DraftTest do
    @moduledoc """
    Filling in more than one required field (`sb-5ow`, graduated by `sb-8dc`).

    ADR-0005 decision 9 validates a config as a **unit** and stores nothing
    when the gate refuses. That invariant is the right one - a stored config is
    always a valid config - and on its own it makes a block type with two
    required fields and no usable defaults impossible to configure through a
    form that commits one field at a time. `core.assign` is the live repro:
    fill `path` and the config still carries an empty `value`, so the gate
    refuses; fill `value` afterwards and, if the edit were computed against the
    STORED config, the gate would refuse again. Both fields are correct on
    screen, the revision never moves, and the author is told twice that a value
    they typed correctly is wrong.

    The shipped editor already carries the mechanism - `drafts`, and
    `effective_config/2` as the base every field edit is computed against - so
    what `sb-8dc` inherited from the spike was a reconciliation rather than a
    port. The first three tests pin the mechanism that was already there,
    because it had no test of its own; the last two are what the spike added on
    top, the affordance that says a draft is outstanding and the gesture that
    throws one away.
    """

    use StatifierBlocks.EditorLiveCase

    defp assign_document do
      Document.new(
        Block.new("core.sequence",
          id: "blk_root",
          slots: %{"body" => [Block.new("core.assign", id: "blk_write", config: %{})]}
        ),
        id: "doc_assign"
      )
    end

    defp mount_assign(conn) do
      {:ok, view, _html} = mount_editor(conn, document: assign_document())

      render_click(
        element(view, ~s([data-block-id="blk_write"] > .sb-node__chrome > .sb-node__label))
      )

      view
    end

    defp change(view, config) do
      view
      |> form(~s(#sb-form-blk_write), %{"config" => config})
      |> render_change()
    end

    defp stored(view) do
      view
      |> render()
      |> then(&Regex.run(~r/data-revision="(\d+)"/, &1))
      |> List.last()
    end

    describe "draft accumulation (sb-5ow)" do
      # Sabotage: `Editor.change_config/3` dropping the draft on a refusal
      # instead of storing it - the second edit is then computed against a
      # config that never took `path`, the gate refuses again, and the two
      # fields can never both be right at once.
      test "two edits in either order commit as one config", %{conn: conn} do
        view = mount_assign(conn)

        change(view, %{"path" => "signup.tier", "value" => ""})
        refute latest_document(), "half a config is not a config, and the gate refused it"

        html = change(view, %{"path" => "signup.tier", "value" => "gold"})

        assert config(latest_document(), "blk_write") == %{
                 "path" => "signup.tier",
                 "value" => "gold"
               }

        refute html =~ "sb-form__pending", "the draft is dropped once it lands"
      end

      # Sabotage: the same, with the fields typed the other way round - a base
      # that is the stored config rather than the draft fails this one first.
      test "the accumulation is order-independent", %{conn: conn} do
        view = mount_assign(conn)

        change(view, %{"value" => "gold"})
        change(view, %{"path" => "signup.tier"})

        assert config(latest_document(), "blk_write") == %{
                 "path" => "signup.tier",
                 "value" => "gold"
               }
      end

      # Sabotage: `History.commit/4` letting an invalid config through - the
      # revision moves on a config `validate_config/1` refused, which is the
      # thing decision 9's gate exists to prevent.
      test "an outstanding draft never reaches the document", %{conn: conn} do
        view = mount_assign(conn)
        before = stored(view)

        change(view, %{"path" => "signup.tier"})

        assert stored(view) == before, "a draft is not a revision"
        refute latest_document()
      end
    end

    describe "the uncommitted-edits affordance" do
      # Sabotage: `Editor.pending_fields/2` returning `[]` unconditionally -
      # the author is left reading a refusal about a field they filled in
      # correctly, with nothing on screen saying why nothing was stored.
      test "it names the fields that are outstanding, and why", %{conn: conn} do
        view = mount_assign(conn)

        html = change(view, %{"path" => "signup.tier"})

        assert html =~ "sb-form__pending"
        assert html =~ "Nothing is stored yet"
        assert html =~ "Write to", "the field's own label, not its key"
        assert html =~ "committed as a unit"
      end

      # Sabotage: comparing the draft's key set against the schema rather than
      # against the document - every field then reads as outstanding forever,
      # including the ones already stored.
      test "a field typed back to what the document holds is not outstanding",
           %{conn: conn} do
        view = mount_assign(conn)

        change(view, %{"path" => "signup.tier", "value" => "gold"})
        html = change(view, %{"path" => "", "value" => "gold"})

        assert html =~ ~s(data-pending="1"),
               "only `path` differs from the stored config"
      end

      # Sabotage: `handle_event("discard-draft", ...)` rebuilding without
      # dropping the draft - the affordance stays on screen and the only way
      # out of a draft stops existing, which is the point of it: a draft was
      # never a command, so it cannot be undone.
      test "discarding returns the form to the document", %{conn: conn} do
        view = mount_assign(conn)

        change(view, %{"path" => "signup.tier", "value" => "gold"})
        change(view, %{"path" => "not a path", "value" => "gold"})

        html =
          view
          |> element(~s(#sb-form-blk_write .sb-form__discard))
          |> render_click()

        refute html =~ "sb-form__pending"
        assert html =~ ~s(value="signup.tier"), "the last config that validated"
      end
    end

    describe "placeholders by control type (sb-ed7)" do
      # Sabotage: dropping the `:expression` placeholder - the first thing an
      # author meets in a condition field is a blank box, which is the defect
      # the spike found on the field it graduated this from.
      test "an :expression field says what belongs in it", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        render_click(
          element(view, ~s([data-block-id="blk_variant"] > .sb-node__chrome > .sb-node__label))
        )

        assert has_element?(view, ~s([data-field-type="expression"] input[placeholder]))
      end

      # Sabotage: putting a placeholder on the `:string` clause too - "string"
      # is too wide a type to suggest anything, and a hint that guesses is
      # worse than none.
      test "a bare :string field says nothing", %{conn: conn} do
        view = mount_assign(conn)

        refute has_element?(view, ~s([data-field="path"] input[placeholder]))
      end
    end

    defp config(document, block_id) do
      document |> Document.blocks() |> Enum.find(&(&1.id == block_id)) |> Map.fetch!(:config)
    end
  end
end
