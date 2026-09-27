# HeliPad family API

This service holds the Neon database credential and authorizes each family
document request against a signed-in member. The iOS app receives an opaque
session token, never the database connection string.

## Configure

Use Node 24 and a dedicated Neon database role that can create the
tables defined in `src/schema.mjs`. Set these environment variables on an HTTPS host:

| Variable | Value |
| --- | --- |
| `DATABASE_URL` | Neon PostgreSQL connection URL; keep it on the server only |
| `APPLE_BUNDLE_ID` | `com.onepalebluedot.helipad` |
| `PORT` | Listener port; defaults to `8080` |
| `TESTFLIGHT_URL` | Optional public `https://testflight.apple.com/join/...` link shown on invitation pages |
| `RESEND_API_KEY` | Optional [Resend](https://resend.com) API key; with `SIGNUP_NOTIFY_TO`, emails each new alpha sign-up |
| `SIGNUP_NOTIFY_TO` | Address (or comma-separated addresses) that receives alpha sign-up emails |
| `SIGNUP_NOTIFY_FROM` | Optional sender; defaults to `HeliPad <onboarding@resend.dev>`, which Resend only delivers to the account owner's own address until a domain is verified |

Run `npm ci && npm start` with server environment variables, or `npm run dev`
to load the ignored local `.env.local` file. Startup applies the additive schema. `GET /health`
returns `{"ok":true}`. Keep this service behind HTTPS and do not expose its
port directly to the internet without TLS termination.

For local validation, put `DATABASE_URL` and `APPLE_BUNDLE_ID` in the ignored
`.env.local` file and run `npm run check:config`. This checks the connection
and table creation permission without printing the credential.

For Vercel, create a **separate project** with `family-api` as its root
directory, Framework Preset **Express**, and the same environment variables.
The exported Express app applies the schema on the first request in each
instance. Use a current Vercel CLI (47.0.5 or later) if deploying from the
command line. Keep the existing `heli-pad` web project separate.

The iOS project points `FAMILY_API_URL` at
`https://heli-pad-family-api.vercel.app`. The app reads this value from
`FamilyAPIURL` in Info.plist. Override the build setting to target another
deployment, or set it to an empty string to use only the on-device setup and
personal Neon integration.

Enable **Sign in with Apple** for the app's bundle ID in the Apple Developer
account. The Xcode target includes the matching entitlement; a device-signed
TestFlight build needs an updated provisioning profile after the capability
is enabled.

## Account flow

1. A person either signs in with Apple or uses a username and password.
2. Apple: the app requests a one-time five-minute nonce, and Sign in with
   Apple returns an identity token bound to it. The API checks Apple's
   signature, issuer, audience, expiry, and nonce, then consumes the nonce.
   Username: `POST /v1/auth/register` or `/v1/auth/login`. Usernames are
   case-insensitive; passwords are stored only as salted scrypt hashes. Ten
   wrong passwords lock the account for 15 minutes, and an unknown username
   answers exactly like a wrong password.
   Either way the API issues a 30-day opaque session stored hashed in Postgres.
3. A signed-in account creates a family or accepts a one-use seven-day invite.
   The owner shares an HTTPS invitation page that opens the app and, when
   configured, provides the public TestFlight installation link.
4. The API checks family membership before every document read and write.
   Only the owner can issue invites. Documents use compare-and-swap revisions
   so existing iOS merge and retry behavior still works.

The two document kinds are `household` (schedule and people) and `lists`.
Existing local data can be uploaded when its owner enables sharing; Lists is
re-keyed to the new family ID before its first sync. A fresh
installation may create a family first and complete the existing setup flow.
An invitee signs in, enters the code, then picks their caregiver profile in
the app. The profile is a schedule preference, not an authentication method.

## Validation

Run `npm test` for API authorization checks and
`../scripts/test-production.sh` for the iOS domain regression suite. A live
two-device TestFlight pass is required after deployment to verify Apple
credential delivery, invitation redemption, and cross-device sync.
