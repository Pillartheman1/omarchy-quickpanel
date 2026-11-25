import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "SpcxStockModel.js" as Model

// Live SPCX (SpaceX) quote — price, day change, sparkline. Span 2 by default.
Item {
  id: root

  property var service: null
  property bool active: false

  property var quote: null
  property var sparkPoints: []
  property string status: "idle" // idle | loading | ready | error
  property string errorText: ""
  property int retryBudget: 0
  property double lastQuoteAt: 0
  property double lastChartAt: 0

  readonly property string ticker: "SPCX"
  readonly property string company: quote && quote.shortName ? quote.shortName : "SpaceX"
  readonly property string priceText: quote ? Model.formatPrice(quote.price) : "—"
  readonly property string changeText: {
    if (!quote) return ""
    return Model.formatSigned(quote.change) + "  (" + Model.formatSignedPct(quote.changePct) + ")"
  }
  readonly property string direction: quote ? Model.changeDirection(quote.change) : "flat"
  readonly property color changeColor: {
    if (direction === "up") return Color.accent
    if (direction === "down") return Color.urgent
    return Color.muted
  }
  readonly property string marketText: quote ? String(quote.marketLabel || "") : ""
  readonly property string rangeText: {
    if (!quote) return ""
    var high = Model.formatPrice(quote.dayHigh)
    var low = Model.formatPrice(quote.dayLow)
    var highLabel = service && service.strings ? service.strings.t("spcxHigh") : "H"
    var lowLabel = service && service.strings ? service.strings.t("spcxLow") : "L"
    return highLabel + " " + high + "  " + lowLabel + " " + low
  }
  readonly property string volumeText: {
    if (!quote || !quote.volume) return ""
    var label = service && service.strings ? service.strings.t("spcxVolume") : "Vol"
    return label + " " + quote.volume
  }
  readonly property string sessionLine: {
    if (!quote || !quote.usingExtended) return ""
    var closeLabel = service && service.strings ? service.strings.t("spcxSessionClose") : "Close"
    return closeLabel + " " + Model.formatPrice(quote.sessionPrice)
      + "  " + Model.formatSigned(quote.sessionChange)
      + " (" + Model.formatSignedPct(quote.sessionChangePct) + ")"
  }
  readonly property string paletteKey: [
    String(Color.accent),
    String(Color.urgent),
    String(Color.muted),
    String(Color.popups.text),
    String(Color.popups.border),
    String(Color.popups.background)
  ].join("|")

  width: parent ? parent.width : Style.space(280)
  height: parent && parent.height > 0 ? parent.height : implicitHeight
  implicitHeight: Style.space(200)

  onActiveChanged: {
    if (active) {
      refresh(false)
    } else {
      retryTimer.stop()
    }
  }

  onPaletteKeyChanged: spark.requestPaint()
  onSparkPointsChanged: spark.requestPaint()
  onDirectionChanged: spark.requestPaint()

  function refresh(force) {
    if (status !== "ready") status = "loading"
    fetchQuote(force)
    // Sparkline changes slowly — refresh far less often than the quote.
    fetchChart(force === true)
  }

  function fetchQuote(force) {
    if (quoteProc.running) return
    var now = Date.now()
    if (!force && root.quote && (now - root.lastQuoteAt) < 45 * 1000) return
    var url = "https://quote.cnbc.com/quote-html-webservice/restQuote/symbolType/symbol"
      + "?symbols=SPCX&requestMethod=itv&noform=1&partnerId=2&fund=1&exthrs=1&output=json&events=1"
    quoteProc.command = [
      "curl", "-fsS", "--max-time", "6",
      "-A", "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36",
      "-H", "Accept: application/json",
      url
    ]
    quoteProc.running = true
    root.lastQuoteAt = now
  }

  function fetchChart(force) {
    if (chartProc.running) return
    var now = Date.now()
    // Chart every 5 minutes unless forced (manual refresh).
    if (!force && root.sparkPoints && root.sparkPoints.length > 1
        && (now - root.lastChartAt) < 5 * 60 * 1000) return
    var url = "https://api.nasdaq.com/api/quote/SPCX/chart?assetclass=stocks"
    chartProc.command = [
      "curl", "-fsS", "--max-time", "6",
      "-A", "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36",
      "-H", "Accept: application/json",
      url
    ]
    chartProc.running = true
    root.lastChartAt = now
  }

  function scheduleRetry() {
    if (retryBudget >= 3) {
      if (!quote) {
        status = "error"
        errorText = service && service.strings
          ? service.strings.t("spcxUnavailable")
          : "Quote unavailable"
      }
      return
    }
    retryBudget++
    retryTimer.restart()
  }

  Process {
    id: quoteProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = Model.parseCnbcQuote(String(text || ""))
        if (parsed && isFinite(parsed.price)) {
          root.quote = parsed
          root.status = "ready"
          root.errorText = ""
          root.retryBudget = 0
        } else {
          root.scheduleRetry()
        }
      }
    }
  }

  Process {
    id: chartProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var points = Model.parseNasdaqChart(String(text || ""))
        if (points && points.length > 1)
          root.sparkPoints = points
      }
    }
  }

  Timer {
    id: retryTimer
    interval: 3000
    onTriggered: root.refresh(true)
  }

  Timer {
    id: refreshTimer
    interval: 60 * 1000
    running: root.active
    repeat: true
    onTriggered: root.refresh(false)
  }

  BorderSurface {
    id: card
    anchors.fill: parent
    radius: Style.cornerRadius
    color: Util.alpha(Color.popups.background, 0.45)
    borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(1)))

    // Header
    Column {
      id: headerCol
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Style.spacing.md
      spacing: Style.spacing.xs

      Row {
        width: parent.width
        spacing: Style.spacing.sm

        Column {
          width: Math.max(0, parent.width - marketBadge.width - parent.spacing)
          spacing: Style.spacing.xxs

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.ticker
            color: Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true
            elide: Text.ElideRight
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.company
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        Text {
          id: marketBadge
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: {
            if (root.status === "loading" && !root.quote)
              return service && service.strings ? service.strings.t("spcxLoading") : "…"
            return root.marketText
          }
          color: Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: {
          if (root.status === "error" && !root.quote) return root.errorText
          if (root.status === "loading" && !root.quote)
            return service && service.strings ? service.strings.t("spcxLoading") : "Loading…"
          return root.priceText
        }
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.font.heading
        font.bold: true
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        visible: root.status === "ready" && root.changeText.length > 0
        textFormat: Text.PlainText
        text: root.changeText
        color: root.changeColor
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        visible: root.sessionLine.length > 0
        textFormat: Text.PlainText
        text: root.sessionLine
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    // Footer: day range + volume
    Row {
      id: footerRow
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.margins: Style.spacing.md
      spacing: Style.spacing.md

      Text {
        width: Math.max(0, (parent.width - parent.spacing) * 0.58)
        visible: root.rangeText.length > 0
        textFormat: Text.PlainText
        text: root.rangeText
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      Text {
        width: Math.max(0, (parent.width - parent.spacing) * 0.42)
        visible: root.volumeText.length > 0
        textFormat: Text.PlainText
        text: root.volumeText
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideLeft
      }
    }

    // Sparkline fills the band between header and footer.
    Item {
      id: sparkHost
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: headerCol.bottom
      anchors.bottom: footerRow.top
      anchors.leftMargin: Style.spacing.md
      anchors.rightMargin: Style.spacing.md
      anchors.topMargin: Style.spacing.sm
      anchors.bottomMargin: Style.spacing.sm

      Canvas {
        id: spark
        anchors.fill: parent
        antialiasing: true
        renderStrategy: Canvas.Cooperative

        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          var pts = root.sparkPoints || []
          var w = width
          var h = height
          if (w < 8 || h < 8 || pts.length < 2) return

          var min = pts[0]
          var max = pts[0]
          for (var i = 1; i < pts.length; i++) {
            if (pts[i] < min) min = pts[i]
            if (pts[i] > max) max = pts[i]
          }
          var pad = Math.max((max - min) * 0.08, 0.05)
          min -= pad
          max += pad
          var span = max - min
          if (span <= 0) span = 1

          var stroke = root.changeColor
          var fill = Util.alpha(stroke, 0.18)
          var baseline = Util.alpha(Color.muted, 0.35)

          ctx.beginPath()
          ctx.moveTo(0, h - 0.5)
          ctx.lineTo(w, h - 0.5)
          ctx.strokeStyle = baseline
          ctx.lineWidth = 1
          ctx.stroke()

          function xAt(idx) {
            return idx * (w - 2) / (pts.length - 1) + 1
          }
          function yAt(val) {
            return 1 + (1 - (val - min) / span) * (h - 3)
          }

          ctx.beginPath()
          ctx.moveTo(xAt(0), yAt(pts[0]))
          for (var j = 1; j < pts.length; j++)
            ctx.lineTo(xAt(j), yAt(pts[j]))
          ctx.lineTo(xAt(pts.length - 1), h - 1)
          ctx.lineTo(xAt(0), h - 1)
          ctx.closePath()
          ctx.fillStyle = fill
          ctx.fill()

          ctx.beginPath()
          ctx.moveTo(xAt(0), yAt(pts[0]))
          for (var k = 1; k < pts.length; k++)
            ctx.lineTo(xAt(k), yAt(pts[k]))
          ctx.strokeStyle = stroke
          ctx.lineWidth = Math.max(1.5, Style.space(2))
          ctx.lineJoin = "round"
          ctx.lineCap = "round"
          ctx.stroke()
        }
      }
    }
  }

  Accessible.role: Accessible.Indicator
  Accessible.name: {
    var title = service && service.strings ? service.strings.t("spcxStock") : "SPCX"
    if (status === "ready")
      return title + ", " + priceText + ", " + changeText + ", " + marketText
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
