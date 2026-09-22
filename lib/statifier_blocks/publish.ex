defmodule StatifierBlocks.Publish do
  @moduledoc """
  The findings a host's publish step refuses a document on, from the same
  functions the editor and the compile run (ADR-0004's Amendment of
  2026-09-22, G4).

  This module is one pure function. It holds no store, starts no process,
  performs no IO and publishes nothing: the publish step is the host's, and
  it calls `findings/3` and then `StatifierBlocks.Compiler.compile/3`,
  refusing on an `:error` from either. A `:warning` is the host's call. An
  `:info` changes no verdict.

  ## What it is not

  `StatifierBlocks.Compiler.compile/3` is not the editor's pipeline with an
  emit stage added. The compile runs the envelope, slot and assignability
  checks and stops at the first stage that refuses; the editor runs none of
  those itself and takes them from its host as caller-supplied findings,
  and adds what the compile never reports - the undeclared-path advisories,
  the subchart outcome disagreements, the summary lints and the palette's
  `StatifierBlocks.DocumentValidator`s. So this module does not alias the
  compile. It composes the compile's stages before Emit
  (`StatifierBlocks.Compiler.structure_findings/3`) with the editor's own
  composition, and that composition is the answer an author sees in the
  editor for the same document, word for word.

  ## The four steps

    1. `StatifierBlocks.Compiler.structure_findings/3`, with `:datamodel`
       and `:declare` taken from `context`, so the host hands one value to
       both halves.
    2. Every finding adapted through `StatifierBlocks.Finding.from_compiler/2`.
    3. When a finding came from the Document stage, the adapted list is
       returned and nothing else runs: the editor's composition reads a tree,
       and the Document stage has refused the tree. That finding carries the
       `:document` anchor.
    4. Otherwise, the editor's composition with the adapted list as its
       caller-supplied findings: the `findings` of
       `StatifierBlocks.ViewModel.build/3` handed the adapted list, then
       `StatifierBlocks.Datamodel.findings/4`'s advisories, then
       `StatifierBlocks.ViewModel.outcome_findings/3`'s disagreements. The
       view model's own derived findings come first.

  Step 4 is the editor's list for the same document, palette and context
  when the editor is handed the adapted list as its `findings`, in the same
  order, and `StatifierBlocks.Editor.findings_count/3` over the same inputs
  is its length. A config refusal can appear twice in it, once derived by
  the view model and once from the compile's Config stage, exactly as the
  editor shows it when a host hands it the compile's refusal; nothing here
  de-duplicates.

  Nothing here emits, so an Emit-stage or Chart-stage refusal is the
  compile's to report, and the checks a compile's `:entry_type` option
  drives are too: `context` does not carry it.

  An undeclared datamodel path is the editor's `:info` advisory, never a
  refusal.
  """

  alias StatifierBlocks.{Compiler, Datamodel, Document, Finding, Palette, ViewModel}

  @typedoc """
  The same inputs the editor takes, as a map. Every key is optional, and an
  absent key means what the editor's default means.

    * `:datamodel` - the host's datamodel: the declared paths the
      undeclared-path advisory reads, and the datamodel the compile's
      typed-environment read check reads. Absent or `nil` turns the advisory
      off (ADR-0005 amendment `11f`) and gives the read check no
      declarations.
    * `:declare` - the `<data>` roots the host declares for this document,
      the compile option's own `{id, expr}` list. Absent means `[]`, which
      declares none.
    * `:chart_outcomes` - what the host says its stored documents finish
      with, for the subchart outcome disagreements. Absent means `%{}`,
      which says nothing about any chart.
  """
  @type context :: %{
          optional(:datamodel) => term(),
          optional(:declare) => term(),
          optional(:chart_outcomes) => term()
        }

  @doc """
  Every finding the host's publish step judges `document` by, before a
  compile, in the editor's order.

  Pure and total: never a raise on a `%Document{}` and a `%Palette{}`,
  whatever the document holds. A document the Document stage refuses comes
  back as that one finding, anchored `:document`, and nothing else. See the
  moduledoc for the four steps and for what `context` holds.
  """
  @spec findings(Document.t(), Palette.t(), context()) :: [Finding.t()]
  def findings(%Document{} = document, %Palette{} = palette, context) when is_map(context) do
    structure = Compiler.structure_findings(document, palette, compile_opts(context))

    # Every finding `structure_findings/3` returns adapts: the Document
    # stage's to `:document`, every later stage's to the block it names
    # (ADR-0004 decision 10). The refused half is empty for every list the
    # compiler produces (ADR-0005's Amendment of 2026-09-22, `11x`).
    {adapted, _refused} = Finding.from_compiler_all(structure)

    if Enum.any?(structure, &(&1.stage == :document)) do
      adapted
    else
      editor_findings(document, palette, adapted, context)
    end
  end

  # The two compile options this reads, only when the host gave them, so an
  # absent key reaches the compile exactly as an absent option would.
  @spec compile_opts(context()) :: [Compiler.option()]
  defp compile_opts(context) do
    for key <- [:datamodel, :declare], Map.has_key?(context, key) do
      {key, Map.fetch!(context, key)}
    end
  end

  # The editor's composition (`StatifierBlocks.Editor`'s view model), over
  # the caller-supplied findings and the editor's own defaults.
  @spec editor_findings(Document.t(), Palette.t(), [Finding.t()], context()) :: [Finding.t()]
  defp editor_findings(document, palette, caller_findings, context) do
    advisories =
      Datamodel.findings(
        document,
        palette,
        Map.get(context, :datamodel),
        Map.get(context, :declare, [])
      )

    disagreements =
      ViewModel.outcome_findings(document, palette, Map.get(context, :chart_outcomes, %{}))

    %ViewModel{findings: findings} =
      ViewModel.build(document, palette, caller_findings ++ advisories ++ disagreements)

    findings
  end
end
