import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "WeatherModel.js" as Model

// Current conditions + today's high/low. Location follows Omarchy's shared
// weather.json (omarchy-weather-location); forecast from Open-Meteo.
Item {
  id: root

  property var service: null
  // Idle until the grid binds active (keepLoaded mounts must not fetch early).
  property bool active: false
  property double lastFetchAt: 0
  readonly property int minFetchMs: 60 * 1000

  property var configuredLocation: ({ name: "", latitude: null, longitude: null })
  property var detectedLocation: ({ name: "", latitude: null, longitude: null })
  property var forecast: null
  property string status: "idle" // idle | loading | ready | error
  property string errorText: ""
  property int retryBudget: 0
  // Location the shown forecast / the running request belong to.
  property string forecastKey: ""
  property string inflightKey: ""

  readonly property var location: Model.effectiveLocation(configuredLocation, detectedLocation)
  readonly property bool autoLocation: Model.isAutoLocation(configuredLocation)
  readonly property string locationKey: Model.locationKey(location)
  readonly property bool hasCoordinates: {
    var lat = parseFloat(String(location.latitude))
    var lon = parseFloat(String(location.longitude))
    return !isNaN(lat) && !isNaN(lon)
  }
  readonly property string placeName: String(location.name || "")
  readonly property string countryHint: detectedLocation && detectedLocation.country
    ? String(detectedLocation.country)
    : ""
  readonly property bool useImperial: Model.shouldUseImperial(Qt.locale().name, countryHint)

  readonly property var current: forecast && forecast.current ? forecast.current : null
  readonly property int dayIndex: Model.todayIndex(forecast ? forecast.daily : null)
  readonly property real highC: {
    if (!forecast || !forecast.daily || dayIndex < 0) return NaN
    var vals = forecast.daily.temperature_2m_max
    return vals && vals[dayIndex] !== undefined ? Number(vals[dayIndex]) : NaN
  }
  readonly property real lowC: {
    if (!forecast || !forecast.daily || dayIndex < 0) return NaN
    var vals = forecast.daily.temperature_2m_min
    return vals && vals[dayIndex] !== undefined ? Number(vals[dayIndex]) : NaN
  }

  readonly property string iconGlyph: current
    ? Model.iconForOpenMeteoCode(current.weather_code, Number(current.is_day) === 0)
    : ""
  readonly property string conditionText: current
    ? Model.conditionForOpenMeteoCode(current.weather_code)
    : ""
  readonly property string tempText: current
    ? Model.formatTemp(current.temperature_2m, useImperial)
    : ""
  readonly property string highText: isFinite(highC) ? Model.bareDegree(highC, useImperial) : ""
  readonly property string lowText: isFinite(lowC) ? Model.bareDegree(lowC, useImperial) : ""
  readonly property string rangeText: {
    if (!highText && !lowText) return ""
    var highLabel = service && service.strings ? service.strings.t("weatherHigh") : "H"
    var lowLabel = service && service.strings ? service.strings.t("weatherLow") : "L"
    return highLabel + " " + highText + "  " + lowLabel + " " + lowText
  }

  width: parent ? parent.width : Style.space(280)
  // Fill the grid cell in both orientations (bottom strip shares strip height).
  height: parent && parent.height > 0 ? parent.height : implicitHeight
  implicitHeight: card.implicitHeight

  onActiveChanged: {
    if (active) {
      refresh(false)
    } else {
      retryTimer.stop()
    }
  }

  onHasCoordinatesChanged: {
    if (active && hasCoordinates) fetchForecast(false)
  }

  onLocationKeyChanged: {
    // Never show another place's forecast under the new place name.
    if (root.forecast && root.forecastKey !== root.locationKey) {
      root.forecast = null
      root.forecastKey = ""
      if (root.locationKey) root.status = "loading"
    }
    if (active && hasCoordinates) fetchForecast(false)
  }

  function refresh(force) {
    locationFile.reload()
    if (autoLocation) detectLocation()
    else if (hasCoordinates) fetchForecast(force)
    else {
      status = "error"
      errorText = service && service.strings
        ? service.strings.t("weatherNoLocation")
        : "No location"
    }
  }

  function detectLocation() {
    if (geoProc.running) return
    if (status !== "ready") status = "loading"
    geoProc.running = true
  }

  function fetchForecast(force) {
    if (!active || !hasCoordinates) return
    // A running request for an old location is dropped and re-run on finish.
    if (forecastProc.running) return
    var key = root.locationKey
    var now = Date.now()
    if (!force && root.forecast && root.forecastKey === key
        && (now - root.lastFetchAt) < root.minFetchMs)
      return
    var lat = parseFloat(String(location.latitude))
    var lon = parseFloat(String(location.longitude))
    var url = "https://api.open-meteo.com/v1/forecast"
      + "?latitude=" + encodeURIComponent(String(lat))
      + "&longitude=" + encodeURIComponent(String(lon))
      + "&daily=weather_code,temperature_2m_max,temperature_2m_min"
      + "&current=temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code,is_day"
      + "&forecast_days=1"
      + "&timezone=auto"
    if (status !== "ready") status = "loading"
    forecastProc.command = ["curl", "-fsS", "--max-time", "5", url]
    root.inflightKey = key
    forecastProc.running = true
    root.lastFetchAt = now
  }

  function scheduleRetry() {
    if (retryBudget >= 3) {
      if (!forecast) {
        status = "error"
        errorText = service && service.strings
          ? service.strings.t("weatherUnavailable")
          : "Weather unavailable"
      }
      return
    }
    retryBudget++
    retryTimer.restart()
  }

  FileView {
    id: locationFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/settings/weather.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      root.configuredLocation = Model.parseLocationFile(text())
      if (!root.active) return
      if (root.autoLocation) root.detectLocation()
      else if (root.hasCoordinates) root.fetchForecast(false)
    }
    onLoadFailed: {
      root.configuredLocation = Model.parseLocationFile("")
      if (root.active) root.detectLocation()
    }
  }

  Process {
    id: geoProc
    command: ["curl", "-fsS", "--max-time", "4", "https://geo.omarchy.org/"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var body = String(text || "")
        var parsed = Model.parseLocationFile(body)
        try {
          var raw = JSON.parse(body || "{}")
          if (raw && raw.country) parsed.country = String(raw.country)
        } catch (e) {}
        if (parsed.latitude !== null && parsed.longitude !== null) {
          root.detectedLocation = parsed
          root.fetchForecast()
        } else if (!root.forecast) {
          root.status = "error"
          root.errorText = root.service && root.service.strings
            ? root.service.strings.t("weatherUnavailable")
            : "Weather unavailable"
        }
      }
    }
  }

  Process {
    id: forecastProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var key = root.inflightKey
        root.inflightKey = ""
        if (key !== root.locationKey) {
          // Location changed while this ran: discard and fetch the new one.
          Qt.callLater(function() { root.fetchForecast(true) })
          return
        }
        var parsed = Model.parseForecast(String(text || ""))
        if (parsed && parsed.current) {
          root.forecast = parsed
          root.forecastKey = key
          root.status = "ready"
          root.errorText = ""
          root.retryBudget = 0
        } else {
          root.scheduleRetry()
        }
      }
    }
  }

  Timer {
    id: retryTimer
    interval: 2500
    onTriggered: root.fetchForecast(true)
  }

  Timer {
    id: refreshTimer
    interval: 15 * 60 * 1000
    running: root.active
    repeat: true
    onTriggered: root.refresh(true)
  }

  BorderSurface {
    id: card
    width: parent.width
    height: parent.height > 0
      ? parent.height
      : (contentCol.implicitHeight + Style.spacing.md * 2)
    implicitHeight: contentCol.implicitHeight + Style.spacing.md * 2
    radius: Style.cornerRadius
    color: Util.alpha(Color.popups.background, 0.45)
    borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(1)))

    Column {
      id: contentCol
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.margins: Style.spacing.md
      spacing: Style.spacing.sm

      Row {
        width: parent.width
        spacing: Style.spacing.md

        Text {
          id: iconLabel
          textFormat: Text.PlainText
          text: root.status === "ready" ? root.iconGlyph : (root.status === "loading" ? "…" : "")
          color: Color.accent
          font.family: Style.font.family
          font.pixelSize: Style.font.display
          verticalAlignment: Text.AlignVCenter
          width: Style.space(40)
          height: Style.space(40)
        }

        Column {
          width: Math.max(0, parent.width - iconLabel.width - parent.spacing)
          spacing: Style.spacing.xxs
          anchors.verticalCenter: iconLabel.verticalCenter

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: {
              if (root.status === "ready" && root.tempText) return root.tempText
              if (root.status === "error") return root.errorText
              return service && service.strings ? service.strings.t("weatherLoading") : "Loading…"
            }
            color: Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            font.bold: true
            elide: Text.ElideRight
          }

          Text {
            width: parent.width
            visible: root.status === "ready" && root.conditionText.length > 0
            textFormat: Text.PlainText
            text: root.conditionText
            color: Color.popups.text
            opacity: 0.8
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }
        }
      }

      Text {
        width: parent.width
        visible: root.placeName.length > 0
        textFormat: Text.PlainText
        text: root.placeName
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        visible: root.status === "ready" && root.rangeText.length > 0
        textFormat: Text.PlainText
        text: root.rangeText
        color: Color.popups.text
        opacity: 0.75
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
      }
    }
  }

  Accessible.role: Accessible.Indicator
  Accessible.name: {
    var title = service && service.strings ? service.strings.t("weather") : "Weather"
    if (status === "ready")
      return title + ", " + tempText + ", " + conditionText + ", " + rangeText + ", " + placeName
    return title
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.MiddleButton | Qt.RightButton
    onClicked: function(mouse) {
      if (mouse.button === Qt.MiddleButton || mouse.button === Qt.RightButton)
        root.refresh(true)
    }
  }
}
