#!/usr/bin/env python3
"""Create and verify HAPI runner sessions through the supported Hub API."""

import argparse
import datetime as dt
import json
import os
import posixpath
import re
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path


class HapiControlError(RuntimeError):
    pass


CLAUDE_MODEL_PRESETS = (
    "sonnet",
    "sonnet[1m]",
    "opus",
    "opus[1m]",
    "fable",
    "fable[1m]",
)
CLAUDE_EFFORTS = ("low", "medium", "high", "xhigh", "max")
CLAUDE_PERMISSIONS = ("default", "acceptEdits", "auto", "bypassPermissions", "plan")
CODEX_PERMISSIONS = ("default", "read-only", "safe-yolo", "yolo")
GOAL_REF = re.compile(r"^task:[A-Za-z0-9][A-Za-z0-9._-]*$")


def compact_path(value):
    if not value:
        return ""
    return posixpath.normpath(str(value))


def safe_api_url(value):
    parsed = urllib.parse.urlsplit(str(value))
    hostname = parsed.hostname or ""
    if ":" in hostname and not hostname.startswith("["):
        hostname = "[{}]".format(hostname)
    netloc = hostname
    if parsed.port is not None:
        netloc = "{}:{}".format(netloc, parsed.port)
    return urllib.parse.urlunsplit(
        (parsed.scheme, netloc, parsed.path.rstrip("/"), "", "")
    )


def normalize_permission(value, flavor):
    compact = str(value).replace("-", "").replace("_", "").lower()
    if compact in {"yolo", "bypasspermissions", "dangerouslyskippermissions"}:
        return "yolo" if flavor == "codex" else "bypassPermissions"
    aliases = {
        "acceptedits": "acceptEdits",
        "default": "default",
        "plan": "plan",
        "auto": "auto",
        "dontask": "dontAsk",
        "manual": "manual",
    }
    return aliases.get(compact, value)


def load_settings(path):
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise HapiControlError("HAPI settings file not found: {}".format(path)) from exc
    except (OSError, json.JSONDecodeError) as exc:
        raise HapiControlError("Cannot read HAPI settings: {}".format(exc)) from exc
    if not isinstance(data, dict):
        raise HapiControlError("HAPI settings must contain a JSON object")
    return data


def resolve_connection(args):
    settings_path = Path(args.settings).expanduser().resolve()
    settings = load_settings(settings_path)
    api_url = os.environ.get("HAPI_API_URL") or settings.get("apiUrl")
    access_token = os.environ.get("CLI_API_TOKEN") or settings.get("cliApiToken")
    if args.machine_id == "auto":
        machine_id = ""
    else:
        machine_id = (
            args.machine_id
            or os.environ.get("HAPI_MACHINE_ID")
            or settings.get("machineId")
        )
    if not api_url:
        raise HapiControlError("HAPI_API_URL/apiUrl is not configured")
    if not access_token:
        raise HapiControlError("CLI_API_TOKEN/cliApiToken is not configured")
    return str(api_url).rstrip("/"), str(access_token), str(machine_id or "")


