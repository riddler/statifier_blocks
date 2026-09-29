// statifier_blocks' Map hook: lays out the graph `StatifierBlocks.Map`
// builds with elkjs and draws it as plain SVG.
//
// The server decides everything that is a fact about the document - which
// boxes exist, what they say, how big they are, the order they are in and
// the ELK options that keep that order. This file asks ELK where the boxes
// go and draws them there. It stores nothing: a position lives only in the
// SVG it was drawn into, and the next change lays the graph out again.
//
// A layout that fails draws an error pane in place of the map, never a
// blank one: an empty panel reads as "this document has no steps", which is
// a worse answer than "the map could not be drawn".
//
// ADR-0005 decision 7, as amended on 2026-09-28 (7e to 7g): one hook pushes
// commands, and this is not it. `StatifierBlocksMap` is a draw-only hook. It
// pushes no command and no event name of its own: a click on the drawing is
// sent as the host list's own event, under the name the host stamped on the
// map's element (`data-select-event`, `data-insert-event`), with the payload
// the list sends for the same gesture. A host that stamps no name gets a
// drawing that sends nothing. test/statifier_blocks/assets_test.exs holds
// this file to that. Hover pushes nothing at all: it shows, beside the
// description region, a description the server already rendered into the
// page, and never writes the region itself (see "Hover" below).
//
// Its own entry point, `statifier_blocks/map`, and not the default export of
// `statifier_blocks`: the import below pulls in the whole of the vendored
// elkjs build (ADR-0018 (b)), so a host that never mounts the Map never
// bundles it. `assets/vendor/package.json` marks that directory CommonJS,
// which is what the bundled build is, inside this `"type": "module"`
// package; the file itself is upstream's, byte for byte.
//
// The layout tests run this file, through the same elkjs, outside the
// browser (test/support/js/statifier_blocks_map_layout.mjs).
import ELK from "../vendor/elk.bundled.js"

const SVG_NS = "http://www.w3.org/2000/svg"
const LINE_HEIGHT = 16
const HEADER_BASE = 12

let sharedElk = null

// One ELK instance per page: the bundled build carries its own worker
// shim, and building it is the expensive part.
function elkInstance() {
  if (sharedElk === null) sharedElk = new ELK()
  return sharedElk
}

export function escapeText(value) {
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;")
}

// Lays `graph` out. Resolves to the laid-out graph, or rejects with the
// reason ELK gave - including a result with nothing in it, which is a
// failure rather than a picture.
//
// A graph whose groups all carry their ports is laid out once. A group
// whose body holds a container carries none, because the server cannot
// know how wide ELK will draw that container; so that graph is laid out
// twice: once to read where the body's steps stand, and again with the
// group's ports put there (`portsFrom`). See `StatifierBlocks.Map`'s
// moduledoc, "The happy path runs straight".
export async function layout(graph, elk = elkInstance()) {
  const first = await layoutOnce(graph, elk)
  const ported = portsFrom(graph, first)
  return ported === null ? first : layoutOnce(ported, elk)
}

async function layoutOnce(graph, elk) {
  const {graph: attached, owners} = onPorts(graph)
  const laid = await elk.layout(attached)

  if (!laid || !Array.isArray(laid.children) || laid.children.length === 0 ||
      !(laid.width > 0) || !(laid.height > 0)) {
    throw new Error("the layout came back empty")
  }

  return offPorts(laid, owners)
}

const PORT_SIDE = "org.eclipse.elk.port.side"
const PORT_CONSTRAINTS = "org.eclipse.elk.portConstraints"

// A group's node: a block whose first child is its body's pane.
function bodyPane(node) {
  const [first] = node.children || []
  return node.kind === "block" && first && first.kind === "slot" && first.style === "body" ? first : null
}

// A copy of `graph` with ports on every group the server left without
// them - a group whose body holds a container - placed where `laid`, the
// same graph laid out once, drew that body's steps: the pane's offset in
// the group plus the centre of its widest step, the rule the server
// applies to a body of leaves at its estimate. The ports are the server's
// shape, `<id>#in` on the top side and `<id>#out` on the bottom, at a
// fixed x. Answers null when every group already has its ports, so a
// graph that needs no second layout gets none.
function portsFrom(graph, laid) {
  const placed = new Map()
  const read = (node) => {
    const pane = bodyPane(node)
    const steps = pane ? pane.children || [] : []
    if (steps.length > 0) {
      const widest = steps.reduce((a, b) => (b.width > a.width ? b : a))
      placed.set(node.id, pane.x + widest.x + widest.width / 2)
    }
    for (const child of node.children || []) read(child)
  }
  read(laid)

  const copy = structuredClone(graph)
  let added = false
  const put = (node) => {
    if (bodyPane(node) && !(node.ports || []).length && placed.has(node.id)) {
      const x = placed.get(node.id)
      node.layoutOptions = {...(node.layoutOptions || {}), [PORT_CONSTRAINTS]: "FIXED_POS"}
      node.ports = [port(`${node.id}#in`, x, "NORTH"), port(`${node.id}#out`, x, "SOUTH")]
      added = true
    }
    for (const child of node.children || []) put(child)
  }
  put(copy)

  return added ? copy : null
}

