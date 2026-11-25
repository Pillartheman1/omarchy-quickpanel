---
name: quickpanel
description: >
  Build and wire custom widgets for the Omarchy Quickpanel (daniel.quickpanel).
  Widgets must support both vertical (side edge) and horizontal (bottom strip)
  layouts and fill the cell height in bottom mode. Use when the user runs
  /quickpanel or /quickpanel-widget, or asks to add a clock, weather strip,
  control, or any QML widget to the quickpanel.
---

# Quickpanel widgets

Plugin tree: `~/Projects/omarchy-quickpanel`  
Runtime symlink: `~/.config/omarchy/plugins/daniel.quickpanel`  
Config: `~/.config/omarchy/extensions/daniel.quickpanel.json`  
Open: **Super+Shift+Z** or right-edge dwell (~200ms) on the globally rightmost output.  
Reload: shell often hot-reloads plugin saves; use `omarchy restart shell` if a `keepLoaded` overlay stays on an old tree.

## Panel anatomy

Side edges (left/right), top → bottom inside the card:

1. **Add apps** / **Edit** (Edit → **Undo** + **Done** + placement) — no title headline
2. **ControlsStrip** — Wi‑Fi, Bluetooth, Sound, Mic, Night light, Focus (DND)
3. **AppGrid** — pinned launchers, **max 2 rows**
4. Divider + **WidgetGrid** (scrollable slot grid)

Bottom edge is a **horizontal strip**: controls | apps + Add apps/Edit under the grid (side by side) | widgets. Controls and apps+buttons columns share the same top/bottom (`pairedH`). `WidgetGrid` lays widgets in a sideways `Row` (`horizontal: true`) and pans with `HorizontalFlick` (trackpad/wheel vertical deltas map to `contentX`).

**Edit mode:** drag widgets/apps to rearrange; ✕ deletes. Long-press drag is disabled outside edit mode. Placement buttons set `draftEdge` (`left` / `right` / `bottom`); **Done** commits `edge` to config. **Undo** restores the edit-entry snapshot. Escape / close cancels the edit.

Do not hardcode widgets in `QuickpanelWindow.qml`. Placement belongs to `WidgetGrid`.

## File map

| Path | Role |
|------|------|
| `Main.qml` | Overlay root: pins, widgets, icon index, IPC, cursor edge, rightmost screen |
| `QuickpanelWindow.qml` | PanelWindow: edge dwell, slide, FocusGrab, layout chrome |
| `ControlsStrip.qml` | Quick toggles (Networking / Bluetooth / Pipewire / nightlight / DND) |
| `AppGrid.qml` | Pins (2-row) + Add apps search (`maxRows: 2`) |
| `WidgetGrid.qml` | Scrollable slot grid; edit-mode drag + ✕ delete |
| `Model.js` | Pins + widgets + edge parse/serialize/place; edit snapshot |
| `CursorEdge.qml` | Hyprland `j/cursorpos` poll for active edge |
| `widgets/<Name>.qml` | Widget modules (`AnalogueClock`, `Weather`, …) |
| `i18n/en.json` | User-visible strings |

## Config schema

```json
{
  "pins": ["foot", "brave-browser"],
  "widgets": [
    { "id": "Weather", "span": 1, "slot": 0 },
    { "id": "AnalogueClock", "span": 2, "slot": 2 }
  ],
  "edge": "right"
}
```

| Field | Meaning |
|-------|---------|
| `id` | Widget id — must match `knownWidgetIds()` / `componentFor()` |
| `slot` | Starting index on the scroll axis (0-based) |
| `span` | Slots occupied along that axis (`defaultSpanFor`) — rows on side edges, width units on bottom |
| `edge` | `right`, `left`, or `bottom` — dwell edge and slide direction |

Empty slots are valid drop targets. In **edit mode**, drag → drop on empty **places**; drop on occupied **swaps**. The grid **scrolls** when widgets exceed the viewport (`emptyTail` keeps spare drop slots).

Legacy pins-only configs are seeded once with `defaultWidgets()` on load.

## Dual layout (required)

Every widget must look correct in **both** orientations. The grid mounts the same module in either mode; do not ship side-only or bottom-only widgets.

| Mode | When | Cell size | Scroll |
|------|------|-----------|--------|
| **Vertical** | `edge` left/right | Full panel width × `span` slot heights | Vertical |
| **Horizontal** (bottom) | `edge` bottom | `span` slot widths × **full strip height** | Horizontal |

In bottom mode **every card shares the same vertical space** (the strip height). Short content must not leave a short card while neighbors fill the strip — root must fill the cell, and the inner layout must use the height.

### Root sizing contract

```qml
Item {
  id: root
  property var service: null
  property bool active: false

  width: parent ? parent.width : Style.space(280)
  // Fill the cell when the grid gives a height (both modes). Fall back to
  // implicitHeight only while unbound (edit ghosts / previews).
  height: parent && parent.height > 0 ? parent.height : implicitHeight
  implicitHeight: Style.space(120) // vertical-mode span sizing hint
}
```

Follow SpcxStock / SystemGauges (`height: parent.height` when available). Avoid Weather/AnalogueClock-style roots that only set `implicitHeight` and leave empty band below the card in bottom mode.

### Layout tips for both orientations

