#!/usr/bin/env python3
"""Validate queue, runtime evidence, ledger, and STATUS consistency."""

import argparse
import json
import re
import subprocess
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
    r'^-\s*(Role ref|角色职责|角色生命周期|连续性|工作区|Runtime requested|Runtime observed|Runtime verification|Session evidence|Dispatch bootstrap|Dispatch message|Identity ACK)[：:]\s*(.*?)\s*$'
)
ROLE_REF = re.compile(r'^role:([a-z0-9][a-z0-9-]*)$')
ROLE_LIFECYCLES = {"persistent", "task-scoped"}
ROLE_STATES = {"available", "reserved", "assigned", "paused", "retired"}
SPEC_STATUS = re.compile(r'^>\s*Status:\s*(DRAFT|FROZEN)\s*$', re.IGNORECASE)
SPEC_FROZEN_BY = re.compile(r'^>\s*Frozen by:\s*(.*?)\s*$', re.IGNORECASE)
RUNTIME_KEYS = ("runtime", "flavor", "model", "effort", "permission", "visibility")
RUNTIME_PLACEHOLDERS = {"default", "auto", "pending", "待确认"}
FAILURE_CLASSES = {
    "PENDING",
    "PRODUCT_FAIL",
    "HARNESS_INVALID",
    "DISPATCH_INVALID",
    "RUNTIME_INVALID",
    "OWNER_DECISION",
}
EXECUTION_PROFILE_KEYS = (
    "Execution profile confirmed by/at",
    "Execution runtime",
    "Execution control",
    "Execution machine",
    "Execution flavor",
    "Model selection policy",
    "Fixed model/effort",
    "Model catalog evidence",
    "Execution permission",
    "Permission scope",
    "Execution visibility",
    "Execution fallback",
)
MONITORING_PROFILE_KEYS = (
    "Monitoring wait primitive",
    "Monitoring observe primitive",
    "Monitoring target evidence",
)
PLACEHOLDER_TOKENS = (
    "<",
    "pending",
    "待确认",
    "待填写",
    "未验证",
    "unknown",
    "tbd",
)
PROTOCOL_VERSION = re.compile(r"^(\d+)\.(\d+)\.(\d+)(?:-beta\.(\d+))?$", re.IGNORECASE)
WORKTREE_VALUE = re.compile(
    r'^`([^`]+)`\s*[（(]分支[：:]\s*`([^`]+)`[）)]$'
)


def ledger_fields(path):
    fields = {}
    duplicates = set()
    for raw in path.read_text(encoding="utf-8").splitlines():
        match = FIELD_ROW.match(raw)
        if match:
            name = match.group(1).strip()
            if name and set(name) <= {"-", ":"}:
                continue
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
            key = match.group(1)
            value = match.group(2).strip()
            metadata["assignments"][key] = (
                value if key == "工作区" else value.strip("`")
            )
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


def protocol_at_least(project_fields, beta):
    raw = project_fields.get("Agent TaskGraph 协议版本", "").strip().strip("`")
    if is_placeholder(raw):
        return True
    match = PROTOCOL_VERSION.fullmatch(raw)
    if not match:
        return True
    release = tuple(int(match.group(index)) for index in (1, 2, 3))
    if release != (0, 8, 0):
        return release > (0, 8, 0)
    current_beta = match.group(4)
    return current_beta is None or int(current_beta) >= beta


def identity_bootstrap_required(project_fields):
    """Preserve batches explicitly pinned pre-beta.9 while hardening new revisions."""
    return protocol_at_least(project_fields, 9)


def dispatch_expected_ack(dispatch):
    return (
        "IDENTITY_READY dispatch_id={Dispatch ID} role={Role ref} "
        "team_revision={Team revision} goal={Goal ref} "
        "context_revision={Context revision}"
    ).format(**dispatch)