function port(id, x, side) {
  return {id, x, y: 0, width: 0, height: 0, layoutOptions: {[PORT_SIDE]: side}}
}

// A copy of `graph` with every edge into or out of a node that carries
// ports moved onto them: an edge out of the node leaves by its bottom
// port, an edge into it arrives by its top one. A group's ports stand
// where its body's steps do - put there by the server, or by `portsFrom`
// for a body holding a container - so the happy path runs straight
// through the group (`StatifierBlocks.Map`'s moduledoc, "The happy path
// runs straight"). Answers the copy and each port's owner.
export function onPorts(graph) {
  const copy = structuredClone(graph)
  const sides = new Map()
  const owners = new Map()
  const collect = (node) => {
    for (const port of node.ports || []) {
      const side = (port.layoutOptions || {})[PORT_SIDE]
      sides.set(`${node.id}|${side}`, port.id)
      owners.set(port.id, node.id)
    }
    for (const child of node.children || []) collect(child)
  }
  const attach = (node) => {
    for (const edge of node.edges || []) {
      edge.sources = edge.sources.map((id) => sides.get(`${id}|SOUTH`) || id)
      edge.targets = edge.targets.map((id) => sides.get(`${id}|NORTH`) || id)
    }
    for (const child of node.children || []) attach(child)
  }
  collect(copy)
  if (owners.size > 0) attach(copy)
  return {graph: copy, owners}
}

// The laid-out graph with every edge given back its own ends: a port's
// owner in place of the port, so an edge joins block to block again.
export function offPorts(laid, owners) {
  const detach = (node) => {
    for (const edge of node.edges || []) {
      edge.sources = edge.sources.map((id) => owners.get(id) || id)
      edge.targets = edge.targets.map((id) => owners.get(id) || id)
    }
    for (const child of node.children || []) detach(child)
  }
  if (owners.size > 0) detach(laid)
  return laid
}

// Every node in the laid-out graph, parents before children, with its box
// made absolute. ELK answers a child's position relative to its parent, so
// the offsets are added up here, once, rather than by every drawing step.
export function boxes(laid) {
  const out = []
  const walk = (node, dx, dy) => {
    for (const child of node.children || []) {
      const box = {...child, x: dx + child.x, y: dy + child.y}
      out.push(box)
      walk(child, box.x, box.y)
    }
  }
  walk(laid, 0, 0)
  return out
}

// Every edge with its points, and its labels' boxes, made absolute. An
// edge's points are relative to the node it is declared in, which is the
// container holding both of its ends; so are its labels'.
export function edgesOf(laid) {
  const out = []
  const shift = (p, dx, dy) => ({x: dx + p.x, y: dy + p.y})
  const walk = (node, dx, dy) => {
    for (const edge of node.edges || []) {
      const sections = (edge.sections || []).map((section) => ({
        startPoint: shift(section.startPoint, dx, dy),
        endPoint: shift(section.endPoint, dx, dy),
        bendPoints: (section.bendPoints || []).map((p) => shift(p, dx, dy)),
      }))
      const labels = (edge.labels || []).map((label) => ({...label, ...shift(label, dx, dy)}))
      out.push({...edge, sections, labels})
    }
    for (const child of node.children || []) walk(child, dx + child.x, dy + child.y)
  }
  walk(laid, 0, 0)
  return out
}

// Every group's interrupt edges, each with the points it is drawn through,
// absolute. They are not ELK's: the server hands them over on the group's
// node as `interrupts`, beside its `edges`, so the layout never sees them
// and they never move a box. Each is drawn from the boxes the layout
// placed: an `abandon` rule (`to: "exit"`) straight down from the bottom
// of its box to the group's bottom edge, which is where the group is left;
// a `resume` rule (`to: "body"`) up from the top of its box to the head of
// the group's body, and in from its side when the head sits to the left.
export function interruptsOf(laid) {
  const all = boxes(laid)
  const byId = new Map(all.map((box) => [box.id, box]))
  const out = []

  for (const group of all) {
    for (const edge of group.interrupts || []) {
      const rule = byId.get(edge.sources[0])
      if (!rule) continue
      const x = rule.x + rule.width / 2
      let points

      if (edge.to === "exit") {
        points = [{x, y: rule.y + rule.height}, {x, y: group.y + group.height}]
      } else {
        const head = byId.get(edge.head)
        if (head && head.x + head.width < x) {
          const y = head.y + head.height / 2
          points = [{x, y: rule.y}, {x, y}, {x: head.x + head.width, y}]
        } else {
          points = [{x, y: rule.y}, {x, y: head ? head.y + head.height : group.y}]
        }
      }

      out.push({id: edge.id, source: edge.sources[0], target: edge.targets[0], to: edge.to, points})
    }
  }

  return out
}

