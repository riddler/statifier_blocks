// Test driver for the StatifierBlocksMap hook's hover, in
// assets/js/statifier_blocks_map.js, run by StatifierBlocks.MapHoverTest
// through Node.
//
//   node statifier_blocks_map_hover.mjs <page.json>
//
// `page.json` is what a page renders: `graph`, the Map's graph as the page
// hands it to the hook; `region`, the description region's inner markup;
// and `entries`, the hidden store's entries as `{id, html}`; and,
// optionally, `patched`, the region's inner markup after a later patch (a
// row selected once the page is up). The driver mounts the real hook - its
// own mounted/0, which draws the graph through the real elkjs - over a
// small document (the region, the hover layer beside it, the store, and
// listeners it records), and then points at every element the drawing
// carries, and at every child of each (the rect, text, circle or path a
// real pointer lands on), each time followed by a pointer over nothing the
// map draws.
//
// The region is the announced node, and only the server writes it. The
// driver records every write anything else makes to it - its markup, its
// dataset, any attribute - so a hook that touched it on a hover is caught
// however it did so. The page's own patches are the server's writes.
//
// It prints one JSON object:
//
// - `hovers`: for every element pointed at, the id it resolved to, whether
//   the layer then held exactly that id's stored entry, shown and marked
//   with it, whether the region still held what the server last wrote, and
//   whether the pointer moving off hid and emptied the layer again;
// - `regionWrites`: every write the hook made to the region, over the
//   whole run;
// - `missing`: every drawn id the store has no entry for;
// - `chained`: pointing at one element and then straight at another shows
//   the second, and moving off then hides the layer;
// - `outOfWindow`: a pointer leaving the window hides the layer;
// - `gaps`: a gap's "+" describes nothing, and pointing at one hides the
//   layer;
// - `patchedMidHover`: a selection that patches the region mid-hover, and
//   a patch that drops the layer's mark, leave the layer showing the
//   hovered entry over the patched region, and moving off hides the layer
//   with the region still patched;
// - `unnamed`: a hook whose element names no layer and no store changes
//   nothing when pointed at;
// - `pushes`: every event the hook pushed to the server;
// - `listening`: how many listeners the hook left on the document after
//   `destroyed()`.
import {readFileSync} from "node:fs"
import {StatifierBlocksMap} from "../../../assets/js/statifier_blocks_map.js"

const page = JSON.parse(readFileSync(process.argv[2], "utf8"))

// A small element tree over the drawn markup: every tag with its data
// attributes as `dataset`, its parent, and a `closest` that walks from the
// element up through its ancestors, as the DOM's does, matching attribute
// selectors (`[name]` and `[name=value]`).
const unescape = (v) => v.replace(/&quot;/g, "\"").replace(/&#39;/g, "'")
  .replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&")
const camel = (name) => name.replace(/-([a-z])/g, (_m, c) => c.toUpperCase())

function matches(el, selector) {
  const [, name, value] = selector.match(/^\[([a-z-]+)(?:=([^\]]+))?\]$/)
  const key = camel(name.replace(/^data-/, ""))
  if (!(key in el.dataset)) return false
  return value === undefined || el.dataset[key] === value
}

function parse(markup) {
  const root = {tag: "#root", dataset: {}, parent: null, children: []}
  let current = root
  for (const [, closing, tag, attrs, selfClosing] of
    markup.matchAll(/<(\/?)([a-zA-Z]+)([^>]*?)(\/?)>/g)) {
    if (closing) {
      current = current.parent || root
      continue
    }
    const dataset = {}
    for (const [, name, value] of attrs.matchAll(/data-([a-z-]+)="([^"]*)"/g)) {
      dataset[camel(name)] = unescape(value)
    }
    const el = {tag, dataset, parent: current, children: []}
    el.closest = (selector) => {
      for (let at = el; at && at.tag !== "#root"; at = at.parent) {
        if (matches(at, selector)) return at
      }
      return null
    }
    current.children.push(el)
    if (!selfClosing) current = el
  }
  return root
}

// The page: the region, its hover layer, the store, and a document that
// records listeners. Every write to the region outside `server()` is
// recorded in `regionWrites`.
let resting = page.region
const regionWrites = []
let serverWriting = false
const server = (fn) => {
  serverWriting = true
  try { fn() } finally { serverWriting = false }
}
const record = (write) => { if (!serverWriting) regionWrites.push(write) }
const regionDataset = new Proxy({}, {
  set(target, key, value) { record(["dataset", key, value]); target[key] = value; return true },
  deleteProperty(target, key) { record(["delete dataset", key]); delete target[key]; return true },
})
const region = new Proxy({
  innerHTML: resting,
  dataset: regionDataset,
  attributes: {"aria-live": "polite"},
  setAttribute(name, value) { record(["setAttribute", name, value]); this.attributes[name] = value },
  removeAttribute(name) { record(["removeAttribute", name]); delete this.attributes[name] },
  toggleAttribute(name) { record(["toggleAttribute", name]) },
}, {
  set(target, key, value) { record([key, value]); target[key] = value; return true },
  deleteProperty(target, key) { record(["delete", key]); delete target[key]; return true },
})
const layer = {innerHTML: "", dataset: {}, hidden: true}
const store = {
  children: page.entries.map((entry) => ({dataset: {describes: entry.id}, innerHTML: entry.html})),
}
const html = new Map(page.entries.map((entry) => [entry.id, entry.html]))
const listeners = {}
const ids = {"sb-map-info": region, "sb-map-info-hover": layer, "sb-map-info-store": store}
const doc = {
  getElementById: (id) => ids[id] || null,
  addEventListener: (type, fn) => { (listeners[type] ||= []).push(fn) },
  removeEventListener: (type, fn) => {
    listeners[type] = (listeners[type] || []).filter((f) => f !== fn)
  },
}
const fire = (type, event) => { for (const fn of listeners[type] || []) fn(event) }
const over = (el) => fire("mouseover", {target: el, relatedTarget: null})