def validate_dispatch_bootstrap(
    task_id, task_dir, fields, goal_assignments, team_revision, pending=False
):
    errors = []
    dispatch_ref = fields.get("Dispatch bootstrap", "")
    if dispatch_ref != "dispatch.md":
        return ["{}: Dispatch bootstrap must be dispatch.md".format(task_id)]
    if goal_assignments.get("Dispatch bootstrap", "").strip("`") != dispatch_ref:
        errors.append("{}: Goal and ledger Dispatch bootstrap differ".format(task_id))

    dispatch_path = task_dir / dispatch_ref
    if not dispatch_path.is_file():
        errors.append("{}: missing dispatch.md".format(task_id))
        return errors
    dispatch, duplicates = ledger_fields(dispatch_path)
    if duplicates:
        errors.append(
            "{}: duplicate dispatch fields: {}".format(
                task_id, ", ".join(sorted(duplicates))
            )
        )

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
    missing = [key for key in required if is_placeholder(dispatch.get(key, ""))]
    if missing:
        errors.append(
            "{}: dispatch requires concrete fields: {}".format(
                task_id, ", ".join(missing)
            )
        )
        return errors

    expected_values = {
        "Task ID": task_id,
        "Role ref": fields.get("Role ref", ""),
        "Role profile": fields.get("Role profile", ""),
        "Role lifecycle": fields.get("Role lifecycle", ""),
        "Team revision": team_revision,
        "Goal ref": "task:{}".format(task_id),
        "Context manifest": fields.get("Context manifest", ""),
        "Context revision": fields.get("Context revision", ""),
        "Continuity": fields.get("Role continuity", ""),
    }
    if not pending:
        expected_values["Session ID"] = fields.get("Session ID", "")
    for key, expected in expected_values.items():
        if dispatch.get(key, "") != expected:
            errors.append(
                "{}: dispatch {} differs from ledger/registry".format(task_id, key)
            )

    dispatch_id = dispatch.get("Dispatch ID", "")
    if not re.fullmatch(
        r"dispatch:{}:[A-Za-z0-9][A-Za-z0-9._:-]*".format(re.escape(task_id)),
        dispatch_id,
    ):
        errors.append("{}: Dispatch ID must be unique to this task".format(task_id))
    expected_ack = dispatch_expected_ack(dispatch)
    if dispatch.get("Expected identity ACK", "") != expected_ack:
        errors.append("{}: Expected identity ACK does not match dispatch metadata".format(task_id))

    if pending:
        pending_values = {
            "Session ID": "PENDING",
            "Delivery": "NOT_SENT",
            "Identity ACK": "PENDING",
            "ACK evidence": "PENDING",
        }
        for key, expected in pending_values.items():
            if dispatch.get(key, "") != expected:
                errors.append(
                    "{}: pre-dispatch {} must be {}".format(task_id, key, expected)
                )
        ledger_pending = {
            "Runtime observed": "PENDING",
            "Runtime verification": "PENDING",
            "Session ID": "PENDING",
            "Runtime evidence": "PENDING",
            "Dispatch message": "NOT_SENT",
            "Identity ACK": "PENDING",
        }
        for key, expected in ledger_pending.items():
            if fields.get(key, "") != expected:
                errors.append(
                    "{}: pre-dispatch ledger {} must be {}".format(
                        task_id, key, expected
                    )
                )
        goal_pending = {
            "Runtime observed": "PENDING",
            "Runtime verification": "PENDING",
            "Session evidence": "PENDING",
            "Dispatch message": "NOT_SENT",
            "Identity ACK": "PENDING",
        }
        for key, expected in goal_pending.items():
            if goal_assignments.get(key, "").strip("`") != expected:
                errors.append(
                    "{}: pre-dispatch Goal {} must be {}".format(
                        task_id, key, expected
                    )
                )
        return errors

    verified_ack = "VERIFIED: {}".format(expected_ack)
    if dispatch.get("Identity ACK", "") != verified_ack:
        errors.append("{}: dispatch Identity ACK must exactly match Expected identity ACK".format(task_id))
    if fields.get("Identity ACK", "") != verified_ack:
        errors.append("{}: ledger Identity ACK must exactly match dispatch.md".format(task_id))
    if goal_assignments.get("Identity ACK", "").strip("`") != verified_ack:
        errors.append("{}: Goal Identity ACK must exactly match dispatch.md".format(task_id))

    delivery = dispatch.get("Delivery", "")
    if not delivery.startswith("SENT:") or dispatch_id not in delivery:
        errors.append("{}: dispatch Delivery must cite its SENT Dispatch ID".format(task_id))
    for source, value in (
        ("ledger", fields.get("Dispatch message", "")),
        ("Goal", goal_assignments.get("Dispatch message", "")),
    ):
        if not value.startswith("SENT:") or dispatch_id not in value:
            errors.append(
                "{}: {} Dispatch message must cite the SENT Dispatch ID".format(
                    task_id, source
                )
            )
    ack_evidence = dispatch.get("ACK evidence", "")
    if fields.get("Session ID", "") not in ack_evidence:
        errors.append("{}: ACK evidence must cite the verified Session ID".format(task_id))
    return errors


