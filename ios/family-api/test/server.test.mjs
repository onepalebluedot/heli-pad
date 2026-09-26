import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { createHandler, safeKind, sha256, uuid } from '../src/server.mjs';

const familyID = '7e7fb77a-2c23-4cce-b1e1-b04023abe825';

async function withServer(query, action, options = {}) {
  const server = http.createServer(createHandler({ query }, {
    appleBundleID: 'com.onepalebluedot.helipad', ...options
  }));
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  try { await action(`http://127.0.0.1:${server.address().port}`); }
  finally { await new Promise(resolve => server.close(resolve)); }
}

test('only known document kinds and UUID family IDs are accepted', () => {
  assert.equal(safeKind('household'), true);
  assert.equal(safeKind('lists'), true);
  assert.equal(safeKind('sessions'), false);
  assert.equal(uuid(familyID), true);
  assert.equal(uuid('../other'), false);
  assert.equal(sha256('secret'), sha256('secret'));
});

test('Apple sign-in consumes its challenge and creates a usable session', async () => {
  let challengeHash;
  let consumed = false;
  let sessionHash;
  await withServer(async (sql, params) => {
    if (sql.includes('INSERT INTO helipad_auth_challenge')) { challengeHash = params[0]; return { rows: [] }; }
    if (sql.includes('DELETE FROM helipad_auth_challenge')) {
      if (consumed || params[0] !== challengeHash) return { rows: [] };
      consumed = true;
      return { rows: [{ nonce_hash: challengeHash }] };
    }
    if (sql.includes('INSERT INTO helipad_account')) return { rows: [{ id: familyID, display_name: 'Alex', email: null }] };
    if (sql.includes('INSERT INTO helipad_session')) { sessionHash = params[0]; return { rows: [] }; }
    if (sql.includes('FROM helipad_session')) {
      return { rows: params[0] === sessionHash ? [{ id: familyID, display_name: 'Alex', email: null }] : [] };
    }
    if (sql.includes('FROM helipad_family f')) return { rows: [] };
    throw new Error(`Unexpected query: ${sql}`);
  }, async base => {
    const challenge = await (await fetch(`${base}/v1/auth/challenge`, { method: 'POST' })).json();
    assert.equal(challengeHash, sha256(challenge.nonce));
    const body = JSON.stringify({ identityToken: 'apple-test-token', nonce: challenge.nonce, displayName: 'Alex' });
    const signedIn = await fetch(`${base}/v1/auth/apple`, {
      method: 'POST', headers: { 'content-type': 'application/json' }, body
    });
    assert.equal(signedIn.status, 200);
    const { token } = await signedIn.json();
    assert.equal(sessionHash, sha256(token));
    const profile = await fetch(`${base}/v1/me`, { headers: { authorization: `Bearer ${token}` } });
    assert.equal(profile.status, 200);
    assert.equal((await profile.json()).account.display_name, 'Alex');
    const replay = await fetch(`${base}/v1/auth/apple`, {
      method: 'POST', headers: { 'content-type': 'application/json' }, body
    });
    assert.equal(replay.status, 401);
  }, { verifyIdentity: async (token, nonce, audience) => {
    assert.equal(token, 'apple-test-token');
    assert.ok(nonce);
    assert.equal(audience, 'com.onepalebluedot.helipad');
    return { sub: 'apple-subject' };
  } });
});

test('a document request without a session is rejected before reading family data', async () => {
  let queries = 0;
  await withServer(async () => { queries++; return { rows: [] }; }, async base => {
    const response = await fetch(`${base}/v1/families/${familyID}/documents/household`);
    assert.equal(response.status, 401);
    assert.equal(queries, 0);
  });
});

test('a signed-in nonmember cannot read a family document', async () => {
  let documentRead = false;
  await withServer(async sql => {
    if (sql.includes('FROM helipad_session')) return { rows: [{ id: familyID, display_name: 'Tester', email: null }] };
    if (sql.includes('FROM helipad_family_member')) return { rows: [] };
    if (sql.includes('FROM helipad_family_document')) documentRead = true;
    return { rows: [] };
  }, async base => {
    const response = await fetch(`${base}/v1/families/${familyID}/documents/household`, {
      headers: { authorization: 'Bearer test_session' }
    });
    assert.equal(response.status, 403);
    assert.equal(documentRead, false);
  });
});

test('only an owner can create family invitations', async () => {
  let inviteInserted = false;
  await withServer(async sql => {
    if (sql.includes('FROM helipad_session')) return { rows: [{ id: familyID, display_name: 'Tester', email: null }] };
    if (sql.includes('FROM helipad_family_member')) return { rows: [{ role: 'member' }] };
    if (sql.includes('INSERT INTO helipad_family_invite')) inviteInserted = true;
    return { rows: [] };
  }, async base => {
    const response = await fetch(`${base}/v1/families/${familyID}/invites`, {
      method: 'POST', headers: { authorization: 'Bearer test_session' }
    });
    assert.equal(response.status, 403);
    assert.equal(inviteInserted, false);
  });
});

test('a shared invitation opens without a session and does not expose a database request', async () => {
  let queries = 0;
  const code = 'a'.repeat(43);
  await withServer(async () => { queries++; return { rows: [] }; }, async base => {
    const response = await fetch(`${base}/invite/${code}`);
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('referrer-policy'), 'no-referrer');
    assert.match(await response.text(), new RegExp(`helipad://invite/${code}`));
    assert.equal(queries, 0);
  });
});

test('alpha sign-up stores a normalised email, answers preflight, and drops honeypot posts', async () => {
  const stored = [];
  await withServer(async (sql, params) => {
    if (sql.includes('INSERT INTO helipad_alpha_signup')) { stored.push(params); return { rows: [] }; }
    throw new Error(`Unexpected query: ${sql}`);
  }, async base => {
    const preflight = await fetch(`${base}/v1/alpha-signup`, { method: 'OPTIONS' });
    assert.equal(preflight.status, 204);
    assert.equal(preflight.headers.get('access-control-allow-origin'), '*');
    const post = body => fetch(`${base}/v1/alpha-signup`, {
      method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body)
    });
    assert.equal((await post({ name: ' Sam ', email: ' Sam@Example.COM ' })).status, 200);
    assert.deepEqual(stored, [['sam@example.com', 'Sam']]);
    assert.equal((await post({ name: 'Sam', email: 'not-an-email' })).status, 400);
    assert.equal((await post({ name: '', email: 'sam@example.com' })).status, 400);
    assert.equal((await post({ name: 'Bot', email: 'bot@example.com', website: 'spam.example' })).status, 200);
    assert.equal(stored.length, 1);
  });
});
