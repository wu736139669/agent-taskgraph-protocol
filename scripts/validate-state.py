#!/usr/bin/env python3
"""Validate queue, runtime evidence, ledger, and STATUS consistency."""

import json
import re
import sys
from pathlib import Path


STATES = ("inbox", "active", "review", "done", "failed")
VISIBLE_STATES = {"active", "review"}
FIELD_ROW = re.compile(r'^\|\s*([^|]+?)\s*\|\s*([^|]*?)\s*\|\s*$')
GOAL_TASK_ID = re.compile(r'^>\s*Task ID:\s*`?([^`]+?)`?\s*$')
GOAL_BASELINE = re.compile(r'^>\s*Baseline:\s*(.+?)\s*$')
GOAL_CONTEXT = re.compile(r'^>\s*Context manifest:\s*`?([^`]+?)`?\s*$')
GOAL_CONTEXT_REVISION = re.compile(r'^>\s*Context revision:\s*`?([^`]+?)`?\s*$')
GOAL_ASSIGNMENT = re.compile(
    r'^-\s*(Role ref|角色职责|角色生命周期|连续性|Runtime requested|Runtime observed|Runtime verification|Session evidence|Dispatch message)[：:]\s*(.*?)\s*$'
)
ROLE_REF = re.compile(r'^role:([a-z0-9][a-z0-9-]*)$')
ROLE_LIFECYCLES = {"persistent", "task-scoped"}
ROLE_STATES = {"available", "assigned", "paused", "retired"}
SPEC_STATUS = re.compile(r'^>\s*Status:\s*(DRAFT|FROZEN)\s*$', re.IGNORECASE)
SPEC_FROZEN_BY = re.compile(r'^>\s*Frozen by:\s*(.*?)\s*$', re.IGNORECASE)
RUNTIME_KEYS = ("runtime", "flavor", "model", "effort", "permission", "visibility")
PLACEHOLDER_TOKENS = (
    "<",
    "pending",
    "待确认",
    "待填写",
    "未验证",
    "unknown",
    "tbd",
)


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


def goal_metadata(path):
    metadata = {
        "task_id": "",
        "baseline": "",
        "context_manifest": "",
        "context_revision": "",
        "assignments": {},
    }
    for raw in path.read_text(encoding="utf-8").splitlines():
        match = GOAL_TASK_ID.match(raw)
        if match:
            metadata["task_id"] = match.group(1).strip()
        match = GOAL_BASELINE.match(raw)
        if match:
            metadata["baseline"] = match.group(1).strip().strip("`")
        match = GOAL_CONTEXT.match(raw)
        if match:
            metadata["context_manifest"] = match.group(1).strip()
        match = GOAL_CONTEXT_REVISION.match(raw)
        if match:
            metadata["context_revision"] = match.group(1).strip()
        match = GOAL_ASSIGNMENT.match(raw)
        if match:
            metadata["assignments"][match.group(1)] = match.group(2).strip().strip("`")
    return metadata


def context_metadata(path):
    metadata = {"task_id": "", "revision": "", "mode": "", "exception": "", "required": []}
    in_required = False
    for raw in path.read_text(encoding="utf-8").splitlines():
        if raw.startswith("> Task ID:"):
            metadata["task_id"] = raw.split(":", 1)[1].strip().strip("`")
        elif raw.startswith("> Revision:"):
            metadata["revision"] = raw.split(":", 1)[1].strip().strip("`")
        elif raw.startswith("> Mode:"):
            metadata["mode"] = raw.split(":", 1)[1].strip().strip("`")
        elif raw.startswith("> Budget exception:"):
            metadata["exception"] = raw.split(":", 1)[1].strip().strip("`")
        elif raw.startswith("## "):
            in_required = raw.startswith("## 必须读取")
        elif in_required and raw.startswith("|"):
            cells = [cell.strip() for cell in raw.strip().strip("|").split("|")]
            if len(cells) == 3 and cells[0] not in {"路径或稳定引用", "---"}:
                metadata["required"].append(cells)
    return metadata


