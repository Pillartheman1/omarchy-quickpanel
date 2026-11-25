import { test } from "node:test";
import assert from "node:assert/strict";
import { loadQmlJs, plain } from "./load-qml-js.mjs";

const M = loadQmlJs("Model.js");
const ids = (list) => plain(list).map((w) => w.id);
const slots = (list) => plain(list).map((w) => [w.id, w.slot, w.span]);

const three = [
  { id: "Weather", span: 1, slot: 0 },
  { id: "AnalogueClock", span: 2, slot: 1 },
  { id: "SystemGauges", span: 1, slot: 3 },
];

test("parseConfigResult: valid config", () => {
  const r = plain(M.parseConfigResult(JSON.stringify({
    pins: ["foot", " foot ", "", "brave"],
    widgets: [{ id: "Weather", span: 1, slot: 0 }],
    edge: "Bottom",
  })));
  assert.equal(r.ok, true);
  assert.equal(r.hasWidgets, true);
  assert.deepEqual(r.pins, ["foot", "brave"]);
  assert.equal(r.edge, "bottom");
});

test("parseConfigResult: empty or missing file is a readable new config", () => {
  for (const raw of ["", "   ", undefined, null, "{}"]) {
    const r = plain(M.parseConfigResult(raw));
    assert.equal(r.ok, true, `raw=${JSON.stringify(raw)}`);
    assert.equal(r.hasWidgets, false);
    assert.deepEqual(r.pins, []);
    assert.equal(r.edge, "right");
  }
});

test("parseConfigResult: unparseable or non-object text is not ok (must not be saved over)", () => {
  for (const raw of ['{"pins": ["foot"', "not json", "[1,2]", "42", '"str"', "null", "true"]) {
    assert.equal(M.parseConfigResult(raw).ok, false, `raw=${raw}`);
  }
});

test("parseConfigResult: pins-only config reports hasWidgets=false but keeps pins", () => {
  const r = plain(M.parseConfigResult('{"pins":["foot"]}'));
  assert.equal(r.ok, true);
  assert.equal(r.hasWidgets, false);
  assert.deepEqual(r.pins, ["foot"]);
});

test("serializeConfig round-trips through parseConfigResult", () => {
  const text = M.serializeConfig(["foot"], three, "left");
  assert.ok(text.endsWith("\n"));
  const r = plain(M.parseConfigResult(text));
  assert.equal(r.ok, true);
  assert.deepEqual(r.pins, ["foot"]);
  assert.deepEqual(slots(r.widgets), slots(three));
  assert.equal(r.edge, "left");
  assert.deepEqual(Object.keys(JSON.parse(text)).sort(), ["edge", "pins", "widgets"]);
});

test("normalizeEdge falls back to right", () => {
  assert.equal(M.normalizeEdge("LEFT "), "left");
  assert.equal(M.normalizeEdge("top"), "right");
  assert.equal(M.normalizeEdge(undefined), "right");
});

test("normalizeWidgets: dedupes, defaults span, auto-assigns slots", () => {
  const r = plain(M.normalizeWidgets(["Weather", { id: "AnalogueClock" }, "Weather", { id: "" }, { id: "SpcxStock", span: 3 }]));
  assert.deepEqual(r, [
    { id: "Weather", span: 1, slot: 0 },
    { id: "AnalogueClock", span: 2, slot: 1 },
    { id: "SpcxStock", span: 3, slot: 3 },
  ]);
});

test("moveWidget: bottom reorder by visual index, packed in splice order", () => {
  const r = M.moveWidget(three, 0, 2);
  assert.deepEqual(slots(r), [["AnalogueClock", 0, 2], ["SystemGauges", 2, 1], ["Weather", 3, 1]]);
  const back = M.moveWidget(three, 2, 0);
  assert.deepEqual(slots(back), [["SystemGauges", 0, 1], ["Weather", 1, 1], ["AnalogueClock", 2, 2]]);
});

test("moveWidget: the reorder sticks (packWidgetSlots on the pre-pack order would undo it)", () => {
  const moved = M.moveWidget(three, 0, 2);
  assert.deepEqual(ids(moved), ["AnalogueClock", "SystemGauges", "Weather"]);
  // Hard rule: never repack by stale slots after a splice. This shows why.
  const stale = [three[1], three[2], three[0]];
  assert.deepEqual(ids(M.packWidgetSlots(stale)), ids(three));
});

