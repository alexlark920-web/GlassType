#!/usr/bin/env python3
"""Set CI-only bundle versions for a beta run or a vX.Y.Z stable tag."""
import argparse
import plistlib
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--channel", choices=("beta", "stable"), required=True)
parser.add_argument("--run-number", type=int, required=True)
parser.add_argument("--ref", required=True)
args = parser.parse_args()

if args.channel == "stable":
    match = re.fullmatch(r"refs/tags/v(\d+\.\d+\.\d+)", args.ref)
    if not match:
        raise SystemExit("Stable builds must run from a vX.Y.Z tag")
    version = match.group(1)
else:
    if not args.ref.startswith("refs/heads/"):
        raise SystemExit("Beta builds must run from a branch")
    info = plistlib.loads((ROOT / "App/Info.plist").read_bytes())
    components = info["CFBundleShortVersionString"].split(".")
    if len(components) == 1:
        components.append("0")
    version = ".".join(components[:2] + [str(args.run_number)])

build = str(args.run_number)
for relative in ("App/Info.plist", "Keyboard/Info.plist"):
    path = ROOT / relative
    info = plistlib.loads(path.read_bytes())
    info["CFBundleShortVersionString"] = version
    info["CFBundleVersion"] = build
    with path.open("wb") as output:
        plistlib.dump(info, output, sort_keys=False)
print(f"version={version}\nbuild={build}")