def validate_context(task_id, task_dir, fields, goal_data):
    errors = []
    manifest_ref = fields.get("Context manifest", "")
    if manifest_ref != "context.md":
        return ["{}: Context manifest must be context.md".format(task_id)]
    if goal_data.get("context_manifest") != manifest_ref:
        errors.append("{}: Goal and ledger Context manifest differ".format(task_id))
    revision = fields.get("Context revision", "")
    if is_placeholder(revision):
        errors.append("{}: Context revision must be concrete".format(task_id))
    if goal_data.get("context_revision") != revision:
        errors.append("{}: Goal and ledger Context revision differ".format(task_id))

    manifest_path = task_dir / manifest_ref
    if not manifest_path.is_file():
        errors.append("{}: missing context.md".format(task_id))
        return errors
    metadata = context_metadata(manifest_path)
    if metadata["task_id"] != task_id:
        errors.append("{}: context Task ID must match the queue directory".format(task_id))
    if metadata["revision"] != revision:
        errors.append("{}: context revision differs from ledger".format(task_id))
    if metadata["mode"] not in {"lean", "balanced", "deep"}:
        errors.append("{}: context Mode must be lean, balanced, or deep".format(task_id))
    if not metadata["required"]:
        errors.append("{}: context must list at least one required item".format(task_id))
    if len(metadata["required"]) > 8 and metadata["exception"].lower() in {"", "none", "无"}:
        errors.append("{}: context has more than 8 required items without Budget exception".format(task_id))
    for path_ref, revision_ref, reason in metadata["required"]:
        if is_placeholder(path_ref) or is_placeholder(revision_ref) or is_placeholder(reason):
            errors.append("{}: context required items must use concrete path, revision, and reason".format(task_id))
            break
    return errors


def is_placeholder(value):
    lowered = value.strip().lower()
    return not lowered or any(token in lowered for token in PLACEHOLDER_TOKENS)


def normalize_permission(value):
    compact = re.sub(r"[-_\s]", "", value).lower()
    aliases = {
        "yolo": "bypassPermissions",
        "bypasspermissions": "bypassPermissions",
        "dangerouslyskippermissions": "bypassPermissions",
        "dangerouslybypassapprovalsandsandbox": "bypassPermissions",
        "acceptedits": "acceptEdits",
    }
    return aliases.get(compact, value)


def runtime_config(value):
    config = {}
    for part in value.strip().strip("`").split(";"):
        if "=" not in part:
            continue
        key, item = part.split("=", 1)
        config[key.strip().lower()] = item.strip()
    if "permission" in config:
        config["permission"] = normalize_permission(config["permission"])
    return config


def validate_role(
    task_id, state, instance, fields, goal_assignments, registered_roles, team_revision
):
    errors = []
    role_ref = fields.get("Role ref", "")
    match = ROLE_REF.fullmatch(role_ref)
    if not match:
        return ["{}: Role ref must use role:<lowercase-id>".format(task_id)]

    role_id = match.group(1)
    if role_id not in registered_roles:
        errors.append("{}: role {} is missing from ROLES.md".format(task_id, role_id))
    lifecycle = fields.get("Role lifecycle", "")
    if lifecycle not in ROLE_LIFECYCLES:
        errors.append("{}: invalid Role lifecycle {!r}".format(task_id, lifecycle))
    expected_profile = "roles/{}/ROLE.md".format(role_id)
    if fields.get("Role profile", "") != expected_profile:
        errors.append("{}: Role profile must be {}".format(task_id, expected_profile))
    if is_placeholder(fields.get("Role continuity", "")):
        errors.append("{}: Role continuity must record reuse or handoff evidence".format(task_id))

    profile_path = instance / expected_profile
    if not profile_path.is_file():
        errors.append("{}: missing role profile {}".format(task_id, expected_profile))
    else:
        profile, duplicates = ledger_fields(profile_path)
        if duplicates:
            errors.append(
                "{}: duplicate role profile fields: {}".format(
                    task_id, ", ".join(sorted(duplicates))
                )
            )
        if profile.get("Role ID", "") != role_id:
            errors.append("{}: role profile Role ID must be {}".format(task_id, role_id))
        if state in VISIBLE_STATES:
            if is_placeholder(team_revision):
                errors.append("{}: ROLES.md requires a concrete Team revision".format(task_id))
            if profile.get("Team revision", "") != team_revision:
                errors.append("{}: role profile Team revision differs from ROLES.md".format(task_id))
            origin = profile.get("Origin", "")
            if is_placeholder(origin) or not origin.startswith(("initial:", "staffing:")):
                errors.append("{}: role profile Origin must be initial:<ref> or staffing:<change-id>".format(task_id))
            elif origin.startswith("staffing:"):
                change_id = origin.split(":", 1)[1]
                change_path = instance / "staffing" / "{}.md".format(change_id)
                if not change_path.is_file():
                    errors.append("{}: missing staffing change record for {}".format(task_id, origin))
                else:
                    change_text = change_path.read_text(encoding="utf-8")
                    if "> Status: `APPLIED`" not in change_text:
                        errors.append("{}: staffing change {} must be APPLIED".format(task_id, change_id))
                    approved = ""
                    for raw in change_text.splitlines():
                        if raw.startswith("> Approved by:"):
                            approved = raw.split(":", 1)[1].strip().strip("`")
                            break
                    if is_placeholder(approved):
                        errors.append("{}: staffing change {} requires approval evidence".format(task_id, change_id))
        if profile.get("生命周期", "") != lifecycle:
            errors.append("{}: role profile lifecycle differs from ledger".format(task_id))
        role_state = profile.get("状态", "")
        if role_state not in ROLE_STATES:
            errors.append("{}: invalid role profile state {!r}".format(task_id, role_state))
        if state in VISIBLE_STATES:
            if role_state != "assigned":
                errors.append("{}: active/review role must be assigned".format(task_id))
            if profile.get("当前 Goal", "") != "task:{}".format(task_id):
                errors.append("{}: role profile Current Goal must reference this task".format(task_id))
        elif state == "done" and lifecycle == "task-scoped":
            if role_state != "retired":
                errors.append("{}: completed task-scoped role must be retired".format(task_id))
            if profile.get("当前 Goal", "").lower() not in {"none", "n/a"}:
                errors.append("{}: completed task-scoped role must release Current Goal".format(task_id))

    if goal_assignments.get("Role ref", "").strip("`") != role_ref:
        errors.append("{}: Goal and ledger Role ref differ".format(task_id))
    if goal_assignments.get("角色生命周期", "").strip("<>") != lifecycle:
        errors.append("{}: Goal and ledger Role lifecycle differ".format(task_id))
    if is_placeholder(goal_assignments.get("角色职责", "")):
        errors.append("{}: Goal requires a concrete role responsibility".format(task_id))
    if is_placeholder(goal_assignments.get("连续性", "")):
        errors.append("{}: Goal requires role continuity or handoff evidence".format(task_id))
    return errors


