import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const script = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  'check-actions-pinned.mjs',
);

test('real repo workflows pass the pin check', () => {
  const result = spawnSync(process.execPath, [script], { encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.match(result.stdout, /OK:/);
});

test('detects floating tags in a synthetic line', () => {
  const USES_RE = /^\s*-?\s*uses:\s*(.+?)\s*(?:#.*)?$/;
  const SHA_RE = /^[0-9a-f]{40}$/i;
  const LOCAL_RE = /^\.\//;
  const lines = [
    '      - uses: actions/checkout@v6',
    '      - uses: actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803 # v6.1.0',
    '    uses: ./.github/actions/install-tools',
  ];
  const bad = [];
  for (const line of lines) {
    const match = line.match(USES_RE);
    if (!match) continue;
    let value = match[1].trim();
    if (LOCAL_RE.test(value)) continue;
    const ref = value.slice(value.lastIndexOf('@') + 1);
    if (!SHA_RE.test(ref)) bad.push(ref);
  }
  assert.deepEqual(bad, ['v6']);
});
