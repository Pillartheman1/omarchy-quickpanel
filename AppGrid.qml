import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Item {
  id: root

  property var service: null
  property bool visibleContent: false
  property bool adding: false
  property string filterText: ""
  // Pinned launcher band stays compact so the widget grid can own the rest.
  property int maxRows: 2
  readonly property bool editMode: !!(service && service.editing)
  // When true, parent anchors drive height (bottom-edge horizontal strip).
  property bool fillAvailable: false
  // Bottom paired column: pin grid at the top (buttons sit below).
  property bool compactTopAlign: false

  readonly property int iconSize: Math.round(36 * Style.fontScale)
  readonly property int iconInset: Style.spacing.md
  readonly property int slotSize: iconSize + iconInset * 2
  readonly property int columns: Math.max(1, Math.floor(Math.max(slotSize, width) / slotSize))
  readonly property int pinRowsHeight: root.maxRows * root.slotSize
    + Math.max(0, root.maxRows - 1) * Style.spacing.xs
  readonly property int pinnedImplicitHeight: appsHeader.implicitHeight
    + Style.spacing.md
    + root.pinRowsHeight

  // Bottom strip: 4 columns, stacked vertically (scroll if needed).
  readonly property int compactColumns: 4
  // Real content height; Grid.rows=1000 inflates implicitHeight and breaks centering.
  readonly property int compactPinRows: Math.max(0,
    Math.ceil(root.pins.length / Math.max(1, root.compactColumns)))
  readonly property int compactGridHeight: root.pins.length === 0
    ? 0
    : (root.compactPinRows * root.slotSize
      + Math.max(0, root.compactPinRows - 1) * Style.spacing.xs)
  // Bottom Add apps: search box + a few result rows, so search is not squeezed
  // into the pin-row band.
  readonly property int compactAddRows: 4
  readonly property int compactAddHeight: searchBox.height + addView.spacing
    + root.compactAddRows * (Style.spacing.popupRowHeight + Style.spacing.sm)
    + Math.max(0, root.compactAddRows - 1) * Style.spacing.hairline
  // What the bottom paired column reserves above its buttons.
  readonly property int compactBodyHeight: root.adding
    ? Math.max(root.compactGridHeight, root.compactAddHeight)
    : root.compactGridHeight

  implicitWidth: root.fillAvailable
    ? (root.compactColumns * root.slotSize
      + Math.max(0, root.compactColumns - 1) * Style.spacing.xs)
    : Style.space(280)
  implicitHeight: root.adding
    ? Math.max(root.pinnedImplicitHeight, Style.space(280))
    : root.pinnedImplicitHeight
  // Parent drives height on the bottom strip — do not bind height here.

  readonly property var pins: service ? service.pins : []
  // Debounced so each keystroke does not rescan DesktopEntries + sort.
  property var searchResults: []

  Timer {
    id: searchDebounce
    interval: 80
    onTriggered: {
      if (!root.adding || !service || typeof service.searchApps !== "function") {
        root.searchResults = []
        return
      }
      root.searchResults = service.searchApps(root.filterText) || []
    }
  }

  onFilterTextChanged: {
    if (!root.adding) {
      root.searchResults = []
      return
    }
    searchDebounce.restart()
  }

  onVisibleContentChanged: {
    if (!visibleContent) {
      root.adding = false
      root.filterText = ""
    }
  }

  onAddingChanged: {
    if (adding) {
      root.filterText = ""
      root.searchResults = []
      searchDebounce.restart()
      Qt.callLater(function() { if (root.adding) filterField.forceActiveFocus() })
    } else {
      root.searchResults = []
    }
  }

  // ---- pinned view -------------------------------------------------------
  // Size the Flickable from sibling implicit heights. `parent.height - y`
  // inside a Column collapses to 0 during layout.
  readonly property bool compact: root.fillAvailable

  Column {
    id: pinnedView
    anchors.fill: parent
    visible: !root.adding
    spacing: root.compact ? 0 : Style.spacing.md

    Text {
      id: appsHeader
      width: parent.width
      visible: !root.compact
      height: visible ? implicitHeight : 0
      textFormat: Text.PlainText
      text: service && service.strings ? service.strings.t("apps") : "Apps"
      color: Color.popups.text
      opacity: 0.7
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }

    Item {
      id: pinBody
      width: parent.width
      height: root.compact
        ? parent.height
        : root.pinRowsHeight

      Flickable {
        id: pinFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: root.compact
          ? Math.max(height, root.compactGridHeight)
          : Math.max(grid.implicitHeight, emptyState.implicitHeight + Style.spacing.xl)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        // Bottom: 4-col stack scrolls vertically inside the strip.
        flickableDirection: Flickable.VerticalFlick
        visible: root.pins.length > 0

        Grid {
          id: grid
          // Bottom paired column: top-align so buttons can sit under the grid.
          // Otherwise center when the pin block is shorter than the viewport.
          y: {
            if (!root.compact || root.compactTopAlign) return 0
            var h = root.compactGridHeight
            var avail = pinFlick.height
            return (h > 0 && h < avail) ? Math.round((avail - h) / 2) : 0
          }
          width: parent.width
          columns: root.compact ? root.compactColumns : root.columns
          flow: Grid.LeftToRight
          rowSpacing: Style.spacing.xs
          columnSpacing: Style.spacing.xs

          Repeater {
            model: root.pins

            delegate: Item {
              id: pinSlot
              required property var modelData
              required property int index

              width: root.slotSize
              height: root.slotSize

              readonly property string desktopId: String(modelData || "")
              readonly property string appName: service ? service.nameFor(desktopId) : desktopId
              readonly property string iconSource: service ? service.iconFor(desktopId) : ""

              Rectangle {
                anchors.fill: parent
                radius: Style.cornerRadius
                color: pinMouse.containsMouse ? Util.alpha(Color.accent, 0.18) : "transparent"
                border.width: pinMouse.pressed ? Style.spacing.hairline : 0
                border.color: Color.accent
              }

              // Light plate so dark/black app icons (foot, cliamp) stay visible.
              Rectangle {
                anchors.centerIn: parent
                width: root.iconSize + Style.spacing.sm
                height: root.iconSize + Style.spacing.sm
                radius: Style.cornerRadius
                color: Util.alpha("#ffffff", 0.16)
              }

              Text {
                anchors.centerIn: parent
                visible: pinIcon.status !== Image.Ready
                textFormat: Text.PlainText
                text: pinSlot.appName ? pinSlot.appName.charAt(0).toUpperCase() : "?"
                color: Color.popups.text
                font.family: Style.font.family
                font.pixelSize: Math.round(root.iconSize * 0.55)
                font.bold: true
              }

              Image {
                id: pinIcon
                anchors.centerIn: parent
                width: root.iconSize
                height: root.iconSize
                sourceSize: Qt.size(root.iconSize * 2, root.iconSize * 2)
                source: pinSlot.iconSource
                fillMode: Image.PreserveAspectFit
                // Match dock AppGrid: load with the cell so icons are present
                // when the panel slides open.
                asynchronous: false
                smooth: true
                mipmap: true
              }

              // Edit-mode delete chip
              Rectangle {
                anchors.top: parent.top
                anchors.right: parent.right
                width: Style.space(18)
                height: Style.space(18)
                radius: width / 2
                z: 20
                visible: root.editMode
                color: Color.urgent
                border.width: Math.max(1, Style.spacing.hairline)
                border.color: Util.alpha("#ffffff", 0.35)

                Text {
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: "✕"
                  color: "#ffffff"
                  font.family: Style.font.family
                  font.pixelSize: Math.round(Style.font.caption * 0.9)
                  font.bold: true
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (service) service.unpinApp(pinSlot.desktopId)
                  }
                }
              }

              MouseArea {
                id: pinMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: root.editMode ? Qt.OpenHandCursor : Qt.PointingHandCursor
                property bool dragging: false
                property int dragFrom: -1

                onPressed: function(mouse) {
                  if (!root.editMode || mouse.button !== Qt.LeftButton) return
                  dragging = false
                  dragFrom = pinSlot.index
                }

                onPositionChanged: function(mouse) {
                  if (!root.editMode || dragFrom < 0) return
                  if (!(mouse.buttons & Qt.LeftButton)) return
                  if (!dragging) {
                    if (Math.abs(mouse.x) + Math.abs(mouse.y) < 8) return
                    dragging = true
                  }
                  var p = mapToItem(grid, mouse.x, mouse.y)
                  var cols = Math.max(1, root.compact ? root.compactColumns : root.columns)
                  var pitch = root.slotSize + Style.spacing.xs
                  var col = Math.floor(p.x / pitch)
                  var row = Math.floor(p.y / pitch)
                  if (col < 0 || row < 0) return
                  if (col >= cols) col = cols - 1
                  var to = row * cols + col
                  if (to >= root.pins.length) to = root.pins.length - 1
                  if (to >= 0 && to !== dragFrom && service && typeof service.movePin === "function") {
                    service.movePin(dragFrom, to)
                    dragFrom = to
                  }
                }

                onReleased: function(mouse) {
                  dragging = false
                  dragFrom = -1
                }

                onClicked: function(mouse) {
                  if (root.editMode) {
                    mouse.accepted = true
                    return
                  }
                  if (mouse.button === Qt.RightButton) {
                    if (service) service.unpinApp(pinSlot.desktopId)
                    return
                  }
                  if (service) service.launchApp(pinSlot.desktopId)
                }
              }

              PanelToolTip {
                visible: pinMouse.containsMouse && !pinMouse.pressed
                text: pinSlot.appName
              }
            }
          }
        }
      }

      Column {
        id: emptyState
        visible: root.pins.length === 0
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Style.spacing.xl
        spacing: Style.spacing.xs
        width: parent.width - Style.spacing.xl * 2

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          textFormat: Text.PlainText
          text: service && service.strings ? service.strings.t("empty") : "No pinned apps yet"
          color: Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          textFormat: Text.PlainText
          text: service && service.strings ? service.strings.t("emptyHint") : "Open Add apps to pin launchers here"
          color: Color.popups.text
          opacity: 0.65
          wrapMode: Text.WordWrap
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }
    }

  }

  // ---- add / search view -------------------------------------------------
  Column {
    id: addView
    anchors.fill: parent
    visible: root.adding
    spacing: Style.spacing.sm

    BorderSurface {
      id: searchBox
      width: parent.width
      height: Math.max(Style.spacing.controlHeight, Style.font.body + Style.spacing.sm * 2)
      radius: Style.cornerRadius
      color: Util.alpha(Color.popups.text, 0.06)
      borderSpec: Border.none()
      padding: Style.spacing.sm

      FilterInput {
        id: filterField
        anchors.fill: parent
        anchors.margins: Style.spacing.sm
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        text: root.filterText
        onTextChanged: root.filterText = text

        Text {
          anchors.fill: parent
          visible: !filterField.text
          textFormat: Text.PlainText
          text: service && service.strings ? service.strings.t("searchApps") : "Search apps"
          color: Color.popups.text
          opacity: 0.45
          font: filterField.font
          verticalAlignment: Text.AlignVCenter
        }
      }
    }

    Flickable {
      id: searchFlick
      width: parent.width
      height: Math.max(
        Style.spacing.popupRowHeight,
        parent.height - searchBox.height - addView.spacing
      )
      contentHeight: searchColumn.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      Column {
        id: searchColumn
        width: parent.width
        spacing: Style.spacing.hairline

        Repeater {
          model: root.searchResults

          delegate: Rectangle {
            id: row
            required property var modelData
            required property int index

            width: searchColumn.width
            height: Style.spacing.popupRowHeight + Style.spacing.sm
            radius: Style.cornerRadius
            color: rowMouse.containsMouse ? Util.alpha(Color.accent, 0.16) : "transparent"

            readonly property string desktopId: modelData && modelData.id ? String(modelData.id) : ""
            readonly property string appName: modelData && modelData.name ? String(modelData.name) : desktopId
            readonly property bool pinned: service ? service.isPinned(desktopId) : false
            readonly property string iconSource: service ? service.iconFor(desktopId) : ""

            Row {
              anchors.fill: parent
              anchors.leftMargin: Style.spacing.sm
              anchors.rightMargin: Style.spacing.sm
              spacing: Style.spacing.sm

              Item {
                anchors.verticalCenter: parent.verticalCenter
                width: Style.font.icon
                height: Style.font.icon

                Rectangle {
                  anchors.centerIn: parent
                  width: parent.width + Style.spacing.xs
                  height: parent.height + Style.spacing.xs
                  radius: Style.cornerRadius
                  color: Util.alpha("#ffffff", 0.16)
                }

                Text {
                  anchors.centerIn: parent
                  visible: rowIcon.status !== Image.Ready
                  textFormat: Text.PlainText
                  text: row.appName ? row.appName.charAt(0).toUpperCase() : "?"
                  color: Color.popups.text
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                }

                Image {
                  id: rowIcon
                  anchors.fill: parent
                  sourceSize: Qt.size(width * 2, height * 2)
                  source: row.iconSource
                  fillMode: Image.PreserveAspectFit
                  asynchronous: false
                  smooth: true
                  mipmap: true
                }
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, parent.width - x - pinMark.width - parent.spacing)
                textFormat: Text.PlainText
                text: row.appName
                color: Color.popups.text
                elide: Text.ElideRight
                font.family: Style.font.family
                font.pixelSize: Style.font.body
              }

              Text {
                id: pinMark
                anchors.verticalCenter: parent.verticalCenter
                visible: row.pinned
                textFormat: Text.PlainText
                text: "●"
                color: Color.accent
                font.pixelSize: Style.font.caption
              }
            }

            MouseArea {
              id: rowMouse
              anchors.fill: parent
              hoverEnabled: true
              acceptedButtons: Qt.LeftButton | Qt.RightButton
              cursorShape: Qt.PointingHandCursor
              onClicked: function(mouse) {
                if (!service || !row.desktopId) return
                if (row.pinned) service.unpinApp(row.desktopId)
                else service.pinApp(row.desktopId)
              }
            }
          }
        }

        Text {
          visible: root.adding && root.searchResults.length === 0
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          topPadding: Style.spacing.xl
          textFormat: Text.PlainText
          text: service && service.strings ? service.strings.t("noMatches") : "No matching apps"
          color: Color.popups.text
          opacity: 0.65
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
