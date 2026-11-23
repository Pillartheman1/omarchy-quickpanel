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

  readonly property int iconSize: Math.round(36 * Style.fontScale)
  readonly property int iconInset: Style.spacing.md
  readonly property int slotSize: iconSize + iconInset * 2
  readonly property int columns: Math.max(1, Math.floor(Math.max(slotSize, width) / slotSize))

  readonly property var pins: service ? service.pins : []
  readonly property var searchResults: {
    if (!root.adding || !service || !service.appLibrary) return []
    if (typeof service.appLibrary.sortedEntries !== "function") return []
    var entries = service.appLibrary.sortedEntries(root.filterText) || []
    var out = []
    var limit = 48
    for (var i = 0; i < entries.length && out.length < limit; i++) {
      var entry = entries[i]
      if (!entry || entry.noDisplay) continue
      out.push(entry)
    }
    return out
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
      Qt.callLater(function() { if (root.adding) filterField.forceActiveFocus() })
    }
  }

  // ---- pinned view -------------------------------------------------------
  Column {
    id: pinnedView
    anchors.fill: parent
    visible: !root.adding
    spacing: Style.spacing.md

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: service && service.strings ? service.strings.t("apps") : "Apps"
      color: Color.popups.text
      opacity: 0.7
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }

    Item {
      width: parent.width
      height: Math.max(0, parent.height - y - footerBlock.height - pinnedView.spacing)

      Flickable {
        id: pinFlick
        anchors.fill: parent
        contentHeight: Math.max(grid.implicitHeight, emptyState.implicitHeight + Style.spacing.xl)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        visible: root.pins.length > 0

        Grid {
          id: grid
          width: parent.width
          columns: root.columns
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

              Image {
                anchors.centerIn: parent
                width: root.iconSize
                height: root.iconSize
                sourceSize: Qt.size(root.iconSize * 2, root.iconSize * 2)
                source: pinSlot.iconSource
                fillMode: Image.PreserveAspectFit
                asynchronous: true
              }

              MouseArea {
                id: pinMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onClicked: function(mouse) {
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

    Column {
      id: footerBlock
      width: parent.width
      spacing: Style.spacing.sm

      PanelSeparator { width: parent.width }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: service && service.strings ? service.strings.t("moreLater") : "More widgets later"
        color: Color.popups.text
        opacity: 0.45
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        horizontalAlignment: Text.AlignHCenter
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
      height: Math.max(0, parent.height - y)
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
            readonly property string appName: {
              if (!modelData) return ""
              if (service && service.appLibrary && typeof service.appLibrary.entryName === "function")
                return String(service.appLibrary.entryName(modelData) || modelData.name || desktopId)
              return String(modelData.name || desktopId)
            }
            readonly property bool pinned: service ? service.isPinned(desktopId) : false
            readonly property string iconSource: {
              if (!service) return ""
              if (modelData && modelData.icon && service.appLibrary && typeof service.appLibrary.iconSource === "function")
                return service.appLibrary.iconSource(modelData.icon)
              return service.iconFor(desktopId)
            }

            Row {
              anchors.fill: parent
              anchors.leftMargin: Style.spacing.sm
              anchors.rightMargin: Style.spacing.sm
              spacing: Style.spacing.sm

              Image {
                anchors.verticalCenter: parent.verticalCenter
                width: Style.font.icon
                height: Style.font.icon
                sourceSize: Qt.size(width * 2, height * 2)
                source: row.iconSource
                fillMode: Image.PreserveAspectFit
                asynchronous: true
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