class HubClient:
    def __init__(self, api_url, access_token, timeout):
        self.api_url = api_url
        self.access_token = access_token
        self.timeout = timeout
        self.jwt = ""

    def url(self, path):
        return self.api_url + "/" + path.lstrip("/")

    def request(self, method, path, payload=None, authenticated=True):
        body = None
        headers = {"accept": "application/json"}
        if payload is not None:
            body = json.dumps(payload).encode("utf-8")
            headers["content-type"] = "application/json"
        if authenticated:
            if not self.jwt:
                raise HapiControlError("HAPI Hub authentication has not completed")
            headers["authorization"] = "Bearer {}".format(self.jwt)
        request = urllib.request.Request(
            self.url(path), data=body, headers=headers, method=method
        )
        try:
            with urllib.request.urlopen(request, timeout=self.timeout) as response:
                raw = response.read().decode("utf-8", errors="replace")
        except urllib.error.HTTPError as exc:
            raw = exc.read().decode("utf-8", errors="replace")
            detail = ""
            try:
                parsed = json.loads(raw)
                if isinstance(parsed, dict):
                    detail = str(parsed.get("error") or parsed.get("message") or "")
            except json.JSONDecodeError:
                detail = ""
            suffix = ": {}".format(detail) if detail else ""
            raise HapiControlError(
                "HAPI Hub {} {} failed with HTTP {}{}".format(
                    method, path, exc.code, suffix
                )
            ) from exc
        except urllib.error.URLError as exc:
            raise HapiControlError(
                "Cannot reach HAPI Hub at {}: {}".format(self.api_url, exc.reason)
            ) from exc
        try:
            return json.loads(raw) if raw else {}
        except json.JSONDecodeError as exc:
            raise HapiControlError(
                "HAPI Hub {} {} returned invalid JSON".format(method, path)
            ) from exc

    def authenticate(self):
        response = self.request(
            "POST", "/api/auth", {"accessToken": self.access_token}, authenticated=False
        )
        token = response.get("token") if isinstance(response, dict) else None
        if not token:
            raise HapiControlError("HAPI Hub authentication returned no session token")
        self.jwt = str(token)


def safe_machine(machine):
    metadata = machine.get("metadata") or {}
    runner_state = machine.get("runnerState") or {}
    return {
        "id": str(machine.get("id") or ""),
        "active": bool(machine.get("active")),
        "name": str(metadata.get("displayName") or metadata.get("name") or ""),
        "host": str(metadata.get("host") or ""),
        "runner_status": str(runner_state.get("status") or ""),
    }


def get_machines(client):
    response = client.request("GET", "/api/machines")
    machines = response.get("machines") if isinstance(response, dict) else None
    if not isinstance(machines, list):
        raise HapiControlError("HAPI Hub returned no machine list")
    return machines


def choose_machine(machines, configured_id):
    active = [
        machine
        for machine in machines
        if machine.get("active")
        and str((machine.get("runnerState") or {}).get("status") or "") == "running"
    ]
    if configured_id:
        for machine in active:
            if str(machine.get("id")) == configured_id:
                return machine
        available = ", ".join(
            "{} ({}/{})".format(
                item.get("id"),
                safe_machine(item)["name"] or "unnamed",
                safe_machine(item)["host"] or "unknown-host",
            )
            for item in active
        )
        suffix = "; online candidates: {}".format(available) if available else ""
        raise HapiControlError(
            "Configured HAPI machine is not online: {}{}. Reconfirm the Execution "
            "machine; use --machine-id auto only to ignore a stale saved default.".format(
                configured_id, suffix
            )
        )
    if len(active) == 1:
        return active[0]
    if not active:
        raise HapiControlError("No online, running HAPI runner machine is available")
    ids = ", ".join(str(machine.get("id")) for machine in active)
    raise HapiControlError(
        "Multiple HAPI runner machines are online; pass --machine-id ({})".format(ids)
    )


def requested_config(args):
    permission = normalize_permission(args.permission, args.flavor)
    body = {
        "directory": args.directory,
        "agent": args.flavor,
        "model": args.model,
        "permissionMode": permission,
        "sessionType": args.session_type,
    }
    if args.worktree_name:
        body["worktreeName"] = args.worktree_name
    if permission in {"yolo", "bypassPermissions"}:
        body["yolo"] = True
    if args.flavor == "codex":
        body["modelReasoningEffort"] = args.effort
        if args.service_tier:
            body["serviceTier"] = args.service_tier
        if args.collaboration_mode:
            body["collaborationMode"] = args.collaboration_mode
    else:
        body["effort"] = args.effort
    return body, permission


def ensure_permission_allowed(permission, flavor):
    allowed = CODEX_PERMISSIONS if flavor == "codex" else CLAUDE_PERMISSIONS
    if permission not in allowed:
        raise HapiControlError(
            "permission {!r} is not supported for {}; available: {}".format(
                permission, flavor, ", ".join(allowed)
            )
        )


