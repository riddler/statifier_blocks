# How to publish a document

This guide shows you how to write the check your publish step runs before it
keeps a revision of a block document, and how to read what the check answers.

The package ships the checks, not the publish. Your publish step, its
registries, its revision store and its editor UI are yours; this package
ships pure functions that step calls, and your step refuses the publish on
what they find. There is no publish step, publish store or process in here.

The example is patron registration: a visitor becomes a library patron
through a few screens, and the document waits for the host to say the
visitor's email address is verified.

## Call the checks in order

Call these four in this order, from your publish step:

1. **`StatifierBlocks.Publish.findings/3`**, with the revision being
   published (the document as saved), the palette and the context map the
   editor takes (`:datamodel`, `:declare`, `:chart_outcomes`, every key
   optional). It runs stages 1 to 4 of the compile - Document, Resolve,
   Config and Structure - through
   `StatifierBlocks.Compiler.structure_findings/3`, and none of the refusals
   the compile runs between Structure and Emit; then it runs the editor's
   own composition over their answer, and returns `StatifierBlocks.Finding`s
   in the editor's order. It emits nothing. A document the compile's
   Document stage refuses comes back as one finding anchored `:document`,
   and nothing else.
2. **`StatifierBlocks.Compiler.compile/3`**, with the same `:datamodel` and
   `:declare`. It adds what only the stages after Structure can find. Its
   refusal and its warnings are `StatifierBlocks.Compiler.Finding`s;
   `StatifierBlocks.Finding.from_compiler_all/2` adapts them to the same
   shape.
3. **The document graph**, over the `%StatifierBlocks.Compiled{}` the compile
   returned. Publishing a parent, call `StatifierBlocks.Graph.check/2` with
   your resolver from a document id to the compiled artifact of that
   document's published revision. Publishing a new revision of a child,
   call `StatifierBlocks.Graph.consumers_broken/2` with the published
   parents you say name that child; it answers each finding paired with
   that parent's document id. Each call judges pairs; walking the graph is
   yours (ADR-0008's Amendment of 2026-09-22).
4. **The `accepts` declaration**, for a revision that carries one. The
   engine's `Statifier.Chart.check_accepts(machine, declared)` judges
   `compiled.accepts` against the chart that revision compiled to, the one
   you will start executions on (ADR-0014 decision 4). It is the engine's
   function, added in statifier 2.7.0, and this package runs no check of
   its own for that rule. It answers a map, not findings: the declared
   names no reachable transition can take (`unreachable`) and the reachable
   descriptors no declared name matches (`undeclared`). A declared name in
   `unreachable` refuses the publish; `undeclared` is internal, never an
   error (ADR-0014 decision 4).

## Decide on each finding by its severity

Every answer from steps 1 to 3 is a finding with one of three severities,
and the rule is the same whichever of those calls reported it:

- **`:error` refuses the publish.**
- **`:warning` is your call.** A reasonable host publishes over one and
  shows it to the author who published, the way the drawer already showed
  it while they edited; a host that wants a warning to stop a publish asks
  the author to confirm first. What it should not do is drop it.
- **`:info` never refuses.** A config value naming a datamodel path the
  host does not declare is `:info`: an advisory, not a refusal. When the
  document declares its own datamodel roots (its `datamodel` key holds at
  least one entry), `Publish.findings/3` answers that same advisory at
  `:error` instead, so the publish refuses; the editor keeps showing it at
  `:info` (ADR-0005's Amendment of 2026-10-19 on 11e).

The editor shows the same findings live because it runs the same functions:
the findings it derives, the undeclared-path advisories, the subchart outcome
disagreements and the palette's validators are what step 1 composes. Handed
the adapted `StatifierBlocks.Compiler.structure_findings/3` list as its
`findings` assign, the editor's list for a document equals
`Publish.findings/3`'s for the same palette and context, order included, and
`StatifierBlocks.Editor.findings_count/3` is its length (ADR-0004's
Amendment of 2026-09-22, G4). The one difference is the severity of an
undeclared-path advisory in a document that declares its own roots, above.
Steps 3 and 4 read a compiled artifact and are not in the editor's list.

## Write the check

A host's check for steps 1 and 2, written against those calls. Your publish
step runs the graph check and the `accepts` check after it, over the
compiled artifact it answers.

```elixir
defmodule MyApp.Publishing do
  @moduledoc "The host's publish check: the package's findings, the host's verdict."

  alias StatifierBlocks.{Compiler, Finding, Publish}

  def check(document, palette, context) do
    findings = Publish.findings(document, palette, context)

    # An :error here already refuses the publish, so the document is not
    # compiled.
    if refuses?(findings) do
      {:refused, findings}
    else
      opts = context |> Map.take([:datamodel, :declare]) |> Map.to_list()

      case Compiler.compile(document, palette, opts) do
        {:ok, compiled} ->
          {warnings, _no_anchor} = Finding.from_compiler_all(compiled.warnings)
          {:ok, compiled, findings ++ warnings}

        {:error, refusal} ->
          {adapted, _no_anchor} = Finding.from_compiler_all(refusal)
          {:refused, findings ++ adapted}
      end
    end
  end

  defp refuses?(findings), do: Enum.any?(findings, &(&1.severity == :error))
end
```

## Read what the author saw

Take the patron registration document from ADR-0014, the one that waits for a
new patron's email to be verified, and add a `core.assign` that writes
`patron.card_number`. The host declares `patron.email` and nothing else, and
the document declares no datamodel roots of its own.

- While the author edits, the drawer shows one row on that block's `path`
  field: `patron.card_number is not declared in the datamodel`, severity
  `:info`.
- At publish, `Publish.findings/3` returns that same finding and nothing
  else. Nothing is an `:error`, the compile succeeds, and the host publishes.
  The author saw the advisory before pressing publish, and the publish does
  not refuse on it.
- Leave the `core.await`'s `event` blank instead and the answer is an
  `:error` on `{:config, block_id, "event"}`: in the drawer as the author
  clears the field, and in `Publish.findings/3`'s list, so the host refuses.
  That `:error` is in the list twice, once derived by the editor's view
  model and once from the compile's Config stage, as the editor shows it
  when a host hands it the compile's refusal; nothing de-duplicates it.

## Where to go next

- [How to write a host advisory finding](../host-validators.md) puts a rule
  of your own in the list step 1 composes.
- [Documents, revisions, charts and executions, and why blocks compile to a chart](../explanation/documents-revisions-charts-and-executions.md)
  says what a publish makes and what it leaves alone.
