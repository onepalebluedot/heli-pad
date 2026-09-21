import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

// Load the worker as ESM without changing its deployment packaging.
const source = await readFile(new URL('./src/index.js', import.meta.url), 'utf8');
const { default: worker } = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);
const env = {
  HELIPAD_MODEL: 'test-model', HELIPAD_TOKENS: JSON.stringify({ fixture: 'test-device' }),
  OPENAI_API_KEY: 'dummy', DAILY_LIMIT: '50',
  USAGE: { get: async () => null, put: async () => {} },
};
function request(names, token = 'fixture') {
  return new Request('https://relay.invalid/assistant/respond', {
    method: 'POST', headers: { authorization: `Bearer ${token}` },
    body: JSON.stringify({ model: 'test-model', store: false, tools: names.map(name => ({ type: 'function', name })) }),
  });
}
test('list read and preview tools reach upstream; unknown tools and missing authentication do not', async () => {
  const original = globalThis.fetch;
  let calls = 0;
  globalThis.fetch = async () => { calls++; return new Response('{}'); };
  try {
    const accepted = await worker.fetch(request(['read_household_lists', 'preview_add_list_items']), env);
    assert.equal(accepted.status, 200);
    assert.equal(calls, 1);
    const unknown = await worker.fetch(request(['delete_database']), env);
    assert.equal(unknown.status, 400);
    const rejected = await worker.fetch(request(['read_household_lists'], 'wrong'), env);
    assert.equal(rejected.status, 401);
    assert.equal(calls, 1);
  } finally { globalThis.fetch = original; }
});
