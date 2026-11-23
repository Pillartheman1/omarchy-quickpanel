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
omarchy-shell shell rescanPlugins
```

Add a keybind in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + SHIFT + Z", "Quickpanel", "omarchy-shell daniel.quickpanel toggle")
```

Then `hyprctl reload` and check `hyprctl configerrors`.

## Use

- Move the pointer to the **right edge**, below the top bar, and hold briefly (~200ms). The panel slides in.
- Leave the panel (or press Escape) to tuck it away again.
- **Super+Shift+Z** opens or closes it.
- Left-click an app to launch it.
- Right-click a pinned app to unpin it.
- Use **Add apps**, search, and click a result to pin it (right-click a search row to pin without leaving the picker).

Pins are stored in `~/.config/omarchy/extensions/daniel.quickpanel.json`.

## v1 scope

Pinned apps and a themed scaffold. Status widgets, system toggles, and custom commands are left for later fills of the same panel.
