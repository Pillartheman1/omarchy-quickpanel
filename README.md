# Quickpanel

[![Built for Omarchy: Plugin](https://raw.githubusercontent.com/tcballard/omarchy-badges/75975e5b5bf75e7ede3764bcd2950046f7abfe2c/badges/v1/omarchy-plugin.svg)](https://github.com/tcballard/omarchy-badges)

Hot-edge quick panel for [Omarchy](https://omarchy.org). Dwell on the right, left, or bottom edge of the screen and a panel slides out with quick controls, pinned apps, and widgets. **Super+Shift+Z** toggles it from the keyboard (keybind below).

**ID:** `daniel.quickpanel`

Unofficial. Not affiliated with Omarchy. Plugins run unsandboxed inside `omarchy-shell`; only add this repo if you trust it.

## Install

```bash
omarchy plugin add https://github.com/Pillartheman1/omarchy-quickpanel.git --enable
```

Or for local development, from a clone:

```bash
ln -sfn "$(pwd)" ~/.config/omarchy/plugins/daniel.quickpanel
omarchy plugin validate ~/.config/omarchy/plugins/daniel.quickpanel
omarchy plugin enable daniel.quickpanel
omarchy restart shell
```

`omarchy plugin add` does not install keybinds. Add one in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + SHIFT + Z", "Quickpanel", "omarchy-shell daniel.quickpanel toggle")
```

Then `hyprctl reload` and check `hyprctl configerrors`. After plugin updates, run `omarchy restart shell` so the overlay is not left on stale QML.

This is a `keepLoaded` overlay (not a bar widget). The hot edge stays mapped; pinned apps are resolved with DesktopEntries and launched via `gtk-launch`.

## Use

- Move the pointer to the panel's edge and hold briefly (~200ms). The panel slides in. Right is the default; **Edit → Placement** switches to left or bottom. Right and bottom use the rightmost monitor, left uses the leftmost. Side edges start below the top bar.
- Leave the panel (or press Escape) to tuck it away again.
- **Super+Shift+Z** opens or closes it.
- Left-click an app to launch it.
- Right-click a pinned app to unpin it.
- Use **Add apps**, search, and click a result to pin it. Clicking a pinned result (marked ●) unpins it. The picker stays open until you press **Done**.

### Edit mode

Press **Edit** (top of the panel on side edges, under the apps on the bottom strip).

- Drag apps or widgets to rearrange them. Dragging only works in Edit mode; there is no long-press, a drag starts once you move the pointer a few pixels.
- **✕** on an app or widget removes it.
- **Placement** (Left / Right / Bottom) picks the edge.
- **Done** saves. **Undo** goes back to how things were when you pressed Edit. Escape or closing the panel cancels the edit and reverts it.

Pins are stored in `~/.config/omarchy/extensions/daniel.quickpanel.json`.

## Widgets

Above the apps: a **Controls** strip (Wi‑Fi, Bluetooth, Sound, Mic, Night light,
Focus/DND). Pinned apps stay in a **2-row** band. Below a divider, a **scrollable
one-column slot grid** fills the rest of the panel (`WidgetGrid.qml`). On the
bottom edge the layout is one strip instead: controls | apps | widgets, with the
widgets in a horizontal row.

Rearranging widgets in Edit mode:

- **Side edges:** drop a widget on an empty slot to place it there, or on
  another widget to swap the two.
- **Bottom strip:** widgets are a packed list. Drop a card on another card's
  position to move it there (the rest shift over), or on the empty slot at the
  end to move it last.

Add as many widgets as you like; the grid scrolls. Layout is stored next to pins in
`~/.config/omarchy/extensions/daniel.quickpanel.json`:

```json
{
  "pins": ["foot", "..."],
  "widgets": [
    { "id": "Weather", "span": 1, "slot": 0 },
    { "id": "AnalogueClock", "span": 2, "slot": 2 }
  ]
}
```

Shipped widgets include **Weather**, **AnalogueClock**, **SpcxStock**, and
**SystemGauges**. Build more with the agent skill:

```
/quickpanel
```

The skill ships **with the plugin** at `.grok/skills/quickpanel/SKILL.md` (also
present after `omarchy plugin add` under
`~/.config/omarchy/plugins/daniel.quickpanel/.grok/skills/quickpanel/`).

Agents do not load it globally just because the overlay is enabled. For install
options (Grok project session, user symlink, other agents), see **[AGENTS.md](AGENTS.md)**.

## Config, network, and dependencies

The plugin writes one file: `~/.config/omarchy/extensions/daniel.quickpanel.json` (pins, widget layout, edge). Nothing is written until you change something, and nothing is saved during Edit mode until you press **Done**. If that file exists but is not valid JSON (say, mid-edit by hand), the panel keeps what it has, logs a warning, and does not save until the file parses again, so your pins are never overwritten.

It reads, but never writes, Omarchy's weather location (`~/.local/state/omarchy/settings/weather.json`), `/proc/stat` and `/proc/meminfo` (System gauges), and the cursor position from Hyprland's local socket (edge dwell).

Network use, only while the panel is open:

- **Weather** (on by default): `api.open-meteo.com` with your Omarchy weather location's coordinates. With no location set, `geo.omarchy.org` is asked for an IP-based location, the same way Omarchy's own weather does it. At most once a minute, refreshed every 15 minutes.
- **SPCX** (off by default; add it in the config): `quote.cnbc.com` (quote, every 60s) and `api.nasdaq.com` (chart, every 5 min). No account or API key.

No telemetry and no API keys.

Commands it runs, all shipped with Omarchy: `curl` (widgets above), `uwsm-app` + `gtk-launch` (launch pinned apps), `omarchy-bluetooth-power`, `omarchy-toggle-nightlight`, and `omarchy-shell notifications` (Controls strip toggles and status).

## Develop

```bash
scripts/check.sh   # node tests + QML syntax check (qmllint if installed)
```

Tests need Node.js 20+ and cover the config parser, widget move/place/pack logic, the widget data parsers, and repo guards (single root manifest, no symlinks, only the plugin's own config is written, argv-only commands, plain-text rendering).

## Remove

```bash
omarchy plugin remove daniel.quickpanel
```

Remove the Super+Shift+Z bind from `bindings.lua` if you added it. Your pins and layout stay in `~/.config/omarchy/extensions/daniel.quickpanel.json`; delete that file if you do not want them kept.
