# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. The pure half of sb-82mu's
# claim - that a free-typed event name is validated exactly as it was - lives
# in `StatifierBlocks.Core.OnEventTest`, deliberately outside this guard.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.EventCandidatesTest do
    @moduledoc """
    `core.on_event`'s `event` candidates (sb-82mu): the completion events the
    blocks in the handler's enclosing body raise, offered as a `<datalist>`
    on a field that is still a `:string`.

    What only exists once there is markup is the half here - that the
    generated names reach a datalist the input is bound to, that the body is
    read through the slot's `:step` declaration rather than by name, that a
    type declaring no outcomes contributes none, and that none of it
    constrains what an author may type.
    """

    use StatifierBlocks.EditorLiveCase

    @credit_approved "done.outcome.s_blk_credit.approved"
    @credit_declined "done.outcome.s_blk_credit.declined"
    @credit_error "done.outcome.s_blk_credit.error"
    @wait_received "done.outcome.s_blk_wait.received"
    @wait_timed_out "done.outcome.s_blk_wait.timed_out"

    defp purchase_document(opts) do
      Document.new(
        Block.new("core.group",
          id: "blk_purchase",
          slots: %{
            "body" => [
              Block.new("core.subchart",
                id: "blk_credit",
                config: %{"chart" => "bdoc_CREDIT", "outcomes" => "approved\ndeclined"}
              ),
              Block.new("core.await",
                id: "blk_wait",
                config: %{"event" => "order.paid"}
              ),
              Block.new("core.assign",
                id: "blk_note",
                config: %{"path" => "order.note", "value" => "seen"}
              )
            ],
            "interrupts" => [
              Block.new("core.on_event",
                id: "blk_cancel",
                config: %{
                  "event" => Keyword.get(opts, :event, ""),
                  "outcome" => "abandon"
                }
              )
            ]
          }
        ),
        id: "doc_purchase"
      )
    end

    defp select(view, block_id) do
      view
      |> element(~s([data-block-id="#{block_id}"] > .sb-node__chrome > .sb-node__label))
      |> render_click()

      view
    end

    defp purchase_view(conn, opts \\ []) do
      {:ok, view, _html} = mount_editor(conn, document: purchase_document(opts))

      select(view, Keyword.get(opts, :select, "blk_cancel"))
    end

    describe "the candidate list" do
      # Sabotage: dropped `list={@list_id}` from the new control's input ->
      # 2 failures, this one and the reach-by-key assertion below, both on
      # the binding rather than on the options. A datalist attached to
      # nothing renders identically and suggests nothing, which is the defect
      # a "does the markup contain the names" assertion would miss.
      test "the body's outcomes render as a datalist the input is bound to", %{conn: conn} do
        view = purchase_view(conn)

        assert has_element?(
                 view,
                 ~s(input[name="config[event]"][list="sb-field-event-events"])
               )

        assert has_element?(view, ~s(datalist#sb-field-event-events[data-event-candidates="5"]))

        for event <- [@credit_approved, @credit_declined, @credit_error] do
          assert has_element?(view, ~s(datalist#sb-field-event-events option[value="#{event}"]))
        end
      end

      # A second body block, and a second `outcomes/1` implementation: the
      # list is the body crossed with each block's own declaration, not one
      # block's. The values are asserted as whole strings rather than by
      # shape, because the point of routing them through
      # `StateId.outcome_event/2` is that the name an author picks here and
      # the name the compiler mints are one string.
      #
      # Sabotage: dropped the second `Enum.flat_map/2` over the slot's
      # children so only the first body block contributed -> this goes red,
      # and the count and label assertions go with it (3 failures, verified).
      test "an await in the same body contributes its own two outcomes", %{conn: conn} do
        view = purchase_view(conn)

        for event <- [@wait_received, @wait_timed_out] do
          assert has_element?(view, ~s(datalist#sb-field-event-events option[value="#{event}"]))
        end
      end

      # Sabotage: dropped `declares_outcomes?/1` from `outcome_candidates/2`
      # -> `core.assign` contributes the A1 default `done`, this goes red
      # with a sixth option, and the count assertion above and the empty-body
      # case below move with it (3 failures, verified). Offering a generated
      # name for an outcome a type never declared is offering a wire that is
      # not there.
      test "a type that declares no outcomes contributes none", %{conn: conn} do
        view = purchase_view(conn)

        refute has_element?(
                 view,
                 ~s(datalist#sb-field-event-events option[value^="done.outcome.s_blk_note."])
               )
      end

      # Sabotage: labelled the candidates with `block.type` instead of
      # `ViewModel.title/1` -> the label reads "core.subchart · approved" and
      # this goes red. The name on the candidate has to be the name on the
      # card.
      test "each candidate is labelled by its block and its outcome", %{conn: conn} do
        view = purchase_view(conn)

        assert has_element?(
                 view,
                 ~s(option[value="#{@credit_approved}"][label="Subchart · approved"])
               )

        assert has_element?(
                 view,
                 ~s(option[value="#{@wait_received}"][label="Wait for event · received"])
               )
      end
    end

    describe "which field is offered the list" do
      # Sabotage: widened `event_candidates/1`'s head to match any selected
      # node -> the await's own `event` field draws the list too and this
      # goes red. `core.send`, `core.raise` and `core.await` each declare an
      # `event` key, and each names events this list is not about.
      test "an await's own event field is the plain input", %{conn: conn} do
        view = purchase_view(conn, select: "blk_wait")

        assert has_element?(view, ~s(input[name="config[event]"]))
        refute has_element?(view, ~s(input[name="config[event]"][list]))
        refute has_element?(view, "datalist#sb-field-event-events")
      end

      # The body is read off the enclosing type's `slot_accepts` declaration,
      # so a block sitting in a slot that does not admit `:step` is not in
      # the body however plausible it looks. A subchart in the `interrupts`
      # slot is a misplacement the editor already reports; what it must not
      # also do is offer its outcomes as though it ran in the body.
      #
      # Sabotage: widened `body_slot?/3` to accept any declared kind list ->
      # the stray subchart's three outcomes join the list and this goes red
      # (verified). The `core.on_event` case alone cannot catch that
      # mutation: a handler declares no outcomes, so an `interrupts` slot
      # counted as a body still contributes nothing.
      test "a slot that does not admit a step is not a body", %{conn: conn} do
        document =
          Document.new(
            Block.new("core.group",
              id: "blk_purchase",
              slots: %{
                "body" => [],
                "interrupts" => [
                  Block.new("core.subchart",
                    id: "blk_stray",
                    config: %{"chart" => "bdoc_CHILD", "outcomes" => "approved"}
                  ),
                  Block.new("core.on_event", id: "blk_cancel", config: %{"outcome" => "abandon"})
                ]
              }
            ),
            id: "doc_stray"
          )

        {:ok, view, _html} = mount_editor(conn, document: document)

        select(view, "blk_cancel")

        refute has_element?(
                 view,
                 ~s(option[value^="done.outcome.s_blk_stray."])
               )

        refute has_element?(view, ~s(input[name="config[event]"][list]))
      end

      # Sabotage: dropped the `type: @on_event_type` guard from
      # `event_candidates/1`'s head -> every selected block with an `event`
      # field draws the list, and this goes red on the await below. Here the
      # check is the handler's own side: no candidate names the handler.
      test "the handler does not offer itself", %{conn: conn} do
        view = purchase_view(conn)

        refute has_element?(
                 view,
                 ~s(datalist#sb-field-event-events option[value^="done.outcome.s_blk_cancel."])
               )
      end

      # The control is reached by the field KEY, exactly as `invoke_type`'s
      # is, and by nothing else on the card: `outcome` is a `:select` and
      # takes no list.
      #
      # Sabotage: dropped `list={@list_id}` from the new control's input ->
      # this goes red with the binding assertion above (2 failures,
      # verified).
      test "the control is reached by the field's key", %{conn: conn} do
        view = purchase_view(conn)

        assert has_element?(view, ~s(.sb-field[data-field="event"] input[list]))
        refute has_element?(view, ~s(.sb-field[data-field="outcome"] input[list]))
      end
    end

    describe "it suggests, and never constrains" do
      # Sabotage: rendered the candidates as a `<select>` instead - the
      # control a constraint would use -> this goes red with "value for
      # select config[event] must be one of ...". The gate on what reaches
      # the document stays `validate_config/1`'s.
      test "a free-typed event name still reaches the document", %{conn: conn} do
        view = purchase_view(conn)

        view
        |> form(~s(#sb-form-blk_cancel), %{"config" => %{"event" => "order.cancelled"}})
        |> render_change()

        assert %{"event" => "order.cancelled"} =
                 latest_document()
                 |> Document.blocks()
                 |> Enum.find(&(&1.id == "blk_cancel"))
                 |> Map.fetch!(:config)
      end

      # Sabotage: made the `Field` clause unconditional on the list being
      # non-empty -> an empty `<datalist>` renders, this goes red, and the
      # two other "plain input" cases go with it (3 failures, verified). No
      # body block with declared outcomes is no candidates, and no candidates
      # is the plain input the field has always rendered.
      test "a body with nothing to offer is the plain input", %{conn: conn} do
        document =
          Document.new(
            Block.new("core.group",
              id: "blk_bare",
              slots: %{
                "body" => [Block.new("core.assign", id: "blk_only", config: %{})],
                "interrupts" => [
                  Block.new("core.on_event", id: "blk_cancel", config: %{"outcome" => "abandon"})
                ]
              }
            ),
            id: "doc_bare"
          )

        {:ok, view, _html} = mount_editor(conn, document: document)

        select(view, "blk_cancel")

        assert has_element?(view, ~s(input[name="config[event]"]))
        refute has_element?(view, ~s(input[name="config[event]"][list]))
      end
    end
  end
end
