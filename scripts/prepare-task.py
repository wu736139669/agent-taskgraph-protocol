#!/usr/bin/env python3
"""Create a schema-stable inbox task and prove it is safe to spawn."""

import argparse
import json
import re
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path


TASK_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
RUNTIME_KEYS = ("runtime", "flavor", "model", "effort", "permission", "visibility")
ORCHESTRATION_MODES = {"lite", "governed"}


class PrepareError(RuntimeError):
    pass


def required(data, key, expected_type=str):
    value = data.get(key)
    if not isinstance(value, expected_type) or (
        expected_type is str and not value.strip()
    ):
        raise PrepareError("manifest requires a concrete {}".format(key))
    return value


def string_list(data, key):
    values = required(data, key, list)
    if not values or not all(isinstance(value, str) and value.strip() for value in values):
        raise PrepareError("manifest {} must be a non-empty string list".format(key))
    return values


def runtime_string(runtime):
    missing = [
        key
        for key in RUNTIME_KEYS
        if not isinstance(runtime.get(key), str) or not runtime[key].strip()
    ]
    if missing:
        raise PrepareError(
            "manifest runtime_requested requires {}".format(", ".join(missing))
        )
    return "; ".join("{}={}".format(key, runtime[key]) for key in RUNTIME_KEYS)


def git_value(worktree, *args):
    try:
        return subprocess.run(
            ["git", "-C", str(worktree), *args],
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        ).stdout.strip()
    except (OSError, subprocess.CalledProcessError) as exc:
        raise PrepareError("Git worktree check failed: {}".format(exc)) from exc


def verify_worktree(path, branch, baseline):
    worktree = Path(path).expanduser().resolve()
    if not worktree.is_dir():
        raise PrepareError("worktree does not exist: {}".format(worktree))
    if git_value(worktree, "branch", "--show-current") != branch:
        raise PrepareError("worktree branch does not match manifest")
    head = git_value(worktree, "rev-parse", "HEAD")
    if head != baseline:
        raise PrepareError("worktree HEAD does not match manifest baseline")
    if git_value(worktree, "status", "--porcelain"):
        raise PrepareError("worktree must be clean before dispatch")
    return worktree


def role_fields(path):
    fields = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        if not raw.startswith("|"):
            continue
        cells = [cell.strip() for cell in raw.strip().strip("|").split("|")]
        if len(cells) == 2 and cells[0] not in {"字段", "---"}:
            fields[cells[0]] = cells[1]
    return fields


def verify_reserved_role(instance, task_id, role_id, lifecycle, team_revision):
    profile = instance / "roles" / role_id / "ROLE.md"
    if not profile.is_file():
        raise PrepareError("reserved role profile is missing: {}".format(profile))
    fields = role_fields(profile)
    expected = {
        "Role ID": role_id,
        "Team revision": team_revision,
        "生命周期": lifecycle,
        "状态": "reserved",
        "当前 Goal": "task:{}".format(task_id),
        "当前 Session ID": "PENDING",
    }
    for key, value in expected.items():
        if fields.get(key) != value:
            raise PrepareError(
                "role profile {} must be {!r}, got {!r}".format(
                    key, value, fields.get(key, "")
                )
            )


def markdown_list(values):
    return "\n".join("- {}".format(value) for value in values)


