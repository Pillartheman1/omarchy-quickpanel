import QtQuick
import Quickshell
import Quickshell.Io

// Poll Hyprland cursor position for the active quickpanel edge (right/left/bottom).
Item {
  id: root

  property bool active: false
  property string edgeMode: "right" // right | left | bottom
  property real edgeCoord: 0
  // Near: dwell / leave-to-close. Far: closed and away from the hot edge.
  property int nearIntervalMs: 45
  property int farIntervalMs: 220
  property real proximityPx: 96
  // True while the panel is open or editing — keep fast polls + moved emits.
  property bool urgency: false

  property real lastX: -1
  property real lastY: -1
  // Emit one more moved after leaving proximity so dwell/hide can cancel.
  property bool lastNear: false

  readonly property string socketPath: Quickshell.env("XDG_RUNTIME_DIR") + "/hypr/"
    + Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") + "/.socket.sock"

  signal moved(real x, real y)

  function requestPos() {
    if (!socket.connected) {
      socket.connected = true
      return
    }
    socket.write("j/cursorpos")
    socket.flush()
  }

  function nearEdge(x, y) {
    if (!isFinite(root.edgeCoord)) return false
    if (root.edgeMode === "left")
      return x <= root.edgeCoord + root.proximityPx && x >= root.edgeCoord - 2
    if (root.edgeMode === "bottom")
      return y >= root.edgeCoord - root.proximityPx && y <= root.edgeCoord + 2
    // right
    return x >= root.edgeCoord - root.proximityPx && x <= root.edgeCoord + 2
  }

  function adaptInterval(x, y) {
    var near = root.urgency || root.nearEdge(x, y)
    var next = near ? root.nearIntervalMs : root.farIntervalMs
    if (poll.interval !== next) poll.interval = next
    return near
  }

  Timer {
    id: poll
    interval: root.farIntervalMs
    running: root.active
    repeat: true
    onTriggered: root.requestPos()
  }

  Socket {
    id: socket
    path: root.socketPath
    onConnectionStateChanged: if (connected) root.requestPos()
    onError: {}
    parser: SplitParser {
      splitMarker: "}"
      onRead: function(data) {
        if (!root.active) return
        try {
          var point = JSON.parse(data + "}")
          if (!isFinite(point.x) || !isFinite(point.y)) return
          if (point.x === root.lastX && point.y === root.lastY) {
            root.adaptInterval(point.x, point.y)
            return
          }
          root.lastX = point.x
          root.lastY = point.y
          // Closed + far: skip moved so desktop mouse moves do not pay for QML
          // hit tests. Still emit once on near→far so dwell/hide can cancel.
          var near = root.adaptInterval(point.x, point.y)
          if (near || root.lastNear)
            root.moved(point.x, point.y)
          root.lastNear = near
        } catch (e) {}
      }
    }
  }

  onActiveChanged: {
    if (active) {
      root.lastNear = false
      root.requestPos()
    } else if (socket.connected) {
      socket.connected = false
    }
  }

  onUrgencyChanged: {
    if (urgency) {
      poll.interval = root.nearIntervalMs
      root.lastNear = true
    }
  }
}
