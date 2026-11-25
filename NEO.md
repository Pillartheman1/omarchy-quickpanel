# Neo — Quickpanel handoff

You are **Neo**. Daniel is handing you **omarchy-quickpanel** (`daniel.quickpanel`), an Omarchy keepLoaded overlay. Read this file first, then `AGENTS.md`, then the skill and code you are about to touch. Prefer evidence in the tree over inventing features.

Local working copy: `~/Projects/omarchy-quickpanel`  
Runtime symlink: `~/.config/omarchy/plugins/daniel.quickpanel` → that tree  
Pins/widgets config: `~/.config/omarchy/extensions/daniel.quickpanel.json`  
GitHub: `https://github.com/Pillartheman1/omarchy-quickpanel`  
Keybind: `SUPER + SHIFT + Z` → `omarchy-shell daniel.quickpanel toggle`

---

## 1. Mission

Keep the quickpanel polished and extendable: edge dwell, controls, pinned apps, and a dual-orientation widget grid. Ship working QML he can feel after `omarchy restart shell`. Do not publish AUR packages or claim official Omarchy endorsement beyond the existing Built for Omarchy badge.

When Daniel says “continue” without a named task, pick the highest-value open item in §6, do that slice, verify on-device, and stop at a clear exit check.

---

## 2. Reading order

1. **This file (`NEO.md`)** — hard rules, current state, open work.
2. **`AGENTS.md`** — how the `/quickpanel` skill ships with the plugin and how agents load it.
3. **`.grok/skills/quickpanel/SKILL.md`** — widget authoring contract (dual layout, registration, `active` gating).
4. **Code for the surface you are changing** — start at `Main.qml` / `QuickpanelWindow.qml` / `WidgetGrid.qml` / `widgets/`.
5. **`README.md`** — end-user install and usage.

---

## 3. Hard rules (do not violate)

1. **Overlay plugin:** `keepLoaded: true`. No `shell.appLibrary` — use `DesktopEntries` + `gtk-launch` / `uwsm-app`.
2. **Edges:** right / left / bottom. Right/bottom → rightmost output; left → leftmost. Flea’s rail owns the middle Overlay edge on the right — do not steal it.
3. **No closed-state accent edge strip** — invisible hot edge only. Closed slide must include `outerGap` or a clipped border remains.
4. **Never assign `undefined` to an anchor** in a ternary (Quickshell can blank the tree). Prefer explicit x/y/width/height. Do not combine anchors and `x`/`y` on the slide axis.
5. **Bottom strip:** controls | apps+buttons | widgets. Hug height to the paired controls/apps band (`bottomPairedNaturalH` / `pairedH`). No “Quickpanel” title on bottom. Buttons under apps side-by-side.
6. **Widget grid:** side edges = vertical `Column` of `displaySlots` + `slotHeightAt`. Bottom = packed `Row` of widgets (+ one edit spare). **Bottom drag = list reorder** via `moveWidget` / visual index — never slot-based `placeWidget` on the packed Row (that cloned/replaced cards).
7. **`moveWidget` packing:** after splice, pack in array order. Do **not** call `packWidgetSlots` there (it re-sorts by stale slots and undoes the move).
8. **Widgets:** every card must work vertical and horizontal and fill bottom cell height. Gate timers/network/Process with `active` (false until `visibleContent`). Drag ghosts must not instantiate a second live widget.
9. **Stale QML:** if layout edits do not show, clear `~/.cache/quickshell/qmlcache` then `omarchy restart shell`.
10. **Out of scope unless asked:** embedding a terminal/TUI in the overlay; rewriting Omarchy core under `/usr/share/omarchy/`; force-pushing; publishing secrets.

---

## 4. Architecture (current)

```
Main.qml                 Overlay root, config, IPC, CursorEdge, Variants of windows
QuickpanelWindow.qml     Chrome, slide, FocusGrab, bottom hug layout, edit chrome
CursorEdge.qml           Hyprland j/cursorpos poll (near ~45ms / far ~220ms; gated moved)
ControlsStrip.qml        Wi-Fi / BT / sound / mic / night / DND
AppGrid.qml              Pins (2-row side; 4-col compact bottom) + Add apps
WidgetGrid.qml           Slot grid, edit drag, widget Loaders
Model.js                 Pins/widgets/edge normalize, placeWidget, moveWidget, pack
widgets/                 Weather, AnalogueClock, SpcxStock, SystemGauges (+ *Model.js)
.grok/skills/quickpanel/ Agent skill for new widgets
AGENTS.md                Skill install notes for humans/agents
i18n/en.json             Strings
```

### Edge behavior (known-good)

- Dwell ~200ms opens; leave-to-close / Escape / FocusGrab.
- IPC/keybind open: do not arm FocusGrab on the open tick; wait for `pointerEnteredWhileOpen`. `onCleared` must not `closeFully` while `pinnedOpen && !pointerEnteredWhileOpen`.
- Bottom dwell: tall CursorEdge band (~72–140px); visible HoverHandler thinner so dock clicks survive.
- CursorEdge emits `moved` only when near/urgency (+ one near→far cancel). `urgency` = `anyPanelOpen || editing`.

### Widget edit (bottom)

- Visual-index `slotAt` → `moveWidget(from, to)`.
- Spare drop Loader binds `slotIndex` to `occupiedEnd` and `visualIndex` to `horizontalWidgets.length`.
- Side edges still use slot-based `placeWidget`.

---

## 5. Verify before declaring done

1. `omarchy restart shell` (clear qmlcache if UI looks stale).
2. Right, left, and bottom edges: open via dwell and via Super+Shift+Z.
3. Bottom Edit: drag-reorder widgets — no clones; order sticks after drop.
4. Side Edit: place/swap still works; span-2 cards do not overlap.
5. Closed panel: no leftover edge strip; dock still clickable on bottom.
6. Widgets idle when panel hidden (`active` false — no gauge/weather/stock chatter).

---

## 6. Open / follow-up (optional)

Not blockers; pick when asked to continue:

- Add-apps on bottom: expand hug height so search is not squeezed into the short paired band.
- Dead-ish CursorEdge history already cleaned; keep far/near tuning if dwell feels laggy.
- Comment trim: shorten changelog-style notes in WidgetGrid / QuickpanelWindow to short WHY constraints.
- README still says long-press/swap in places — align copy with packed bottom reorder + side place/swap.
- Manifest version: bump when shipping a tagged release.

---

## 7. How to work with Daniel

- Prefer small, reversible QML/JS diffs. Match surrounding Style / Color / Commons patterns.
- After layout or open/close changes, verify on the machine (grim / hyprctl layers `omarchy-quickpanel` if the layer looks wrong).
- Store durable machine facts with SIA (`sia note --from grok`) when a fix is proven; do not store secrets.
- For new widgets: run `/quickpanel` (skill must be visible — see `AGENTS.md`).

---

## 8. Pasteable kickoff (for Grok Bot)

Copy into Neo when starting a session:

> You are Neo on omarchy-quickpanel. Working tree: `~/Projects/omarchy-quickpanel` (plugin symlink `daniel.quickpanel`). Read `NEO.md`, then `AGENTS.md`, then `.grok/skills/quickpanel/SKILL.md`. Repo: https://github.com/Pillartheman1/omarchy-quickpanel. Current state: bottom hug layout, Column side widgets, bottom drag = moveWidget (fixed clone + no-op drop bugs), CursorEdge efficiency gating, AGENTS.md skill shipping notes. Continue from NEO.md §6 unless I name a task. Verify with `omarchy restart shell` and edge dwell + Edit drag before claiming done.
