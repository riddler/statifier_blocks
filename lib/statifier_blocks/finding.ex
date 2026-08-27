defmodule StatifierBlocks.Finding do
  @moduledoc """
  A finding as the editor renders it: normalized for presentation, and the
  anchor routes it (ADR-0005 decision 11).

  Findings arrive from sources with different shapes - `validate_config/1`
  returns `{key, message}` pairs, arity and undeclared-slot violations are
  about a slot, resolution failures are about a block - so this struct
  normalizes them to one shape with one routing mechanism: the `anchor`.
  `StatifierBlocks.ViewModel` is what actually does the routing; this
  module owns only the shape.

  ## Two `Finding` modules, on purpose

  `StatifierBlocks.Compiler.Finding` already exists, and it is a
  **different** struct for a **different** layer: it carries
  `stage`/`fault`/`code`/`reason` for the compile pipeline (ADR-0004
  decision 10), keyed to the stage that produced it and to whether the
  problem is the author's or the package's. This module,
  `StatifierBlocks.Finding`, is the **presentation** finding ADR-0005
  decision 11 specifies: `anchor`/`severity`/`source`/`message`, keyed to
  where in the rendered tree the finding shows up. Neither is a
  degenerate case of the other, neither wraps the other, and nothing in
  this package adapts one into the other (see
  `StatifierBlocks.ViewModel`'s moduledoc for why that adapter is
  deliberately not built here). If you are about to import this module
  and get `stage`, `fault`, `code`, or `reason` back, you have the wrong
  one - reach for `StatifierBlocks.Compiler.Finding` instead.
  """

  alias StatifierBlocks.Block

  @typedoc """
  The whole routing mechanism (ADR-0005 decision 11). A `:config` finding
  renders inline beneath its field, a `:slot` finding on that slot's
  header, a `:block` finding on the block's chrome.
  """
  @type anchor ::
          {:config, Block.id(), key :: String.t()}
          | {:slot, Block.id(), Block.slot_name()}
          | {:block, Block.id()}

  @typedoc "Where this finding's rule lives. See `StatifierBlocks.ViewModel`'s moduledoc."
  @type source :: :config | :arity | :assignability | :resolution | :lint

  @type t :: %__MODULE__{
          severity: :error | :warning,
          anchor: anchor(),
          source: source(),
          message: String.t()
        }

  @enforce_keys [:anchor, :source, :message]
  defstruct [:anchor, :source, :message, severity: :error]

  @doc """
  Builds a finding, in the shape `StatifierBlocks.Compiler.Finding.new/4`
  already uses: the fixed positional arguments first, `message` last among
  them, and everything else in `opts`.

  `opts` carries `:severity`, defaulting to `:error` - the default every
  source but `:lint` uses (ADR-0005 decision 11).
  """
  @spec new(anchor(), source(), String.t(), keyword()) :: t()
  def new(anchor, source, message, opts \\ []) do
    %__MODULE__{
      anchor: anchor,
      source: source,
      message: message,
      severity: Keyword.get(opts, :severity, :error)
    }
  end
end
