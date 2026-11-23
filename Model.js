.pragma library

function parseConfig(raw) {
  try {
    var data = JSON.parse(String(raw || "{}"))
    if (!data || typeof data !== "object") return { pins: [] }
    var pins = Array.isArray(data.pins) ? data.pins : []
    var out = []
    var seen = {}
    for (var i = 0; i < pins.length; i++) {
      var id = String(pins[i] || "").trim()
      if (!id || seen[id]) continue
      seen[id] = true
      out.push(id)
    }
    return { pins: out }
  } catch (e) {
    return { pins: [] }
  }
}

function serializeConfig(pins) {
  var list = Array.isArray(pins) ? pins : []
  var out = []
  var seen = {}
  for (var i = 0; i < list.length; i++) {
    var id = String(list[i] || "").trim()
    if (!id || seen[id]) continue
    seen[id] = true
    out.push(id)
  }
  return JSON.stringify({ pins: out }, null, 2) + "\n"
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