// Every timer edge, each with the points it is drawn through and where its
// label goes, absolute. Like the interrupt edges they are not ELK's: the
// server hands them over on the graph's root as `timers`, so the layout
// never sees them and they never move a box. Each runs from the side of
// the delayed send's box to the side of the box that hears its event, an
// interrupt rule or a wait: across to the right when that box stands to the
// right, to the left when it stands to the left, and out past both right
// sides and back when the two share a column. The label, the delay as the
// send holds it, is written beside the vertical run.
const TIMER_REACH = 16

export function timersOf(laid) {
  const byId = new Map(boxes(laid).map((box) => [box.id, box]))
  const out = []

  for (const edge of laid.timers || []) {
    const send = byId.get(edge.sources[0])
    const hears = byId.get(edge.targets[0])
    if (!send || !hears) continue
    const sy = send.y + send.height / 2
    const hy = hears.y + hears.height / 2
    let from
    let x
    let to

    if (hears.x >= send.x + send.width) {
      from = send.x + send.width
      to = hears.x
      x = (from + to) / 2
    } else if (hears.x + hears.width <= send.x) {
      from = send.x
      to = hears.x + hears.width
      x = (from + to) / 2
    } else {
      from = send.x + send.width
      to = hears.x + hears.width
      x = Math.max(from, to) + TIMER_REACH
    }

    const points = [{x: from, y: sy}, {x, y: sy}, {x, y: hy}, {x: to, y: hy}]
    const label = Math.abs(hy - sy) >= LINE_HEIGHT
      ? {x: x + 4, y: (sy + hy) / 2 + 4}
      : {x: Math.min(from, x) + 4, y: sy - 4}

    out.push({
      id: edge.id,
      source: edge.sources[0],
      target: edge.targets[0],
      delay: edge.delay,
      points,
      label,
    })
  }

  return out
}

// A branch's band: one strip spanning every arm, in the room the server
// left between the branch's header and its arms, with the fork mark at its
// left and the branch's caption after it. Read from the boxes the layout
// placed, never stored; never narrower than the server's `caption_width`,
// the room the fork mark and the caption need. Answers
// `{x, y, width, height, fork: {x, y}, caption: {x, y} | null}` in the
// coordinates `node` is in (absolute, for a box out of `boxes`), or null
// for a node with no band or no arm.
const BAND_HEIGHT = 16
const BAND_GAP = 4
// The fork mark's room at the band's left, before the caption: the same
// 26px the server's `caption_width` counts.
const FORK_ROOM = 26

export function bandOf(node) {
  if (node.band !== true) return null
  const arms = (node.children || []).filter((c) => c.kind === "slot" && c.style === "arm")
  if (arms.length === 0) return null

  const left = Math.min(...arms.map((a) => a.x))
  const right = Math.max(...arms.map((a) => a.x + a.width))
  const top = Math.min(...arms.map((a) => a.y))
  const y = node.y + top - BAND_GAP - BAND_HEIGHT

  return {
    x: node.x + left,
    y,
    width: Math.max(right - left, node.caption_width || 0),
    height: BAND_HEIGHT,
    fork: {x: node.x + left + 6, y: y + 1},
    caption: node.caption ? {x: node.x + left + FORK_ROOM, y: y + BAND_HEIGHT - 4} : null,
  }
}

// The fork mark, a 14px glyph: one stem splitting into three.
function drawFork({x, y}) {
  return `<path class="sb-map__fork" data-map-fork="true" ` +
    `d="M${x + 7} ${y} V${y + 5} M${x + 7} ${y + 5} L${x + 1} ${y + 13} ` +
    `M${x + 7} ${y + 5} V${y + 13} M${x + 7} ${y + 5} L${x + 13} ${y + 13}" style="${MARK_STYLE}"/>`
}

function drawBand(node) {
  const band = bandOf(node)
  if (band === null) return ""
  // Its own group, so the selected box's `> rect` outline stays on the box.
  return `<g class="sb-map__band-group">` +
    `<rect class="sb-map__band" data-map-band="${escapeText(node.id)}" ` +
    `x="${band.x}" y="${band.y}" width="${band.width}" height="${band.height}" rx="4" ` +
    `style="fill: var(--sb-map-band-fill, #e2e8f0); stroke: var(--sb-map-slot-stroke, #cbd5e1)"/>` +
    drawFork(band.fork) + drawCaption(band.caption, node.caption) + `</g>`
}

// A container's one-line caption: on a branch's band, or under a group's
// rules column's label. The text is the server's: the first sentence of
// the type's own explanation, cut to one line.
function drawCaption(at, text) {
  if (!at || !text) return ""
  return `<text class="sb-map__caption" data-map-caption="true" x="${at.x}" y="${at.y}">` +
    `${escapeText(text)}</text>`
}

