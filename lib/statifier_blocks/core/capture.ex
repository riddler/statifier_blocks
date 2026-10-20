defmodule StatifierBlocks.Core.Capture do
  @moduledoc false

  # The optional `capture` map, shared by the two core types that hold
  # for an event: `core.on_event` and `core.await`. One spelling of the
  # key, one validation, one emission, so the two cannot drift apart.
  #
  # What the map means - the key is the destination, the value is the
  # source, a string source is a path inside `_event.data` and a
  # `["const", value]` source is a literal - is recorded in
  # `StatifierBlocks.Core.OnEvent`'s moduledoc and in ADR-0002's Notes of
  # 2026-09-05, 2026-09-12 and 2026-09-13. Both types read it from there;
  # nothing here is specific to either. Each type puts the assigns
  # `assigns/1` answers on the transition its own event selects,
  # which is the only place `_event.data` is in scope.
  #
  # The `payload` declaration and its refusal stay `core.on_event`'s: they
  # read the pairs through `path?/1` here, and nothing about a capture's
  # emission depends on them.

  alias StatifierBlocks.Core.Config
  alias StatifierBlocks.Emission

  # The one spelling of the config key the pairs are stored under.
  @capture_key "capture"

  # The tag of a literal capture source (ADR-0002's Note of 2026-09-12,
  # N1). In the stored document the form is the two-element JSON array
  # `["const", value]`; `{"const", value}` is that array as this package
  # reads it, and ADR-0001 owns the bytes.
  @const_tag "const"

  # A path's shape, in both directions of a `capture` pair: non-empty and
  # carrying no whitespace, and deliberately NOT a dotted-identifier
  # grammar. `core.assign` reads the destination side with exactly this
  # rule and for exactly its reason - this package does not own the
  # datamodel path grammar, and a regex here that accepted `review.parked`
  # and refused something a host's datamodel legitimately declares would
  # be a second, quieter proposal riding along with this one. The source
  # side is a path inside `_event.data`, which this package owns no more
  # of than it owns the other.
  #
  # Any whitespace, not just the space/tab/newline trio: a carriage
  # return or a vertical tab is whitespace too.
  @whitespace ~r/\s/

  # The map is optional, and an empty one is the same as none - it is what
  # a document that once carried pairs and no longer does looks like.
  # A single finding is reported for the whole key rather than one per bad
  # pair, because `capture` has no field in `config_schema/1` to render a
  # per-pair finding against (see `StatifierBlocks.Core.OnEvent`'s
  # moduledoc), so the anchor an editor
  # could use is the key itself.
  @spec check([{String.t(), String.t()}], map()) :: [{String.t(), String.t()}]
  def check(findings, config) do
    case Map.get(config, @capture_key) do
      nil ->
        findings

      capture when is_map(capture) ->
        if Enum.all?(capture, &pair?/1) do
          control_finding(findings, capture)
        else
          [{@capture_key, capture_message()} | findings]
        end

      _other ->
        [{@capture_key, capture_message()} | findings]
    end
  end

  defp pair?({destination, source}), do: path?(destination) and source?(source)
  defp pair?(_other), do: false

  # The one restriction on a literal that is not a question of type
  # (ADR-0002's line of 2026-09-13, taken on this request). `literal/1`
  # writes a string's characters into an `<assign expr=...>` attribute
  # value, and `escape/1` rewrites exactly three control characters - tab,
  # line feed and carriage return - as the escapes predicator's lexer
  # decodes. Every other C0 control reaches the attribute RAW, and XML 1.0
  # admits no character below `U+0020` in an attribute value other than
  # those three (XML 1.0 5th ed., the `Char` production). Saxy reads one
  # back today, but a parser's tolerance is not the wire format's contract,
  # so the document is refused at compile instead.
  #
  # The finding lands on the `capture` key for the reason `check/2`
  # gives: the key is the only anchor an editor has. The message names the
  # offending codepoint so an author can find it in a string whose damage
  # is invisible on screen.
  #
  # The walk is `literal/1`'s own: into a list, and into a map's KEYS as
  # well as its members, because `literal/1` spells a key with the same
  # function it spells a string value with. Pairs and object keys are
  # sorted first so a document with more than one offender reports the same
  # codepoint on every compile.
  #
  # A control character in the PATH form is not this clause's business: a
  # path is refused for containing whitespace already, and what an
  # otherwise-shaped path spells is `path?/1`'s question.
  defp control_finding(findings, capture) do
    case control_codepoint(capture) do
      nil -> findings
      codepoint -> [{@capture_key, control_message(codepoint)} | findings]
    end
  end

  @spec control_codepoint(map()) :: non_neg_integer() | nil
  defp control_codepoint(capture) do
    capture
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.find_value(fn
      {_destination, [@const_tag, value]} -> control_in(value)
      {_destination, _source} -> nil
    end)
  end

  # `String.to_charlist/1` raises `UnicodeConversionError` on a binary that
  # is not valid UTF-8, so the clause asks `String.valid?/1` first and
  # answers `nil` - no control character found - for one that is not. A
  # parsed document never reaches that case: `Decode.decode/1` runs
  # `Validation.validate/1` over every document this package parses, and
  # its `canonical_json_check/2` refuses a non-UTF-8 binary in `config`
  # before any compile walks it. `validate_config/1` is public, though,
  # and a host calling it directly with `["const", <<0xFF>>]` asks a
  # question about SHAPE; it gets the shape answer rather than a raise,
  # and the encoding refusal stays the one `canonical_json_check/2`
  # gives.
  #
  # A literal that is BOTH invalid UTF-8 and carries a C0 control byte,
  # `<<1, 0xFF>>`, therefore draws no control-character finding either.
  # That is the same deliberate shape answer and not an oversight: this
  # walk reads CHARACTERS, a binary that is not valid UTF-8 has none to
  # read, and the byte that would offend is visible only to something
  # reading raw bytes instead. The layering is what makes it harmless -
  # such a binary is outside `ADR-0001`'s decision 6 value grammar
  # altogether, so the only way it arrives is a direct call - this
  # callback, or a host-built config on any in-memory path that reaches
  # it: a hand-built `t:StatifierBlocks.Document.t/0` handed to
  # `StatifierBlocks.Compiler.compile/3`, the editor's
  # `{:update_config, id, config}` gate in
  # `StatifierBlocks.Edit.check_config/3`, or the per-block config check
  # behind `StatifierBlocks.ViewModel.build/3`. Of those three paths only
  # the compile reaches `canonical_json_check/2`: its Document stage runs
  # `StatifierBlocks.Document.validate/1` before any config is walked, so
  # there the encoding refusal comes at the door rather than as a second
  # copy of it phrased as a control-character finding here. The editor's
  # gate and the view model's check call nothing in
  # `StatifierBlocks.Validation` - they ask this callback and the shared
  # `{:type_expr, opts}` check only - so a non-UTF-8 config passes both
  # with no finding, and the encoding refusal it gets instead is the one
  # the next compile or decode of that document gives.
  defp control_in(value) when is_binary(value) do
    if String.valid?(value), do: value |> String.to_charlist() |> Enum.find(&control?/1)
  end

  defp control_in(value) when is_list(value), do: Enum.find_value(value, &control_in/1)

  defp control_in(value) when is_map(value) and not is_struct(value) do
    value
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.find_value(fn {key, member} -> control_in(key) || control_in(member) end)
  end

  defp control_in(_other), do: nil

  defp control?(codepoint), do: codepoint < 0x20 and codepoint not in [?\t, ?\n, ?\r]

  defp control_message(codepoint) do
    ~s(must not carry the control character ) <>
      hex(codepoint) <>
      ~s( inside a ["const", value] literal: a literal is written into an ) <>
      "XML attribute value raw, and XML 1.0 admits no character below " <>
      "U+0020 there other than tab (U+0009), line feed (U+000A) and " <>
      "carriage return (U+000D)"
  end

  defp hex(codepoint) do
    "U+" <> (codepoint |> Integer.to_string(16) |> String.pad_leading(4, "0"))
  end

  # ADR-0002's Note of 2026-09-12, N1: the value position of a pair takes
  # either form, and the two are told apart by SHAPE and never by content.
  # A string is a path - no string is reinterpreted as a literal because of
  # what it happens to spell - and a two-element list tagged `"const"` is a
  # literal. Everything else is malformed, including a list of any other
  # length and a tagged pair whose value this package cannot spell as a
  # literal expression (`spellable?/1`).
  defp source?(source) when is_binary(source), do: path?(source)
  defp source?([@const_tag, value]), do: spellable?(value)
  defp source?(_other), do: false

  @spec path?(term()) :: boolean()
  def path?(value) do
    Config.non_empty_string?(value) and not Regex.match?(@whitespace, value)
  end

  defp capture_message do
    "must map each datamodel path written, like order.cancel_reason, " <>
      "to its source: either the path inside _event.data it is read from, " <>
      ~s(like reason, or the literal ["const", value], whose value is any ) <>
      "JSON a block document may carry: a string, an integer, true, " <>
      "false, null, an array or an object"
  end

  # The `<assign>` elements a `capture` map compiles to, in their
  # datamodel paths' sorted order, or `[]` for a handler that captures
  # nothing.
  #
  # A malformed map answers with a finding rather than dropping the pair.
  # The Config stage makes that arm unreachable in practice, never
  # impossible, and a capture silently not emitted is the failure this key
  # exists to prevent: everything downstream reads an unwritten path as an
  # authored absence.
  @spec assigns(term()) :: {:ok, [Emission.t()]} | {:error, [{String.t(), String.t()}]}
  def assigns(nil), do: {:ok, []}

  def assigns(capture) when is_map(capture) do
    if Enum.all?(capture, &pair?/1) do
      assigns =
        capture
        |> Enum.sort_by(fn {destination, _source} -> destination end)
        |> Enum.map(fn {destination, source} ->
          guarded(
            source,
            Emission.element(
              "assign",
              [{"expr", source_expr(source)}, {"location", destination}]
            )
          )
        end)

      {:ok, assigns}
    else
      {:error, [{@capture_key, capture_message()}]}
    end
  end

  def assigns(_other), do: {:error, [{@capture_key, capture_message()}]}

  # ADR-0002's Note of 2026-09-12, `N2`: from `0.28.0` on, a pair whose
  # source is a PATH and whose path the firing event's payload does not
  # carry writes nothing at its destination, so that "not answered" and
  # "answered with nothing" stop being the same value. The Note decides the
  # behaviour and leaves the mechanism here; this is the mechanism, and the
  # four facts it rests on are cited below against the resolved dependency
  # versions (`statifier` 2.5.0, `predicator` 9.4.1), which are what an
  # emitted chart is read by.
  #
  # The assign is wrapped in an `<if>` whose `cond` tests the very path the
  # assign reads, spelled once by `source_expr/1` so the guard and the read
  # cannot drift apart:
  #
  #     <if cond="_event.data.reason !== undefined">
  #       <assign expr="_event.data.reason" location="order.cancel_reason"/>
  #     </if>
  #
  #   1. `<if>` is executable content the engine supports inside a
  #      `<transition>`, end to end: it is in the lowering table
  #      (`statifier/lowering.ex:75`, `"if" => &Builders.build_if/2`), it is
  #      placed into a transition like any other content node
  #      (`lowering/builders.ex`, `place({:content_node, node}, %Transition{}
  #      = parent, _)`), and it executes by selecting the first matching
  #      branch (`machine/content/if.ex:107`, `def execute(%If{branches:
  #      branches}, ...)`). With no branch selected it runs nothing and
  #      answers the context unchanged (`if.ex:112`, `nil -> {:ok, context,
  #      []}`), which is precisely "leaves its destination unwritten".
  #   2. A bare `<assign>` cannot express this: it always writes. `_event`
  #      is a bound root whatever the payload carries, and an access that
  #      does not resolve answers the unbound marker rather than failing
  #      (`predicator/evaluator.ex:1230`, `Map.get(object, key,
  #      Undefined.value())`), so the assign succeeds and stores
  #      `:undefined`. That is the behaviour `N2` retires, and it is the
  #      engine's, not this package's.
  #   3. `!==` is the operator, not `!=`. Every non-strict comparison
  #      propagates the marker rather than answering a boolean
  #      (`predicator/evaluator.ex:787`, `:791`, guarded `when operator not
  #      in ["STRICT_EQ", "STRICT_NE"]`); the strict pair compares the terms
  #      themselves (`:795`, `compare_values(left, right, "STRICT_EQ"), do:
  #      left === right`). A `cond` that answers a non-boolean is treated as
  #      false (`machine/content/if.ex:152`, `{:non_boolean_cond, other}`,
  #      accumulated into the context's `pending_errors` rather than
  #      selecting the branch) AND raises a spurious `error.execution` -
  #      three hops on: `interpreter/content.ex:241` (`drain_pending/2`
  #      over a non-empty `pending_errors`), `:295`
  #      (`raise_execution_error/4`), and `machine_state.ex:811`, where
  #      `raise_platform/4` `enqueue_internal`s the event. So `!=` would
  #      skip the assign and dirty the run at the same time. This
  #      is the same reading `core.subchart` took for its routing
  #      conditions, where `==` against an absent `_event.data.outcome` cost
  #      a spurious `error.execution` (pinned upstream in statifier-ex).
  #   4. A nested source needs no chain of guards: an access whose target is
  #      neither map nor list answers the marker too
  #      (`predicator/evaluator.ex:1244`, `defp access_value(object, _key,
  #      _operation) when not is_map(object) and not is_list(object)`), so
  #      one `!== undefined` over the whole path covers an absent
  #      intermediate as well as an absent leaf.
  #
  # A LITERAL pair is never guarded (`N2`: "a literal pair has no source to
  # be absent, and always writes"), which is also what keeps a document
  # whose every pair is a literal compiling to the bytes `N1` gave it.
  #
  # `null` is not absence. A payload that carries the source with a JSON
  # `null` writes `null`, because the marker and `null` are distinct terms
  # under `===` - which is the whole of what `N2` decides: "not answered"
  # and "answered with nothing" are different values.
  @spec guarded(String.t() | [term()], Emission.t()) :: Emission.t()
  defp guarded(source, assign) when is_binary(source) do
    Emission.element("if", [{"cond", source_expr(source) <> " !== undefined"}], [assign])
  end

  defp guarded([@const_tag, _value], assign), do: assign

  # The `expr` of one pair's `<assign>`, told apart by the source's SHAPE
  # (`source?/1`): a string is a path inside the firing event's payload and
  # compiles exactly as it always has, and a `["const", value]` pair
  # compiles to `value` spelled as a literal expression. Only pairs
  # `pair?/1` has already admitted reach here.
  @spec source_expr(String.t() | [term()]) :: String.t()
  defp source_expr(source) when is_binary(source), do: "_event.data." <> source
  defp source_expr([@const_tag, value]), do: literal(value)

  # A document value spelled as a predicator literal expression - the
  # decision ADR-0002's Note of 2026-09-12 delegates to this request, taken
  # against `predicator` 9.4.1 (the version measured; `mix.exs` requires
  # `>= 9.4.1` and `~> 9.4`) and against `Statifier.Compiler.Expressions.compile/3`, which
  # is what an `<assign expr=...>` is read by.
  #
  # The spelling is predicator's own literal grammar rather than the
  # value's JSON encoding, because the two differ in exactly one place
  # that matters: JSON escapes a character it cannot write literally as
  # `\uXXXX`, and predicator's lexer has no such escape - it decodes an
  # unrecognised `\X` to the bare `X` (`take_string/6`), so a JSON-encoded
  # string would arrive at the datamodel with the escape's own letters in
  # it. The grammar this emits, per type:
  #
  #   * a string  - double-quoted, with `\` escaped and then `"` escaped,
  #     which is the order predicator's own writer uses; the three control
  #     characters its lexer decodes (`\n`, `\t`, `\r`) are written as
  #     those escapes rather than raw, because a raw newline or tab in an
  #     XML attribute value is normalised to a space before any lexer sees
  #     it;
  #   * an integer - its digits, a negative one with the `-` that
  #     predicator reads as a unary minus over the positive literal and
  #     evaluates to the negative integer;
  #   * `true` / `false` - themselves;
  #   * `null` - JSON's null and predicator's, which both evaluate to
  #     Elixir's `nil`;
  #   * an array - `[` the elements by this same rule, comma-separated `]`;
  #   * an object - `{` its pairs as `"key": value`, comma-separated, in
  #     the keys' sorted order `}`. Sorted for the reason the pairs
  #     themselves are sorted: a map has no order of its own and a compile
  #     has to be deterministic.
  #
  # There is no float clause, and there needs to be none: a float is not a
  # value a block document may carry at all
  # (`StatifierBlocks.Validation`'s `{:float, path}` problem).
  #
  # The facts this rests on - the escape set the lexer decodes, and that a
  # string literal is written back whole rather than a byte at a time - are
  # that lexer's behaviour rather than a documented grammar, so `mix.exs`
  # requires no lower than the version they were measured at: `>= 9.4.1`.
  #
  # The round trips in `test/statifier_blocks/core/on_event_test.exs` hold
  # BOTH of them honest, and the same way: they assert the value read back
  # rather than the bytes emitted, against the real engine, so they answer
  # for whichever 9.x is actually resolved. An escape that stops decoding
  # takes the escape cases red; a lexer that goes back to writing a
  # string's codepoints one byte at a time takes the non-ASCII case red.
  # That second direction is the one nothing in this suite could cover
  # while the refusal stood, because a literal the refusal turned away
  # never reached this function to be round-tripped at all.
  @spec literal(term()) :: String.t()
  defp literal(value) when is_binary(value), do: ~s(") <> escape(value) <> ~s(")
  defp literal(value) when is_integer(value), do: Integer.to_string(value)
  defp literal(true), do: "true"
  defp literal(false), do: "false"
  defp literal(nil), do: "null"

  defp literal(value) when is_list(value),
    do: "[" <> Enum.map_join(value, ",", &literal/1) <> "]"

  defp literal(value) when is_map(value) and not is_struct(value) do
    inner =
      value
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map_join(",", fn {key, member} -> literal(key) <> ":" <> literal(member) end)

    "{" <> inner <> "}"
  end

  @spec escape(String.t()) :: String.t()
  defp escape(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace(~s("), ~s(\\"))
    |> String.replace("\n", "\\n")
    |> String.replace("\t", "\\t")
    |> String.replace("\r", "\\r")
  end

  # Whether `literal/1` can spell this value so that the engine reads back
  # what the document carried. Total, and the gate `source?/1` puts in
  # front of `literal/1`, so a value that cannot be spelled is a malformed
  # pair rather than bytes that only look like the author's value.
  #
  # This is a question of TYPE and nothing else. Until 2026-09-13 a string
  # carried one restriction beyond type - it had to stay inside printable
  # ASCII, tab, newline and carriage return - because predicator 9.4.0's
  # lexer read a string literal codepoint by codepoint and wrote each one
  # back as a single BYTE, so any character above ASCII arrived at the
  # datamodel mangled. That restriction was never a rule this package's
  # records state - `N1` of ADR-0002's Note of 2026-09-12 admits every JSON
  # type and left the spelling to the code - so it was declared interim
  # here and in `mix.exs`, and it ended with ADR-0002's Note of 2026-09-13:
  # predicator 9.4.1 reads a string literal back whole, `mix.exs` requires
  # `>= 9.4.1` for that reason and no other, and `escape/1` plus the round
  # trip in `test/statifier_blocks/core/on_event_test.exs` are now the whole
  # of what a string has to satisfy.
  #
  # So a string is admitted whatever it carries, and what is left here is
  # the types a block document may not carry into a predicator literal at
  # all: a float (`StatifierBlocks.Validation` refuses one before this key
  # is read), an atom other than `true` / `false` / `nil`, a tuple, a
  # struct, and a map with a key that is not a string.
  @spec spellable?(term()) :: boolean()
  defp spellable?(value) when is_binary(value), do: true
  defp spellable?(value) when is_integer(value), do: true
  defp spellable?(value) when is_boolean(value), do: true
  defp spellable?(nil), do: true
  defp spellable?(value) when is_list(value), do: Enum.all?(value, &spellable?/1)

  defp spellable?(value) when is_map(value) and not is_struct(value) do
    Enum.all?(value, fn {key, member} -> is_binary(key) and spellable?(member) end)
  end

  defp spellable?(_other), do: false
end
