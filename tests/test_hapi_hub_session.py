#!/usr/bin/env python3
"""Black-box tests for the HAPI Hub session helper."""

import json
import subprocess
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "hapi-hub-session.py"


class HubState:
    def __init__(self):
        self.spawn_requests = []
        self.archived = []
        self.permission = "bypassPermissions"
        self.lifecycle = "running"
        self.messages = []
        self.thinking = False
        self.path_exists = True
        self.custom_models = ["deepseek-v4-flash[1m]"]
        self.codex_models = [
            {
                "id": "gpt-5.6-sol",
                "displayName": "GPT-5.6 Sol",
                "isDefault": True,
                "supportedReasoningEfforts": [
                    "low",
                    "medium",
                    "high",
                    "xhigh",
                    "max",
                ],
            }
        ]


class HubHandler(BaseHTTPRequestHandler):
    state = None

    def log_message(self, _format, *_args):
        return

    def body(self):
        size = int(self.headers.get("content-length", "0"))
        return json.loads(self.rfile.read(size).decode("utf-8")) if size else {}

    def reply(self, status, payload):
        raw = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def authenticated(self):
        return self.headers.get("authorization") == "Bearer test-jwt"

    def do_POST(self):
        if self.path == "/api/auth":
            body = self.body()
            if body.get("accessToken") != "test-access-token":
                self.reply(401, {"error": "Invalid access token"})
                return
            self.reply(200, {"token": "test-jwt", "user": {"id": 1}})
            return
        if not self.authenticated():
            self.reply(401, {"error": "Invalid token"})
            return
        if self.path == "/api/machines/machine-1/spawn":
            self.state.spawn_requests.append(self.body())
            self.reply(200, {"type": "success", "sessionId": "session-1"})
            return
        if self.path == "/api/machines/machine-1/paths/exists":
            body = self.body()
            self.reply(
                200,
                {
                    "exists": {
                        path: self.state.path_exists for path in body.get("paths", [])
                    }
                },
            )
            return
        if self.path == "/api/sessions/session-1/archive":
            self.body()
            self.state.archived.append("session-1")
            self.reply(200, {"ok": True})
            return
        self.reply(404, {"error": "Not found"})

    def do_GET(self):
        if not self.authenticated():
            self.reply(401, {"error": "Invalid token"})
            return
        if self.path == "/api/machines":
            self.reply(
                200,
                {
                    "machines": [
                        {
                            "id": "machine-1",
                            "active": True,
                            "metadata": {"displayName": "Test Runner", "host": "test.local"},
                            "runnerState": {"status": "running"},
                        }
                    ]
                },
            )
            return
        if self.path == "/api/claude/custom-models":
            self.reply(200, {"models": self.state.custom_models})
            return
        if self.path == "/api/machines/machine-1/codex-models":
            self.reply(200, {"success": True, "models": self.state.codex_models})
            return
        if self.path == "/api/sessions/session-1":
            self.reply(
                200,
                {
                    "session": {
                        "id": "session-1",
                        "active": True,
                        "thinking": self.state.thinking,
                        "model": "deepseek-v4-flash[1m]",
                        "effort": "max",
                        "permissionMode": self.state.permission,
                        "metadata": {
                            "machineId": "machine-1",
                            "hostPid": 4242,
                            "flavor": "claude",
                            "path": "/work/project",
                            "startedBy": "runner",
                            "startedFromRunner": True,
                            "lifecycleState": self.state.lifecycle,
                        },
                    }
                },
            )
            return
        if self.path == "/api/sessions/session-1/messages?limit=1":
            latest = self.state.messages[-1:]
            self.reply(
                200,
                {
                    "messages": latest,
                    "page": {
                        "epoch": 1,
                        "snapshotHeadSeq": latest[-1].get("seq", 1) if latest else None,
                        "snapshotHeadAt": latest[-1].get("createdAt", 1000)
                        if latest
                        else None,
                    },
                },
            )
            return
        self.reply(404, {"error": "Not found"})