def model_catalog(client, machine_id, flavor):
    checked_at = dt.datetime.now(dt.timezone.utc).isoformat()
    if flavor == "claude":
        response = client.request("GET", "/api/claude/custom-models")
        custom = response.get("models") if isinstance(response, dict) else None
        if not isinstance(custom, list):
            raise HapiControlError("HAPI Hub returned no Claude custom model catalog")
        model_ids = []
        for model in (*CLAUDE_MODEL_PRESETS, *custom):
            model_id = str(model).strip()
            if model_id and model_id not in model_ids:
                model_ids.append(model_id)
        models = [
            {
                "id": model_id,
                "display_name": model_id,
                "supported_efforts": list(CLAUDE_EFFORTS),
            }
            for model_id in model_ids
        ]
        source = "HAPI Claude presets + /api/claude/custom-models"
    else:
        response = client.request(
            "GET",
            "/api/machines/{}/codex-models".format(
                urllib.parse.quote(machine_id, safe="")
            ),
        )
        if not isinstance(response, dict) or response.get("success") is not True:
            raise HapiControlError(
                "Cannot discover Codex models for the selected runner: {}".format(
                    (response or {}).get("error") or "unexpected response"
                )
            )
        raw_models = response.get("models")
        if not isinstance(raw_models, list) or not raw_models:
            raise HapiControlError("Selected runner returned an empty Codex model catalog")
        models = []
        for item in raw_models:
            if not isinstance(item, dict):
                continue
            model_id = str(item.get("id") or "").strip()
            if not model_id:
                continue
            efforts = item.get("supportedReasoningEfforts")
            normalized_efforts = []
            if isinstance(efforts, list):
                for effort in efforts:
                    value = str(effort).strip().lower()
                    if value and value not in normalized_efforts:
                        normalized_efforts.append(value)
            models.append(
                {
                    "id": model_id,
                    "display_name": str(item.get("displayName") or model_id),
                    "is_default": item.get("isDefault") is True,
                    "supported_efforts": normalized_efforts,
                }
            )
        if not models:
            raise HapiControlError("Selected runner returned no usable Codex models")
        source = "/api/machines/:id/codex-models"
    return {
        "status": "READY",
        "flavor": flavor,
        "machine_id": machine_id,
        "source": source,
        "checked_at": checked_at,
        "permissions": list(CODEX_PERMISSIONS if flavor == "codex" else CLAUDE_PERMISSIONS),
        "models": models,
    }


def validate_catalog_selection(catalog, model, effort):
    selected = next(
        (item for item in catalog["models"] if item.get("id") == model), None
    )
    if selected is None:
        available = ", ".join(item["id"] for item in catalog["models"])
        raise HapiControlError(
            "model {!r} is not in the selected runner catalog; available: {}".format(
                model, available
            )
        )
    efforts = selected.get("supported_efforts") or []
    if effort.lower() not in efforts:
        available = ", ".join(efforts) if efforts else "none reported"
        raise HapiControlError(
            "effort {!r} is not proven available for model {!r}; available: {}".format(
                effort, model, available
            )
        )
    return {
        "status": "VERIFIED",
        "source": catalog["source"],
        "checked_at": catalog["checked_at"],
        "model": model,
        "effort": effort,
        "model_supported": True,
        "effort_supported": True,
    }


def ensure_directory_exists(client, machine_id, directory):
    response = client.request(
        "POST",
        "/api/machines/{}/paths/exists".format(
            urllib.parse.quote(machine_id, safe="")
        ),
        {"paths": [directory]},
    )
    values = response.get("exists") if isinstance(response, dict) else None
    if not isinstance(values, dict) or values.get(directory) is not True:
        raise HapiControlError(
            "directory is not available on the selected HAPI runner: {}".format(
                directory
            )
        )


