defmodule StatifierBlocks.ThemeAuditTest do
  @moduledoc """
  The theme audit, held against the stylesheet rather than against a comment.

  ADR-0005 decision 14's proposed amendment 14e asks for exactly this, and asks
  for it in **both directions**:

  > The package's own check fails on **either** direction: a `var(--sb-*)`
  > reference with no declaration, and a declared token no rule reads.

  The second half is the one worth having. A missing declaration produces a
  visible defect the first time someone looks at the editor; a declared token
  nothing reads produces no defect at all - a host sets it, nothing moves, and
  there is no way to tell that from a bug in their own stylesheet. The spike
  shipped two of those (`--sb-gap-height` and `--sb-gap-hover-bg`, declared in
  its first pass and consumed by nothing) and found them by measuring rather
  than by reading.

  14b's reset rule is checked here too, because it is "mechanical enough to be
  a lint" and that is the only form it survives in - the bug it prevents is
  silent by construction.

  What this file does NOT check, and what `sb-2b9` completes: contrast ratios
  between the declared foreground and surface tokens, and override purity for a
  theme file. The package ships one theme and no theme files, so neither has a
  subject here yet; the arithmetic lives in the spike's `dev/theme-audit.html`
  until it does.

  Deliberately **not** tagged `:liveview`: it reads a file off disk, so it runs
  in the headless tree too, where `assets/` is easiest to forget.
  """

  use ExUnit.Case, async: true

  @stylesheet "assets/css/statifier_blocks.css"

  setup_all do
    source = @stylesheet |> File.read!() |> strip_comments()

    %{
      source: source,
      declared: declared_tokens(source),
      referenced: referenced_tokens(source)
    }
  end

  # Every check here is about what the browser sees, and a comment is not that.
  # A token named in prose is not declared, a token named in prose is not read,
  # and a selector quoted in a comment explaining why it would be wrong must not
  # be reported as the wrong selector.
  defp strip_comments(source), do: String.replace(source, ~r|/\*.*?\*/|s, "")

  # `--sb-name:` at the head of a declaration. Custom properties may be
  # declared anywhere, so this deliberately does not care which rule it is in;
  # the rule that they all belong on the canvas root is asserted separately.
  defp declared_tokens(source) do
    ~r/(--sb-[a-z0-9-]+)\s*:/
    |> Regex.scan(source)
    |> MapSet.new(fn [_all, name] -> name end)
  end

  defp referenced_tokens(source) do
    ~r/var\(\s*(--sb-[a-z0-9-]+)/
    |> Regex.scan(source)
    |> MapSet.new(fn [_all, name] -> name end)
  end

  describe "token coverage runs in both directions (14e)" do
    # Sabotage: adding `color: var(--sb-fg-nonexistent)` to `.sb-node` - the
    # reference has no declaration and this goes red naming it.
    test "every token a rule reads is declared", context do
      undeclared = MapSet.difference(context.referenced, context.declared)

      assert MapSet.to_list(undeclared) == [], """
      ADR-0005 amendment 14e: a `var(--sb-*)` reference with no declaration is
      a token a host cannot set and a value that falls back to nothing.

      Referenced and never declared: #{inspect(MapSet.to_list(undeclared))}
      """
    end

    # Sabotage: declaring `--sb-ghost-bg: #fff` on `.sb-editor` without a rule
    # that reads it - a reserved name in a published surface is a promise, and
    # this goes red on it.
    test "every token declared is read by some rule", context do
      dead = MapSet.difference(context.declared, context.referenced)

      assert MapSet.to_list(dead) == [], """
      ADR-0005 amendment 14e: a declared token no rule reads is worse than a
      missing one - a host sets it, nothing moves, and there is no way to tell
      that from a bug. Either give it a consumer or retire the name; a name in
      a published surface is a commitment to keep meaning what it says.

      Declared and never read: #{inspect(MapSet.to_list(dead))}
      """
    end

    # Not a claim about the stylesheet: it is what stops the two checks above
    # from passing vacuously if the scan regexes ever stop matching anything.
    # Sabotage: narrowing `declared_tokens/1` to a name that does not exist -
    # both directions go quiet and this is what notices.
    test "the scan actually saw the surface", context do
      assert MapSet.member?(context.declared, "--sb-accent")
      assert MapSet.member?(context.referenced, "--sb-accent")
    end
  end

  describe "the scheme token (14a)" do
    # Sabotage: deleting the `color-scheme: var(--sb-color-scheme)` declaration
    # - every theme's `<select>` drop-downs, scrollbars and carets go back to
    # being unreachable by any token, which is the defect that reads as "the
    # dark theme is half-finished" and cannot be diagnosed from the stylesheet.
    test "the editor declares --sb-color-scheme and reads it as color-scheme",
         %{source: source, declared: declared} do
      assert MapSet.member?(declared, "--sb-color-scheme")
      assert source =~ ~r/color-scheme:\s*var\(--sb-color-scheme\)/
    end

    # Sabotage: moving the declaration onto `:root` - the editor then tells the
    # host page which scheme it is in, which is the editor reaching outside its
    # own box.
    test "it is scoped to the editor's container, never :root", %{source: source} do
      refute source =~ ~r/(^|\})\s*:root\b/,
             "14a: scoped to the editor's own container, never `:root`"
    end
  end

  describe "the scoped reset is zero-specificity on its container half (14b)" do
    # Sabotage: rewriting one reset selector as `.sb-editor p` - it out-weighs
    # every single-class component rule below it, which is how a reset starts
    # silently stripping the padding and margins it exists to make room for.
    test "no selector matches the container as a class and an element", %{source: source} do
      offenders =
        ~r/\.sb-editor\s+[a-zA-Z]/
        |> Regex.scan(source)
        |> Enum.map(fn [match] -> match end)
        |> Enum.uniq()

      assert offenders == [], """
      ADR-0005 amendment 14b: a scoped reset may match its container only
      through `:where(.sb-editor)`. `.sb-editor p` weighs one class plus one
      element, which beats any single-class component rule, so it forces every
      rule below it to defend itself with an element qualifier the next author
      will not know to copy.

      Found: #{inspect(offenders)}
      """
    end

    # The same corroborator for the check above: a stylesheet with no reset at
    # all satisfies the specificity rule perfectly.
    # Sabotage: deleting the reset block - the lint above stays green and this
    # goes red.
    test "the reset is actually present", %{source: source} do
      assert source =~ ":where(.sb-editor) button"
      assert source =~ ":where(.sb-editor) :focus-visible"
    end
  end

  describe "the token surface's shape (decision 14)" do
    # Sabotage: declaring a `--sb-*` token inside `.sb-node` - a host setting it
    # through the `theme` assign, which writes to the canvas root, then cannot
    # override it, because the nearer declaration wins.
    test "every token is declared on the editor root", %{source: source} do
      root_block = source |> String.split("\n.sb-editor {", parts: 2) |> List.last()
      {tokens, rest} = String.split(root_block, "\n}\n", parts: 2) |> List.to_tuple()

      stray =
        ~r/(--sb-[a-z0-9-]+)\s*:/
        |> Regex.scan(rest)
        |> Enum.map(fn [_all, name] -> name end)
        |> Enum.uniq()

      assert stray == [], """
      ADR-0005 decision 14: every custom property is declared on the canvas
      root, which is where the `theme` assign writes. A declaration further in
      is one a host cannot override.

      Declared elsewhere: #{inspect(stray)}
      """

      assert tokens =~ "--sb-accent", "the split found the root block"
    end

    # Sabotage: renaming one token to `--radius` - the namespace is what keeps
    # the package from colliding with a host's own properties, and the record
    # commits to it.
    test "no custom property outside the --sb-* namespace is declared", %{source: source} do
      stray =
        ~r/(--(?!sb-)[a-z0-9-]+)\s*:/
        |> Regex.scan(source)
        |> Enum.map(fn [_all, name] -> name end)
        |> Enum.uniq()

      assert stray == [],
             "decision 14: the property namespace is `--sb-*`. Found: #{inspect(stray)}"
    end
  end
end
