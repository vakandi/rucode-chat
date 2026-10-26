#!/usr/bin/env python3
"""Stage the macOS sources for the Command-Line-Tools SwiftPM build.

Xcode's `#Preview` payloads need the `PreviewsMacros` plugin, which only ships
inside Xcode. A CLT-only compiler cannot expand them, so the staged copy has
those declarations removed. Preview blocks are compile-time-only and never
referenced by library code, so behaviour is unchanged; the original sources
keep their previews for the Xcode project.

iOS-only sources are skipped: the CLT SDK has no UIKit, and this manifest only
builds the macOS target.

Usage: python3 scripts/stage-sources.py
"""
from __future__ import annotations

import pathlib
import shutil
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "Enchanted"
STAGE = ROOT / "build" / "generated-sources" / "RuCodeChat"

SKIP_DIRS = {"UI/iOS"}
SKIP_FILES = {
    "Info.plist",
    "Enchanted.entitlements",
    "EnchantedDebug.entitlements",
    "Accessibility.plist",
    "Assets.xcassets",
    "Preview Content",
}


def strip_previews(source: str) -> str:
    lines = source.splitlines(keepends=True)
    output: list[str] = []
    index = 0
    while index < len(lines):
        line = lines[index]
        if line.lstrip().startswith("#Preview"):
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
    if not SOURCE.is_dir():
        print(f"missing sources: {SOURCE}", file=sys.stderr)
        return 1
    if STAGE.exists():
        shutil.rmtree(STAGE)
    STAGE.mkdir(parents=True)

    staged = 0
    stripped = 0
    for path in sorted(SOURCE.rglob("*.swift")):
        relative = path.relative_to(SOURCE)
        if any(part in SKIP_DIRS for part in relative.parts):
            continue
        if any(part in SKIP_FILES for part in relative.parts):
            continue
        text = path.read_text(encoding="utf-8")
        patched = strip_previews(text)
        if patched != text:
            stripped += 1
        destination = STAGE / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(patched, encoding="utf-8")
        staged += 1

    print(f"staged {staged} Swift file(s), stripped previews from {stripped}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
