defmodule StatifierBlocks.Palette.Preflight do
  @moduledoc false
  # The work behind `StatifierBlocks.Palette.preflight/1` and `/2`: the
  # binding check (ADR-0002 decision 7, amended 2026-09-28) asked of a
  # palette's host types and of a host's stored documents, before the
  # package asks it at compile, at the edit gate and in the view model.
  #
  # Every step a callback can raise in is one `attempt/2` call, so a raising
  # type answers one finding naming the step and the palette is still
  # walked to its end.

  alias StatifierBlocks.{Block, BlockType, Document, Palette}

  @spec palette(Palette.t()) :: [Palette.preflight_finding()]
  def palette(%Palette{types: types} = palette) do
    core = Palette.core_types()

    types
    |> Enum.reject(fn {name, ref} -> Map.get(core, name) == ref end)
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.flat_map(fn {name, ref} -> host_type(palette, name, ref) end)
  end

  @spec documents(Palette.t(), [Document.t()]) :: [Palette.preflight_finding()]
  def documents(%Palette{} = palette, documents) when is_list(documents) do
    for %Document{} = document <- documents,
        block <- Document.blocks(document),
        finding <- block(palette, block),
        do: finding
  end

  # A type's defaults, each judged against the declaration that carries it,
  # and then the block `Palette.new_block/2` builds from them: the config a
  # freshly inserted block starts from. The two usually find the same
  # value, which is one finding, not two. A `config_schema(%{})` that
  # raises is the type's one finding: `new_block/2` would only raise it
  # again.
  @spec host_type(Palette.t(), Block.type_name(), Palette.type_ref()) ::
          [Palette.preflight_finding()]
  defp host_type(palette, name, ref) do
    defaults =
      guard(:config_schema, fn ->
        ref
        |> Palette.call(:config_schema, [%{}], [])
        |> Enum.flat_map(&default_violations/1)
      end)

    violations =
      case defaults do
        [{:raised, _step, _message}] ->
          defaults

        _judged ->
          defaults ++
            guard(:new_block, fn ->
              {:ok, block} = Palette.new_block(palette, name)
              violations(ref, block.config)
            end)
      end

    violations
    |> Enum.map(&finding(name, nil, &1))
    |> Enum.uniq()
  end

  # The default placed where the field's value lives, so the binding check
  # reads it exactly as it reads a stored value. A declaration with no
  # `default` key is the compiler's own refusal and is not judged here.
  @spec default_violations(term()) :: [violation()]
  defp default_violations(%{default: default} = decl) do
    path = BlockType.value_path(decl)
    config = List.foldr(path, default, fn key, inner -> %{key => inner} end)
    BlockType.field_type_violations([decl], config)
  end

  defp default_violations(_no_default), do: []

  # A document block is judged as the compiler judges it: resolved (and
  # migrated in memory) through the palette first. A block whose type the
  # palette does not carry, or that does not resolve, is not judged: its
  # refusal is `Palette.resolve/2`'s, and it is one today.
  @spec block(Palette.t(), Block.t()) :: [Palette.preflight_finding()]
  defp block(palette, %Block{type: name, id: id} = block) do
    case Palette.fetch(palette, name) do
      {:ok, _ref} -> palette |> carried_block(block) |> Enum.map(&finding(name, id, &1))
      {:error, _unknown} -> []
    end
  end

  @spec carried_block(Palette.t(), Block.t()) :: [violation() | raised()]
  defp carried_block(palette, block) do
    case attempt(:resolve, fn -> Palette.resolve(palette, block) end) do
      {:ok, {:ok, ref, resolved}} ->
        guard(:config_schema, fn -> violations(ref, resolved.config) end)

      {:ok, {:error, _reason}} ->
        []

      {:raised, _step, _message} = raised ->
        [raised]
    end
  end

  @typep violation :: {BlockType.field_decl(), Block.json(), BlockType.finding()}
  @typep raised :: {:raised, atom(), String.t()}

  @spec violations(Palette.type_ref(), Block.config()) :: [violation()]
  defp violations(ref, config) do
    ref
    |> Palette.call(:config_schema, [config], [])
    |> BlockType.field_type_violations(config)
  end

  @spec guard(atom(), (-> [violation()])) :: [violation() | raised()]
  defp guard(step, fun) do
    case attempt(step, fun) do
      {:ok, violations} -> violations
      raised -> [raised]
    end
  end

  # The one place a host callback's raise, throw or exit is caught: it
  # becomes the step's finding, and the walk goes on.
  @spec attempt(atom(), (-> result)) :: {:ok, result} | raised() when result: term()
  defp attempt(step, fun) do
    {:ok, fun.()}
  rescue
    exception -> {:raised, step, Exception.format_banner(:error, exception, __STACKTRACE__)}
  catch
    kind, reason -> {:raised, step, Exception.format_banner(kind, reason, __STACKTRACE__)}
  end

  @spec finding(Block.type_name(), Block.id() | nil, violation() | raised()) ::
          Palette.preflight_finding()
  defp finding(name, id, {:raised, step, message}) do
    %{type: name, block_id: id, raised: step, message: message}
  end

  defp finding(name, id, {%{key: key, type: declared}, value, {key, message}}) do
    %{type: name, block_id: id, key: key, declared_type: declared, value: value, message: message}
  end
end
