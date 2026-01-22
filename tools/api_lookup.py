#!/usr/bin/env python3
"""Search the BeamNG API TXT dump with context."""

from __future__ import annotations

import argparse
from pathlib import Path

DUMP_PATH = Path("docs/beamng-api/raw/api_dump_0.38.txt")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Search BeamNG API dump with context.")
    parser.add_argument("query", help="Substring to search for")
    parser.add_argument("--limit", type=int, default=20, help="Maximum number of matches to show")
    parser.add_argument("--context-before", type=int, default=2, help="Lines before match")
    parser.add_argument("--context-after", type=int, default=6, help="Lines after match")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if not DUMP_PATH.exists():
        raise SystemExit(f"Missing dump: {DUMP_PATH}")

    lines = DUMP_PATH.read_text(encoding="utf-8", errors="replace").splitlines()
    query = args.query.lower()

    matches: list[int] = []
    matching_modules: set[str] = set()
    matching_functions: set[str] = set()

    for idx, line in enumerate(lines):
        if query not in line.lower():
            continue
        matches.append(idx)

        stripped = line.strip()
        if line and not line.startswith(" ") and ":" in line:
            matching_modules.add(stripped.split(":", 1)[0])
        if line.startswith("    ") and stripped and not stripped.endswith(":") and not stripped.startswith("("):
            matching_functions.add(stripped)

    print(f"Query: {args.query}")
    print(f"Total matches: {len(matches)}")
    print("")

    if matching_modules:
        print("Matching modules/tables:")
        for name in sorted(matching_modules):
            print(f"- {name}")
        print("")

    if matching_functions:
        print("Matching functions:")
        for name in sorted(matching_functions):
            print(f"- {name}")
        print("")

    if not matches:
        return

    print("Context matches:")
    shown = 0
    for idx in matches:
        if shown >= args.limit:
            break
        start = max(idx - args.context_before, 0)
        end = min(idx + args.context_after + 1, len(lines))
        print("-")
        for line_no in range(start, end):
            prefix = ">" if line_no == idx else " "
            print(f"{prefix} {line_no + 1:>6}: {lines[line_no]}")
        shown += 1

    if len(matches) > args.limit:
        print("")
        print(f"... {len(matches) - args.limit} more matches not shown (refine search).")


if __name__ == "__main__":
    main()
