#!/usr/bin/env python3
"""Validate queue, ledger, and STATUS consistency."""

import re
import sys
from pathlib import Path


STATES = ("inbox", "active", "review", "done", "failed")
VISIBLE_STATES = {"active", "review"}
FIELD_ROW = re.compile(r'^\|\s*([^|]+?)\s*\|\s*([^|]*?)\s*\|\s*$')
GOAL_TASK_ID = re.compile(r'^>\s*Task ID:\s*`?([^`]+?)`?\s*$')


def ledger_fields(path):
    fields = {}
    duplicates = set()
    for raw in path.read_text(encoding="utf-8").splitlines():
        match = FIELD_ROW.match(raw)
        if match:
            name = match.group(1).strip()
            if name in fields:
                duplicates.add(name)
            fields[name] = match.group(2).strip()
    return fields, duplicates


def goal_task_id(path):
    for raw in path.read_text(encoding="utf-8").splitlines():
        match = GOAL_TASK_ID.match(raw)
        if match:
            return match.group(1).strip()
    return ""


def status_rows(path):
    rows = {}
    duplicates = set()
    for raw in path.read_text(encoding="utf-8").splitlines():
        if not raw.startswith("|"):
            continue
        cells = [cell.strip() for cell in raw.strip().strip("|").split("|")]
        if len(cells) != 7 or cells[0] in {"任务 ID", "任务号"} or set(cells[0]) == {"-"}:
            continue
        if cells[0] in rows:
            duplicates.add(cells[0])
        rows[cells[0]] = {"state": cells[2], "line": raw}
    return rows, duplicates


def validate(project):
    instance = project / ".agent-taskgraph"
    queue = instance / "queue"
    status_path = instance / "STATUS.md"
    errors = []
    if not queue.is_dir() or not status_path.is_file():
        return ["missing .agent-taskgraph/queue or STATUS.md"]

    tasks = {}
    for state in STATES:
        state_dir = queue / state
        if not state_dir.is_dir():
            errors.append("missing queue state directory: {}".format(state))
            continue
        for child in state_dir.iterdir():
            if child.name.startswith("."):
                continue
            if not child.is_dir():
                errors.append("unexpected non-directory in queue/{}: {}".format(state, child.name))
                continue
            if child.name in tasks:
                errors.append("task appears in multiple states: {}".format(child.name))
                continue
            tasks[child.name] = state
            goal = child / "goal.md"
            ledger = child / "ledger.md"
            if not goal.is_file():
                errors.append("{}: missing goal.md".format(child.name))
            elif goal_task_id(goal) != child.name:
                errors.append("{}: Goal Task ID must match the queue directory".format(child.name))
            if not ledger.is_file():
                errors.append("{}: missing ledger.md".format(child.name))
                continue
            fields, duplicate_fields = ledger_fields(ledger)
            if duplicate_fields:
                errors.append(
                    "{}: duplicate ledger fields: {}".format(
                        child.name, ", ".join(sorted(duplicate_fields))
                    )
                )
            ledger_id = fields.get("任务 ID", "")
            if ledger_id != child.name:
                errors.append("{}: ledger task ID is {!r}".format(child.name, ledger_id))
            ledger_state = fields.get("状态", "")
            if ledger_state != state:
                errors.append("{}: ledger state {!r} != directory state {!r}".format(child.name, ledger_state, state))
            expected_ref = "task:{}".format(child.name)
            if fields.get("Goal ref", "") != expected_ref:
                errors.append("{}: Goal ref must be {}".format(child.name, expected_ref))
            expected_path = "queue/{}/{}/goal.md".format(state, child.name)
            if fields.get("Goal current path", "") != expected_path:
                errors.append("{}: Goal current path must be {}".format(child.name, expected_path))

    rows, duplicate_rows = status_rows(status_path)
    for task_id in sorted(duplicate_rows):
        errors.append("{}: duplicate STATUS.md row".format(task_id))
    expected_visible = {task_id: state for task_id, state in tasks.items() if state in VISIBLE_STATES}
    for task_id, state in expected_visible.items():
        if task_id not in rows:
            errors.append("{}: missing from STATUS.md".format(task_id))
        elif rows[task_id]["state"] != state:
            errors.append(
                "{}: STATUS state {!r} != queue state {!r}".format(
                    task_id, rows[task_id]["state"], state
                )
            )
    for task_id in rows:
        if task_id not in expected_visible:
            errors.append("{}: stale or unknown STATUS.md row".format(task_id))
    return errors


def main(argv):
    if len(argv) != 2:
        print("Usage: validate-state.py <project-directory>", file=sys.stderr)
        return 2
    project = Path(argv[1]).resolve()
    if not project.is_dir():
        print("Project directory does not exist: {}".format(project), file=sys.stderr)
        return 2
    errors = validate(project)
    if errors:
        for error in errors:
            print("ERROR: {}".format(error), file=sys.stderr)
        return 1
    print("State validation passed: {}".format(project / ".agent-taskgraph"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
