.pragma library

function parseConfig(raw) {
  try {
    var data = JSON.parse(String(raw || "{}"))
    if (!data || typeof data !== "object")
      return { pins: [], widgets: [], edge: "right" }
    return {
      pins: normalizePins(data.pins),
      widgets: normalizeWidgets(data.widgets),
      edge: normalizeEdge(data.edge)
    }
  } catch (e) {
    return { pins: [], widgets: [], edge: "right" }
  }
}

// Like parseConfig, but reports whether the text was a readable config
// object. Callers must not save over a file that failed to parse (a hand
// edit in progress or a partial write) or the user's pins would be lost.
function parseConfigResult(raw) {
  var text = String(raw || "")
  if (text.trim() === "") text = "{}"
  var data
  try {
    data = JSON.parse(text)
  } catch (e) {
    return { ok: false, hasWidgets: false, pins: [], widgets: [], edge: "right" }
  }
  if (!data || typeof data !== "object" || Array.isArray(data))
    return { ok: false, hasWidgets: false, pins: [], widgets: [], edge: "right" }
  return {
    ok: true,
    hasWidgets: Object.prototype.hasOwnProperty.call(data, "widgets"),
    pins: normalizePins(data.pins),
    widgets: normalizeWidgets(data.widgets),
    edge: normalizeEdge(data.edge)
  }
}

function normalizeEdge(edge) {
  var e = String(edge || "right").trim().toLowerCase()
  if (e === "left" || e === "bottom" || e === "right") return e
  return "right"
}

function cloneSnapshot(pins, widgets, edge) {
  return {
    pins: normalizePins(pins),
    widgets: normalizeWidgets(widgets),
    edge: normalizeEdge(edge)
  }
}

function normalizePins(pins) {
  var list = Array.isArray(pins) ? pins : []
  var out = []
  var seen = {}
  for (var i = 0; i < list.length; i++) {
    var id = String(list[i] || "").trim()
    if (!id || seen[id]) continue
    seen[id] = true
    out.push(id)
  }
  return out
}

function normalizeWidgets(widgets) {
  var list = Array.isArray(widgets) ? widgets : []
  var out = []
  var seen = {}
  var autoSlot = 0
  for (var i = 0; i < list.length; i++) {
    var entry = list[i]
    var id = ""
    var span = 1
    var slot = -1
    if (typeof entry === "string") {
      id = String(entry || "").trim()
    } else if (entry && typeof entry === "object") {
      id = String(entry.id || "").trim()
      var rawSpan = Number(entry.span)
      // span 0 / missing → widget default (clock is taller).
      if (!rawSpan || rawSpan < 1) span = defaultSpanFor(id)
      else span = Math.max(1, Math.round(rawSpan))
      if (entry.slot !== undefined && entry.slot !== null && entry.slot !== "")
        slot = Math.max(0, Math.round(Number(entry.slot)))
    }
    if (!id || seen[id]) continue
    seen[id] = true
    if (slot < 0) {
      slot = autoSlot
      autoSlot += span
    } else {
      autoSlot = Math.max(autoSlot, slot + span)
    }
    out.push({ id: id, span: span, slot: slot })
  }
  return out
}

function serializeConfig(pins, widgets, edge) {
  return JSON.stringify({
    pins: normalizePins(pins),
    widgets: normalizeWidgets(widgets),
    edge: normalizeEdge(edge)
  }, null, 2) + "\n"
}

function movePin(pins, fromIndex, toIndex) {
  var next = normalizePins(pins)
  if (fromIndex < 0 || fromIndex >= next.length) return next
  if (toIndex < 0) toIndex = 0
  if (toIndex >= next.length) toIndex = next.length - 1
  if (fromIndex === toIndex) return next
  var item = next.splice(fromIndex, 1)[0]
  next.splice(toIndex, 0, item)
  return next
}

function withPin(pins, id) {
  var key = String(id || "").trim()
  if (!key) return Array.isArray(pins) ? pins.slice() : []
  var next = Array.isArray(pins) ? pins.slice() : []
  if (next.indexOf(key) >= 0) return next
  next.push(key)
  return next
}

function withoutPin(pins, id) {
  var key = String(id || "").trim()
  var list = Array.isArray(pins) ? pins : []
  if (!key) return list.slice()
  return list.filter(function (item) { return item !== key })
}

function isPinned(pins, id) {
  var key = String(id || "").trim()
  if (!key || !Array.isArray(pins)) return false
  return pins.indexOf(key) >= 0
}

function withWidget(widgets, id, span, slot) {
  var key = String(id || "").trim()
  if (!key) return normalizeWidgets(widgets)
  var next = normalizeWidgets(widgets)
  for (var i = 0; i < next.length; i++) {
    if (next[i].id === key) return next
  }
  var useSpan = Math.max(1, Math.round(Number(span) || 1))
  var useSlot = slot === undefined || slot === null || slot === ""
    ? nextSlot(next)
    : Math.max(0, Math.round(Number(slot)))
  next.push({ id: key, span: useSpan, slot: useSlot })
  return next
}

