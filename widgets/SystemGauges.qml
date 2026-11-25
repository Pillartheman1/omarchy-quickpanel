import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "SystemGaugesModel.js" as Model

// Unified CPU + RAM analogue gauges. Side edges: side-by-side. Bottom: stacked.
Item {
  id: root

  property var service: null
  property bool active: false
  // WidgetGrid sets this when the panel edge is bottom.
  property bool horizontal: false

  property var prevCpu: null
  property real cpuPercent: 0
  property real ramPercent: 0
  property string ramDetail: ""
  property bool ready: false

  property real cpuNeedle: 0
  property real ramNeedle: 0

  Behavior on cpuNeedle {
    NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic }
  }
  Behavior on ramNeedle {
    NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic }
  }

  readonly property string cpuLabel: service && service.strings
    ? service.strings.t("systemGaugesCpu") : "CPU"
  readonly property string ramLabel: service && service.strings
    ? service.strings.t("systemGaugesRam") : "RAM"
  readonly property string cpuText: ready ? Model.formatPercent(cpuPercent) : "—"
  readonly property string ramText: ready ? Model.formatPercent(ramPercent) : "—"

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
  implicitHeight: Style.space(100)

  // Bottom strip stacks CPU over RAM; left/right keep the original row.
  readonly property bool stackGauges: {
    if (root.horizontal) return true
    var edge = root.service ? String(root.service.activeEdge || "") : ""
    return edge === "bottom"
  }
  readonly property int gaugeGap: Style.spacing.sm
  // Cache Style.space for paint (avoid per-frame token lookups).
  readonly property real s1: Style.space(1)
  readonly property real s2: Style.space(2)
  readonly property real s3: Style.space(3)
  readonly property real s4: Style.space(4)
  readonly property real s5: Style.space(5)
  readonly property real s8: Style.space(8)

  onActiveChanged: {
    if (active) {
      prevCpu = null
      sample()
    }
  }

  onPaletteKeyChanged: {
    cpuFace.requestPaint()
    ramFace.requestPaint()
  }
  onCpuNeedleChanged: cpuFace.requestPaint()
  onRamNeedleChanged: ramFace.requestPaint()
  onStackGaugesChanged: {
    cpuFace.requestPaint()
    ramFace.requestPaint()
  }

  function sample() {
    if (!sampleProc.running) sampleProc.running = true
  }

  function applySample(raw) {
    var text = String(raw || "")
    var parts = text.split("\n---\n")
    var cpuRaw = parts[0] || ""
    var memRaw = parts.length > 1 ? parts[1] : ""

    var current = Model.parseCpuLine(cpuRaw)
    if (current) {
      var pct = Model.cpuPercent(root.prevCpu, current)
      root.prevCpu = current
      if (isFinite(pct)) {
        var nextCpu = Model.clampPercent(pct)
        if (Math.abs(nextCpu - root.cpuPercent) >= 0.4) {
          root.cpuPercent = nextCpu
          root.cpuNeedle = nextCpu
        }
        root.ready = true
      }
    }

    var mem = Model.parseMeminfo(memRaw)
    if (mem) {
      var nextRam = Model.clampPercent(mem.percent)
      if (Math.abs(nextRam - root.ramPercent) >= 0.3) {
        root.ramPercent = nextRam
        root.ramNeedle = nextRam
        root.ramDetail = Model.formatRamLabel(mem)
      } else if (!root.ramDetail) {
        root.ramDetail = Model.formatRamLabel(mem)
      }
      root.ready = true
    }
  }

  function paintGauge(ctx, w, h, value, hot) {
    ctx.reset()
    if (w < 8 || h < 8) return

    var cx = w / 2
    var cy = h * 0.72
    var r = Math.min(w * 0.44, h * 0.62)
    if (r < 8) return

    var track = Util.alpha(Color.muted, 0.4)
    var fill = hot ? Color.urgent : Color.accent
    var textCol = Color.popups.text
    var muted = Color.muted

    var start = Math.PI
    var sweep = Math.PI
    var frac = Model.clampPercent(value) / 100
    var thick = Math.max(3, Math.round(root.s4))

    function arcStroke(a0, a1, color, width) {
      ctx.beginPath()
      ctx.arc(cx, cy, r, a0, a1, false)
      ctx.strokeStyle = color
      ctx.lineWidth = width
      ctx.lineCap = "round"
      ctx.stroke()
    }

    arcStroke(start, start + sweep, track, thick)
    if (frac > 0.002)
      arcStroke(start, start + sweep * frac, fill, thick)

    for (var t = 0; t <= 2; t++) {
      var a = start + sweep * (t / 2)
      var outer = r - 1
      var inner = outer - root.s5
      ctx.beginPath()
      ctx.moveTo(cx + Math.cos(a) * inner, cy + Math.sin(a) * inner)
      ctx.lineTo(cx + Math.cos(a) * outer, cy + Math.sin(a) * outer)
      ctx.strokeStyle = Util.alpha(muted, 0.85)
      ctx.lineWidth = Math.max(1, root.s1)
      ctx.lineCap = "round"
      ctx.stroke()
    }

    var na = start + sweep * frac
    var tip = r - root.s8
    ctx.beginPath()
    ctx.moveTo(cx - Math.cos(na) * root.s5, cy - Math.sin(na) * root.s5)
    ctx.lineTo(cx + Math.cos(na) * tip, cy + Math.sin(na) * tip)
    ctx.strokeStyle = fill
    ctx.lineWidth = Math.max(2, root.s2)
    ctx.lineCap = "round"
    ctx.stroke()

    ctx.beginPath()
    ctx.arc(cx, cy, root.s3, 0, Math.PI * 2)
    ctx.fillStyle = fill
    ctx.fill()
    ctx.beginPath()
    ctx.arc(cx, cy, Math.max(1, root.s1), 0, Math.PI * 2)
    ctx.fillStyle = textCol
    ctx.fill()
  }

  Process {
    id: sampleProc
    // One fork per sample — avoid bash; head+cat via a tiny sh -c is enough.
    command: ["sh", "-c", "head -n1 /proc/stat; printf '\\n---\\n'; cat /proc/meminfo"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applySample(String(text || ""))
    }
  }

  Timer {
    interval: 2000
    running: root.active
    repeat: true
    triggeredOnStart: true
    onTriggered: root.sample()
  }

  BorderSurface {
    id: card
    anchors.fill: parent
    radius: Style.cornerRadius
    color: Util.alpha(Color.popups.background, 0.45)
    borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(1)))

    Item {
      id: gaugeHost
      anchors.fill: parent
      anchors.margins: Style.spacing.sm

      readonly property int cellW: root.stackGauges
        ? width
        : Math.max(0, Math.floor((width - root.gaugeGap) / 2))
      readonly property int cellH: root.stackGauges
        ? Math.max(0, Math.floor((height - root.gaugeGap) / 2))
        : height

      Item {
        id: cpuBlock
        x: 0
        y: 0
        width: gaugeHost.cellW
        height: gaugeHost.cellH

        Canvas {
          id: cpuFace
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.bottom: cpuMeta.top
          antialiasing: true
          renderStrategy: Canvas.Cooperative
          onWidthChanged: requestPaint()
          onHeightChanged: requestPaint()
          onPaint: root.paintGauge(getContext("2d"), width, height, root.cpuNeedle, root.cpuNeedle >= 85)
        }

        Column {
          id: cpuMeta
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          spacing: 0

          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
            text: root.cpuText
            color: root.cpuNeedle >= 85 ? Color.urgent : Color.popups.text
            font.family: Style.font.family
            font.pixelSize: root.stackGauges ? Style.font.caption : Style.font.body
            font.bold: true
          }
          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
            text: root.cpuLabel
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
      }

      Item {
        id: ramBlock
        x: root.stackGauges ? 0 : (gaugeHost.cellW + root.gaugeGap)
        y: root.stackGauges ? (gaugeHost.cellH + root.gaugeGap) : 0
        width: gaugeHost.cellW
        height: gaugeHost.cellH

        Canvas {
          id: ramFace
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.bottom: ramMeta.top
          antialiasing: true
          renderStrategy: Canvas.Cooperative
          onWidthChanged: requestPaint()
          onHeightChanged: requestPaint()
          onPaint: root.paintGauge(getContext("2d"), width, height, root.ramNeedle, root.ramNeedle >= 90)
        }

        Column {
          id: ramMeta
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          spacing: 0

          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
            text: root.ramText
            color: root.ramNeedle >= 90 ? Color.urgent : Color.popups.text
            font.family: Style.font.family
            font.pixelSize: root.stackGauges ? Style.font.caption : Style.font.body
            font.bold: true
          }
          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
            text: root.ramLabel + (root.ramDetail ? "  " + root.ramDetail : "")
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }
      }
    }
  }

  Accessible.role: Accessible.Indicator
  Accessible.name: {
    var title = service && service.strings ? service.strings.t("systemGauges") : "CPU and RAM"
    if (!ready) return title
    return title + ", CPU " + cpuText + ", RAM " + ramText
      + (ramDetail ? ", " + ramDetail : "")
  }
}