def is_placeholder(value):
    lowered = value.strip().lower()
    return not lowered or any(token in lowered for token in PLACEHOLDER_TOKENS)


def json_value_is_placeholder(value):
    return value is None or is_placeholder(str(value))


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


def runtime_value_is_placeholder(key, value):
    if is_placeholder(value):
        return True
    return key in {"model", "effort"} and value.strip().lower() in RUNTIME_PLACEHOLDERS


def validate_monitoring_profile(fields):
    errors = []
    for key in MONITORING_PROFILE_KEYS:
        if is_placeholder(fields.get(key, "")):
            errors.append("PROJECT.md: {} must be concrete".format(key))

    runtime = fields.get("Execution runtime", "").strip().lower()
    control = fields.get("Execution control", "").strip().lower()
    wait_primitive = fields.get("Monitoring wait primitive", "").strip().lower()
    observe_primitive = fields.get("Monitoring observe primitive", "").strip().lower()

    if runtime == "hapi":
        if "wait_agent" in wait_primitive or "wait_threads" in wait_primitive:
            errors.append(
                "PROJECT.md: HAPI monitoring cannot use wait_agent/wait_threads; "
                "those primitives only target native agent/thread trees"
            )
        if not any(
            token in wait_primitive
            for token in ("hapi event", "hapi-event", "timer cell", "timer-cell", "runtime event")
        ):
            errors.append(
                "PROJECT.md: HAPI Monitoring wait primitive must use HAPI events "
                "and/or a runtime timer cell"
            )
        if not any(
            token in observe_primitive
            for token in ("inspect_peer", "hapi", "session metadata", "session log")
        ):
            errors.append(
                "PROJECT.md: HAPI Monitoring observe primitive must inspect the HAPI peer/session"
            )
    elif "spawn_agent" in control and "wait_agent" not in wait_primitive:
        errors.append(
            "PROJECT.md: spawn_agent control requires wait_agent for its native agent tree"
        )
    elif "thread" in control and "wait_threads" not in wait_primitive:
        errors.append(
            "PROJECT.md: native thread control requires wait_threads"
        )

    if "functions.wait" in wait_primitive and not any(
        token in wait_primitive for token in ("cell_id", "real cell", "timer cell", "timer-cell")
    ):
        errors.append(
            "PROJECT.md: functions.wait is only valid with a real timer/observe cell_id"
        )
    return errors


def validate_execution_profile(
    fields, require_runtime_choice=False, require_monitoring=False
):
    errors = []
    if fields.get("Execution profile status", "") != "CONFIRMED":
        errors.append("PROJECT.md: Execution profile status must be CONFIRMED before dispatch")
    for key in EXECUTION_PROFILE_KEYS:
        if is_placeholder(fields.get(key, "")):
            errors.append("PROJECT.md: {} must be concrete".format(key))
    if require_runtime_choice and is_placeholder(
        fields.get("Runtime choice confirmed by/at", "")
    ):
        errors.append(
            "PROJECT.md: Runtime choice confirmed by/at must be explicit; "
            "model/effort/permission approval cannot imply a runtime choice"
        )
    if require_monitoring:
        errors.extend(validate_monitoring_profile(fields))

    runtime = fields.get("Execution runtime", "").strip().lower()
    flavor = fields.get("Execution flavor", "").strip().lower()
    visibility = fields.get("Execution visibility", "").strip().lower()
    policy = fields.get("Model selection policy", "").strip().lower()
    if flavor not in {"claude", "codex"}:
        errors.append("PROJECT.md: Execution flavor must be claude or codex")
    if visibility not in {"visible", "headless"}:
        errors.append("PROJECT.md: Execution visibility must be visible or headless")
    if policy not in {"adaptive-batch", "fixed", "per-worker"}:
        errors.append(
            "PROJECT.md: Model selection policy must be adaptive-batch, fixed, or per-worker"
        )
    if runtime == "hapi":
        machine = fields.get("Execution machine", "")
        if "id=" not in machine:
            errors.append("PROJECT.md: HAPI Execution machine must include an exact id=")
        if "hapi" not in fields.get("Execution control", "").lower():
            errors.append("PROJECT.md: HAPI Execution control must name the verified HAPI path")
        if require_runtime_choice and "hapi" not in fields.get(
            "已启用可选适配器", ""
        ).lower():
            errors.append("PROJECT.md: HAPI must be listed in 已启用可选适配器")

    if policy == "fixed":
        fixed = runtime_config(fields.get("Fixed model/effort", ""))
        for key in ("model", "effort"):
            if runtime_value_is_placeholder(key, fixed.get(key, "")):
                errors.append(
                    "PROJECT.md: fixed model policy requires concrete {}".format(key)
                )
    return errors


