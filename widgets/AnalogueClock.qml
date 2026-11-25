import QtQuick
import qs.Commons

// Analogue wall clock that follows the active Omarchy theme via Color / Style.
// Static dial is painted once; only the hands layer ticks every second.
Item {
  id: root

  property var service: null
  // Default false so keepLoaded mounts stay idle until the grid binds active.
  property bool active: false

  readonly property int faceSize: Style.space(168)
  property int dayKey: -1
  property string dateLabel: ""

  readonly property string paletteKey: [
    String(Color.accent),
    String(Color.muted),
    String(Color.popups.text),
    String(Color.popups.border),
    String(Color.popups.background)
  ].join("|")

  // Cache Style.space lookups used inside paint (avoid per-tick allocation).
  readonly property real s1: Style.space(1)
  readonly property real s2: Style.space(2)
  readonly property real s3: Style.space(3)
  readonly property real s4: Style.space(4)
  readonly property real s5: Style.space(5)
  readonly property real s8: Style.space(8)
  readonly property real s12: Style.space(12)

  width: parent ? parent.width : faceSize
  // Fill the grid cell in both orientations (bottom strip shares strip height).
  height: parent && parent.height > 0 ? parent.height : implicitHeight
  implicitHeight: faceSize + Style.spacing.md + dateText.implicitHeight

  function updateDateLabel(d) {
    var key = d.getFullYear() * 1000 + d.getMonth() * 40 + d.getDate()
    if (key === root.dayKey) return
    root.dayKey = key
    var weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    root.dateLabel = weekdays[d.getDay()] + " " + months[d.getMonth()] + " " + d.getDate()
  }

  onPaletteKeyChanged: {
    dial.requestPaint()
    hands.requestPaint()
  }

  onActiveChanged: {
    if (active) {
      tick.arm()
      dial.requestPaint()
      hands.requestPaint()
    } else {
      tick.stop()
    }
  }

  Timer {
    id: tick
    interval: 1000
    repeat: true
    running: false
    triggeredOnStart: true

    function arm() {
      var d = new Date()
      root.updateDateLabel(d)
      // Align to the next whole second so the second hand does not drift.
      interval = Math.max(50, 1000 - d.getMilliseconds())
      restart()
    }

    onTriggered: {
      if (interval !== 1000) interval = 1000
      root.updateDateLabel(new Date())
      hands.requestPaint()
    }
  }

  Column {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.verticalCenter: parent.verticalCenter
    width: parent.width
    spacing: Style.spacing.md

    Item {
      anchors.horizontalCenter: parent.horizontalCenter
      // Shrink the face slightly when the cell is shorter than the default.
      width: Math.min(root.faceSize, Math.max(Style.space(96), root.height - Style.space(36)))
      height: width

      // Dial + ticks — only when size or palette changes.
      Canvas {
        id: dial
        anchors.fill: parent
        antialiasing: true
        renderStrategy: Canvas.Cooperative
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          var size = Math.min(width, height)
          if (size < 8) return

          var cx = width / 2
          var cy = height / 2
          var r = size / 2
          var text = Color.popups.text
          var muted = Color.muted
          var border = Color.popups.border
          var fill = Util.alpha(Color.popups.background, 0.55)
          var s1 = root.s1
          var s2 = root.s2
          var s5 = root.s5
          var s8 = root.s8
          var s12 = root.s12

          ctx.beginPath()
          ctx.arc(cx, cy, r - s1, 0, Math.PI * 2)
          ctx.fillStyle = fill
          ctx.fill()

          ctx.beginPath()
          ctx.arc(cx, cy, r - s2, 0, Math.PI * 2)
          ctx.strokeStyle = border
          ctx.lineWidth = Math.max(1, s2)
          ctx.stroke()

          for (var i = 0; i < 60; i++) {
            var isHour = (i % 5) === 0
            var angle = (i / 60) * Math.PI * 2 - Math.PI / 2
            var outer = r - s8
            var inner = outer - (isHour ? s12 : s5)
            ctx.beginPath()
            ctx.moveTo(cx + Math.cos(angle) * inner, cy + Math.sin(angle) * inner)
            ctx.lineTo(cx + Math.cos(angle) * outer, cy + Math.sin(angle) * outer)
            ctx.strokeStyle = isHour ? text : Util.alpha(muted, 0.7)
            ctx.lineWidth = isHour ? Math.max(2, s2) : Math.max(1, s1)
            ctx.lineCap = "round"
            ctx.stroke()
          }
        }
      }

      // Hands only — every second while active.
      Canvas {
        id: hands
        anchors.fill: parent
        antialiasing: true
        renderStrategy: Canvas.Cooperative

        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          var size = Math.min(width, height)
          if (size < 8) return

          var cx = width / 2
          var cy = height / 2
          var r = size / 2
          var d = new Date()
          var hours = d.getHours() % 12
          var minutes = d.getMinutes()
          var seconds = d.getSeconds()

          var accent = Color.accent
          var text = Color.popups.text
          var s2 = root.s2
          var s3 = root.s3
          var s4 = root.s4
          var s8 = root.s8

          function hand(fraction, length, width, color) {
            var a = fraction * Math.PI * 2 - Math.PI / 2
            ctx.beginPath()
            ctx.moveTo(cx - Math.cos(a) * s8, cy - Math.sin(a) * s8)
            ctx.lineTo(cx + Math.cos(a) * length, cy + Math.sin(a) * length)
            ctx.strokeStyle = color
            ctx.lineWidth = width
            ctx.lineCap = "round"
            ctx.stroke()
          }

          var hourFrac = (hours + minutes / 60 + seconds / 3600) / 12
          var minuteFrac = (minutes + seconds / 60) / 60
          var secondFrac = seconds / 60

          hand(hourFrac, r * 0.48, Math.max(3, s3), text)
          hand(minuteFrac, r * 0.68, Math.max(2, s2), text)
          hand(secondFrac, r * 0.74, Math.max(1, root.s1), accent)

          var sa = secondFrac * Math.PI * 2 - Math.PI / 2
          ctx.beginPath()
          ctx.arc(cx + Math.cos(sa) * r * 0.74, cy + Math.sin(sa) * r * 0.74, s2, 0, Math.PI * 2)
          ctx.fillStyle = accent
          ctx.fill()

          ctx.beginPath()
          ctx.arc(cx, cy, s4, 0, Math.PI * 2)
          ctx.fillStyle = accent
          ctx.fill()
          ctx.beginPath()
          ctx.arc(cx, cy, s2, 0, Math.PI * 2)
          ctx.fillStyle = text
          ctx.fill()
        }
      }
    }

    Text {
      id: dateText
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: root.dateLabel
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }
  }

  Accessible.role: Accessible.Indicator
  Accessible.name: {
    if (service && service.strings)
      return service.strings.t("analogueClock") + ", " + root.dateLabel
    return "Analogue clock, " + root.dateLabel
  }
}
