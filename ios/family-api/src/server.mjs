import { createHash, randomBytes, randomUUID } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import express from 'express';
import { Pool } from 'pg';
import { createRemoteJWKSet, jwtVerify } from 'jose';
import { schema } from './schema.mjs';

for (const envPath of ['.env.local', '.env']) {
  try {
    process.loadEnvFile?.(new URL(`../${envPath}`, import.meta.url));
  } catch {}
}


const appleKeys = createRemoteJWKSet(new URL('https://appleid.apple.com/auth/keys'));
const sha256 = value => createHash('sha256').update(value).digest('hex');
const randomCode = () => randomBytes(32).toString('base64url');
const uuid = value => typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
const safeKind = value => value === 'household' || value === 'lists';

export { sha256, uuid, safeKind };

class ApiError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}

async function bodyJSON(request) {
  let size = 0;
  const chunks = [];
  for await (const chunk of request) {
    size += chunk.length;
    if (size > 4 * 1024 * 1024) throw new ApiError(413, 'The family document is too large.');
    chunks.push(chunk);
  }
  try { return JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}'); }
  catch { throw new ApiError(400, 'Invalid JSON.'); }
}

function send(response, status, value) {
  response.writeHead(status, { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' });
  response.end(JSON.stringify(value));
}

function inviteLanding(response, code) {
  const deepLink = `helipad://invite/${code}`;
  const testFlight = process.env.TESTFLIGHT_URL;
  const installURL = (() => {
    try {
      const url = new URL(testFlight);
      return url.protocol === 'https:' && url.hostname === 'testflight.apple.com' ? url.href : null;
    } catch { return null; }
  })();
  const install = installURL ? `<a class="secondary" href="${installURL}">Install with TestFlight</a>` : '';
  response.writeHead(200, {
    'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store',
    'referrer-policy': 'no-referrer',
    'content-security-policy': "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'"
  });
  response.end(`<!doctype html><html lang="en"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Join a HeliPad family</title><style>body{font:17px system-ui,sans-serif;background:#f6f4ed;color:#244c40;margin:0;padding:40px 20px}main{max-width:440px;margin:10vh auto;background:white;border-radius:20px;padding:30px}h1{font-size:28px}p{line-height:1.5;color:#52675e}a{display:block;text-align:center;background:#205744;color:white;padding:15px;border-radius:10px;text-decoration:none;margin-top:14px}.secondary{background:#e6eee1;color:#205744}code{overflow-wrap:anywhere}</style><main><h1>You’re invited to HeliPad</h1><p>Open the app, sign in with Apple, and join your family. If you need the app first, install it through TestFlight, then return to this invitation.</p><a href="${deepLink}">Open HeliPad</a>${install}<p>Invitation code: <code>${code}</code></p></main></html>`);
}

async function accountFor(request, pool) {
  const token = /^Bearer ([A-Za-z0-9_-]+)$/.exec(request.headers.authorization || '')?.[1];
  if (!token) throw new ApiError(401, 'Sign in to continue.');
  const { rows } = await pool.query(`
    SELECT a.id, a.display_name, a.email
    FROM helipad_session s JOIN helipad_account a ON a.id = s.account_id
    WHERE s.token_hash = $1 AND s.expires_at > now()
  `, [sha256(token)]);
  if (!rows[0]) throw new ApiError(401, 'Your session has expired. Sign in again.');
  return rows[0];
}

async function membership(pool, familyID, accountID, ownerOnly = false) {
  if (!uuid(familyID)) throw new ApiError(404, 'Family not found.');
  const { rows } = await pool.query(
    'SELECT role FROM helipad_family_member WHERE family_id = $1 AND account_id = $2',
    [familyID, accountID]
  );
  if (!rows[0] || (ownerOnly && rows[0].role !== 'owner')) {
    throw new ApiError(403, 'You do not have access to this family.');
  }
  return rows[0];
}

async function verifyApple(identityToken, nonce, audience) {
  const { payload } = await jwtVerify(identityToken, appleKeys, {
    issuer: 'https://appleid.apple.com', audience, algorithms: ['RS256']
  });
  if (!payload.sub || payload.nonce !== nonce) throw new ApiError(401, 'Apple sign-in could not be verified.');
  return payload;
}

// Emails the owner about a new alpha sign-up through Resend's HTTP API. Unset
// RESEND_API_KEY or SIGNUP_NOTIFY_TO turns it off, so local runs and tests
// send nothing. Plain text only: the name is visitor input, and an HTML body
// would need escaping to stay safe in a mail client.
async function notifyByEmail({ name, email }) {
  const { RESEND_API_KEY, SIGNUP_NOTIFY_TO, SIGNUP_NOTIFY_FROM } = process.env;
  if (!RESEND_API_KEY || !SIGNUP_NOTIFY_TO) return;
  const response = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: { authorization: `Bearer ${RESEND_API_KEY}`, 'content-type': 'application/json' },
    body: JSON.stringify({
      from: SIGNUP_NOTIFY_FROM || 'HeliPad <onboarding@resend.dev>',
      to: SIGNUP_NOTIFY_TO.split(',').map(s => s.trim()).filter(Boolean),
      subject: `New HeliPad alpha sign-up: ${name}`,
      text: `${name} <${email}> asked to join the HeliPad alpha.\n\nSee everyone: SELECT name, email, created_at FROM helipad_alpha_signup ORDER BY created_at;`
    }),
    // Vercel freezes the function once it responds, so the send is awaited
    // before replying; the timeout keeps a slow mail API from stalling the form.
    signal: AbortSignal.timeout(5000)
  });
  if (!response.ok) throw new Error(`Resend answered ${response.status}`);
}