def registered_worktrees(project):
    try:
        result = subprocess.run(
            ["git", "-C", str(project), "worktree", "list", "--porcelain"],
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except (OSError, subprocess.CalledProcessError):
        return {}

    worktrees = {}
    current = {}
    for raw in result.stdout.splitlines() + [""]:
        if not raw:
            if current.get("path"):
                worktrees[str(Path(current["path"]).resolve())] = current
            current = {}
        elif raw.startswith("worktree "):
            current["path"] = raw.split(" ", 1)[1]
        elif raw.startswith("HEAD "):
            current["head"] = raw.split(" ", 1)[1]
        elif raw.startswith("branch refs/heads/"):
            current["branch"] = raw[len("branch refs/heads/") :]
    return worktrees


def validate_goal_worktree(task_id, goal_data, worktrees):
    value = goal_data["assignments"].get("工作区", "")
    match = WORKTREE_VALUE.fullmatch(value)
    if not match:
        return [
            "{}: Goal 工作区 must be `absolute-path`（分支：`branch`）".format(
                task_id
            )
        ], ""

    raw_path, branch = match.groups()
    path = Path(raw_path)
    errors = []
    if not path.is_absolute():
        errors.append("{}: Goal worktree path must be absolute".format(task_id))
        return errors, str(path)
    resolved = str(path.resolve())
    actual = worktrees.get(resolved)
    if not path.is_dir() or not actual:
        errors.append(
            "{}: Goal worktree is not a registered Git worktree: {}".format(
                task_id, raw_path
            )
        )
        return errors, resolved
    if actual.get("branch") != branch:
        errors.append(
            "{}: Goal worktree branch mismatch: {!r} != {!r}".format(
                task_id, branch, actual.get("branch", "")
            )
        )
    baseline_match = re.search(r"\b[0-9a-fA-F]{7,40}\b", goal_data.get("baseline", ""))
    if not baseline_match:
        errors.append("{}: Goal baseline must contain a Git revision".format(task_id))
    elif not actual.get("head", "").startswith(baseline_match.group(0).lower()):
        errors.append("{}: Goal baseline does not match worktree HEAD".format(task_id))
    try:
        dirty = subprocess.run(
            ["git", "-C", resolved, "status", "--porcelain"],
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        ).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        dirty = "git-status-failed"
    if dirty:
        errors.append("{}: pre-dispatch worktree must be clean".format(task_id))
    return errors, resolved


def validate_task_against_execution_profile(task_id, requested, project_fields):
    errors = []
    expected = {
        "runtime": project_fields.get("Execution runtime", "").strip(),
        "flavor": project_fields.get("Execution flavor", "").strip(),
        "permission": normalize_permission(
            project_fields.get("Execution permission", "").strip()
        ),
        "visibility": project_fields.get("Execution visibility", "").strip(),
    }
    for key, value in expected.items():
        if value and requested.get(key) != value:
            errors.append(
                "{}: requested {} differs from confirmed Execution profile: {!r} != {!r}".format(
                    task_id, key, requested.get(key, ""), value
                )
            )
    if project_fields.get("Model selection policy", "").strip().lower() == "fixed":
        fixed = runtime_config(project_fields.get("Fixed model/effort", ""))
        for key in ("model", "effort"):
            if fixed.get(key) and requested.get(key) != fixed.get(key):
                errors.append(
                    "{}: requested {} differs from fixed Execution profile".format(
                        task_id, key
                    )
                )
    return errors


def validate_role(
    task_id,
    state,
    instance,
    fields,
    goal_assignments,
    registered_roles,
    team_revision,
    predispatch=False,
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
        if state in VISIBLE_STATES or predispatch:
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
            if profile.get("当前 Session ID", "") != fields.get("Session ID", ""):
                errors.append("{}: role profile Current Session ID differs from ledger".format(task_id))
        elif predispatch:
            if role_state != "reserved":
                errors.append("{}: inbox role must be reserved before spawn".format(task_id))
            if profile.get("当前 Goal", "") != "task:{}".format(task_id):
                errors.append("{}: reserved role Current Goal must reference this task".format(task_id))
            if profile.get("当前 Session ID", "") != "PENDING":
                errors.append("{}: reserved role Session ID must be PENDING".format(task_id))
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


def validate_hapi_evidence(
    task_id, task_dir, fields, observed, project_fields, require_goal_bound
):
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

    # Preserve completed pre-beta.8 history without pretending it had fields that
    # did not exist. Active/review work always uses the strict Goal-bound schema.
    if not require_goal_bound and "goal_ref" not in evidence:
        if evidence.get("phase") != "pre-dispatch":
            errors.append("{}: legacy HAPI evidence phase must be pre-dispatch".format(task_id))
        if evidence.get("messages_received") != 0:
            errors.append("{}: legacy HAPI evidence must precede dispatch".format(task_id))
        if str(evidence.get("session_id", "")) != fields.get("Session ID", ""):
            errors.append("{}: HAPI evidence Session ID differs from ledger".format(task_id))
        for key in ("flavor", "model", "effort", "permission"):
            evidence_value = str(evidence.get(key, ""))
            if key == "permission":
                evidence_value = normalize_permission(evidence_value)
            if evidence_value != observed.get(key, ""):
                errors.append(
                    "{}: legacy HAPI evidence {} differs from observed runtime".format(
                        task_id, key
                    )
                )
        return errors

    phase = evidence.get("phase")
    if phase not in {"pre-dispatch", "pre-redispatch"}:
        errors.append(
            "{}: HAPI evidence phase must be pre-dispatch or pre-redispatch".format(
                task_id
            )
        )
    if evidence.get("goal_ref") != "task:{}".format(task_id):
        errors.append("{}: HAPI evidence goal_ref must match this Goal".format(task_id))
    if json_value_is_placeholder(evidence.get("verification_id")):
        errors.append("{}: HAPI evidence requires a fresh verification_id".format(task_id))
    if evidence.get("thinking") is not False:
        errors.append("{}: HAPI evidence requires an idle, non-thinking session".format(task_id))
    if evidence.get("active") is not True or evidence.get("lifecycle") != "running":
        errors.append("{}: HAPI evidence requires an active/running session".format(task_id))

    watermark = evidence.get("message_watermark")
    if not isinstance(watermark, dict):
        errors.append("{}: HAPI evidence requires a message watermark".format(task_id))
        watermark = {}
    if json_value_is_placeholder(watermark.get("captured_at")):
        errors.append("{}: HAPI message watermark requires captured_at".format(task_id))
    if phase == "pre-dispatch" and (
        evidence.get("messages_received") != 0
        or watermark.get("snapshot_head_seq") is not None
    ):
        errors.append("{}: HAPI evidence must precede the first Goal message".format(task_id))
    if phase == "pre-redispatch" and not isinstance(
        evidence.get("messages_received"), int
    ):
        errors.append("{}: HAPI reuse evidence requires a message count".format(task_id))
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

    catalog = evidence.get("catalog")
    if not isinstance(catalog, dict) or catalog.get("status") != "VERIFIED":
        errors.append("{}: HAPI evidence requires VERIFIED model catalog data".format(task_id))
    else:
        if catalog.get("model_supported") is not True or catalog.get("effort_supported") is not True:
            errors.append("{}: HAPI catalog must prove model and effort support".format(task_id))
        for key in ("model", "effort"):
            if str(catalog.get(key, "")) != observed.get(key, ""):
                errors.append("{}: HAPI catalog {} differs from observed runtime".format(task_id, key))
        for key in ("source", "checked_at"):
            if json_value_is_placeholder(catalog.get(key)):
                errors.append("{}: HAPI catalog {} must be concrete".format(task_id, key))

    if project_fields.get("Execution runtime", "") == "hapi":
        machine_id = str(evidence.get("machine_id", ""))
        if not machine_id or machine_id not in project_fields.get("Execution machine", ""):
            errors.append("{}: HAPI evidence machine differs from Execution profile".format(task_id))
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


def validate(project, predispatch=False):
    instance = project / ".agent-taskgraph"
    queue = instance / "queue"
    status_path = instance / "STATUS.md"
    errors = []
    if not queue.is_dir() or not status_path.is_file():
        return ["missing .agent-taskgraph/queue or STATUS.md"]

    project_path = instance / "PROJECT.md"
    project_fields = {}
    if project_path.is_file():
        project_fields, project_duplicates = ledger_fields(project_path)
        if project_duplicates:
            errors.append(
                "PROJECT.md: duplicate fields: {}".format(
                    ", ".join(sorted(project_duplicates))
                )
            )

    strict_inbox = predispatch or protocol_at_least(project_fields, 11)
    worktrees = registered_worktrees(project)
    worktree_assignments = {}

    tasks = {}
    persistent_assignments = {}
    registered_roles = role_registry(instance / "ROLES.md")
    team_revision = role_team_revision(instance / "ROLES.md")
    active_or_review = False
    has_gated_inbox = False
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
            inbox_gated = state == "inbox" and strict_inbox
            if inbox_gated:
                has_gated_inbox = True
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
            role_required = inbox_gated or state in VISIBLE_STATES or (
                state == "done" and "Role ref" in fields
            )
            context_required = inbox_gated or state in VISIBLE_STATES or (
                state == "done" and "Context manifest" in fields
            )
            dispatch_required = identity_bootstrap_required(project_fields) and (
                inbox_gated
                or state in VISIBLE_STATES
                or (state == "done" and "Role ref" in fields)
            )
            if (runtime_evidence_required or inbox_gated) and is_placeholder(goal_data["baseline"]):
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

            failure_class = fields.get("Failure class", "").strip().upper()
            if failure_class and failure_class not in FAILURE_CLASSES:
                errors.append(
                    "{}: Failure class must be one of {}".format(
                        child.name, ", ".join(sorted(FAILURE_CLASSES))
                    )
                )
            if failure_class == "HARNESS_INVALID":
                harness_attempt = fields.get("Harness attempt", "")
                if not harness_attempt.isdigit():
                    errors.append("{}: HARNESS_INVALID requires numeric Harness attempt".format(child.name))
            if failure_class in {"DISPATCH_INVALID", "RUNTIME_INVALID"} and state in {"active", "review"}:
                errors.append(
                    "{}: {} must remain inbox until the control plane is repaired".format(
                        child.name, failure_class
                    )
                )

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
                        inbox_gated,
                    )
                )
                errors.extend(
                    validate_reviewer_role(
                        child.name, state, instance, fields, registered_roles
                    )
                )
                role_ref = fields.get("Role ref", "")
                if (state in VISIBLE_STATES or inbox_gated) and fields.get("Role lifecycle", "") == "persistent":
                    persistent_assignments.setdefault(role_ref, []).append(child.name)

            if context_required:
                errors.extend(validate_context(child.name, child, fields, goal_data))

            if dispatch_required:
                errors.extend(
                    validate_dispatch_bootstrap(
                        child.name,
                        child,
                        fields,
                        goal_data["assignments"],
                        team_revision,
                        inbox_gated,
                    )
                )

            if inbox_gated:
                requested = runtime_config(fields.get("Runtime requested", ""))
                missing_requested = [
                    key
                    for key in RUNTIME_KEYS
                    if runtime_value_is_placeholder(key, requested.get(key, ""))
                ]
                if missing_requested:
                    errors.append(
                        "{}: Runtime requested missing concrete fields: {}".format(
                            child.name, ", ".join(missing_requested)
                        )
                    )
                goal_requested = runtime_config(
                    goal_data["assignments"].get("Runtime requested", "")
                )
                if goal_requested != requested:
                    errors.append("{}: Goal and ledger Runtime requested differ".format(child.name))
                errors.extend(
                    validate_task_against_execution_profile(
                        child.name, requested, project_fields
                    )
                )
                worktree_errors, worktree_path = validate_goal_worktree(
                    child.name, goal_data, worktrees
                )
                errors.extend(worktree_errors)
                if worktree_path:
                    worktree_assignments.setdefault(worktree_path, []).append(child.name)

            if runtime_evidence_required:
                requested_raw = fields.get("Runtime requested", "")
                observed_raw = fields.get("Runtime observed", "")
                requested = runtime_config(requested_raw)
                observed = runtime_config(observed_raw)
                missing_requested = [
                    key
                    for key in RUNTIME_KEYS
                    if runtime_value_is_placeholder(key, requested.get(key, ""))
                ]
                missing_observed = [
                    key
                    for key in RUNTIME_KEYS
                    if runtime_value_is_placeholder(key, observed.get(key, ""))
                ]
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

                if state in VISIBLE_STATES:
                    errors.extend(
                        validate_task_against_execution_profile(
                            child.name, requested, project_fields
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
                    errors.extend(
                        validate_hapi_evidence(
                            child.name,
                            child,
                            fields,
                            observed,
                            project_fields if state in VISIBLE_STATES else {},
                            state in VISIBLE_STATES,
                        )
                    )

    for role_ref, task_ids in sorted(persistent_assignments.items()):
        if len(task_ids) > 1:
            errors.append(
                "{}: persistent role assigned to concurrent tasks: {}".format(
                    role_ref, ", ".join(sorted(task_ids))
                )
            )

    for worktree_path, task_ids in sorted(worktree_assignments.items()):
        if len(task_ids) > 1:
            errors.append(
                "worktree assigned to multiple inbox tasks: {} ({})".format(
                    worktree_path, ", ".join(sorted(task_ids))
                )
            )

    dispatch_gated = active_or_review or has_gated_inbox
    if dispatch_gated:
        if not project_path.is_file():
            errors.append("dispatch-gated tasks require PROJECT.md")
        else:
            protocol_version = project_fields.get("Agent TaskGraph 协议版本", "")
            if is_placeholder(protocol_version):
                errors.append(
                    "PROJECT.md: Agent TaskGraph 协议版本 must be concrete before dispatch"
                )
            source_baseline = project_fields.get("Source baseline", "")
            if not source_baseline.upper().startswith("READY:") or is_placeholder(source_baseline):
                errors.append("PROJECT.md: Source baseline must start with READY: before dispatch")
            errors.extend(
                validate_execution_profile(
                    project_fields,
                    require_runtime_choice=strict_inbox,
                    require_monitoring=protocol_at_least(project_fields, 12),
                )
            )
        errors.extend(validate_frozen_spec(instance))

    rows, duplicate_rows = status_rows(status_path)
    for task_id in sorted(duplicate_rows):
        errors.append("{}: duplicate STATUS.md row".format(task_id))
    tracked_states = VISIBLE_STATES | ({"inbox"} if strict_inbox else set())
    expected_visible = {
        task_id: state for task_id, state in tasks.items() if state in tracked_states
    }
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
    parser = argparse.ArgumentParser(
        description="Validate Agent TaskGraph queue and dispatch evidence"
    )
    parser.add_argument(
        "--phase",
        choices=("current", "pre-dispatch"),
        default="current",
        help="pre-dispatch applies the strict inbox gate even to older project versions",
    )
    parser.add_argument("project_directory")
    try:
        args = parser.parse_args(argv[1:])
    except SystemExit as exc:
        return int(exc.code)
    project = Path(args.project_directory).resolve()
    if not project.is_dir():
        print("Project directory does not exist: {}".format(project), file=sys.stderr)
        return 2
    errors = validate(project, predispatch=args.phase == "pre-dispatch")
    if errors:
        for error in errors:
            print("ERROR: {}".format(error), file=sys.stderr)
        return 1
    print("State validation passed: {}".format(project / ".agent-taskgraph"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