function textLines(node, x, y, className) {
  return (node.lines || [])
    .map((line, i) =>
      `<text class="${className}" x="${x}" y="${y + i * LINE_HEIGHT}">${escapeText(line)}</text>`)
    .join("")
}

// The "+" at a block's lower right corner: the gap right after the block,
// the same gap the list's "+" under its row arms. Drawn only on a page that
// can edit, and never for the root, which sits in no slot.
function drawGap(node) {
  if (node.kind !== "block" || node.gap !== true) return ""
  const cx = node.x + node.width - 10
  const cy = node.y + node.height
  return `<g class="sb-map__gap" data-map-gap="${escapeText(node.id)}">` +
    `<circle cx="${cx}" cy="${cy}" r="7" ` +
    `style="fill: var(--sb-map-block-fill, #ffffff); stroke: var(--sb-map-edge, #64748b)"/>` +
    `<path d="M${cx - 3.5} ${cy} H${cx + 3.5} M${cx} ${cy - 3.5} V${cy + 3.5}" ` +
    `style="stroke: var(--sb-map-edge, #64748b); stroke-width: 1.5"/>` +
    `</g>`
}

function drawNode(node) {
  const x = node.x
  const y = node.y
  const w = node.width
  const h = node.height
  const container = Array.isArray(node.children) && node.children.length > 0
  const id = escapeText(node.id)

  if (node.kind === "empty") {
    const target = node.parent === undefined ? "" :
      ` data-map-parent="${escapeText(node.parent)}" data-map-slot="${escapeText(node.slot)}"`
    return `<g class="sb-map__empty" data-map-node="${id}" data-map-kind="empty"${target}>` +
      `<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="6" ` +
      `style="fill: var(--sb-map-empty-fill, transparent); stroke: var(--sb-map-empty-stroke, #94a3b8); stroke-dasharray: 4 3"/>` +
      `<text class="sb-map__empty-text" x="${x + 12}" y="${y + HEADER_BASE + LINE_HEIGHT - 4}">${escapeText(node.title)}</text>` +
      `</g>`
  }

  // Where the document finishes: the state chart's final mark, a dot inside
  // a ring, one per outcome it finishes with - a solid ring for done, a
  // dashed one where an interrupt rule abandons the last step. It carries
  // no text (the outcome is named on the edge into it). Like the start dot
  // it is not a block: it carries its id, so the description region can
  // name it, but no data-map-kind, so a click on it selects nothing.
  if (node.kind === "end") {
    const abandon = node.outcome === "abandon"
    const cx = x + w / 2
    const cy = y + h / 2
    const r = Math.min(w, h) / 2 - 1
    return `<g class="sb-map__end sb-map__end--${abandon ? "abandon" : "done"}" ` +
      `data-map-end="${id}" data-map-node="${id}" data-map-outcome="${escapeText(node.outcome)}">` +
      `<circle class="sb-map__end-ring" cx="${cx}" cy="${cy}" r="${r}" ` +
      `style="fill: none; stroke: var(--sb-map-edge, #64748b); stroke-width: 1.5` +
      `${abandon ? "; stroke-dasharray: 3 2" : ""}"/>` +
      `<circle class="sb-map__end-dot" cx="${cx}" cy="${cy}" r="${r / 2}" ` +
      `style="fill: var(--sb-map-edge, #64748b)"/>` +
      `</g>`
  }

  // Where the document starts: the state chart's initial mark, a filled
  // dot with no text. Like the end mark it is not a block, and it carries
  // no data-map-kind, so a click on it selects nothing.
  if (node.kind === "start") {
    return `<g class="sb-map__start" data-map-start="${id}" data-map-node="${id}">` +
      `<circle cx="${x + w / 2}" cy="${y + h / 2}" r="${Math.min(w, h) / 2}" ` +
      `style="fill: var(--sb-map-edge, #64748b)"/>` +
      `</g>`
  }

  // A slot's box: an arm, a rail, a tray, or a group's body pane. A group's
  // rules column carries its caption on the line under its label.
  if (node.kind === "slot") {
    const style = escapeText(node.style || "arm")
    const top = y + HEADER_BASE + LINE_HEIGHT - 4
    const caption = {x: x + 12, y: top + (node.lines || []).length * LINE_HEIGHT}
    return `<g class="sb-map__slot sb-map__slot--${style}" data-map-node="${id}" data-map-kind="slot">` +
      `<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="8" ` +
      `style="fill: var(--sb-map-slot-fill, #f8fafc); stroke: var(--sb-map-slot-stroke, #cbd5e1)"/>` +
      textLines(node, x + 12, top, "sb-map__slot-label") + drawCaption(caption, node.caption) +
      `</g>`
  }

  const caption = `<text class="sb-map__title" x="${x + 12}" y="${y + HEADER_BASE + LINE_HEIGHT - 4}">${escapeText(node.title)}</text>`
  const body = textLines(node, x + 12, y + HEADER_BASE + 2 * LINE_HEIGHT - 4, "sb-map__sentence")

  return `<g class="sb-map__block${container ? " sb-map__block--container" : ""}" data-map-node="${id}" data-map-kind="block">` +
    `<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="8" ` +
    `style="fill: var(--sb-map-block-fill, #ffffff); stroke: var(--sb-map-block-stroke, #64748b)"/>` +
    caption + body + drawMark(node) + drawBand(node) +
    `</g>`
}