def render_files(data, team_revision, worktree):
    tick = chr(96)
    task_id = data["task_id"]
    role_id = data["role_id"]
    role_ref = "role:{}".format(role_id)
    lifecycle = data["role_lifecycle"]
    context_revision = data["context_revision"]
    dispatch_id = "dispatch:{}:attempt-1".format(task_id)
    expected_ack = (
        "IDENTITY_READY dispatch_id={} role={} team_revision={} "
        "goal=task:{} context_revision={}"
    ).format(dispatch_id, role_ref, team_revision, task_id, context_revision)
    runtime = runtime_string(data["runtime_requested"])
    orchestration_mode = data["orchestration_mode"]
    route = "needs: {}; PASS -> {}; FAIL -> {}; max_attempts={}".format(
        ", ".join(data["needs"]),
        data["pass_route"],
        data["fail_route"],
        data["max_attempts"],
    )
    now = datetime.now(timezone.utc).isoformat(timespec="seconds")

    goal_template = """# Goal: {title}

> Stage: {stage}
> Started: {now}
> Task ID: {tick}{task_id}{tick}
> Baseline: {tick}{baseline}; branch={branch}; clean{tick}
> Frozen spec: {tick}{frozen_spec}{tick}
> Graph node: {tick}{graph_node}{tick}
> Independent contract: 不适用
> Context manifest: {tick}context.md{tick}
> Context revision: {tick}{context_revision}{tick}
> Legal terminal: **{task_id} candidate ready** 或 **{task_id} redesign required: <最早失败边界>**
> Orchestration mode: {orchestration_mode}

## Objective

{objective}

## 图输入、输出与写入范围

- 直接依赖（needs）：{needs}
- 必须读取（consumes）：{consumes}
- 必须产出（produces）：{produces}
- 唯一写入范围（writes）：{writes}
- 路由：PASS -> {pass_route}；FAIL -> {fail_route}；最大尝试 {max_attempts}
- 失败策略：{failure_policy}

## 分配记录

- Role ref：{tick}{role_ref}{tick}
- 角色职责：{role_responsibility}
- 角色生命周期：{lifecycle}
- 派给：{role_id}
- 分配理由：职责匹配
- 连续性：{role_continuity}
- 工作区：{tick}{worktree}{tick}（分支：{tick}{branch}{tick}）
- Runtime requested：{tick}{runtime}{tick}
- Runtime observed：{tick}PENDING{tick}
- Runtime verification：{tick}PENDING{tick}
- Session evidence：{tick}PENDING{tick}
- Dispatch bootstrap：{tick}dispatch.md{tick}
- Dispatch message：{tick}NOT_SENT{tick}
- Identity ACK：{tick}PENDING{tick}
- 完整启动方式：派发预览批准后由所选 runtime 控制面生成

## 报告协议

- 完成、失败或阻塞时通知 PMO，并引用任务号、legal terminal 和证据路径。
- worker 不修改 PMO 管理的 queue ledger、STATUS 或角色注册表。

## 验收标准（证据门）

{acceptance}

## Frozen（禁止触碰，明确列出）

{frozen}

## Estimate

{estimate}

## 完成时交付

- graph 节点约定的 produces
- 验收证据与残余风险
"""
    goal_values = dict(data)
    goal_values.update(
        {
            "tick": tick,
            "now": now,
            "worktree": worktree,
            "runtime": runtime,
            "orchestration_mode": orchestration_mode,
            "role_ref": role_ref,
            "lifecycle": lifecycle,
            "acceptance": markdown_list(data["acceptance"]),
            "frozen": markdown_list(data["frozen"]),
            "needs": ", ".join(data["needs"]),
            "consumes": ", ".join(data["consumes"]),
            "produces": ", ".join(data["produces"]),
            "writes": ", ".join(data["writes"]),
        }
    )
    goal = goal_template.format(**goal_values)

    ledger = """# 台账记录：{task_id}

| 字段 | 值 |
|---|---|
| 任务 ID | {task_id} |
| Goal ref | task:{task_id} |
| Goal current path | queue/inbox/{task_id}/goal.md |
| Context manifest | context.md |
| Context revision | {context_revision} |
| Role ref | {role_ref} |
| Role lifecycle | {lifecycle} |
| Role profile | roles/{role_id}/ROLE.md |
| Role continuity | {role_continuity} |
| Reviewer Role ref | PENDING |
| Reviewer Role profile | PENDING |
| Frozen spec | {frozen_spec} |
| Graph node | {graph_node} |
| 编排模式 | {orchestration_mode} |
| 依赖/路由 | {route} |
| 状态 | inbox |
| 负责人 | {role_id} |
| 分配理由 | 职责匹配 |
| 轮次 | 1 |
| 开始时间 | {now} |
| 最后更新 | {now} |
| 验收结果 | PENDING |
| Failure class | PENDING |
| Failure boundary | {task_id} |
| Harness attempt | 0 |
| Batch approved at | {now} |
| 日志指针 | PENDING |
| Runtime requested | {runtime} |
| Runtime observed | PENDING |
| Runtime verification | PENDING |
| Session ID | PENDING |
| Runtime evidence | PENDING |
| Dispatch bootstrap | dispatch.md |
| Dispatch message | NOT_SENT |
| Identity ACK | PENDING |
| 等待归属 | 在等谁：PMO；等什么：spawn + runtime verification + IDENTITY_READY；静默 5 分钟必须诊断并告知 Owner |

## 备注

Prepared from task-manifest.json. Do not hand-edit field names.

## 状态转换历史（追加式）

| 时间 | from -> to | 操作者 | 依据/证据 | 唯一下一步 |
|---|---|---|---|---|
| {now} | created -> inbox | PMO | structured manifest | run pre-dispatch validation |
""".format(
        task_id=task_id,
        context_revision=context_revision,
        role_ref=role_ref,
        lifecycle=lifecycle,
        role_id=role_id,
        role_continuity=data["role_continuity"],
        frozen_spec=data["frozen_spec"],
        graph_node=data["graph_node"],
        route=route,
        now=now,
        runtime=runtime,
        orchestration_mode=orchestration_mode,
    )

    context_rows = "\n".join(
        "| {tick}{path}{tick} | {revision} | {reason} |".format(
            tick=tick, **item
        )
        for item in data["context_items"]
    )
    context = """# Context Manifest: {task_id}

> Task ID: {tick}{task_id}{tick}
> Revision: {tick}{context_revision}{tick}
> Mode: {tick}{context_mode}{tick}
> Budget exception: {tick}none{tick}

## 必须读取（默认不超过 8 项）

| 路径或稳定引用 | Revision / 范围 | 为什么本 Goal 必须读 |
|---|---|---|
{context_rows}

## 按需检索（先搜索，再局部读取）

| 路径/范围 | 触发条件 | 检索提示 |
|---|---|---|
| source tree | Goal 需要实现细节时 | 先 rg，再局部读取 |

## 最近 Delta

- {now}: structured pre-dispatch manifest created.
""".format(
        tick=tick,
        task_id=task_id,
        context_revision=context_revision,
        context_mode=data["context_mode"],
        context_rows=context_rows,
        now=now,
    )

    dispatch = """# Dispatch Bootstrap: {task_id}

| Field | Value |
|---|---|
| Task ID | {task_id} |
| Dispatch ID | {dispatch_id} |
| Role ref | {role_ref} |
| Role profile | roles/{role_id}/ROLE.md |
| Role lifecycle | {lifecycle} |
| Team revision | {team_revision} |
| Goal ref | task:{task_id} |
| Context manifest | context.md |
| Context revision | {context_revision} |
| Continuity | {role_continuity} |
| Session ID | PENDING |
| Expected identity ACK | {expected_ack} |
| Delivery | NOT_SENT |
| Identity ACK | PENDING |
| ACK evidence | PENDING |

Read Role, PROJECT, context, Goal and direct evidence in that order. Return the exact identity ACK before executing the Goal.
""".format(
        task_id=task_id,
        dispatch_id=dispatch_id,
        role_ref=role_ref,
        role_id=role_id,
        lifecycle=lifecycle,
        team_revision=team_revision,
        context_revision=context_revision,
        role_continuity=data["role_continuity"],
        expected_ack=expected_ack,
    )
    return {
        "goal.md": goal,
        "ledger.md": ledger,
        "context.md": context,
        "dispatch.md": dispatch,
    }


