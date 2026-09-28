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
  # | A sentence that    | reads as                        |
  # |--------------------|---------------------------------|
  # | sends an event     | "Send word that" and the words  |
  # | waits for an event | "Wait until" and the words      |
  # | names it elsewhere | the words                       |
  #
  # A name the function has no words for is left as it is, so a host that
  # passes nothing draws every sentence exactly as the package writes it.

  alias StatifierBlocks.ViewModel
  alias StatifierBlocks.ViewModel.Node

  @typedoc "An event name to the words a reader reads for it, or `nil`."
  @type phrase :: (String.t() -> String.t() | nil)

  # An event name is dotted words, so a name is only whole where neither
  # side runs on into another word character or dot. The send and the wait
  # shapes are tried before a bare name at each place in the line.
  @name ~r/\b([Ss]end) ([\w.]+)(?![\w.])|\b([Ww]ait) for ([\w.]+)(?![\w.])|(?<![\w.])([\w.]+)(?![\w.])/u

  @doc "The phrase that knows no words: every name stays as authored."
  @spec none(String.t()) :: nil
  def none(_event), do: nil

  @doc "`line` with every whole event name `phrase` has words for read as words."
  @spec line(String.t(), phrase()) :: String.t()
  def line(line, phrase) when is_binary(line) and is_function(phrase, 1) do
    Regex.replace(@name, line, fn whole, send, sent, wait, awaited, name ->
      cond do
        send != "" -> phrased(whole, phrase.(sent), &"#{send} word that #{&1}")
        wait != "" -> phrased(whole, phrase.(awaited), &"#{wait} until #{&1}")
        true -> phrased(whole, phrase.(name), & &1)
      end
    end)
  end

  @doc "A block's sentence, its event names read through `phrase`."
  @spec sentence(Node.t(), phrase()) :: String.t()
  def sentence(%Node{} = node, phrase), do: node |> ViewModel.sentence() |> line(phrase)

  @spec phrased(String.t(), String.t() | nil, (String.t() -> String.t())) :: String.t()
  defp phrased(_whole, words, shape) when is_binary(words), do: shape.(words)
  defp phrased(whole, _no_words, _shape), do: whole
end