test("moveWidget: uses visual (slot) order even if the array is unsorted", () => {
  const shuffled = [three[2], three[0], three[1]];
  assert.deepEqual(ids(M.moveWidget(shuffled, 0, 1)), ["AnalogueClock", "Weather", "SystemGauges"]);
});

test("moveWidget: no clones, no losses, no-op and clamping", () => {
  for (let from = 0; from < 3; from++) {
    for (let to = -1; to < 5; to++) {
      const r = plain(M.moveWidget(three, from, to));
      assert.equal(r.length, 3);
      assert.deepEqual([...ids(r)].sort(), [...ids(three)].sort());
      let cursor = 0;
      for (const w of r) { assert.equal(w.slot, cursor); cursor += w.span; }
    }
  }
  assert.deepEqual(slots(M.moveWidget(three, 1, 1)), slots(three));
  assert.deepEqual(slots(M.moveWidget(three, 7, 0)), slots(three));
});

test("placeWidget: drop on empty slot places there", () => {
  const r = M.placeWidget(three, "Weather", 6);
  assert.deepEqual(plain(r).find((w) => w.id === "Weather").slot, 6);
});

test("placeWidget: drop on occupied slot swaps start slots", () => {
  const r = plain(M.placeWidget([{ id: "A", span: 1, slot: 0 }, { id: "B", span: 1, slot: 1 }], "A", 1));
  assert.deepEqual(r.map((w) => [w.id, w.slot]), [["A", 1], ["B", 0]]);
});

test("placeWidget: drop on own cells is a no-op", () => {
  assert.deepEqual(slots(M.placeWidget(three, "AnalogueClock", 2)), slots(three));
});

test("placeWidget: resolves span overlaps without dropping widgets", () => {
  const r = plain(M.placeWidget(three, "SystemGauges", 1));
  assert.equal(r.length, 3);
  for (let i = 0; i < r.length; i++) {
    for (let j = i + 1; j < r.length; j++) {
      assert.equal(M.rangesOverlap(r[i].slot, r[i].span, r[j].slot, r[j].span), false, JSON.stringify(r));
    }
  }
});

test("placeWidget: unknown id leaves the list unchanged", () => {
  assert.deepEqual(slots(M.placeWidget(three, "Nope", 0)), slots(three));
});

test("withWidget / withoutWidget", () => {
  const added = M.withWidget(three, "SpcxStock", 2);
  assert.deepEqual(plain(added).at(-1), { id: "SpcxStock", span: 2, slot: 4 });
  assert.deepEqual(slots(M.withWidget(three, "Weather", 1)), slots(three));
  const removed = M.withoutWidget(three, "Weather");
  assert.deepEqual(slots(removed), [["AnalogueClock", 0, 2], ["SystemGauges", 2, 1]]);
});

test("pins helpers", () => {
  assert.deepEqual(plain(M.movePin(["a", "b", "c"], 0, 2)), ["b", "c", "a"]);
  assert.deepEqual(plain(M.movePin(["a", "b"], 0, 9)), ["b", "a"]);
  assert.deepEqual(plain(M.withPin(["a"], "a")), ["a"]);
  assert.deepEqual(plain(M.withPin(["a"], " b ")), ["a", "b"]);
  assert.deepEqual(plain(M.withoutPin(["a", "b"], "a")), ["b"]);
  assert.equal(M.isPinned(["a"], "a"), true);
  assert.equal(M.isPinned(["a"], ""), false);
});

test("cloneSnapshot is independent of later edits (Undo scope)", () => {
  const pins = ["a", "b"];
  const widgets = three.map((w) => ({ ...w }));
  const snap = M.cloneSnapshot(pins, widgets, "bottom");
  pins.push("c");
  widgets[0].slot = 9;
  assert.deepEqual(plain(snap.pins), ["a", "b"]);
  assert.equal(plain(snap.widgets)[0].slot, 0);
  assert.equal(snap.edge, "bottom");
});

test("registry: every known widget has a default span; defaults are known", () => {
  const known = plain(M.knownWidgetIds());
  for (const id of known) assert.ok(M.defaultSpanFor(id) >= 1);
  for (const w of plain(M.defaultWidgets())) assert.ok(known.includes(w.id));
});
