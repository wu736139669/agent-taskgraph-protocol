#!/usr/bin/env python3
"""Verify observed HAPI session settings before a Goal is dispatched."""

import argparse
import json
import os
import re
import sys
from pathlib import Path


SESSION_RE = re.compile(r"\bSession(?: created)?:\s*([0-9a-fA-F-]{8,})")
REPORTING_RE = re.compile(r"Reporting session\s+([0-9a-fA-F-]{8,})\s+to runner")
WORKING_DIRECTORY_RE = re.compile(r'"workingDirectory"\s*:\s*"([^"]+)"')
PROCESS_PID_RE = re.compile(r'"processPid"\s*:\s*(\d+)')
CONFIG_RE = re.compile(
    r"\b(permissionMode|modelReasoningEffort|model|effort)=([^,\s)]+)"
)


def normalize_permission(value):
    compact = re.sub(r"[-_\s]", "", value).lower()
    aliases = {
        "yolo": "bypassPermissions",
        "bypasspermissions": "bypassPermissions",
        "dangerouslyskippermissions": "bypassPermissions",
        "dangerouslybypassapprovalsandsandbox": "bypassPermissions",
        "acceptedits": "acceptEdits",
        "default": "default",
        "plan": "plan",
    }
    return aliases.get(compact, value)


def parse_start_args(line):
    marker = "Starting hapi CLI with args:"
    if marker not in line:
        return ""
    raw = line.split(marker, 1)[1].strip()
    try:
        args = json.loads(raw)
    except json.JSONDecodeError:
        return ""
    for item in args:
        if item in {"claude", "codex"}:
            return item
    return ""


def parse_log(path):
    observed = {
        "session_id": "",
        "flavor": "",
        "cwd": "",
        "pid": "",
        "model": "",
        "effort": "",
        "permission": "",
        "messages_received": 0,
    }
    with path.open(encoding="utf-8", errors="replace") as handle:
        for line in handle:
            flavor = parse_start_args(line)
            if flavor:
                observed["flavor"] = flavor

            match = WORKING_DIRECTORY_RE.search(line)
            if match:
                observed["cwd"] = match.group(1)

            match = PROCESS_PID_RE.search(line)
            if match:
                observed["pid"] = match.group(1)

            match = SESSION_RE.search(line) or REPORTING_RE.search(line)
            if match:
                observed["session_id"] = match.group(1)

            if "Synced session config for keepalive:" in line:
                values = dict(CONFIG_RE.findall(line))
                if "permissionMode" in values:
                    observed["permission"] = normalize_permission(values["permissionMode"])
                if "model" in values:
                    observed["model"] = values["model"]
                effort = values.get("modelReasoningEffort", values.get("effort"))
                if effort:
                    observed["effort"] = effort

            if "User message received with permission mode:" in line:
                observed["messages_received"] += 1
    return observed


def process_is_running(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def compare(args, observed):
    errors = []
    if args.pid <= 0:
        errors.append("pid must be greater than zero")
    expected = {
        "session_id": args.session_id,
        "flavor": args.flavor,
        "cwd": str(Path(args.cwd).resolve()),
        "pid": str(args.pid),
        "model": args.model,
        "effort": args.effort,
        "permission": normalize_permission(args.permission),
    }

    for key, expected_value in expected.items():
        actual_value = observed.get(key, "")
        if key == "cwd" and actual_value:
            actual_value = str(Path(actual_value).resolve())
        if actual_value != expected_value:
            errors.append(
                "{} mismatch: expected {!r}, observed {!r}".format(
                    key, expected_value, actual_value or "<missing>"
                )
            )

    if args.pid > 0 and not process_is_running(args.pid):
        errors.append("pid {} is not running".format(args.pid))

    if args.phase == "pre-dispatch" and observed["messages_received"]:
        errors.append(
            "session already received {} message(s); pre-dispatch verification must "
            "pass before the first Goal message".format(observed["messages_received"])
        )
    return expected, errors


def build_parser():
    parser = argparse.ArgumentParser(
        description=(
            "Compare approved HAPI settings with the latest settings observed in a "
            "session log. The default pre-dispatch phase also rejects sessions that "
            "already received a message."
        )
    )
    parser.add_argument("--log", required=True, type=Path, help="HAPI session log")
    parser.add_argument("--session-id", required=True)
    parser.add_argument("--pid", required=True, type=int)
    parser.add_argument("--cwd", required=True)
    parser.add_argument("--flavor", required=True, choices=("claude", "codex"))
    parser.add_argument("--model", required=True)
    parser.add_argument("--effort", required=True)
    parser.add_argument("--permission", required=True)
    parser.add_argument(
        "--phase",
        choices=("pre-dispatch", "audit"),
        default="pre-dispatch",
        help="audit permits prior messages but cannot authorize a new dispatch",
    )
    parser.add_argument("--json", action="store_true", help="print structured evidence")
    return parser


def main(argv=None):
    args = build_parser().parse_args(argv)
    log_path = args.log.expanduser().resolve()
    if not log_path.is_file():
        print("ERROR: HAPI log does not exist: {}".format(log_path), file=sys.stderr)
        return 2

    observed = parse_log(log_path)
    expected, errors = compare(args, observed)
    result = {
        "status": "FAILED" if errors else "VERIFIED",
        "phase": args.phase,
        "session_id": observed["session_id"],
        "pid": observed["pid"],
        "flavor": observed["flavor"],
        "cwd": observed["cwd"],
        "model": observed["model"],
        "effort": observed["effort"],
        "permission": observed["permission"],
        "messages_received": observed["messages_received"],
        "evidence": str(log_path),
    }

    if errors:
        if args.json:
            result["expected"] = expected
            result["errors"] = errors
            print(json.dumps(result, ensure_ascii=False, indent=2))
        else:
            for error in errors:
                print("ERROR: {}".format(error), file=sys.stderr)
        return 1

    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        print(
            "HAPI runtime verification passed: session={} pid={} "
            "flavor={} model={} effort={} permission={} cwd={}".format(
                observed["session_id"],
                observed["pid"],
                observed["flavor"],
                observed["model"],
                observed["effort"],
                observed["permission"],
                observed["cwd"],
            )
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
