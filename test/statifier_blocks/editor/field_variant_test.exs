# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a file that renders one of its components. The whole
# file is LiveView-cased, so the whole file wears the guard.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.FieldVariantTest do
    @moduledoc """
    `variant: :inline` on `Editor.Field.field/1` (campaign-SF038 ruling
    `RQ-SF038-18`, bead `sb-2qm3`).

    The attribute is a component attribute and not a layout mode: a host that
    wants two selects reading as words inside a sentence of its own writing
    says so on the field it places, and nothing about the editor's own forms
    changes. So the claims worth holding are the ones that say the attribute
    stays that small.

    Four of them. The default is not merely equivalent to the old row, it is
    **byte-identical** to it, because an additive attribute that quietly
    reflows every existing form is not additive. `:inline` drops the label's
    chrome without dropping the label: the `<label>` is still in the markup
    and still bound to the control by `for`, and it is a stylesheet rule that
    takes it off the screen, so a control rendered inline still has an
    accessible name. `:inline` posts what `:block` posts - the same controls
    under the same param names - which is what makes
    `ConfigForm.decode/3` read the two identically and the config a form
    produces independent of how its fields were dressed. And the declaration's
    own flags still win over it, because `hidden?` and `readonly?` are
    statements about the field while this is a statement about one placement.
    """

    use StatifierBlocks.EditorLiveCase

    alias StatifierBlocks.Editor.{ConfigForm, Field}
    alias StatifierBlocks.ViewModel

    @stylesheet "assets/css/statifier_blocks.css"

    # The host's own case, in the signup domain: a plan header wanting a
    # choice inside a sentence. A `{:select, choices}` is the field type that
    # case is actually about, and it is also the one with the most markup
    # between the label and the posted value.
    defp select_field(flags \\ []) do
      %ViewModel.Field{
        key: "channel",
        type: {:select, [{"email", "Email"}, {"sms", "Text message"}]},
        label: "Channel",
        required?: Keyword.get(flags, :required?, false),
        default: "email",
        value: "sms",
        hidden?: Keyword.get(flags, :hidden?, false),
        readonly?: Keyword.get(flags, :readonly?, false)
      }
    end

    defp string_field do
      %ViewModel.Field{
        key: "note",
        type: :string,
        label: "Note",
        required?: false,
        default: "",
        value: "first"
      }
    end

    defp markup(field, opts \\ []) do
      render_component(&Field.field/1, [field: field, target: self()] ++ opts)
    end

    # Every `name="..."` the markup posts under, in document order. The param
    # names are the whole of what `ConfigForm.decode/3` reads, so comparing
    # them is comparing what the two variants post.
    defp param_names(html) do
      ~r/name="([^"]*)"/
      |> Regex.scan(html)
      |> Enum.map(fn [_whole, name] -> name end)
    end

    describe "the default" do
      # Sabotage: gave `variant` a `default: :inline`, or dropped the guard
      # from the inline clause so it matched every field - red, because the
      # markup a host already mounted on would change under it.
      test "renders byte for byte what the component rendered without the attribute" do
        assert markup(select_field()) == markup(select_field(), variant: :block)
      end

      # The corroborator: the sameness above would also hold if BOTH spellings
      # were broken in the same way. This says the default is the block row
      # rather than merely equal to whatever `:block` produces.
      test "is the block row, not the inline one" do
        html = markup(select_field())

        assert html =~ ~s(<div class="sb-field )
        refute html =~ "sb-field--inline"
        refute html =~ ~s(data-field-variant="inline")
      end
    end

    describe "the inline variant" do
      # Sabotage: rendered the inline box as a `div` with the block classes -
      # red, because the row a host placed mid-sentence is a block again.
      test "draws an inline box carrying the field's own DOM contract" do
        html = markup(select_field(), variant: :inline)

        assert html =~ "sb-field--inline"
        assert html =~ ~s(data-field-variant="inline")
        assert html =~ ~s(data-field="channel")
        assert html =~ ~s(data-field-type="select")
        refute html =~ ~s(<div class="sb-field )
      end

      # Sabotage: replaced the label with nothing, or with an `aria-label` on a
      # control this component does not own - red. A control with no name is
      # the defect the whole variant is one stylesheet rule away from, so the
      # label being present and bound is asserted rather than assumed.
      test "keeps the label in the markup and bound to the control" do
        html = markup(select_field(), variant: :inline)

        assert html =~ "sb-field__label--inline"
        assert html =~ "Channel"

        [_whole, label_for] = Regex.run(~r/<label[^>]*for="([^"]*)"/, html)
        assert label_for == Field.input_id(select_field())
        assert html =~ ~s(id="#{label_for}")
      end

      # Sabotage: swapped the clipping recipe for `display: none` - red. Both
      # hide the label on screen; only one leaves it in the accessibility
      # tree, and the difference is the whole reason the label is still there.
      test "hides the label by clipping it, not by removing it from the a11y tree" do
        rule = label_rule()

        assert rule =~ "clip-path"
        refute rule =~ "display: none"
        refute rule =~ "visibility: hidden"
      end

      # Sabotage: dropped the findings loop from the inline clause - red. A
      # field owns its findings (decision 11) wherever it is placed; a variant
      # that silently swallows them loses information rather than chrome.
      test "still shows the field's own findings" do
        field = %{select_field() | findings: [finding("Pick a channel")]}
        html = markup(field, variant: :inline)

        assert html =~ "Pick a channel"
        assert html =~ "sb-finding"
      end
    end

    describe "what the inline variant posts" do
      # Sabotage: rendered the inline control from different markup instead of
      # calling the same `control/1` - red, because the param names drift and
      # the form posts under keys the decode never reads.
      test "is exactly what the block variant posts" do
        assert param_names(markup(select_field())) ==
                 param_names(markup(select_field(), variant: :inline))

        assert param_names(markup(string_field())) ==
                 param_names(markup(string_field(), variant: :inline))
      end

      # The claim the one above is only evidence for: a payload posted from
      # inline markup decodes to the config a payload posted from block markup
      # decodes to. Asserted through `decode/3` itself rather than stopping at
      # the names, because `decode/3` is the contract the bead names.
      test "decodes to the same config through ConfigForm.decode/3" do
        fields = [select_field(), string_field()]

        [name | _rest] = param_names(markup(select_field(), variant: :inline))
        assert name == "config[channel]"

        params = %{"config" => %{"channel" => "email", "note" => "typed"}}

        assert ConfigForm.decode(fields, params) == %{
                 "channel" => "email",
                 "note" => "typed"
               }
      end
    end

    describe "the declaration's flags win over the variant" do
      # Sabotage: put the inline clause ABOVE the two flag clauses - red on
      # both. A hidden field would start rendering a control, which is the
      # one thing ADR-0002 decision 7's F1 says it never does.
      test "a hidden field renders nothing at all, inline or not" do
        assert markup(select_field(hidden?: true), variant: :inline) =~ ~r/\A\s*\z/
      end

      test "a readonly field renders its readonly row, inline or not" do
        html = markup(select_field(readonly?: true), variant: :inline)

        assert html =~ ~s(data-field-readonly="true")
        refute html =~ "<select"
        refute html =~ ~s(data-field-variant="inline")
      end
    end

    defp finding(message) do
      StatifierBlocks.Finding.new({:config, "blk_seed", "channel"}, :config, message)
    end

    # The `.sb-field__label--inline` declaration block, comments stripped, so a
    # sentence in a comment cannot answer for a rule the sheet does not have.
    defp label_rule do
      css = @stylesheet |> File.read!() |> StatifierBlocks.ThemeAudit.strip_comments()

      [_whole, body] = Regex.run(~r/\.sb-field__label--inline\s*\{([^}]*)\}/, css)
      body
    end
  end
end
