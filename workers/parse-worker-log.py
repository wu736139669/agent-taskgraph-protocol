#!/usr/bin/env python3
"""Convert Codex JSONL or plain session logs into a compact progress stream."""

from __future__ import annotations

import argparse
import json
import sys
from typing import Any, Iterable


def compact(value: Any, limit: int) -> str:
    if isinstance(value, list):
        parts = []
        for item in value:
            if isinstance(item, dict):
                text = item.get("text") or item.get("output_text") or item.get("input_text")
                if text:
                    parts.append(str(text))
            elif item:
                parts.append(str(item))
        value = " ".join(parts)
    elif isinstance(value, dict):
        value = value.get("text") or value.get("message") or ""

    return " ".join(str(value or "").split())[:limit]


def parse_codex_event(event: dict[str, Any]) -> str | None:
    event_type = event.get("type", "")
    payload = event.get("payload") or {}
    payload_type = str(payload.get("type", ""))

    if event_type == "event_msg":
        if payload_type == "user_message":
            return f"USER: {compact(payload.get('message'), 100)}"
        if payload_type == "agent_message":
            return f"AGENT: {compact(payload.get('message'), 120)}"
        if payload_type in {"task_complete", "task_failed"}:
            return f"END: {payload_type.upper()}"
        if "error" in payload_type.lower():
            detail = compact(payload.get("message") or payload.get("error"), 120)
            return f"ERROR: {payload_type}{': ' + detail if detail else ''}"

    if event_type == "response_item":
        if payload_type == "agent_message":
            return f"AGENT: {compact(payload.get('content'), 120)}"
        if payload_type in {"function_call", "custom_tool_call"}:
            function = payload.get("function") or {}
            name = payload.get("name") or function.get("name") or "?"
            return f"CALL: {name}"

    return None


def parse_lines(lines: Iterable[str], log_format: str) -> Iterable[str]:
    for raw_line in lines:
        line = raw_line.strip()
        if not line:
            continue
        if log_format == "text":
            yield f"FILE: {compact(line, 150)}"
            continue
        try:
            event = json.loads(line)
        except (json.JSONDecodeError, TypeError):
            continue
        if not isinstance(event, dict):
            continue
        parsed = parse_codex_event(event)
        if parsed:
            yield parsed


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--format", choices=("jsonl", "text"), default="jsonl")
    args = parser.parse_args()

    for output in parse_lines(sys.stdin, args.format):
        print(output, flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
