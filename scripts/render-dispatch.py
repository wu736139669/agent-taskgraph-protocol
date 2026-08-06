#!/usr/bin/env python3
"""Render a validated, runtime-neutral Role bootstrap message."""

import argparse
import re
import sys
from pathlib import Path


STATES = ("inbox", "active", "review", "done", "failed")
FIELD_ROW = re.compile(r"^\|\s*([^|]+?)\s*\|\s*([^|]*?)\s*\|\s*$")
ROLE_REF = re.compile(r"^role:([a-z0-9][a-z0-9-]*)$")
SAFE_REVISION = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]*$")
PLACEHOLDERS = ("<", "pending", "待确认", "待填写", "unknown", "tbd")
GOAL_ROLE = re.compile(r"^-\s*Role ref[：:]\s*`?([^`]+?)`?\s*$")


class DispatchError(RuntimeError):
    pass


def is_placeholder(value):
    lowered = value.strip().lower()
    return not lowered or any(token in lowered for token in PLACEHOLDERS)


def table_fields(path):
    fields = {}
    duplicates = set()
    for raw in path.read_text(encoding="utf-8").splitlines():
        match = FIELD_ROW.match(raw)
        if not match:
            continue
        key = match.group(1).strip()
        if not key or set(key) <= {"-", ":"}:
            continue
        if key in fields:
            duplicates.add(key)
        fields[key] = match.group(2).strip().strip("`")
    if duplicates:
        raise DispatchError(
            "duplicate dispatch fields: {}".format(", ".join(sorted(duplicates)))
        )
    return fields


def resolve_task(project, goal_ref):
    if not goal_ref.startswith("task:"):
        raise DispatchError("--goal must use stable task:<id> syntax")
    task_id = goal_ref.split(":", 1)[1]
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", task_id):
        raise DispatchError("task ID contains unsupported characters")
    matches = [
        project / ".agent-taskgraph" / "queue" / state / task_id
        for state in STATES
        if (project / ".agent-taskgraph" / "queue" / state / task_id).is_dir()
    ]
    if len(matches) != 1:
        raise DispatchError(
            "{} must resolve to exactly one queue task; found {}".format(
                goal_ref, len(matches)
            )
        )
    return task_id, matches[0]


def expected_ack(fields):
    return (
        "IDENTITY_READY dispatch_id={Dispatch ID} role={Role ref} "
        "team_revision={Team revision} goal={Goal ref} "
        "context_revision={Context revision}"
    ).format(**fields)


def quoted_metadata(path, label):
    prefix = "> {}:".format(label)
    for raw in path.read_text(encoding="utf-8").splitlines():
        if raw.startswith(prefix):
            return raw.split(":", 1)[1].strip().strip("`")
    return ""


def goal_role_ref(path):
    for raw in path.read_text(encoding="utf-8").splitlines():
        match = GOAL_ROLE.match(raw)
        if match:
            return match.group(1).strip()
    return ""