- Prefer `anchors.fill` (with margins) or a full-cell `Column`/`Row` over content that only sizes to `implicitHeight` at the top of the cell.
- Flexible middle: pin header/footer with anchors; give charts, dials, and lists `anchors.top`/`bottom` between them so they grow with strip height.
- Wide bottom cells: use horizontal groupings (`Row` of dials, side-by-side stats). Tall side cells: stack sections vertically.
- Keep `implicitHeight` meaningful for vertical `span` defaults; bottom mode ignores it for cell height once `parent.height` is set.
- Verify **Edit → Bottom** and **Edit → Right** (or Left) before calling a widget done.

## Controls strip

`ControlsStrip.qml` sits above apps. Left-click toggles:

| Tile | Mechanism |
|------|-----------|
| Wi‑Fi | `Networking.wifiEnabled` (`Quickshell.Networking`) |
| Bluetooth | `omarchy-bluetooth-power on\|off` (rfkill; matches bar plugin) |
| Sound | `Pipewire.defaultAudioSink.audio.muted` |
| Mic | `Pipewire.defaultAudioSource.audio.muted` |
| Night | `omarchy toggle nightlight` |
| Focus | `omarchy-shell notifications toggleDnd` |

Do not re-implement full network/bluetooth/audio panels here — those stay in the bar plugins.

## Shipped widgets

| Id | Default span | Notes |
|----|--------------|-------|
| `Weather` | 1 | Open-Meteo + Omarchy `weather.json` location (`widgets/WeatherModel.js`) |
| `AnalogueClock` | 2 | Theme via `Color.accent` / `Color.popups.*` / `Color.muted` |
| `SpcxStock` | 2 | Live SPCX (SpaceX) quote + sparkline; CNBC quote + Nasdaq chart |
| `SystemGauges` | 1 | Dual analogue CPU + RAM; stacked on bottom, side-by-side on left/right; `/proc/stat` + `/proc/meminfo` |

## How to add a widget

1. **Create** `widgets/<Name>.qml` — root `Item` following the **Dual layout** sizing contract above. Expose:
   - `property var service` — for `service.strings.t(...)` and helpers
   - `property bool active` — pause timers/network when the panel is hidden
2. **Optimize for both orientations** — fill the cell; reflow with anchors/`Row`/`Column` so side (tall) and bottom (full-height strip) both look intentional. See **Dual layout**.
3. **Style** with Omarchy kit only: `qs.Commons` / `qs.Ui` (`Style`, `Color`, `Util`, `Button`, `BorderSurface`). Motion under 300ms via `Style.duration(...)`.
4. **Register** in all three places:
   - `Model.js` → `knownWidgetIds()`, `defaultSpanFor(id)`, and `defaultWidgets()` if it should ship on
   - `WidgetGrid.qml` → `componentFor()` switch + `Component { id: nameComponent; Name {} }`
   - `i18n/en.json` → labels; read with `service.strings.t("key")` and `textFormat: Text.PlainText`
5. **Persist** only under the extensions JSON via `Model.js` / `Main.qml` (`addWidget`, `placeWidget`, `saveWidgets`). Never write to `/usr/share/omarchy/`.
6. **Verify**: open the panel, confirm paint, use **Edit** to drag/delete, try **Left/Right and Bottom** placement + Done (same vertical fill on bottom for every card). Restart the shell if needed.

### Main.qml widget API

| Call | Effect |
|------|--------|
| `addWidget(id, span?, slot?)` | Append (span defaults via `defaultSpanFor`) |
| `removeWidget(id)` | Remove from config |
| `placeWidget(id, slot, persist?)` | Move/swap; `persist: false` while dragging |
| `saveWidgets(list)` | Replace list and write config |
| `saveConfig()` | Write pins + widgets |

## Performance (required for new widgets)

- Default `property bool active: false`. The grid sets `active` only while the panel is shown. Timers, Process, and network must key off `active`.
- No always-on startup Timers that fetch while inactive. Prefer `onActiveChanged` + FileView `onLoaded` gated by `active`.
- Debounce or throttle network (Weather/Spcx-style `lastFetchAt` / min interval). Heavy chart data may refresh slower than quotes.
- Canvas: paint static layers once (palette/size); tick only the dynamic layer. Cache `Style.space(...)` outside `onPaint`.
- Prefer one Process per sample over multiple forks (see SystemGauges).
- Drag ghosts must not instantiate a second live widget (no duplicate timers/network).

## Widget authoring constraints

- **Dual layout** — every widget must work in vertical (side) and horizontal (bottom) cells; bottom cards all share the strip height. See **Dual layout**.
- Overlay plugins do **not** get `shell.appLibrary`. Resolve apps with `DesktopEntries`; launch with `uwsm-app -- gtk-launch <id>.desktop`.
- Never size a Column child as `parent.height - y` — it collapses to 0. Use sibling `implicitHeight` or anchors between fixed chrome (`AppGrid` height from `maxRows`, `WidgetGrid` fills the rest).
- Slot axis follows the edge: `span` / `slot` are rows on the side, width units on the bottom. Do not invent a separate multi-column grid unless asked.
- Icons: use `Main.qml` `iconSource` / `iconFor` (on-disk index) over bare `Quickshell.iconPath`; pin `Image`s load with `asynchronous: false`.
- Network/IPC text is untrusted → always `textFormat: Text.PlainText`.
- Panel mounts on the edge’s target output (right/bottom → rightmost screen; left → leftmost).
- Do not embed a terminal/agent TUI in the overlay (opaque Foot under Overlay produced a dead black box). Widgets are QML; author them with this skill.

## Ask the user

If the request is vague, ask what the widget should show or control, then build it. Keep the 2-row app band usable; new widgets go in the slot grid below the divider.