def add_status_row(status_text, task_id, title, role_id):
    if "|" in title:
        raise PrepareError("title cannot contain a table separator")
    row = "| {} | {} | inbox | {} | 1 | now | preparing 0/1: session not created |".format(
        task_id, title, role_id
    )
    marker = "\n## 当前批次总结"
    if marker not in status_text:
        raise PrepareError("STATUS.md is missing 当前批次总结")
    return status_text.replace(marker, "\n{}\n{}".format(row, marker), 1)


def load_manifest(path):
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise PrepareError("cannot read manifest: {}".format(exc)) from exc
    if not isinstance(data, dict):
        raise PrepareError("manifest root must be an object")
    # Older beta manifests remain usable; new tasks are rendered with explicit
    # defaults so the failure policy cannot disappear from the ledger.
    data.setdefault("orchestration_mode", "lite")
    data.setdefault(
        "failure_policy",
        "PRODUCT_FAIL returns to worker; HARNESS_INVALID reuses reviewer; "
        "DISPATCH_INVALID/RUNTIME_INVALID repair control plane in place",
    )
    for key in (
        "task_id",
        "title",
        "orchestration_mode",
        "stage",
        "baseline",
        "branch",
        "worktree",
        "frozen_spec",
        "graph_node",
        "context_revision",
        "context_mode",
        "role_id",
        "role_lifecycle",
        "role_responsibility",
        "role_continuity",
        "objective",
        "pass_route",
        "fail_route",
        "failure_policy",
        "estimate",
    ):
        required(data, key)
    for key in ("needs", "consumes", "produces", "writes", "acceptance", "frozen"):
        string_list(data, key)
    required(data, "runtime_requested", dict)
    items = required(data, "context_items", list)
    if not 1 <= len(items) <= 8:
        raise PrepareError("context_items must contain 1-8 entries")
    for item in items:
        if not isinstance(item, dict):
            raise PrepareError("each context item must be an object")
        for key in ("path", "revision", "reason"):
            required(item, key)
    if data["context_mode"] not in {"lean", "balanced", "deep"}:
        raise PrepareError("context_mode must be lean, balanced, or deep")
    if data["role_lifecycle"] not in {"persistent", "task-scoped"}:
        raise PrepareError("role_lifecycle must be persistent or task-scoped")
    if data["orchestration_mode"] not in ORCHESTRATION_MODES:
        raise PrepareError("orchestration_mode must be lite or governed")
    if not isinstance(data.get("max_attempts"), int) or data["max_attempts"] < 1:
        raise PrepareError("max_attempts must be a positive integer")
    if not TASK_ID.fullmatch(data["task_id"]):
        raise PrepareError("invalid task_id")
    return data


