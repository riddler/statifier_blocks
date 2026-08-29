defmodule StatifierBlocks.ThemeAudit do
  @moduledoc """
  The pure half of theming, as arithmetic (ADR-0005 decision 14's amendment).

  Test-only support: this module lives in `test/support`, is compiled in
  `:test` alone, and ships in no release. It is deliberately not `lib/` API.
  Decision 14 says a host themes this package by setting `--sb-*` custom
  properties and nothing else; that is a claim about text, and text is
  checkable. Everything here takes a stylesheet as a **string** and returns
  values - nothing reads a file, nothing paints, nothing needs a browser.

  It is a port of the pure half of the campaign-012 spike's
  `spike/js/theme.js`, which `spike/dev/theme-audit.html` ran against the
  spike's three themes. The spike could only ever run it in Chrome by hand.
  Here it runs in the gate, which is the whole point of the port.

  Four jobs:

    * **coverage** - `declared_tokens/1` and `referenced_tokens/1`, the two
      directions 14e asks for.
    * **contrast** - `contrast_ratio/2` and the WCAG relative luminance under
      it, plus `resolve/2` for following a token whose value is a `var()` on
      another token.
    * **purity** - `structural_declarations/1`, which is 14's hard rule about
      a host theme file expressed as a list that has to come back empty.
    * **accent names** - `accent_token_gaps/2`, 14d's "a descriptor carries a
      NAME, never a colour" checked from the other end: a name nothing
      defines.

  ## What the CSS reader is, and is not

  `declaration_blocks/1` is a deliberately small reader. It finds
  `selector { property: value; ... }` and knows nothing else about CSS - no
  at-rules, no nesting, no shorthand expansion. That is enough for a token
  block and for a host theme file, both of which are flat lists of custom
  properties, and a real CSS parser here would be a dependency this package
  does not want for one test.

  Comments are stripped first, so a commented-out token is not a declared one
  and a token named in prose is not a declaration.
  """

  @typedoc "One `selector { ... }` block, declarations in source order."
  @type block :: %{selector: String.t(), declarations: [{String.t(), String.t()}]}

  @doc "The source with every `/* ... */` comment removed."
  @spec strip_comments(String.t()) :: String.t()
  def strip_comments(css), do: String.replace(css, ~r|/\*.*?\*/|s, "")

  @doc """
  Every rule block, as `%{selector: ..., declarations: [{property, value}]}`.

  Comments are stripped first. A block with no declarations is still returned,
  because "this selector declares nothing" is a fact a caller may want.
  """
  @spec declaration_blocks(String.t()) :: [block()]
  def declaration_blocks(css) do
    ~r/([^{}]+)\{([^{}]*)\}/
    |> Regex.scan(strip_comments(css))
    |> Enum.map(fn [_all, selector, body] ->
      %{
        selector: selector |> String.trim() |> String.replace(~r/\s+/, " "),
        declarations: declarations(body)
      }
    end)
  end

  @spec declarations(String.t()) :: [{String.t(), String.t()}]
  defp declarations(body) do
    ~r/([a-zA-Z-]+)\s*:\s*([^;]*);/
    |> Regex.scan(body)
    |> Enum.map(fn [_all, property, value] -> {property, String.trim(value)} end)
  end

  @doc "Every `--sb-*` name declared anywhere in the source."
  @spec declared_tokens(String.t()) :: MapSet.t(String.t())
  def declared_tokens(css) do
    ~r/(--sb-[a-z0-9-]+)\s*:/
    |> Regex.scan(strip_comments(css))
    |> MapSet.new(fn [_all, name] -> name end)
  end

  @doc "Every `--sb-*` name read by a `var()` anywhere in the source."
  @spec referenced_tokens(String.t()) :: MapSet.t(String.t())
  def referenced_tokens(css) do
    ~r/var\(\s*(--sb-[a-z0-9-]+)/
    |> Regex.scan(strip_comments(css))
    |> MapSet.new(fn [_all, name] -> name end)
  end

  @doc """
  Every `--sb-*` token and its value, later declarations winning.

  Source order is the resolution a browser would reach for one cascade level
  and one element, which is the case every token block here is: the package
  declares its defaults on `.sb-editor`, a host theme restates some of them
  further down. It is not a general cascade.
  """
  @spec token_values(String.t()) :: %{String.t() => String.t()}
  def token_values(css) do
    css
    |> declaration_blocks()
    |> Enum.flat_map(& &1.declarations)
    |> Enum.filter(fn {property, _value} -> String.starts_with?(property, "--sb-") end)
    |> Map.new()
  end

  @doc """
  The literal hex colour `name` resolves to, following `var()` chains, or
  `nil`.

  `nil` covers every case a contrast ratio would be a number about a guess:
  an undeclared name, a `calc()` or a keyword, and deliberately an `rgba()`
  tint, whose ratio depends on whatever it is painted over. A cycle also
  resolves to `nil` rather than looping.
  """
  @spec resolve(%{String.t() => String.t()}, String.t()) :: String.t() | nil
  def resolve(values, name), do: resolve(values, name, MapSet.new())

  @spec resolve(%{String.t() => String.t()}, String.t(), MapSet.t(String.t())) :: String.t() | nil
  defp resolve(values, name, seen) do
    with false <- MapSet.member?(seen, name),
         {:ok, value} <- Map.fetch(values, name) do
      follow(values, value, MapSet.put(seen, name))
    else
      _other -> nil
    end
  end

  @spec follow(%{String.t() => String.t()}, String.t(), MapSet.t(String.t())) :: String.t() | nil
  defp follow(values, value, seen) do
    case Regex.run(~r/^var\(\s*(--sb-[a-z0-9-]+)/, value) do
      [_all, referenced] -> resolve(values, referenced, seen)
      nil -> hex(value)
    end
  end

  @spec hex(String.t()) :: String.t() | nil
  defp hex(value) do
    if Regex.match?(~r/^#[0-9a-fA-F]{3,8}$/, value), do: value
  end

  @doc """
  Every `--sb-*` token whose **own** value is a colour literal.

  Its own, not what it resolves to: `--sb-focus-ring: var(--sb-accent)` is a
  token that follows the accent by design, and a theme that restates the
  accent has already moved the focus ring. The tokens listed here are the ones
  a theme has to say out loud, because nothing else in the surface will say
  them for it - which is the dark-theme failure mode in its purest form, one
  surface colour left at the light default.
  """
  @spec colour_tokens(String.t()) :: [String.t()]
  def colour_tokens(css) do
    css
    |> token_values()
    |> Enum.filter(fn {_name, value} ->
      Regex.match?(~r/^(#[0-9a-fA-F]{3,8}|rgba?\(|hsla?\()/, value)
    end)
    |> Enum.map(fn {name, _value} -> name end)
    |> Enum.sort()
  end

  @doc """
  Every declaration that is **not** a `--sb-*` custom property, with the
  selector it sits in.

  This is decision 14's rule about a host theme file, as a list that has to
  come back empty: a theme may set `--sb-*` properties and may do nothing
  else. A theme that needs a structural declaration has found a hole in the
  token surface, and the fix goes in the surface rather than in the theme.
  """
  @spec structural_declarations(String.t()) :: [%{selector: String.t(), property: String.t()}]
  def structural_declarations(css) do
    css
    |> declaration_blocks()
    |> Enum.flat_map(fn block ->
      block.declarations
      |> Enum.reject(fn {property, _value} -> String.starts_with?(property, "--sb-") end)
      |> Enum.map(fn {property, _value} -> %{selector: block.selector, property: property} end)
    end)
  end

  @doc """
  The accent token names `entries` declare that `defined` does not contain.

  14d's discipline from the other end. `StatifierBlocks.ViewModel.accent_token/1`
  refuses a value that is not an anchored `--sb-` name, which is what keeps a
  block type from naming a colour and what keeps a typo out of a style
  attribute. It cannot know whether the name it accepts means anything: a
  well-formed name nothing defines resolves through the renderer's fallback to
  the editor's own accent, so the block type silently loses its identity and
  looks exactly like a type that never declared one.

  `defined` is the union of the package's tokens and the host theme's, since
  a per-type accent is by construction a name the host declares.
  """
  @spec accent_token_gaps([map()], Enumerable.t()) :: [String.t()]
  def accent_token_gaps(entries, defined) do
    defined = MapSet.new(defined)

    entries
    |> Enum.map(&StatifierBlocks.ViewModel.accent_token/1)
    |> Enum.reject(&(&1 == nil or MapSet.member?(defined, &1)))
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc "sRGB channels, 0.0 to 1.0, from a `#rgb` or `#rrggbb` string."
  @spec channels(String.t()) :: [float()]
  def channels(colour) do
    hex = colour |> String.trim() |> String.trim_leading("#")

    full =
      case String.length(hex) do
        3 -> hex |> String.graphemes() |> Enum.map_join(&(&1 <> &1))
        _other -> hex
      end

    unless Regex.match?(~r/^[0-9a-fA-F]{6}$/, full) do
      raise ArgumentError, "not a hex colour: #{inspect(colour)}"
    end

    for at <- [0, 2, 4], do: String.to_integer(binary_part(full, at, 2), 16) / 255
  end

  @doc "WCAG relative luminance."
  @spec relative_luminance(String.t()) :: float()
  def relative_luminance(colour) do
    [r, g, b] =
      Enum.map(channels(colour), fn c ->
        if c <= 0.03928, do: c / 12.92, else: :math.pow((c + 0.055) / 1.055, 2.4)
      end)

    0.2126 * r + 0.7152 * g + 0.0722 * b
  end

  @doc """
  WCAG contrast ratio, 1.0 to 21.0, order-independent.

  Rounded to two places, because these numbers are read against a threshold
  and a 4.4999 that prints as `4.5` while failing costs an afternoon.
  """
  @spec contrast_ratio(String.t(), String.t()) :: float()
  def contrast_ratio(a, b) do
    [high, low] = [relative_luminance(a), relative_luminance(b)] |> Enum.sort(:desc)
    Float.round((high + 0.05) / (low + 0.05), 2)
  end

  @doc """
  The worst ratio `colour` reaches against any of `surfaces`, as
  `{ratio, surface_token, surface_colour}`.

  Every surface, not the nearest one: a foreground token is used across the
  editor's panes, and the theme's failure is whichever pane it reads worst on.
  """
  @spec worst_contrast(String.t(), %{String.t() => String.t()}, [String.t()]) ::
          {float(), String.t(), String.t()}
  def worst_contrast(colour, values, surfaces) do
    surfaces
    |> Enum.map(fn token -> {token, resolve(values, token)} end)
    |> Enum.reject(fn {_token, on} -> on == nil end)
    |> Enum.map(fn {token, on} -> {contrast_ratio(colour, on), token, on} end)
    |> Enum.min()
  end
end
