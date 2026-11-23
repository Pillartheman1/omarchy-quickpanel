import QtQuick
import Quickshell
import Quickshell.Io

// Poll Hyprland cursor position. Flea's shelf rail owns the middle 60% of the
// right edge on the Overlay layer, so a HoverHandler alone cannot see the full
// ridge; compositor IPC still can.
Item {
  id: root

  property bool active: false
  property int intervalMs: 40

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

  Timer {
    interval: root.intervalMs
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
          if (isFinite(point.x) && isFinite(point.y)) root.moved(point.x, point.y)
        } catch (e) {}
      }
    }
  }

  onActiveChanged: {
    if (active) root.requestPos()
    else if (socket.connected) socket.connected = false
  }
}
