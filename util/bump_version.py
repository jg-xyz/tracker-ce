#!/usr/bin/env python3
"""Bump firmware versions in version.mk.

usage: bump_version.py {patch|minor|major} {ALL|ORIGINAL|PLUS|MINI}

minor resets patch to 0; major resets minor and patch to 0.
"""
import re
import sys
from pathlib import Path

KINDS = ["MAJOR", "MINOR", "PATCH"]
ALL = ["ORIGINAL", "PLUS", "MINI"]


def main() -> int:
    if len(sys.argv) != 3 or sys.argv[1].upper() not in KINDS:
        print(__doc__)
        return 2
    kind = sys.argv[1].upper()
    target = sys.argv[2].upper()
    targets = ALL if target in ("ALL", "") else [target]
    if any(t not in ALL for t in targets):
        print(f"Unknown TARGET {target}; use ALL, {', '.join(ALL)}")
        return 2

    path = Path(__file__).resolve().parent.parent / "version.mk"
    text = path.read_text()

    def field(t: str, k: str) -> re.Pattern:
        return re.compile(rf"^({t}_VER_{k}\s*:=\s*)(\d+)", re.M)

    for t in targets:
        m = field(t, kind).search(text)
        if not m:
            print(f"{t}_VER_{kind} not found in version.mk")
            return 1
        text = field(t, kind).sub(lambda mm: f"{mm.group(1)}{int(mm.group(2)) + 1}", text, count=1)
        for lower in KINDS[KINDS.index(kind) + 1:]:
            text = field(t, lower).sub(lambda mm: f"{mm.group(1)}0", text, count=1)

    path.write_text(text)
    print(f"Bumped {kind.lower()} version for {targets}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
