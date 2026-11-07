#!/usr/bin/env python3
"""Package every project input, including SPM data/licences and new UIKit files."""
from pathlib import Path
import zipfile

root = Path(__file__).resolve().parents[1]
files = []
for folder in ["App", "Keyboard", "Shared", "Core", "GlassType.xcodeproj", "Docs", "Scripts"]:
    for path in (root / folder).rglob("*"):
        if path.is_file() and not any(p in {".build", "build", "__pycache__", ".swiftpm", "xcuserdata"} for p in path.parts):
            files.append(path)
files += [root / "README.md", root / "LICENSE", root / ".gitignore"]
destination = root.parent / "GlassType-1.1-update.zip"
with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
    for path in sorted(files):
        item = zipfile.ZipInfo(str(path.relative_to(root)), date_time=(2026, 11, 7, 0, 0, 0))
        item.compress_type = zipfile.ZIP_DEFLATED
        item.external_attr = (0o100644 << 16)
        archive.writestr(item, path.read_bytes())
print(f"{destination}: {len(files)} files, {destination.stat().st_size} bytes")
