defmodule StatifierBlocks.Composite.Collapse do
  @moduledoc """
  The proposer half of Collapse: an arrangement an author built by hand,
  read back as the `StatifierBlocks.Composite.Data` declaration that stands
  for it (ADR-0005 part (iii), amended 2026-09-07, clauses `15E` to `20E`).

  `propose/3` reads; it writes nothing. It takes no socket, no assigns and
  no `StatifierBlocks.Edit.Session`, it is callable from a test, a script or
  a host's own code with no LiveView in the picture, and it is the only
  entry point this package offers to Collapse's first half.

      {:ok, declaration} = Collapse.propose(document, palette, ["blk_7", "blk_9"])

  ## What comes back is the storable row, minus its name

  The `{:ok, ...}` value is JSON-shaped, in the shape
  `StatifierBlocks.Composite.Data.declaration/1` accepts, with `"version"`,
  `"params"`, `"subtree"` and - where the selection holds an unfilled slot -
  `"slots"`. It carries **no `"type_name"`** (`15E`): a type name is a key
  in the *host's* palette namespace, the host is the only party that knows
  what is registered there, and a package that minted one would be minting
  a collision it cannot see. So `declaration/1` refuses the row until the
  host names it, and that refusal is the seam working rather than a gap in
  it.

  `"sentence"` and `"palette_entry"` are omitted for the same reason at one
  remove: both are prose or presentation the author never typed in this
  gesture, and a proposer that invented an English sentence or an icon
  would be inventing content and calling it a proposal.

  ## Which values become params

  `18E`. The proposed params are the config values the author **marks** in
  the gesture; where the author marks none, every value that differs from
  its field's declared default. A value left at its default is a value the
  author never chose, and a param whose default is the field's default
  parameterises nothing.

  The marks are the gesture's, so they arrive beside the three arguments
  `15E` fixes rather than inside them: `propose/4`'s option list carries
  `marks: %{block_id => [field key]}`, and `propose/3` - the record's entry
  point, and the whole of what a caller with no gesture behind it needs -
  is the unmarked reading. Neither of the three arguments is a name, which
  is the property `RQ-SF038-1` fixes the arity for.

  Each param's field declaration is the **source field's**: its `"type"`,
  `"label"` and whichever of `"required?"`, `"value_path"`,
  `"datamodel_path?"`, `"hidden?"` and `"readonly?"` the source field
  declares, carried across unchanged, with `"default"` set to the value the
  block's config held. Nothing is re-derived, so the control the author
  sees on the composite's form is the control they were looking at on the
  block.

  A param's key is the source field's key. Where two blocks in one
  arrangement declare the same field key - two `core.assign`s both declare
  `path` - every colliding param takes `<id_suffix>_<field key>` instead
  and the un-colliding ones keep their bare keys.

  ## The template, and the ids it mints

  The template is the subtree with each proposed value replaced by
  `%{"$param" => key}` and every other config value carried across as the
  literal it is. A value that genuinely *is* a one-key `"$param"` (or
  `"$literal"`) map is carried as `%{"$literal" => ...}`, which is what
  that escape exists for.

  `"id_suffix"` is minted from the source block's **type**, not from its
  id: the type name's last dot-separated segment - `core.invoke` gives
  `invoke`, `core.assign` gives `assign` - with a positional discriminator
  appended where a type repeats, in document order: `assign`, `assign_2`,
  `assign_3`. A document id is arbitrary (`blk_7`), carries no meaning to a
  later reader, and need not match the `"id_suffix"` pattern, while a type
  segment does.

  One consequence, stated because it is sharp: a `use`-composite twin of a
  collapsed declaration expands byte-identically **only if its authored
  `id_suffix`es are the ones this rule mints**. ADR-0002's "Guarded step"
  is authored with `call` and `guard`, so its expansion's ids are
  `blk_GS_call` and `blk_GS_guard` where a collapse of the same arrangement
  mints `blk_GS_invoke` and `blk_GS_assign`. The configs, the types and the
  tree shape are identical; the ids are not, and the rule cannot ask an
  author who is not there.

  ## Slots

  `20E`. Exactly one subtree under one parent (`12E`, unamended): two
  siblings, a block and a cousin, or a partial subtree with a child left
  outside are refused. A selection whose subtree holds an **unfilled** slot
  is admitted, and that slot is proposed as a pass-through slot -
  `"slots" => %{name => [local_id, inner_slot]}` - in the shape ADR-0002's
  pass-through amendment fixes. A **filled** slot is not proposed and its
  children are not lifted: they are part of what the author selected, and a
  Collapse that silently turned them into an opening would be deciding for
  the author that the blocks they put there were an example rather than the
  thing.

  ## The replacement is a separate function the host calls, or does not

  `17E`. `replacement/4` answers the `{:compound, ...}` that puts the
  composite where the arrangement was. Nothing in this package calls it:
  the gesture does not, and `on_collapse` does not. A host that saves a
  declaration and never swaps the arrangement out has done a legitimate
  thing, and the swap can only happen after the host has stored the
  declaration, named it and rebuilt its palette with it - until then the
  `:insert` names a type the document cannot resolve.
  """

  alias StatifierBlocks.{Block, BlockType, Document, Edit, Palette}

  @typedoc """
  The proposed row: JSON-shaped, in `Composite.Data`'s declaration shape and
  without its `"type_name"`.
  """
  @type declaration :: %{optional(String.t()) => term()}

  @typedoc "Which config values the gesture marked, per block."
  @type marks :: %{optional(Block.id()) => [String.t()]}

  # One member of the selection, resolved: the block as the palette answers
  # it, the entry to call callbacks on, and the `"id_suffix"` this collapse
  # minted for it.
  @typep member :: %{block: Block.t(), ref: Palette.type_ref(), suffix: String.t()}

  # One proposed param, before its key is settled: collisions are resolved
  # across the whole list, so the key cannot be minted per field.
  @typep proposal :: %{
           block_id: Block.id(),
           suffix: String.t(),
           field: BlockType.field_decl(),
           value: term()
         }

  @version 1

  # -- propose -----------------------------------------------------------

  @doc """
  Reads a selection back as the declaration that stands for it.

  Answers `{:ok, declaration}` - the storable row without its
  `"type_name"` - or `{:error, reason}`. Nothing is written in either case
  and the document is not touched.

  The refusals, each a refused **gesture** and none of them a finding:

    * `{:error, {:not_one_subtree, ids}}` - the selection is not exactly one
      subtree under one parent (`12E`);
    * `{:error, {:no_such_block, id}}` - an id the document does not hold;
    * `{:error, {:cannot_collapse_root, id}}` - the document root, which has
      no target a composite could take;
    * `{:error, {:unspellable_field, block_id, field_key}}` - a value no
      `Composite.Data` spelling carries (`19E`). Two ids, because "this
      arrangement cannot be saved" is not actionable and "the `payload`
      field on `blk_13` cannot be saved" is;
    * whatever `StatifierBlocks.Palette.resolve/2` refuses a member with.

  Options:

    * `:marks` - `%{block_id => [field key]}`, the config values the gesture
      marked. Absent, or an empty map - which is what a tray with nothing
      ticked hands over - is `18E`'s unmarked reading: every value that
      differs from its field's declared default.

      iex> alias StatifierBlocks.{Block, Document, Palette}
      iex> alias StatifierBlocks.Composite.Collapse
      iex> document =
      ...>   Document.new(
      ...>     Block.new("core.sequence",
      ...>       id: "blk_ROOT",
      ...>       slots: %{
      ...>         "body" => [
      ...>           Block.new("core.assign",
      ...>             id: "blk_9",
      ...>             config: %{"path" => "signup.state", "value" => "done"}
      ...>           )
      ...>         ]
      ...>       }
      ...>     )
      ...>   )
      iex> {:ok, declaration} = Collapse.propose(document, Palette.core(), ["blk_9"])
      iex> Enum.map(declaration["params"], & &1["key"])
      ["path", "value"]
      iex> Map.has_key?(declaration, "type_name")
      false
  """
  @spec propose(Document.t(), Palette.t(), [Block.id()]) ::
          {:ok, declaration()} | {:error, term()}
  @spec propose(Document.t(), Palette.t(), [Block.id()], keyword()) ::
          {:ok, declaration()} | {:error, term()}
  def propose(document, palette, ids, opts \\ [])

  def propose(%Document{} = document, %Palette{} = palette, ids, opts) when is_list(ids) do
    # `18E`'s "where the author marks none": a gesture that ticked nothing
    # hands over an EMPTY map rather than no map at all, and the two have to
    # mean the same thing or a tray with nothing ticked would propose a step
    # with no params - which is not a step.
    marks =
      case Keyword.get(opts, :marks, %{}) do
        empty when empty == %{} -> :unmarked
        marks -> marks
      end

    with {:ok, root} <- selection_root(document, ids),
         {:ok, members} <- members(palette, root),
         {:ok, proposals} <- proposals(members, marks),
         {:ok, params, placeholders} <- params(proposals) do
      {:ok, row(members, params, placeholders)}
    end
  end

  # -- replacement -------------------------------------------------------

  @doc """
  The compound that puts a composite of `type_name` where the arrangement
  was: the exact inverse of Expand.

      {:compound, [{:remove, root_id}, {:insert, target, block}]}

  `target` is the arrangement's own - the same parent, the same slot, the
  same index the selection's root held - and the inserted block's config is
  each param's declared `"default"`, which by `18E` is the value the author
  had selected, so the composite expands to the arrangement they started
  with. Removing first and inserting at the freed position is Expand's
  ordering read backwards, and one remove with one insert is one undo entry
  (`2n`, `3E`), so the author sees one gesture and no intermediate document
  in which the arrangement is gone and the composite is not yet there.

  The host commits it through `StatifierBlocks.Edit.Session.commit/2`. It
  is answered rather than committed here, and refused rather than raised
  where the document cannot carry it: `{:error, {:no_such_block, id}}` for
  an id the document does not hold, `{:error, {:cannot_collapse_root, id}}`
  for the root.
  """
  @spec replacement(Document.t(), Block.id(), Block.type_name(), declaration()) ::
          {:ok, Edit.t()} | {:error, term()}
  def replacement(%Document{} = document, root_id, type_name, declaration)
      when is_binary(root_id) and is_binary(type_name) and is_map(declaration) do
    case Document.fetch_path(document, root_id) do
      {:ok, []} ->
        {:error, {:cannot_collapse_root, root_id}}

      {:ok, path} ->
        config =
          declaration
          |> Map.get("params", [])
          |> Map.new(fn param -> {param["key"], param["default"]} end)

        block = Block.new(type_name, config: config)

        {:ok, {:compound, [{:remove, root_id}, {:insert, List.last(path), block}]}}

      :error ->
        {:error, {:no_such_block, root_id}}
    end
  end

  # -- 12E: exactly one subtree under one parent -------------------------

  # The selection is one subtree when exactly one of its ids has no parent
  # inside the selection AND every block under that id is in the selection
  # too. The second half is what refuses a partial subtree with a child left
  # outside, which the first half alone would admit.
  @spec selection_root(Document.t(), [Block.id()]) :: {:ok, Block.t()} | {:error, term()}
  defp selection_root(%Document{root: document_root} = document, ids) do
    blocks = Map.new(Document.blocks(document), &{&1.id, &1})
    selected = MapSet.new(ids)
    parents = parents(document)

    cond do
      ids == [] ->
        {:error, {:not_one_subtree, ids}}

      (missing = Enum.reject(ids, &Map.has_key?(blocks, &1))) != [] ->
        {:error, {:no_such_block, hd(missing)}}

      true ->
        roots =
          ids |> Enum.reject(&MapSet.member?(selected, Map.get(parents, &1))) |> Enum.uniq()

        one_subtree(roots, blocks, selected, ids, document_root.id)
    end
  end

  @spec one_subtree(
          [Block.id()],
          %{optional(Block.id()) => Block.t()},
          MapSet.t(Block.id()),
          [Block.id()],
          Block.id()
        ) :: {:ok, Block.t()} | {:error, term()}
  defp one_subtree([root_id], _blocks, _selected, _ids, root_id),
    do: {:error, {:cannot_collapse_root, root_id}}

  defp one_subtree([root_id], blocks, selected, ids, _document_root_id) do
    root = Map.fetch!(blocks, root_id)

    if MapSet.equal?(MapSet.new(subtree_blocks(root), & &1.id), selected),
      do: {:ok, root},
      else: {:error, {:not_one_subtree, ids}}
  end

  defp one_subtree(_none_or_many, _blocks, _selected, ids, _document_root_id),
    do: {:error, {:not_one_subtree, ids}}

  @spec parents(Document.t()) :: %{optional(Block.id()) => Block.id()}
  defp parents(%Document{root: root}) do
    root
    |> subtree_blocks()
    |> Enum.flat_map(fn %Block{id: id, slots: slots} ->
      for {_slot, children} <- slots, %Block{id: child} <- children, do: {child, id}
    end)
    |> Map.new()
  end

  # `Document.blocks/1`'s walk, over one block rather than a whole document:
  # the block, then its slots in UTF-8-sorted name order. It is the order
  # `18E`'s "document order" means, and it is deterministic however the
  # slots map happened to be built.
  @spec subtree_blocks(Block.t()) :: [Block.t()]
  defp subtree_blocks(%Block{slots: slots} = block) do
    children =
      slots
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.flat_map(fn {_slot, kids} -> kids end)
      |> Enum.flat_map(&subtree_blocks/1)

    [block | children]
  end

  # -- resolving the members, and minting their suffixes -----------------

  @spec members(Palette.t(), Block.t()) :: {:ok, [member()]} | {:error, term()}
  defp members(palette, root) do
    root
    |> subtree_blocks()
    |> Enum.reduce_while({:ok, []}, fn block, {:ok, acc} ->
      case Palette.resolve(palette, block) do
        {:ok, ref, resolved} -> {:cont, {:ok, [{resolved, ref} | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, reversed} -> {:ok, mint_suffixes(Enum.reverse(reversed))}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec mint_suffixes([{Block.t(), Palette.type_ref()}]) :: [member()]
  defp mint_suffixes(pairs) do
    {members, _taken} =
      Enum.map_reduce(pairs, MapSet.new(), fn {block, ref}, taken ->
        suffix = free_suffix(segment(block.type), taken, 1)
        {%{block: block, ref: ref, suffix: suffix}, MapSet.put(taken, suffix)}
      end)

    members
  end

  # The type name's last dot-separated segment, held to the `"id_suffix"`
  # pattern `Composite.Data` enforces: lowercase, and no run of anything
  # else. A type whose segment is empty after that has no name to mint from,
  # so it mints `node` and takes the ordinary positional discriminator.
  @spec segment(Block.type_name()) :: String.t()
  defp segment(type) do
    type
    |> String.split(".")
    |> List.last()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "_")
    |> String.trim("_")
    |> case do
      "" -> "node"
      segment -> segment
    end
  end

  @spec free_suffix(String.t(), MapSet.t(String.t()), pos_integer()) :: String.t()
  defp free_suffix(segment, taken, 1) do
    if MapSet.member?(taken, segment), do: free_suffix(segment, taken, 2), else: segment
  end

  defp free_suffix(segment, taken, n) do
    candidate = "#{segment}_#{n}"

    if MapSet.member?(taken, candidate), do: free_suffix(segment, taken, n + 1), else: candidate
  end

  # -- 18E: which values become params -----------------------------------

  @spec proposals([member()], marks() | :unmarked) :: {:ok, [proposal()]} | {:error, term()}
  defp proposals(members, marks) do
    {:ok,
     Enum.flat_map(members, fn %{block: block, ref: ref, suffix: suffix} ->
       ref
       |> Palette.call(:config_schema, [block.config], [])
       |> Enum.filter(&marked?(&1, block, marks))
       |> Enum.map(fn field ->
         %{block_id: block.id, suffix: suffix, field: field, value: value(block, field)}
       end)
     end)}
  end

  @spec marked?(BlockType.field_decl(), Block.t(), marks() | :unmarked) :: boolean()
  defp marked?(field, block, :unmarked), do: value(block, field) != field.default

  defp marked?(field, block, marks) when is_map(marks),
    do: field.key in Map.get(marks, block.id, [])

  # A field's value is where its `value_path` says it is, which for most
  # fields is `[key]` and for `core.branch`'s arms is a key, an index and a
  # key. Reading `config[key]` instead would read `nil` for every such field
  # and propose the wrong default at the wrong place.
  @spec value(Block.t(), BlockType.field_decl()) :: term()
  defp value(%Block{config: config}, field) do
    case BlockType.fetch_value(config, BlockType.value_path(field)) do
      {:ok, value} -> value
      :error -> field.default
    end
  end

  # A param's key is its source field's, unless two blocks declared the same
  # one - two `core.assign`s both declare `path` - in which case every
  # colliding param takes `<id_suffix>_<field key>` and the un-colliding
  # ones keep their bare keys.
  @spec params([proposal()]) ::
          {:ok, [map()],
           %{optional({Block.id(), String.t()}) => {BlockType.value_path(), String.t()}}}
          | {:error, term()}
  defp params(proposals) do
    keys = Enum.map(proposals, & &1.field.key)
    colliding = MapSet.new(keys -- Enum.uniq(keys))

    proposals
    |> Enum.reduce_while({:ok, [], %{}}, fn proposal, {:ok, acc, placeholders} ->
      case param(proposal, colliding) do
        {:ok, param} ->
          key = {proposal.block_id, proposal.field.key}
          path = BlockType.value_path(proposal.field)
          {:cont, {:ok, [param | acc], Map.put(placeholders, key, {path, param["key"]})}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, reversed, placeholders} -> {:ok, Enum.reverse(reversed), placeholders}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec param(proposal(), MapSet.t(String.t())) :: {:ok, map()} | {:error, term()}
  defp param(%{field: field, value: value, block_id: block_id} = proposal, colliding) do
    case spell(field.type) do
      {:ok, type, options} when is_map(options) or options == :none ->
        if json?(value) do
          param =
            %{
              "key" => param_key(proposal, colliding),
              "type" => type,
              "label" => field.label,
              "default" => value
            }
            |> put_options(options)
            |> put_flags(field)

          {:ok, param}
        else
          {:error, {:unspellable_field, block_id, field.key}}
        end

      :error ->
        {:error, {:unspellable_field, block_id, field.key}}
    end
  end

  @spec param_key(proposal(), MapSet.t(String.t())) :: String.t()
  defp param_key(%{field: %{key: key}, suffix: suffix}, colliding) do
    if MapSet.member?(colliding, key), do: "#{suffix}_#{key}", else: key
  end

  @spec put_options(map(), map() | :none) :: map()
  defp put_options(param, :none), do: param
  defp put_options(param, options), do: Map.put(param, "options", options)

  @spec put_flags(map(), BlockType.field_decl()) :: map()
  defp put_flags(param, field) do
    Enum.reduce(
      [:required?, :value_path, :datamodel_path?, :hidden?, :readonly?],
      param,
      fn flag, acc ->
        case Map.fetch(field, flag) do
          {:ok, value} -> Map.put(acc, Atom.to_string(flag), value)
          :error -> acc
        end
      end
    )
  end

  # -- 19E: the spellings, written out ------------------------------------

  # `Composite.Data`'s decoder read backwards: a field type to its `"type"`
  # name and the `"options"` that carry its second element, or `:error`
  # where nothing carries it.
  @spec spell(BlockType.field_type()) :: {:ok, String.t(), map() | :none} | :error
  defp spell(:string), do: {:ok, "string", :none}
  defp spell(:integer), do: {:ok, "integer", :none}
  defp spell(:boolean), do: {:ok, "boolean", :none}
  defp spell(:expression), do: {:ok, "expression", :none}
  defp spell(:duration), do: {:ok, "duration", :none}

  defp spell({:select, choices}) when is_list(choices) and choices != [] do
    if Enum.all?(choices, fn
         {value, label} -> is_binary(value) and is_binary(label)
         _other -> false
       end) do
      {:ok, "select", %{"choices" => Enum.map(choices, fn {value, label} -> [value, label] end)}}
    else
      :error
    end
  end

  defp spell({:path, opts}) when is_map(opts) do
    if Enum.all?(opts, fn {key, value} ->
         key in [:expects, :writes] and is_binary(value) and value != ""
       end) do
      {:ok, "path", Map.new(opts, fn {key, value} -> {Atom.to_string(key), value} end)}
    else
      :error
    end
  end

  defp spell({:list, inner}) do
    case spell(inner) do
      {:ok, type, :none} -> {:ok, "list", %{"inner" => %{"type" => type}}}
      {:ok, type, options} -> {:ok, "list", %{"inner" => %{"type" => type, "options" => options}}}
      :error -> :error
    end
  end

  defp spell({:type_expr, opts}) when is_map(opts) do
    arms = Map.get(opts, :arms, :absent)
    allow_empty? = Map.get(opts, :allow_empty?, :absent)

    cond do
      Map.keys(opts) -- [:arms, :allow_empty?] != [] -> :error
      arms != :absent and not spellable_arms?(arms) -> :error
      allow_empty? != :absent and not is_boolean(allow_empty?) -> :error
      true -> {:ok, "type_expr", type_expr_options(arms, allow_empty?)}
    end
  end

  defp spell(_field_type), do: :error

  @spec spellable_arms?(term()) :: boolean()
  defp spellable_arms?(arms) when is_list(arms) and arms != [],
    do: arms == Enum.uniq(arms) and Enum.all?(arms, &(&1 in [:name, :inline]))

  defp spellable_arms?(_arms), do: false

  @spec type_expr_options(term(), term()) :: map()
  defp type_expr_options(arms, allow_empty?) do
    %{}
    |> then(fn options ->
      if arms == :absent,
        do: options,
        else: Map.put(options, "arms", Enum.map(arms, &Atom.to_string/1))
    end)
    |> then(fn options ->
      if allow_empty? == :absent,
        do: options,
        else: Map.put(options, "allow_empty?", allow_empty?)
    end)
  end

  # A `"default"` a declaration cannot hold is as unspellable as a field
  # type it cannot name, and the refusal is the same one.
  @spec json?(term()) :: boolean()
  defp json?(value)
       when is_binary(value) or is_number(value) or is_boolean(value) or is_nil(value),
       do: true

  defp json?(value) when is_list(value), do: Enum.all?(value, &json?/1)

  defp json?(value) when is_map(value) and not is_struct(value),
    do: Enum.all?(value, fn {key, inner} -> is_binary(key) and json?(inner) end)

  defp json?(_value), do: false

  # -- the row --------------------------------------------------------------

  @spec row([member()], [map()], map()) :: declaration()
  defp row([root | _rest] = members, params, placeholders) do
    slots = pass_through_slots(members)

    %{
      "version" => @version,
      "params" => params,
      "subtree" => [template(root, members, placeholders)]
    }
    |> then(fn row -> if slots == %{}, do: row, else: Map.put(row, "slots", slots) end)
  end

  @spec template(member(), [member()], map()) :: map()
  defp template(%{block: block, suffix: suffix} = member, members, placeholders) do
    slots = template_slots(member, members, placeholders)

    %{
      "type" => block.type,
      "id_suffix" => suffix,
      "config" => template_config(block, placeholders)
    }
    |> then(fn node -> if slots == %{}, do: node, else: Map.put(node, "slots", slots) end)
  end

  @spec template_config(Block.t(), map()) :: map()
  defp template_config(%Block{id: id, config: config}, placeholders) do
    literals = Map.new(config, fn {key, value} -> {key, escape(value)} end)

    placeholders
    |> Enum.filter(fn {{block_id, _field}, _param} -> block_id == id end)
    |> Enum.reduce(literals, fn {{_block_id, _field}, {path, param}}, acc ->
      BlockType.put_value(acc, path, %{"$param" => param})
    end)
  end

  # The one-key escape, recursively: `substitute/2` reads `"$param"` and
  # `"$literal"` at every depth, so a config value that genuinely holds one
  # has to be escaped at every depth too.
  @spec escape(term()) :: term()
  defp escape(%{"$param" => _key} = value) when map_size(value) == 1,
    do: %{"$literal" => value}

  defp escape(%{"$literal" => _value} = value) when map_size(value) == 1,
    do: %{"$literal" => value}

  defp escape(value) when is_map(value) and not is_struct(value),
    do: Map.new(value, fn {key, inner} -> {key, escape(inner)} end)

  defp escape(value) when is_list(value), do: Enum.map(value, &escape/1)
  defp escape(value), do: value

  @spec template_slots(member(), [member()], map()) :: map()
  defp template_slots(%{block: block} = member, members, placeholders) do
    filled =
      block.slots
      |> Enum.reject(fn {_name, children} -> children == [] end)
      |> Map.new(fn {name, children} ->
        {name, Enum.map(children, &template(member_of(members, &1.id), members, placeholders))}
      end)

    Map.merge(filled, Map.new(unfilled_slots(member), &{&1, []}))
  end

  @spec member_of([member()], Block.id()) :: member()
  defp member_of(members, id), do: Enum.find(members, &(&1.block.id == id))

  # -- 20E: an unfilled slot is proposed as a pass-through slot -----------

  @spec pass_through_slots([member()]) :: map()
  defp pass_through_slots(members) do
    proposed =
      Enum.flat_map(members, fn %{suffix: suffix} = member ->
        for name <- unfilled_slots(member), do: {name, suffix}
      end)

    names = Enum.map(proposed, &elem(&1, 0))
    colliding = MapSet.new(names -- Enum.uniq(names))

    Map.new(proposed, fn {name, suffix} ->
      key = if MapSet.member?(colliding, name), do: "#{suffix}_#{name}", else: name
      {key, [suffix, name]}
    end)
  end

  # The slots the member's type declares that hold no children here. A
  # filled slot is not proposed and its children are not lifted (`20E`).
  @spec unfilled_slots(member()) :: [Block.slot_name()]
  defp unfilled_slots(%{block: block, ref: ref}) do
    ref
    |> Palette.call(:slots, [block.config], [])
    |> Enum.map(&elem(&1, 0))
    |> Enum.filter(&(Map.get(block.slots, &1, []) == []))
    |> Enum.sort()
  end
end
