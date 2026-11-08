#!/usr/bin/env python3
"""Compile newline-delimited lexicons into six-byte UTF-8 byte tries."""
from __future__ import annotations

import argparse
import pathlib
import struct
import unicodedata


ROOT = pathlib.Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "Core/Sources/KeyboardCore/Resources"
NODE_SIZE = 6
IS_TERMINAL = 0x01
HAS_SIBLING = 0x02


class Node:
    __slots__ = ("byte", "terminal", "children")

    def __init__(self, byte: int = 0) -> None:
        self.byte = byte
        self.terminal = False
        self.children: dict[int, Node] = {}


def compile_file(source: pathlib.Path, destination: pathlib.Path, check: bool = False) -> tuple[int, int, int]:
    root = Node()
    words = 0
    for line in source.read_text(encoding="utf-8").splitlines():
        value = line.split("\t", 1)[0].strip()
        if not value:
            continue
        word = unicodedata.normalize("NFC", value.lower())
        node = root
        for byte in word.encode("utf-8"):
            node = node.children.setdefault(byte, Node(byte))
        if not node.terminal:
            words += 1
            node.terminal = True

    output = bytearray(NODE_SIZE)  # sentinel root; byte 0 is reserved

    def write_group(siblings: list[Node]) -> int:
        if not siblings:
            return 0
        start = len(output)
        output.extend(b"\0" * (NODE_SIZE * len(siblings)))
        for index, node in enumerate(siblings):
            offset = start + NODE_SIZE * index
            output[offset] = node.byte
            flags = (IS_TERMINAL if node.terminal else 0) | (HAS_SIBLING if index + 1 < len(siblings) else 0)
            output[offset + 1] = flags
        for index, node in enumerate(siblings):
            if node.children:
                offset = start + NODE_SIZE * index
                child_offset = write_group([node.children[key] for key in sorted(node.children)])
                struct.pack_into("<I", output, offset + 2, child_offset)
        return start

    child_offset = write_group([root.children[key] for key in sorted(root.children)])
    struct.pack_into("<I", output, 2, child_offset)
    if len(output) > 0xFFFFFFFF:
        raise ValueError(f"Trie exceeds UInt32 offset space: {source}")
    if check:
        if not destination.is_file() or destination.read_bytes() != output:
            raise SystemExit(f"Out of date binary trie: {destination}")
    else:
        destination.write_bytes(output)
    return words, (len(output) - NODE_SIZE) // NODE_SIZE, len(output)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--resources", type=pathlib.Path, default=RESOURCES)
    parser.add_argument("--check", action="store_true", help="fail if generated tries differ from checked-in resources")
    args = parser.parse_args()
    total_source = total_output = 0
    for language in ("en", "ru", "uk"):
        source = args.resources / f"lexicon_{language}.txt"
        destination = args.resources / f"lexicon_{language}.trie"
        words, nodes, size = compile_file(source, destination, check=args.check)
        source_size = source.stat().st_size
        total_source += source_size
        total_output += size
        ratio = size / source_size if source_size else 0
        print(f"{language}: {words:,} words, {nodes:,} nodes, {source_size:,} -> {size:,} bytes ({ratio:.1%})")
    print(f"total: {total_source:,} -> {total_output:,} bytes ({total_output / total_source:.1%})")


if __name__ == "__main__":
    main()
