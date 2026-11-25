# Quickpanel

[![Built for Omarchy: Plugin](https://raw.githubusercontent.com/tcballard/omarchy-badges/75975e5b5bf75e7ede3764bcd2950046f7abfe2c/badges/v1/omarchy-plugin.svg)](https://github.com/tcballard/omarchy-badges)

Right-edge hot strip for [Omarchy](https://omarchy.org). Dwell on the right edge of the screen (below the top bar) and a panel slides out with pinned app icons. **Super+Shift+Z** toggles it from the keyboard.

## Install

```bash
omarchy plugin add https://github.com/Pillartheman1/omarchy-quickpanel.git --enable
```

Or for local development:

```bash
ln -sfn ~/Projects/omarchy-quickpanel ~/.config/omarchy/plugins/daniel.quickpanel
omarchy plugin validate ~/.config/omarchy/plugins/daniel.quickpanel
omarchy plugin enable daniel.quickpanel
omarchy restart shell
```

Add a keybind in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + SHIFT + Z", "Quickpanel", "omarchy-shell daniel.quickpanel toggle")
```

Then `hyprctl reload` and check `hyprctl configerrors`.

This is a `keepLoaded` overlay (not a bar widget). The hot edge stays mapped; pinned apps are resolved with DesktopEntries and launched via `gtk-launch`.

## Use

- Move the pointer to the **right edge**, below the top bar, and hold briefly (~200ms). The panel slides in.
- Leave the panel (or press Escape) to tuck it away again.
- **Super+Shift+Z** opens or closes it.
- Left-click an app to launch it.
- Right-click a pinned app to unpin it.
- Use **Add apps**, search, and click a result to pin it (right-click a search row to pin without leaving the picker).

Pins are stored in `~/.config/omarchy/extensions/daniel.quickpanel.json`.

## Widgets

Above the apps: a **Controls** strip (Wi‑Fi, Bluetooth, Sound, Mic, Night light,
Focus/DND). Pinned apps stay in a **2-row** band. Below a divider, a **scrollable
one-column slot grid** fills the rest of the panel (`WidgetGrid.qml`). Long-press
a widget and drop it: on **side edges**, empty cells place and occupied cells
swap; on the **bottom strip**, cards reorder as a packed list. Add as many
widgets as you like; the grid scrolls. Layout is stored next to pins in
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