def prepare(project, manifest_path):
    project = project.resolve()
    instance = project / ".agent-taskgraph"
    if not instance.is_dir():
        raise PrepareError("project is not initialized with .agent-taskgraph")
    health_script = Path(__file__).with_name("check-operational-health.py")
    health = subprocess.run(
        [str(health_script), str(project), "--json"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if health.returncode:
        try:
            details = json.loads(health.stdout)
            reason = "; ".join(details.get("reasons", []))
        except (json.JSONDecodeError, TypeError):
            reason = health.stderr.strip() or health.stdout.strip()
        raise PrepareError(
            "operational health is CIRCUIT_OPEN; no new task may be prepared{}".format(
                ": " + reason if reason else ""
            )
        )
    data = load_manifest(manifest_path)
    baseline = required(data, "baseline")
    if not re.fullmatch(r"[0-9a-fA-F]{40}", baseline):
        raise PrepareError("baseline must be a full 40-character Git revision")
    worktree = verify_worktree(data["worktree"], data["branch"], baseline)

    roles_path = instance / "ROLES.md"
    roles_text = roles_path.read_text(encoding="utf-8")
    team_revision = ""
    for raw in roles_text.splitlines():
        if raw.startswith("> Team revision:"):
            team_revision = raw.split(":", 1)[1].strip().strip(chr(96))
            break
    if not team_revision or team_revision.upper() == "PENDING":
        raise PrepareError("ROLES.md requires a concrete Team revision")
    verify_reserved_role(
        instance,
        data["task_id"],
        data["role_id"],
        data["role_lifecycle"],
        team_revision,
    )

    destination = instance / "queue" / "inbox" / data["task_id"]
    if destination.exists():
        raise PrepareError("task already exists: {}".format(destination))
    status_path = instance / "STATUS.md"
    original_status = status_path.read_text(encoding="utf-8")
    updated_status = add_status_row(
        original_status, data["task_id"], data["title"], data["role_id"]
    )
    files = render_files(data, team_revision, worktree)

    temporary = Path(
        tempfile.mkdtemp(prefix=".{}-".format(data["task_id"]), dir=destination.parent)
    )
    try:
        for name, content in files.items():
            (temporary / name).write_text(content, encoding="utf-8")
        (temporary / "task-manifest.json").write_text(
            json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        temporary.rename(destination)
        status_path.write_text(updated_status, encoding="utf-8")
        validator = Path(__file__).with_name("validate-state.py")
        result = subprocess.run(
            [str(validator), "--phase", "pre-dispatch", str(project)],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        if result.returncode:
            raise PrepareError(result.stderr.strip() or "pre-dispatch validation failed")
    except Exception:
        status_path.write_text(original_status, encoding="utf-8")
        if destination.exists():
            shutil.rmtree(destination)
        if temporary.exists():
            shutil.rmtree(temporary)
        raise
    return destination


def main(argv):
    parser = argparse.ArgumentParser(
        description="Create an inbox task from a structured JSON manifest"
    )
    parser.add_argument("--project", required=True)
    parser.add_argument("--manifest", required=True)
    args = parser.parse_args(argv[1:])
    try:
        destination = prepare(
            Path(args.project).expanduser(), Path(args.manifest).expanduser()
        )
    except (OSError, PrepareError) as exc:
        print("ERROR: {}".format(exc), file=sys.stderr)
        return 1
    print("Prepared and validated: {}".format(destination))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
