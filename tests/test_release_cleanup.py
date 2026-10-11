import importlib.util
import json
import os
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "release_cleanup", Path(__file__).resolve().parents[1] / "scripts/delete-old-releases.py")
cleanup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cleanup)


class CleanupTests(unittest.TestCase):
    def setUp(self):
        self.environment = patch.dict(os.environ, {
            "GITHUB_REPOSITORY": cleanup.REPOSITORY,
            "KEEP_TAG": "JDCloud-25.12.2-NSS-new",
        })
        self.environment.start()
        self.addCleanup(self.environment.stop)

    def published_release(self):
        return patch.object(cleanup.subprocess, "check_output", return_value=json.dumps({
            "draft": False, "assets": [{"name": "factory.bin"}],
        }))

    def test_only_allowlisted_release_records_are_deleted(self):
        def api(command, **kwargs):
            if "DELETE" in command:
                return subprocess.CompletedProcess(command, 0)
            release_id = int(command[-1].rsplit("/", 1)[1])
            return subprocess.CompletedProcess(command, 0, json.dumps({
                "id": release_id, "tag_name": cleanup.OLD_RELEASES[release_id],
            }), "")

        with self.published_release(), patch.object(cleanup.subprocess, "run", side_effect=api) as run:
            cleanup.main()
        deletes = [c.args[0] for c in run.call_args_list if "DELETE" in c.args[0]]
        self.assertEqual(len(deletes), 8)
        self.assertEqual({int(c[-1].rsplit("/", 1)[1]) for c in deletes}, set(cleanup.OLD_RELEASES))
        self.assertTrue(all("/releases/" in c[-1] for c in deletes))

    def test_other_repository_is_rejected_before_api_access(self):
        with patch.dict(os.environ, {"GITHUB_REPOSITORY": "another/repo"}), \
                patch.object(cleanup.subprocess, "check_output") as api:
            with self.assertRaises(SystemExit):
                cleanup.main()
            api.assert_not_called()

    def test_replacement_cannot_be_in_delete_list(self):
        with patch.dict(os.environ, {"KEEP_TAG": next(iter(cleanup.OLD_RELEASES.values()))}), \
                patch.object(cleanup.subprocess, "check_output") as api:
            with self.assertRaises(SystemExit):
                cleanup.main()
            api.assert_not_called()

    def test_unpublished_replacement_prevents_cleanup(self):
        with patch.object(cleanup.subprocess, "check_output", return_value='{"draft":true,"assets":[]}'), \
                patch.object(cleanup.subprocess, "run") as run:
            with self.assertRaises(SystemExit):
                cleanup.main()
            run.assert_not_called()

    def test_mismatched_tag_prevents_deletion(self):
        first_id = next(iter(cleanup.OLD_RELEASES))
        result = subprocess.CompletedProcess([], 0, json.dumps({"id": first_id, "tag_name": "different"}), "")
        with self.published_release(), patch.object(cleanup.subprocess, "run", return_value=result) as run:
            with self.assertRaises(SystemExit):
                cleanup.main()
            self.assertEqual(run.call_count, 1)

    def test_missing_records_are_idempotent(self):
        result = subprocess.CompletedProcess([], 1, "", "gh: Not Found (HTTP 404)")
        with self.published_release(), patch.object(cleanup.subprocess, "run", return_value=result) as run:
            cleanup.main()
            self.assertEqual(run.call_count, 8)

    def test_api_error_stops_cleanup(self):
        result = subprocess.CompletedProcess([], 1, "", "gh: Forbidden (HTTP 403)")
        with self.published_release(), patch.object(cleanup.subprocess, "run", return_value=result) as run:
            with self.assertRaises(SystemExit):
                cleanup.main()
            self.assertEqual(run.call_count, 1)


if __name__ == "__main__":
    unittest.main()