export function createHandler(pool, { appleBundleID, verifyIdentity = verifyApple, notifySignup = notifyByEmail } = {}) {
  if (!appleBundleID) throw new Error('APPLE_BUNDLE_ID is required');
  return async (request, response) => {
    try {
      const url = new URL(request.url, 'http://localhost');
      const path = url.pathname.split('/').filter(Boolean);
      if (request.method === 'GET' && url.pathname === '/health') return send(response, 200, { ok: true });
      if (request.method === 'GET' && path[0] === 'invite' && path.length === 2 && /^[A-Za-z0-9_-]{40,60}$/.test(path[1])) {
        return inviteLanding(response, path[1]);
      }

      // The public website posts here from another origin. It carries no
      // credentials, so a wildcard origin exposes nothing a form could not.
      if (url.pathname === '/v1/alpha-signup') {
        response.setHeader('access-control-allow-origin', '*');
        if (request.method === 'OPTIONS') {
          response.writeHead(204, {
            'access-control-allow-methods': 'POST',
            'access-control-allow-headers': 'content-type',
            'access-control-max-age': '86400'
          });
          return response.end();
        }
        if (request.method !== 'POST') throw new ApiError(405, 'Use POST.');
        const body = await bodyJSON(request);
        // A hidden field people never see; bots that fill every input get a
        // success reply and no row, so they have no signal to adapt to.
        if (typeof body.website === 'string' && body.website.trim()) return send(response, 200, { ok: true });
        const name = typeof body.name === 'string' ? body.name.trim() : '';
        const email = typeof body.email === 'string' ? body.email.trim().toLowerCase() : '';
        // Control characters would let a name break the notification's subject line.
        if (!name || name.length > 80 || /[\u0000-\u001f\u007f]/.test(name)) throw new ApiError(400, 'Enter your name.');
        if (email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) throw new ApiError(400, 'Enter a valid email address.');
        // xmax is 0 only on a freshly inserted row, so a repeat sign-up that
        // just updates the name does not send a second email.
        const { rows } = await pool.query(`
          INSERT INTO helipad_alpha_signup (email, name) VALUES ($1, $2)
          ON CONFLICT (email) DO UPDATE SET name = EXCLUDED.name
          RETURNING (xmax = 0) AS inserted
        `, [email, name]);
        if (rows[0]?.inserted) {
          // The row is saved either way; a mail outage must not tell the visitor
          // their sign-up failed.
          try { await notifySignup({ name, email }); }
          catch (error) { console.error('Alpha sign-up notification failed', error); }
        }
        return send(response, 200, { ok: true });
      }

      if (request.method === 'POST' && url.pathname === '/v1/auth/challenge') {
        const nonce = randomCode();
        await pool.query('INSERT INTO helipad_auth_challenge (nonce_hash, expires_at) VALUES ($1, now() + interval \'5 minutes\')', [sha256(nonce)]);
        return send(response, 200, { nonce });
      }
      if (request.method === 'POST' && url.pathname === '/v1/auth/apple') {
        const body = await bodyJSON(request);
        if (typeof body.identityToken !== 'string' || typeof body.nonce !== 'string') throw new ApiError(400, 'Apple sign-in is incomplete.');
        let identity;
        try { identity = await verifyIdentity(body.identityToken, body.nonce, appleBundleID); }
        catch (error) { throw error instanceof ApiError ? error : new ApiError(401, 'Apple sign-in could not be verified.'); }
        const consumed = await pool.query(
          'DELETE FROM helipad_auth_challenge WHERE nonce_hash = $1 AND expires_at > now() RETURNING nonce_hash',
          [sha256(body.nonce)]
        );
        if (!consumed.rows[0]) throw new ApiError(401, 'Sign-in challenge expired. Please try again.');
        const accountID = randomUUID();
        const displayName = typeof body.displayName === 'string' ? body.displayName.trim().slice(0, 80) : '';
        const email = typeof identity.email === 'string' ? identity.email : null;
        const account = await pool.query(`
          INSERT INTO helipad_account (id, apple_subject, display_name, email)
          VALUES ($1, $2, $3, $4)
          ON CONFLICT (apple_subject) DO UPDATE SET
            email = COALESCE(EXCLUDED.email, helipad_account.email),
            display_name = CASE WHEN helipad_account.display_name = '' THEN EXCLUDED.display_name ELSE helipad_account.display_name END
          RETURNING id, display_name, email
        `, [accountID, identity.sub, displayName, email]);
        const token = randomCode();
        await pool.query(`
          INSERT INTO helipad_session (token_hash, account_id, expires_at)
          VALUES ($1, $2, now() + interval '30 days')
        `, [sha256(token), account.rows[0].id]);
        return send(response, 200, { token, account: account.rows[0] });
      }

      const account = await accountFor(request, pool);
      if (request.method === 'POST' && url.pathname === '/v1/auth/logout') {
        const token = request.headers.authorization.slice(7);
        await pool.query('DELETE FROM helipad_session WHERE token_hash = $1', [sha256(token)]);
        return send(response, 200, { ok: true });
      }
      if (request.method === 'GET' && url.pathname === '/v1/me') {
        const { rows } = await pool.query(`
          SELECT f.id, f.name, m.role FROM helipad_family f
          JOIN helipad_family_member m ON m.family_id = f.id
          WHERE m.account_id = $1 ORDER BY f.created_at
        `, [account.id]);
        return send(response, 200, { account, families: rows });
      }
      if (request.method === 'POST' && url.pathname === '/v1/families') {
        const body = await bodyJSON(request);
        const name = typeof body.name === 'string' ? body.name.trim() : '';
        if (!name || name.length > 80) throw new ApiError(400, 'Enter a family name of 80 characters or fewer.');
        if (body.state != null && (typeof body.state !== 'object' || Array.isArray(body.state))) throw new ApiError(400, 'Invalid family data.');
        const id = randomUUID();
        const client = await pool.connect();
        try {
          await client.query('BEGIN');
          await client.query('INSERT INTO helipad_family (id, name) VALUES ($1, $2)', [id, name]);
          await client.query('INSERT INTO helipad_family_member (family_id, account_id, role) VALUES ($1, $2, $3)', [id, account.id, 'owner']);
          if (body.state != null) await client.query(
            'INSERT INTO helipad_family_document (family_id, kind, state_data) VALUES ($1, $2, $3::jsonb)',
            [id, 'household', JSON.stringify(body.state)]
          );
          await client.query('COMMIT');
        } catch (error) { await client.query('ROLLBACK'); throw error; }
        finally { client.release(); }
        return send(response, 201, { family: { id, name, role: 'owner' } });
      }
      if (path[0] === 'v1' && path[1] === 'families' && uuid(path[2])) {
        const familyID = path[2];
        if (path[3] === 'members' && request.method === 'GET') {
          await membership(pool, familyID, account.id);
          const { rows } = await pool.query(`
            SELECT a.id, a.display_name, m.role FROM helipad_family_member m
            JOIN helipad_account a ON a.id = m.account_id
            WHERE m.family_id = $1 ORDER BY m.created_at
          `, [familyID]);
          return send(response, 200, { members: rows });
        }
        if (path[3] === 'invites' && request.method === 'POST') {
          await membership(pool, familyID, account.id, true);
          const code = randomCode();
          const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000);
          await pool.query(`
            INSERT INTO helipad_family_invite (code_hash, family_id, created_by, expires_at)
            VALUES ($1, $2, $3, $4)
          `, [sha256(code), familyID, account.id, expiresAt]);
          return send(response, 201, { code, expiresAt: expiresAt.toISOString() });
        }
        if (path[3] === 'documents' && safeKind(path[4])) {
          await membership(pool, familyID, account.id);
          const kind = path[4];
          if (request.method === 'GET') {
            const { rows } = await pool.query(
              'SELECT state_data, revision FROM helipad_family_document WHERE family_id = $1 AND kind = $2',
              [familyID, kind]
            );
            return send(response, 200, { data: url.searchParams.has('revisionOnly') ? null : rows[0]?.state_data ?? null, revision: rows[0]?.revision?.toString() ?? null });
          }
          if (request.method === 'PUT') {
            const body = await bodyJSON(request);
            if (!body.data || typeof body.data !== 'object' || Array.isArray(body.data)) throw new ApiError(400, 'Invalid family document.');
            if (kind === 'lists' && body.data.householdID !== familyID) throw new ApiError(400, 'Lists belong to another family.');
            const expected = body.expectedRevision;
            if (expected != null && !/^[1-9][0-9]*$/.test(String(expected))) throw new ApiError(400, 'Invalid revision.');
            const query = expected == null
              ? `INSERT INTO helipad_family_document (family_id, kind, state_data)
                 VALUES ($1, $2, $3::jsonb) ON CONFLICT DO NOTHING RETURNING revision`
              : `UPDATE helipad_family_document SET state_data = $3::jsonb,
                   revision = revision + 1, updated_at = now()
                 WHERE family_id = $1 AND kind = $2 AND revision = $4 RETURNING revision`;
            const params = expected == null ? [familyID, kind, JSON.stringify(body.data)] : [familyID, kind, JSON.stringify(body.data), expected];
            const { rows } = await pool.query(query, params);
            if (!rows[0]) throw new ApiError(409, 'The family changed. Refresh and try again.');
            return send(response, 200, { revision: rows[0].revision.toString() });
          }
        }
      }
      if (path[0] === 'v1' && path[1] === 'invites' && typeof path[2] === 'string') {
        const code = path[2];
        if (!/^[A-Za-z0-9_-]{40,60}$/.test(code)) throw new ApiError(404, 'Invite not found.');
        if (request.method === 'GET' && path.length === 3) {
          const { rows } = await pool.query(`
            SELECT f.name, i.expires_at FROM helipad_family_invite i
            JOIN helipad_family f ON f.id = i.family_id
            WHERE i.code_hash = $1 AND i.expires_at > now() AND i.accepted_at IS NULL
          `, [sha256(code)]);
          if (!rows[0]) throw new ApiError(404, 'This invitation has expired or was already used.');
          return send(response, 200, { name: rows[0].name, expiresAt: rows[0].expires_at });
        }
        if (request.method === 'POST' && path[3] === 'accept') {
          const client = await pool.connect();
          try {
            await client.query('BEGIN');
            const { rows } = await client.query(`
              SELECT family_id FROM helipad_family_invite
              WHERE code_hash = $1 AND expires_at > now() AND accepted_at IS NULL FOR UPDATE
            `, [sha256(code)]);
            if (!rows[0]) throw new ApiError(404, 'This invitation has expired or was already used.');
            await client.query(`
              INSERT INTO helipad_family_member (family_id, account_id, role)
              VALUES ($1, $2, 'member') ON CONFLICT DO NOTHING
            `, [rows[0].family_id, account.id]);
            await client.query(`
              UPDATE helipad_family_invite SET accepted_by = $2, accepted_at = now()
              WHERE code_hash = $1
            `, [sha256(code), account.id]);
            await client.query('COMMIT');
            return send(response, 200, { familyId: rows[0].family_id });
          } catch (error) { await client.query('ROLLBACK'); throw error; }
          finally { client.release(); }
        }
      }
      throw new ApiError(404, 'Not found.');
    } catch (error) {
      if (!(error instanceof ApiError)) console.error('Family API request failed', error);
      send(response, error.status || 500, { error: error instanceof ApiError ? error.message : 'The family service is unavailable.' });
    }
  };
}

