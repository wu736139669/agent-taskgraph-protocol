#!/usr/bin/env python3
"""Validate Agent TaskGraph topology without third-party dependencies."""

import ast
import json
import re
import sys
from pathlib import Path


NODE_START = re.compile(r'^  - id:\s*(.+?)\s*$')
FIELD = re.compile(r'^    ([A-Za-z_][A-Za-z0-9_]*):\s*(.*?)\s*$')
LIST_FIELDS = ("needs", "consumes", "produces", "writes")
KINDS = {"expert", "worker", "verifier", "merge", "human_gate"}
TERMINALS = {"done", "failed"}


class ValidationError(Exception):
    pass


def scalar(value, line_number):
    value = value.strip()
    if not value:
        return ""
    if value[0] in "\"'":
        try:
            parsed = ast.literal_eval(value)
        except (SyntaxError, ValueError) as exc:
            raise ValidationError("line {}: invalid quoted scalar: {}".format(line_number, exc))
        if not isinstance(parsed, str):
            raise ValidationError("line {}: expected a string".format(line_number))
        return parsed
    return value


def inline_list(value, field_name, line_number):
    try:
        parsed = json.loads(value)
    except json.JSONDecodeError as exc:
        raise ValidationError(
            "line {}: {} must be a JSON-compatible inline list: {}".format(
                line_number, field_name, exc.msg
            )
        )
    if not isinstance(parsed, list) or not all(isinstance(item, str) for item in parsed):
        raise ValidationError("line {}: {} must be a list of strings".format(line_number, field_name))
    return parsed


def parse_nodes(path):
    nodes = []
    current = None
    for line_number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        start = NODE_START.match(raw)
        if start:
            if current:
                nodes.append(current)
            current = {"id": scalar(start.group(1), line_number), "_line": line_number}
            continue
        if current is None:
            continue
        field_match = FIELD.match(raw)
        if not field_match:
            continue
        name, value = field_match.groups()
        if name in LIST_FIELDS:
            current[name] = inline_list(value, name, line_number)
        elif name == "max_attempts":
            try:
                current[name] = int(value)
            except ValueError:
                raise ValidationError("line {}: max_attempts must be an integer".format(line_number))
        elif name in {"title", "kind", "goal_ref", "goal", "on_pass", "on_fail"}:
            current[name] = scalar(value, line_number)
    if current:
        nodes.append(current)
    if not nodes:
        raise ValidationError("no nodes found; expected two-space '- id:' entries")
    return nodes


def ancestors(node_id, by_id, memo, visiting):
    if node_id in memo:
        return memo[node_id]
    if node_id in visiting:
        raise ValidationError("needs cycle detected at {}".format(node_id))
    visiting.add(node_id)
    result = set()
    for dependency in by_id[node_id]["needs"]:
        result.add(dependency)
        result.update(ancestors(dependency, by_id, memo, visiting))
    visiting.remove(node_id)
    memo[node_id] = result
    return result


def path_contains(owner, target):
    owner = owner.strip().rstrip("/")
    target = target.strip().rstrip("/")
    if not owner or not target:
        return False
    return target == owner or target.startswith(owner + "/")


def paths_overlap(left, right):
    return path_contains(left, right) or path_contains(right, left)


def validate(path):
    nodes = parse_nodes(path)
    errors = []
    by_id = {}

    required = ("id", "title", "kind", "goal_ref", "needs", "consumes", "produces", "writes", "on_pass", "on_fail", "max_attempts")
    for node in nodes:
        node_id = node.get("id", "")
        if not node_id:
            errors.append("line {}: empty node id".format(node["_line"]))
            continue
        if node_id in by_id:
            errors.append("duplicate node id: {}".format(node_id))
        by_id[node_id] = node
        missing = [name for name in required if name not in node]
        if missing:
            errors.append("{}: missing fields {}".format(node_id, ", ".join(missing)))
        if "goal" in node:
            errors.append("{}: use stable goal_ref, not goal".format(node_id))
        goal_ref = node.get("goal_ref", "")
        if "goal_ref" in node and not goal_ref:
            errors.append("{}: goal_ref must not be empty".format(node_id))
        if re.search(r'queue/(inbox|active|review|done|failed)', goal_ref):
            errors.append("{}: goal_ref contains a dynamic queue path".format(node_id))
        if goal_ref and not goal_ref.startswith(("task:", "decision:")):
            errors.append("{}: goal_ref must start with task: or decision:".format(node_id))
        if node.get("kind") not in KINDS:
            errors.append("{}: unsupported kind {}".format(node_id, node.get("kind")))
        if node.get("max_attempts", 0) < 1:
            errors.append("{}: max_attempts must be greater than zero".format(node_id))

    if errors:
        return errors

    for node in nodes:
        for dependency in node["needs"]:
            if dependency not in by_id:
                errors.append("{}: unknown needs target {}".format(node["id"], dependency))
        for route_name in ("on_pass", "on_fail"):
            target = node[route_name]
            if target not in by_id and target not in TERMINALS:
                errors.append("{}: unknown {} target {}".format(node["id"], route_name, target))
    if errors:
        return errors

    memo = {}
    try:
        for node_id in by_id:
            ancestors(node_id, by_id, memo, set())
    except ValidationError as exc:
        errors.append(str(exc))
        return errors

    owner_paths = {}
    for node in nodes:
        owner_paths[node["id"]] = node["produces"] + node["writes"]

    for node in nodes:
        node_ancestors = memo[node["id"]]
        for consumed in node["consumes"]:
            producers = {
                candidate["id"]
                for candidate in nodes
                if candidate["id"] != node["id"]
                and any(paths_overlap(path, consumed) for path in owner_paths[candidate["id"]])
            }
            if producers and not (producers & node_ancestors):
                errors.append(
                    "{} consumes {!r} from {}, but none is in its needs ancestry".format(
                        node["id"], consumed, ", ".join(sorted(producers))
                    )
                )

    for index, left in enumerate(nodes):
        for right in nodes[index + 1 :]:
            if right["id"] in memo[left["id"]] or left["id"] in memo[right["id"]]:
                continue
            for left_write in left["writes"]:
                for right_write in right["writes"]:
                    if paths_overlap(left_write, right_write):
                        errors.append(
                            "parallel write overlap: {} {!r} vs {} {!r}".format(
                                left["id"], left_write, right["id"], right_write
                            )
                        )
    return errors


def main(argv):
    if len(argv) != 2:
        print("Usage: validate-graph.py <graph.yaml>", file=sys.stderr)
        return 2
    path = Path(argv[1])
    if not path.is_file():
        print("Graph file does not exist: {}".format(path), file=sys.stderr)
        return 2
    try:
        errors = validate(path)
    except ValidationError as exc:
        errors = [str(exc)]
    if errors:
        for error in errors:
            print("ERROR: {}".format(error), file=sys.stderr)
        return 1
    print("Graph validation passed: {}".format(path))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
