#!/usr/bin/env python3
"""Add a verified IPA release to a SideStore source without copying sources."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import urllib.parse
import zipfile
import plistlib

parser = argparse.ArgumentParser()
parser.add_argument("--distribution", type=Path, required=True)
parser.add_argument("--repository", required=True, help="owner/repository")
parser.add_argument("--channel", choices=("beta", "stable"), required=True)
parser.add_argument("--tag", required=True)
parser.add_argument("--ipa", type=Path, required=True)
parser.add_argument("--date", required=True)
parser.add_argument("--description", required=True)
args = parser.parse_args()

if "/" not in args.repository or any(c.isspace() for c in args.repository):
    raise SystemExit("DISTRIBUTION_REPOSITORY must be owner/repository")
if args.channel == "stable" and not args.tag.startswith("v"):
    raise SystemExit("Stable release tag must be vX.Y.Z")

with zipfile.ZipFile(args.ipa) as archive:
    info = plistlib.loads(archive.read("Payload/GlassType.app/Info.plist"))
    ext_info = plistlib.loads(archive.read("Payload/GlassType.app/PlugIns/GlassTypeKeyboard.appex/Info.plist"))
if info["CFBundleIdentifier"] != "org.opentype.GlassType":
    raise SystemExit("IPA does not contain the expected GlassType app")
if ext_info["CFBundleIdentifier"] != "org.opentype.GlassType.Keyboard":
    raise SystemExit("IPA does not contain the expected keyboard extension")
version = info["CFBundleShortVersionString"]
if args.channel == "stable" and args.tag != "v" + version:
    raise SystemExit("Stable tag and IPA version differ")

repo_url = f"https://github.com/{args.repository}"
asset_name = args.ipa.name
download_url = f"{repo_url}/releases/download/{urllib.parse.quote(args.tag, safe='')}/{urllib.parse.quote(asset_name)}"
icon_url = f"https://raw.githubusercontent.com/{args.repository}/main/assets/icon.png"
source_url = f"https://raw.githubusercontent.com/{args.repository}/main/sources/{args.channel}.json"
date = datetime.fromisoformat(args.date.replace("Z", "+00:00")).astimezone(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
version_entry = {
    "version": version,
    "date": date,
    "downloadURL": download_url,
    "size": args.ipa.stat().st_size,
    "localizedDescription": args.description.strip() or f"GlassType {version}",
}

root = args.distribution
source_path = root / "sources" / f"{args.channel}.json"
source_path.parent.mkdir(parents=True, exist_ok=True)
if source_path.exists():
    source = json.loads(source_path.read_text(encoding="utf-8"))
    if source.get("identifier") != f"org.opentype.GlassType.source.{args.channel}":
        raise SystemExit(f"Unexpected source identity in {source_path}")
    app = source["apps"][0]
    if app.get("bundleIdentifier") != info["CFBundleIdentifier"]:
        raise SystemExit("Existing source app identifier does not match IPA")
    if any(item.get("version") == version for item in app.get("versions", [])):
        raise SystemExit(f"Version {version} is already present; refusing to overwrite history")
else:
    app = {
        "name": "GlassType",
        "bundleIdentifier": info["CFBundleIdentifier"],
        "developerName": "GlassType",
        "localizedDescription": "An offline iOS keyboard with English, Russian and Ukrainian layouts, local suggestions, glide typing, emoji search and configurable Liquid Glass styling.",
        "iconURL": icon_url,
        "versions": [],
    }
    source = {
        "name": f"GlassType {args.channel.title()}",
        "identifier": f"org.opentype.GlassType.source.{args.channel}",
        "sourceURL": source_url,
        "apps": [app],
    }

app["versions"].insert(0, version_entry)
app["versions"] = app["versions"][:20]
source_path.write_text(json.dumps(source, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

readme = f"""# GlassType distribution\n\nGlassType is an offline iOS keyboard with English, Russian and Ukrainian layouts. The private development repository is not included here; this public repository contains release artifacts, SideStore metadata and the app icon only.\n\n## Add a source in SideStore\n\n- [Stable source](sidestore://source?url={urllib.parse.quote('https://raw.githubusercontent.com/' + args.repository + '/main/sources/stable.json', safe='')})\n- [Beta source](sidestore://source?url={urllib.parse.quote('https://raw.githubusercontent.com/' + args.repository + '/main/sources/beta.json', safe='')})\n\nIf the link does not open in your installed SideStore version, copy the corresponding raw JSON URL into Sources → Add Source. Install GlassType from the selected source; use Refresh All in My Apps to check for updates. A beta and a stable listing share the same app bundle identifier, so installing both side by side is not supported.\n\n## Notes\n\nThe keyboard requires SideStore to re-sign the unsigned IPA. Installation and refresh still depend on SideStore, the paired device, and Apple free provisioning limits. The IPA being downloadable does not prove that it installs on every iOS version; please report device and iOS details with reproducible issues.\n"""
(root / "README.md").write_text(readme, encoding="utf-8")
print(f"Updated {source_path}; version={version}; size={version_entry['size']}; history={len(app['versions'])}")