// Vercel recognizes this Express export; the same entrypoint runs with Node
// for local development or a container. Initialize schema once per process.
const app = express();
const runtimePool = new Pool({ connectionString: process.env.DATABASE_URL, max: 3 });
let initialization;
async function initializeSchema() {
  const client = await runtimePool.connect();
  try {
    await client.query('BEGIN');
    await client.query('SELECT pg_advisory_xact_lock($1)', [45127419]);
    await client.query(schema);
    await client.query('COMMIT');
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}
app.use(async (request, response) => {
  if (!process.env.DATABASE_URL || !process.env.APPLE_BUNDLE_ID) {
    return send(response, 503, { error: 'Family service configuration is incomplete.' });
  }
  try {
    initialization ??= initializeSchema();
    await initialization;
    return createHandler(runtimePool, { appleBundleID: process.env.APPLE_BUNDLE_ID })(request, response);
  } catch (error) {
    initialization = undefined;
    console.error('Family API initialization failed', error);
    return send(response, 503, { error: 'The family service is unavailable.' });
  }
});
export default app;

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const { DATABASE_URL, APPLE_BUNDLE_ID, PORT = '8080' } = process.env;
  if (!DATABASE_URL || !APPLE_BUNDLE_ID) throw new Error('DATABASE_URL and APPLE_BUNDLE_ID are required');
  app.listen(Number(PORT), () => console.log(`HeliPad family API listening on ${PORT}`));
}
