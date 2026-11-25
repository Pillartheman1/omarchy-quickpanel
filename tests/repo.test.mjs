// Repository and source guards: marketplace structure, and static checks for
// the hard rules in NEO.md that a refactor could silently break.
import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { existsSync, lstatSync, readdirSync, readFileSync } from "node:fs";
import { join, relative } from "node:path";
import { repoRoot } from "./load-qml-js.mjs";

const read = (p) => readFileSync(join(repoRoot, p), "utf8");
const manifest = JSON.parse(read("manifest.json"));

function trackedFiles() {
  try {
    return execFileSync("git", ["-C", repoRoot, "ls-files", "-s"], { encoding: "utf8" })
      .trim().split("\n").filter(Boolean)
      .map((line) => { const [meta, path] = line.split("\t"); return { mode: meta.split(" ")[0], path }; });
  } catch {
    const out = [];
    const walk = (dir) => {
      for (const name of readdirSync(dir)) {
        if (name === ".git" || name === "node_modules") continue;
        const full = join(dir, name);
        const st = lstatSync(full);
        if (st.isDirectory()) walk(full);
        else out.push({ mode: st.isSymbolicLink() ? "120000" : "100644", path: relative(repoRoot, full) });
      }
    };
    walk(repoRoot);
    return out;
  }
}

const sourceFiles = trackedFiles().map((f) => f.path).filter((p) => /\.(qml|js)$/.test(p) && !p.startsWith("tests/"));

test("manifest matches the marketplace schema", () => {
  assert.equal(manifest.schemaVersion, 1);
  for (const field of ["id", "name", "version", "author", "description", "license"]) {
    assert.equal(typeof manifest[field], "string", field);
    assert.ok(manifest[field].trim().length > 0, field);
  }
  assert.match(manifest.id, /^[a-z0-9][a-z0-9._-]*$/);
  assert.ok(!manifest.id.startsWith("omarchy."));
  assert.ok(manifest.description.length <= 500);
  assert.match(manifest.version, /^\d+\.\d+\.\d+$/);
  assert.deepEqual(manifest.kinds, ["overlay"]);
  assert.equal(manifest.keepLoaded, true);
  assert.equal(manifest.entryPoints.overlay, "Main.qml");
  assert.ok(existsSync(join(repoRoot, manifest.entryPoints.overlay)));
});

test("exactly one manifest, at the root", () => {
  const manifests = trackedFiles().filter((f) => /(^|\/)manifest\.json$/i.test(f.path));
  assert.deepEqual(manifests.map((f) => f.path), ["manifest.json"]);
});

test("no symlinks (the marketplace rejects them)", () => {
  assert.deepEqual(trackedFiles().filter((f) => f.mode === "120000").map((f) => f.path), []);
});

test("README has install and removal instructions; LICENSE present", () => {
  const readme = read("README.md");
  assert.match(readme, /omarchy plugin add https:\/\/github\.com\/Pillartheman1\/omarchy-quickpanel/);
  assert.match(readme, /^## Remove/m);
  assert.ok(readme.includes(`omarchy plugin remove ${manifest.id}`));
  assert.match(read("LICENSE"), /MIT License/);
});

test("the plugin writes only its own config file", () => {
  const writers = [];
  for (const p of sourceFiles) {
    const src = read(p);
    for (const m of src.matchAll(/\b(setText|setData|writeAdapter)\s*\(/g)) writers.push(`${p}:${m[1]}`);
  }
  assert.deepEqual(writers, ["Main.qml:setText"]);
  assert.match(read("Main.qml"), /"\/omarchy\/extensions\/daniel\.quickpanel\.json"/);
  assert.match(read("Main.qml"), /configFile\.setText\(/);
});

test("detached commands use argv arrays, never a shell string", () => {
  for (const p of sourceFiles) {
    for (const m of read(p).matchAll(/execDetached\(\s*(.)/g)) {
      assert.equal(m[1], "[", `${p}: execDetached must take an argv array`);
    }
  }
});

test("hard rule: bottom drag uses moveWidget; moveWidget never repacks by stale slots", () => {
  const grid = read("WidgetGrid.qml");
  const endDrag = grid.slice(grid.indexOf("function endDrag()"));
  const horizontal = endDrag.slice(endDrag.indexOf("if (root.horizontal)"), endDrag.indexOf("service.placeWidget"));
  assert.match(horizontal, /service\.moveWidget\(/);
  assert.doesNotMatch(horizontal, /placeWidget/);
  const model = read("Model.js");
  const move = model.slice(model.indexOf("function moveWidget("), model.indexOf("function knownWidgetIds("));
  assert.doesNotMatch(move.replace(/\/\/.*$/gm, ""), /packWidgetSlots\(/);
});

test("every Text renders untrusted strings as plain text", () => {
  for (const p of sourceFiles.filter((f) => f.endsWith(".qml"))) {
    const src = read(p);
    const texts = (src.match(/^\s*Text \{/gm) || []).length;
    const plainText = (src.match(/textFormat:\s*Text\.PlainText/g) || []).length;
    assert.ok(plainText >= texts, `${p}: ${texts} Text items, ${plainText} PlainText`);
  }
});

test("widget work is gated on active", () => {
  for (const p of sourceFiles.filter((f) => /^widgets\/.*\.qml$/.test(f))) {
    const src = read(p);
    assert.match(src, /property bool active: false/, p);
    for (const block of src.split(/\n\s*Timer \{/).slice(1)) {
      const body = block.slice(0, block.indexOf("\n  }"));
      // Manually started timers (no binding / running: false) are fine.
      if (!/running:/.test(body) || /running:\s*false/.test(body)) continue;
      assert.match(body, /running:\s*root\.active/, `${p}: Timer must run only while active`);
    }
  }
});
