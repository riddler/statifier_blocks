# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. The seam under test is a pure
# function, but the claim about it is not - it is that its number is the number
# the drawer renders, and only a mounted editor renders anything.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.FindingsCountTest do
    @moduledoc """
    sb-ukgu: one findings number.

    `Editor.findings_count/3` exists so a host header and the drawer's
    Findings tab cannot disagree about one document, and the only assertion
    that means anything about it is the comparison against what the drawer
    actually rendered. So every test here mounts the editor, reads the number
    off the strip as a person would, and compares it to what the seam returns
    for the same inputs.

    The document is built to have findings from three sources at once - the
    `:resolution` finding `ViewModel` derives, an undeclared-path advisory
    `Datamodel` derives, and two the caller supplied, one of them orphaned -
    because a seam that counted only the caller's list would pass against any
    document with one source and fail an author on every real one.
    """

    use StatifierBlocks.EditorLiveCase

    alias StatifierBlocks.Editor

    @declared ["signup.step"]

    # `blk_variant_write` writes `signup.variant`, which @declared does not
    # declare: one `:info` advisory (11e). `EditorFixtures.tracking/0` is the
    # block the core palette cannot resolve: one derived `:resolution`.
    defp document do
      Document.new(
        Block.new("core.sequence",
          id: "blk_wizard",
          slots: %{
            "body" => [
              Block.new("core.assign",
                id: "blk_variant_write",
                config: %{"path" => "signup.variant", "value" => "\"b\""}
              ),
              EditorFixtures.tracking()
            ]
          }
        ),
        id: "doc_one_number"
      )
    end

    # Two the caller supplied. The second is anchored on a block this document
    # does not hold, so it routes nowhere on the canvas and lands in
    # `orphan_findings` - and is still one of the document's findings.
    defp caller_findings do
      [
        Finding.new({:block, "blk_variant_write"}, :lint, "writes a path nothing reads",
          severity: :warning
        ),
        Finding.new({:block, "blk_deleted_long_ago"}, :resolution, "no such block any more")
      ]
    end

    defp seam(document \\ document(), opts \\ []) do
      Editor.findings_count(
        document,
        EditorFixtures.palette(),
        Keyword.merge([findings: caller_findings(), datamodel: @declared], opts)
      )
    end

    # What the collapsed strip says, as an integer. The strip carries the
    # active tab's count, and with no fixtures source the Truth tables count
    # is 0, so `Shell`'s resolution rule makes Findings the active tab - which
    # is the state an author lands in on a document with findings and no
    # tables.
    defp strip_count(view) do
      [_all, count] =
        view
        |> element(".sb-drawer__strip .sb-drawer__count")
        |> render()
        |> then(&Regex.run(~r/>\s*(\d+)\s*</, &1))

      String.to_integer(count)
    end

    describe "the seam against the strip" do
      # Sabotage: `Editor.findings_count/3` passing `Keyword.get(opts,
      # :findings, [])` as `[]` - the caller's two findings drop out, the seam
      # answers 2 where the strip renders 4, and this goes red (verified).
      test "the number is the strip's number, over findings from three sources",
           %{conn: conn} do
        {:ok, view, _html} =
          mount_editor(conn,
            document: document(),
            findings: caller_findings(),
            datamodel: @declared
          )

        assert has_element?(view, ~s(.sb-drawer[data-tab="findings"]))
        assert strip_count(view) == 4
        assert seam() == strip_count(view)

        assert seam() > length(caller_findings()),
               "a number the host could have got by counting its own list proves nothing"
      end

      # Sabotage: `findings_count/3` counting the view model's routed findings
      # rather than all of them (`length(vm.findings) - length(vm.orphan_findings)`)
      # - the orphan drops out of the seam and out of the comparison against
      # the anchored-only run together, the difference goes to 0 and this goes
      # red (verified).
      test "an orphaned finding is inside the number", %{conn: conn} do
        {:ok, view, _html} =
          mount_editor(conn,
            document: document(),
            findings: caller_findings(),
            datamodel: @declared
          )

        anchored_only = seam(document(), findings: [hd(caller_findings())])

        assert seam() - anchored_only == 1
        assert seam() == strip_count(view)
      end

      # Sabotage: `findings_count/3` defaulting `:datamodel` to `[]` rather
      # than `nil` - an empty declared set is a host saying its documents
      # address nothing, so the advisory fires with no datamodel supplied and
      # the seam answers 2 against a strip rendering 1 (11f).
      test "the defaults are the component's defaults", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: document())

        assert strip_count(view) == 1
        assert Editor.findings_count(document(), EditorFixtures.palette()) == strip_count(view)
      end
    end

    describe "after a rebuild" do
      # The view model is a projection and not a cache (`rebuild/1`), and this
      # is the assertion that costs something if it ever becomes one.
      # Sabotage: `update/3` rebuilding only when there is no view model yet -
      # the strip keeps the first document's 4 after the swap while the seam
      # answers 3 for the document actually open, and this goes red
      # (verified).
      test "the seam tracks a document the host swapped in", %{conn: conn} do
        {:ok, view, _html} =
          mount_editor(conn,
            document: document(),
            findings: caller_findings(),
            datamodel: @declared
          )

        assert strip_count(view) == 4

        send(view.pid, {:swap_document, EditorFixtures.signup_wizard()})
        assert render(view) =~ "sb-editor"

        swapped = EditorFixtures.signup_wizard()

        assert strip_count(view) == seam(swapped)
        assert strip_count(view) == 3
      end
    end
  end
end
