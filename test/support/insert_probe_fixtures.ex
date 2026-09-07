defmodule StatifierBlocks.InsertProbeFixtures do
  @moduledoc """
  The insert probe's config, in one place (sb-1c7g).

  `StatifierBlocks.Editor` builds a probe block of the dragged type to ask
  `StatifierBlocks.Edit.Targets` which slots would take it, and the probe's
  config is whatever `config_schema/1` declares as its defaults. A path
  field whose default is the empty string names no path, so a block whose
  read is declared on such a field declares no read at all on the probe -
  and a slot that would refuse the configured block accepts the probe.

  `cards.settle_final` is that block: one `{:path, %{expects: "Settled"}}`
  field defaulting to `""`, the way
  `StatifierBlocks.CardProcessingFixtures.Settle`'s own subject field does,
  and a `palette_entry/0` whose `default_config` names the path a host
  would configure it with. The entry block is
  `StatifierBlocks.CardProcessingFixtures.Open`, which puts a
  `cards.credit_txn` at the subject path, and that record does not satisfy
  the `Settled` shape - it has no `settled_on` - so the read the probe
  ought to declare is exactly the one that refuses.

  `test/support/` carries one subject per file, and this one's subject is
  that reproduction end to end: the type, the palette, and the document
  whose slot the assertions read.
  """

  alias StatifierBlocks.{Block, CardProcessingFixtures, Document, Palette}

  defmodule SettleFinal do
    @moduledoc """
    A step whose read is a function of its config: the path it settles is
    the `subject` field's value, and the shape it expects there is
    `Settled`. Nothing about it is special except that its path field
    starts empty, which is what makes an unconfigured probe silent.
    """

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1

    @impl true
    def slots(_config), do: []

    @impl true
    def config_schema(_config) do
      [
        %{
          key: "subject",
          type: {:path, %{expects: "Settled"}},
          label: "Settle what",
          required?: true,
          default: ""
        }
      ]
    end

    @impl true
    def validate_config(_config), do: :ok

    @impl true
    def io(_config), do: %{kinds: [:step]}

    @impl true
    def palette_entry do
      %{
        label: "Final settlement",
        subject: "cards.current_txn",
        default_config: %{"subject" => "cards.current_txn"}
      }
    end

    @impl true
    def emit(%Block{id: id}, _context), do: {:error, {:not_implemented, id}}
  end

  @doc "The core vocabulary, the worked example's entry block, and the step above."
  @spec palette() :: Palette.t()
  def palette do
    Palette.new(
      Map.merge(Palette.core_types(), %{
        "cards.open" => CardProcessingFixtures.Open,
        "cards.settle_final" => SettleFinal
      })
    )
  end

  @doc """
  The entry block, then a group whose `body` and `interrupts` are empty.

  `blk_GRP`'s `body` is what the assertions read. It has exactly one gap,
  and that gap sees the entry block's write - unlike the root's own `body`,
  whose gap 0 sits ahead of that write and accepts everything, which the
  existential reduction `StatifierBlocks.Edit.Targets` documents would then
  spread over the whole slot.
  """
  @spec document() :: Document.t()
  def document do
    open = Block.new("cards.open", id: "blk_OPEN")

    group =
      Block.new("core.resumable_group", id: "blk_GRP", slots: %{"body" => [], "interrupts" => []})

    root = Block.new("core.sequence", id: "blk_ROOT", slots: %{"body" => [open, group]})
    Document.new(root, id: "bdoc_insert_probe")
  end

  @doc """
  The datamodel both spellings resolve through - ADR-0011's worked one,
  with the two `local` entries left out.

  The entries matter from ADR-0011's amendment of 2026-09-06: the
  environment now seeds the declared path types the document has written,
  so a document that declares `cards.current_txn` types that path at every
  position - including the gap ahead of the entry block, which is the one
  this file's assertions turn on. The declarations this fixture needs are
  the **types**, which is what `Settled` and `Settleable` resolve through;
  what the document declares about its own paths is another file's
  subject.
  """
  @spec datamodel() :: map()
  def datamodel do
    Map.update!(CardProcessingFixtures.datamodel(), "scopes", fn scopes ->
      Enum.map(scopes, fn scope -> Map.put(scope, "entries", []) end)
    end)
  end
end
