#!/usr/bin/env python3
"""Validate local Markdown links, structure, versions, and mirrored Skill docs."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parents[1]
PLUGIN_SKILL = ROOT / "plugins/agent-taskgraph/skills/agent-taskgraph"
LINK_RE = re.compile(r"!?\[[^\]]*\]\(([^)]+)\)")
HEADING_RE = re.compile(r"^(#{1,6})\s+\S")
VERSION_RE = re.compile(r"v?0\.8\.0-beta\.\d+")


def markdown_files() -> list[Path]:
    result = []
    for path in ROOT.rglob("*.md"):
        relative = path.relative_to(ROOT)
        if ".git" in relative.parts or "videos" in relative.parts:
            continue
        result.append(path)
    return sorted(result)


def visible_lines(text: str):
    in_fence = False
    fence = ""
    for number, line in enumerate(text.splitlines(), 1):
        stripped = line.lstrip()
        if stripped.startswith(("```", "~~~")):
            marker = stripped[:3]
            if not in_fence:
                in_fence = True
                fence = marker
            elif marker == fence:
                in_fence = False
                fence = ""
            continue
        if not in_fence:
            yield number, line
    if in_fence:
        yield -1, "UNCLOSED_FENCE"


def validate_markdown(path: Path) -> list[str]:
    errors = []
    text = path.read_text(encoding="utf-8")
    relative = path.relative_to(ROOT)

    for number, line in enumerate(text.splitlines(), 1):
        if line.rstrip() != line:
            errors.append(f"{relative}:{number}: trailing whitespace")

    visible = list(visible_lines(text))
    if visible and visible[-1] == (-1, "UNCLOSED_FENCE"):
        errors.append(f"{relative}: unclosed Markdown fence")
        visible.pop()

    if not relative.parts[0] == ".github":
        headings = []
        for number, line in visible:
            match = HEADING_RE.match(line)
            if match:
                headings.append((number, len(match.group(1))))
        h1_count = sum(level == 1 for _, level in headings)
        if h1_count != 1:
            errors.append(f"{relative}: expected exactly one H1, found {h1_count}")
        for (number, level), (_, previous) in zip(headings[1:], headings):
            if level > previous + 1:
                errors.append(
                    f"{relative}:{number}: heading jumps from H{previous} to H{level}"
                )

    for number, line in visible:
        for raw_target in LINK_RE.findall(line):
            target = raw_target.strip().split(maxsplit=1)[0].strip("<>")
            if target.startswith(("http://", "https://", "mailto:", "#")):
                continue
            local = unquote(target.split("#", 1)[0])
            if local and not (path.parent / local).resolve().exists():
                errors.append(f"{relative}:{number}: missing local link target {target}")
    return errors


def validate_versions() -> list[str]:
    errors = []
    version = (ROOT / "VERSION").read_text(encoding="utf-8").strip()
    manifests = (
        ROOT / ".claude-plugin/marketplace.json",
        ROOT / "plugins/agent-taskgraph/.claude-plugin/plugin.json",
        ROOT / "plugins/agent-taskgraph/.codex-plugin/plugin.json",
    )
    for path in manifests:
        data = json.loads(path.read_text(encoding="utf-8"))
        actual = data["plugins"][0]["version"] if path.name == "marketplace.json" else data["version"]
        if actual != version:
            errors.append(f"{path.relative_to(ROOT)}: version {actual} != {version}")

    if (PLUGIN_SKILL / "VERSION").read_text(encoding="utf-8").strip() != version:
        errors.append("plugin Skill VERSION differs from root VERSION")

    for name in ("README.md", "README.zh-CN.md", "plugins/agent-taskgraph/README.md"):
        path = ROOT / name
        found = set(VERSION_RE.findall(path.read_text(encoding="utf-8")))
        if found != {f"v{version}"}:
            errors.append(f"{name}: expected only v{version}, found {sorted(found)}")
    return errors


def validate_doc_mirrors() -> list[str]:
    errors = []
    pairs = [
        (ROOT / "SKILL.md", PLUGIN_SKILL / "SKILL.md"),
        (ROOT / "references/native-runtimes.md", PLUGIN_SKILL / "references/native-runtimes.md"),
        (ROOT / "references/team-protocol.md", PLUGIN_SKILL / "references/team-protocol.md"),
        (ROOT / "references/development-team-example.md", PLUGIN_SKILL / "references/development-team-example.md"),
    ]
    pairs.extend(
        (path, PLUGIN_SKILL / "templates" / path.name)
        for path in sorted((ROOT / "templates").glob("*.md"))
    )
    for source, mirror in pairs:
        if not mirror.is_file():
            errors.append(f"missing plugin mirror: {mirror.relative_to(ROOT)}")
        elif source.read_bytes() != mirror.read_bytes():
            errors.append(f"plugin mirror differs: {source.relative_to(ROOT)}")
    return errors


def main() -> int:
    files = markdown_files()
    errors = []
    for path in files:
        errors.extend(validate_markdown(path))
    errors.extend(validate_versions())
    errors.extend(validate_doc_mirrors())
    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print(f"Documentation validation passed: {len(files)} Markdown files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