// A timer block's mark, a 14px glyph at the box's top right, level with the
// title (the server left the title room for it): an hourglass for a wait
// on an event (`core.await`), a clock face for a timed wait (`core.wait`)
// or a delayed send. It is drawn inside the block's group, so a click on it
// selects the block and nothing else.
const MARK_STYLE = "fill: none; stroke: var(--sb-map-mark, #64748b); stroke-width: 1.5"

function drawMark(node) {
  if (node.mark !== "wait" && node.mark !== "clock") return ""
  const x = node.x + node.width - 22
  const y = node.y + HEADER_BASE - 4
  const glyph = node.mark === "wait"
    ? `<path d="M${x + 2} ${y} H${x + 12} M${x + 2} ${y + 14} H${x + 12} ` +
      `M${x + 3} ${y} L${x + 11} ${y + 14} M${x + 11} ${y} L${x + 3} ${y + 14}" style="${MARK_STYLE}"/>`
    : `<circle cx="${x + 7}" cy="${y + 7}" r="6.5" style="${MARK_STYLE}"/>` +
      `<path d="M${x + 7} ${y + 3} V${y + 7} H${x + 10}" style="${MARK_STYLE}"/>`

  return `<g class="sb-map__mark sb-map__mark--${node.mark}" data-map-mark="${node.mark}">` +
    glyph + `</g>`
}

// A layout edge. A branch's rejoin is drawn heavier, with a join dot where
// it leaves the branch's bottom edge: the point the arms come back
// together. An edge into an end mark carries its outcome, and the one into
// an abandon end is dashed, as the interrupt edges that lead there are.
function drawEdge(edge) {
  const rejoin = edge.kind === "rejoin"
  const outcome = edge.outcome === undefined ? "" : ` data-map-outcome="${escapeText(edge.outcome)}"`
  return (edge.sections || []).map((section) => {
    const points = [section.startPoint, ...(section.bendPoints || []), section.endPoint]
    const d = points.map((p, i) => `${i === 0 ? "M" : "L"}${p.x} ${p.y}`).join(" ")
    const path = rejoin
      ? `<path class="sb-map__edge sb-map__edge--rejoin" data-map-edge="${escapeText(edge.id)}" ` +
        `data-map-edge-kind="rejoin"${outcome} d="${d}" marker-end="url(#sb-map-arrow)" ` +
        `style="fill: none; stroke: var(--sb-map-edge, #64748b); stroke-width: 1.5"/>`
      : edge.kind === "end"
        ? `<path class="sb-map__edge sb-map__edge--end" data-map-edge="${escapeText(edge.id)}" ` +
          `data-map-edge-kind="end"${outcome} d="${d}" marker-end="url(#sb-map-arrow)" ` +
          `style="fill: none; stroke: var(--sb-map-edge, #64748b)` +
          `${edge.outcome === "abandon" ? "; stroke-dasharray: 5 4" : ""}"/>`
        : `<path class="sb-map__edge" data-map-edge="${escapeText(edge.id)}" d="${d}" ` +
          `marker-end="url(#sb-map-arrow)" style="fill: none; stroke: var(--sb-map-edge, #64748b)"/>`
    const dot = rejoin
      ? `<circle class="sb-map__join" data-map-join="${escapeText(edge.id)}" ` +
        `data-map-edge="${escapeText(edge.id)}" ` +
        `cx="${section.startPoint.x}" cy="${section.startPoint.y}" r="3.5" ` +
        `style="fill: var(--sb-map-edge, #64748b)"/>`
      : ""
    return path + dot
  }).join("") + drawEdgeLabels(edge)
}

// An edge's caption - the start edge's sentence, or the outcome on an edge
// into an end mark - written where the layout placed its label (the server
// sized it, so the layout left it room). It carries the edge's id, so
// pointing at the caption names the edge.
function drawEdgeLabels(edge) {
  const which = edge.kind === "start" ? "start" : "end"
  return (edge.labels || []).map((label) =>
    `<text class="sb-map__caption sb-map__${which}-caption" data-map-caption="true" ` +
    `data-map-edge="${escapeText(edge.id)}" ` +
    `x="${label.x}" y="${label.y + label.height - 4}">${escapeText(label.text)}</text>`,
  ).join("")
}

