defmodule StatifierBlocks.Edit.Session do
  @moduledoc """
  The commit funnel: one place a gesture reaches the document, over
  `StatifierBlocks.Edit.History.commit/4`.

  A session is the editing state a surface holds between gestures - the
  palette it resolves types through, the document it is editing, the undo
  history behind it, the per-block config drafts the document has refused,
  and the last refusal that had nowhere else to go. Every function here is
  a pure function of that value: it takes a session and returns a session,
  with no socket, no assigns and no process state in it.

  ## Why the funnel is a module and not four copies

  The package's own editor and every host embedding it face the same four
  lines of `Edit.History.commit/4` handling, and the decisions inside them
  are the package's, not the surface's:

    * a refused `{:update_config, id, config}` is held as a **draft** of
      what the author typed, keyed by block id, rather than being blanked
      back to the document's value (ADR-0005 decision 9). A host that
      re-implements the funnel re-implements that decision, and gets it
      wrong by keeping the keystrokes it should drop or dropping the ones
      it should keep;
    * a refusal that is not about a config lands in `last_error` and moves
      nothing else;
    * an undo or a redo drops **every** draft: a draft is by definition
      config the document never accepted, and carrying one across a
      history move shows the author a value belonging to a document state
      they just stepped out of;
    * a list gesture reads and writes through the field's own `value_path`
      (ADR-0002 decision 7, amended 2026-08-27) rather than through its
      key, and descends into nested members the same way the control that
      draws them does.

  ## The `{:ok, session}` / `{:error, session}` result

  Every funnel function answers with a tagged session, and the tag says
  exactly one thing: **did the document move**. `{:ok, session}` means it
  did, and is the caller's cue to run whatever it does on a change - the
  package editor notifies its `on_change` host callback, a host store
  persists. `{:error, session}` means it did not, and the session still
  comes back because a refusal is a state change too: it is where the
  draft was recorded, or where `last_error` was set. There is nothing for
  a caller to do with it but render it.

  ## Where this module is, and is not

  It lives beside `StatifierBlocks.Edit.History` and
  `StatifierBlocks.Edit.Targets` because it operates on exactly what they
  operate on - a document, a palette and a history - and because, like
  them, it compiles and runs with no LiveView in the tree. The alternative
  home, under `StatifierBlocks.Editor`, is the LiveView component's own
  namespace: ADR-0005 decision 1 compiles it out entirely when LiveView is
  absent, and it is where the socket lives. The socket stays there; the
  document, the history and the drafts come here.

  ## Building one

  A session is an ordinary struct with no constructor to learn:

      %StatifierBlocks.Edit.Session{
        palette: palette,
        document: document,
        history: StatifierBlocks.Edit.History.new()
      }

  `drafts` defaults to `%{}` and `last_error` to `nil`.
  """

  alias StatifierBlocks.{Block, BlockType, Document, Edit, Palette, ViewModel}
  alias StatifierBlocks.Edit.History

  @typedoc "Per-block config the document refused, keyed by block id."
  @type drafts :: %{optional(Block.id()) => Block.config()}

  @type t :: %__MODULE__{
          palette: Palette.t(),
          document: Document.t(),
          history: History.t(),
          drafts: drafts(),
          last_error: term() | nil
        }

  @enforce_keys [:palette, :document, :history]
  defstruct [:palette, :document, :history, drafts: %{}, last_error: nil]

  @typedoc "What a list control asks of one member list: append a blank, or drop the member at an index."
  @type gesture :: :add | {:remove, integer()}

  @typedoc """
  A gesture, optionally addressed at a nested member list.

  The bare form is the field's own list. A `{path, gesture}` pair steps
  into that list's member at each index in turn - the same descent the
  control makes when it nests - and applies the gesture there.
  """
  @type list_gesture :: gesture() | {[non_neg_integer()], gesture()}

  @doc """
  Applies `command` to the session's document through the gated history.

  The one place a command reaches the document, so the gate, the undo
  stack and the caller's change notification each have one implementation
  rather than one per gesture.

  On `{:ok, session}` the document and the history have both moved and
  `last_error` is cleared; drafts are untouched, because a command that is
  not a config change says nothing about a config the document refused. On
  `{:error, session}` the refusal is in `last_error` and nothing else
  moved.

  ## Examples

      iex> alias StatifierBlocks.{Block, Document, Palette}
      iex> alias StatifierBlocks.Edit.{History, Session}
      iex> document = Document.new(Block.new("core.sequence", id: "blk_ROOT", slots: %{"body" => []}))
      iex> session = %Session{palette: Palette.core(), document: document, history: History.new()}
      iex> {:ok, block} = Palette.new_block(session.palette, "core.placeholder")
      iex> {:ok, moved} = Session.commit(session, {:insert, {"blk_ROOT", "body", 0}, block})
      iex> length(Document.blocks(moved.document))
      2
      iex> {:error, refused} = Session.commit(session, {:remove, "blk_NOPE"})
      iex> refused.last_error
      {:no_such_block, "blk_NOPE"}
  """
  @spec commit(t(), Edit.t()) :: {:ok, t()} | {:error, t()}
  def commit(%__MODULE__{} = session, command) do
    case History.commit(session.history, session.palette, session.document, command) do
      {:ok, history, document} ->
        {:ok, %{session | history: history, document: document, last_error: nil}}

      {:error, reason} ->
        {:error, %{session | last_error: reason}}
    end
  end

  @doc """
  Writes `config` onto the block `id`, holding a refused config as a draft.

  This differs from `commit/2` in one way and only one: an
  `{:invalid_config, id, findings}` refusal is recorded in `drafts` under
  `id` instead of in `last_error`. That is ADR-0005 decision 9's draft
  treatment - a value the document refuses is still the value the author
  is holding, and blanking it back to the document's would delete their
  keystrokes to punish a typo. Every other refusal lands in `last_error`
  exactly as `commit/2`'s does.

  A config the document accepts clears that block's draft: the author has
  resolved the refusal that produced it.

  """
  @spec change_config(t(), Block.id(), Block.config()) :: {:ok, t()} | {:error, t()}
  def change_config(%__MODULE__{} = session, id, config) do
    case History.commit(
           session.history,
           session.palette,
           session.document,
           {:update_config, id, config}
         ) do
      {:ok, history, document} ->
        {:ok,
         %{
           session
           | history: history,
             document: document,
             drafts: Map.delete(session.drafts, id),
             last_error: nil
         }}

      {:error, {:invalid_config, ^id, _findings}} ->
        {:error, %{session | drafts: Map.put(session.drafts, id, config)}}

      {:error, reason} ->
        {:error, %{session | last_error: reason}}
    end
  end

  @doc """
  Steps the history one move: `:undo` or `:redo`.

  Both directions arrive at the same reconciliation, because `History` has
  already done the part that differs by the time this runs. Drafts are
  dropped wholesale on a successful step - see the moduledoc for why - and
  an empty stack answers `{:error, session}` with `:nothing_to_undo` or
  `:nothing_to_redo` in `last_error`.

  ## Examples

      iex> alias StatifierBlocks.{Block, Document, Palette}
      iex> alias StatifierBlocks.Edit.{History, Session}
      iex> document = Document.new(Block.new("core.sequence", id: "blk_ROOT", slots: %{"body" => []}))
      iex> session = %Session{palette: Palette.core(), document: document, history: History.new()}
      iex> {:error, nothing} = Session.step(session, :undo)
      iex> nothing.last_error
      :nothing_to_undo
      iex> {:ok, block} = Palette.new_block(session.palette, "core.placeholder")
      iex> {:ok, moved} = Session.commit(session, {:insert, {"blk_ROOT", "body", 0}, block})
      iex> {:ok, back} = Session.step(moved, :undo)
      iex> length(Document.blocks(back.document))
      1
  """
  @spec step(t(), :undo | :redo) :: {:ok, t()} | {:error, t()}
  def step(%__MODULE__{} = session, direction) when direction in [:undo, :redo] do
    stepped =
      case direction do
        :undo -> History.undo(session.history, session.palette, session.document)
        :redo -> History.redo(session.history, session.palette, session.document)
      end

    case stepped do
      {:ok, history, document} ->
        {:ok, %{session | history: history, document: document, drafts: %{}, last_error: nil}}

      {:error, reason} ->
        {:error, %{session | last_error: reason}}
    end
  end

  @doc """
  Applies a list gesture to `field` on the block `id`, and commits it.

  The rows are read from the block's **effective** config - the draft if
  one is held, the document's otherwise - and written back through the
  field's own `value_path/1`, which is where the form's other writes go.
  The commit is `change_config/3`'s, so a list edit that leaves the config
  invalid is held as a draft like any other refused config rather than
  being lost.

  `gesture` is a `t:list_gesture/0`: `:add`, `{:remove, index}`, or either
  of those addressed at a nested member list by a `{path, gesture}` pair.

  """
  @spec update_list(t(), Block.id(), ViewModel.Field.t(), list_gesture()) ::
          {:ok, t()} | {:error, t()}
  def update_list(%__MODULE__{} = session, id, %ViewModel.Field{} = field, gesture) do
    config = Document.effective_config(session.document, id, session.drafts)
    path = ViewModel.Field.value_path(field)

    held =
      case BlockType.fetch_value(config, path) do
        {:ok, value} -> value
        :error -> nil
      end

    rows = apply_gesture(%{field | value: held}, gesture)

    change_config(session, id, BlockType.put_value(config, path, rows))
  end

  @doc """
  The rows `field` would hold after `gesture`, as a value.

  The document is not consulted and nothing is committed: this is the list
  half of `update_list/4` on its own, for a surface that needs the rows
  before it has somewhere to put them. The field's `type` says what a
  blank member looks like and how a stored value reads as rows, and its
  `value` is what the gesture is applied to.

  A `{:list, t}` wraps whatever it finds, which is what a stored scalar
  has always meant there. A `{:type_expr, opts}` does not: its inline arm
  is a list and its name arm is a string, and wrapping the string would
  turn a type name into a nameless member.

  ## Examples

      iex> alias StatifierBlocks.Edit.Session
      iex> alias StatifierBlocks.ViewModel.Field
      iex> field = %Field{key: "tags", type: {:list, :string}, label: "Tags", required?: false, default: [], value: ["a", "b"]}
      iex> Session.apply_gesture(field, :add)
      ["a", "b", ""]
      iex> Session.apply_gesture(field, {:remove, 0})
      ["b"]
  """
  @spec apply_gesture(ViewModel.Field.t(), list_gesture()) :: [term()]
  def apply_gesture(%ViewModel.Field{type: type, value: value}, gesture) do
    {path, bare} = addressed(gesture)

    type
    |> rows_of(value)
    |> descend(path, bare, blank_row(type))
  end

  @spec addressed(list_gesture()) :: {[non_neg_integer()], gesture()}
  defp addressed({path, gesture}) when is_list(path), do: {path, gesture}
  defp addressed(gesture), do: {[], gesture}

  @spec rows_of(BlockType.field_type(), term()) :: [term()]
  defp rows_of({:type_expr, _opts}, value) when is_list(value), do: value
  defp rows_of({:type_expr, _opts}, _not_a_member_list), do: []
  defp rows_of(_type, value), do: List.wrap(value)

  @spec blank_row(BlockType.field_type()) :: term()
  defp blank_row({:type_expr, _opts}), do: %{"name" => "", "type" => "", "required?" => false}
  defp blank_row(_type), do: ""

  @spec descend([term()], [non_neg_integer()], gesture(), term()) :: [term()]
  defp descend(rows, [], :add, blank), do: rows ++ [blank]
  defp descend(rows, [], {:remove, index}, _blank), do: List.delete_at(rows, index)

  defp descend(rows, [index | rest], gesture, blank) do
    List.update_at(rows, index, fn row ->
      inner =
        case row do
          %{"type" => members} when is_list(members) -> members
          _no_nested_members -> []
        end

      row
      |> member_row()
      |> Map.put("type", descend(inner, rest, gesture, blank))
    end)
  end

  @spec member_row(term()) :: map()
  defp member_row(row) when is_map(row), do: row
  defp member_row(_row), do: %{"name" => "", "required?" => false}
end
