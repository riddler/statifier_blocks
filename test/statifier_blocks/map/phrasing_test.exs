defmodule StatifierBlocks.Map.PhrasingTest do
  @moduledoc """
  The rules that read a host's words for its event names into the
  package's sentences, under the library world's words.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.Document
  alias StatifierBlocks.Map.Phrasing
  alias StatifierBlocks.MapFixtures
  alias StatifierBlocks.ViewModel

  defp line(text), do: Phrasing.line(text, &MapFixtures.phrase/1)

  # Every event the two teaching documents send, wait for, listen for or
  # accept has its words, so neither document draws a bare event name in
  # a sentence.
  test "the library world has words for every event the two documents name" do
    for key <- MapFixtures.keys() do
      document = MapFixtures.document!(key)

      for event <- events(document) do
        assert is_binary(MapFixtures.phrase(event)), "#{key}: no words for #{event}"
      end
    end
  end

  # Sabotage: dropped "word that" from the send rule; this went red.
  # Reverted from a copy.
  test "a send says what it announces" do
    assert line("Send loan.closed") == "Send word that the loan is closed"

    assert line("In 7 days, send registration.deadline") ==
             "In 7 days, send word that the registration week is up"
  end

  # Sabotage: made the wait rule keep "for"; this went red. Reverted from a
  # copy.
  test "a wait says what it waits until, keeping its timeout" do
    assert line("Wait for guardian.consented, giving up after 14d") ==
             "Wait until a guardian consents, giving up after 14d"

    assert line("Wait for email.verified") == "Wait until the email address is verified"
  end

  # Sabotage: made the bare-name rule bracket its words; this went red.
  # Reverted from a copy.
  test "a rule's event reads as a clause" do
    assert line("When registration.deadline, abandon") ==
             "When the registration week is up, abandon"
  end

  # Sabotage: made line/2 replace the first match only; this went red.
  # Reverted from a copy.
  test "every event in a line is phrased, and nothing else changes" do
    assert line("After Send loan.overdue, Wait for copy.returned, giving up after 14d") ==
             "After Send word that the loan is overdue, " <>
               "Wait until the copy is returned, giving up after 14d"
  end

  # A name that only starts or ends like a known one is a different event.
  #
  # Sabotage: made the bare-name rule trim a trailing full stop from a name;
  # this went red. Reverted from a copy.
  test "matches a whole event name only" do
    assert line("Send loan.closed_early") == "Send loan.closed_early"
    assert line("Send old.loan.closed") == "Send old.loan.closed"
    assert line("When loan.closed.") == "When loan.closed."
  end

  # Sabotage: made phrased/3 shape a name it has no words for; this went
  # red. Reverted from a copy.
  test "leaves a line with no known event name as it is" do
    assert line("Send payment.settled") == "Send payment.settled"
    assert line("Wait for payment.settled") == "Wait for payment.settled"
    assert Phrasing.line("Send loan.closed", &Phrasing.none/1) == "Send loan.closed"
  end

  # Sabotage: made sentence/2 answer the sentence unphrased; this went red.
  # Reverted from a copy.
  test "a block's sentence reads through the phrase" do
    view_model = MapFixtures.view_model!("library_loan")
    node = ViewModel.find_node(view_model, "blk_ll_close")

    assert ViewModel.sentence(node) == "Send loan.closed"
    assert Phrasing.sentence(node, &MapFixtures.phrase/1) == "Send word that the loan is closed"
  end

  # Every event name a document's blocks and its `accepts` carry.
  defp events(%Document{root: root, accepts: accepts}) do
    Enum.uniq(accepts ++ block_events(root))
  end

  defp block_events(block) do
    own =
      case block.config do
        %{"event" => event} when is_binary(event) -> [event]
        _none -> []
      end

    own ++ Enum.flat_map(Map.values(block.slots), &Enum.flat_map(&1, fn b -> block_events(b) end))
  end
end