// An interrupt edge, dashed: it is not a step that follows the one before
// it but a way out of (or back into) the group that fires whenever the
// rule's event arrives.
function drawInterrupt(edge) {
  const d = edge.points.map((p, i) => `${i === 0 ? "M" : "L"}${p.x} ${p.y}`).join(" ")
  return `<path class="sb-map__edge sb-map__edge--interrupt" data-map-edge="${escapeText(edge.id)}" ` +
    `data-map-edge-kind="interrupt" data-map-edge-to="${escapeText(edge.to)}" d="${d}" ` +
    `marker-end="url(#sb-map-arrow)" ` +
    `style="fill: none; stroke: var(--sb-map-edge, #64748b); stroke-dasharray: 5 4"/>`
}

// A timer edge, dotted where an interrupt edge is dashed: it is not a way
// out of anything but the event a delayed send arms, drawn to the rule or
// the wait that hears it, labelled with the delay. Its label carries the
// edge's id, so pointing at either names the edge.
function drawTimer(edge) {
  const d = edge.points.map((p, i) => `${i === 0 ? "M" : "L"}${p.x} ${p.y}`).join(" ")
  const id = escapeText(edge.id)
  return `<path class="sb-map__edge sb-map__edge--timer" data-map-edge="${id}" ` +
    `data-map-edge-kind="timer" d="${d}" marker-end="url(#sb-map-arrow)" ` +
    `style="fill: none; stroke: var(--sb-map-edge, #64748b); stroke-dasharray: 2 3"/>` +
    `<text class="sb-map__caption sb-map__timer-caption" data-map-caption="true" ` +
    `data-map-edge="${id}" x="${edge.label.x}" y="${edge.label.y}">${escapeText(edge.delay)}</text>`
}

// The laid-out graph as one SVG string. The picture is decoration over the
// list, which is the accessible path through the same document, so the SVG
// is hidden from assistive technology and takes no focus.
//
// `editable` adds the gaps an insert can target; a read-only page draws
// none.
export function renderSvg(laid, {editable = false} = {}) {
  const all = boxes(laid)
  const nodes = all.map(drawNode).join("")
  const gaps = editable ? all.map(drawGap).join("") : ""
  const edges = edgesOf(laid).map(drawEdge).join("") +
    interruptsOf(laid).map(drawInterrupt).join("") + timersOf(laid).map(drawTimer).join("")
  const width = Math.ceil(laid.width)
  const height = Math.ceil(laid.height)

  return `<svg xmlns="${SVG_NS}" class="sb-map__svg" data-map-svg="true" ` +
    `width="${width}" height="${height}" viewBox="0 0 ${width} ${height}" ` +
    `aria-hidden="true" focusable="false">` +
    `<defs><marker id="sb-map-arrow" viewBox="0 0 10 10" refX="10" refY="5" ` +
    `markerWidth="7" markerHeight="7" orient="auto-start-reverse">` +
    `<path d="M0 0 L10 5 L0 10 z" style="fill: var(--sb-map-edge, #64748b)"/></marker></defs>` +
    nodes + edges + gaps +
    `</svg>`
}

// The pane drawn in place of a map that could not be laid out.
export function renderError(reason) {
  const message = reason && reason.message ? reason.message : String(reason)

  return `<div class="sb-map__error" data-map-error="true">` +
    `<p class="sb-map__error-title">The map could not be drawn.</p>` +
    `<p class="sb-map__error-reason">${escapeText(message)}</p>` +
    `<p class="sb-map__error-hint">The list has every step of this document.</p>` +
    `</div>`
}

// Lays `graph` out and draws the result, or the error pane, into `target`.
// Resolves to `{drawn: "map", laid}` with the laid-out graph it drew, or
// `{drawn: "error", laid: null}`, so a caller can tell which it drew and
// read the very positions it drew from. `editable` is `renderSvg`'s.
export async function drawMap(target, graph, {elk = elkInstance(), editable = false} = {}) {
  try {
    const laid = await layout(graph, elk)
    target.innerHTML = renderSvg(laid, {editable})
    return {drawn: "map", laid}
  } catch (reason) {
    target.innerHTML = renderError(reason)
    return {drawn: "error", laid: null}
  }
}

// What a click on the map asks the page to do, as `{event, payload}`, or
// null. Every event is one the host's list already sends, under the name the
// host gave it, with the payload the list sends it: a block's box selects it
// (`events.select`); a gap arms the insert right after its block
// (`events.insert`, as the row's "+"); an empty slot's marker arms the insert
// at the head of that slot (`events.insert` with the slot named). A page that
// cannot edit gets only the selection, and a gesture whose event the host
// named no name for asks nothing: this file has no event name of its own.
// `target` is any element with `closest` and `dataset`.
export function mapGesture(target, editable, events = {}) {
  const gesture = (event, payload) => (typeof event === "string" && event !== "" ? {event, payload} : null)

  const gap = target.closest("[data-map-gap]")
  if (gap) return editable ? gesture(events.insert, {"block-id": gap.dataset.mapGap}) : null

  const empty = target.closest("[data-map-kind=empty]")
  if (empty) {
    if (!editable || empty.dataset.mapParent === undefined) return null
    return gesture(events.insert, {"block-id": empty.dataset.mapParent, slot: empty.dataset.mapSlot})
  }

  const box = target.closest("[data-map-kind=block]")
  if (box) return gesture(events.select, {"block-id": box.dataset.mapNode})

  return null
}

