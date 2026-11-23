import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// One screen's quickpanel: right-edge hot strip below the top bar, and a
// sliding card with pinned apps. Edge enter uses Hyprland cursor polling so
// Flea's middle-edge rail cannot steal the dwell zone.
PanelWindow {
  id: window

  property var service: null

  Binding { target: window.contentItem; property: "LayoutMirroring.enabled"; value: Commons.I18n.rightToLeft }
  Binding { target: window.contentItem; property: "LayoutMirroring.childrenInherit"; value: true }

  readonly property var monitor: Hyprland.monitorFor(screen)
  readonly property var reserved: {
    var ipc = monitor && monitor.lastIpcObject ? monitor.lastIpcObject.reserved : null
    if (!ipc || ipc.length < 4) return [0, Style.bar.sizeHorizontal, 0, 0]
    return [ipc[0] || 0, ipc[1] || 0, ipc[2] || 0, ipc[3] || 0]
  }
  readonly property int topInset: Math.max(reserved[1], Style.bar.sizeHorizontal) + Style.spacing.xs
  readonly property int panelWidth: Style.space(340)
  readonly property int edgeDepth: Style.space(8)
  readonly property int outerGap: Style.gapsOut
  readonly property int dwellMs: 200
  readonly property int hideMs: 180

  property bool revealed: false
  property bool dwellArmed: false
  property bool grabReady: false
  property bool cursorOnEdge: false
  property bool cursorOnPanel: false

  readonly property bool pinnedOpen: !!(service && service.forceOpen)
  readonly property bool contentShown: revealed || pinnedOpen
  readonly property bool pointerInside: cursorOnEdge || cursorOnPanel || edgeHover.hovered || panelHover.hovered

  readonly property real screenX: screen ? screen.x : 0
  readonly property real screenY: screen ? screen.y : 0
  readonly property real screenW: screen ? screen.width : 0
  readonly property real screenH: screen ? screen.height : 0

  function dismiss() {
    window.revealed = false
    window.dwellArmed = false
    window.grabReady = false
    dwellTimer.stop()
    hideTimer.stop()
    grabTimer.stop()
  }

  function reveal() {
    window.revealed = true
    dwellTimer.stop()
    hideTimer.stop()
  }

  function closeFully() {
    if (service) service.close()
    else window.dismiss()
  }

  function requestHide() {
    if (window.pointerInside) return
    hideTimer.restart()
  }

  function onEdge(x, y) {
    if (!screen || screenW <= 0) return false
    var right = window.screenX + window.screenW
    var top = window.screenY + window.topInset
    var bottom = window.screenY + window.screenH
    return x >= right - window.edgeDepth && x <= right + 1 && y >= top && y <= bottom
  }

  function onPanel(x, y) {
    if (!screen || screenW <= 0 || !window.contentShown) return false
    var right = window.screenX + window.screenW
    var left = right - window.edgeDepth - window.panelWidth - window.outerGap
    var top = window.screenY + window.topInset
    var bottom = window.screenY + window.screenH - window.outerGap
    return x >= left && x <= right + 1 && y >= top && y <= bottom
  }

  function handleCursor(x, y) {
    var edge = window.onEdge(x, y)
    var panel = window.onPanel(x, y)
    window.cursorOnEdge = edge
    window.cursorOnPanel = panel

    if (!window.contentShown) {
      if (edge) {
        hideTimer.stop()
        if (!window.dwellArmed) {
          window.dwellArmed = true
          dwellTimer.restart()
        }
      } else {
        dwellTimer.stop()
        window.dwellArmed = false
      }
      return
    }

    // Open: leave the panel/edge to collapse, including keybind-opened state.
    if (edge || panel) hideTimer.stop()
    else window.requestHide()
  }

  visible: !remapGuard.remapping
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  exclusiveZone: 0
  WlrLayershell.namespace: "omarchy-quickpanel"
  // Overlay matches Flea's rail layer; cursor polling still owns the dwell.
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: window.contentShown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

  anchors { top: true; bottom: true; right: true }
  implicitWidth: window.panelWidth + window.outerGap + window.edgeDepth
  implicitHeight: 0

  mask: Region {
    item: edgeTrigger
    Region { item: window.contentShown ? slideHost : null }
  }

  Connections {
    target: window.service
    function onCursorXChanged() { window.handleCursor(window.service.cursorX, window.service.cursorY) }
    function onCursorYChanged() { window.handleCursor(window.service.cursorX, window.service.cursorY) }
  }

  Timer {
    id: dwellTimer
    interval: window.dwellMs
    onTriggered: {
      if (window.cursorOnEdge || edgeHover.hovered) window.reveal()
      window.dwellArmed = false
    }
  }

  Timer {
    id: hideTimer
    interval: window.hideMs
    onTriggered: {
      if (window.pointerInside) return
      window.closeFully()
    }
  }

  // Focus grab after open so Escape and click-outside work without the
  // pointer sitting on the card. Arming on the same tick as IPC open clears
  // immediately and used to hide the panel before it appeared.
  Timer {
    id: grabTimer
    interval: 100
    onTriggered: {
      if (!window.contentShown) return
      window.grabReady = true
      keyScope.forceActiveFocus()
    }
  }

  onContentShownChanged: {
    if (window.contentShown) {
      window.grabReady = false
      grabTimer.restart()
    } else {
      window.grabReady = false
      grabTimer.stop()
    }
  }

  onPinnedOpenChanged: {
    if (window.pinnedOpen) window.reveal()
    else if (!window.pointerInside) window.requestHide()
  }

  Item {
    id: edgeTrigger
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.top: parent.top
    anchors.topMargin: window.topInset
    width: window.edgeDepth
    z: 2

    HoverHandler {
      id: edgeHover
      onHoveredChanged: {
        if (hovered) {
          hideTimer.stop()
          window.cursorOnEdge = true
          if (window.contentShown) return
          window.dwellArmed = true
          dwellTimer.restart()
        } else {
          window.cursorOnEdge = false
          if (!window.cursorOnPanel && !panelHover.hovered) {
            dwellTimer.stop()
            window.dwellArmed = false
            window.requestHide()
          }
        }
      }
    }

    Rectangle {
      anchors.fill: parent
      color: Color.accent
      opacity: window.contentShown ? 0.85 : (window.dwellArmed || window.cursorOnEdge ? 0.7 : 0.35)
      Behavior on opacity {
        NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic }
      }
    }
  }

  Item {
    id: slideHost
    anchors.right: parent.right
    anchors.rightMargin: window.edgeDepth
    anchors.top: parent.top
    anchors.topMargin: window.topInset
    anchors.bottom: parent.bottom
    anchors.bottomMargin: window.outerGap
    width: window.panelWidth + window.outerGap
    clip: true
    z: 1

    BorderSurface {
      id: panelCard
      width: window.panelWidth
      height: parent.height
      x: window.contentShown ? 0 : width
      radius: Style.cornerRadius
      color: Util.alpha(Color.popups.background, 0.96)
      borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
      padding: Style.spacing.panelPadding

      Behavior on x {
        id: slideMotion
        NumberAnimation {
          duration: Style.duration(slideMotion.targetValue > 0 ? 120 : 180)
          easing.type: Easing.OutCubic
        }
      }

      HoverHandler {
        id: panelHover
        onHoveredChanged: {
          if (hovered) {
            hideTimer.stop()
            window.cursorOnPanel = true
          } else {
            window.cursorOnPanel = false
            if (!window.cursorOnEdge && !edgeHover.hovered) window.requestHide()
          }
        }
      }

      FocusScope {
        id: keyScope
        anchors.fill: parent
        anchors.margins: panelCard.padding
        focus: window.contentShown

        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            window.closeFully()
            event.accepted = true
          }
        }

        Column {
          anchors.fill: parent
          spacing: Style.spacing.md

          Row {
            width: parent.width
            spacing: Style.spacing.sm

            Text {
              textFormat: Text.PlainText
              text: service && service.strings ? service.strings.t("title") : "Quickpanel"
              color: Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width - addButton.width - parent.spacing
              anchors.verticalCenter: parent.verticalCenter
            }

            Button {
              id: addButton
              bordered: true
              foreground: Color.popups.text
              text: {
                if (!service || !service.strings) return appGrid.adding ? "Done" : "Add apps"
                return appGrid.adding ? service.strings.t("doneAdding") : service.strings.t("addApps")
              }
              onClicked: appGrid.adding = !appGrid.adding
            }
          }

          AppGrid {
            id: appGrid
            width: parent.width
            height: Math.max(0, parent.height - y)
            service: window.service
            visibleContent: window.contentShown
          }
        }
      }
    }
  }

  HyprlandFocusGrab {
    active: window.contentShown && window.grabReady
    windows: [window]
    onCleared: window.closeFully()
  }

  ScreenMoveRemap {
    id: remapGuard
    window: window
  }
}
