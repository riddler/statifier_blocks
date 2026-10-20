defmodule StatifierBlocks.ReadmeRegistrationTest do
  @moduledoc """
  The registration guide's example is executed, not trusted.

  `readme_test.exs` makes the same argument for the pages it covers, and
  the reason applies with more force here: this page defines a host block
  type from scratch, so a callback that gains an argument or a builder that
  changes shape breaks the very snippet a host copies first. Every elixir
  block on `docs/guides/register-block-types.md` is evaluated once, in
  reading order - the blocks define modules, and evaluating them twice
  would redefine them - and every value the page claims in a `#=>` comment
  is asserted against what the evaluation produced.

  The example runs no LiveView code, so this test runs in the headless
  tree too.
  """

  use ExUnit.Case, async: false

  @page Path.join([__DIR__, "..", "..", "docs", "guides", "register-block-types.md"])
        |> Path.expand()
  @external_resource @page

  setup_all do
    page = File.read!(@page)
    blocks = elixir_blocks_in(page)

    refute blocks == [], "no elixir code blocks found in docs/guides/register-block-types.md"

    {_result, binding} = blocks |> Enum.join("\n\n") |> Code.eval_string([], file: @page)

    %{page: page, binding: binding}
  end

  # Sabotage: pointed the page's registration at `StatifierBlocks.Core.Wait`
  # instead of the module the snippet defines - red on the fetch assert,
  # which is the check that the palette really holds what the snippet says
  # (verified).
  test "the example registers the host type beside the core vocabulary", ctx do
    palette = Keyword.fetch!(ctx.binding, :palette)
    review = Keyword.fetch!(ctx.binding, :review)

    assert review == Module.concat([:MyApp, :Blocks, :LibrarianReview])
    assert StatifierBlocks.Palette.fetch(palette, "myapp.librarian_review") == {:ok, review}

    assert {:ok, StatifierBlocks.Core.Sequence} =
             StatifierBlocks.Palette.fetch(palette, "core.sequence")

    assert map_size(palette.types) == map_size(StatifierBlocks.Palette.core_types()) + 1
  end

  # Sabotage: dropped `@behaviour StatifierBlocks.BlockType` from the
  # page's module - red here, since a host example that does not declare
  # the behaviour is teaching the wrong thing (verified).
  test "the host type is a conforming block type", ctx do
    review = Keyword.fetch!(ctx.binding, :review)

    assert StatifierBlocks.BlockType in (review.module_info(:attributes)[:behaviour] || [])
    assert review.current_version() == 1
    assert review.slots(%{}) == []
    assert review.validate_config(%{"queue" => "front_desk"}) == :ok
    assert {:error, [{"queue", _message}]} = review.validate_config(%{})
  end

  # Sabotage: changed the page entry's badge to a 30-character chip -
  # red here, because the normalizer refuses it and the claimed `#=>` line
  # no longer holds (verified).
  test "the declared badge and accent token normalize to what the page claims", ctx do
    entry = Keyword.fetch!(ctx.binding, :review).palette_entry()

    assert StatifierBlocks.BlockType.badge(entry) == "manual review"
    assert StatifierBlocks.ViewModel.accent_token(entry) == "--sb-accent-myapp-review"
  end

  # Sabotage: edited one `#=>` line on the page to claim a different
  # value - red here, which is the half that catches prose drift a
  # still-passing snippet would hide (verified).
  test "every output the page claims is the one it produces", ctx do
    claimed =
      ctx.page
      |> elixir_blocks_in()
      |> Enum.join("\n")
      |> then(&Regex.scan(~r/^\s*#=> (.+)$/m, &1))
      |> Enum.map(fn [_whole, claim] -> claim end)

    assert claimed == [
             "true",
             ~s("manual review"),
             ~s("--sb-accent-myapp-review"),
             ~s("myapp:print_card"),
             ~s(["label", "invoke_type"]),
             ~s([{"done", "Done"}, {"error", "Error"}]),
             ~s(%{kinds: [:step], produces: "myapp.library_card"})
           ]
  end

  # Sabotage: dropped the `produces:` option from the page's `use` -
  # the declared type stops reaching `io/1` and the claimed `#=>` no
  # longer holds, taking this red (verified).
  test "the declared step answers every callback the section claims" do
    print_card = Module.concat([:MyApp, :Blocks, :PrintCard])

    assert StatifierBlocks.BlockType in (print_card.module_info(:attributes)[:behaviour] || [])
    assert print_card.invoke_type() == "myapp:print_card"
    assert Enum.map(print_card.config_schema(%{}), & &1.key) == ["label", "invoke_type"]
    assert print_card.outcomes(%{}) == [{"done", "Done"}, {"error", "Error"}]
    assert print_card.io(%{}) == %{kinds: [:step], produces: "myapp.library_card"}
    assert print_card.slots(%{}) == []
    assert print_card.current_version() == 1
    assert print_card.validate_config(%{}) == :ok
  end

  # Every ```elixir block on a page, in reading order.
  @spec elixir_blocks_in(binary()) :: [binary()]
  defp elixir_blocks_in(page) do
    ~r/^```elixir\n(.*?)^```$/ms
    |> Regex.scan(page)
    |> Enum.map(fn [_whole, code] -> code end)
  end
end