def session_observation(session):
    metadata = session.get("metadata") or {}
    flavor = str(metadata.get("flavor") or "")
    effort = session.get("modelReasoningEffort") if flavor == "codex" else session.get("effort")
    return {
        "session_id": str(session.get("id") or ""),
        "machine_id": str(metadata.get("machineId") or ""),
        "pid": str(metadata.get("hostPid") or ""),
        "flavor": flavor,
        "cwd": str(metadata.get("path") or ""),
        "model": str(session.get("model") or ""),
        "effort": str(effort or ""),
        "permission": str(session.get("permissionMode") or ""),
        "active": bool(session.get("active")),
        "thinking": session.get("thinking"),
        "started_by": str(metadata.get("startedBy") or ""),
        "started_from_runner": bool(metadata.get("startedFromRunner")),
        "lifecycle": str(metadata.get("lifecycleState") or ""),
    }


def observation_errors(observed, args, machine_id, expected_permission, message_state, phase):
    expected = {
        "machine_id": machine_id,
        "flavor": args.flavor,
        "cwd": compact_path(args.directory),
        "model": args.model,
        "effort": args.effort,
        "permission": expected_permission,
    }
    errors = []
    for key, value in expected.items():
        actual = observed.get(key, "")
        if key == "cwd":
            actual = compact_path(actual)
        if actual != value:
            errors.append(
                "{} mismatch: expected {!r}, observed {!r}".format(
                    key, value, actual or "<missing>"
                )
            )
    if not observed.get("active"):
        errors.append("session is not active")
    if observed.get("lifecycle") != "running":
        errors.append(
            "session lifecycle mismatch: expected 'running', observed {!r}".format(
                observed.get("lifecycle") or "<missing>"
            )
        )
    if observed.get("thinking") is not False:
        state = "thinking" if observed.get("thinking") is True else "unknown"
        errors.append("session is not idle (thinking state: {})".format(state))
    if not observed.get("pid").isdigit() or int(observed["pid"]) <= 0:
        errors.append("session has no positive host PID")
    if observed.get("started_by") != "runner" and not observed.get("started_from_runner"):
        errors.append("session is not identified as runner-spawned")
    if phase == "pre-dispatch":
        latest_count = message_state["latest_page_count"]
        snapshot_head = message_state["snapshot_head_seq"]
        if latest_count != 0 or snapshot_head is not None:
            errors.append(
                "session already received message(s) before verification "
                "(latest page: {}, snapshot head: {!r})".format(
                    latest_count, snapshot_head
                )
            )
    return errors


def message_snapshot(client, session_id):
    response = client.request(
        "GET",
        "/api/sessions/{}/messages?limit=1".format(
            urllib.parse.quote(session_id, safe="")
        ),
    )
    messages = response.get("messages") if isinstance(response, dict) else None
    page = response.get("page") if isinstance(response, dict) else None
    if not isinstance(messages, list) or not isinstance(page, dict):
        raise HapiControlError("HAPI Hub returned invalid message watermark data")
    latest = messages[-1] if messages else {}
    return {
        "latest_page_count": len(messages),
        "latest_message_id": str(latest.get("id") or "") if isinstance(latest, dict) else "",
        "snapshot_head_seq": page.get("snapshotHeadSeq"),
        "snapshot_head_at": page.get("snapshotHeadAt"),
        "epoch": page.get("epoch"),
        "captured_at": dt.datetime.now(dt.timezone.utc).isoformat(),
    }


def inspect_session(client, session_id):
    response = client.request(
        "GET", "/api/sessions/{}".format(urllib.parse.quote(session_id, safe=""))
    )
    session = response.get("session") if isinstance(response, dict) else None
    if not isinstance(session, dict):
        raise HapiControlError("HAPI Hub returned no session metadata")
    return session


def verify_until_ready(client, session_id, args, machine_id, expected_permission, phase):
    deadline = time.monotonic() + args.wait_seconds
    last_observed = {}
    last_errors = ["session metadata has not arrived"]
    message_state = {}
    while time.monotonic() <= deadline:
        try:
            session = inspect_session(client, session_id)
            last_observed = session_observation(session)
            message_state = message_snapshot(client, session_id)
            last_errors = observation_errors(
                last_observed,
                args,
                machine_id,
                expected_permission,
                message_state,
                phase,
            )
            if not last_errors:
                return last_observed, message_state
        except HapiControlError as exc:
            last_errors = [str(exc)]
        time.sleep(args.poll_interval)
    detail = "; ".join(last_errors)
    raise HapiControlError(
        "HAPI session {} failed {} verification: {}".format(
            session_id, phase, detail
        )
    )


