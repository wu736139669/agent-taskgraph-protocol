#!/usr/bin/env python3
"""Detect TaskGraph control-plane loops before they consume more sessions."""

import argparse
import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


FIELD_ROW = re.compile(r"^\|\s*([^|]+?)\s*\|\s*([^|]*?)\s*\|\s*$")
CONTROL_SUBJECT = re.compile(r"^(?:pmo|chore\(pmo\)|agent-taskgraph)(?::|\b)", re.I)
CONTROL_PREFIXES = (".agent-taskgraph/", ".agent-queue/")
CONTROL_FAILURES = {"HARNESS_INVALID", "DISPATCH_INVALID", "RUNTIME_INVALID"}
DEFAULTS = {
    "first_worker_minutes": 5,
    "no_product_minutes": 30,
    "max_control_commits": 5,
    "max_worktrees": 8,
    "max_consecutive_invalid": 1,
}


def run_git(project, *args):
    try:
        return subprocess.run(
            ["git", "-C", str(project), *args],
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        ).stdout
    except (OSError, subprocess.CalledProcessError):
        return ""


def markdown_fields(path):
    fields = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        match = FIELD_ROW.match(raw)
        if not match:
            continue
        key = match.group(1).strip()
        if key and set(key) <= {"-", ":"}:
            continue
        fields[key] = match.group(2).strip()
    return fields


def parse_time(value, fallback=None):
    raw = value.strip().replace("Z", "+00:00")
    try:
        parsed = datetime.fromisoformat(raw)
    except ValueError:
        return fallback
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def failure_class(fields):
    explicit = fields.get("Failure class", "").strip().upper()
    if explicit and explicit != "PENDING":
        return explicit
    result = fields.get("验收结果", "").strip().upper()
    if not result or result == "PENDING":
        return "PENDING"
    if "INVALID" in result:
        return "HARNESS_INVALID"
    if result.startswith("FAIL") or result.startswith("❌"):
        return "PRODUCT_FAIL"
    if result.startswith("BLOCKED"):
        return "OWNER_DECISION"
    return "OTHER"


def failure_boundary(task_id, fields):
    explicit = fields.get("Failure boundary", "").strip()
    if explicit and explicit.upper() != "PENDING":
        return explicit
    return re.sub(r"-(?:R|H)\d+[A-Z]?$", "", task_id, flags=re.I)


def task_records(instance, states):
    records = []
    for state in states:
        state_dir = instance / "queue" / state
        if not state_dir.is_dir():
            continue
        for task_dir in state_dir.iterdir():
            ledger = task_dir / "ledger.md"
            if task_dir.name.startswith(".") or not ledger.is_file():
                continue
            fields = markdown_fields(ledger)
            fallback = datetime.fromtimestamp(ledger.stat().st_mtime, timezone.utc)
            records.append(
                {
                    "task_id": task_dir.name,
                    "state": state,
                    "fields": fields,
                    "updated_at": parse_time(fields.get("最后更新", ""), fallback),
                }
            )
    return records


def worktree_count(project):
    output = run_git(project, "worktree", "list", "--porcelain")
    return sum(1 for raw in output.splitlines() if raw.startswith("worktree "))


def commit_records(project):
    output = run_git(
        project,
        "log",
        "HEAD",
        "--since=7.days",
        "--format=@@@%H%x09%ct%x09%s",
        "--name-only",
    )
    records = []
    current = None
    for raw in output.splitlines() + ["@@@END\t0\tEND"]:
        if raw.startswith("@@@"):
            if current:
                paths = current.pop("paths")
                outside_control = any(
                    path and not path.startswith(CONTROL_PREFIXES) for path in paths
                )
                current["control_only"] = (
                    CONTROL_SUBJECT.search(current["subject"]) is not None
                    or (bool(paths) and not outside_control)
                )
                records.append(current)
            if raw.startswith("@@@END"):
                break
            commit_hash, timestamp, subject = raw[3:].split("\t", 2)
            current = {
                "hash": commit_hash,
                "timestamp": datetime.fromtimestamp(int(timestamp), timezone.utc),
                "subject": subject,
                "paths": [],
            }
        elif current and raw.strip():
            current["paths"].append(raw.strip())
    return records


def consecutive_control_invalids(records):
    grouped = {}
    for record in records:
        fields = record["fields"]
        kind = failure_class(fields)
        if kind == "PENDING":
            continue
        boundary = failure_boundary(record["task_id"], fields)
        grouped.setdefault(boundary, []).append((record["updated_at"], kind))

    worst_boundary = ""
    worst_count = 0
    for boundary, outcomes in grouped.items():
        count = 0
        for _, kind in sorted(outcomes, reverse=True):
            if kind not in CONTROL_FAILURES:
                break
            count += 1
        if count > worst_count:
            worst_boundary = boundary
            worst_count = count
    return worst_boundary, worst_count