def role_registry(path):
    roles = set()
    if not path.is_file():
        return roles
    for raw in path.read_text(encoding="utf-8").splitlines():
        if not raw.startswith("|"):
            continue
        cells = [cell.strip() for cell in raw.strip().strip("|").split("|")]
        if len(cells) != 8 or cells[0] == "Role ID" or set(cells[0]) == {"-"}:
            continue
        if re.fullmatch(r"[a-z0-9][a-z0-9-]*", cells[0]):
            roles.add(cells[0])
    return roles


def role_team_revision(path):
    if not path.is_file():
        return ""
    for raw in path.read_text(encoding="utf-8").splitlines():
        if raw.startswith("> Team revision:"):
            return raw.split(":", 1)[1].strip().strip("`")
    return ""


def validate_reviewer_role(task_id, state, instance, fields, registered_roles):
    if state not in {"review", "done"}:
        return []
    errors = []
    role_ref = fields.get("Reviewer Role ref", "")
    match = ROLE_REF.fullmatch(role_ref)
    if not match:
        return ["{}: review/done requires an independent Reviewer Role ref".format(task_id)]
    if role_ref == fields.get("Role ref", ""):
        errors.append("{}: reviewer role must differ from worker role".format(task_id))
    role_id = match.group(1)
    if role_id not in registered_roles:
        errors.append("{}: reviewer role {} is missing from ROLES.md".format(task_id, role_id))
    expected_profile = "roles/{}/ROLE.md".format(role_id)
    if fields.get("Reviewer Role profile", "") != expected_profile:
        errors.append("{}: Reviewer Role profile must be {}".format(task_id, expected_profile))
    profile_path = instance / expected_profile
    if not profile_path.is_file():
        errors.append("{}: missing reviewer role profile {}".format(task_id, expected_profile))
        return errors
    profile, _ = ledger_fields(profile_path)
    if profile.get("Role ID", "") != role_id:
        errors.append("{}: reviewer profile Role ID must be {}".format(task_id, role_id))
    if profile.get("生命周期", "") != "task-scoped":
        errors.append("{}: reviewer role must be task-scoped".format(task_id))
    expected_state = "assigned" if state == "review" else "retired"
    if profile.get("状态", "") != expected_state:
        errors.append("{}: reviewer role must be {} in {}".format(task_id, expected_state, state))
    expected_goal = "task:{}".format(task_id) if state == "review" else {"none", "n/a"}
    current_goal = profile.get("当前 Goal", "")
    if state == "review" and current_goal != expected_goal:
        errors.append("{}: reviewer role Current Goal must reference this task".format(task_id))
    if state == "done" and current_goal.lower() not in expected_goal:
        errors.append("{}: completed reviewer role must release Current Goal".format(task_id))
    return errors


