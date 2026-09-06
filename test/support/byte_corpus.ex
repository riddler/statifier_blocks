defmodule StatifierBlocks.ByteCorpus do
  @moduledoc """
  The corpus `sb-hxs5` pins byte for byte: the documents whose compiled
  bytes must not move when a failure-classed outcome is declared, classed
  and propagated.

  Two of the entries are the family's worked examples - the
  card-processing one (`myapp.authorize` / `myapp.capture`) and the signup
  wizard - built by `StatifierBlocks.DocumentFixtures` from the same
  canonical bytes the encoder and decoder are checked against. The other
  three are the three shipped types that class an outcome, each with its
  failure slot **occupied**: ADR-0002's amendment of 2026-09-06 section 2
  says every byte of the occupied case is what it is today, and these are
  where that claim is cashed.

  Each entry compiles three ways - plain, `terminate: true` and
  `child_use: true` - because the propagation rule is gated on the last
  two and "unchanged" has to mean unchanged under the gate as well as
  outside it.
  """

  alias StatifierBlocks.{Block, CoreFixtures, Document, DocumentFixtures, Palette}

  @dir "test/fixtures/corpus"

  @doc "The corpus, as `{name, document, palette}` triples."
  @spec entries() :: [{String.t(), Document.t(), Palette.t()}]
  def entries do
    core = Palette.new(Palette.core_types())

    [
      {"worked_example", DocumentFixtures.worked_example(), CoreFixtures.palette()},
      {"signup_wizard", DocumentFixtures.signup_wizard(), CoreFixtures.palette()},
      {"invoke_handled", invoke_handled(), core},
      {"map_handled", map_handled(), core},
      {"subchart_handled", subchart_handled(), core}
    ]
  end

  @doc "The three compile option sets every entry is pinned under."
  @spec modes() :: [{String.t(), keyword()}]
  def modes,
    do: [{"plain", []}, {"terminate", [terminate: true]}, {"child_use", [child_use: true]}]

  @doc "Where one entry's golden bytes live."
  @spec golden_path(String.t(), String.t()) :: String.t()
  def golden_path(name, mode), do: Path.join(@dir, "#{name}-#{mode}.scxml")

  defp invoke_handled do
    Document.new(
      Block.new("core.sequence",
        id: "blk_SEQ",
        slots: %{
          "body" => [
            Block.new("core.invoke",
              id: "blk_INV",
              config: %{"invoke_type" => "myapp:authorize", "assign_to" => "cards.auth"},
              slots: %{"on_error" => [Block.new("core.sequence", id: "blk_ERR")]}
            )
          ]
        }
      ),
      id: "bdoc_INVOKE"
    )
  end

  defp map_handled do
    Document.new(
      Block.new("core.map",
        id: "blk_MAP",
        config: %{
          "items" => "signup.invitees",
          "chart" => "bdoc_CHILD",
          "item_as" => "invitee",
          "collect" => "answers"
        },
        slots: %{"on_error" => [Block.new("core.sequence", id: "blk_MERR")]}
      ),
      id: "bdoc_MAP"
    )
  end

  defp subchart_handled do
    Document.new(
      Block.new("core.subchart",
        id: "blk_SUB",
        config: %{"chart" => "bdoc_CHILD", "outcomes" => "approved\ndeclined"},
        slots: %{"on_error" => [Block.new("core.sequence", id: "blk_SERR")]}
      ),
      id: "bdoc_SUB"
    )
  end
end
