defmodule StatifierBlocks.Declarations do
  @moduledoc """
  The declarations panel's arithmetic: every author gesture on the
  document's `datamodel` key, as a pure list-to-list function
  (ADR-0005's 2026-09-01 amendment, clauses 2g-2m).

  Deliberately outside `StatifierBlocks.Editor.*`, and for decision 1's
  reason: the editor's job is translation, so which entry moved and what
  the new list is are decided here and asserted with `phoenix_live_view`
  absent from the dependency tree. Nothing in this module renders, and
  nothing in it writes a document - every function returns a **candidate
  list**, which the caller hands to `{:set_datamodel, entries}` and the
  command either accepts or refuses (2h).

  ## Every function is total, and out of range is a no-op

  An index arrives from a `phx-value-index` attribute, so a stale one is
  an ordinary race - the author pressed a row's remove button on markup
  that a concurrent change had already shortened - and a crafted one is a
  payload, not a bug. Both get the same answer: the list unchanged. That
  is the same stance `StatifierBlocks.Shell.drawer_tab/2` takes for a tab
  name off the wire, and it is what keeps the panel free of an error state
  nobody can act on.

  ## Why `add/1` mints a name instead of appending a blank row

  ADR-0001 11b gives `id` no empty spelling: it is
  `~r/\\A[a-z][a-z0-9_]*\\z/` or it is refused. A blank row would therefore
  be a list `{:set_datamodel, entries}` refuses, so pressing Add would
  produce a refusal rather than a row - the author would have to type a
  legal name before the gesture they already made took effect.

  `add/1` mints `root_1`, `root_2`, ... - the first that no entry already
  holds - so the list a press produces is always one the command accepts.
  This is decision 2's minting discipline in a second place and for the
  same reason it gives there: the value is completed at gesture time and
  the recorded command carries a finished list, so replaying a command log
  yields the same document every time.

  ## The accepted events

  The panel's second row is the document's `accepts` list (ADR-0014
  decision 6): the names of the external events the document accepts,
  written through `{:set_accepts, names}` on the terms the roots are
  written through `{:set_datamodel, entries}`. `remove/2` and `move/3` serve
  both lists unchanged, because neither looks inside an entry.
  `add_accepted/1` and `put_accepted/3` are the two gestures that do, and
  they exist beside `add/1` and `put/4` rather than inside them because a
  name is a bare string with no fields to address. `add_accepted/1` mints
  for `add/1`'s reason: an empty name is refused, so a blank row would be a
  press that produces a refusal.
  """

  alias StatifierBlocks.Document.DatamodelEntry

  @typedoc "The three fields ADR-0001 11b gives an entry, as they arrive from a form."
  @type field :: :id | :expr | :description

  @minted_prefix "root_"
  @minted_event_prefix "event_"

  @doc """
  Appends a freshly named entry: `root_1`, or the first `root_N` no entry
  already holds.

  `expr` and `description` are `nil`, which is the absent spelling ADR-0001
  11b gives both and the one 11d omits from the canonical bytes. The new
  root therefore reads as `undefined` until something assigns it, which is
  what an author who has just named a root has said about it.

      iex> StatifierBlocks.Declarations.add([])
      [%StatifierBlocks.Document.DatamodelEntry{id: "root_1", expr: nil, description: nil}]

      iex> entry = %StatifierBlocks.Document.DatamodelEntry{id: "root_1"}
      iex> [_kept, minted] = StatifierBlocks.Declarations.add([entry])
      iex> minted.id
      "root_2"
  """
  @spec add([DatamodelEntry.t()]) :: [DatamodelEntry.t()]
  def add(entries) when is_list(entries) do
    entries ++ [%DatamodelEntry{id: mint(entries)}]
  end

  @doc """
  Drops the entry at `index`, or returns `entries` unchanged when no entry
  sits there.

      iex> entries = [%StatifierBlocks.Document.DatamodelEntry{id: "signup"}]
      iex> StatifierBlocks.Declarations.remove(entries, 0)
      []
      iex> StatifierBlocks.Declarations.remove(entries, 4) == entries
      true
  """
  @spec remove([entry], term()) :: [entry] when entry: DatamodelEntry.t() | String.t()
  def remove(entries, index) when is_list(entries) do
    if in_range?(entries, index), do: List.delete_at(entries, index), else: entries
  end

  @doc """
  Swaps the entry at `index` with its neighbour in `direction`.

  Order is the emission order of the document's `<data>` elements
  (ADR-0001 11a), so this is an authoring act with a visible meaning in the
  compiled chart rather than a display preference - which is why it is a
  document edit and not editor state.

  A move off either end is a no-op, so the first row's "up" and the last
  row's "down" are inert rather than wrapping. Wrapping would make one
  press of a repeated gesture do the opposite of the press before it.

      iex> a = %StatifierBlocks.Document.DatamodelEntry{id: "a"}
      iex> b = %StatifierBlocks.Document.DatamodelEntry{id: "b"}
      iex> StatifierBlocks.Declarations.move([a, b], 1, :up) |> Enum.map(& &1.id)
      ["b", "a"]
      iex> StatifierBlocks.Declarations.move([a, b], 0, :up) |> Enum.map(& &1.id)
      ["a", "b"]
  """
  @spec move([entry], term(), term()) :: [entry] when entry: DatamodelEntry.t() | String.t()
  def move(entries, index, direction) when is_list(entries) do
    with true <- in_range?(entries, index),
         {:ok, other} <- neighbour(index, direction),
         true <- in_range?(entries, other) do
      swap(entries, index, other)
    else
      _no -> entries
    end
  end

  @doc """
  Writes one field of the entry at `index`.

  `expr` and `description` are optional in ADR-0001 11b and absent is
  spelled `nil` on the struct, so a cleared text input - the empty string a
  browser sends for a field the author emptied - becomes `nil` here rather
  than `""`. The alternative is a value 11b refuses and 11d would never
  encode, reached by the ordinary act of clearing a box.

  `id` is written through verbatim, blank included. It is required, so
  there is nothing for a blank to mean, and the refusal the command answers
  with is the panel's message to the author (2l) rather than something to
  paper over here.

      iex> entries = [%StatifierBlocks.Document.DatamodelEntry{id: "a", expr: "1"}]
      iex> StatifierBlocks.Declarations.put(entries, 0, :expr, "") |> hd() |> Map.get(:expr)
      nil
      iex> StatifierBlocks.Declarations.put(entries, 0, :id, "signup") |> hd() |> Map.get(:id)
      "signup"
  """
  @spec put([DatamodelEntry.t()], term(), field(), term()) :: [DatamodelEntry.t()]
  def put(entries, index, field, value)
      when is_list(entries) and field in [:id, :expr, :description] do
    if in_range?(entries, index) do
      List.update_at(entries, index, &%{&1 | field => cast(field, value)})
    else
      entries
    end
  end

  @doc """
  The entry list a `phx-change` payload asks for: every field the form
  carries, written onto the entry at `index`.

  Keys the form did not send are left alone, so a panel that grows a field
  later does not silently blank the ones beside it, and a key outside
  11b's three is ignored rather than written - the payload is untrusted
  input and this is the only place it becomes an entry.

  The `id` field arrives under the name `"name"`. That is not a rename of
  11b's field, which is still `id` on the struct and in the bytes; it is
  the one spelling LiveView leaves alone. An `<input name="id">` inside a
  form overrides the form element's own DOM id, which LiveView refuses at
  compile time, so the wire name and the struct key differ here and this
  table is where they are reconciled.

      iex> entries = [%StatifierBlocks.Document.DatamodelEntry{id: "a"}]
      iex> params = %{"name" => "signup", "description" => "the wizard", "nope" => "x"}
      iex> [entry] = StatifierBlocks.Declarations.change(entries, 0, params)
      iex> {entry.id, entry.description}
      {"signup", "the wizard"}
  """
  @spec change([DatamodelEntry.t()], term(), map()) :: [DatamodelEntry.t()]
  def change(entries, index, params) when is_list(entries) and is_map(params) do
    Enum.reduce([id: "name", expr: "expr", description: "description"], entries, fn {field, key},
                                                                                    acc ->
      case Map.fetch(params, key) do
        {:ok, value} -> put(acc, index, field, value)
        :error -> acc
      end
    end)
  end

  @doc """
  Appends a freshly named accepted event: `event_1`, or the first `event_N`
  the list does not already hold.

  The name is a placeholder the author is expected to overwrite with the
  event their host sends, and it is one `{:set_accepts, names}` accepts, so
  the press lands as a row rather than as a refusal.

      iex> StatifierBlocks.Declarations.add_accepted([])
      ["event_1"]

      iex> StatifierBlocks.Declarations.add_accepted(["event_1", "email.verified"])
      ["event_1", "email.verified", "event_2"]
  """
  @spec add_accepted([String.t()]) :: [String.t()]
  def add_accepted(names) when is_list(names) do
    taken = MapSet.new(names)

    minted =
      1
      |> Stream.iterate(&(&1 + 1))
      |> Stream.map(&(@minted_event_prefix <> Integer.to_string(&1)))
      |> Enum.find(&(not MapSet.member?(taken, &1)))

    names ++ [minted]
  end

  @doc """
  Writes the accepted event name at `index`, or returns `names` unchanged
  when no name sits there.

  The value is written through verbatim, blank included, as `put/4` writes
  an `id`: a name is required, so there is nothing for a blank to mean, and
  the refusal `{:set_accepts, names}` answers with is the panel's message to
  the author.

      iex> StatifierBlocks.Declarations.put_accepted(["event_1"], 0, "email.verified")
      ["email.verified"]
      iex> StatifierBlocks.Declarations.put_accepted(["event_1"], 3, "email.verified")
      ["event_1"]
  """
  @spec put_accepted([String.t()], term(), term()) :: [String.t() | term()]
  def put_accepted(names, index, value) when is_list(names) do
    if in_range?(names, index), do: List.replace_at(names, index, value), else: names
  end

  @doc """
  How many declarations the document carries - the drawer strip's count for
  the Declarations tab.

      iex> StatifierBlocks.Declarations.count([%StatifierBlocks.Document.DatamodelEntry{id: "a"}])
      1
      iex> StatifierBlocks.Declarations.count(nil)
      0
  """
  @spec count(term()) :: non_neg_integer()
  def count(entries) when is_list(entries), do: length(entries)
  def count(_other), do: 0

  @doc """
  A refusal from `{:set_datamodel, entries}` or `{:set_accepts, names}`, as
  one sentence for the panel.

  ADR-0005 decision 11's anchors name a block, a slot or a config key, and
  none of them can name a declaration entry, so a refusal here is not a
  `%StatifierBlocks.Finding{}` and does not enter the findings pipeline
  (2l). It is rendered in the panel that produced it, which is the only
  place it is about.

  Anything this function does not recognize gets the generic sentence
  rather than an inspected tuple: the panel is read by an author, and a
  term it cannot phrase is a term the author cannot act on either.

      iex> StatifierBlocks.Declarations.refusal(
      ...>   {:malformed_envelope, {:datamodel, {:duplicate_id, "signup"}}}
      ...> )
      ~s(Two declarations are named "signup". Every id must be unique.)

      iex> StatifierBlocks.Declarations.refusal(
      ...>   {:malformed_envelope, {:accepts, {:entry, 0, :empty}}}
      ...> )
      "Accepted event 1 needs a name, such as email.verified."

      iex> StatifierBlocks.Declarations.refusal(:something_else)
      "That change was refused."
  """
  @spec refusal(term()) :: String.t()
  def refusal({:malformed_envelope, {:datamodel, reason}}), do: datamodel_refusal(reason)
  def refusal({:malformed_envelope, {:accepts, reason}}), do: accepts_refusal(reason)
  def refusal(_other), do: "That change was refused."

  @spec datamodel_refusal(term()) :: String.t()
  defp datamodel_refusal({:duplicate_id, id}),
    do: ~s(Two declarations are named "#{id}". Every id must be unique.)

  defp datamodel_refusal({:entry, index, {:id, :not_an_identifier}}),
    do:
      "Declaration #{index + 1} needs a name like signup or card_last4: " <>
        "lowercase, starting with a letter."

  defp datamodel_refusal({:entry, index, {:expr, :not_an_expression}}),
    do: "Declaration #{index + 1}'s initial value must be text, or left empty."

  defp datamodel_refusal({:entry, index, {:description, :not_a_non_empty_string}}),
    do: "Declaration #{index + 1}'s description must be text, or left empty."

  defp datamodel_refusal(_other), do: "That change was refused."

  # ADR-0014 decision 2's four arms. `:not_a_list` has no sentence of its
  # own: the panel only ever builds a list, so it reaches here from nowhere an
  # author stands, and takes the generic one.
  @spec accepts_refusal(term()) :: String.t()
  defp accepts_refusal({:duplicate_name, name}),
    do: ~s(The document already accepts "#{name}". Every accepted event is named once.)

  defp accepts_refusal({:entry, index, :empty}),
    do: "Accepted event #{index + 1} needs a name, such as email.verified."

  defp accepts_refusal({:entry, index, :not_a_string}),
    do: "Accepted event #{index + 1} must be named in text."

  defp accepts_refusal(_other), do: "That change was refused."

  # `root_1` upward, skipping every name already taken. The scan is over the
  # ids the list holds rather than over its length, so removing `root_1` and
  # adding again re-uses the freed name instead of climbing forever.
  @spec mint([DatamodelEntry.t()]) :: String.t()
  defp mint(entries) do
    taken =
      entries
      |> Enum.map(fn
        %DatamodelEntry{id: id} -> id
        _other -> nil
      end)
      |> MapSet.new()

    1
    |> Stream.iterate(&(&1 + 1))
    |> Stream.map(&(@minted_prefix <> Integer.to_string(&1)))
    |> Enum.find(&(not MapSet.member?(taken, &1)))
  end

  @spec cast(field(), term()) :: term()
  defp cast(:id, value), do: value
  defp cast(_optional, ""), do: nil
  defp cast(_optional, value), do: value

  @spec neighbour(non_neg_integer(), term()) :: {:ok, integer()} | :error
  defp neighbour(index, :up), do: {:ok, index - 1}
  defp neighbour(index, :down), do: {:ok, index + 1}
  defp neighbour(index, "up"), do: neighbour(index, :up)
  defp neighbour(index, "down"), do: neighbour(index, :down)
  defp neighbour(_index, _other), do: :error

  @spec in_range?([DatamodelEntry.t() | String.t()], term()) :: boolean()
  defp in_range?(entries, index) when is_integer(index),
    do: index >= 0 and index < length(entries)

  defp in_range?(_entries, _index), do: false

  @spec swap([entry], non_neg_integer(), non_neg_integer()) :: [entry]
        when entry: DatamodelEntry.t() | String.t()
  defp swap(entries, a, b) do
    at_a = Enum.at(entries, a)
    at_b = Enum.at(entries, b)

    entries
    |> List.replace_at(a, at_b)
    |> List.replace_at(b, at_a)
  end
end