def archive_session(client, session_id):
    client.request(
        "POST",
        "/api/sessions/{}/archive".format(urllib.parse.quote(session_id, safe="")),
        {},
    )


def evidence(observed, message_state, args, phase, catalog_evidence, machine):
    return {
        "status": "VERIFIED",
        "phase": phase,
        "verification_id": str(uuid.uuid4()),
        "goal_ref": args.goal_ref,
        "session_id": observed["session_id"],
        "machine_id": observed["machine_id"],
        "machine_name": safe_machine(machine)["name"],
        "machine_host": safe_machine(machine)["host"],
        "pid": observed["pid"],
        "flavor": observed["flavor"],
        "cwd": observed["cwd"],
        "model": observed["model"],
        "effort": observed["effort"],
        "permission": observed["permission"],
        "messages_received": message_state["latest_page_count"],
        "message_watermark": message_state,
        "active": observed["active"],
        "thinking": observed["thinking"],
        "lifecycle": observed["lifecycle"],
        "catalog": catalog_evidence,
        "evidence": "HAPI Hub session metadata, model catalog, and message watermark",
        "verified_at": dt.datetime.now(dt.timezone.utc).isoformat(),
    }


def write_json_atomic(path, value):
    target = Path(path).expanduser().resolve()
    target.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(
        prefix=".{}-".format(target.name), dir=str(target.parent)
    )
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(value, handle, ensure_ascii=False, indent=2)
            handle.write("\n")
        os.chmod(temporary, 0o600)
        os.replace(temporary, target)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def connect(args):
    api_url, access_token, configured_machine_id = resolve_connection(args)
    client = HubClient(api_url, access_token, args.http_timeout)
    client.authenticate()
    machines = get_machines(client)
    machine = choose_machine(machines, configured_machine_id)
    return client, machine, machines


def command_machines(args):
    api_url, access_token, configured_machine_id = resolve_connection(args)
    client = HubClient(api_url, access_token, args.http_timeout)
    client.authenticate()
    machines = get_machines(client)
    online = [
        safe_machine(item)
        for item in machines
        if item.get("active")
        and str((item.get("runnerState") or {}).get("status") or "") == "running"
    ]
    print(
        json.dumps(
            {
                "status": "READY",
                "api_url": safe_api_url(client.api_url),
                "configured_machine_id": configured_machine_id,
                "configured_machine_online": any(
                    item["id"] == configured_machine_id for item in online
                ),
                "online_machines": online,
            },
            ensure_ascii=False,
            indent=2,
        )
    )


def command_probe(args):
    client, machine, machines = connect(args)
    result = {
        "status": "READY",
        "api_url": safe_api_url(client.api_url),
        "selected_machine": safe_machine(machine),
        "online_machines": [
            safe_machine(item)
            for item in machines
            if item.get("active")
            and str((item.get("runnerState") or {}).get("status") or "") == "running"
        ],
        "capabilities": {
            "spawn": True,
            "inspect": True,
            "observe_messages": True,
            "archive": True,
            "path_preflight": True,
            "model_catalog": True,
            "reuse_verification": True,
        },
    }
    print(json.dumps(result, ensure_ascii=False, indent=2))


def command_catalog(args):
    client, machine, _ = connect(args)
    machine_id = str(machine.get("id"))
    result = model_catalog(client, machine_id, args.flavor)
    result["machine"] = safe_machine(machine)
    print(json.dumps(result, ensure_ascii=False, indent=2))


