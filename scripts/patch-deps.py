#!/usr/bin/env python3
"""Strip `#Preview { ... }` blocks from SwiftPM dependency checkouts.

Command Line Tools ship the SwiftUI and Observation macro plugins but not the
`PreviewsMacros` plugin that backs Xcode's `#Preview` payload. Any dependency
that ships preview payloads in its library sources therefore fails to compile
on a CLT-only machine. Removing the preview declarations changes no library
behaviour: they are compile-time-only, never referenced by library code.

Idempotent: rerunning it on already patched sources is a no-op.
"""
from __future__ import annotations

import pathlib
import sys

CHECKOUTS = pathlib.Path(__file__).resolve().parent.parent / ".build" / "checkouts"


def strip_previews(source: str) -> str:
    lines = source.splitlines(keepends=True)
    output: list[str] = []
    index = 0
    while index < len(lines):
        line = lines[index]
        if line.lstrip().startswith("#Preview"):
            # Skip the attribute name, optional trailing closure, and any
            # chained modifiers until braces balance and the line ends.
            depth = 0
            seen_brace = False
            while index < len(lines):
                current = lines[index]
                depth += current.count("{") - current.count("}")
                if "{" in current:
                    seen_brace = True
                index += 1
                if seen_brace and depth <= 0:
                    break
            continue
        output.append(line)
        index += 1
    return "".join(output)


def main() -> int:
    if not CHECKOUTS.is_dir():
        print(f"no checkouts at {CHECKOUTS}", file=sys.stderr)
        return 0
    patched = 0
    for path in sorted(CHECKOUTS.rglob("*.swift")):
        source = path.read_text(encoding="utf-8", errors="surrogateescape")
        if "#Preview" not in source:
            continue
        # SwiftPM checkouts are read-only (git index mode); make the file
        # writable before rewriting it.
        path.chmod(0o644)
        path.write_text(strip_previews(source), encoding="utf-8", errors="surrogateescape")
        patched += 1
        print(f"patched {path.relative_to(CHECKOUTS.parent.parent)}")
    print(f"{patched} file(s) patched")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