def section_body(lines, heading):
    collecting = False
    body = []
    for raw in lines:
        if raw.startswith("## "):
            if collecting:
                break
            collecting = raw.strip() == heading
            continue
        if collecting:
            body.append(raw)
    return body


def validate_frozen_spec(instance):
    spec_path = instance / "spec.md"
    if not spec_path.is_file():
        return []
    lines = spec_path.read_text(encoding="utf-8").splitlines()
    status = ""
    frozen_by = ""
    for raw in lines:
        match = SPEC_STATUS.match(raw)
        if match:
            status = match.group(1).upper()
        match = SPEC_FROZEN_BY.match(raw)
        if match:
            frozen_by = match.group(1).strip()
    if status != "FROZEN":
        return []

    errors = []
    if is_placeholder(frozen_by):
        errors.append("spec.md: FROZEN requires a concrete Frozen by record")
    open_questions = [
        raw.strip()
        for raw in section_body(lines, "## 开放问题")
        if raw.strip() and not raw.lstrip().startswith("<!--")
    ]
    normalized = {raw.lstrip("- ").strip().lower() for raw in open_questions}
    if not open_questions or normalized not in ({"无"}, {"none"}):
        errors.append("spec.md: FROZEN requires 开放问题 to be exactly 无")
    return errors


