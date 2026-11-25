.pragma library

// Shared helpers for the Quickpanel weather widget. Location format matches
// omarchy-weather-location / ~/.local/state/omarchy/settings/weather.json.

function parseLocationFile(raw) {
  var unset = { name: "", latitude: null, longitude: null }
  try {
    var data = JSON.parse(String(raw || ""))
    if (!data || typeof data !== "object") return unset
    var latitude = parseFloat(data.latitude)
    var longitude = parseFloat(data.longitude)
    var hasCoordinates = !isNaN(latitude) && !isNaN(longitude)
    return {
      name: typeof data.name === "string" ? data.name.replace(/^\s+|\s+$/g, "") : "",
      latitude: hasCoordinates ? latitude : null,
      longitude: hasCoordinates ? longitude : null
    }
  } catch (e) {
    return unset
  }
}

function isAutoLocation(state) {
  var s = state || {}
  return String(s.name || "") === "" && (s.latitude === null || s.latitude === undefined)
}

function effectiveLocation(configured, detected) {
  return isAutoLocation(configured) && detected ? detected : (configured || { name: "", latitude: null, longitude: null })
}

// Location id at ~1 km precision ("" when unset). A forecast is only
// shown while its key matches the current location.
function locationKey(loc) {
  var l = loc || {}
  if (l.latitude === null || l.latitude === undefined || l.latitude === "") return ""
  if (l.longitude === null || l.longitude === undefined || l.longitude === "") return ""
  var lat = parseFloat(String(l.latitude))
  var lon = parseFloat(String(l.longitude))
  if (isNaN(lat) || isNaN(lon)) return ""
  return lat.toFixed(2) + "," + lon.toFixed(2)
}

function roundedTemp(value) {
  if (value === undefined || value === null || value === "") return ""
  var n = parseFloat(String(value))
  return isNaN(n) ? "" : String(Math.round(n))
}

function celsiusToFahrenheit(value) {
  if (value === undefined || value === null || value === "") return ""
  var n = parseFloat(String(value))
  return isNaN(n) ? "" : (n * 9 / 5) + 32
}

function localeUsesImperial(localeName) {
  var name = String(localeName || "").replace(".", "_")
  return /^en[_-]US($|[_.-])/.test(name) || /^en[_-]LR($|[_.-])/.test(name) || /^my($|[_.-])/.test(name)
}

function countryUsesImperial(countryName) {
  var country = String(countryName || "")
    .replace(/^\s+|\s+$/g, "")
    .replace(/[._-]+/g, " ")
    .toLowerCase()
  if (!country) return null
  if (country === "us" || country === "usa" || country === "united states" || country === "united states of america") return true
  if (country === "liberia" || country === "myanmar" || country === "burma") return true
  return false
}

function shouldUseImperial(localeName, countryName) {
  var countryPreference = countryUsesImperial(countryName)
  if (countryPreference !== null) return countryPreference
  return localeUsesImperial(localeName)
}

function formatTemp(celsius, useImperial) {
  if (celsius === undefined || celsius === null || celsius === "") return ""
  var value = useImperial ? celsiusToFahrenheit(celsius) : celsius
  var rounded = roundedTemp(value)
  if (!rounded) return ""
  return rounded + "°" + (useImperial ? "F" : "C")
}

function bareDegree(celsius, useImperial) {
  if (celsius === undefined || celsius === null || celsius === "") return ""
  var value = useImperial ? celsiusToFahrenheit(celsius) : celsius
  var rounded = roundedTemp(value)
  return rounded ? rounded + "°" : ""
}

function iconForOpenMeteoCode(code, night) {
  var c = parseInt(String(code || "0"), 10)
  if (c === 0) return night ? "" : ""
  if (c === 1 || c === 2) return night ? "" : ""
  if (c === 3) return ""
  if (c === 45 || c === 48) return night ? "\ue346" : "\ue313"
  if (c === 51 || c === 53 || c === 55 || c === 56 || c === 57 || c === 61) return ""
  if (c === 63 || c === 65 || c === 66 || c === 67 || c === 80 || c === 81 || c === 82) return ""
  if (c === 71 || c === 73 || c === 75 || c === 77 || c === 85 || c === 86) return ""
  if (c === 95 || c === 96 || c === 99) return ""
  return ""
}

function conditionForOpenMeteoCode(code) {
  var c = parseInt(String(code || "0"), 10)
  if (c === 0) return "Clear"
  if (c === 1) return "Mostly clear"
  if (c === 2) return "Partly cloudy"
  if (c === 3) return "Overcast"
  if (c === 45 || c === 48) return "Fog"
  if (c === 51 || c === 53 || c === 55) return "Drizzle"
  if (c === 56 || c === 57) return "Freezing drizzle"
  if (c === 61) return "Light rain"
  if (c === 63) return "Rain"
  if (c === 65) return "Heavy rain"
  if (c === 66 || c === 67) return "Freezing rain"
  if (c === 71 || c === 73) return "Snow"
  if (c === 75 || c === 77) return "Heavy snow"
  if (c === 80 || c === 81 || c === 82) return "Showers"
  if (c === 85 || c === 86) return "Snow showers"
  if (c === 95) return "Thunderstorm"
  if (c === 96 || c === 99) return "Thunderstorm"
  return "Cloudy"
}

function todayIndex(daily) {
  if (!daily || !daily.time || !daily.time.length) return -1
  var today = isoDate(new Date())
  for (var i = 0; i < daily.time.length; i++) {
    if (String(daily.time[i]).slice(0, 10) === today) return i
  }
  return 0
}

function isoDate(d) {
  var y = d.getFullYear()
  var m = d.getMonth() + 1
  var day = d.getDate()
  return y + "-" + (m < 10 ? "0" : "") + m + "-" + (day < 10 ? "0" : "") + day
}

function parseForecast(raw) {
  try {
    return JSON.parse(String(raw || ""))
  } catch (e) {
    return null
  }
}
