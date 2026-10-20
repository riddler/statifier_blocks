defmodule StatifierBlocks.ViewModel.AdvisoryFindingsTest do
  @moduledoc """
  The pure half of the editor's `advisories` assign (ADR-0005's Amendment
  of 2026-10-19): how a host's function is called and how its return value
  is read. It runs with LiveView off the path, which is the point of keeping
  it outside the editor's guard; the rendered half is
  `StatifierBlocks.Editor.HostAdvisoriesTest`.

  The return value is read exactly as a `StatifierBlocks.DocumentValidator`'s
  is (ADR-0005 clause `11r`): the package stamps `:lint`, the default
  severity is `:warning`, and a shape it does not recognise is no finding.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Document, Finding, ViewModel}

  defp loan_document do
    Document.new(
      Block.new("core.group",
        id: "blk_desk",
        slots: %{
          "body" => [
            Block.new("core.await", id: "blk_return", config: %{"event" => "loan.returned"})
          ]
        }
      ),
      id: "doc_circulation_desk"
    )
  end

  describe "the default" do
    # sabotage: made the catch-all clause answer one finding on the document's
    # root for any value - `nil` says something and this goes red (verified)
    test "nil calls nothing and adds nothing" do
      assert ViewModel.advisory_findings(loan_document(), nil) == []
    end

    # sabotage: the catch-all mutation above turns this red as well (verified)
    test "a value that is not a one-argument function says nothing" do
      assert ViewModel.advisory_findings(loan_document(), %{"blk_return" => "late"}) == []
      assert ViewModel.advisory_findings(loan_document(), fn -> [] end) == []
    end
  end

  describe "the host's function" do
    # sabotage: called the function with the document's root block in place
    # of the document - the message the host sends itself carries the block,
    # and the `assert_received` match goes red (verified)
    test "is handed the document, and its advisory is stamped :lint at :warning" do
      test_pid = self()

      host = fn argument ->
        send(test_pid, {:handed, argument})
        [{{:config, "blk_return", "event"}, "no desk sends loan.returned"}]
      end

      assert [
               %Finding{
                 anchor: {:config, "blk_return", "event"},
                 source: :lint,
                 severity: :warning,
                 message: "no desk sends loan.returned"
               }
             ] = ViewModel.advisory_findings(loan_document(), host)

      assert_received {:handed, %Document{id: "doc_circulation_desk"}}
    end

    # sabotage: read the host's return with a default severity of `:error`
    # - the unmarked advisory comes back as an error and this goes red
    # (verified)
    test "a severity in opts is kept, and an advisory with none is a :warning" do
      host = fn _document ->
        [
          {{:block, "blk_return"}, "a hold may be waiting", severity: :info},
          {{:slot, "blk_desk", "body"}, "the desk has one step"}
        ]
      end

      assert [%Finding{severity: :info}, %Finding{severity: :warning}] =
               ViewModel.advisory_findings(loan_document(), host)
    end

    # The return is read, never validated back at the host: what the
    # normalizer does not recognise is no finding, and nothing raises.
    #
    # sabotage: admitted `:document` in the normalizer's `anchor?/1` - the
    # document-anchored member comes back as a finding and this goes red
    # (verified)
    test "a return that is not a list, and a member of neither shape, is no finding" do
      assert ViewModel.advisory_findings(loan_document(), fn _ -> :nothing end) == []

      host = fn _document ->
        [
          :not_a_spec,
          {{:block, "blk_return"}, :not_a_message},
          {:document, "the document anchor is not admitted"},
          {{:block, "blk_return"}, "kept"}
        ]
      end

      assert [%Finding{anchor: {:block, "blk_return"}, message: "kept"}] =
               ViewModel.advisory_findings(loan_document(), host)
    end

    # The host's code raising is the host's bug, and it is not rescued into
    # an empty list (ADR-0005 clause `11r`).
    #
    # sabotage: wrapped the call in a `try` rescuing to `[]` - nothing
    # raises and this goes red (verified)
    test "a raise inside the host's function is not rescued" do
      assert_raise RuntimeError, "the host's lookup failed", fn ->
        ViewModel.advisory_findings(loan_document(), fn _ -> raise "the host's lookup failed" end)
      end
    end
  end
end
