import copy
import json
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from pathlib import Path
from uuid import uuid4
from server import ListServer


class ServiceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.server = ListServer(("127.0.0.1", 0), Path(cls.temp.name) / "test.sqlite")
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.url = f"http://127.0.0.1:{cls.server.server_port}"

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown(); cls.server.server_close(); cls.thread.join(); cls.temp.cleanup()

    def request(self, path, method="GET", payload=None):
        data = json.dumps(payload).encode() if payload is not None else None
        req = urllib.request.Request(self.url + path, data=data, method=method, headers={"Content-Type": "application/json"})
        try:
            response = urllib.request.urlopen(req, timeout=5)
        except urllib.error.HTTPError as error:
            response = error
        return response.code, json.loads(response.read())

    def setUp(self):
        group = {"id": str(uuid4()), "title": "Pantry"}
        self.group = group
        self.item = {"id": str(uuid4()), "groupID": group["id"], "text": "Oat milk", "quantity": "2 cartons", "note": "", "steps": [], "createdAt": 100, "updatedAt": 100}
        board = {"id": str(uuid4()), "kind": "groceries", "name": "Test shopping", "groups": [group], "items": [self.item]}
        code, result = self.request("/v1/lists", "POST", {"version": 1, "board": board})
        self.assertEqual(code, 201)
        self.path = "/v1/lists/" + result["token"]

    def operation(self, kind, **fields):
        return {"id": str(uuid4()), "kind": kind, "now": 100, **fields}

    def test_completion_and_concurrent_content_edit_merge(self):
        self.request(self.path, "PATCH", self.operation("complete", itemID=self.item["id"], completed=True))
        edited = dict(self.item, quantity="3 cartons")
        code, result = self.request(self.path, "PATCH", self.operation("save", item=edited, base=self.item))
        self.assertEqual(code, 200)
        self.assertEqual(result["board"]["items"][0]["quantity"], "3 cartons")
        self.assertIn("completedAt", result["board"]["items"][0])

    def test_retry_is_idempotent(self):
        op = self.operation("complete", itemID=self.item["id"], completed=True)
        first = self.request(self.path, "PATCH", op)
        self.assertEqual(first, self.request(self.path, "PATCH", op))

    def test_same_field_conflict_is_rejected(self):
        self.request(self.path, "PATCH", self.operation("save", item=dict(self.item, text="Almond milk"), base=self.item))
        code, _ = self.request(self.path, "PATCH", self.operation("save", item=dict(self.item, text="Soy milk"), base=self.item))
        self.assertEqual(code, 409)

    def test_edit_after_delete_never_resurrects(self):
        self.request(self.path, "PATCH", self.operation("delete", itemID=self.item["id"]))
        code, _ = self.request(self.path, "PATCH", self.operation("save", item=dict(self.item, text="Updated milk"), base=self.item))
        self.assertEqual(code, 409)
        self.assertEqual(self.request(self.path)[1]["board"]["items"], [])

    def test_different_field_edits_survive(self):
        self.request(self.path, "PATCH", self.operation("save", item=dict(self.item, text="Almond milk"), base=self.item))
        code, result = self.request(self.path, "PATCH", self.operation("save", item=dict(self.item, note="Unsweetened"), base=self.item))
        self.assertEqual(code, 200)
        self.assertEqual(result["board"]["items"][0]["text"], "Almond milk")
        self.assertEqual(result["board"]["items"][0]["note"], "Unsweetened")

    def test_private_link_is_required(self):
        self.assertEqual(self.request("/v1/lists/unknown")[0], 404)
        self.assertEqual(self.request("/v1/lists")[0], 404)

    def test_invalid_operation_is_atomic(self):
        before = self.request(self.path)
        code, _ = self.request(self.path, "PATCH", self.operation("save", item=dict(self.item, text=" "), base=self.item))
        self.assertEqual(code, 400)
        self.assertEqual(before, self.request(self.path))

    def test_rename_changes_the_list_name(self):
        code, result = self.request(self.path, "PATCH", self.operation("rename", name="  Weekend shop  "))
        self.assertEqual(code, 200)
        self.assertEqual(result["board"]["name"], "Weekend shop")

    def test_rename_rejects_a_blank_name(self):
        code, _ = self.request(self.path, "PATCH", self.operation("rename", name="   "))
        self.assertEqual(code, 400)

    def test_group_save_adds_then_renames(self):
        group = {"id": str(uuid4()), "title": "Fruit", "sortIndex": 1}
        code, result = self.request(self.path, "PATCH", self.operation("groupSave", group=group))
        self.assertEqual(code, 200)
        self.assertEqual([g["title"] for g in result["board"]["groups"]], ["Pantry", "Fruit"])
        code, result = self.request(self.path, "PATCH", self.operation("groupSave", group=dict(group, title="Fruit & veg")))
        self.assertEqual(code, 200)
        self.assertEqual(len(result["board"]["groups"]), 2)
        self.assertEqual(result["board"]["groups"][1]["title"], "Fruit & veg")

    def test_group_delete_keeps_its_items_and_refuses_the_last_group(self):
        extra = {"id": str(uuid4()), "title": "Fruit", "sortIndex": 1}
        self.request(self.path, "PATCH", self.operation("groupSave", group=extra))
        code, result = self.request(self.path, "PATCH", self.operation("groupDelete", groupID=extra["id"]))
        self.assertEqual(code, 200)
        self.assertEqual([g["title"] for g in result["board"]["groups"]], ["Pantry"])
        self.assertEqual(len(result["board"]["items"]), 1)
        code, _ = self.request(self.path, "PATCH", self.operation("groupDelete", groupID=self.group["id"]))
        self.assertEqual(code, 400)

    def test_reorder_only_save_preserves_inactivity(self):
        self.request(self.path, "PATCH", self.operation("keep", itemID=self.item["id"]))
        before = self.request(self.path)[1]["board"]["items"][0]
        code, result = self.request(self.path, "PATCH", self.operation("save", item=dict(self.item, sortIndex=1), base=self.item))
        self.assertEqual(code, 200)
        after = result["board"]["items"][0]
        self.assertEqual(after["sortIndex"], 1)
        self.assertEqual(after["updatedAt"], before["updatedAt"], "A move is not an edit")
        self.assertIn("reviewAfter", after, "A move must not clear a snooze")

    def test_reorder_merges_with_a_concurrent_text_edit(self):
        self.request(self.path, "PATCH", self.operation("save", item=dict(self.item, text="Almond milk"), base=self.item))
        code, result = self.request(self.path, "PATCH", self.operation("save", item=dict(self.item, sortIndex=1), base=self.item))
        self.assertEqual(code, 200)
        self.assertEqual(result["board"]["items"][0]["text"], "Almond milk")
        self.assertEqual(result["board"]["items"][0]["sortIndex"], 1)


if __name__ == "__main__":
    unittest.main()
