defmodule StatifierBlocks.PalettePreflightTest do
  # `Palette.preflight/1` and `/2`: the binding check (ADR-0002 decision 7,
  # amended 2026-09-28) asked of a palette's host types and of a host's
  # stored documents before the minor that makes declared field types
  # binding. Pure: no editor, no LiveView.
  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Document, Palette}

  doctest StatifierBlocks.Palette, only: [preflight: 1]

  defmodule RenewalNotice do
    @moduledoc false
    # A library-loan host type whose defaults agree with its declarations.
    use StatifierBlocks.BlockType

    @impl true
    def config_schema(_config) do
      [
        %{key: "subject", type: :string, label: "Subject", required?: true, default: "Due soon"},
        %{key: "days_before", type: :integer, label: "Days before", required?: true, default: 3}
      ]
    end

    @impl true
    def emit(%Block{id: id}, _context), do: {:error, {:not_implemented, id}}
  end

  defmodule OverdueNotice do
    @moduledoc false
    # A library-loan host type declaring an integer field whose default is a
    # string: the disagreement the pre-flight exists to list.
    use StatifierBlocks.BlockType

    @impl true
    def config_schema(_config) do
      [
        %{key: "subject", type: :string, label: "Subject", required?: true, default: "Overdue"},
        %{key: "days_late", type: :integer, label: "Days late", required?: true, default: "3"}
      ]
    end

    @impl true
    def emit(%Block{id: id}, _context), do: {:error, {:not_implemented, id}}
  end

  defmodule DeskNotice do
    @moduledoc false
    # A library-loan host type whose default lives at a nested value path.
    use StatifierBlocks.BlockType

    @impl true
    def config_schema(_config) do
      [
        %{
          key: "branch",
          type: :string,
          label: "Branch",
          required?: false,
          default: 12,
          value_path: ["desk", "branch"]
        }
      ]
    end

    @impl true
    def emit(%Block{id: id}, _context), do: {:error, {:not_implemented, id}}
  end

  defmodule BrokenSchema do
    @moduledoc false
    # A patron-registration host type whose config_schema/1 raises.
    use StatifierBlocks.BlockType

    @impl true
    def config_schema(_config), do: raise(ArgumentError, "patron form not loaded")

    @impl true
    def emit(%Block{id: id}, _context), do: {:error, {:not_implemented, id}}
  end

  defmodule BrokenVersion do
    @moduledoc false
    # A parcel-delivery host type whose schema reads, but whose
    # current_version/0 raises, so new_block/2 raises.
    use StatifierBlocks.BlockType

    @impl true
    def config_schema(_config),
      do: [%{key: "carrier", type: :string, label: "Carrier", required?: true, default: ""}]

    @impl true
    def current_version, do: raise("parcel version table missing")

    @impl true
    def emit(%Block{id: id}, _context), do: {:error, {:not_implemented, id}}
  end

  defp palette(extra \\ %{}) do
    Palette.new(
      Map.merge(
        Palette.core_types(),
        Map.merge(
          %{"library.renewal_notice" => RenewalNotice, "library.overdue_notice" => OverdueNotice},
          extra
        )
      )
    )
  end

  defp document(children) do
    Document.new(
      Block.new("core.sequence", id: "blk_root", slots: %{"steps" => children}),
      id: "doc_loans"
    )
  end

  describe "preflight/1" do
    # Sabotage: drop `Enum.uniq/1` from `host_type/3` -> the defaults step
    # and the new_block step list the one value twice and this goes red.
    test "one agreeing and one disagreeing host type answer exactly one finding" do
      assert [finding] = Palette.preflight(palette())

      assert finding == %{
               type: "library.overdue_notice",
               block_id: nil,
               key: "days_late",
               declared_type: :integer,
               value: "3",
               message: "the days_late field is declared an integer, and holds a string"
             }
    end

    # Sabotage: reject by name alone (`Map.has_key?(core, name)`) in
    # `Preflight.palette/1` -> the host module under `core.wait` is skipped
    # and this goes red.
    test "Palette.core() answers none, and a host module under a core name is judged" do
      assert Palette.preflight(Palette.core()) == []

      swapped = Palette.new(Map.put(Palette.core_types(), "core.wait", OverdueNotice))
      assert [%{type: "core.wait", key: "days_late"}] = Palette.preflight(swapped)
    end

    # Sabotage: place each default at `[key]` rather than at its value path
    # in `default_violations/1` -> the default under `desk.branch` is never
    # read (nor is the flat new_block config) and this goes red.
    test "a default at a nested value path is judged where the value lives" do
      assert [%{type: "library.desk_notice", key: "branch", declared_type: :string, value: 12}] =
               Palette.preflight(palette(%{"library.desk_notice" => DeskNotice}))
               |> Enum.filter(&(&1.type == "library.desk_notice"))
    end

    # Sabotage: `attempt/2`'s rescue answering `{:ok, []}` -> the raise is
    # swallowed with no finding and this goes red.
    test "a type whose config_schema/1 raises is one finding, not a raise" do
      findings = Palette.preflight(palette(%{"patron.registration" => BrokenSchema}))

      assert [%{type: "patron.registration", block_id: nil, raised: :config_schema} = raised] =
               Enum.filter(findings, &(&1.type == "patron.registration"))

      assert raised.message =~ "patron form not loaded"
      assert Enum.any?(findings, &(&1.type == "library.overdue_notice"))
    end

    # Sabotage: skip the new_block step in `host_type/3` -> the type answers
    # no finding and this goes red.
    test "a type whose new_block/2 raises is a finding, not a raise" do
      findings = Palette.preflight(palette(%{"parcel.delivery" => BrokenVersion}))

      assert [%{type: "parcel.delivery", raised: :new_block, message: message}] =
               Enum.filter(findings, &(&1.type == "parcel.delivery"))

      assert message =~ "parcel version table missing"
    end
  end

  describe "preflight/2" do
    # Sabotage: `Preflight.documents/2` answering `[]` -> the block's
    # finding is missing and this goes red.
    test "a document block of an agreeing type with a wrong-typed value is a finding" do
      loan =
        Block.new("library.renewal_notice",
          id: "blk_renewal",
          config: %{"subject" => "Due soon", "days_before" => "three"}
        )

      assert [palette_finding, block_finding] =
               Palette.preflight(palette(), [document([loan])])

      assert palette_finding.type == "library.overdue_notice"

      assert block_finding == %{
               type: "library.renewal_notice",
               block_id: "blk_renewal",
               key: "days_before",
               declared_type: :integer,
               value: "three",
               message: "the days_before field is declared an integer, and holds a string"
             }
    end

    # Sabotage: the unknown arm of `Preflight.block/2` answering a finding
    # naming the type -> the stranger is listed and this goes red.
    test "a block whose type the palette does not carry is not judged" do
      stranger =
        Block.new("parcel.unregistered", id: "blk_stranger", config: %{"days_before" => "x"})

      assert Palette.preflight(palette(), [document([stranger])]) ==
               Palette.preflight(palette())
    end

    # Sabotage: `attempt/2`'s rescue answering `{:ok, []}` -> the block's
    # raise is swallowed with no finding and this goes red.
    test "a document block whose type raises is a finding, not a raise" do
      patron = Block.new("patron.registration", id: "blk_patron")
      palette = palette(%{"patron.registration" => BrokenSchema})

      assert [%{type: "patron.registration", block_id: "blk_patron", raised: :config_schema}] =
               palette
               |> Palette.preflight([document([patron])])
               |> Enum.filter(&(&1.block_id == "blk_patron"))
    end
  end
end
