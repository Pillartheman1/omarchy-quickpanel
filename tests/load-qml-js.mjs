// Load a QML ".pragma library" JS file into a plain object so node:test can
// exercise it. The files are ES5 function declarations with no QML imports.
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import vm from "node:vm";

export const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");

export function loadQmlJs(relativePath) {
  const source = readFileSync(resolve(repoRoot, relativePath), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
  const context = vm.createContext({});
  vm.runInContext(source, context, { filename: relativePath });
  return context;
}

// vm objects come from another realm; round-trip through JSON so
// assert.deepStrictEqual compares plain data.
export function plain(value) {
  return JSON.parse(JSON.stringify(value));
}
