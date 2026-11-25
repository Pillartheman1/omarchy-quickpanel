import { test } from "node:test";
import assert from "node:assert/strict";
import { loadQmlJs, plain } from "./load-qml-js.mjs";

const W = loadQmlJs("widgets/WeatherModel.js");
const G = loadQmlJs("widgets/SystemGaugesModel.js");
const S = loadQmlJs("widgets/SpcxStockModel.js");

test("WeatherModel.locationKey identifies a location, empty when unset", () => {
  assert.equal(W.locationKey({ latitude: 52.52, longitude: 13.406 }), "52.52,13.41");
  assert.equal(W.locationKey({ latitude: "52.521", longitude: "13.4049" }), "52.52,13.40");
  assert.equal(W.locationKey({ latitude: null, longitude: 1 }), "");
  assert.equal(W.locationKey({ latitude: "x", longitude: 1 }), "");
  assert.equal(W.locationKey(null), "");
  assert.notEqual(W.locationKey({ latitude: 40.71, longitude: -74.0 }), W.locationKey({ latitude: 52.52, longitude: 13.4 }));
});

test("WeatherModel.parseLocationFile tolerates bad input", () => {
  assert.deepEqual(plain(W.parseLocationFile("garbage")), { name: "", latitude: null, longitude: null });
  assert.deepEqual(plain(W.parseLocationFile('{"name":" Berlin ","latitude":"52.5","longitude":13.4}')),
    { name: "Berlin", latitude: 52.5, longitude: 13.4 });
  assert.equal(W.isAutoLocation(W.parseLocationFile("")), true);
});

test("WeatherModel.parseForecast returns null on bad JSON", () => {
  assert.equal(W.parseForecast("<html>"), null);
  assert.equal(plain(W.parseForecast('{"current":{"temperature_2m":3}}')).current.temperature_2m, 3);
});

test("SystemGaugesModel: CPU percent from two /proc/stat samples", () => {
  const a = G.parseCpuLine("cpu  100 0 100 800 0 0 0 0 0 0\ncpu0 1 2 3 4");
  const b = G.parseCpuLine("cpu  150 0 150 900 0 0 0 0 0 0");
  assert.equal(Math.round(G.cpuPercent(a, b)), 50);
  assert.ok(Number.isNaN(G.cpuPercent(b, a)));
  assert.equal(G.parseCpuLine("nothing here"), null);
});

test("SystemGaugesModel: meminfo", () => {
  const m = plain(G.parseMeminfo("MemTotal:       16000000 kB\nMemFree: 1 kB\nMemAvailable:    4000000 kB\n"));
  assert.equal(m.usedKb, 12000000);
  assert.equal(Math.round(m.percent), 75);
  assert.equal(G.parseMeminfo("MemTotal: 0 kB"), null);
});

test("SpcxStockModel: untrusted responses never throw", () => {
  for (const raw of ["", "<html>", "{}", "[]", '{"FormattedQuoteResult":{"FormattedQuote":[{"symbol":"EVIL"}]}}']) {
    assert.equal(S.parseCnbcQuote(raw), null, raw);
    assert.deepEqual(plain(S.parseNasdaqChart(raw)), []);
  }
  const pts = plain(S.parseNasdaqChart(JSON.stringify({ data: { chart: Array.from({ length: 200 }, (_, i) => ({ y: i })) } })));
  assert.equal(pts.length, 48);
  assert.equal(pts[0], 0);
  assert.equal(pts.at(-1), 199);
});
