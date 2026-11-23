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

  visible: !remapGuard.remapping
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  exclusiveZone: 0
  WlrLayershell.namespace: "omarchy-quickpanel"
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.keyboardFocus: window.contentShown ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

  anchors { top: true; bottom: true; right: true }
  implicitWidth: window.panelWidth + window.outerGap + window.edgeDepth
  implicitHeight: 0

  mask: Region {
    item: edgeTrigger
    Region { item: window.contentShown ? slideHost : null }
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
      Qt.callLater(function() {
        if (window.pinnedOpen) keyScope.forceActiveFocus()
      })
    } else if (!window.hoverKeep) {
      window.requestHide()
    }
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

    Rectangle {
      anchors.fill: parent
      color: Color.accent
      opacity: window.contentShown ? 0.85 : (window.dwellArmed ? 0.65 : 0.4)
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
      // Prefer an opaque enough fill so icons read on light wallpapers.
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

  ScreenMoveRemap {
    id: remapGuard
    window: window
  }
}