class HapiHubSessionTests(unittest.TestCase):
    def setUp(self):
        self.state = HubState()
        handler = type("BoundHubHandler", (HubHandler,), {"state": self.state})
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.temp = tempfile.TemporaryDirectory()
        self.settings = Path(self.temp.name) / "settings.json"
        self.settings.write_text(
            json.dumps(
                {
                    "apiUrl": "http://127.0.0.1:{}".format(self.server.server_port),
                    "cliApiToken": "test-access-token",
                    "machineId": "machine-1",
                }
            ),
            encoding="utf-8",
        )

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)
        self.temp.cleanup()

    def run_helper(self, *args, check=True):
        return subprocess.run(
            [str(SCRIPT), *args, "--settings", str(self.settings)],
            cwd=ROOT,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=check,
        )

    def runtime_args(self):
        return (
            "--directory",
            "/work/project",
            "--flavor",
            "claude",
            "--model",
            "deepseek-v4-flash[1m]",
            "--effort",
            "max",
            "--permission",
            "yolo",
            "--goal-ref",
            "task:T1-research",
            "--wait-seconds",
            "0.3",
            "--poll-interval",
            "0.05",
        )

    def test_probe_reports_supported_control_plane_without_secrets(self):
        result = self.run_helper("probe")
        payload = json.loads(result.stdout)
        self.assertEqual(payload["status"], "READY")
        self.assertEqual(payload["selected_machine"]["id"], "machine-1")
        self.assertTrue(payload["capabilities"]["spawn"])
        self.assertTrue(payload["capabilities"]["observe_messages"])
        self.assertTrue(payload["capabilities"]["model_catalog"])
        self.assertTrue(payload["capabilities"]["reuse_verification"])
        self.assertNotIn("message", payload["capabilities"])
        self.assertNotIn("test-access-token", result.stdout)
        self.assertNotIn("test-jwt", result.stdout)

    def test_probe_can_ignore_a_stale_saved_machine_id(self):
        settings = json.loads(self.settings.read_text(encoding="utf-8"))
        settings["machineId"] = "stale-machine"
        self.settings.write_text(json.dumps(settings), encoding="utf-8")

        failed = self.run_helper("probe", check=False)
        self.assertNotEqual(failed.returncode, 0)
        self.assertIn("online candidates: machine-1", failed.stderr)

        machines = self.run_helper("machines")
        machine_payload = json.loads(machines.stdout)
        self.assertFalse(machine_payload["configured_machine_online"])
        self.assertEqual(machine_payload["online_machines"][0]["id"], "machine-1")

        result = self.run_helper("probe", "--machine-id", "auto")
        payload = json.loads(result.stdout)
        self.assertEqual(payload["selected_machine"]["id"], "machine-1")

    def test_spawn_preserves_bracketed_model_and_writes_verified_evidence(self):
        evidence_path = Path(self.temp.name) / "runtime-evidence.json"
        result = self.run_helper(
            "spawn", *self.runtime_args(), "--evidence-output", str(evidence_path)
        )
        payload = json.loads(result.stdout)
        self.assertEqual(payload["status"], "VERIFIED")
        self.assertEqual(payload["model"], "deepseek-v4-flash[1m]")
        self.assertEqual(payload["permission"], "bypassPermissions")
        self.assertEqual(payload["goal_ref"], "task:T1-research")
        self.assertFalse(payload["thinking"])
        self.assertEqual(payload["catalog"]["status"], "VERIFIED")
        self.assertEqual(payload["messages_received"], 0)
        self.assertEqual(json.loads(evidence_path.read_text())["session_id"], "session-1")
        self.assertEqual(len(self.state.spawn_requests), 1)
        request = self.state.spawn_requests[0]
        self.assertEqual(request["model"], "deepseek-v4-flash[1m]")
        self.assertEqual(request["permissionMode"], "bypassPermissions")
        self.assertTrue(request["yolo"])
        self.assertEqual(self.state.archived, [])

    def test_dry_run_does_not_spawn(self):
        result = self.run_helper("spawn", *self.runtime_args(), "--dry-run")
        payload = json.loads(result.stdout)
        self.assertEqual(payload["mode"], "dry-run")
        self.assertEqual(payload["requested"]["model"], "deepseek-v4-flash[1m]")
        self.assertEqual(self.state.spawn_requests, [])

    def test_codex_dry_run_maps_yolo_and_reasoning_effort(self):
        result = self.run_helper(
            "spawn",
            "--directory",
            "/work/project",
            "--flavor",
            "codex",
            "--model",
            "gpt-5.6-sol",
            "--effort",
            "xhigh",
            "--permission",
            "yolo",
            "--goal-ref",
            "task:T2-codex",
            "--service-tier",
            "standard",
            "--dry-run",
        )
        requested = json.loads(result.stdout)["requested"]
        self.assertEqual(requested["permissionMode"], "yolo")
        self.assertEqual(requested["modelReasoningEffort"], "xhigh")
        self.assertEqual(requested["serviceTier"], "standard")
        self.assertEqual(self.state.spawn_requests, [])

    def test_placeholder_model_and_effort_are_rejected(self):
        result = self.run_helper(
            "spawn",
            "--directory",
            "/work/project",
            "--flavor",
            "claude",
            "--model",
            "default",
            "--effort",
            "default",
            "--permission",
            "default",
            "--goal-ref",
            "task:T3-placeholder",
            "--dry-run",
            check=False,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("must be an explicit observed value", result.stderr)
        self.assertEqual(self.state.spawn_requests, [])

    def test_mismatch_archives_only_the_new_session(self):
        self.state.permission = "acceptEdits"
        result = self.run_helper("spawn", *self.runtime_args(), check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("permission mismatch", result.stderr)
        self.assertEqual(self.state.archived, ["session-1"])

    def test_non_running_lifecycle_archives_the_new_session(self):
        self.state.lifecycle = "exited"
        result = self.run_helper("spawn", *self.runtime_args(), check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("session lifecycle mismatch", result.stderr)
        self.assertEqual(self.state.archived, ["session-1"])

    def test_existing_message_archives_the_new_session(self):
        self.state.messages = [{"id": "message-1", "seq": 1, "createdAt": 1000}]
        result = self.run_helper("spawn", *self.runtime_args(), check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("already received message(s)", result.stderr)
        self.assertEqual(self.state.archived, ["session-1"])

    def test_catalog_reports_only_proven_models_and_efforts(self):
        result = self.run_helper("catalog", "--flavor", "claude")
        payload = json.loads(result.stdout)
        model_ids = [item["id"] for item in payload["models"]]
        self.assertIn("sonnet", model_ids)
        self.assertIn("deepseek-v4-flash[1m]", model_ids)
        self.assertEqual(payload["models"][-1]["supported_efforts"][-1], "max")

        result = self.run_helper("catalog", "--flavor", "codex")
        payload = json.loads(result.stdout)
        self.assertEqual(payload["models"][0]["id"], "gpt-5.6-sol")
        self.assertIn("xhigh", payload["models"][0]["supported_efforts"])

    def test_unlisted_model_is_rejected_before_spawn(self):
        args = list(self.runtime_args())
        args[args.index("deepseek-v4-flash[1m]")] = "deepseek-v4-flash[1m"
        result = self.run_helper("spawn", *args, check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not in the selected runner catalog", result.stderr)
        self.assertEqual(self.state.spawn_requests, [])

    def test_unproven_codex_effort_is_rejected_before_spawn(self):
        result = self.run_helper(
            "spawn",
            "--directory",
            "/work/project",
            "--flavor",
            "codex",
            "--model",
            "gpt-5.6-sol",
            "--effort",
            "ultra",
            "--permission",
            "yolo",
            "--goal-ref",
            "task:T4-codex",
            "--dry-run",
            check=False,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not proven available", result.stderr)
        self.assertEqual(self.state.spawn_requests, [])

    def test_missing_runner_directory_is_rejected_before_spawn(self):
        self.state.path_exists = False
        result = self.run_helper("spawn", *self.runtime_args(), check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("directory is not available", result.stderr)
        self.assertEqual(self.state.spawn_requests, [])

    def test_reuse_allows_messages_and_records_a_fresh_watermark(self):
        self.state.messages = [
            {"id": "message-7", "seq": 7, "createdAt": 7000}
        ]
        result = self.run_helper(
            "reuse", "--session-id", "session-1", *self.runtime_args()
        )
        payload = json.loads(result.stdout)
        self.assertEqual(payload["phase"], "pre-redispatch")
        self.assertEqual(payload["messages_received"], 1)
        self.assertEqual(payload["message_watermark"]["snapshot_head_seq"], 7)
        self.assertEqual(payload["goal_ref"], "task:T1-research")
        self.assertEqual(self.state.archived, [])

    def test_reuse_rejects_a_thinking_session_without_archiving_it(self):
        self.state.thinking = True
        result = self.run_helper(
            "reuse",
            "--session-id",
            "session-1",
            *self.runtime_args(),
            check=False,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("session is not idle", result.stderr)
        self.assertEqual(self.state.archived, [])


if __name__ == "__main__":
    unittest.main()
