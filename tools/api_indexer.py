#!/usr/bin/env python3
"""Generate compact BeamNG API indexes from the TXT dump."""

from __future__ import annotations

from pathlib import Path
import re

RAW_DUMP = Path("docs/beamng-api/raw/api_dump_0.38.txt")
INDEX_MODULES = Path("docs/beamng-api/index/index_modules.md")
INDEX_FUNCTIONS = Path("docs/beamng-api/index/index_functions.md")


def parse_dump(lines: list[str]) -> dict[str, dict[str, set[str]]]:
    modules: dict[str, dict[str, set[str]]] = {}
    current: str | None = None
    in_functions = False

    for raw_line in lines:
        line = raw_line.rstrip("\n")
        if not line:
            continue

        if line.startswith(" "):
            if current is None:
                continue

            if line.startswith("  functions:"):
                in_functions = True
                continue

            if in_functions:
                if not line.startswith("    "):
                    in_functions = False
                else:
                    name = line.strip()
                    if name and not name.endswith(":") and not name.startswith("("):
                        modules[current]["functions"].add(name)
                continue

            if line.startswith("  ") and ":" in line:
                field_name = line.strip().split(":", 1)[0]
                if field_name != "functions":
                    modules[current]["fields"].add(field_name)
            continue

        in_functions = False
        match = re.match(r"^(\S+):\s+(\S+)", line)
        if match:
            current = match.group(1)
            modules.setdefault(current, {"functions": set(), "fields": set()})
        else:
            current = None

    return modules


def render_index_modules(modules: dict[str, dict[str, set[str]]]) -> str:
    lines: list[str] = [
        "# Module Index",
        "",
        "Generated from `docs/beamng-api/raw/api_dump_0.38.txt`.",
        "",
    ]

    for module in sorted(modules.keys()):
        functions = sorted(modules[module]["functions"])
        fields = sorted(modules[module]["fields"])
        lines.extend(
            [
                f"## {module}",
                "",
                "Description: _Unknown (from dump)_",
                f"Functions: {len(functions)}",
                f"Fields: {len(fields)}",
                "",
            ]
        )

        if functions:
            lines.append("Top functions:")
            for fn in functions[:20]:
                lines.append(f"- {fn}")
            if len(functions) > 20:
                lines.append(f"- ...and {len(functions) - 20} more (see index_functions)")
            lines.append("")

    return "\n".join(lines).rstrip() + "\n"


def render_index_functions(modules: dict[str, dict[str, set[str]]]) -> str:
    lines: list[str] = [
        "# Function Index",
        "",
        "One entry per function, generated from `docs/beamng-api/raw/api_dump_0.38.txt`.",
        "",
    ]

    for module in sorted(modules.keys()):
        functions = sorted(modules[module]["functions"])
        for fn in functions:
            if module == "_G":
                entry = fn
            else:
                if ":" in fn or "." in fn:
                    if fn.startswith(f"{module}:") or fn.startswith(f"{module}."):
                        entry = fn
                    else:
                        entry = f"{module}.{fn}"
                else:
                    entry = f"{module}.{fn}"
            lines.append(entry)

    return "\n".join(lines).rstrip() + "\n"


def main() -> None:
    if not RAW_DUMP.exists():
        raise SystemExit(f"Missing dump: {RAW_DUMP}")

    lines = RAW_DUMP.read_text(encoding="utf-8", errors="replace").splitlines()
    modules = parse_dump(lines)

    INDEX_MODULES.write_text(render_index_modules(modules), encoding="utf-8")
    INDEX_FUNCTIONS.write_text(render_index_functions(modules), encoding="utf-8")


if __name__ == "__main__":
    main()