def validate(project, task_id, task_dir, fields):
    required = (
        "Task ID",
        "Dispatch ID",
        "Role ref",
        "Role profile",
        "Role lifecycle",
        "Team revision",
        "Goal ref",
        "Context manifest",
        "Context revision",
        "Continuity",
        "Expected identity ACK",
    )
    missing = [key for key in required if is_placeholder(fields.get(key, ""))]
    if missing:
        raise DispatchError(
            "dispatch requires concrete fields: {}".format(", ".join(missing))
        )
    if fields["Task ID"] != task_id or fields["Goal ref"] != "task:{}".format(task_id):
        raise DispatchError("dispatch Task ID and Goal ref must match the queue task")
    role_match = ROLE_REF.fullmatch(fields["Role ref"])
    if not role_match:
        raise DispatchError("Role ref must use role:<lowercase-id>")
    role_id = role_match.group(1)
    expected_profile = "roles/{}/ROLE.md".format(role_id)
    if fields["Role profile"] != expected_profile:
        raise DispatchError("Role profile must be {}".format(expected_profile))
    role_path = project / ".agent-taskgraph" / expected_profile
    if not role_path.is_file():
        raise DispatchError("Role profile does not exist: {}".format(expected_profile))
    if fields["Role lifecycle"] not in {"persistent", "task-scoped"}:
        raise DispatchError("Role lifecycle must be persistent or task-scoped")
    for key in ("Dispatch ID", "Team revision", "Context revision"):
        if not SAFE_REVISION.fullmatch(fields[key]):
            raise DispatchError("{} must be a whitespace-free stable ID".format(key))
    if not fields["Dispatch ID"].startswith("dispatch:{}:".format(task_id)):
        raise DispatchError("Dispatch ID must be unique to this task")
    if fields["Context manifest"] != "context.md":
        raise DispatchError("Context manifest must be context.md")
    registry_path = project / ".agent-taskgraph" / "ROLES.md"
    if not registry_path.is_file():
        raise DispatchError("project ROLES.md does not exist")
    registry_revision = quoted_metadata(registry_path, "Team revision")
    if registry_revision != fields["Team revision"]:
        raise DispatchError("dispatch Team revision differs from ROLES.md")
    role_fields = table_fields(role_path)
    expected_role_values = {
        "Role ID": role_id,
        "Team revision": fields["Team revision"],
        "生命周期": fields["Role lifecycle"],
    }
    for key, expected_value in expected_role_values.items():
        if role_fields.get(key, "") != expected_value:
            raise DispatchError("dispatch metadata differs from ROLE.md field {}".format(key))

    context_path = task_dir / "context.md"
    if not context_path.is_file():
        raise DispatchError("task context.md does not exist")
    if quoted_metadata(context_path, "Task ID") != task_id:
        raise DispatchError("context Task ID differs from dispatch")
    if quoted_metadata(context_path, "Revision") != fields["Context revision"]:
        raise DispatchError("context revision differs from dispatch")

    goal_path = task_dir / "goal.md"
    if not goal_path.is_file():
        raise DispatchError("task goal.md does not exist")
    expected_goal_values = {
        "Task ID": task_id,
        "Context manifest": "context.md",
        "Context revision": fields["Context revision"],
    }
    for key, expected_value in expected_goal_values.items():
        if quoted_metadata(goal_path, key) != expected_value:
            raise DispatchError("Goal {} differs from dispatch".format(key))
    if goal_role_ref(goal_path) != fields["Role ref"]:
        raise DispatchError("Goal Role ref differs from dispatch")
    expected = expected_ack(fields)
    if fields["Expected identity ACK"] != expected:
        raise DispatchError("Expected identity ACK does not match dispatch metadata")
    return expected


def render(project, task_id, fields, ack):
    role_profile = ".agent-taskgraph/{}".format(fields["Role profile"])
    return "\n".join(
        (
            "Use $agent-taskgraph.",
            "Role bootstrap: dispatch_id={}; role={}; lifecycle={}; team_revision={}.".format(
                fields["Dispatch ID"],
                fields["Role ref"],
                fields["Role lifecycle"],
                fields["Team revision"],
            ),
            "Current assignment: goal=task:{}; context=context.md@{}; continuity={}.".format(
                task_id, fields["Context revision"], fields["Continuity"]
            ),
            "Resolve exactly one current task directory under "
            ".agent-taskgraph/queue/{{inbox,active,review,done,failed}}/{} before every read or write.".format(
                task_id
            ),
            "Read in order: {}; PROJECT.md relevant sections; the current task context.md; "
            "the current Goal; then only the required references and direct dependencies listed by context.md.".format(
                role_profile
            ),
            "Role is your durable responsibility; Goal is your only current authorization. "
            "Do not expand writes, Frozen scope, permissions, or Human Gates, and do not edit PMO-owned queue state, STATUS, DECISIONS, or ledger.",
            "Before implementation, emit this exact first status line: {}".format(ack),
            "If any identity file or revision disagrees, emit IDENTITY_BLOCKED with the mismatch and stop. "
            "Otherwise execute the Goal and report its legal terminal with evidence.",
        )
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", required=True, help="Target project directory")
    parser.add_argument("--goal", required=True, help="Stable task:<id> Goal ref")
    args = parser.parse_args()

    project = Path(args.project).expanduser().resolve()
    if not project.is_dir():
        raise DispatchError("project directory does not exist: {}".format(project))
    task_id, task_dir = resolve_task(project, args.goal)
    dispatch_path = task_dir / "dispatch.md"
    if not dispatch_path.is_file():
        raise DispatchError("missing task dispatch.md")
    fields = table_fields(dispatch_path)
    ack = validate(project, task_id, task_dir, fields)
    print(render(project, task_id, fields, ack))


if __name__ == "__main__":
    try:
        main()
    except DispatchError as exc:
        print("Error: {}".format(exc), file=sys.stderr)
        raise SystemExit(1)