def evaluate(project, thresholds):
    instance = project / ".agent-taskgraph"
    reasons = []
    warnings = []
    now = datetime.now(timezone.utc)
    records = task_records(instance, ("inbox", "active", "review", "failed"))
    active = [record for record in records if record["state"] in {"active", "review"}]
    inbox = [record for record in records if record["state"] == "inbox"]
    failed = [record for record in records if record["state"] == "failed"]

    overdue_inbox = []
    for record in inbox:
        fields = record["fields"]
        if fields.get("Session ID", "").upper() != "PENDING":
            continue
        approved = parse_time(fields.get("Batch approved at", ""), record["updated_at"])
        age_minutes = (now - approved).total_seconds() / 60
        if age_minutes > thresholds["first_worker_minutes"]:
            overdue_inbox.append(record["task_id"])
    if overdue_inbox:
        reasons.append(
            "time-to-first-worker exceeded {}m for: {}".format(
                thresholds["first_worker_minutes"], ", ".join(sorted(overdue_inbox))
            )
        )

    boundary, invalid_count = consecutive_control_invalids(failed)
    if invalid_count > thresholds["max_consecutive_invalid"]:
        reasons.append(
            "{} consecutive control-plane INVALID outcomes at {} (limit {})".format(
                invalid_count, boundary, thresholds["max_consecutive_invalid"]
            )
        )

    worktrees = worktree_count(project)
    if worktrees > thresholds["max_worktrees"]:
        reasons.append(
            "{} registered worktrees exceed limit {}".format(
                worktrees, thresholds["max_worktrees"]
            )
        )

    commits = commit_records(project)
    latest_product = None
    latest_control = None
    control_after_product = 0
    for commit in commits:
        if commit["control_only"]:
            if latest_control is None or commit["timestamp"] > latest_control:
                latest_control = commit["timestamp"]
        elif latest_product is None or commit["timestamp"] > latest_product:
            latest_product = commit["timestamp"]
    for commit in commits:
        if commit["control_only"] and (
            latest_product is None or commit["timestamp"] > latest_product
        ):
            control_after_product += 1

    stalled_minutes = 0
    if latest_control and latest_product and latest_control > latest_product:
        stalled_minutes = int((latest_control - latest_product).total_seconds() / 60)
    elif latest_control and latest_product is None:
        stalled_minutes = int((now - latest_control).total_seconds() / 60)
    if (
        active
        and control_after_product >= thresholds["max_control_commits"]
        and stalled_minutes >= thresholds["no_product_minutes"]
    ):
        reasons.append(
            "{} control-only commits and {}m without a product commit".format(
                control_after_product, stalled_minutes
            )
        )
    elif control_after_product >= 3:
        warnings.append(
            "{} control-only commits since the latest product commit".format(
                control_after_product
            )
        )

    metrics = {
        "inbox_tasks": len(inbox),
        "active_or_review_tasks": len(active),
        "failed_tasks": len(failed),
        "registered_worktrees": worktrees,
        "consecutive_control_invalids": invalid_count,
        "invalid_boundary": boundary or None,
        "control_commits_after_product": control_after_product,
        "stalled_minutes": stalled_minutes,
    }
    return {
        "status": "CIRCUIT_OPEN" if reasons else "HEALTHY",
        "reasons": reasons,
        "warnings": warnings,
        "metrics": metrics,
        "required_action": (
            "Stop spawning. Reuse the current Goal/session for one bounded control-plane "
            "repair, or ask the Owner to downgrade to Lite/single-agent mode."
            if reasons
            else "Continue with the approved dispatch."
        ),
    }


def main(argv):
    parser = argparse.ArgumentParser(
        description="Detect Agent TaskGraph operational loops before dispatch"
    )
    parser.add_argument("project_directory")
    parser.add_argument("--json", action="store_true")
    for key, default in DEFAULTS.items():
        parser.add_argument("--{}".format(key.replace("_", "-")), type=int, default=default)
    args = parser.parse_args(argv[1:])
    project = Path(args.project_directory).expanduser().resolve()
    if not (project / ".agent-taskgraph").is_dir():
        print("Project is not initialized with .agent-taskgraph", file=sys.stderr)
        return 2
    thresholds = {
        key: getattr(args, key)
        for key in DEFAULTS
    }
    result = evaluate(project, thresholds)
    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        print("Operational health: {}".format(result["status"]))
        for reason in result["reasons"]:
            print("ERROR: {}".format(reason))
        for warning in result["warnings"]:
            print("WARNING: {}".format(warning))
        print("Metrics: {}".format(json.dumps(result["metrics"], ensure_ascii=False)))
        print("Action: {}".format(result["required_action"]))
    return 1 if result["status"] == "CIRCUIT_OPEN" else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
