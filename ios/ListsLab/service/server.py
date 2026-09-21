#!/usr/bin/env python3
"""Isolated LAN collaboration service for Lists Preview. No HeliPad credentials/data."""
import argparse
import copy
import html
import json
import secrets
import sqlite3
import time
from contextlib import closing
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import quote, urlparse
from uuid import UUID

LIMIT = 2_000_000
CONTENT_FIELDS = ("text", "quantity", "note", "steps", "groupID", "sortIndex")


def identifier(value):
    try:
        UUID(value)
        return True
    except (ValueError, TypeError, AttributeError):
        return False


def text(value, limit, empty=True):
    return isinstance(value, str) and len(value) <= limit and (empty or bool(value.strip()))


def validate(board):
    try:
        groups, items = board["groups"], board["items"]
        if not identifier(board["id"]) or board["kind"] not in ("todos", "groceries") or not text(board["name"], 100, False):
            return False
        if not 1 <= len(groups) <= 30 or len(items) > 1000:
            return False
        group_ids = {g["id"] for g in groups}
        if len(group_ids) != len(groups) or len({i["id"] for i in items}) != len(items):
            return False
        if not all(identifier(g["id"]) and text(g["title"], 60, False) for g in groups):
            return False
        for item in items:
            if not identifier(item["id"]) or item["groupID"] not in group_ids:
                return False
            if not text(item["text"], 200, False) or not text(item["quantity"], 80) or not text(item["note"], 2000):
                return False
            steps = item["steps"]
            if len(steps) > 20 or len({s["id"] for s in steps}) != len(steps):
                return False
            if not all(identifier(s["id"]) and text(s["text"], 200, False) and isinstance(s["isCompleted"], bool) for s in steps):
                return False
            for field in ("createdAt", "updatedAt", "completedAt", "reviewAfter"):
                value = item.get(field)
                if value is not None and (not isinstance(value, (int, float)) or not -1e10 < value < 1e10):
                    return False
            if "createdAt" not in item or "updatedAt" not in item:
                return False
        return True
    except (KeyError, TypeError):
        return False


class Conflict(Exception):
    pass


def apply_operation(board, op):
    if not isinstance(op, dict) or not identifier(op.get("id")):
        raise ValueError("Invalid operation identity")
    kind = op.get("kind")
    if kind == "save" and (not isinstance(op.get("item"), dict) or
                           (op.get("base") is not None and not isinstance(op["base"], dict))):
        raise ValueError("Invalid operation")
    result = copy.deepcopy(board)
    # The server clock owns inactivity for shared edits. Swift Date JSON uses 2001 epoch.
    now = time.time() - 978307200

    def item(identity):
        return next((i for i in result["items"] if i["id"] == identity), None)

    if kind == "save":
        incoming, base = op.get("item"), op.get("base")
        target = incoming.get("id")
        if not identifier(target):
            raise ValueError("Invalid operation identity")
        current = item(target)
        if current is None:
            if base is not None:
                raise Conflict("Item was removed")
            result["items"].append(copy.deepcopy(incoming))
            current = result["items"][-1]
            current["createdAt"] = now
        else:
            if base is None:
                raise Conflict("Item already exists")
            # Merge edits to different fields. Concurrent completion survives a text edit.
            changed = [key for key in CONTENT_FIELDS if incoming.get(key) != base.get(key)]
            if any(current.get(key) != base.get(key) and current.get(key) != incoming.get(key) for key in changed):
                raise Conflict("Item changed on another device")
            for key in changed:
                current[key] = incoming[key]
            # Moving a row is not an edit: it must not restart the inactivity
            # clock or clear a "keep for now" snooze.
            if not all(key == "sortIndex" for key in changed):
                current["updatedAt"] = now
                current.pop("reviewAfter", None)
    elif kind in ("delete", "complete", "keep"):
        target = op.get("itemID")
        if not identifier(target):
            raise ValueError("Invalid operation identity")
        current = item(target)
        if kind == "delete":
            result["items"] = [i for i in result["items"] if i["id"] != target]
        elif kind == "complete":
            if not isinstance(op.get("completed"), bool):
                raise ValueError("Completion must be true or false")
            if current is None:
                raise Conflict("Item was removed")
            if bool(current.get("completedAt") is not None) != op["completed"]:
                if op["completed"]:
                    current["completedAt"] = now
                else:
                    current.pop("completedAt", None)
                current["updatedAt"] = now
                current.pop("reviewAfter", None)
        else:
            if current is None:
                raise Conflict("Item was removed")
            current["reviewAfter"] = now + 30 * 86400
    elif kind == "rename":
        name = op.get("name")
        if not isinstance(name, str):
            raise ValueError("Invalid operation")
        result["name"] = name.strip()
    elif kind == "groupSave":
        group = op.get("group")
        if not isinstance(group, dict) or not identifier(group.get("id")) or not isinstance(group.get("title"), str):
            raise ValueError("Invalid operation")
        existing = next((g for g in result["groups"] if g["id"] == group["id"]), None)
        if existing is None:
            result["groups"].append({"id": group["id"], "title": group["title"].strip(),
                                     "sortIndex": group.get("sortIndex", len(result["groups"]))})
        else:
            existing["title"] = group["title"].strip()
            existing["sortIndex"] = group.get("sortIndex", existing.get("sortIndex", 0))
    elif kind == "groupDelete":
        target = op.get("groupID")
        if not identifier(target):
            raise ValueError("Invalid operation identity")
        if len(result["groups"]) <= 1 or not any(g["id"] == target for g in result["groups"]):
            raise ValueError("Cannot remove the only section")
        result["groups"] = [g for g in result["groups"] if g["id"] != target]
        fallback = sorted(result["groups"], key=lambda g: g.get("sortIndex", 0))[0]["id"]
        for entry in result["items"]:
            if entry["groupID"] == target:
                entry["groupID"] = fallback
    else:
        raise ValueError("Unknown operation")
    if not validate(result):
        raise ValueError("Invalid list contents")
    return result


