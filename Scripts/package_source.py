#!/usr/bin/env python3
"""Build a reproducible, version-named archive of the canonical project sources."""
from pathlib import Path
import plistlib
import zipfile

root = Path(__file__).resolve().parents[1]
app = plistlib.loads((root / "App/Info.plist").read_bytes())
keyboard = plistlib.loads((root / "Keyboard/Info.plist").read_bytes())
version = app["CFBundleShortVersionString"]
build = app["CFBundleVersion"]
if (version, build) != (keyboard["CFBundleShortVersionString"], keyboard["CFBundleVersion"]):
    raise SystemExit("App and keyboard extension versions do not match")

files = []
folders = ["App", "Keyboard", "Shared", "Core", "GlassType.xcodeproj", "Docs", "Scripts", ".github"]
ignored = {".build", "build", "__pycache__", ".swiftpm", "xcuserdata"}
for folder in folders:
    for path in (root / folder).rglob("*"):
        if path.is_file() and not any(part in ignored for part in path.parts):
            files.append(path)
files.extend(root / name for name in ["README.md", "LICENSE", ".gitignore"] if (root / name).is_file())

destination = root / "build" / f"GlassType-source-v{version}-build{build}.zip"
destination.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
    for path in sorted(set(files)):
        item = zipfile.ZipInfo(str(path.relative_to(root)), date_time=(2026, 11, 7, 0, 0, 0))
        item.compress_type = zipfile.ZIP_DEFLATED
        item.external_attr = 0o100644 << 16
        archive.writestr(item, path.read_bytes())
print(f"{destination}: {len(set(files))} files, {destination.stat().st_size} bytes")
