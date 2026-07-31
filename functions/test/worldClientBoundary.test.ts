import assert from "node:assert/strict";
import {readdirSync, readFileSync} from "node:fs";
import {join, relative} from "node:path";
import test from "node:test";

const ALLOWED_RAW_CLIENT_FILES = new Set([
  "platform/worldBucketProvider.ts",
  "platform/worldFirestoreProvider.ts",
]);

test("raw Firebase client construction stays in platform adapters", () => {
  const sourceRoot = join(process.cwd(), "src");
  const violations: string[] = [];

  for (const file of typescriptFiles(sourceRoot)) {
    const sourcePath = relative(sourceRoot, file);
    if (ALLOWED_RAW_CLIENT_FILES.has(sourcePath)) continue;

    const source = readFileSync(file, "utf8");
    if (/\bgetFirestore\s*\(/.test(source)) {
      violations.push(`${sourcePath}: getFirestore()`);
    }
    if (/\bgetStorage\s*\(/.test(source)) {
      violations.push(`${sourcePath}: getStorage()`);
    }
  }

  assert.deepEqual(violations, []);
});

test("regional callables use the world-routing wrapper", () => {
  const sourceRoot = join(process.cwd(), "src");
  const violations: string[] = [];

  for (const file of typescriptFiles(sourceRoot)) {
    const sourcePath = relative(sourceRoot, file);
    if (sourcePath === "platform/worldCallable.ts") continue;

    const source = readFileSync(file, "utf8");
    if (/from ["']firebase-functions\/v2\/https["']/.test(source) &&
        /\bonCall\b/.test(source)) {
      violations.push(sourcePath);
    }
  }

  assert.deepEqual(violations, []);
});

/**
 * Returns every TypeScript source file below a directory.
 *
 * @param {string} directory Directory to scan.
 * @return {string[]} Absolute source file paths.
 */
function typescriptFiles(directory: string): string[] {
  return readdirSync(directory, {withFileTypes: true}).flatMap((entry) => {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) return typescriptFiles(path);
    return entry.isFile() && entry.name.endsWith(".ts") ? [path] : [];
  });
}
