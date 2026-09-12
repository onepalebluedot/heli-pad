# HeliPad assistant relay — Cloudflare Worker

The deployable version of `../dev-relay/relay.py`. Holds the OpenAI key so the
app never has to, gives you HTTPS for free (so no App Transport Security
exception is needed in production), and works on cellular with your Mac shut.

Sized for a household: tokens are a static per-device map, not real identity.
Enough to revoke one phone without touching the other. Replace it with proper
session issuance before anyone outside the family uses this.

## Deployed

`https://helipad-assistant-relay.es-johnv.workers.dev` — live since
12 September 2026, serving the iOS app. Two device tokens exist; they are in
`device-tokens.txt`, which is gitignored.

Redeploy after any change with `npx wrangler deploy` from this directory.

## First-time deploy

Run everything from this directory.

**1. Log in**

```bash
npx wrangler login
```

**2. Create the KV namespace for the daily counters**

```bash
npx wrangler kv namespace create USAGE
```

Paste the `id` it prints into `wrangler.toml`, replacing
`REPLACE_WITH_KV_NAMESPACE_ID`.

**3. Generate one token per phone**

```bash
echo "yours:  $(openssl rand -hex 24)"; echo "hers:   $(openssl rand -hex 24)"
```

Keep these. You will paste each into that phone's Settings.

**4. Set the secrets**

```bash
npx wrangler secret put OPENAI_API_KEY
```

Paste your key when prompted. Then:

```bash
npx wrangler secret put HELIPAD_TOKENS
```

Paste a JSON object mapping each token to a label, on one line:

```json
{"<first token>":"john-iphone","<second token>":"sarah-iphone"}
```

The label is what appears in the logs and what the daily counter is keyed on.

**5. Deploy**

```bash
npx wrangler deploy
```

It prints a URL like `https://helipad-assistant-relay.<subdomain>.workers.dev`.

**6. Check it**

```bash
curl https://helipad-assistant-relay.<subdomain>.workers.dev/health
```

Expect `{"ok":true,"model":"gpt-5.6-luna","key_loaded":true}`. If
`key_loaded` is false the secret did not take.

**7. Point each phone at it**

In HeliPad: **Settings › Assistant**. Service URL is the Worker URL, session
token is that phone's token. Tap **Test connection** — it should say
Reachable. Then open the Assistant tab.

Settings is the only way to configure this. Writing the values with
`xcrun simctl spawn … defaults write` looks like it works — `defaults read`
shows the new value — but the app does not see it; the sandboxed app reads a
plist inside its own data container. If you need to script it for a
simulator, write that container plist directly:

```bash
PLIST="$(xcrun simctl get_app_container <udid> com.onepalebluedot.helipad data)/Library/Preferences/com.onepalebluedot.helipad.plist"
```

Each phone gets its own token. Do not share one between them, or you lose the
ability to revoke one and the daily counter covers both at once.

## Running it

```bash
npx wrangler tail          # live logs, including the provider's real errors
npx wrangler deploy        # after any change
```

Provider error messages are logged rather than returned to the app, because
they can name your project and organisation. `wrangler tail` is where you see
why something failed. The error *code* is passed through, so a wrong model id
still surfaces in the app.

## Revoking a phone

Re-run `npx wrangler secret put HELIPAD_TOKENS` with that token removed from
the JSON, then `npx wrangler deploy`. The phone gets a 401 and the app reports
the session was rejected.

## Cost and limits

- Workers free tier: 100,000 requests/day. Two people will not approach it.
- KV free tier: 1,000 writes/day. One write per assistant request, so the
  `DAILY_LIMIT` of 50 per device keeps this comfortable.
- **OpenAI usage bills your account.** `DAILY_LIMIT` in `wrangler.toml` is the
  guard. It is a spend guard rather than a hard quota: KV is eventually
  consistent, so simultaneous requests can slip a few over. Fine for
  protecting a personal bill, not something to rely on for anything stricter.

One assistant question is typically several requests, because the model calls
an operation, reads the result, and may call another before answering. Budget
roughly three to five requests per question when picking a limit.

## What it enforces

Re-checked here rather than trusted from the app, because a modified client
could send anything:

| Check | Behaviour |
| --- | --- |
| Unknown or missing bearer token | 401 |
| Model other than `HELIPAD_MODEL` | 400, no substitution |
| `store` not false | 400 |
| A hosted tool (`web_search`, `code_interpreter`, …) | 400 |
| A function outside the app's allowlist | 400 |
| Over the device's daily limit | 429, which the app shows as a quota message |

## Still missing for real users

- Real identity and session issuance; these tokens never expire on their own.
- Household scoping derived server-side. Right now the app asserts its own
  household id, which is fine when you trust both devices and wrong the moment
  you do not.
- Per-household billing. Every request bills one account: yours.