// The host list's event names, as the host stamped them on the map's
// element: `data-select-event` and `data-insert-event`.
export function listEvents(el) {
  return {select: el.dataset.selectEvent, insert: el.dataset.insertEvent}
}

// `graph` with the selection mark taken off the one block node that carries
// it (`StatifierBlocks.Map.graph/2`'s `:selected`), and the id it was on, or
// null. A selection that moves hands the hook the same boxes, and this is
// what lets the hook see that.
export function unmarkSelected(graph) {
  let selected = null
  const walk = (node) => {
    if (node.selected === true) {
      selected = node.id
      delete node.selected
    }
    for (const child of node.children || []) walk(child)
  }
  const copy = structuredClone(graph)
  walk(copy)
  return {graph: copy, selected}
}

// Marks the box of the block the page has selected, and unmarks the rest.
export function markSelected(target, id) {
  for (const node of target.querySelectorAll("[data-map-kind=block]")) {
    node.classList.toggle("sb-map__block--selected", node.dataset.mapNode === id)
  }
}

// ------------------------------------------------------------------ hover
//
// The description region, on hover: pointing at anything the map draws
// shows that element's description where the region is read, and pointing
// away shows the region again - the selected block's description, or the
// document's when nothing is selected.
//
// Selection speaks, hover is silent. The region is the page's
// `aria-live="polite"` node, and only the server writes it, on a
// selection. A hover never touches it: the hovered description goes into
// the hover layer, a sibling of the region outside it, hidden from
// assistive technology, which the stylesheet stacks over the region while
// it is shown. So what is announced changes on a selection and never on a
// hover, and `aria-live` is never toggled.
//
// Every description was computed by the server (`StatifierBlocks.Map.Info`)
// and rendered into the page's hidden store, one entry per map id under
// `data-describes`, in the same markup the region draws. The hook finds the
// hover layer and the store by the ids the host stamps on its element,
// `data-info-hover` and `data-info-store`; a host that stamps neither gets
// no hover. This code only copies an entry into the layer and hides the
// layer again: it pushes nothing to the server, adds no command, and never
// changes what is selected. It listens on the document, so the map may be
// redrawn under it at any time.
//
// The region stays the list's: the map is `aria-hidden`, and a keyboard or
// a screen reader reaches every description by selecting a row, which the
// server renders into the region itself.

// The map id of the drawn element `target` belongs to, or null when it
// belongs to none. A connector or an interrupt edge carries its id in
// `data-map-edge`; a block, a slot's box or an empty slot's marker in
// `data-map-node`, on the group its rect, text and timer mark sit inside.
// A gap's "+" describes nothing of its own.
export function describedId(target) {
  if (!target || typeof target.closest !== "function") return null
  if (target.closest("[data-map-gap]")) return null

  const edge = target.closest("[data-map-edge]")
  if (edge) return edge.dataset.mapEdge

  const node = target.closest("[data-map-node]")
  if (node) return node.dataset.mapNode

  return null
}

// The store's entry for `id`, or null. Compared by value rather than by an
// attribute selector, because a map id carries `>` and `/`.
export function entryFor(store, id) {
  if (!store) return null
  for (const entry of store.children) {
    if (entry.dataset.describes === id) return entry
  }
  return null
}

// The show and the hide, over the hover layer and the store. `layer()` and
// `store()` are asked afresh on every call, since a patch may replace
// either. Neither touches the region.
//
// `show(id)` puts the entry for `id` into the layer, marks the layer with
// `data-map-hover` and unhides it. `restore()` hides the layer, empties it
// and drops the mark, whatever it showed; the region under it has kept
// whatever the server last wrote there, a selection made mid-hover
// included. An id with no entry restores instead.
export function hover(layer, store) {
  function restore() {
    const el = layer()
    if (!el) return
    el.hidden = true
    el.innerHTML = ""
    delete el.dataset.mapHover
  }

  function show(id) {
    const el = layer()
    const entry = id === null ? null : entryFor(store(), id)
    if (!el || !entry) return restore()
    if (el.dataset.mapHover === id && !el.hidden) return

    el.innerHTML = entry.innerHTML
    el.dataset.mapHover = id
    el.hidden = false
  }

  return {show, restore}
}

// The element the host names by `id` in the hook element's dataset, or
// null when it names none.
function named(doc, id) {
  return typeof id === "string" && id !== "" ? doc.getElementById(id) : null
}

