#!/usr/bin/env node
/**
 * Fail if any third-party GitHub Action `uses:` value is not a full 40-char
 * commit SHA. Local composite actions (`./.github/...`) are allowed.
 *
 * Scans `.github/workflows/` and `.github/actions/`. Version comments
 * (`# vX.Y.Z`) are recommended but not required by this check.
 */
import { readdir, readFile, access } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const scanRoots = [
  path.join(root, '.github', 'workflows'),
  path.join(root, '.github', 'actions'),
];

const USES_RE = /^\s*-?\s*uses:\s*(.+?)\s*(?:#.*)?$/;
const SHA_RE = /^[0-9a-f]{40}$/i;
const LOCAL_RE = /^\.\//;

const failures = [];

async function collectYamlFiles(dir) {
  try {
    await access(dir);
  } catch {
    return [];
  }
  const entries = await readdir(dir, { withFileTypes: true });
  const files = [];
  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      files.push(...(await collectYamlFiles(full)));
      continue;
    }
    if (
      entry.isFile() &&
      (entry.name.endsWith('.yml') ||
        entry.name.endsWith('.yaml') ||
        entry.name === 'action.yml' ||
        entry.name === 'action.yaml')
    ) {
      files.push(full);
    }
  }
  return files;
}

const files = (
  await Promise.all(scanRoots.map((dir) => collectYamlFiles(dir)))
)
  .flat()
  .sort();

for (const filePath of files) {
  const rel = path.relative(root, filePath);
  const text = await readFile(filePath, 'utf8');
  const lines = text.split(/\r?\n/);
  for (let i = 0; i < lines.length; i++) {
    const match = lines[i].match(USES_RE);
    if (!match) continue;
    let value = match[1].trim();
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    if (LOCAL_RE.test(value)) continue;
    const at = value.lastIndexOf('@');
    if (at === -1) {
      failures.push(`${rel}:${i + 1}: missing @ref in ${value}`);
      continue;
    }
    const ref = value.slice(at + 1);
    if (!SHA_RE.test(ref)) {
      failures.push(
        `${rel}:${i + 1}: unpinned action ref "${ref}" (want 40-char commit SHA) in ${value}`,
      );
    }
  }
}

if (failures.length > 0) {
  console.error('GitHub Actions pin check failed:');
  for (const line of failures) console.error(`  ${line}`);
  process.exit(1);
}

console.log(
  `OK: ${files.length} workflow/action file(s); all third-party actions are SHA-pinned.`,
);