def validate_hapi_evidence(task_id, task_dir, fields, observed):
    raw_path = fields.get("Runtime evidence", "")
    if is_placeholder(raw_path):
        return []
    evidence_path = Path(raw_path)
    if evidence_path.is_absolute():
        return ["{}: HAPI Runtime evidence must be stored inside the task directory".format(task_id)]
    evidence_path = (task_dir / evidence_path).resolve()
    try:
        evidence_path.relative_to(task_dir.resolve())
    except ValueError:
        return ["{}: HAPI Runtime evidence escapes the task directory".format(task_id)]
    if not evidence_path.is_file():
        return ["{}: HAPI Runtime evidence file is missing: {}".format(task_id, raw_path)]
    try:
        evidence = json.loads(evidence_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        return ["{}: invalid HAPI Runtime evidence: {}".format(task_id, exc)]

    errors = []
    if evidence.get("status") != "VERIFIED":
        errors.append("{}: HAPI evidence status must be VERIFIED".format(task_id))
    if evidence.get("phase") != "pre-dispatch":
        errors.append("{}: HAPI evidence phase must be pre-dispatch".format(task_id))
    if evidence.get("messages_received") != 0:
        errors.append("{}: HAPI evidence must precede the first Goal message".format(task_id))
    if str(evidence.get("session_id", "")) != fields.get("Session ID", ""):
        errors.append("{}: HAPI evidence Session ID differs from ledger".format(task_id))
    for key in ("flavor", "model", "effort", "permission"):
        evidence_value = str(evidence.get(key, ""))
        if key == "permission":
            evidence_value = normalize_permission(evidence_value)
        if evidence_value != observed.get(key, ""):
            errors.append(
                "{}: HAPI evidence {} mismatch: observed {!r}, evidence {!r}".format(
                    task_id, key, observed.get(key, ""), evidence_value
                )
            )
    return errors


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
    persistent_assignments = {}
    registered_roles = role_registry(instance / "ROLES.md")
    team_revision = role_team_revision(instance / "ROLES.md")
    active_or_review = False
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
            if state in VISIBLE_STATES:
                active_or_review = True
            goal = child / "goal.md"
            ledger = child / "ledger.md"
            goal_data = {
                "task_id": "",
                "baseline": "",
                "context_manifest": "",
                "context_revision": "",
                "assignments": {},
            }
            if not goal.is_file():
                errors.append("{}: missing goal.md".format(child.name))
            else:
                goal_data = goal_metadata(goal)
                if goal_data["task_id"] != child.name:
                    errors.append("{}: Goal Task ID must match the queue directory".format(child.name))
            if not ledger.is_file():
                errors.append("{}: missing ledger.md".format(child.name))
                continue
            fields, duplicate_fields = ledger_fields(ledger)
            runtime_evidence_required = state in VISIBLE_STATES or (
                state == "done" and "Runtime requested" in fields
            )
            role_required = state in VISIBLE_STATES or (
                state == "done" and "Role ref" in fields
            )
            context_required = state in VISIBLE_STATES or (
                state == "done" and "Context manifest" in fields
            )
            if runtime_evidence_required and is_placeholder(goal_data["baseline"]):
                errors.append("{}: evidence-bearing Goal requires a concrete baseline".format(child.name))
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

            if role_required:
                goal_assignments = goal_data["assignments"]
                errors.extend(
                    validate_role(
                        child.name,
                        state,
                        instance,
                        fields,
                        goal_assignments,
                        registered_roles,
                        team_revision,
                    )
                )
                errors.extend(
                    validate_reviewer_role(
                        child.name, state, instance, fields, registered_roles
                    )
                )
                role_ref = fields.get("Role ref", "")
                if state in VISIBLE_STATES and fields.get("Role lifecycle", "") == "persistent":
                    persistent_assignments.setdefault(role_ref, []).append(child.name)

            if context_required:
                errors.extend(validate_context(child.name, child, fields, goal_data))

            if runtime_evidence_required:
                requested_raw = fields.get("Runtime requested", "")
                observed_raw = fields.get("Runtime observed", "")
                requested = runtime_config(requested_raw)
                observed = runtime_config(observed_raw)
                missing_requested = [key for key in RUNTIME_KEYS if is_placeholder(requested.get(key, ""))]
                missing_observed = [key for key in RUNTIME_KEYS if is_placeholder(observed.get(key, ""))]
                if missing_requested:
                    errors.append(
                        "{}: Runtime requested missing concrete fields: {}".format(
                            child.name, ", ".join(missing_requested)
                        )
                    )
                if missing_observed:
                    errors.append(
                        "{}: Runtime observed missing concrete fields: {}".format(
                            child.name, ", ".join(missing_observed)
                        )
                    )
                for key in RUNTIME_KEYS:
                    if requested.get(key) and observed.get(key) and requested.get(key) != observed.get(key):
                        errors.append(
                            "{}: runtime {} mismatch: requested {!r}, observed {!r}".format(
                                child.name, key, requested.get(key), observed.get(key)
                            )
                        )

                if fields.get("Runtime verification", "") != "VERIFIED":
                    errors.append("{}: Runtime verification must be VERIFIED".format(child.name))
                if is_placeholder(fields.get("Session ID", "")):
                    errors.append("{}: evidence-bearing task requires a real Session ID".format(child.name))
                if is_placeholder(fields.get("Runtime evidence", "")):
                    errors.append("{}: evidence-bearing task requires Runtime evidence".format(child.name))
                if not fields.get("Dispatch message", "").startswith("SENT:"):
                    errors.append("{}: Dispatch message must start with SENT:".format(child.name))

                goal_assignments = goal_data["assignments"]
                goal_requested = runtime_config(goal_assignments.get("Runtime requested", ""))
                goal_observed = runtime_config(goal_assignments.get("Runtime observed", ""))
                if goal_requested != requested:
                    errors.append("{}: Goal and ledger Runtime requested differ".format(child.name))
                if goal_observed != observed:
                    errors.append("{}: Goal and ledger Runtime observed differ".format(child.name))
                if not goal_assignments.get("Runtime verification", "").startswith("VERIFIED"):
                    errors.append("{}: Goal Runtime verification must be VERIFIED".format(child.name))
                if is_placeholder(goal_assignments.get("Session evidence", "")):
                    errors.append("{}: Goal requires concrete Session evidence".format(child.name))
                if not goal_assignments.get("Dispatch message", "").startswith("SENT:"):
                    errors.append("{}: Goal Dispatch message must start with SENT:".format(child.name))
                if requested.get("runtime") == "hapi":
                    errors.extend(validate_hapi_evidence(child.name, child, fields, observed))

    for role_ref, task_ids in sorted(persistent_assignments.items()):
        if len(task_ids) > 1:
            errors.append(
                "{}: persistent role assigned to concurrent tasks: {}".format(
                    role_ref, ", ".join(sorted(task_ids))
                )
            )

    if active_or_review:
        project_path = instance / "PROJECT.md"
        if not project_path.is_file():
            errors.append("active/review tasks require PROJECT.md")
        else:
            project_fields, _ = ledger_fields(project_path)
            source_baseline = project_fields.get("Source baseline", "")
            if not source_baseline.upper().startswith("READY:") or is_placeholder(source_baseline):
                errors.append("PROJECT.md: Source baseline must start with READY: before dispatch")
        errors.extend(validate_frozen_spec(instance))

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
