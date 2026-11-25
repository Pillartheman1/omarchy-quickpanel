# Quickpanel widgets

Drop custom QML widgets here. They appear in the slot grid (vertical on side
edges, horizontal strip on bottom). Edit mode: drag to place or swap.

Every widget must work in **both** orientations and fill the cell — on bottom,
all cards share the same strip height. Details and the root sizing contract are
in the project skill (`.grok/skills/quickpanel/SKILL.md`). How to expose that
skill to Grok or other agents after install: see root **[AGENTS.md](../AGENTS.md)**.

In any coding agent that can see the skill, run:

```
/quickpanel
```

That builds widgets under `widgets/`, registers them in `Model.js` +
`WidgetGrid.qml`, and wires i18n.