function packWidgetSlots(widgets) {
  var next = normalizeWidgets(widgets)
  // Sort by current slot so visual order survives, then pack tightly from 0.
  next.sort(function (a, b) {
    return (Number(a.slot) || 0) - (Number(b.slot) || 0)
  })
  var cursor = 0
  for (var i = 0; i < next.length; i++) {
    next[i] = { id: next[i].id, span: next[i].span, slot: cursor }
    cursor += next[i].span
  }
  return next
}

function withoutWidget(widgets, id) {
  var key = String(id || "").trim()
  var next = normalizeWidgets(widgets)
  if (!key) return next
  next = next.filter(function (item) { return item.id !== key })
  // Repack so the bottom packed Row and side emptyTail stay aligned with slots.
  return packWidgetSlots(next)
}

function nextSlot(widgets) {
  var list = normalizeWidgets(widgets)
  var max = 0
  for (var i = 0; i < list.length; i++) {
    max = Math.max(max, list[i].slot + list[i].span)
  }
  return max
}

function widgetAtSlot(widgets, slot) {
  var list = normalizeWidgets(widgets)
  var s = Math.max(0, Math.round(Number(slot) || 0))
  for (var i = 0; i < list.length; i++) {
    var w = list[i]
    if (s >= w.slot && s < w.slot + w.span) return w
  }
  return null
}

function rangesOverlap(aSlot, aSpan, bSlot, bSpan) {
  return aSlot < bSlot + bSpan && bSlot < aSlot + aSpan
}

// After a move, shove any overlapping widgets to the first free slot.
function resolveOverlaps(widgets, keepId) {
  var next = normalizeWidgets(widgets)
  var guard = 0
  while (guard++ < next.length * next.length) {
    var conflict = -1
    var keeper = -1
    for (var i = 0; i < next.length; i++) {
      for (var j = i + 1; j < next.length; j++) {
        if (!rangesOverlap(next[i].slot, next[i].span, next[j].slot, next[j].span))
          continue
        // Prefer keeping the widget the user just placed.
        if (keepId && next[i].id === keepId) { keeper = i; conflict = j }
        else if (keepId && next[j].id === keepId) { keeper = j; conflict = i }
        else { keeper = i; conflict = j }
        break
      }
      if (conflict >= 0) break
    }
    if (conflict < 0) break
    var kept = next[keeper]
    next[conflict] = {
      id: next[conflict].id,
      span: next[conflict].span,
      slot: kept.slot + kept.span
    }
  }
  return next
}

// Move a widget so its start row is toSlot. Dropping on another widget swaps
// start slots; dropping on an empty cell places there. Overlaps are resolved.
function placeWidget(widgets, id, toSlot) {
  var key = String(id || "").trim()
  var next = normalizeWidgets(widgets)
  if (!key) return next
  var target = Math.max(0, Math.round(Number(toSlot) || 0))
  var idx = -1
  for (var i = 0; i < next.length; i++) {
    if (next[i].id === key) { idx = i; break }
  }
  if (idx < 0) return next

  var moving = next[idx]
  // Dropping onto a cell we already occupy is a no-op.
  if (target >= moving.slot && target < moving.slot + moving.span)
    return next

  var occupant = null
  var occIdx = -1
  for (var j = 0; j < next.length; j++) {
    if (j === idx) continue
    var w = next[j]
    if (target >= w.slot && target < w.slot + w.span) {
      occupant = w
      occIdx = j
      break
    }
  }

  if (occupant) {
    var fromSlot = moving.slot
    next[idx] = { id: moving.id, span: moving.span, slot: target }
    next[occIdx] = { id: occupant.id, span: occupant.span, slot: fromSlot }
  } else {
    next[idx] = { id: moving.id, span: moving.span, slot: target }
  }
  return resolveOverlaps(next, key)
}

// List reorder for the bottom packed strip — keeps slots tight from 0.
function moveWidget(widgets, fromIndex, toIndex) {
  var next = normalizeWidgets(widgets)
  // Sort by slot first so fromIndex matches the visual Row order.
  next.sort(function (a, b) {
    return (Number(a.slot) || 0) - (Number(b.slot) || 0)
  })
  if (fromIndex < 0 || fromIndex >= next.length) return next
  if (toIndex < 0) toIndex = 0
  if (toIndex >= next.length) toIndex = next.length - 1
  if (fromIndex === toIndex) return next
  var item = next.splice(fromIndex, 1)[0]
  next.splice(toIndex, 0, item)
  // Pack in the post-splice array order. Do not call packWidgetSlots here —
  // that re-sorts by the still-stale slot values and undoes the reorder.
  var cursor = 0
  for (var i = 0; i < next.length; i++) {
    next[i] = { id: next[i].id, span: next[i].span, slot: cursor }
    cursor += next[i].span
  }
  return next
}

function knownWidgetIds() {
  return ["Weather", "AnalogueClock", "SpcxStock", "SystemGauges"]
}

function defaultWidgets() {
  return [
    { id: "Weather", span: 1, slot: 0 },
    { id: "AnalogueClock", span: 2, slot: 1 }
  ]
}

function defaultSpanFor(id) {
  switch (String(id || "")) {
    case "AnalogueClock": return 2
    case "SpcxStock": return 2
    case "SystemGauges": return 1
    case "Weather": return 1
    default: return 1
  }
}