class ListServer(ThreadingHTTPServer):
    def __init__(self, address, database):
        self.database = str(database)
        Path(database).parent.mkdir(parents=True, exist_ok=True)
        with closing(sqlite3.connect(self.database)) as db, db:
            db.execute("CREATE TABLE IF NOT EXISTS lists (token TEXT PRIMARY KEY, board TEXT NOT NULL, revision INTEGER NOT NULL)")
            db.execute("CREATE TABLE IF NOT EXISTS receipts (token TEXT, op TEXT, PRIMARY KEY (token, op))")
        super().__init__(address, Handler)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass  # Never log private link tokens or item contents.

    def reply(self, status, payload, content_type="application/json"):
        raw = json.dumps(payload).encode() if content_type == "application/json" else payload.encode()
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(raw)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(raw)

    def body(self):
        length = int(self.headers.get("Content-Length", "0"))
        if not 0 < length <= LIMIT or self.headers.get_content_type() != "application/json":
            raise ValueError("Expected bounded JSON body")
        data = json.loads(self.rfile.read(length))
        if not isinstance(data, dict):
            raise ValueError("Expected JSON object")
        return data

    def token(self):
        parts = urlparse(self.path).path.strip("/").split("/")
        if len(parts) != 3 or parts[:2] != ["v1", "lists"]:
            return None
        return parts[2]

    def do_GET(self):
        if self.path == "/health":
            return self.reply(200, {"service": "Lists Preview", "ok": True})
        if urlparse(self.path).path.startswith("/join/"):
            token = urlparse(self.path).path.split("/")[-1]
            with closing(sqlite3.connect(self.server.database)) as db, db:
                if not db.execute("SELECT 1 FROM lists WHERE token=?", (token,)).fetchone():
                    return self.reply(404, {"error": "List not found"})
            link = "http://" + self.headers.get("Host", "localhost:8788") + "/join/" + token
            deep = "helipadlists://join?url=" + quote(link, safe="")
            page = '<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1"><title>Shared list</title><body style="background:#f6f4ed;color:#233d33;font:18px system-ui;padding:40px;max-width:520px;margin:auto"><p>HELIPAD · LISTS PREVIEW</p><h1 style="font-family:Georgia;font-weight:normal">A list to share.</h1><p>Open this private list in the separate Lists Preview app. Both devices need access to the preview service.</p><p><a style="display:inline-block;background:#235746;color:white;padding:16px 24px;border-radius:24px;text-decoration:none" href="' + html.escape(deep, quote=True) + '">Open Lists Preview</a></p><p>If the preview app is not installed, ask the sender for the test build. Anyone with this link can edit the list.</p></body>'
            return self.reply(200, page, "text/html; charset=utf-8")
        token = self.token()
        with closing(sqlite3.connect(self.server.database)) as db, db:
            row = db.execute("SELECT board,revision FROM lists WHERE token=?", (token,)).fetchone()
        if not row:
            return self.reply(404, {"error": "List not found"})
        self.reply(200, {"board": json.loads(row[0]), "revision": row[1]})

    def do_POST(self):
        if self.path != "/v1/lists":
            return self.reply(404, {"error": "Not found"})
        try:
            data = self.body()
            if data.get("version") != 1 or not validate(data.get("board")):
                raise ValueError("Invalid list")
            token = secrets.token_urlsafe(32)
            with closing(sqlite3.connect(self.server.database)) as db, db:
                db.execute("BEGIN IMMEDIATE")
                if db.execute("SELECT count(*) FROM lists").fetchone()[0] >= 200:
                    return self.reply(429, {"error": "Preview list limit reached"})
                db.execute("INSERT INTO lists VALUES (?,?,1)", (token, json.dumps(data["board"])))
            self.reply(201, {"token": token, "revision": 1})
        except (ValueError, TypeError, KeyError):
            self.reply(400, {"error": "Invalid list data"})

    def do_PATCH(self):
        token = self.token()
        try:
            op = self.body()
            with closing(sqlite3.connect(self.server.database)) as db, db:
                db.execute("BEGIN IMMEDIATE")
                row = db.execute("SELECT board,revision FROM lists WHERE token=?", (token,)).fetchone()
                if not row:
                    return self.reply(404, {"error": "List not found"})
                board, revision = json.loads(row[0]), row[1]
                if not identifier(op.get("id")):
                    raise ValueError("Invalid operation identity")
                if not db.execute("SELECT 1 FROM receipts WHERE token=? AND op=?", (token, op["id"])).fetchone():
                    board = apply_operation(board, op)
                    revision += 1
                    db.execute("UPDATE lists SET board=?,revision=? WHERE token=?", (json.dumps(board), revision, token))
                    db.execute("INSERT INTO receipts VALUES (?,?)", (token, op["id"]))
            self.reply(200, {"board": board, "revision": revision})
        except Conflict:
            self.reply(409, {"error": "Item changed; review required"})
        except (ValueError, TypeError, KeyError):
            self.reply(400, {"error": "Invalid operation"})


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8788)
    parser.add_argument("--database", default=str(Path(__file__).parent / ".data/lists.sqlite"))
    args = parser.parse_args()
    print(f"Lists Preview service at http://{args.host}:{args.port}. Private test data only.", flush=True)
    ListServer((args.host, args.port), args.database).serve_forever()