def command_spawn(args):
    client, machine, _ = connect(args)
    machine_id = str(machine.get("id"))
    body, expected_permission = requested_config(args)
    ensure_permission_allowed(expected_permission, args.flavor)
    ensure_directory_exists(client, machine_id, args.directory)
    catalog = model_catalog(client, machine_id, args.flavor)
    catalog_evidence = validate_catalog_selection(catalog, args.model, args.effort)
    if args.dry_run:
        result = {
            "status": "READY",
            "mode": "dry-run",
            "machine": safe_machine(machine),
            "requested": body,
            "goal_ref": args.goal_ref,
            "catalog": catalog_evidence,
        }
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return

    response = client.request(
        "POST",
        "/api/machines/{}/spawn".format(urllib.parse.quote(machine_id, safe="")),
        body,
    )
    if response.get("type") != "success" or not response.get("sessionId"):
        raise HapiControlError(
            "HAPI spawn failed: {}".format(
                response.get("message") or "unexpected response"
            )
        )
    session_id = str(response["sessionId"])
    try:
        observed, message_state = verify_until_ready(
            client, session_id, args, machine_id, expected_permission, "pre-dispatch"
        )
    except HapiControlError as exc:
        if not args.keep_on_failure:
            try:
                archive_session(client, session_id)
            except HapiControlError as archive_error:
                raise HapiControlError(
                    "{}; automatic archive also failed: {}".format(exc, archive_error)
                ) from archive_error
        raise
    result = evidence(
        observed, message_state, args, "pre-dispatch", catalog_evidence, machine
    )
    if args.evidence_output:
        write_json_atomic(args.evidence_output, result)
    print(json.dumps(result, ensure_ascii=False, indent=2))


def command_verify(args):
    client, machine, _ = connect(args)
    expected_permission = normalize_permission(args.permission, args.flavor)
    ensure_permission_allowed(expected_permission, args.flavor)
    machine_id = str(machine.get("id"))
    ensure_directory_exists(client, machine_id, args.directory)
    catalog = model_catalog(client, machine_id, args.flavor)
    catalog_evidence = validate_catalog_selection(catalog, args.model, args.effort)
    observed, message_state = verify_until_ready(
        client,
        args.session_id,
        args,
        machine_id,
        expected_permission,
        "pre-dispatch",
    )
    result = evidence(
        observed, message_state, args, "pre-dispatch", catalog_evidence, machine
    )
    if args.evidence_output:
        write_json_atomic(args.evidence_output, result)
    print(json.dumps(result, ensure_ascii=False, indent=2))


def command_reuse(args):
    client, machine, _ = connect(args)
    expected_permission = normalize_permission(args.permission, args.flavor)
    ensure_permission_allowed(expected_permission, args.flavor)
    machine_id = str(machine.get("id"))
    ensure_directory_exists(client, machine_id, args.directory)
    catalog = model_catalog(client, machine_id, args.flavor)
    catalog_evidence = validate_catalog_selection(catalog, args.model, args.effort)
    observed, message_state = verify_until_ready(
        client,
        args.session_id,
        args,
        machine_id,
        expected_permission,
        "pre-redispatch",
    )
    result = evidence(
        observed, message_state, args, "pre-redispatch", catalog_evidence, machine
    )
    if args.evidence_output:
        write_json_atomic(args.evidence_output, result)
    print(json.dumps(result, ensure_ascii=False, indent=2))


def command_archive(args):
    api_url, access_token, _ = resolve_connection(args)
    client = HubClient(api_url, access_token, args.http_timeout)
    client.authenticate()
    archive_session(client, args.session_id)
    print(json.dumps({"status": "ARCHIVED", "session_id": args.session_id}, indent=2))


def add_connection_arguments(parser):
    parser.add_argument(
        "--settings",
        default=os.environ.get("HAPI_SETTINGS", "~/.hapi/settings.json"),
        help="HAPI settings JSON (default: ~/.hapi/settings.json)",
    )
    parser.add_argument(
        "--machine-id",
        help=(
            "Exact online HAPI runner machine ID; 'auto' ignores a stale saved ID "
            "and succeeds only when one runner is online"
        ),
    )
    parser.add_argument("--http-timeout", type=float, default=10.0)


