import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { createHandler, hashPassword, passwordMatches, safeKind, sha256, uuid } from '../src/server.mjs';

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

test('passwords are salted and only the original password matches', async () => {
  const first = await hashPassword('correct horse');
  const second = await hashPassword('correct horse');
  assert.notEqual(first, second);
  assert.equal(await passwordMatches('correct horse', first), true);
  assert.equal(await passwordMatches('Correct horse', first), false);
  assert.equal(await passwordMatches('correct horse', 'not-a-hash'), false);
});

// An in-memory stand-in for the account and session tables, enough for the
// username routes to register, sign in, fail, lock and read a profile.
function usernameDatabase() {
  const accounts = new Map();
  const sessions = new Map();
  const query = async (sql, params) => {
    if (sql.includes('INSERT INTO helipad_account (id, username')) {
      const [id, username, password_hash, display_name] = params;
      if ([...accounts.values()].some(a => a.username === username)) return { rows: [] };
      accounts.set(id, { id, username, password_hash, display_name, email: null, failed_logins: 0, locked_until: null });
      return { rows: [{ id, display_name, email: null, username }] };
    }
    if (sql.includes('FROM helipad_account WHERE username')) {
      const a = [...accounts.values()].find(a => a.username === params[0]);
      return { rows: a ? [{ ...a, locked: a.locked_until != null && a.locked_until > Date.now() }] : [] };
    }
    if (sql.includes('failed_logins = CASE')) {
      const a = accounts.get(params[0]);
      if (a.failed_logins + 1 >= params[1]) { a.failed_logins = 0; a.locked_until = Date.now() + 15 * 60_000; }
      else a.failed_logins++;
      return { rows: [] };
    }
    if (sql.includes('failed_logins = 0')) { Object.assign(accounts.get(params[0]), { failed_logins: 0, locked_until: null }); return { rows: [] }; }
    if (sql.includes('INSERT INTO helipad_session')) { sessions.set(params[0], params[1]); return { rows: [] }; }
    if (sql.includes('FROM helipad_session')) {
      const a = accounts.get(sessions.get(params[0]));
      return { rows: a ? [{ id: a.id, display_name: a.display_name, email: null, username: a.username }] : [] };
    }
    if (sql.includes('FROM helipad_family f')) return { rows: [] };
    throw new Error(`Unexpected query: ${sql}`);
  };
  return { query, accounts };
}

const postJSON = (url, body) => fetch(url, {
  method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body)
});

test('a username account registers, signs in case-insensitively, and never stores the password', async () => {
  const db = usernameDatabase();
  await withServer(db.query, async base => {
    const created = await postJSON(`${base}/v1/auth/register`, { username: ' Kellie.V ', password: 'school-run-8', displayName: 'Kellie' });
    assert.equal(created.status, 201);
    const { token, account } = await created.json();
    assert.equal(account.username, 'kellie.v');
    const stored = [...db.accounts.values()][0];
    assert.ok(!stored.password_hash.includes('school-run-8'));

    const profile = await fetch(`${base}/v1/me`, { headers: { authorization: `Bearer ${token}` } });
    assert.deepEqual((await profile.json()).account, { id: stored.id, display_name: 'Kellie', email: null, username: 'kellie.v' });

    const again = await postJSON(`${base}/v1/auth/register`, { username: 'kellie.v', password: 'another-pass' });
    assert.equal(again.status, 400, 'a taken username is refused');

    const login = await postJSON(`${base}/v1/auth/login`, { username: 'KELLIE.V', password: 'school-run-8' });
    assert.equal(login.status, 200);
    assert.ok((await login.json()).token);
  });
});

test('registration rejects short passwords and unusable usernames', async () => {
  const db = usernameDatabase();
  await withServer(db.query, async base => {
    assert.equal((await postJSON(`${base}/v1/auth/register`, { username: 'sam', password: 'short' })).status, 400);
    assert.equal((await postJSON(`${base}/v1/auth/register`, { username: 'a b', password: 'long enough' })).status, 400);
    assert.equal((await postJSON(`${base}/v1/auth/register`, { username: 'x', password: 'long enough' })).status, 400);
    assert.equal(db.accounts.size, 0);
  });
});

test('a wrong password and an unknown username get the same answer, and repeated failures lock the account', async () => {
  const db = usernameDatabase();
  await withServer(db.query, async base => {
    await postJSON(`${base}/v1/auth/register`, { username: 'sam', password: 'right-password' });
    const wrong = await postJSON(`${base}/v1/auth/login`, { username: 'sam', password: 'wrong-password' });
    const unknown = await postJSON(`${base}/v1/auth/login`, { username: 'nobody', password: 'wrong-password' });
    assert.equal(wrong.status, 401);
    assert.equal(unknown.status, 401);
    assert.deepEqual(await wrong.json(), await unknown.json());

    for (let i = 1; i < 10; i++) await postJSON(`${base}/v1/auth/login`, { username: 'sam', password: 'wrong-password' });
    const locked = await postJSON(`${base}/v1/auth/login`, { username: 'sam', password: 'right-password' });
    assert.equal(locked.status, 429, 'even the right password waits out the lock');
  });
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
  const notified = [];
  await withServer(async (sql, params) => {
    if (sql.includes('INSERT INTO helipad_alpha_signup')) {
      const inserted = !stored.some(row => row[0] === params[0]);
      stored.push(params);
      return { rows: [{ inserted }] };
    }
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
    assert.equal((await post({ name: 'Sam\r\nBcc: x', email: 'sam@example.com' })).status, 400);
    assert.equal((await post({ name: 'Bot', email: 'bot@example.com', website: 'spam.example' })).status, 200);
    assert.equal(stored.length, 1);
    assert.equal((await post({ name: 'Samuel', email: 'sam@example.com' })).status, 200);
    assert.deepEqual(notified, [{ name: 'Sam', email: 'sam@example.com' }], 'only the first sign-up for an email notifies');
  }, { notifySignup: async signup => { notified.push(signup); } });
});

test('a failed sign-up notification still reports success', async () => {
  await withServer(async () => ({ rows: [{ inserted: true }] }), async base => {
    const response = await fetch(`${base}/v1/alpha-signup`, {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ name: 'Ada', email: 'ada@example.com' })
    });
    assert.equal(response.status, 200);
  }, { notifySignup: async () => { throw new Error('mail down'); } });
});
