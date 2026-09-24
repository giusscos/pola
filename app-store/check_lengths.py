#!/usr/bin/env python3
"""Checks App Store Connect field limits for every language file of a release.

Usage: python3 app-store/check_lengths.py app-store/1.1.0
"""
import re
import sys
from pathlib import Path

CHAR_LIMITS = {"App Name": 30, "Subtitle": 30, "Promotional Text": 170, "Description": 4000, "What's New": 4000}
KEYWORD_BYTES = 100
HEADLINE_MAX, SUBLINE_MAX = 31, 45   # our own screenshot layout limits, not Apple's
IAP_NAME_MAX, IAP_DESC_MAX = 30, 45


def blocks(section: str) -> list[str]:
    return [b.strip("\n") for b in re.findall(r"```\n(.*?)```", section, re.S)]


def check(path: Path) -> list[str]:
    text = path.read_text()
    sections = dict(re.findall(r"^## ([^\n*]+?)\s*(?:\*\([^)]*\)\*)?\n(.*?)(?=^## |\Z)", text, re.S | re.M))
    problems = []

    for field, limit in CHAR_LIMITS.items():
        for value in blocks(sections.get(field, "")):
            if len(value) > limit:
                problems.append(f"{field}: {len(value)}/{limit} chars")

    for value in blocks(sections.get("Keywords", "")):
        size = len(value.encode("utf-8"))
        if size > KEYWORD_BYTES:
            problems.append(f"Keywords: {size}/{KEYWORD_BYTES} bytes")
        if ", " in value:
            problems.append("Keywords: remove spaces after commas")
        words = value.split(",")
        if len(words) != len(set(words)):
            problems.append("Keywords: duplicates")
        indexed = " ".join(blocks(sections.get("App Name", "")) + blocks(sections.get("Subtitle", ""))).lower()
        repeated = [w for w in words if re.search(rf"\b{re.escape(w)}\b", indexed)]
        if repeated:
            problems.append(f"Keywords: already in name/subtitle: {repeated}")

    for row in re.findall(r"^\| \d+ \| (.*?) \| (.*?) \|$", sections.get("Screenshot captions", ""), re.M):
        headline, subline = row
        if len(headline) > HEADLINE_MAX:
            problems.append(f"Screenshot headline too long ({len(headline)}): {headline}")
        if len(subline) > SUBLINE_MAX:
            problems.append(f"Screenshot subline too long ({len(subline)}): {subline}")

    for label, value in re.findall(r"^\| (.*?) \| (.*?) \|$", sections.get("In-App Purchases", ""), re.M):
        limit = IAP_NAME_MAX if "display name" in label else IAP_DESC_MAX if "description" in label else None
        if limit and len(value) > limit:
            problems.append(f"IAP {label}: {len(value)}/{limit} chars")

    # Other companies' trademarks in metadata risk rejection (App Review 2.3.7 / 5.2.1).
    for banned in ("Polaroid", "Instax", "Fujifilm", "Kodak", "Ektar", "SX-70"):
        if re.search(rf"\b{banned}\b", text, re.I):
            problems.append(f"Third-party trademark in copy: {banned}")
    return problems


def main() -> int:
    release = Path(sys.argv[1] if len(sys.argv) > 1 else "app-store/1.1.0")
    failed = False
    for path in sorted(release.glob("*.md")):
        if path.name == "README.md":
            continue
        problems = check(path)
        print(f"{path.name}: {'OK' if not problems else ''}")
        for p in problems:
            print(f"  - {p}")
        failed |= bool(problems)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