def add_runtime_arguments(parser, include_session_id=False):
    if include_session_id:
        parser.add_argument("--session-id", required=True)
    parser.add_argument("--directory", required=True)
    parser.add_argument("--flavor", required=True, choices=("claude", "codex"))
    parser.add_argument("--model", required=True)
    parser.add_argument("--effort", required=True)
    parser.add_argument("--permission", required=True)
    parser.add_argument(
        "--goal-ref",
        required=True,
        help="Stable Goal reference in task:<id> form",
    )
    parser.add_argument("--wait-seconds", type=float, default=30.0)
    parser.add_argument("--poll-interval", type=float, default=0.5)
    parser.add_argument("--evidence-output")


def build_parser():
    parser = argparse.ArgumentParser(
        description=(
            "Use the supported HAPI Hub API to discover, create, and verify visible "
            "runner-backed sessions without printing credentials."
        )
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    machines = subparsers.add_parser(
        "machines", help="List online runners even when the saved machine ID is stale"
    )
    add_connection_arguments(machines)
    machines.set_defaults(handler=command_machines)

    probe = subparsers.add_parser("probe", help="Authenticate and list safe runner capability data")
    add_connection_arguments(probe)
    probe.set_defaults(handler=command_probe)

    catalog = subparsers.add_parser(
        "catalog", help="List models, efforts, and permissions proven on one runner"
    )
    add_connection_arguments(catalog)
    catalog.add_argument("--flavor", required=True, choices=("claude", "codex"))
    catalog.set_defaults(handler=command_catalog)

    spawn = subparsers.add_parser("spawn", help="Create and pre-dispatch verify a HAPI session")
    add_connection_arguments(spawn)
    add_runtime_arguments(spawn)
    spawn.add_argument("--session-type", choices=("simple", "worktree"), default="simple")
    spawn.add_argument("--worktree-name")
    spawn.add_argument("--service-tier", choices=("fast", "standard"))
    spawn.add_argument("--collaboration-mode", choices=("default", "plan"))
    spawn.add_argument("--dry-run", action="store_true")
    spawn.add_argument(
        "--keep-on-failure",
        action="store_true",
        help="Do not archive a newly created session when verification fails",
    )
    spawn.set_defaults(handler=command_spawn)

    verify = subparsers.add_parser("verify", help="Verify an existing HAPI session before dispatch")
    add_connection_arguments(verify)
    add_runtime_arguments(verify, include_session_id=True)
    verify.set_defaults(handler=command_verify)

    reuse = subparsers.add_parser(
        "reuse", help="Verify an idle existing HAPI session before redispatch"
    )
    add_connection_arguments(reuse)
    add_runtime_arguments(reuse, include_session_id=True)
    reuse.set_defaults(handler=command_reuse)

    archive = subparsers.add_parser("archive", help="Archive one explicitly identified HAPI session")
    add_connection_arguments(archive)
    archive.add_argument("--session-id", required=True)
    archive.set_defaults(handler=command_archive)
    return parser


def main(argv=None):
    args = build_parser().parse_args(argv)
    if getattr(args, "wait_seconds", 0) < 0:
        raise HapiControlError("--wait-seconds must be non-negative")
    if getattr(args, "poll_interval", 0.5) <= 0:
        raise HapiControlError("--poll-interval must be positive")
    for field in ("model", "effort"):
        value = str(getattr(args, field, "") or "").strip().lower()
        if value in {"default", "pending", "auto", "待确认"}:
            raise HapiControlError(
                "--{} must be an explicit observed value, not {!r}".format(field, value)
            )
    goal_ref = str(getattr(args, "goal_ref", "") or "")
    if goal_ref and not GOAL_REF.fullmatch(goal_ref):
        raise HapiControlError("--goal-ref must use stable task:<id> form")
    args.handler(args)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except HapiControlError as exc:
        print("ERROR: {}".format(exc), file=sys.stderr)
        sys.exit(1)
