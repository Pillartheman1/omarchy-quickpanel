.pragma library

// Helpers for the SPCX (SpaceX) live quote widget.
// Quote: CNBC public quote webservice. Sparkline: Nasdaq chart API.

function parseMoney(raw) {
  if (raw === undefined || raw === null || raw === "") return NaN
  var s = String(raw).replace(/[$,+\s]/g, "").replace(/,/g, "")
  var n = parseFloat(s)
  return isNaN(n) ? NaN : n
}

function parsePercent(raw) {
  if (raw === undefined || raw === null || raw === "") return NaN
  var s = String(raw).replace(/[%+\s]/g, "").replace(/,/g, "")
  var n = parseFloat(s)
  return isNaN(n) ? NaN : n
}

function formatPrice(value, digits) {
  if (!isFinite(value)) return "—"
  var d = digits === undefined || digits === null ? 2 : digits
  return "$" + Number(value).toFixed(d)
}

function formatSigned(value, digits) {
  if (!isFinite(value)) return "—"
  var d = digits === undefined || digits === null ? 2 : digits
  var sign = value > 0 ? "+" : ""
  return sign + Number(value).toFixed(d)
}

function formatSignedPct(value) {
  if (!isFinite(value)) return "—"
  var sign = value > 0 ? "+" : ""
  return sign + Number(value).toFixed(2) + "%"
}

function formatVolume(raw) {
  if (raw === undefined || raw === null || raw === "") return ""
  var s = String(raw).replace(/^\s+|\s+$/g, "")
  if (!s) return ""
  // Prefer compact forms already provided (e.g. "84.8M").
  if (/[KMBT]$/i.test(s.replace(/,/g, ""))) return s.replace(/,/g, "")
  var n = parseFloat(s.replace(/,/g, ""))
  if (isNaN(n)) return s
  if (n >= 1e12) return (n / 1e12).toFixed(2) + "T"
  if (n >= 1e9) return (n / 1e9).toFixed(2) + "B"
  if (n >= 1e6) return (n / 1e6).toFixed(1) + "M"
  if (n >= 1e3) return (n / 1e3).toFixed(1) + "K"
  return String(Math.round(n))
}

function marketLabel(status) {
  var s = String(status || "").toUpperCase()
  if (s === "REG_MKT" || s === "OPEN") return "Open"
  if (s === "PRE_MKT" || s === "PRE") return "Pre-market"
  if (s === "POST_MKT" || s === "POST" || s === "AFTER") return "After-hours"
  if (s === "CLOSED" || s === "CLOSE") return "Closed"
  if (s.indexOf("PRE") >= 0) return "Pre-market"
  if (s.indexOf("POST") >= 0 || s.indexOf("AFTER") >= 0) return "After-hours"
  if (s.indexOf("OPEN") >= 0 || s.indexOf("REG") >= 0) return "Open"
  if (s) return s
  return "—"
}

function parseCnbcQuote(raw) {
  try {
    var data = JSON.parse(String(raw || ""))
    var list = data
      && data.FormattedQuoteResult
      && data.FormattedQuoteResult.FormattedQuote
    if (!list || !list.length) return null
    var q = list[0]
    if (!q || String(q.symbol || "").toUpperCase() !== "SPCX") return null

    var sessionPrice = parseMoney(q.last)
    var sessionChange = parseMoney(q.change)
    var sessionChangePct = parsePercent(q.change_pct)
    var prevClose = parseMoney(q.previous_day_closing)
    var dayHigh = parseMoney(q.high)
    var dayLow = parseMoney(q.low)
    var dayOpen = parseMoney(q.open)
    var volume = formatVolume(q.volume_alt || q.volume)
    var status = String(q.curmktstatus || "")
    var sessionTime = String(q.last_timedate || "")

    var ext = q.ExtendedMktQuote && typeof q.ExtendedMktQuote === "object"
      ? q.ExtendedMktQuote
      : null
    var hasExt = !!(ext && isFinite(parseMoney(ext.last)))
    var extPrice = hasExt ? parseMoney(ext.last) : NaN
    var extChange = hasExt ? parseMoney(ext.change) : NaN
    var extChangePct = hasExt ? parsePercent(ext.change_pct) : NaN
    var extTime = hasExt ? String(ext.last_timedate || "") : ""
    var extVolume = hasExt ? formatVolume(ext.volume_alt || ext.volume) : ""

    var useExt = hasExt && (status === "POST_MKT" || status === "PRE_MKT"
      || String(ext.type || "").indexOf("MKT") >= 0)

    return {
      symbol: "SPCX",
      name: String(q.name || "Space Exploration Technologies Corp"),
      shortName: "SpaceX",
      status: status,
      marketLabel: marketLabel(status),
      // Display price prefers extended when the session is pre/post.
      price: useExt ? extPrice : sessionPrice,
      change: useExt ? extChange : sessionChange,
      changePct: useExt ? extChangePct : sessionChangePct,
      timeLabel: useExt && extTime ? extTime : sessionTime,
      sessionPrice: sessionPrice,
      sessionChange: sessionChange,
      sessionChangePct: sessionChangePct,
      prevClose: prevClose,
      dayHigh: dayHigh,
      dayLow: dayLow,
      dayOpen: dayOpen,
      volume: volume,
      extPrice: extPrice,
      extChange: extChange,
      extChangePct: extChangePct,
      extVolume: extVolume,
      usingExtended: useExt
    }
  } catch (e) {
    return null
  }
}

function parseNasdaqChart(raw) {
  try {
    var data = JSON.parse(String(raw || ""))
    var payload = data && data.data
    if (!payload || !Array.isArray(payload.chart)) return []
    var points = []
    for (var i = 0; i < payload.chart.length; i++) {
      var row = payload.chart[i]
      if (!row) continue
      var y = Number(row.y)
      if (!isFinite(y)) continue
      points.push(y)
    }
    return downsample(points, 48)
  } catch (e) {
    return []
  }
}

function downsample(points, maxPoints) {
  var list = Array.isArray(points) ? points : []
  var max = Math.max(2, Math.round(Number(maxPoints) || 48))
  if (list.length <= max) return list.slice()
  var out = []
  var last = list.length - 1
  for (var i = 0; i < max; i++) {
    var idx = Math.round(i * last / (max - 1))
    out.push(list[idx])
  }
  return out
}

function changeDirection(change) {
  if (!isFinite(change) || change === 0) return "flat"
  return change > 0 ? "up" : "down"
}