// The LiveView hook. The graph arrives JSON-encoded in `data-graph` on the
// hook's element, the selected block's id as the graph's own `selected`
// mark (or, lacking one, in `data-selected`), and whether the page can edit
// in `data-editable`; the drawing goes into the child marked
// `data-map-canvas` (which the page keeps out of LiveView's patching) or,
// lacking one, into the element itself.
//
// An element with no `data-map-canvas` child is not supported. LiveView
// patches the element itself, so a drawing written into it can be taken
// away by the next patch, and the re-mark of a moved selection and the kept
// error pane below both assume the drawing is still there. The hook still
// draws into the element, as it always has, and says so once per mount with
// a `console.warn` naming the missing child. `map_region/1` always renders
// the child.
//
// A patch that changes only the selection re-marks the drawing rather than
// laying it out again, and one carrying the same unparsable graph as the last
// leaves the error pane as it stands. A layout still running when a newer
// graph arrives is dropped when it lands, so a slow layout never draws over a
// newer one.
//
// A click becomes the event `mapGesture` names, under the host list's own
// name for it, sent through the page's own handlers. After an insert armed
// from the map, the next patch scrolls the element the host names in
// `data-insert-reveal` (a selector; none by default) into view, since the
// insert the list opened may sit below the map. The map is hidden from
// assistive technology; the list and the panel are the keyboard path to
// every one of these gestures but the insert into an empty slot.
//
// A pointer arriving over any element the map draws shows that element's
// description in the hover layer; one arriving over nothing the map draws,
// or leaving the window, hides the layer again (see "Hover" above).
export const StatifierBlocksMap = {
  mounted() {
    const doc = this.el.ownerDocument
    if (doc) {
      this.hover = hover(
        () => named(doc, this.el.dataset.infoHover),
        () => named(doc, this.el.dataset.infoStore),
      )
      this.onOver = (event) => this.hover.show(describedId(event.target))
      this.onOut = (event) => {
        if (!event.relatedTarget) this.hover.restore()
      }
      doc.addEventListener("mouseover", this.onOver)
      doc.addEventListener("mouseout", this.onOut)
    }
    this.el.addEventListener("click", (event) => {
      const events = listEvents(this.el)
      const gesture = mapGesture(event.target, this.el.dataset.editable === "true", events)
      if (!gesture) return
      if (gesture.event === events.insert) this.revealInsert = true
      this.pushEvent(gesture.event, gesture.payload)
    })
    return this.draw()
  },

  updated() {
    const drawn = this.draw()
    const reveal = this.el.dataset.insertReveal
    if (this.revealInsert && reveal) {
      const opened = document.querySelector(reveal)
      if (opened) {
        this.revealInsert = false
        opened.scrollIntoView({block: "nearest"})
      }
    }
    return drawn
  },

  destroyed() {
    const doc = this.el.ownerDocument
    if (doc && this.onOver) {
      doc.removeEventListener("mouseover", this.onOver)
      doc.removeEventListener("mouseout", this.onOut)
    }
  },

  // Resolves once whatever this call started has been drawn, so a caller
  // outside the browser can wait for it; LiveView ignores it.
  draw() {
    const canvas = this.el.querySelector("[data-map-canvas]")
    if (!canvas && !this.warnedNoCanvas) {
      this.warnedNoCanvas = true
      console.warn(
        "StatifierBlocksMap: the hook's element has no [data-map-canvas] child, " +
          "so the map is drawn into the element itself, which LiveView patches; " +
          "this is not supported. map_region/1 renders the child.",
      )
    }
    const target = canvas || this.el
    const editable = this.el.dataset.editable === "true"
    const text = this.el.dataset.graph
    let parsed

    // Text that is not JSON is kept as the source under its own prefix, which
    // no parsed graph's source carries, so the same text on a later patch
    // leaves the error pane standing and anything else draws.
    try {
      parsed = JSON.parse(text)
    } catch (reason) {
      const unparsable = `unparsable|${text}`
      if (unparsable === this.source) return Promise.resolve({drawn: "kept", laid: null})
      this.source = unparsable
      this.drawn = (this.drawn || 0) + 1
      target.innerHTML = renderError(reason)
      return Promise.resolve({drawn: "error", laid: null})
    }

    const {graph, selected} = unmarkSelected(parsed)
    const source = `${editable}|${JSON.stringify(graph)}`
    this.selected = selected || this.el.dataset.selected || null

    if (source === this.source) {
      markSelected(target, this.selected)
      return Promise.resolve({drawn: "marked", laid: null})
    }

    this.source = source
    const token = (this.drawn = (this.drawn || 0) + 1)
    const staging = {innerHTML: ""}

    return drawMap(staging, graph, {editable}).then((result) => {
      if (token !== this.drawn) return {drawn: "dropped", laid: null}
      target.innerHTML = staging.innerHTML
      markSelected(target, this.selected)
      return result
    })
  },
}

export default {StatifierBlocksMap}
