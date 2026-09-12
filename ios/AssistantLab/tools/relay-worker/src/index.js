/**
 * HeliPad assistant relay — Cloudflare Worker.
 *
 * The deployable version of tools/dev-relay/relay.py. It exists so the
 * OpenAI key lives on a server instead of on a phone (PREWALK_PLAN.md A01):
 * the app sends a per-device session token, this forwards the request with
 * the real key, and no build of the app ever contains a provider credential.
 *
 * Sized for a household, not a product. Tokens are a static per-device map
 * rather than real identity, which is enough to revoke one phone without
 * touching the other. Replace it with proper session issuance before anyone
 * outside the family uses this.
 *
 * Bindings:
 *   OPENAI_API_KEY   secret  the provider key
 *   HELIPAD_TOKENS   secret  JSON, {"<token>": "<device label>"}
 *   HELIPAD_MODEL    var     model id, pinned; no silent substitution
 *   DAILY_LIMIT      var     requests per device per day
 *   USAGE            KV      daily counters
 */

/** Operations the app may expose. The client enforces this too; a client-side
 *  allowlist is not a control, so it is enforced again here. */
const ALLOWED_TOOLS = new Set([
  "find_events",
  "get_event",
  "list_household_people",
  "list_saved_places",
  "preview_create_events",
  "preview_assign_tasks",
  "get_schedule_trends",
  "get_app_help",
]);

const UPSTREAM = "https://api.openai.com/v1/responses";

function json(status, body) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function refuse(status, detail) {
  console.log("refused:", detail);
  return json(status, { error: { message: detail, code: "relay_refused" } });
}

/**
 * Resolves the bearer token to a device label, or null.
 *
 * Compared against the whole map rather than short-circuiting on first
 * mismatch, so the work does not depend on how much of the token is correct.
 */
function identify(request, env) {
  const header = request.headers.get("Authorization") || "";
  if (!header.startsWith("Bearer ")) return null;
  const presented = header.slice(7);

  let tokens;
  try {
    tokens = JSON.parse(env.HELIPAD_TOKENS || "{}");
  } catch {
    console.log("HELIPAD_TOKENS is not valid JSON");
    return null;
  }

  let match = null;
  for (const [token, label] of Object.entries(tokens)) {
    if (timingSafeEqual(token, presented)) match = label;
  }
  return match;
}

function timingSafeEqual(a, b) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/**
 * Per-device daily counter.
 *
 * This is a spend guard, not a hard quota: KV is eventually consistent, so a
 * burst of simultaneous requests can slip a few over the line. That is an
 * acceptable trade for protecting a personal API bill, and worth knowing
 * before relying on it for anything stricter.
 */
async function overDailyLimit(env, label) {
  const limit = Number(env.DAILY_LIMIT || 50);
  if (!Number.isFinite(limit) || limit <= 0) return false;
  if (!env.USAGE) return false; // No KV bound: fail open rather than lock out.

  const day = new Date().toISOString().slice(0, 10);
  const key = `count:${label}:${day}`;
  const used = Number((await env.USAGE.get(key)) || 0);
  if (used >= limit) return true;

  // Two days, so a counter written just before midnight UTC still expires.
  await env.USAGE.put(key, String(used + 1), { expirationTtl: 60 * 60 * 48 });
  return false;
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    // Settings › Assistant probes this. Deliberately unauthenticated and
    // free: it answers "is the service up", nothing about the household.
    if (request.method === "GET" && url.pathname === "/health") {
      return json(200, {
        ok: true,
        model: env.HELIPAD_MODEL || "unset",
        key_loaded: Boolean(env.OPENAI_API_KEY),
      });
    }

    if (request.method !== "POST" || url.pathname !== "/assistant/respond") {
      return refuse(404, "no such endpoint");
    }

    const device = identify(request, env);
    if (!device) return refuse(401, "session rejected");

    if (await overDailyLimit(env, device)) {
      // 429 maps to the app's quota failure card, which tells the user the
      // household has hit its limit and that the rest of the app still works.
      return json(429, {
        error: { message: "daily assistant limit reached", code: "rate_limited" },
      });
    }

    const raw = await request.text();
    let body;
    try {
      body = JSON.parse(raw);
    } catch {
      return refuse(400, "body was not JSON");
    }

    // Pin the model. No substitution in either direction.
    if (body.model !== env.HELIPAD_MODEL) {
      return refuse(400, `model must be ${env.HELIPAD_MODEL}`);
    }
    // Refuse provider-side storage being switched back on.
    if (body.store !== false) {
      return refuse(400, "store must be false");
    }
    // Refuse hosted tools and anything off the allowlist. This is the check a
    // tampered client cannot get around.
    for (const tool of body.tools || []) {
      if (tool.type !== "function") {
        return refuse(400, `hosted tool ${tool.type} is not permitted`);
      }
      if (!ALLOWED_TOOLS.has(tool.name)) {
        return refuse(400, `tool ${tool.name} is not on the allowlist`);
      }
    }

    // Forward the original bytes: re-serialising would risk changing a body
    // that already passed validation.
    const abort = new AbortController();
    const timer = setTimeout(() => abort.abort(), 60_000);
    let upstream;
    try {
      upstream = await fetch(UPSTREAM, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          authorization: `Bearer ${env.OPENAI_API_KEY}`,
        },
        body: raw,
        signal: abort.signal,
      });
    } catch (error) {
      console.log("upstream unreachable:", String(error));
      return refuse(502, "assistant service could not reach the model");
    } finally {
      clearTimeout(timer);
    }

    if (upstream.ok) {
      console.log(`200 ${device} <- ${env.HELIPAD_MODEL}`);
      return new Response(upstream.body, {
        status: 200,
        headers: { "content-type": "application/json" },
      });
    }

    if (upstream.status === 429) {
      return json(429, { error: { message: "provider rate limit", code: "rate_limited" } });
    }

    // The provider's message can name the project and organisation, so it is
    // logged rather than returned. `wrangler tail` shows it. The error code is
    // passed through because a wrong model id is otherwise invisible.
    const detail = await upstream.text();
    console.log(`upstream ${upstream.status} for ${device}:`, detail.slice(0, 800));
    let code = `http_${upstream.status}`;
    try {
      code = JSON.parse(detail)?.error?.code || code;
    } catch {}
    return json(upstream.status, {
      error: { message: `assistant service error (${code})`, code: "upstream_error" },
    });
  },
};
