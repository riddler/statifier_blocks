defmodule StatifierBlocks.Map.Phrasing do
  @moduledoc false

  # A host's words for its event names, read into the sentences this
  # package writes. A block's sentence names an event by its name ("Send
  # loan.closed", "Wait for copy.returned"), which is the right thing to
  # author and not what a reader of a drawing should have to decode. A host
  # that has words for its names hands `StatifierBlocks.Map.graph/2` a
  # `:phrase` function, an event name to its words or `nil`, and the rules
  # below read the words into the package's own sentence shapes:
  #
  # | A sentence that             | reads as                        |
  # |-----------------------------|---------------------------------|
  # | sends an event              | "Send word that" and the words  |
  # | waits for an event          | "Wait until" and the words      |
  # | starts a rule with an event | "When" and the words            |
  #
  # Only a name in one of those three places is an event, so only those are
  # read as words. A known name anywhere else - a path a step sets, a name
  # after a send word glued to a dotted prefix - is left as written. A name
  # the function has no words for is left as it is, so a host that passes
  # nothing draws every sentence exactly as the package writes it.

  alias StatifierBlocks.ViewModel
  alias StatifierBlocks.ViewModel.Node

  @typedoc "An event name to the words a reader reads for it, or `nil`."
  @type phrase :: (String.t() -> String.t() | nil)

  # A name in event position: after "Send" (or a delayed "send"), after
  # "Wait for", or after a rule's "When". An event name is dotted words, so
  # the opening word counts only where no word character or dot runs into
  # it ("loan.Send" opens nothing), and the name runs until neither a word
  # character nor a dot follows.
  @event_position ~r/(?<![\w.])(?:([Ss]end)|([Ww]ait) for|When) ([\w.]+)(?![\w.])/u

  @doc "The phrase that knows no words: every name stays as authored."
  @spec none(String.t()) :: nil
  def none(_event), do: nil

  @doc """
  `line` with every whole event name `phrase` has words for, in event
  position, read as words; anything else in the line is left as it is.
  """
  @spec line(String.t(), phrase()) :: String.t()
  def line(line, phrase) when is_binary(line) and is_function(phrase, 1) do
    Regex.replace(@event_position, line, fn whole, send, wait, event ->
      phrased(whole, phrase.(event), send, wait)
    end)
  end

  @doc "A block's sentence, its event names read through `phrase`."
  @spec sentence(Node.t(), phrase()) :: String.t()
  def sentence(%Node{} = node, phrase), do: node |> ViewModel.sentence() |> line(phrase)

  # One match of `@event_position`: the whole match, the words for its name
  # (or `nil`), and the "Send" or "send" it opened with (or ""), or the
  # "Wait" or "wait" (or "").
  @spec phrased(String.t(), String.t() | nil, String.t(), String.t()) :: String.t()
  defp phrased(whole, nil, _send, _wait), do: whole
  defp phrased(_whole, words, send, _wait) when send != "", do: send <> " word that " <> words
  defp phrased(_whole, words, _send, wait) when wait != "", do: wait <> " until " <> words
  defp phrased(_whole, words, _send, _wait), do: "When " <> words
end
