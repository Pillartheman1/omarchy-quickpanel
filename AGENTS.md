# Agent notes — Omarchy Quickpanel

This repo is the **daniel.quickpanel** Omarchy overlay (`Main.qml`, keepLoaded).
Pinned apps, controls, and a scrollable widget grid live here. End-user install
is via Omarchy (`omarchy plugin add …`); this file is for coding agents and
humans who want to **extend** the panel.

## Widget authoring skill

The full procedure lives in:

```
.grok/skills/quickpanel/SKILL.md
```

Alias: `.grok/skills/quickpanel-widget` → same skill.

Invoke it as **`/quickpanel`** (or `/quickpanel-widget`) once your agent can
see that skill. It covers dual layout (side + bottom), registration in
`Model.js` / `WidgetGrid.qml` / `i18n`, and performance rules (`active` gating).

Shipped widget modules: `widgets/` (`Weather`, `AnalogueClock`, `SpcxStock`,
`SystemGauges`). See also `widgets/README.md`.

## Does the skill install with the plugin?

**The files do.** `omarchy plugin add` clones this tree (including
`.grok/skills/`) into the plugin folder. **Agents do not auto-load it globally**
just because the overlay is enabled — you still need a project session on this
tree, or a user-level skill link (below).

After a normal plugin install the skill path is:

```text
~/.config/omarchy/plugins/daniel.quickpanel/.grok/skills/quickpanel/SKILL.md
```

(Dev symlink setups may point that plugin id at a clone elsewhere; same relative
path under the plugin root.)

## Grok Build

**In this repo (or the installed plugin folder as cwd):** Grok loads
`.grok/skills/` as project skills when the folder is trusted. `/quickpanel`
works in that session.

**From any directory** (user skill):

```bash
# From a clone / project checkout:
ln -sfn "$(pwd)/.grok/skills/quickpanel" ~/.grok/skills/quickpanel

# Or from the Omarchy-installed plugin:
ln -sfn ~/.config/omarchy/plugins/daniel.quickpanel/.grok/skills/quickpanel \
  ~/.grok/skills/quickpanel
```

Then start a new Grok session (or reload skills).

## Other agents (Claude Code, Cursor, Codex, …)

- Open this plugin directory as the workspace so project skills / `AGENTS.md`
  are visible, **or**
- Copy or symlink `.grok/skills/quickpanel` into that tool’s skill root, **or**
- Paste / `@`-reference `.grok/skills/quickpanel/SKILL.md` when asking for a
  new widget.

Omarchy itself does not register community plugin skills into
`/usr/share/omarchy/default/agents/skills/`.

## Quick map

| Path | Role |
|------|------|
| `Main.qml` | Overlay root, pins/widgets config, IPC, cursor edge |
| `QuickpanelWindow.qml` | Panel chrome, edges, slide, edit chrome |
| `ControlsStrip.qml` | Wi‑Fi / BT / audio / night / DND toggles |
| `AppGrid.qml` | Pinned launchers + Add apps |
| `WidgetGrid.qml` | Slot grid; edit drag; widget `Loader`s |
| `Model.js` | Pins/widgets/edge parse + place/move |
| `widgets/` | Widget QML modules |
| `.grok/skills/quickpanel/` | Agent skill for adding widgets |
| `NEO.md` | Handoff brief for Neo (Grok Bot) — current state + hard rules |

Config on disk: `~/.config/omarchy/extensions/daniel.quickpanel.json`.
Reload shell after QML changes if the keepLoaded overlay looks stale:
`omarchy restart shell` (and clear `~/.cache/quickshell/qmlcache` if needed).
