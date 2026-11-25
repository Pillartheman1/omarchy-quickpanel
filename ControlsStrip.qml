import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.Pipewire
import Quickshell.Io
import qs.Commons
import qs.Ui

// Compact quick-settings row above the app grid. Left-click toggles; the
// matching bar panels already own the deep UI.
Item {
  id: root

  property var service: null
  property bool visibleContent: false
  property bool fillAvailable: false
  // Bottom paired column: grow tiles so the grid fills the shared height.
  property bool stretchTiles: false

  readonly property var adapter: Bluetooth.defaultAdapter
  readonly property bool btOn: !!(adapter && adapter.enabled)
  readonly property bool wifiOn: Networking.wifiEnabled === true
  readonly property bool wifiAvailable: Networking.backend === NetworkBackendType.NetworkManager

  readonly property var sink: Pipewire.defaultAudioSink
  readonly property var source: Pipewire.defaultAudioSource
  readonly property bool outputMuted: !!(sink && sink.audio && sink.audio.muted)
  readonly property bool inputMuted: !!(source && source.audio && source.audio.muted)
  readonly property bool hasOutput: !!(sink && sink.audio)
  readonly property bool hasInput: !!(source && source.audio)

  readonly property var trackedAudio: {
    var out = []
    if (sink) out.push(sink)
    if (source) out.push(source)
    return out
  }

  property bool nightlightOn: false
  property bool dndOn: false

  // Stable tile ids — state is read live in the delegate (avoids recreating
  // the Repeater model on every wifi/bt/mute change).
  readonly property var tileIds: ["wifi", "bt", "audio", "mic", "night", "dnd"]

  PwObjectTracker {
    objects: root.trackedAudio
  }

  function t(key, fallback) {
    if (service && service.strings) return service.strings.t(key)
    return fallback
  }

  function tileLabel(id) {
    switch (id) {
      case "wifi": return root.t("controlWifi", "Wi‑Fi")
      case "bt": return root.t("controlBluetooth", "Bluetooth")
      case "audio": return root.t("controlAudio", "Sound")
      case "mic": return root.t("controlMic", "Mic")
      case "night": return root.t("controlNightlight", "Night")
      case "dnd": return root.t("controlDnd", "Focus")
      default: return id
    }
  }

  function tileGlyph(id) {
    switch (id) {
      case "wifi": return root.wifiOn ? "󰖩" : "󰖪"
      case "bt": return root.btOn ? "󰂯" : "󰂲"
      case "audio": return root.outputMuted || !root.hasOutput ? "󰝟" : "󰕾"
      case "mic": return root.inputMuted || !root.hasInput ? "󰍭" : "󰍬"
      case "night": return "󰖔"
      case "dnd": return root.dndOn ? "󰂛" : "󰂚"
      default: return "?"
    }
  }

  function tileOn(id) {
    switch (id) {
      case "wifi": return root.wifiOn
      case "bt": return root.btOn
      case "audio": return root.hasOutput && !root.outputMuted
      case "mic": return root.hasInput && !root.inputMuted
      case "night": return root.nightlightOn
      case "dnd": return root.dndOn
      default: return false
    }
  }

  function tileEnabled(id) {
    switch (id) {
      case "wifi": return root.wifiAvailable
      case "bt": return !!root.adapter
      case "audio": return root.hasOutput
      case "mic": return root.hasInput
      case "night": return true
      case "dnd": return true
      default: return false
    }
  }

  function refreshFlags() {
    if (!root.visibleContent) return
    if (!nightlightProc.running) nightlightProc.running = true
    if (!dndProc.running) dndProc.running = true
  }

  function activate(id) {
    switch (id) {
      case "wifi":
        if (wifiAvailable) Networking.wifiEnabled = !Networking.wifiEnabled
        break
      case "bt":
        if (!adapter) break
        Quickshell.execDetached([
          "omarchy-bluetooth-power",
          adapter.enabled ? "off" : "on"
        ])
        break
      case "audio":
        if (hasOutput) sink.audio.muted = !sink.audio.muted
        break
      case "mic":
        if (hasInput) source.audio.muted = !source.audio.muted
        break
      case "night":
        Quickshell.execDetached(["omarchy", "toggle", "nightlight"])
        flagRefresh.restart()
        Qt.callLater(root.refreshFlags)
        break
      case "dnd":
        Quickshell.execDetached(["omarchy-shell", "notifications", "toggleDnd"])
        flagRefresh.restart()
        Qt.callLater(root.refreshFlags)
        break
    }
  }

  onVisibleContentChanged: {
    if (visibleContent) {
      refreshFlags()
      flagRefresh.restart()
    } else {
      flagRefresh.stop()
    }
  }

  Timer {
    id: flagRefresh
    // Night/DND flags change rarely — poll gently while the panel is open.
    interval: 5000
    running: false
    repeat: true
    onTriggered: root.refreshFlags()
  }

  Process {
    id: nightlightProc
    command: ["omarchy", "toggle", "nightlight", "--status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse(String(text || "{}"))
          root.nightlightOn = !!(data && data.enabled)
        } catch (e) {}
      }
    }
  }

  Process {
    id: dndProc
    command: ["omarchy-shell", "notifications", "isDnd"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var v = String(text || "").trim().toLowerCase()
        root.dndOn = v === "on" || v === "true" || v === "1"
      }
    }
  }

  // Bottom: 2-column stack with labels. Side: caption + 3-col.
  readonly property bool compact: root.fillAvailable
  readonly property int compactColumns: 2
  readonly property int compactRows: Math.ceil(root.tileIds.length / root.compactColumns)
  readonly property int baseTileH: root.compact ? Style.space(56) : Style.space(64)
  // Natural height ignores stretch so paired-column math does not feedback.
  readonly property int naturalHeight: root.compact
    ? (root.compactRows * root.baseTileH
      + Math.max(0, root.compactRows - 1) * Style.spacing.sm)
    : (controlsHeader.implicitHeight + Style.spacing.sm
      + Math.ceil(root.tileIds.length / 3) * root.baseTileH
      + Math.max(0, Math.ceil(root.tileIds.length / 3) - 1) * Style.spacing.sm)
  readonly property int tileH: {
    if (root.compact && root.stretchTiles && root.height > root.naturalHeight
        && root.compactRows > 0) {
      var gaps = Math.max(0, root.compactRows - 1) * Style.spacing.sm
      return Math.max(root.baseTileH, Math.floor((root.height - gaps) / root.compactRows))
    }
    return root.baseTileH
  }
  readonly property int tileMinW: root.compact ? Style.space(72) : Style.space(64)

  Text {
    id: controlsHeader
    width: parent.width
    visible: !root.compact
    height: visible ? implicitHeight : 0
    textFormat: Text.PlainText
    text: root.t("controls", "Controls")
    color: Color.popups.text
    opacity: 0.7
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }

  Grid {
    id: grid
    // Avoid anchors.*: undefined. Stretch mode fills top→bottom; otherwise
    // center when the root is taller than the natural tile grid.
    x: 0
    y: {
      if (!root.compact)
        return controlsHeader.height + Style.spacing.sm
      if (root.stretchTiles)
        return 0
      var h = root.naturalHeight
      return (h > 0 && root.height > h)
        ? Math.max(0, Math.round((root.height - h) / 2))
        : 0
    }
    width: parent.width
    columns: root.compact ? root.compactColumns : 3
    rowSpacing: Style.spacing.sm
    columnSpacing: Style.spacing.sm

    Repeater {
      model: root.tileIds

      delegate: Item {
        id: tile
        required property var modelData
        required property int index

        readonly property string tileId: String(modelData || "")
        readonly property bool active: root.tileOn(tileId)
        readonly property bool canUse: root.tileEnabled(tileId)

        width: Math.max(root.tileMinW,
          Math.floor((grid.width - grid.columnSpacing * (grid.columns - 1)) / grid.columns))
        height: root.tileH

        Rectangle {
          anchors.fill: parent
          radius: Style.cornerRadius
          color: {
            if (!tile.canUse) return Util.alpha(Color.muted, 0.08)
            if (tile.active) return Util.alpha(Color.accent, 0.22)
            return Util.alpha(Color.popups.text, 0.06)
          }
          border.width: Math.max(1, Style.spacing.hairline)
          border.color: tile.active
            ? Util.alpha(Color.accent, 0.7)
            : Util.alpha(Color.popups.border, 0.55)

          Behavior on color {
            ColorAnimation { duration: Style.duration(100) }
          }
        }

        Column {
          anchors.centerIn: parent
          spacing: Style.spacing.xxs
          width: parent.width - Style.spacing.sm

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            textFormat: Text.PlainText
            text: root.tileGlyph(tile.tileId)
            color: {
              if (!tile.canUse) return Util.alpha(Color.muted, 0.5)
              return tile.active ? Color.accent : Color.popups.text
            }
            font.family: Style.font.family
            font.pixelSize: Style.font.icon
          }

          Text {
            // Labels on both layouts.
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
            text: root.tileLabel(tile.tileId)
            color: tile.canUse ? Color.popups.text : Util.alpha(Color.muted, 0.6)
            opacity: tile.active ? 1 : 0.75
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        MouseArea {
          anchors.fill: parent
          enabled: tile.canUse
          cursorShape: tile.canUse ? Qt.PointingHandCursor : Qt.ArrowCursor
          onClicked: root.activate(tile.tileId)
        }

        Accessible.role: Accessible.Button
        Accessible.name: root.tileLabel(tile.tileId) + (tile.active ? ", on" : ", off")
        Accessible.onPressAction: root.activate(tile.tileId)
      }
    }
  }

  // Bottom: 2 columns × 3 rows. Side: full panel width.
  // implicitHeight stays at naturalHeight so stretch does not feedback into pairedH.
  implicitWidth: root.compact
    ? (root.compactColumns * root.tileMinW
      + Math.max(0, root.compactColumns - 1) * Style.spacing.sm)
    : Style.space(280)
  implicitHeight: root.naturalHeight
}
