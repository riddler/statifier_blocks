// Test driver for the StatifierBlocksMap hook in
// assets/js/statifier_blocks_map.js, run by StatifierBlocks.MapLayoutTest
// through Node.
//
//   node statifier_blocks_map_hook.mjs <graph.json> <scenario.json>
//
// Mounts the hook itself - its own mounted/0, updated/0 and click listener -
// on a stand-in for the LiveView element, with every layout the real elkjs
// runs counted, then plays the scenario and prints one JSON object.
//
// The scenario is `{"element": {...data attributes...}, "steps": [...]}`.
// `element` is the hook element's dataset before mounting, beside the graph
// (for example `{"editable": "true", "selectEvent": "select-row"}`). Each
// step is one of:
//
//   {"select": "<block id>"}  a patch that changes only the selection: the
//                             graph carries `selected` on that block's node
//                             and `data-selected` names it, as
//                             `StatifierBlocks.Map.graph/2` answers it
//   {"graph": <graph>}        a patch that hands the hook a different graph
//   {"raw": "<text>"}         a patch whose `data-graph` is that text as it
//                             stands, so text that is not JSON reaches the
//                             hook unparsable
//   {"click": "<block id>", "on": "block" | "gap"}
//                             a click on that block's box or on its gap
//
// It prints `layouts`, the number of elkjs layouts run in all; `steps`, one
// entry per step with the layouts run so far, the times the canvas has been
// drawn into so far (`writes`), the block the drawing marks selected and the
// drawing's kind; and `pushes`, every pushEvent the hook made, in order, as
// `{event, payload}`.
import {readFileSync} from "node:fs"
import ELK from "../../../assets/vendor/elk.bundled.js"
import {StatifierBlocksMap} from "../../../assets/js/statifier_blocks_map.js"

const graph = JSON.parse(readFileSync(process.argv[2], "utf8"))
const scenario = JSON.parse(readFileSync(process.argv[3], "utf8"))

let layouts = 0
const realLayout = ELK.prototype.layout
ELK.prototype.layout = function (...args) {
  layouts += 1
  return realLayout.apply(this, args)
}

// The drawing's block groups, read off the markup, each with a classList
// whose toggles are kept on the canvas: a new drawing starts unmarked.
// Every assignment to the canvas's markup is counted as a write, the same
// markup again included, since a browser builds it again.
function canvas() {
  let html = ""
  let marked = new Set()
  let writes = 0
  return {
    dataset: {},
    get innerHTML() { return html },
    set innerHTML(value) { html = value; marked = new Set(); writes += 1 },
    get marked() { return [...marked] },
    get writes() { return writes },
    querySelectorAll(selector) {
      if (selector !== "[data-map-kind=block]") throw new Error(`unexpected selector ${selector}`)
      return [...html.matchAll(/data-map-node="([^"]*)" data-map-kind="block"/g)].map(([, id]) => ({
        dataset: {mapNode: id},
        classList: {
          toggle(name, on) {
            if (name !== "sb-map__block--selected") throw new Error(`unexpected class ${name}`)
            if (on) marked.add(id)
            else marked.delete(id)
          },
        },
      }))
    },
  }
}

// `graph` with `selected` on the one block node `id` names.
function withSelected(node, id) {
  const copy = {...node}
  if (copy.kind === "block" && copy.id === id) copy.selected = true
  if (Array.isArray(copy.children)) copy.children = copy.children.map((c) => withSelected(c, id))
  return copy
}

// What a click on a block's box or its gap reaches the hook as: a target
// whose `closest` answers the drawn group the click is inside.
function clickTarget(id, on) {
  const group = on === "gap"
    ? {dataset: {mapGap: id}, selector: "[data-map-gap]"}
    : {dataset: {mapNode: id, mapKind: "block"}, selector: "[data-map-kind=block]"}
  return {closest: (selector) => (selector === group.selector ? group : null)}
}

const drawing = canvas()
const listeners = []
const pushes = []
const hook = Object.create(StatifierBlocksMap)
hook.el = {
  dataset: {...scenario.element, graph: JSON.stringify(graph)},
  querySelector: (selector) => (selector === "[data-map-canvas]" ? drawing : null),
  addEventListener: (type, listener) => listeners.push({type, listener}),
}
hook.pushEvent = (event, payload) => pushes.push({event, payload})

await hook.mounted()
const kindOf = () => (drawing.innerHTML.includes("data-map-error") ? "error" : drawing.innerHTML === "" ? "none" : "map")
const steps = [{step: "mounted", layouts, writes: drawing.writes, marked: drawing.marked, drawn: kindOf()}]

for (const step of scenario.steps) {
  if (step.select !== undefined) {
    hook.el.dataset.graph = JSON.stringify(withSelected(graph, step.select))
    hook.el.dataset.selected = step.select
    await hook.updated()
  } else if (step.graph !== undefined) {
    hook.el.dataset.graph = JSON.stringify(step.graph)
    await hook.updated()
  } else if (step.raw !== undefined) {
    hook.el.dataset.graph = step.raw
    await hook.updated()
  } else if (step.click !== undefined) {
    for (const {type, listener} of listeners) {
      if (type === "click") listener({target: clickTarget(step.click, step.on)})
    }
  }
  steps.push({step, layouts, writes: drawing.writes, marked: drawing.marked, drawn: kindOf()})
}

process.stdout.write(JSON.stringify({layouts, steps, pushes}))
