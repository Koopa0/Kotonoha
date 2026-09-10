#!/usr/bin/env python3
"""Fail closed on a Dart/Flutter JSON test report.

A missing file, a successful-looking report with zero executable tests,
an all-skipped suite, a missing required name, or any failure is red.
Hidden loader tests are ignored. This is the floor that keeps
"the file exists" from counting as execution.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections.abc import Iterable
from pathlib import Path


def _events(path: Path) -> list[dict]:
    text = path.read_text(encoding="utf-8")
    stripped = text.strip()
    if not stripped:
        return []
    if stripped[0] == "[":
        payload = json.loads(stripped)
        if not isinstance(payload, list):
            raise ValueError("JSON array report must contain objects")
        return [item for item in payload if isinstance(item, dict)]
    events: list[dict] = []
    for line_no, raw in enumerate(text.splitlines(), start=1):
        line = raw.strip()
        if not line:
            continue
        try:
            item = json.loads(line)
        except json.JSONDecodeError as exc:
            raise ValueError(f"{path}:{line_no}: invalid JSON") from exc
        if isinstance(item, dict):
            events.append(item)
    return events


def _summarize(events: Iterable[dict]) -> dict[str, object]:
    names: dict[int, str] = {}
    hidden_ids: set[int] = set()
    passed: list[str] = []
    skipped: list[str] = []
    failed: list[str] = []
    hidden = 0
    success = None
    for event in events:
        kind = event.get("type")
        if kind == "testStart":
            test = event.get("test") or {}
            test_id = test.get("id")
            name = test.get("name")
            if isinstance(test_id, int) and isinstance(name, str):
                names[test_id] = name
        elif kind == "testDone":
            test_id = event.get("testID")
            name = names.get(test_id, f"id:{test_id}")
            if event.get("hidden") is True:
                hidden += 1
                if isinstance(test_id, int):
                    hidden_ids.add(test_id)
                continue
            result = event.get("result")
            if event.get("skipped") is True:
                skipped.append(name)
            elif result == "success":
                passed.append(name)
            else:
                failed.append(name)
        elif kind == "done":
            success = event.get("success")
    executable = passed + skipped + failed
    return {
        "passed": passed,
        "skipped": skipped,
        "failed": failed,
        "hidden": hidden,
        "executable": executable,
        "success": success,
    }


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", required=True, type=Path)
    parser.add_argument("--min-passed", type=int, default=1)
    parser.add_argument("--forbid-skip", action="store_true")
    parser.add_argument("--require-name", action="append", default=[])
    args = parser.parse_args(argv)

    report: Path = args.report
    if not report.is_file():
        print(f"test report missing: {report}", file=sys.stderr)
        return 1

    try:
        summary = _summarize(_events(report))
    except ValueError as exc:
        print(f"unreadable test report: {exc}", file=sys.stderr)
        return 1

    passed: list[str] = summary["passed"]  # type: ignore[assignment]
    skipped: list[str] = summary["skipped"]  # type: ignore[assignment]
    failed: list[str] = summary["failed"]  # type: ignore[assignment]
    executable: list[str] = summary["executable"]  # type: ignore[assignment]
    print(
        f"report={report} executable={len(executable)} "
        f"passed={len(passed)} skipped={len(skipped)} "
        f"failed={len(failed)} hidden={summary['hidden']} "
        f"done.success={summary['success']}"
    )
    if passed:
        print("passed names:")
        for name in passed:
            print(f"  - {name}")
    if skipped:
        print("skipped names:")
        for name in skipped:
            print(f"  - {name}")
    if failed:
        print("failed names:")
        for name in failed:
            print(f"  - {name}")

    problems: list[str] = []
    if not executable:
        problems.append("zero executable tests (file presence is not execution)")
    if len(passed) < args.min_passed:
        problems.append(
            f"need at least {args.min_passed} passed test(s), got {len(passed)}"
        )
    if args.forbid_skip and skipped:
        problems.append("skipped tests are forbidden in this isolated gate")
    if failed:
        problems.append("one or more tests failed")
    if summary["success"] is False:
        problems.append("reporter marked the run unsuccessful")
    missing = [name for name in args.require_name if name not in passed]
    if missing:
        problems.append("required passed names missing: " + ", ".join(missing))

    if problems:
        for problem in problems:
            print(f"gate red: {problem}", file=sys.stderr)
        return 1
    print("gate green: required tests ran and passed")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
