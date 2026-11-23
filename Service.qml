import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import "Model.js" as Model

Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property var appLibrary: shell ? shell.appLibrary : null
  readonly property string configPath: {
    var configHome = Quickshell.env("XDG_CONFIG_HOME")
    if (!configHome || configHome === "")
      configHome = Quickshell.env("HOME") + "/.config"
    return configHome + "/omarchy/extensions/daniel.quickpanel.json"
  }

  property var pins: []
  property bool forceOpen: false

  property alias strings: stringsCatalog

  Commons.Translations {
    id: stringsCatalog
    directory: Qt.resolvedUrl("i18n")
  }

  function loadConfig(raw) {
    root.pins = Model.parseConfig(raw).pins
  }

  function savePins(nextPins) {
    root.pins = Array.isArray(nextPins) ? nextPins.slice() : []
    configFile.setText(Model.serializeConfig(root.pins))
  }

  function pinApp(desktopId) {
    root.savePins(Model.withPin(root.pins, desktopId))
  }

  function unpinApp(desktopId) {
    root.savePins(Model.withoutPin(root.pins, desktopId))
  }

  function isPinned(desktopId) {
    return Model.isPinned(root.pins, desktopId)
  }

  function entryFor(desktopId) {
    var id = String(desktopId || "")
    if (!id) return null
    var entry = DesktopEntries.byId(id)
    if (entry) return entry
    return DesktopEntries.heuristicLookup(id)
  }

  function iconFor(desktopId) {
    var entry = root.entryFor(desktopId)
    var icon = entry && entry.icon ? entry.icon : String(desktopId || "")
    if (root.appLibrary && typeof root.appLibrary.iconSource === "function")
      return root.appLibrary.iconSource(icon)
    return Quickshell.iconPath(icon, true)
  }

  function nameFor(desktopId) {
    var entry = root.entryFor(desktopId)
    if (entry && entry.name) return String(entry.name)
    if (root.appLibrary && typeof root.appLibrary.entryName === "function" && entry)
      return String(root.appLibrary.entryName(entry) || desktopId)
    return String(desktopId || "")
  }

  function launchApp(desktopId) {
    var entry = root.entryFor(desktopId)
    if (!entry) return
    if (root.appLibrary && typeof root.appLibrary.launch === "function")
      root.appLibrary.launch(entry.id, entry.name)
    root.close()
  }

  function open() {
    root.forceOpen = true
  }

  function close() {
    root.forceOpen = false
    var windows = panels.instances
    for (var i = 0; i < windows.length; i++) {
      if (windows[i] && typeof windows[i].dismiss === "function")
        windows[i].dismiss()
    }
  }

  function toggle() {
    if (root.forceOpen || root.anyRevealed()) root.close()
    else root.open()
  }

  function anyRevealed() {
    var windows = panels.instances
    for (var i = 0; i < windows.length; i++) {
      if (windows[i] && windows[i].revealed) return true
    }
    return false
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
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
  }

  Variants {
    id: panels
    model: Quickshell.screens

    delegate: Component {
      QuickpanelWindow {
        required property var modelData

        screen: modelData
        service: root
      }
    }
  }
}
