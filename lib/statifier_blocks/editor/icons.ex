if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.Icons do
    @moduledoc """
    The shipped default icon set, and the seam a host overrides it through
    (ADR-0005 decision 10's `icon` key, decision 14's "markup, not styling"
    line).

    ## Why a default set exists at all

    ADR-0005 decision 10 says `icon` is a **name, never markup**, and that a
    host that ships nothing "gets a neutral glyph". Read literally that was
    true: the editor rendered a `U+25A1` white square in every tile. Read as a
    design it was not, because the one thing a white square communicates is
    that something failed to load - the first impression the shipped editor
    made on a host that had not yet written an icon component was of a broken
    page rather than an unstyled one, and the palette got no tile at all.

    So this module ships the glyphs for the names `StatifierBlocks.Palette.core/0`
    emits, and `glyph/1` uses them when the host passes no `icon`. Nothing about
    the decision moves: `icon` is still a name, the editor still resolves the
    name through a component, and a host that passes its own `icon` still wins
    on every tile. The default is markup this package authored for names this
    package emits, which is the case the injection argument was never about.

    ## What it is not

    **No font, no CDN, no build step.** Every glyph is an inline SVG in this
    module's compiled template. Nothing is fetched, nothing is registered in a
    host's asset pipeline, and a host that imports the stylesheet and nothing
    else has icons.

    **No colour, and no size of its own.** Every path paints with
    `currentColor` and the `<svg>` fills its tile, so the tile's own rule -
    `.sb-node__icon` and `.sb-palette__icon`, which read `--sb-block-accent`
    and `--sb-block-accent-tint` - decides both. A theme restyles the icons by
    restyling nothing but tokens, which is decision 14d's rule and the reason
    this is markup rather than styling.

    **Not a general icon library, and not anybody's icon set.** The paths are
    written here, for these eleven names, at a single 24-unit grid and a
    single stroke weight. A host that wants a real icon library passes one.

    ## The three cases `glyph/1` has

      * the entry names an icon this module has - the shipped glyph;
      * the entry names one it does not - the **unnamed mark**, three dots, a
        tile that reads as deliberate rather than as a failed load. A host
        block type declaring `icon: "credit-card"` gets a neutral chip and the
        name in `data-icon`, not a white square;
      * the entry names none at all (`icon: nil`, ViewModel's default) - **no
        tile**. A block type that declared no icon is not missing one, and the
        chrome closes up around the label. This is the deliberate empty state
        the bead asked for, and it applies to a host-supplied `icon` component
        too: a host is never called with a `nil` name.

    ## What a host's component may do

    A host's `icon` is rendered as a **function component**, exactly as if the
    editor had written `<.icon name={...} class={...} />` against it, so its
    assigns are a tracked assigns map and every `Phoenix.Component` helper
    works inside it: `assign/3`, `assign_new/3`, whatever a host reaches for
    to derive one value before the markup. It must return a `~H` template,
    which is the one thing the seam has always required.
    """

    use Phoenix.Component

    # Every path in one place so `known_names/0` and the rendering cannot
    # disagree, and so a test can hold the set against `Palette.core/0`.
    #
    # The grid is 24 units, the weight is 1.75, the caps and joins are round,
    # and the fill is none everywhere: they are one family or they are a
    # ransom note.
    @glyphs %{
      "arrow-path" => [
        "M20 12a8 8 0 1 1-2.4-5.7",
        "M18.5 2.5v4.5H14"
      ],
      "arrow-up-right" => [
        "M7 17 17 7",
        "M9 7h8v8"
      ],
      "arrows-right-left" => [
        "M4 9h13",
        "m14 6 3 3-3 3",
        "M20 15H7",
        "m10 12-3 3 3 3"
      ],
      "bars-3" => [
        "M4 7h16",
        "M4 12h16",
        "M4 17h16"
      ],
      "bolt" => [
        "M13.5 2.5 5 13.5h6l-1.5 8L18 10.5h-6z"
      ],
      "clock" => [
        "M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18z",
        "M12 7v5.2l3.4 2"
      ],
      "inbox" => [
        "M3.5 13.5h5l1 2h5l1-2h5",
        "M3.5 13.5 6 5h12l2.5 8.5V19h-17z"
      ],
      "megaphone" => [
        "M4 9.5v5a2 2 0 0 0 2 2h2.5L18 21V3L8.5 7.5H6a2 2 0 0 0-2 2z",
        "M8 16.5V20a1.5 1.5 0 0 0 3 0v-2.3"
      ],
      "paper-airplane" => [
        "M21 3 3 10.5l7.5 3L14 21z",
        "M10.5 13.5 21 3"
      ],
      "rectangle-group" => [
        "M3 5.5h18v13H3z",
        "M6 9h6v3H6z",
        "M15 9h3v6h-3z"
      ],
      "view-columns" => [
        "M3 5.5h18v13H3z",
        "M9 5.5v13",
        "M15 5.5v13"
      ]
    }

    # Three dots: a mark, not a container. A box is what "missing" looks like,
    # which is the whole reason the fallback glyph had to go.
    @unnamed ["M8.75 12h.5", "M11.75 12h.5", "M14.75 12h.5"]

    @doc """
    The icon names this module ships, sorted.

    Public so the property that matters - every name the core palette emits
    has a glyph here - is asserted against the module rather than against a
    list copied into a test.
    """
    @spec known_names() :: [String.t()]
    def known_names, do: @glyphs |> Map.keys() |> Enum.sort()

    attr(:icon, :any,
      default: nil,
      doc: "The host's icon component, or nil for the shipped default set."
    )

    attr(:name, :any, default: nil, doc: "The icon name the palette entry declared, or nil.")
    attr(:class, :string, required: true, doc: "The tile class the caller owns.")

    @doc """
    One tile: the host's component if it passed one, the shipped glyph
    otherwise, and nothing at all when the entry named no icon.
    """
    def glyph(assigns)

    def glyph(%{name: nil} = assigns) do
      ~H"""
      """
    end

    def glyph(%{icon: nil} = assigns) do
      ~H"""
      <.icon name={@name} class={@class} />
      """
    end

    # The host's component is rendered the way HEEx renders `<.icon ... />`,
    # not by applying the function to a bare map. `~H` cannot name a runtime
    # function in a tag, so the call goes through the same entry point the
    # engine compiles that tag into - it is what puts `__changed__` in the
    # assigns and what checks the return is a `%Rendered{}`.
    #
    # Calling `@icon.(%{name: ..., class: ...})` instead handed the host a map
    # with no `__changed__` key, so any host component that derived a value
    # the ordinary way - `assign/3`, `assign_new/3`, anything expecting a
    # tracked assigns map - raised on a seam that renders straight from its
    # arguments in every example we ship (sb-b8g).
    def glyph(assigns) do
      ~H"""
      {Phoenix.LiveView.TagEngine.component(
        @icon,
        %{name: @name, class: @class},
        {__MODULE__, {:glyph, 1}, __ENV__.file, __ENV__.line}
      )}
      """
    end

    attr(:name, :string, required: true)
    attr(:class, :string, default: nil)

    @doc """
    The shipped default icon component, in the shape the `icon` assign takes.

    A host may pass this directly, or wrap it to fall back to it for the names
    it has not drawn itself.
    """
    def icon(assigns) do
      assigns = assign(assigns, :paths, Map.get(@glyphs, assigns.name, @unnamed))

      ~H"""
      <span class={@class} data-icon={@name} aria-hidden="true">
        <svg
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="1.75"
          stroke-linecap="round"
          stroke-linejoin="round"
          focusable="false"
        >
          <path :for={d <- @paths} d={d} />
        </svg>
      </span>
      """
    end
  end
end
