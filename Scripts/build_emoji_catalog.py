#!/usr/bin/env python3
"""Generate the compact offline emoji catalog from Unicode emoji-test.txt.gz."""
from pathlib import Path
import gzip
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Docs/Unicode/emoji-test-18.0.txt.gz"
OUTPUT = ROOT / "Core/Sources/KeyboardCore/Resources/emoji_catalog.tsv"
MANIFEST = ROOT / "Core/Sources/KeyboardCore/Resources/emoji_catalog-manifest.json"

GROUPS = {
    "Smileys & Emotion": "smileys",
    "People & Body": "people",
    "Animals & Nature": "animals",
    "Food & Drink": "food",
    "Travel & Places": "travel",
    "Activities": "activities",
    "Objects": "objects",
    "Symbols": "symbols",
    "Flags": "flags",
    "Component": "components",
}
VERSION = "18.0"
ENTRY = re.compile(r"^\s*(.*?)\s*;\s*(fully-qualified|component)\s*#\s*\S+\s+E[0-9.]+\s+(.+?)\s*$")


def main() -> None:
    source = gzip.decompress(SOURCE.read_bytes()).decode("utf-8")
    if not re.search(rf"^# Version: {re.escape(VERSION)}$", source, re.MULTILINE):
        raise SystemExit(f"Expected Unicode Emoji {VERSION} data in {SOURCE}")

    group = ""
    rows: list[str] = []
    seen: set[str] = set()
    counts: dict[str, int] = {}
    for line in source.splitlines():
        if line.startswith("# group: "):
            group = line.removeprefix("# group: ").strip()
            continue
        match = ENTRY.match(line)
        if not match:
            continue
        category = GROUPS.get(group)
        if category is None:
            continue
        codepoints, _status, name = match.groups()
        emoji = "".join(chr(int(codepoint, 16)) for codepoint in codepoints.split())
        if emoji in seen:
            raise SystemExit(f"Duplicate RGI emoji sequence: {emoji}")
        if "\t" in name or "\n" in name:
            raise SystemExit(f"Unexpected control character in emoji name: {name!r}")
        seen.add(emoji)
        rows.append(f"{category}\t{emoji}\t{name}")
        counts[category] = counts.get(category, 0) + 1

    if len(rows) < 3900:
        raise SystemExit(f"Unicode catalog unexpectedly small: {len(rows)}")
    payload = (f"# Unicode Emoji {VERSION}; RGI fully-qualified sequences and components\n" + "\n".join(rows) + "\n").encode("utf-8")
    OUTPUT.write_bytes(payload)
    component_count = counts.get("components", 0)
    manifest = {
        "unicodeVersion": VERSION,
        "emojiCount": len(rows),
        "fullyQualifiedCount": len(rows) - component_count,
        "componentCount": component_count,
        "sha256": hashlib.sha256(payload).hexdigest(),
        "categories": counts,
    }
    MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Unicode Emoji {VERSION}: {len(rows)} sequences in {len(counts)} categories")


if __name__ == "__main__":
    main()
