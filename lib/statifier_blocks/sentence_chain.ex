defmodule StatifierBlocks.SentenceChain do
  @moduledoc false

  # ADR-0005's 2026-09-07 three-way chain, written once.
  #
  # | The block | this answers |
  # |---|---|
  # | its type declares `sentence/1`, and the reader accepts the return | that string |
  # | its type declares no usable `sentence/1`, and the author gave a `title` | the author's `title` |
  # | neither | the type's label, falling back to the type name |
  #
  # Two surfaces draw a block's line: `StatifierBlocks.ViewModel` builds it
  # into `Node.sentence` for the card, and `StatifierBlocks.Compiler` names
  # the owning composite in a writer finding. They held two copies of the
  # chain and the compiler's copy stopped at the type's label, so a
  # composite declaring no `sentence/1` and carrying an author's `label`
  # was named one way on its card and another way in a `:type_mismatch`
  # sentence - the hazard `ViewModel.sentence/1`'s docstring exists to
  # prevent. The chain lives here because the compiler holds no view model
  # and `ViewModel.sentence/1` is not callable from it.
  #
  # Internal: no host calls into this module, and nothing here is public
  # surface. The public readers stay where they are -
  # `StatifierBlocks.BlockType.sentence/2` answers the first rung and
  # `ViewModel.sentence/1` answers a built node's line.

  alias StatifierBlocks.{Block, BlockType, Palette}

  # ADR-0005's 2026-09-07 three-way chain. `declares?/1` is asked
  # separately from the reader's answer because the two records draw the
  # line in different places and both lines matter: a type that declares
  # NOTHING may land on the author's `title` (ADR-0005 row two), while a
  # declared callback that raises, throws, exits or answers something
  # unusable lands on the type's label and never on the title (ADR-0002
  # row three, restated in ADR-0005 as "never the author's `title`"). The
  # reader answers a string in both cases, so declaredness is the only
  # thing that separates them.
  @spec sentence(
          Palette.type_ref(),
          Block.config(),
          BlockType.palette_entry(),
          String.t() | nil,
          Block.type_name()
        ) ::
          String.t()
  def sentence(ref, config, entry, title, type) do
    label = Map.get(entry, :label) || type

    if Palette.declares?(ref, :sentence, 1) do
      BlockType.sentence(ref, config) || label
    else
      title || label
    end
  end

  # The author's own name for this block, or `nil`, for a caller holding a
  # type ref rather than a schema it already read.
  @spec title(Palette.type_ref(), Block.config()) :: String.t() | nil
  def title(ref, config) do
    ref
    |> Palette.call(:config_schema, [config], [])
    |> title_override(config)
  end

  # The palette entry a caller that has not built one already reads the
  # label out of. `sentence/5`'s own `|| type` supplies the type-name
  # fallback, so no default is merged in here.
  @spec palette_entry(Palette.type_ref()) :: BlockType.palette_entry()
  def palette_entry(ref), do: Palette.call(ref, :palette_entry, [], %{})

  # The author's own name for this block, or `nil`.
  #
  # A declared `:string` field keyed `label` is the seam, and it is the whole
  # of it: a block type that wants its instances named says so the same way it
  # declares any other field, and a type that declares none has no title
  # override rather than a special case. Read through `BlockType.value_path/1`
  # like every other field's value, so a type that stores its name somewhere
  # other than `config["label"]` is read where it actually put it.
  #
  # No block type in the `core.*` vocabulary declares one. That is the
  # intended shape rather than a gap: "Wait" is what a wait is called, and a
  # type whose steps are worth naming individually is a host's.
  @spec title_override([BlockType.field_decl()], Block.config()) :: String.t() | nil
  def title_override(schema, config) do
    with %{} = field <- Enum.find(schema, &(&1.key == "label" and &1.type == :string)),
         {:ok, value} <- BlockType.fetch_value(config, BlockType.value_path(field)) do
      non_empty_string(value)
    else
      _undeclared_or_absent -> nil
    end
  end

  @spec non_empty_string(term()) :: String.t() | nil
  defp non_empty_string(value) when is_binary(value) do
    if String.trim(value) == "", do: nil, else: value
  end

  defp non_empty_string(_value), do: nil
end
