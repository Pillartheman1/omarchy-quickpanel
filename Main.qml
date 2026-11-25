import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import "Model.js" as Model

Item {
  id: root

  property var shell: null
  property var manifest: null

  // Overlay plugins do not receive shell.appLibrary (menu kinds only), so
  // apps are resolved through DesktopEntries and launched with gtk-launch.
  readonly property string configPath: {
    var configHome = Quickshell.env("XDG_CONFIG_HOME")
    if (!configHome || configHome === "")
      configHome = Quickshell.env("HOME") + "/.config"
    return configHome + "/omarchy/extensions/daniel.quickpanel.json"
  }

  property var pins: []
  property var widgets: []
  property string edge: "right"
  property bool forceOpen: false
  property real cursorX: -1
  property real cursorY: -1

  // Edit mode: snapshot for Undo; draftEdge chosen before Done commits.
  property bool editing: false
  property var editSnapshot: null
  property string draftEdge: "right"

  // Same fallback index AppLibrary builds: Qt's themed iconPath often misses
  // app icons in a long-lived shell (cache never re-scans; some names only
  // live under apps/ or pixmaps).
  property var iconIndex: ({})
  property var pendingIconIndex: ({})

  property alias strings: stringsCatalog

  Commons.Translations {
    id: stringsCatalog
    directory: Qt.resolvedUrl("i18n")
  }

  function loadConfig(raw) {
    // Ignore disk reloads while editing so Undo/Done own the working copy.
    if (root.editing) return
    var parsed = Model.parseConfig(raw)
    root.pins = parsed.pins
    root.edge = parsed.edge
    root.draftEdge = parsed.edge
    var hadWidgetsKey = false
    try {
      var data = JSON.parse(String(raw || "{}"))
      hadWidgetsKey = !!(data && Object.prototype.hasOwnProperty.call(data, "widgets"))
    } catch (e) {
      hadWidgetsKey = false
    }
    // Legacy pins-only config: seed Weather + AnalogueClock and persist once.
    if (!hadWidgetsKey) {
      root.widgets = Model.defaultWidgets()
      Qt.callLater(function() { root.saveConfig() })
    } else {
      root.widgets = parsed.widgets
    }
  }

  function saveConfig() {
    configFile.setText(Model.serializeConfig(root.pins, root.widgets, root.edge))
  }

  function persistWorking() {
    if (!root.editing) root.saveConfig()
  }

  function savePins(nextPins) {
    root.pins = Array.isArray(nextPins) ? nextPins.slice() : []
    root.persistWorking()
  }

  function pinApp(desktopId) {
    root.savePins(Model.withPin(root.pins, desktopId))
  }

  function unpinApp(desktopId) {
    root.savePins(Model.withoutPin(root.pins, desktopId))
  }

  function movePin(fromIndex, toIndex) {
    root.pins = Model.movePin(root.pins, fromIndex, toIndex)
    root.persistWorking()
  }

  function isPinned(desktopId) {
    return Model.isPinned(root.pins, desktopId)
  }

  function saveWidgets(nextWidgets) {
    root.widgets = Model.normalizeWidgets(nextWidgets)
    root.persistWorking()
  }

  function addWidget(id, span, slot) {
    var useSpan = span
    if (useSpan === undefined || useSpan === null || useSpan === "")
      useSpan = Model.defaultSpanFor(id)
    root.saveWidgets(Model.withWidget(root.widgets, id, useSpan, slot))
  }

  function removeWidget(id) {
    root.saveWidgets(Model.withoutWidget(root.widgets, id))
  }

  // Place a widget at a grid slot. Pass persist=false while dragging; save on drop.
  function placeWidget(id, slot, persist) {
    root.widgets = Model.placeWidget(root.widgets, id, slot)
    if (persist !== false) root.persistWorking()
  }

  // List reorder (bottom packed strip); see Model.moveWidget.
  function moveWidget(fromIndex, toIndex, persist) {
    root.widgets = Model.moveWidget(root.widgets, fromIndex, toIndex)
    if (persist !== false) root.persistWorking()
  }

  function beginEdit() {
    if (root.editing) return
    root.editSnapshot = Model.cloneSnapshot(root.pins, root.widgets, root.edge)
    root.draftEdge = root.edge
    root.editing = true
  }

  function undoEdit() {
    if (!root.editing || !root.editSnapshot) return
    var snap = root.editSnapshot
    root.pins = Model.normalizePins(snap.pins)
    root.widgets = Model.normalizeWidgets(snap.widgets)
    root.draftEdge = Model.normalizeEdge(snap.edge)
  }

  function doneEdit() {
    if (!root.editing) return
    root.edge = Model.normalizeEdge(root.draftEdge)
    root.editing = false
    root.editSnapshot = null
    root.saveConfig()
  }

  function cancelEdit() {
    if (!root.editing) return
    root.undoEdit()
    root.edge = Model.normalizeEdge(root.draftEdge)
    root.editing = false
    root.editSnapshot = null
    root.saveConfig()
  }

  function setDraftEdge(next) {
    root.draftEdge = Model.normalizeEdge(next)
  }

  function entryFor(desktopId) {
    var id = String(desktopId || "")
    if (!id) return null
    var entry = DesktopEntries.byId(id)
    if (entry) return entry
    return DesktopEntries.heuristicLookup(id)
  }

  function iconSource(icon) {
    // Touch iconIndex so callers rebind when the scan finishes.
    var index = root.iconIndex
    var value = String(icon || "")
    if (value.length === 0) return Quickshell.iconPath("application-x-executable", true)
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return Util.fileUrl(value)

    // Prefer the on-disk app/device index (same order as AppLibrary). An
    // unconstrained themed lookup can miss names that only live under apps/
    // or resolve an app name to the wrong glyph in a long-lived shell.
    var found = index[value]
    if (found) return Util.fileUrl(found)

    var themed = Quickshell.iconPath(value, true)
    if (themed && themed.length > 0) return themed

    return Quickshell.iconPath("application-x-executable", true)
  }

  function iconFor(desktopId) {
    var entry = root.entryFor(desktopId)
    var icon = entry && entry.icon ? String(entry.icon) : ""
    var id = String(desktopId || "")
    // Prefer Icon= from the desktop entry, then the desktop id / basename.
    var fromIcon = icon ? root.iconSource(icon) : ""
    if (fromIcon && fromIcon.length > 0 && fromIcon.indexOf("application-x-executable") < 0)
      return fromIcon
    var base = id
    var dot = id.lastIndexOf(".")
    if (dot >= 0 && dot < id.length - 1) base = id.slice(dot + 1)
    var fromId = id ? root.iconSource(id) : ""
    if (fromId && fromId.length > 0 && fromId.indexOf("application-x-executable") < 0)
      return fromId
    if (base && base !== id) {
      var fromBase = root.iconSource(base)
      if (fromBase && fromBase.length > 0 && fromBase.indexOf("application-x-executable") < 0)
        return fromBase
    }
    return fromIcon || fromId || root.iconSource(icon || id)
  }

  function nameFor(desktopId) {
    var entry = root.entryFor(desktopId)
    if (entry && entry.name) return String(entry.name)
    return String(desktopId || "")
  }

  function iconIndexScanCommand() {
    // Prefer PNG app icons over SVG: many theme SVGs paint near-black and
    // disappear on a dark panel. Skip symbolic glyphs. First hit wins.
    return [
      'dirs="$HOME/.icons $HOME/.local/share/icons";',
      'IFS=":"; for d in ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do dirs="$dirs $d/icons"; done; unset IFS;',
      '{',
      '  for base in $dirs; do',
      '    if [[ -d $base ]]; then',
      '      find "$base" \\( -path "*/apps/*" -o -path "*/devices/*" \\) -name "*.png" ! -name "*-symbolic*" 2>/dev/null;',
      '      find "$base" \\( -path "*/apps/*" -o -path "*/devices/*" \\) -name "*.svg" ! -name "*-symbolic*" 2>/dev/null;',
      '    fi;',
      '  done;',
      '  find /usr/share/pixmaps -maxdepth 1 \\( -name "*.png" -o -name "*.svg" \\) 2>/dev/null;',
      '}'
    ].join(' ')
  }

  function indexIconLine(path) {
    var value = String(path || "").trim()
    if (value.length === 0) return
    if (value.indexOf("-symbolic.") >= 0 || value.indexOf("/symbolic/") >= 0) return
    var slash = value.lastIndexOf("/")
    var file = slash >= 0 ? value.slice(slash + 1) : value
    var dot = file.lastIndexOf(".")
    var name = dot > 0 ? file.slice(0, dot) : file
    if (name.length === 0) return
    // Prefer larger raster sizes when several PNGs share a name: keep the
    // first path unless the new one looks clearly bigger (128/256/512).
    var existing = root.pendingIconIndex[name]
    if (existing === undefined) {
      root.pendingIconIndex[name] = value
      return
    }
    if (existing.indexOf(".png") >= 0 && value.indexOf(".svg") >= 0) return
    if (existing.indexOf(".svg") >= 0 && value.indexOf(".png") >= 0) {
      root.pendingIconIndex[name] = value
      return
    }
    var score = function(p) {
      if (p.indexOf("/512x512/") >= 0) return 512
      if (p.indexOf("/256x256/") >= 0) return 256
      if (p.indexOf("/128x128/") >= 0) return 128
      if (p.indexOf("/64x64/") >= 0) return 64
      if (p.indexOf("/48x48/") >= 0) return 48
      if (p.indexOf("/scalable/") >= 0) return 96
      return 32
    }
    if (score(value) > score(existing)) root.pendingIconIndex[name] = value
  }

  function refreshIcons(force) {
    // Skip the heavy find(1) scan when we already have an index unless forced
    // (DesktopEntries changed) or the index is still empty.
    if (!force && root.iconIndex && Object.keys(root.iconIndex).length > 0)
      return
    if (!iconIndexScan.running) iconIndexScan.running = true
  }

  function debugIcons() {
    var out = []
    for (var i = 0; i < root.pins.length; i++) {
      var id = root.pins[i]
      var entry = root.entryFor(id)
      out.push({
        id: id,
        entryIcon: entry && entry.icon ? String(entry.icon) : "",
        source: root.iconFor(id),
        indexSize: Object.keys(root.iconIndex).length
      })
    }
    return JSON.stringify(out)
  }

  function searchApps(query) {
    var q = String(query || "").trim().toLowerCase()
    var values = DesktopEntries.applications.values
    var out = []
    var n = values.length
    var limit = 48
    for (var i = 0; i < n && out.length < limit; i++) {
      var entry = values[i]
      if (!entry || entry.noDisplay) continue
      if (q) {
        var name = String(entry.name || "").toLowerCase()
        if (name.indexOf(q) < 0) {
          var id = String(entry.id || "").toLowerCase()
          if (id.indexOf(q) < 0) continue
        }
      }
      out.push(entry)
    }
    // Empty query: DesktopEntries order is fine — skip localeCompare sort.
    if (q && out.length > 1) {
      out.sort(function(a, b) {
        return String(a.name || "").localeCompare(String(b.name || ""))
      })
    }
    return out
  }

  function launchApp(desktopId) {
    var entry = root.entryFor(desktopId)
    if (!entry) return
    var id = String(entry.id || desktopId || "")
    if (!id) return
    // Match AppLibrary: scope gtk-launch under the graphical app slice.
    Util.execDetached("uwsm-app -- gtk-launch " + Util.shellQuote(id + ".desktop"))
    root.close()
  }

  function open(payloadJson) {
    root.refreshIcons(false)
    root.forceOpen = true
  }

  function close() {
    if (root.editing) root.cancelEdit()
    root.forceOpen = false
    var windows = panels.instances
    for (var i = 0; i < windows.length; i++) {
      if (windows[i] && typeof windows[i].dismiss === "function")
        windows[i].dismiss()
    }
  }

  function toggle() {
    if (root.forceOpen || root.anyRevealed()) root.close()
    else root.open("{}")
  }

  function anyRevealed() {
    return root.anyPanelOpen
  }

  // Binding-friendly open state so CursorEdge urgency tracks dwell reveals.
  readonly property bool anyPanelOpen: {
    if (root.forceOpen) return true
    var windows = panels.instances
    for (var i = 0; i < windows.length; i++) {
      if (windows[i] && windows[i].revealed) return true
    }
    return false
  }

  // Active edge for geometry (draft while editing so placement preview applies).
  readonly property string activeEdge: root.editing ? root.draftEdge : root.edge

  readonly property var rightmostScreen: {
    var screens = Quickshell.screens
    var n = screens ? screens.length : 0
    if (n === 0) return null
    var best = screens[0]
    var bestRight = Number(best.x) + Number(best.width)
    for (var i = 1; i < n; i++) {
      var s = screens[i]
      var right = Number(s.x) + Number(s.width)
      if (right > bestRight) {
        best = s
        bestRight = right
      }
    }
    return best
  }

  readonly property var leftmostScreen: {
    var screens = Quickshell.screens
    var n = screens ? screens.length : 0
    if (n === 0) return null
    var best = screens[0]
    var bestLeft = Number(best.x)
    for (var i = 1; i < n; i++) {
      var s = screens[i]
      var left = Number(s.x)
      if (left < bestLeft) {
        best = s
        bestLeft = left
      }
    }
    return best
  }

  // Right → rightmost; left → leftmost; bottom → rightmost (primary strip).
  readonly property var targetScreen: {
    if (root.activeEdge === "left") return root.leftmostScreen
    return root.rightmostScreen
  }

  readonly property var targetScreens: {
    var s = root.targetScreen
    return s ? [s] : []
  }

  // keepLoaded overlays stay mounted; open() is also used by shell summon.
  Component.onCompleted: {
    root.close()
    root.refreshIcons()
  }

  Process {
    id: iconIndexScan
    command: ["bash", "-c", root.iconIndexScanCommand()]
    stdout: SplitParser { onRead: function(line) { root.indexIconLine(line) } }
    onStarted: root.pendingIconIndex = ({})
    onExited: root.iconIndex = root.pendingIconIndex
  }

  Timer {
    id: iconIndexDebounce
    interval: 750
    onTriggered: root.refreshIcons(true)
  }

  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() { iconIndexDebounce.restart() }
  }

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadConfig(text())
    onLoadFailed: root.loadConfig("{}")
    onFileChanged: reload()
  }

  ShellIpc {
    target: "daniel.quickpanel"
    function open(): void { root.open("{}") }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function icons(): string { return root.debugIcons() }
    // Kept for old keybinds/menus: open the panel (widgets are built via /quickpanel).
    function widgets(): void { root.open("{}") }
  }

  // One Hyprland cursor poll for the active edge's screen.
  CursorEdge {
    id: cursorEdge
    active: true
    edgeMode: root.activeEdge
    // Bottom: screen bottom. Proximity is large enough to cover the dock band.
    edgeCoord: {
      var s = root.targetScreen
      if (!s) return 0
      if (root.activeEdge === "left") return Number(s.x)
      if (root.activeEdge === "bottom") return Number(s.y) + Number(s.height)
      return Number(s.x) + Number(s.width)
    }
    proximityPx: root.activeEdge === "bottom" ? 140 : 96
    urgency: root.anyPanelOpen || root.editing
    onMoved: function(x, y) {
      if (root.cursorX !== x) root.cursorX = x
      if (root.cursorY !== y) root.cursorY = y
      var windows = panels.instances
      for (var i = 0; i < windows.length; i++) {
        if (windows[i])
          windows[i].handleCursor(x, y)
      }
    }
  }

  Variants {
    id: panels
    model: root.targetScreens

    delegate: Component {
      QuickpanelWindow {
        required property var modelData

        screen: modelData
        service: root
      }
    }
  }
}
