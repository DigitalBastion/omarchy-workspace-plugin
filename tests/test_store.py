import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "bin" / "workspace-opener-store"


class StoreTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.home = Path(self.temp.name) / "home"
        self.projects = self.home / "Projects"
        self.env = os.environ | {
            "HOME": str(self.home),
            "XDG_CONFIG_HOME": str(self.home / "config"),
            "XDG_STATE_HOME": str(self.home / "state"),
        }

    def tearDown(self):
        self.temp.cleanup()

    def invoke(self, action, request=None):
        result = subprocess.run(
            ["python3", str(HELPER), action], input=json.dumps(request or {}) + "\n",
            text=True, capture_output=True, env=self.env, check=False,
        )
        return result.returncode, json.loads(result.stdout)

    def project(self, group, name):
        path = self.projects / group / name
        path.mkdir(parents=True)
        return path

    def test_scan_observes_exact_depth_hidden_items_and_src_layout(self):
        plain = self.project("Acme", "Website")
        split = self.project("Acme", "Backend")
        (split / "src").mkdir()
        (split / "output").mkdir()
        (split / ".cache").mkdir()
        (split / "README").write_text("extra visible item", encoding="utf-8")
        exact = self.project("DigitalBastion", "Plugin")
        (exact / "src").mkdir()
        (exact / "output").mkdir()
        (self.projects / ".hidden").mkdir(parents=True)
        (self.projects / ".hidden" / "ignored").mkdir()
        (self.projects / "Acme" / ".ignored").mkdir()

        _, response = self.invoke("snapshot")
        self.assertEqual(response["preferences"]["editor"], "default")
        self.assertGreaterEqual(len(response["editorChoices"]), 1)
        self.assertEqual(response["editorChoices"][0]["id"], "default")
        items = {item["id"]: item for item in response["projects"]}
        self.assertEqual(set(items), {"Acme/Backend", "Acme/Website", "DigitalBastion/Plugin"})
        self.assertEqual(items["Acme/Backend"]["launchPath"], str(split))
        self.assertEqual(items["DigitalBastion/Plugin"]["launchPath"], str(exact / "src"))
        self.assertEqual(items["DigitalBastion/Plugin"]["opens"], "src")
        self.assertEqual(items["Acme/Website"]["launchPath"], str(plain))

    def test_history_dismissal_is_section_specific_and_launch_restores_it(self):
        self.project("Acme", "Backend")
        self.invoke("snapshot")
        self.invoke("history", {"action": "record", "id": "Acme/Backend"})
        _, dismissed = self.invoke("history", {"action": "dismiss", "id": "Acme/Backend", "section": "Recent"})
        entry = dismissed["history"]["entries"]["Acme/Backend"]
        self.assertEqual(entry["count"], 1)
        self.assertIn("recent", entry["dismissed"])
        self.assertNotIn("mostUsed", entry["dismissed"])
        _, restored = self.invoke("history", {"action": "record", "id": "Acme/Backend"})
        entry = restored["history"]["entries"]["Acme/Backend"]
        self.assertEqual(entry["count"], 2)
        self.assertNotIn("dismissed", entry)

    def test_snapshot_prunes_history_for_removed_projects(self):
        project = self.project("Acme", "Backend")
        self.invoke("snapshot")
        self.invoke("history", {"action": "record", "id": "Acme/Backend"})
        project.rmdir()
        _, response = self.invoke("snapshot")
        self.assertEqual(response["history"]["entries"], {})

    def test_malformed_history_is_preserved_and_reported(self):
        history = self.home / "state" / "omarchy" / "workspace-opener" / "history.json"
        history.parent.mkdir(parents=True)
        history.write_text("not json", encoding="utf-8")
        _, response = self.invoke("snapshot")
        self.assertIn("error", response)
        self.assertEqual(history.read_text(encoding="utf-8"), "not json")

    def test_editor_choices_follow_configured_order(self):
        config = self.home / "config" / "omarchy" / "workspace-opener" / "config.json"
        config.parent.mkdir(parents=True)
        config.write_text(json.dumps({"version": 1, "editor": "cursor", "editors": ["cursor"]}), encoding="utf-8")
        _, response = self.invoke("snapshot")
        self.assertEqual(response["editorChoices"], [{"id": "cursor", "label": "Cursor"}])


if __name__ == "__main__":
    unittest.main()
