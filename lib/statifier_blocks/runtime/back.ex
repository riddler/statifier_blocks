defmodule StatifierBlocks.Runtime.Back do
  @moduledoc """
  Whether Back is offered to one execution, read from its datamodel.

  A document with a returnable step compiles with a trail in the chart's own
  datamodel and answers the reserved event `statifier_blocks.back`
  (ADR-0004's Amendment of 2026-11-20, `L1` to `L6`). A host that offers a
  Back control needs to know, for one execution, whether delivering that
  event would take it anywhere, without reading the trail's shape itself.
  `offered?/3` is that answer: a pure function of the execution's
  datamodel, its active leaf states and the document it runs, with no
  process, store or engine call.

  ## What "offered" means

  Back takes an execution to the returnable step it entered most recently
  **behind its current position** (`L4`). So the answer is not whether a
  trail is non-empty, but whether it holds a step behind the position:

    * **Inside a returnable step**, the step's own entry is the trail's top,
      so Back is offered when something is below it. At the first step of a
      registration the trail holds that step alone, and Back does nothing
      (`L5`).
    * **Anywhere else in the scope**, Back re-enters the trail's top step,
      so it is offered when the trail is non-empty.

  An empty trail offers nothing (`L5`): a finished document or lane, a
  scope just past a `core.checkpoint`, a document with no returnable step.

  ## Which trail: the scopes around the position

  A trail belongs to a **trail scope** (`L1`): the document, a
  `core.foreach` body or a `core.parallel` lane. Each active leaf state is
  read against the trail scopes that enclose it, innermost first, found
  from the block that produced the leaf and its path in `document`:

    * when the leaf is inside the innermost scope's top step, that scope's
      trail answers alone, because the step's own last Back transition
      takes the event whatever is behind it (`L5`);
    * otherwise the leaf offers Back when any enclosing scope's trail is
      non-empty. An enclosing scope's trail was cleared on entering the
      loop or the parallel that opened the inner one (`L6`), so in practice
      it is the innermost scope's trail that answers.

  Back is offered when at least one active leaf offers it: lanes of a
  `core.parallel` run at once, and each answers for its own position.

  A trail whose scope encloses no active leaf answers nothing. That keeps a
  lane stopped by `complete: "first"`, or a loop body left by an interrupt,
  from offering Back through the entries it still holds.

  ## Reading the inputs

  `datamodel` is the execution's datamodel, keyed by root id. The trail
  roots are read by the names `L1` gives them; anything else in it is
  never read, so no response a person submitted is consulted (`L7`).

  `active` is the execution's active **leaf** states, as
  `Statifier.active_leaf_states/1` answers them: a list or a set of state
  ids. Pass the leaves only, never their ancestors: an ancestor such as the
  root block's own state is not inside any step, so it would read the
  trail's top as behind it and answer `true` at a first step where Back
  does nothing. A leaf whose id this package did not mint (a block type
  minting its states through `StatifierBlocks.Compiler.Context.role_id/2`
  never emits one), or whose block `document` does not carry, offers
  nothing; so does an execution with no active leaf.

  `document` is the document the execution's chart was compiled from.
  """

  alias StatifierBlocks.Compiler.{StateId, Trail}
  alias StatifierBlocks.Document

  @doc ~S"""
  Whether delivering `statifier_blocks.back` to the execution whose
  datamodel is `datamodel` and whose active leaf states are `active` would
  re-enter a returnable step of `document`.

  `true` when, at some active leaf, the trail of a scope around it holds a
  returnable step behind that position; `false` otherwise, and always for
  a document with no returnable step.

      iex> alias StatifierBlocks.{Block, Document}
      iex> step = &Block.new("library.collect", id: &1)
      iex> root = Block.new("core.sequence", id: "blk_ROOT", slots: %{"body" => [step.("blk_NAME"), step.("blk_CARD"), step.("blk_RULES")]})
      iex> document = Document.new(root)
      iex> StatifierBlocks.Runtime.Back.offered?(%{"s_blk_ROOT__trail" => ["s_blk_NAME", []]}, ["s_blk_NAME__waiting"], document)
      false
      iex> StatifierBlocks.Runtime.Back.offered?(%{"s_blk_ROOT__trail" => ["s_blk_CARD", ["s_blk_NAME", []]]}, ["s_blk_CARD__waiting"], document)
      true
      iex> StatifierBlocks.Runtime.Back.offered?(%{"s_blk_ROOT__trail" => ["s_blk_CARD", ["s_blk_NAME", []]]}, ["s_blk_RULES__waiting"], document)
      true
      iex> StatifierBlocks.Runtime.Back.offered?(%{"s_blk_ROOT__trail" => []}, ["s_blk_ROOT__o_done"], document)
      false
      iex> StatifierBlocks.Runtime.Back.offered?(%{"responses" => %{}}, ["s_blk_CARD__waiting"], document)
      false
  """
  @spec offered?(map(), Enumerable.t(StateId.t()), Document.t()) :: boolean()
  def offered?(datamodel, active, %Document{} = document) when is_map(datamodel) do
    Enum.any?(active, &leaf_offers?(datamodel, &1, document))
  end

  defp leaf_offers?(datamodel, leaf, document) do
    with {:ok, {block_id, _role}} <- StateId.unstate_id(leaf),
         {:ok, path} <- Document.fetch_path(document, block_id) do
      case trails(datamodel, document, path) do
        [] -> false
        [innermost | _outer] = trails -> answer(block_id, innermost, trails)
      end
    else
      :error -> false
    end
  end

  # The trails of the scopes enclosing a block at `path`, innermost first:
  # a `core.foreach` body or `core.parallel` lane is a slot whose scope
  # state is minted under the slot's own name as its role (`L1`), and the
  # document scope encloses every block.
  defp trails(datamodel, %Document{root: root}, path) do
    nested =
      for {parent_id, slot, _index} <- path,
          {:ok, scope_state} <- [StateId.state_id(parent_id, slot)],
          {:ok, trail} <- [Map.fetch(datamodel, Trail.root_id(scope_state))],
          do: trail

    document_trail =
      case Map.fetch(datamodel, Trail.root_id(StateId.state_id(root.id))) do
        {:ok, trail} -> [trail]
        :error -> []
      end

    Enum.reverse(nested) ++ document_trail
  end

  # Inside the innermost scope's top step, Back reaches only the step below
  # it; anywhere else, any enclosing trail's top step is behind the leaf.
  defp answer(block_id, [top, below], trails) when is_binary(top) do
    if top_block(top) == block_id, do: below != [], else: Enum.any?(trails, &(&1 != []))
  end

  defp answer(_block_id, _innermost, trails), do: Enum.any?(trails, &(&1 != []))

  defp top_block(top) do
    case StateId.unstate_id(top) do
      {:ok, {block_id, _role}} -> block_id
      :error -> nil
    end
  end
end
