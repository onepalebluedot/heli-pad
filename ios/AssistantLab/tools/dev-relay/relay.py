#!/usr/bin/env python3
"""A local stand-in for the authenticated relay described in PREWALK_PLAN.md A01.

Runs on your Mac. The simulator talks to it over localhost, so the OpenAI key
stays in this process and never enters the app - which is the whole point of
A01, and the reason the app can be tested against a real model without ever
holding a provider credential.

This is a development prototype, not the deployable service. What it does show
is the shape that service needs: it authenticates the caller, pins the model,
refuses hosted tools, refuses anything outside the app's allowlist, and keeps
the key server-side. A real deployment adds proper identity, per-household
rate limiting, logging and TLS.

    python3 relay.py            # reads ../../.env, serves on 8787

Environment (from AssistantLab/.env):
    OPENAI_API_KEY              required
    HELIPAD_ASSISTANT_MODEL     default gpt-5.6-luna
    HELIPAD_DEV_SESSION_TOKEN   default dev-local-token
"""

import json
import os
import sys
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

PORT = int(os.environ.get("HELIPAD_RELAY_PORT", "8787"))
UPSTREAM = "https://api.openai.com/v1/responses"

# The operations the app is allowed to expose. The client already enforces
# this; the relay enforces it again because a client-side allowlist is not a
# control - a tampered build could send anything.
ALLOWED_TOOLS = {
    "find_events", "get_event", "list_household_people", "list_saved_places",
    "preview_create_events", "preview_assign_tasks", "get_schedule_trends",
    "get_app_help",
}


def load_env():
    """Reads AssistantLab/.env, with the real environment taking precedence."""
    values = {}
    env_path = Path(__file__).resolve().parents[2] / ".env"
    if env_path.exists():
        for raw in env_path.read_text().splitlines():
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            body = line[7:] if line.startswith("export ") else line
            if "=" not in body:
                continue
            key, _, value = body.partition("=")
            key, value = key.strip(), value.strip()
            if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
                value = value[1:-1]
            if key and value:
                values[key] = value
    values.update(os.environ)
    return values


ENV = load_env()
API_KEY = ENV.get("OPENAI_API_KEY", "")
MODEL = ENV.get("HELIPAD_ASSISTANT_MODEL", "gpt-5.6-luna")
SESSION_TOKEN = ENV.get("HELIPAD_DEV_SESSION_TOKEN", "dev-local-token")


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        sys.stderr.write("  relay: " + (fmt % args) + "\n")

    def _send(self, status, payload):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _reject(self, status, detail):
        self.log_message("refused: %s", detail)
        self._send(status, {"error": {"message": detail, "code": "relay_refused"}})

    def do_GET(self):
        if self.path == "/health":
            self._send(200, {"ok": True, "model": MODEL, "key_loaded": bool(API_KEY)})
        else:
            self._reject(404, "no such endpoint")

    def do_POST(self):
        if self.path != "/assistant/respond":
            return self._reject(404, "no such endpoint")

        # 1. Authenticate. A real relay resolves a session to a user and a
        #    household here, and derives household scope from that rather than
        #    from anything in the body.
        auth = self.headers.get("Authorization", "")
        if auth != f"Bearer {SESSION_TOKEN}":
            return self._reject(401, "session rejected")

        length = int(self.headers.get("Content-Length", "0"))
        try:
            body = json.loads(self.rfile.read(length) or b"{}")
        except json.JSONDecodeError:
            return self._reject(400, "body was not JSON")

        # 2. Pin the model. No silent substitution, in either direction.
        if body.get("model") != MODEL:
            return self._reject(400, f"model must be {MODEL}, got {body.get('model')!r}")

        # 3. Refuse provider-side storage being switched back on.
        if body.get("store") is not False:
            return self._reject(400, "store must be false")

        # 4. Refuse hosted tools and anything outside the allowlist. This is
        #    the check that a tampered client cannot get around.
        for tool in body.get("tools", []):
            if tool.get("type") != "function":
                return self._reject(400, f"hosted tool {tool.get('type')!r} is not permitted")
            if tool.get("name") not in ALLOWED_TOOLS:
                return self._reject(400, f"tool {tool.get('name')!r} is not on the allowlist")

        # 5. Forward with the server-held key.
        request = urllib.request.Request(
            UPSTREAM,
            data=json.dumps(body).encode(),
            headers={"Content-Type": "application/json", "Authorization": f"Bearer {API_KEY}"},
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=90) as response:
                payload = response.read()
            self.log_message("200 <- %s", MODEL)
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
        except urllib.error.HTTPError as error:
            detail = error.read().decode(errors="replace")[:800]
            self.log_message("upstream %s: %s", error.code, detail)
            # Passed through so a wrong model id or a missing scope is legible
            # while developing. A deployed relay would not echo this.
            self._send(error.code, {"error": {"message": detail, "code": "upstream_error"}})
        except Exception as error:  # noqa: BLE001 - dev tool, report anything
            self.log_message("transport: %s", error)
            self._reject(502, "upstream unreachable")


def main():
    if not API_KEY:
        sys.exit(
            "No OPENAI_API_KEY.\n"
            f"Put it in {Path(__file__).resolve().parents[2] / '.env'} or pass it in the environment."
        )
    print(f"HeliPad dev relay on http://localhost:{PORT}")
    print(f"  model         {MODEL}")
    print(f"  session token {SESSION_TOKEN}")
    print(f"  key           loaded, {len(API_KEY)} chars, never sent to the app")
    print("  the simulator reaches this at http://localhost:%d\n" % PORT)
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
