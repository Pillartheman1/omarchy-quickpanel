import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// One screen's quickpanel on the configured edge (right / left / bottom).
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
  // Reserved bottom is often 0 even with a dock, hence the taller dwell band.
  // The window anchors to the output bottom and paints above the dock (Overlay).
  readonly property int bottomInset: Math.max(Number(reserved[3]) || 0, 0)
  readonly property int panelWidth: Style.space(340)
  // Side: fixed tall card. Bottom: hug the controls/apps paired height (no dead
  // band); compactBodyHeight grows it while Add apps is open.
  readonly property int bottomChromeBtnH: Style.space(32)
  readonly property int bottomPairedNaturalH: {
    var ctrlH = controlsStrip ? controlsStrip.naturalHeight : 0
    var appsH = appGrid
      ? (appGrid.compactBodyHeight + Style.spacing.xs + window.bottomChromeBtnH)
      : 0
    return Math.max(ctrlH, appsH, Style.space(120))
  }
  readonly property int panelHeight: {
    if (!window.isBottom) return Style.space(320)
    var pad = 2 * Style.spacing.panelPadding
    var place = window.editing ? (Style.spacing.xs + Style.space(32)) : 0
    return window.bottomPairedNaturalH + pad + place
  }
  readonly property int edgeDepth: Style.space(8)
  // Visible hot strip + HoverHandler target.
  readonly property int bottomEdgeDepth: Style.space(16)
  // Cursor-poll hit band (taller than the mask so dwell works over the dock).
  readonly property int bottomDwellBand: Style.space(72)
  readonly property int outerGap: Style.gapsOut
  readonly property int dwellMs: 200
  readonly property int hideMs: 180

  readonly property string edge: service ? String(service.activeEdge || "right") : "right"
  readonly property bool isBottom: edge === "bottom"
  readonly property bool isLeft: edge === "left"
  readonly property bool isRight: edge === "right"
  readonly property bool editing: !!(service && service.editing)

  // Global Y of the output bottom (minus reserved), where bottom dwell aims.
  readonly property real bottomEdgeY: window.screenY + window.screenH - window.bottomInset

  property bool revealed: false
  property bool dwellArmed: false
  property bool grabReady: false
  property bool cursorOnEdge: false
  property bool cursorOnPanel: false
  property bool pointerEnteredWhileOpen: false
  property double grabArmedAt: 0

  readonly property bool pinnedOpen: !!(service && service.forceOpen)
  readonly property bool contentShown: revealed || pinnedOpen
  readonly property bool pointerInside: cursorOnEdge || cursorOnPanel || edgeHover.hovered || panelHover.hovered

  readonly property real screenX: screen ? screen.x : 0
  readonly property real screenY: screen ? screen.y : 0
  readonly property real screenW: screen ? screen.width : 0
  readonly property real screenH: screen ? screen.height : 0

  function t(key, fallback) {
    if (service && service.strings) return service.strings.t(key)
    return fallback
  }

  function dismiss() {
    window.revealed = false
    window.dwellArmed = false
    window.grabReady = false
    window.pointerEnteredWhileOpen = false
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
    if (window.editing) return
    if (window.pinnedOpen && !window.pointerEnteredWhileOpen) return
    hideTimer.restart()
  }

  function onEdge(x, y) {
    if (!screen || screenW <= 0) return false
    var left = window.screenX
    var right = window.screenX + window.screenW
    var top = window.screenY + (window.isBottom ? 0 : window.topInset)
    var bottom = window.screenY + window.screenH
    if (window.isBottom) {
      var edgeY = window.bottomEdgeY
      return y >= edgeY - window.bottomDwellBand && y <= edgeY + 2
        && x >= left && x <= right + 1
    }
    if (window.isLeft) {
      return x >= left - 1 && x <= left + window.edgeDepth
        && y >= top && y <= bottom
    }
    return x >= right - window.edgeDepth && x <= right + 1
      && y >= top && y <= bottom
  }

  function onPanel(x, y) {
    if (!screen || screenW <= 0 || !window.contentShown) return false
    var left = window.screenX
    var right = window.screenX + window.screenW
    var top = window.screenY + window.topInset
    var bottom = window.screenY + window.screenH
    if (window.isBottom) {
      var edgeY = window.bottomEdgeY
      var stripTop = edgeY - window.bottomEdgeDepth - window.panelHeight - window.outerGap
      return y >= stripTop && y <= edgeY + 2 && x >= left && x <= right + 1
    }
    if (window.isLeft) {
      var stripRight = left + window.edgeDepth + window.panelWidth + window.outerGap
      return x >= left - 1 && x <= stripRight
        && y >= top && y <= bottom - window.outerGap
    }
    var stripLeft = right - window.edgeDepth - window.panelWidth - window.outerGap
    return x >= stripLeft && x <= right + 1
      && y >= top && y <= bottom - window.outerGap
  }

  function handleCursor(x, y) {
    var edgeHit = window.onEdge(x, y)
    var panelHit = window.contentShown ? window.onPanel(x, y) : false
    if (window.cursorOnEdge !== edgeHit) window.cursorOnEdge = edgeHit
    if (window.cursorOnPanel !== panelHit) window.cursorOnPanel = panelHit

    if (!window.contentShown) {
      if (edgeHit) {
        if (hideTimer.running) hideTimer.stop()
        if (!window.dwellArmed) {
          window.dwellArmed = true
          dwellTimer.restart()
        }
      } else if (window.dwellArmed) {
        dwellTimer.stop()
        window.dwellArmed = false
      }
      return
    }

    if (edgeHit || panelHit) {
      if (hideTimer.running) hideTimer.stop()
      window.pointerEnteredWhileOpen = true
    } else if (!hideTimer.running) {
      window.requestHide()
    }
  }

  visible: !remapGuard.remapping
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  exclusiveZone: 0
  WlrLayershell.namespace: "omarchy-quickpanel"
  WlrLayershell.layer: WlrLayer.Overlay
  // Exclusive focus on the open tick remaps the layer and blanks the panel;
  // take focus only after the pointer enters the open card.
  WlrLayershell.keyboardFocus: (window.contentShown && window.pointerEnteredWhileOpen)
    ? WlrKeyboardFocus.Exclusive
    : WlrKeyboardFocus.None



  anchors.top: !window.isBottom
  anchors.bottom: true
  anchors.left: window.isLeft || window.isBottom
  anchors.right: window.isRight || window.isBottom
  // PanelWindow uses margins.*, not anchors.bottomMargin.
  margins.bottom: window.isBottom ? window.bottomInset : 0
  implicitWidth: window.isBottom ? 0 : (window.panelWidth + window.outerGap + window.edgeDepth)
  implicitHeight: window.isBottom
    ? (window.panelHeight + window.outerGap + window.bottomEdgeDepth)
    : 0

  // Closed: edge strip only (click-through). Open: unmasked so the card paints.
  mask: window.contentShown ? null : edgeMask

  Region {
    id: edgeMask
    item: edgeTrigger
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
      if (window.pointerInside || window.editing) return
      window.closeFully()
    }
  }

  Timer {
    id: grabTimer
    interval: 280
    onTriggered: {
      if (!window.contentShown) return
      window.grabReady = true
      window.grabArmedAt = Date.now()
      keyScope.forceActiveFocus()
    }
  }

  onContentShownChanged: {
    if (window.contentShown) {
      window.grabReady = false
      window.pointerEnteredWhileOpen = window.pointerInside
      grabTimer.restart()
    } else {
      window.grabReady = false
      window.pointerEnteredWhileOpen = false
      grabTimer.stop()
    }
  }

  onPinnedOpenChanged: {
    if (window.pinnedOpen) {
      window.reveal()
      window.pointerEnteredWhileOpen = window.pointerInside
    } else if (!window.pointerInside) {
      window.requestHide()
    }
  }

  onEditingChanged: {
    if (window.editing) appGrid.adding = false
  }

  Item {
    id: edgeTrigger
    z: 2
    anchors.top: window.isBottom ? undefined : parent.top
    anchors.topMargin: window.isBottom ? 0 : window.topInset
    anchors.bottom: parent.bottom
    anchors.left: window.isRight ? undefined : parent.left
    anchors.right: window.isLeft ? undefined : parent.right
    width: window.isBottom ? undefined : window.edgeDepth
    height: window.isBottom ? window.bottomEdgeDepth : undefined

    HoverHandler {
      id: edgeHover
      onHoveredChanged: {
        if (hovered) {
          hideTimer.stop()
          window.cursorOnEdge = true
          if (window.contentShown) {
            window.pointerEnteredWhileOpen = true
            return
          }
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
  }

  Item {
    id: slideHost
    z: 1
    clip: true

    anchors.fill: parent
    anchors.topMargin: window.isBottom ? 0 : window.topInset
    anchors.bottomMargin: window.isBottom ? window.bottomEdgeDepth : window.outerGap
    anchors.leftMargin: window.isLeft ? window.edgeDepth
      : (window.isBottom ? window.outerGap : 0)
    anchors.rightMargin: window.isRight ? window.edgeDepth
      : (window.isBottom ? window.outerGap : 0)

    BorderSurface {
      id: panelCard
      // Explicit geometry only — no anchors on the slide axis.
      width: window.isBottom ? parent.width : window.panelWidth
      height: window.isBottom ? Math.min(window.panelHeight, parent.height) : parent.height
      // Slide targets. Wait for a laid-out parent so closedY never parks the
      // card below a 0-height clip.
      readonly property bool slideReady: parent && parent.height > 0 && width > 0 && height > 0
      readonly property real openX: window.isLeft ? 0 : Math.max(0, parent.width - width)
      readonly property real closedX: window.isLeft
        ? -(width + Style.space(2))
        : (parent.width + Style.space(2))
      readonly property real openY: Math.max(0, parent.height - height)
      readonly property real closedY: parent.height + Style.space(2)

      x: window.isBottom ? 0 : (window.contentShown ? openX : closedX)
      y: {
        if (!window.isBottom) return 0
        if (!slideReady) return 0
        return window.contentShown ? openY : closedY
      }

      radius: Style.cornerRadius
      color: Color.popups.background
      borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
      padding: Style.spacing.panelPadding
      clip: true
      visible: true
      opacity: window.contentShown ? 1 : 0

      Behavior on x {
        enabled: !window.isBottom && panelCard.slideReady
        NumberAnimation {
          id: slideAnimX
          duration: Style.duration(window.contentShown ? 180 : 120)
          easing.type: Easing.OutCubic
        }
      }
      // Bottom: no Behavior on y (it freezes the first closedY below the clip).

      HoverHandler {
        id: panelHover
        onHoveredChanged: {
          if (hovered) {
            hideTimer.stop()
            window.cursorOnPanel = true
            window.pointerEnteredWhileOpen = true
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
            if (window.editing && service) {
              service.cancelEdit()
              event.accepted = true
              return
            }
            window.closeFully()
            event.accepted = true
          }
        }

        Item {
          id: body
          anchors.fill: parent

          // Side edges: Add/Edit (+ placement) chrome only — no title headline.
          // Bottom: no chrome column; buttons sit under the apps grid.
          Item {
            id: sideChrome
            anchors.top: parent.top
            anchors.left: parent.left
            width: window.isBottom ? 0 : parent.width
            height: window.isBottom ? 0 : sideChromeCol.implicitHeight
            visible: !window.isBottom

            Column {
              id: sideChromeCol
              width: parent.width
              spacing: Style.spacing.sm

              Flow {
                width: parent.width
                spacing: Style.spacing.xs

                Button {
                  visible: !window.editing
                  bordered: true
                  foreground: Color.popups.text
                  text: appGrid.adding
                    ? window.t("doneAdding", "Done")
                    : window.t("addApps", "Add apps")
                  onClicked: appGrid.adding = !appGrid.adding
                }

                Button {
                  visible: !window.editing
                  bordered: true
                  foreground: Color.popups.text
                  text: window.t("edit", "Edit")
                  onClicked: if (service) service.beginEdit()
                }

                Button {
                  visible: window.editing
                  bordered: true
                  foreground: Color.popups.text
                  text: window.t("undo", "Undo")
                  onClicked: if (service) service.undoEdit()
                }

                Button {
                  visible: window.editing
                  bordered: true
                  foreground: Color.accent
                  text: window.t("done", "Done")
                  onClicked: if (service) service.doneEdit()
                }
              }

              Column {
                width: parent.width
                spacing: Style.spacing.xs
                visible: window.editing

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: window.t("placement", "Placement")
                  color: Color.muted
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }

                Flow {
                  width: parent.width
                  spacing: Style.spacing.xs

                  Button {
                    bordered: true
                    foreground: (service && service.draftEdge === "left") ? Color.accent : Color.popups.text
                    text: window.t("edgeLeft", "Left")
                    onClicked: if (service) service.setDraftEdge("left")
                  }
                  Button {
                    bordered: true
                    foreground: (service && service.draftEdge === "right") ? Color.accent : Color.popups.text
                    text: window.t("edgeRight", "Right")
                    onClicked: if (service) service.setDraftEdge("right")
                  }
                  Button {
                    bordered: true
                    foreground: (service && service.draftEdge === "bottom") ? Color.accent : Color.popups.text
                    text: window.t("edgeBottom", "Bottom")
                    onClicked: if (service) service.setDraftEdge("bottom")
                  }
                }
              }
            }
          }

          // Bottom: controls | apps+buttons | widgets.
          // Side: chrome → controls → apps → widgets (stacked).
          // Explicit x/y/w/h only — never anchors.*: undefined.
          readonly property int gap: Style.spacing.md
          readonly property int appsW: window.isBottom
            ? Math.max(appGrid.implicitWidth, Style.space(200))
            : parent.width
          readonly property int controlsW: window.isBottom
            ? Math.max(controlsStrip.implicitWidth, Style.space(148))
            : parent.width
          readonly property int dividerW: Math.max(1, Style.spacing.hairline)

          // Paired columns fill the body (panel already hugs this height).
          readonly property int chromeBtnH: window.bottomChromeBtnH
          readonly property int appsStackNaturalH: window.isBottom
            ? (appGrid.compactBodyHeight + Style.spacing.xs + body.chromeBtnH)
            : 0
          readonly property int pairedH: window.isBottom
            ? Math.max(controlsStrip.naturalHeight, body.appsStackNaturalH)
            : 0
          // No vertical centering — panelHeight tracks pairedH, so y stays 0.
          readonly property int pairedY: 0

          // Controls column — same top/bottom as appsCol on bottom.
          Item {
            id: controlsCol
            x: 0
            y: window.isBottom ? 0 : (sideChrome.height + Style.spacing.lg)
            width: body.controlsW
            height: window.isBottom ? body.pairedH : controlsStrip.implicitHeight

            ControlsStrip {
              id: controlsStrip
              service: window.service
              visibleContent: window.contentShown
              fillAvailable: window.isBottom
              // Stretch only when the paired band is taller than the tiles.
              stretchTiles: window.isBottom && body.pairedH > naturalHeight
              width: parent.width
              height: window.isBottom ? parent.height : implicitHeight
            }
          }

          // Apps + buttons under the grid. Same top/bottom as controlsCol.
          Item {
            id: appsCol
            x: window.isBottom
              ? (controlsCol.width + body.gap)
              : 0
            y: window.isBottom
              ? 0
              : (controlsCol.y + controlsCol.height + Style.spacing.panelGap)
            width: body.appsW
            height: window.isBottom ? body.pairedH : appGrid.implicitHeight

            AppGrid {
              id: appGrid
              maxRows: 2
              service: window.service
              visibleContent: window.contentShown
              fillAvailable: window.isBottom
              compactTopAlign: window.isBottom
              x: 0
              y: 0
              width: parent.width
              height: window.isBottom
                ? Math.max(0, parent.height - Style.spacing.xs - body.chromeBtnH)
                : implicitHeight
            }

            // Bottom only: Add apps | Edit side by side under the grid.
            Row {
              id: appsButtonRow
              visible: window.isBottom
              x: 0
              y: parent.height - height
              width: parent.width
              height: body.chromeBtnH
              spacing: Style.spacing.xs

              readonly property int btnW: Math.max(
                Style.space(72),
                Math.floor((width - spacing) / 2))

              Button {
                visible: !window.editing
                width: appsButtonRow.btnW
                height: parent.height
                bordered: true
                foreground: Color.popups.text
                text: appGrid.adding
                  ? window.t("doneAdding", "Done")
                  : window.t("addApps", "Add apps")
                onClicked: appGrid.adding = !appGrid.adding
              }

              Button {
                visible: !window.editing
                width: appsButtonRow.btnW
                height: parent.height
                bordered: true
                foreground: Color.popups.text
                text: window.t("edit", "Edit")
                onClicked: if (service) service.beginEdit()
              }

              Button {
                visible: window.editing
                width: appsButtonRow.btnW
                height: parent.height
                bordered: true
                foreground: Color.popups.text
                text: window.t("undo", "Undo")
                onClicked: if (service) service.undoEdit()
              }

              Button {
                visible: window.editing
                width: appsButtonRow.btnW
                height: parent.height
                bordered: true
                foreground: Color.accent
                text: window.t("done", "Done")
                onClicked: if (service) service.doneEdit()
              }
            }
          }

          // Bottom edit: placement chips under the paired columns (full width).
          Row {
            id: bottomPlacement
            visible: window.isBottom && window.editing
            x: 0
            y: body.pairedH + Style.spacing.xs
            width: controlsCol.width + body.gap + appsCol.width
            spacing: Style.spacing.xs

            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: window.t("placement", "Placement")
              color: Color.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }

            Button {
              bordered: true
              foreground: (service && service.draftEdge === "left") ? Color.accent : Color.popups.text
              text: window.t("edgeLeft", "Left")
              onClicked: if (service) service.setDraftEdge("left")
            }
            Button {
              bordered: true
              foreground: (service && service.draftEdge === "right") ? Color.accent : Color.popups.text
              text: window.t("edgeRight", "Right")
              onClicked: if (service) service.setDraftEdge("right")
            }
            Button {
              bordered: true
              foreground: (service && service.draftEdge === "bottom") ? Color.accent : Color.popups.text
              text: window.t("edgeBottom", "Bottom")
              onClicked: if (service) service.setDraftEdge("bottom")
            }
          }

          Rectangle {
            id: appsDivider
            color: Util.alpha(Color.popups.border, 0.7)
            visible: !window.isBottom
            x: 0
            y: appsCol.y + appsCol.height + Style.spacing.panelGap
            width: parent.width
            height: Math.max(1, Style.spacing.hairline)
          }

          Rectangle {
            id: colDivider
            color: Util.alpha(Color.popups.border, 0.7)
            visible: window.isBottom
            x: appsCol.x + appsCol.width + Style.spacing.sm
            y: 0
            width: body.dividerW
            height: window.isBottom ? body.pairedH : parent.height
          }

          WidgetGrid {
            id: widgetGrid
            service: window.service
            visibleContent: window.contentShown
            horizontal: window.isBottom
            x: window.isBottom ? (colDivider.x + colDivider.width + body.gap) : 0
            y: window.isBottom ? 0 : (appsDivider.y + appsDivider.height + Style.spacing.panelGap)
            width: window.isBottom
              ? Math.max(Style.space(280), parent.width - x)
              : parent.width
            // Bottom: match the controls/apps paired height (panel hugs that).
            height: window.isBottom ? body.pairedH : Math.max(0, parent.height - y)
          }
        }
      }
    }
  }

  HyprlandFocusGrab {
    // Grab only after the pointer enters: on keybind open the grab clears at
    // once and would dismiss the panel.
    active: window.contentShown && window.grabReady && window.pointerEnteredWhileOpen
    windows: [window]
    onCleared: {
      if (window.pointerInside || window.editing) return
      if (window.pinnedOpen && !window.pointerEnteredWhileOpen) return
      if (Date.now() - window.grabArmedAt < 300) return
      window.closeFully()
    }
  }

  ScreenMoveRemap {
    id: remapGuard
    window: window
  }
}
