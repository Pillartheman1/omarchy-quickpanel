.pragma library

// Parse /proc/stat + /proc/meminfo for the SystemGauges widget.

function parseCpuLine(raw) {
  var text = String(raw || "")
  var line = ""
  var lines = text.split("\n")
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].indexOf("cpu ") === 0) {
      line = lines[i]
      break
    }
  }
  if (!line) return null
  var parts = line.replace(/\s+/g, " ").replace(/^\s+|\s+$/g, "").split(" ")
  if (parts.length < 5) return null
  var total = 0
  for (var j = 1; j < parts.length; j++) {
    var n = parseInt(parts[j], 10)
    if (isNaN(n)) continue
    total += n
  }
  // idle + iowait
  var idle = parseInt(parts[4], 10) || 0
  if (parts.length > 5) idle += parseInt(parts[5], 10) || 0
  return { total: total, idle: idle }
}

function cpuPercent(previous, current) {
  if (!previous || !current) return NaN
  var totalDelta = current.total - previous.total
  var idleDelta = current.idle - previous.idle
  if (totalDelta <= 0 || idleDelta < 0) return NaN
  var busy = 1 - (idleDelta / totalDelta)
  if (busy < 0) busy = 0
  if (busy > 1) busy = 1
  return busy * 100
}

function parseMeminfo(raw) {
  var text = String(raw || "")
  var total = NaN
  var available = NaN
  var lines = text.split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (line.indexOf("MemTotal:") === 0) {
      total = parseKb(line)
    } else if (line.indexOf("MemAvailable:") === 0) {
      available = parseKb(line)
    }
  }
  if (!isFinite(total) || total <= 0 || !isFinite(available)) return null
  var used = total - available
  if (used < 0) used = 0
  if (used > total) used = total
  return {
    totalKb: total,
    availableKb: available,
    usedKb: used,
    percent: (used / total) * 100
  }
}

function parseKb(line) {
  var parts = String(line || "").replace(/\s+/g, " ").split(" ")
  if (parts.length < 2) return NaN
  var n = parseInt(parts[1], 10)
  return isNaN(n) ? NaN : n
}

function clampPercent(value) {
  if (!isFinite(value)) return 0
  if (value < 0) return 0
  if (value > 100) return 100
  return value
}

function formatPercent(value) {
  if (!isFinite(value)) return "—"
  return Math.round(value) + "%"
}

function formatGib(kb) {
  if (!isFinite(kb) || kb < 0) return "—"
  var gib = kb / (1024 * 1024)
  if (gib >= 10) return gib.toFixed(0) + "G"
  return gib.toFixed(1) + "G"
}

function formatRamLabel(mem) {
  if (!mem) return ""
  return formatGib(mem.usedKb) + " / " + formatGib(mem.totalKb)
}
