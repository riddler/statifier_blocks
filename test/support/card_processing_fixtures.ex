defmodule StatifierBlocks.CardProcessingFixtures do
  @moduledoc """
  ADR-0011's worked shape, in one place: the card processing datamodel
  document, the block types the record's own example names, and the two
  host relations that example needs.

  The record's argument is made against one document - a datamodel
  declaring two records and two shapes under `types`, an entry block that
  names the subject path, and a settle step that reads a shape and writes a
  record - and three surfaces now assert against it: the walk
  (`StatifierBlocks.EnvironmentTest`), the drop check
  (`StatifierBlocks.Edit.Targets`), and the editor's Datamodel tab
  (`sb-sy0q`, ADR-0011 decision 9). A second copy of the shape would let
  two of them agree about a document the third does not have, which is the
  only kind of drift a fixture can introduce on its own.

  `test/support/` carries one subject per file and this one's subject is
  that document, end to end.
  """

  alias StatifierBlocks.{Block, Document, Palette}

  @datamodel %{
    "version" => 1,
    "scopes" => [
      %{"scope" => "global", "label" => "Global", "entries" => []},
      %{
        "scope" => "local",
        "label" => "This run",
        "entries" => [
          %{
            "name" => "current_txn",
            "path" => "cards.current_txn",
            "type" => "object",
            "label" => "Current transaction"
          },
          %{
            "name" => "settlement",
            "path" => "cards.settlement",
            "type" => "object",
            "label" => "Settlement"
          }
        ]
      },
      %{"scope" => "event", "label" => "Event", "entries" => []}
    ],
    "types" => [
      %{
        "name" => "cards.credit_txn",
        "kind" => "record",
        "label" => "Credit card transaction",
        "fields" => [
          %{"name" => "amount_minor", "type" => "integer", "required?" => true},
          %{"name" => "currency", "type" => "string", "required?" => true},
          %{"name" => "authorized_at", "type" => "datetime"},
          %{"name" => "expires_on", "type" => "date"}
        ]
      },
      %{
        "name" => "cards.settlement",
        "kind" => "record",
        "label" => "Settlement",
        "fields" => [
          %{"name" => "amount_minor", "type" => "integer", "required?" => true},
          %{"name" => "currency", "type" => "string", "required?" => true},
          %{"name" => "settled_on", "type" => "date", "required?" => true}
        ]
      },
      %{
        "name" => "Settleable",
        "kind" => "shape",
        "label" => "Settleable",
        "fields" => [
          %{"name" => "amount_minor", "type" => "integer", "required?" => true},
          %{"name" => "currency", "type" => "string", "required?" => true}
        ]
      },
      %{
        "name" => "Settled",
        "kind" => "shape",
        "label" => "Settled",
        "fields" => [
          %{"name" => "amount_minor", "type" => "integer", "required?" => true},
          %{"name" => "settled_on", "type" => "date", "required?" => true}
        ]
      }
    ]
  }

  @subject "cards.current_txn"
  @doc "ADR-0011's worked datamodel document, `types` key and all."
  @spec datamodel() :: map()
  def datamodel, do: @datamodel

  @doc "The subject path every block type here declares (decision 6)."
  @spec subject() :: String.t()
  def subject, do: @subject

  defmodule Open do
    @moduledoc "The entry block: names the subject path and puts a record there."

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1
    @impl true
    def slots(_config), do: []
    @impl true
    def config_schema(_config), do: []
    @impl true
    def validate_config(_config), do: :ok
    @impl true
    def io(_config), do: %{kinds: [:step], produces: "cards.credit_txn"}
    @impl true
    def palette_entry, do: %{label: "Open", subject: "cards.current_txn"}
    @impl true
    def emit(%Block{id: id}, _context), do: {:error, {:not_implemented, id}}
  end

  defmodule Settle do
    @moduledoc """
    The record's settle step: a `subject` field expecting a shape, and an
    `assign_to` field writing a record.
    """

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1
    @impl true
    def slots(_config), do: []

    @impl true
    def config_schema(config) do
      [
        %{
          key: "subject",
          type: {:path, %{expects: Map.get(config, "expects", "Settleable")}},
          label: "Settle what",
          required?: true,
          default: ""
        },
        %{
          key: "assign_to",
          type: {:path, %{writes: "cards.settlement"}},
          label: "Write the settlement to",
          required?: false,
          default: ""
        }
      ]
    end

    @impl true
    def validate_config(_config), do: :ok
    @impl true
    def io(_config), do: %{kinds: [:step]}
    @impl true
    def palette_entry, do: %{label: "Settle", subject: "cards.current_txn"}
    @impl true
    def emit(%Block{id: id}, _context), do: {:error, {:not_implemented, id}}
  end

  defmodule WriteString do
    @moduledoc "Writes one of the nine scalars at the path its field names."

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1
    @impl true
    def slots(_config), do: []

    @impl true
    def config_schema(_config),
      do: [
        %{
          key: "at",
          type: {:path, %{writes: "string"}},
          label: "Write a string to",
          required?: true,
          default: ""
        }
      ]

    @impl true
    def validate_config(_config), do: :ok
    @impl true
    def io(_config), do: %{kinds: [:step]}
    @impl true
    def palette_entry, do: %{label: "Write a string"}
    @impl true
    def emit(%Block{id: id}, _context), do: {:error, {:not_implemented, id}}
  end

  defmodule Widens do
    @moduledoc "Widens `cards.credit_txn` into `Settled`, and nothing else."

    @behaviour StatifierBlocks.Assignability.Relation

    @impl true
    def assignable?("cards.credit_txn", "Settled"), do: true
    def assignable?(_held, _expected), do: false
  end

  defmodule Deny do
    @moduledoc "Widens nothing - the floor a host relation can never fall below."

    @behaviour StatifierBlocks.Assignability.Relation

    @impl true
    def assignable?(_held, _expected), do: false
  end

  @doc "The palette the worked example resolves through."
  @spec palette(module() | nil) :: Palette.t()
  def palette(assignability \\ nil) do
    Palette.new(
      Map.merge(Palette.core_types(), %{"cards.open" => Open, "cards.settle" => Settle}),
      assignability: assignability
    )
  end

  @doc "`palette/1`, plus the scalar-writing step the merge tests need."
  @spec string_palette() :: Palette.t()
  def string_palette do
    Palette.new(
      Map.merge(Palette.core_types(), %{
        "cards.open" => Open,
        "cards.settle" => Settle,
        "cards.write_string" => WriteString
      })
    )
  end

  @doc "The context the walk and the drop check are asked with."
  @spec ctx() :: map()
  def ctx, do: %{datamodel: @datamodel}

  @doc "The entry block."
  @spec open(String.t()) :: Block.t()
  def open(id \\ "blk_OPEN"), do: Block.new("cards.open", id: id)

  @doc "A settle step, reading `Settleable` at the subject unless told otherwise."
  @spec settle(String.t(), map() | keyword()) :: Block.t()
  def settle(id, opts \\ []) do
    config =
      %{"subject" => @subject, "assign_to" => "cards.settlement"}
      |> Map.merge(Map.new(opts))

    Block.new("cards.settle", id: id, config: config)
  end

  @doc "A `core.assign` writing a bare path."
  @spec assign(String.t(), String.t()) :: Block.t()
  def assign(id, path) do
    Block.new("core.assign", id: id, config: %{"path" => path, "value" => "1"})
  end

  @doc "A root sequence holding `children`."
  @spec document([Block.t()], String.t()) :: Document.t()
  def document(children, id \\ "bdoc_cards") do
    Document.new(Block.new("core.sequence", id: "blk_ROOT", slots: %{"body" => children}), id: id)
  end

  @doc "A `core.branch` reading its arms from the config, one slot per arm."
  @spec branch(String.t(), keyword([Block.t()]) | [{String.t(), [Block.t()]}]) :: Block.t()
  def branch(id, arms) do
    Block.new("core.branch",
      id: id,
      config: %{"arms" => Enum.map(arms, fn {slot, _} -> %{"slot" => slot, "cond" => "true"} end)},
      slots: Map.new(arms)
    )
  end
end
