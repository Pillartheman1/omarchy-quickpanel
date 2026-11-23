import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// One screen's quickpanel: thin right-edge hot strip below the top bar, and a
// sliding card that carries pinned apps.
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
  // Clear the top bar / control strip so the hot edge never sits under it.
  readonly property int topInset: Math.max(reserved[1], Style.bar.sizeHorizontal) + Style.spacing.xs

  readonly property int panelWidth: Style.space(340)
  readonly property int edgeDepth: Style.space(4) + Style.spacing.hairline
  readonly property int outerGap: Style.gapsOut
  readonly property int dwellMs: 200
  readonly property int hideMs: 150

  property bool revealed: false
  property bool dwellArmed: false
  readonly property bool pinnedOpen: !!(service && service.forceOpen)
  readonly property bool contentShown: revealed || pinnedOpen
  readonly property bool hoverKeep: edgeHover.hovered || panelHover.hovered

  function dismiss() {
    window.revealed = false
    window.dwellArmed = false
    dwellTimer.stop()
    hideTimer.stop()
  }

  function reveal() {
    window.revealed = true
    dwellTimer.stop()
    hideTimer.stop()
  }

  function requestHide() {
    if (window.pinnedOpen || window.hoverKeep) return
    hideTimer.restart()
  }

  visible: true
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  exclusiveZone: 0
  WlrLayershell.namespace: "omarchy-quickpanel"
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.keyboardFocus: window.contentShown ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

  anchors {
    top: true
    bottom: true
    right: true
  }

  implicitWidth: window.panelWidth + window.outerGap + window.edgeDepth
  implicitHeight: 0

  mask: Region {
    item: window.contentShown ? panelCard : null
    Region { item: edgeTrigger }
  }

  Timer {
    id: dwellTimer
    interval: window.dwellMs
    onTriggered: {
      if (edgeHover.hovered) window.reveal()
      window.dwellArmed = false
    }
  }

  Timer {
    id: hideTimer
    interval: window.hideMs
    onTriggered: {
      if (!window.pinnedOpen && !window.hoverKeep) window.revealed = false
    }
  }

  onPinnedOpenChanged: {
    if (window.pinnedOpen) {
      window.reveal()
      Qt.callLater(function() { if (window.pinnedOpen) keyScope.forceActiveFocus() })
    } else if (!window.hoverKeep) {
      window.requestHide()
    }
  }

  // Hot edge: right strip starting below the top bar.
  Item {
    id: edgeTrigger
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.top: parent.top
    anchors.topMargin: window.topInset
    width: window.edgeDepth

    HoverHandler {
      id: edgeHover
      onHoveredChanged: {
        if (hovered) {
          hideTimer.stop()
          if (window.contentShown) return
          window.dwellArmed = true
          dwellTimer.restart()
        } else {
          dwellTimer.stop()
          window.dwellArmed = false
          window.requestHide()
        }
      }
    }

    // Subtle teaching cue while the dwell is counting.
    Rectangle {
      anchors.fill: parent
      color: Color.accent
      opacity: window.dwellArmed && !window.contentShown ? 0.55 : 0
      Behavior on opacity {
        NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic }
      }
    }
  }

  BorderSurface {
    id: panelCard
    width: window.panelWidth
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.topMargin: window.topInset
    anchors.bottomMargin: window.outerGap
    anchors.right: parent.right
    anchors.rightMargin: window.outerGap - tuck

    property real tuck: window.contentShown ? 0 : window.panelWidth + window.outerGap

    Behavior on tuck {
      id: tuckMotion
      NumberAnimation {
        duration: Style.duration(tuckMotion.targetValue > 0 ? 120 : 180)
        easing.type: Easing.OutCubic
      }
    }

    opacity: window.contentShown || tuck < window.panelWidth ? 1 : 0
    radius: Style.cornerRadius
    color: Color.popups.background
    borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
    padding: Style.spacing.panelPadding

    HoverHandler {
      id: panelHover
      onHoveredChanged: {
        if (hovered) hideTimer.stop()
        else window.requestHide()
      }
    }

    FocusScope {
      id: keyScope
      anchors.fill: parent
      anchors.margins: panelCard.padding
      focus: window.contentShown

      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          if (service) service.close()
          else window.dismiss()
          event.accepted = true
        }
      }

      Column {
        id: body
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

  HyprlandFocusGrab {
    active: window.pinnedOpen && window.contentShown
    windows: [window]
    onCleared: {
      if (service) service.close()
      else window.dismiss()
    }
  }

  ScreenMoveRemap {
    window: window
  }
}
