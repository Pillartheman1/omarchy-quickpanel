import QtQuick
import qs.Commons
import qs.Ui
import "widgets"

// Slot grid for widgets. Vertical scroll on side edges; horizontal scroll when
// the panel sits on the bottom edge.
Item {
  id: root

  property var service: null
  property bool visibleContent: false
  property bool horizontal: false

  readonly property bool editMode: !!(service && service.editing)

  readonly property int columns: 1
  readonly property int minSlotHeight: Style.space(96)
  readonly property int minSlotWidth: Style.space(200)
  // Bottom strip: tight fixed strides so cards pack side-by-side. Do not
  // derive width from strip height — that left huge inter-widget voids.
  // Wireframe cards are roomy; keep span-1 readable and span-2 for clock/SPCX.
  readonly property int minSlotWidthHorizontal: Style.space(130)
  readonly property int maxSlotWidthHorizontal: Style.space(168)
  readonly property int slotGap: Style.spacing.xs
  readonly property int emptyTail: 2
  readonly property int emptyTailHorizontal: 1

  property int dragFromSlot: -1
  property string dragWidgetId: ""
  property int dragSpan: 1
  property real dragHotX: 0
  property real dragHotY: 0
  property real dragPointerX: 0
  property real dragPointerY: 0
  property real dragWidth: 0
  property real dragHeight: 0
  property int hoverSlot: -1
  property bool dragging: false

  property var occupancy: ({})

  readonly property var widgets: service ? service.widgets : []

  // Bottom strip: sorted widget list for the packed Row (on root so the
  // Repeater can see it — a Flickable-local copy left the model empty).
  readonly property var horizontalWidgets: {
    if (!root.horizontal) return []
    var list = root.widgets || []
    var sorted = []
    for (var i = 0; i < list.length; i++) {
      var w = list[i]
      if (!w || !w.id) continue
      sorted.push(w)
    }
    if (sorted.length > 1) {
      sorted.sort(function(a, b) {
        return (Number(a.slot) || 0) - (Number(b.slot) || 0)
      })
    }
    return sorted
  }

  // Along the scroll axis: height for vertical, width for horizontal.
  readonly property real slotStride: {
    if (root.horizontal) {
      return Math.max(root.minSlotWidthHorizontal,
        Math.min(root.maxSlotWidthHorizontal, Style.space(128)))
    }
    return root.minSlotHeight
  }

  readonly property int occupiedEnd: {
    var needed = 0
    var list = root.widgets || []
    for (var i = 0; i < list.length; i++) {
      var w = list[i]
      if (!w) continue
      needed = Math.max(needed, Number(w.slot || 0) + Math.max(1, Number(w.span) || 1))
    }
    return needed
  }

  readonly property int viewportSlots: {
    // Only pad the vertical column to the viewport. Horizontal mode sizes to
    // content so we do not invent a row of empty wide cards.
    if (root.horizontal) return 1
    var stride = root.slotStride + root.slotGap
    if (stride <= 0) return 1
    if (height <= 0) return 1
    return Math.max(1, Math.ceil((height + root.slotGap) / stride))
  }

  readonly property int slotCount: {
    var tail = root.horizontal ? root.emptyTailHorizontal : root.emptyTail
    // Outside edit mode on the bottom strip, only keep occupied slots so the
    // Row packs widgets tightly.
    if (root.horizontal && !root.editMode)
      return Math.max(root.occupiedEnd, 1)
    return Math.max(
      root.occupiedEnd + tail,
      root.viewportSlots,
      (root.widgets ? root.widgets.length : 0) + tail
    )
  }

  readonly property real contentLength: {
    var n = root.slotCount
    if (n <= 0) return 0
    return n * root.slotStride + Math.max(0, n - 1) * root.slotGap
  }

  // Slot indices to render (skip span-continuation cells). Used by the
  // horizontal Row so spacing is not applied to zero-width placeholders.
  property var displaySlots: []

  function rebuildDisplaySlots() {
    // Bottom Row uses horizontalWidgets; skip the vertical slot walk.
    if (root.horizontal) {
      if (root.displaySlots.length !== 0)
        root.displaySlots = []
      return
    }
    var out = []
    var n = root.slotCount
    for (var i = 0; i < n; i++) {
      var occ = root.occupancyAt(i)
      if (occ && occ.isStart) {
        out.push(i)
        continue
      }
      // Empty drop targets while editing (and always on side edges).
      if (!occ)
        out.push(i)
    }
    root.displaySlots = out
  }

  function rebuildOccupancy() {
    var map = ({})
    var list = root.widgets || []
    for (var i = 0; i < list.length; i++) {
      var w = list[i]
      if (!w || !w.id) continue
      var start = Math.max(0, Math.round(Number(w.slot) || 0))
      var span = Math.max(1, Math.round(Number(w.span) || 1))
      for (var s = 0; s < span; s++) {
        // String keys — QVariantMap lookups with int can miss after edge switches.
        map[String(start + s)] = {
          id: String(w.id),
          span: span,
          slot: start,
          isStart: s === 0
        }
      }
    }
    root.occupancy = map
  }

  function componentFor(id) {
    switch (String(id || "")) {
      case "Weather": return weatherComponent
      case "AnalogueClock": return analogueClockComponent
      case "SpcxStock": return spcxStockComponent
      case "SystemGauges": return systemGaugesComponent
      default: return null
    }
  }

  // Bottom: returns visual index into horizontalWidgets (list.length = trailing
  // spare). Side: returns grid slot index. Packed Row has no hole cells, so
  // slot-based hit-testing cannot be used on the bottom strip.
  function slotAt(posInContent) {
    if (root.horizontal) {
      var list = root.horizontalWidgets || []
      var x = posInContent
      var cursor = 0
      for (var i = 0; i < list.length; i++) {
        var w = list[i]
        if (!w) continue
        var span = Math.max(1, Number(w.span) || 1)
        var wWidth = root.slotStride * span
          + root.slotGap * Math.max(0, span - 1)
        if (x < cursor + wWidth + root.slotGap / 2)
          return i
        cursor += wWidth + root.slotGap
      }
      return list.length
    }
    var stride = root.slotStride + root.slotGap
    if (stride <= 0) return 0
    var idx = Math.floor(posInContent / stride)
    if (idx < 0) return 0
    if (idx >= root.slotCount) return root.slotCount - 1
    return idx
  }

  function slotOrigin(slot) {
    return slot * (root.slotStride + root.slotGap)
  }

  function occupancyAt(slot) {
    return root.occupancy[String(slot)] || root.occupancy[slot] || null
  }

  // Vertical Loader height from occupancy — do not wait on item.slotIndex /
  // item.height or span-2 cards overlap the next slot.
  function slotHeightAt(slot) {
    var occ = root.occupancyAt(slot)
    if (!occ) return root.slotStride
    if (!occ.isStart) return 0
    var span = Math.max(1, Number(occ.span) || 1)
    return root.slotStride * span + root.slotGap * Math.max(0, span - 1)
  }

  function beginDrag(widgetId, span, fromSlot, slotItem, mouseX, mouseY) {
    if (!widgetId || !slotItem) return
    root.dragging = true
    root.dragWidgetId = String(widgetId)
    root.dragSpan = Math.max(1, span)
    root.dragFromSlot = fromSlot
    root.hoverSlot = fromSlot
    root.dragWidth = slotItem.width
    root.dragHeight = slotItem.height
    root.dragHotX = mouseX
    root.dragHotY = mouseY
    var rootPoint = slotItem.mapToItem(root, mouseX, mouseY)
    root.dragPointerX = rootPoint.x
    root.dragPointerY = rootPoint.y
  }

  function updateDragFromItem(item, mouseX, mouseY) {
    if (!root.dragging || !item) return
    var rootPoint = item.mapToItem(root, mouseX, mouseY)
    root.dragPointerX = rootPoint.x
    root.dragPointerY = rootPoint.y

    // Map into the packed Row / vertical column so hit-testing matches layout.
    var contentPos
    if (root.horizontal && hRow) {
      var rowPoint = item.mapToItem(hRow, mouseX, mouseY)
      contentPos = rowPoint.x
    } else if (!root.horizontal && vCol) {
      var colPoint = item.mapToItem(vCol, mouseX, mouseY)
      contentPos = colPoint.y
    } else {
      contentPos = root.horizontal
        ? rootPoint.x + flick.contentX
        : rootPoint.y + flick.contentY
    }
    var next = root.slotAt(contentPos)
    if (next !== root.hoverSlot) root.hoverSlot = next

    var edge = Style.space(28)
    var step = Style.space(10)
    if (root.horizontal) {
      if (rootPoint.x < edge)
        flick.contentX = Math.max(0, flick.contentX - step)
      else if (rootPoint.x > root.width - edge) {
        var maxX = Math.max(0, flick.contentWidth - flick.width)
        flick.contentX = Math.min(maxX, flick.contentX + step)
      }
    } else {
      if (rootPoint.y < edge)
        flick.contentY = Math.max(0, flick.contentY - step)
      else if (rootPoint.y > root.height - edge) {
        var maxY = Math.max(0, flick.contentHeight - flick.height)
        flick.contentY = Math.min(maxY, flick.contentY + step)
      }
    }
  }

  function endDrag() {
    if (!root.dragging) return
    var id = root.dragWidgetId
    var target = root.hoverSlot
    root.dragging = false
    root.dragWidgetId = ""
    root.dragFromSlot = -1
    root.hoverSlot = -1
    root.dragWidth = 0
    root.dragHeight = 0
    if (!id || target < 0) return

    // Bottom strip is a packed list — reorder by visual index, then repack.
    // Slot-based placeWidget swaps left holes that the Row does not render,
    // so the spare Loader and cards fought over the same occupancy (clones).
    if (root.horizontal) {
      var list = root.horizontalWidgets || []
      var fromIdx = -1
      for (var i = 0; i < list.length; i++) {
        if (list[i] && String(list[i].id) === id) {
          fromIdx = i
          break
        }
      }
      if (fromIdx < 0 || !service) return
      var toIdx = target
      if (toIdx >= list.length)
        toIdx = list.length - 1
      if (toIdx < 0 || fromIdx === toIdx) return
      service.moveWidget(fromIdx, toIdx, true)
      return
    }

    if (service)
      service.placeWidget(id, target, true)
  }

  Component.onCompleted: {
    rebuildOccupancy()
    rebuildDisplaySlots()
  }
  onWidgetsChanged: rebuildOccupancy()
  onOccupancyChanged: rebuildDisplaySlots()
  onSlotCountChanged: rebuildDisplaySlots()
  onEditModeChanged: rebuildDisplaySlots()
  onHorizontalChanged: {
    flick.contentX = 0
    flick.contentY = 0
    rebuildDisplaySlots()
  }

  Component { id: weatherComponent; Weather {} }
  Component { id: analogueClockComponent; AnalogueClock {} }
  Component { id: spcxStockComponent; SpcxStock {} }
  Component { id: systemGaugesComponent; SystemGauges {} }

  // Shared slot cell (used by horizontal Row and vertical absolute grid).
  Component {
    id: slotCellComponent

    Item {
      id: cell

      property int slotIndex: 0
      // Packed Row visual index; list.length marks the trailing spare. Side
      // edges leave this at -1 and use slotIndex for drop highlighting.
      property int visualIndex: -1
      property bool layHorizontal: false

      readonly property var occ: root.occupancyAt(slotIndex)
      readonly property bool isStart: !!(occ && occ.isStart)
      readonly property bool isEmpty: !occ
      readonly property bool isDropTarget: root.dragging && (
        root.horizontal
          ? root.hoverSlot === visualIndex
          : root.hoverSlot === slotIndex)
      readonly property bool isDragSource: root.dragging
        && root.dragWidgetId.length > 0
        && isStart
        && occ
        && occ.id === root.dragWidgetId

      readonly property real spanSize: {
        if (!isStart && !isEmpty) return 0
        if (isStart && occ)
          return root.slotStride * occ.span
            + root.slotGap * Math.max(0, occ.span - 1)
        return root.slotStride
      }

      // Keep visibility on the cell itself — do not overwrite from Loader.onLoaded
      // (that fought Loader.visible: item.visible and blanked the side grid).
      visible: layHorizontal || isStart || isEmpty

      // Bottom (horizontal): size from span. Side (vertical): fill the parent
      // Loader, whose height comes from slotHeightAt(index) — avoids span-2
      // cards painting over the next slot when cell spanSize races slotIndex.
      width: layHorizontal
        ? spanSize
        : (parent && parent.width > 0 ? parent.width : (flick ? flick.width : spanSize))
      height: layHorizontal
        ? (flick ? flick.height : root.slotStride)
        : (parent && parent.height > 0 ? parent.height : spanSize)
      z: isDragSource ? 5 : 0

      Rectangle {
        anchors.fill: parent
        radius: Style.cornerRadius
        visible: root.dragging && (cell.isEmpty || cell.isDropTarget)
        color: cell.isDropTarget && cell.isEmpty
          ? Util.alpha(Color.accent, 0.18)
          : Util.alpha(Color.muted, 0.10)
        border.width: Math.max(1, Style.spacing.hairline)
        border.color: cell.isDropTarget
          ? Color.accent
          : Util.alpha(Color.muted, 0.45)
      }

      Loader {
        id: loader
        anchors.fill: parent
        active: cell.isStart && cell.occ && cell.occ.id
        sourceComponent: cell.isStart && cell.occ ? root.componentFor(cell.occ.id) : null
        opacity: cell.isDragSource ? 0 : 1
        enabled: !cell.isDragSource
        clip: true
        asynchronous: true

        onLoaded: {
          if (!item) return
          if ("service" in item) item.service = root.service
          if ("active" in item) item.active = root.visibleContent
          // SystemGauges stacks from service.activeEdge; no horizontal inject
          // here — Binding horizontal onto every card blanked the side grid.
        }

        Binding {
          target: loader.item
          property: "service"
          value: root.service
          when: loader.status === Loader.Ready && loader.item
        }

        Binding {
          target: loader.item
          property: "active"
          value: root.visibleContent && !cell.isDragSource
          when: loader.status === Loader.Ready && loader.item
        }
      }

      Rectangle {
        anchors.fill: parent
        radius: Style.cornerRadius
        color: Util.alpha(Color.muted, 0.14)
        border.width: Math.max(1, Style.spacing.hairline)
        border.color: Util.alpha(Color.muted, 0.4)
        visible: cell.isDragSource
        z: -1
      }

      Rectangle {
        anchors.fill: parent
        radius: Style.cornerRadius
        color: "transparent"
        border.width: cell.isDropTarget && !cell.isEmpty && !cell.isDragSource
          ? Math.max(1, Style.space(2))
          : 0
        border.color: Color.accent
        visible: border.width > 0
        z: 10
      }

      Rectangle {
        id: deleteChip
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Style.spacing.xs
        width: Style.space(22)
        height: Style.space(22)
        radius: width / 2
        z: 30
        visible: root.editMode && cell.isStart && cell.occ && !cell.isDragSource
        color: Color.urgent
        border.width: Math.max(1, Style.spacing.hairline)
        border.color: Util.alpha("#ffffff", 0.35)

        Text {
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: "✕"
          color: "#ffffff"
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (service && cell.occ)
              service.removeWidget(String(cell.occ.id))
          }
        }
      }

      MouseArea {
        id: dragArea
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        enabled: root.editMode && (cell.isStart || root.dragging)
        propagateComposedEvents: !root.editMode
        cursorShape: root.dragging ? Qt.ClosedHandCursor
          : (root.editMode && cell.isStart ? Qt.OpenHandCursor : Qt.ArrowCursor)
        hoverEnabled: false
        property bool armed: false
        property real pressX: 0
        property real pressY: 0

        onPressed: function(mouse) {
          if (!root.editMode || !cell.isStart || !cell.occ) {
            mouse.accepted = false
            return
          }
          armed = true
          pressX = mouse.x
          pressY = mouse.y
          mouse.accepted = true
        }

        onPositionChanged: function(mouse) {
          if (!root.editMode) return
          if (!(mouse.buttons & Qt.LeftButton)) return
          if (!root.dragging && armed && cell.isStart && cell.occ) {
            var dx = mouse.x - pressX
            var dy = mouse.y - pressY
            if (dx * dx + dy * dy < 16) return
            root.beginDrag(
              String(cell.occ.id),
              Math.max(1, Number(cell.occ.span) || 1),
              root.horizontal ? cell.visualIndex : cell.slotIndex,
              cell,
              mouse.x,
              mouse.y
            )
          }
          if (!root.dragging) return
          root.updateDragFromItem(cell, mouse.x, mouse.y)
          mouse.accepted = true
        }

        onReleased: function(mouse) {
          armed = false
          if (root.dragging) {
            root.updateDragFromItem(cell, mouse.x, mouse.y)
            root.endDrag()
            mouse.accepted = true
          } else {
            mouse.accepted = false
          }
        }

        onCanceled: {
          armed = false
          if (root.dragging) root.endDrag()
        }

        onClicked: function(mouse) {
          if (root.dragging || root.editMode) {
            mouse.accepted = true
            return
          }
          mouse.accepted = false
        }
      }
    }
  }

  Flickable {
    id: flick
    anchors.fill: parent
    contentWidth: root.horizontal
      ? Math.max(width, hRow.width)
      : width
    contentHeight: root.horizontal
      ? height
      : Math.max(height, vCol.implicitHeight, root.contentLength)
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: root.horizontal ? Flickable.HorizontalFlick : Flickable.VerticalFlick
    interactive: {
      if (root.dragging) return false
      if (root.horizontal) return hRow.width > width + 1
      return root.contentLength > height + 1
    }

    onContentYChanged: {
      if (root.horizontal && contentY !== 0) contentY = 0
    }
    onContentXChanged: {
      if (!root.horizontal && contentX !== 0) contentX = 0
    }

    // Bottom edge: pack widget cards only (plus one empty drop target while
    // editing). Width comes from span × tight stride — never from viewport.
    Row {
      id: hRow
      visible: root.horizontal
      height: flick.height
      spacing: root.slotGap

      Repeater {
        model: root.horizontal ? root.horizontalWidgets : []
        delegate: Loader {
          id: hSlotLoader
          required property int index
          required property var modelData
          active: root.horizontal && !!modelData && !!modelData.id
          height: hRow.height
          width: {
            var span = Math.max(1, Number(modelData && modelData.span) || 1)
            return root.slotStride * span + root.slotGap * Math.max(0, span - 1)
          }
          sourceComponent: slotCellComponent
          onLoaded: {
            if (!item || !modelData) return
            item.slotIndex = Math.max(0, Math.round(Number(modelData.slot) || 0))
            item.visualIndex = index
            item.layHorizontal = true
          }

          Binding {
            target: hSlotLoader.item
            property: "slotIndex"
            value: Math.max(0, Math.round(Number(modelData.slot) || 0))
            when: hSlotLoader.status === Loader.Ready && hSlotLoader.item
              && modelData && modelData.id
          }

          Binding {
            target: hSlotLoader.item
            property: "visualIndex"
            value: index
            when: hSlotLoader.status === Loader.Ready && hSlotLoader.item
          }
        }
      }

      // Single spare drop slot at the end while editing. Never bind slotIndex
      // without a model guard — a missing modelData falling through to 0 made
      // every recycling cell load the widget at slot 0 (clone/replace).
      Loader {
        id: spareDropLoader
        active: root.horizontal && root.editMode
        height: hRow.height
        width: active ? root.slotStride : 0
        visible: active
        sourceComponent: slotCellComponent
        onLoaded: {
          if (!item) return
          item.slotIndex = root.occupiedEnd
          item.visualIndex = root.horizontalWidgets.length
          item.layHorizontal = true
        }

        Binding {
          target: spareDropLoader.item
          property: "slotIndex"
          value: root.occupiedEnd
          when: spareDropLoader.status === Loader.Ready && spareDropLoader.item
        }

        Binding {
          target: spareDropLoader.item
          property: "visualIndex"
          value: root.horizontalWidgets.length
          when: spareDropLoader.status === Loader.Ready && spareDropLoader.item
        }
      }
    }

    // Side edges: packed column of start slots (+ empty drop targets).
    // A Column avoids absolute-y + continuation-slot races that stacked cards
    // on top of each other after bottom→right edge switches.
    Column {
      id: vCol
      visible: !root.horizontal
      width: flick.width
      spacing: root.slotGap

      Repeater {
        model: root.horizontal ? [] : root.displaySlots
        delegate: Loader {
          id: slotLoader
          required property int index
          required property var modelData
          readonly property int slot: Math.max(0, Number(modelData) || 0)
          active: !root.horizontal
          width: vCol.width
          height: root.slotHeightAt(slot)
          clip: true
          asynchronous: false
          sourceComponent: slotCellComponent
          onLoaded: {
            if (!item) return
            item.slotIndex = slot
            item.layHorizontal = false
          }

          Binding {
            target: slotLoader.item
            property: "slotIndex"
            value: slot
            when: slotLoader.status === Loader.Ready && slotLoader.item
          }
        }
      }
    }
  }

  // On root (not inside Flickable) so it is not reparented onto contentItem.
  // Trackpads send vertical wheel deltas — map them onto contentX.
  WheelHandler {
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    enabled: root.horizontal && !root.dragging
    onWheel: function(event) {
      var maxX = Math.max(0, flick.contentWidth - flick.width)
      if (maxX <= 0) return
      var delta = event.angleDelta.x !== 0 ? event.angleDelta.x : event.angleDelta.y
      if (delta === 0)
        delta = event.pixelDelta.x !== 0 ? event.pixelDelta.x : event.pixelDelta.y
      if (delta === 0) return
      flick.contentX = Math.max(0, Math.min(maxX, flick.contentX - delta))
      event.accepted = true
    }
  }

  Item {
    id: dragGhost
    visible: root.dragging && root.dragWidgetId.length > 0
    width: root.dragWidth
    height: root.dragHeight
    x: root.dragPointerX - root.dragHotX
    y: root.dragPointerY - root.dragHotY
    z: 100
    opacity: 0.92
    scale: 1.03

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: Util.alpha(Color.popups.background, 0.92)
      border.width: Math.max(1, Style.space(1))
      border.color: Color.accent
    }

    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: root.dragWidgetId
      color: Color.popups.text
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      font.bold: true
    }
  }
}