// The hook's element: the graph, an editable page (so the gaps are drawn),
// the region's, the layer's and the store's ids, and the canvas it draws
// into.
const canvas = {innerHTML: "", querySelectorAll: () => []}
const pushes = []

function mount(dataset) {
  const hook = Object.create(StatifierBlocksMap)
  hook.el = {
    dataset: {graph: JSON.stringify(page.graph), editable: "true", ...dataset},
    ownerDocument: doc,
    querySelector: (selector) => (selector === "[data-map-canvas]" ? canvas : null),
    addEventListener: () => {},
  }
  hook.pushEvent = (...args) => pushes.push(args)
  hook.pushEventTo = (...args) => pushes.push(args)
  return hook
}

const hook = mount({
  infoHover: "sb-map-info-hover",
  infoStore: "sb-map-info-store",
})
const {drawn} = await hook.mounted()
if (drawn !== "map") throw new Error(`the map did not draw: ${canvas.innerHTML}`)

const all = []
const walk = (el) => { for (const child of el.children) { all.push(child); walk(child) } }
walk(parse(canvas.innerHTML))
const svg = all.find((el) => el.tag === "svg")

// A patch after mount redraws the region (a row selected); that is what
// the region must still hold through every hover.
if (page.patched !== undefined) {
  server(() => { region.innerHTML = page.patched })
  resting = page.patched
}

// Every drawn element the map gives an id: a group carrying data-map-node,
// or a path carrying data-map-edge.
const drawnEls = all.filter((el) =>
  (el.tag === "g" && el.dataset.mapNode !== undefined) || el.dataset.mapEdge !== undefined)
const idOf = (el) => el.dataset.mapNode ?? el.dataset.mapEdge

// The layer is hidden, empty and unmarked.
const idle = () => layer.hidden === true && layer.innerHTML === "" &&
  layer.dataset.mapHover === undefined

const hovers = []
const point = (el, element, child) => {
  over(el)
  const id = layer.dataset.mapHover ?? null
  const shown = id !== null && layer.hidden === false && layer.innerHTML === html.get(id)
  const silent = region.innerHTML === resting
  over(svg)
  hovers.push({element, child, id, shown, silent,
    restored: idle() && region.innerHTML === resting})
}

for (const el of drawnEls) {
  point(el, idOf(el), null)
  for (const child of el.children) point(child, idOf(el), child.tag)
}

const missing = [...new Set(drawnEls.map(idOf))].filter((id) => !html.has(id))

// One element, then straight at another, then off.
const [first, second] = drawnEls
over(first)
over(second)
const chainedShown = layer.dataset.mapHover === idOf(second) && layer.hidden === false &&
  layer.innerHTML === html.get(idOf(second))
over(svg)
const chained = chainedShown && idle() && region.innerHTML === resting

// The pointer leaves the window.
over(first)
fire("mouseout", {target: first, relatedTarget: null})
const outOfWindow = idle() && region.innerHTML === resting

// A gap's "+" and whatever is inside it.
const gapEls = all.filter((el) => el.dataset.mapGap !== undefined)
const gaps = gapEls.length > 0 && gapEls.every((gap) => {
  over(first)
  over(gap.children[0] || gap)
  return idle() && region.innerHTML === resting
})

// A selection mid-hover: the server writes the region, and a patch that
// reaches the layer (which LiveView leaves alone but for its data
// attributes) drops the layer's mark. The layer still shows the hovered
// entry over the patched region; moving off hides it, and the region
// keeps what the server wrote.
over(first)
server(() => { region.innerHTML = "<p>patched</p>" })
delete layer.dataset.mapHover
const midHover = layer.hidden === false && layer.innerHTML === html.get(idOf(first)) &&
  region.innerHTML === "<p>patched</p>"
over(svg)
const patchedMidHover = midHover && idle() && region.innerHTML === "<p>patched</p>"
server(() => { region.innerHTML = resting })

StatifierBlocksMap.destroyed.call(hook)

// A hook whose element names no layer and no store: pointing at the
// drawing changes nothing.
const bare = mount({})
await bare.mounted()
over(first)
const unnamed = idle() && region.innerHTML === resting
StatifierBlocksMap.destroyed.call(bare)

const listening = Object.values(listeners).reduce((n, fns) => n + fns.length, 0)

process.stdout.write(JSON.stringify({
  hovers, regionWrites, missing, chained, outOfWindow, gaps, patchedMidHover, unnamed, pushes,
  listening,
}))
