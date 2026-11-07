#!/usr/bin/env python3
"""Check the unsigned SideStore IPA's app/extension structure and metadata."""
import argparse
import plistlib
import zipfile

parser = argparse.ArgumentParser()
parser.add_argument("ipa")
parser.add_argument("--app-bundle-id", required=True)
parser.add_argument("--extension-bundle-id", required=True)
parser.add_argument("--version", required=True)
parser.add_argument("--build", required=True)
args = parser.parse_args()

app_root = "Payload/GlassType.app/"
app_plist = app_root + "Info.plist"
extension_root = app_root + "PlugIns/GlassTypeKeyboard.appex/"
extension_plist = extension_root + "Info.plist"
with zipfile.ZipFile(args.ipa) as archive:
    names = set(archive.namelist())
    if app_plist not in names or extension_plist not in names:
        raise SystemExit("IPA is missing the app or embedded Keyboard Extension")
    app = plistlib.loads(archive.read(app_plist))
    extension = plistlib.loads(archive.read(extension_plist))
    if app.get("CFBundleIdentifier") != args.app_bundle_id:
        raise SystemExit("Unexpected app bundle identifier")
    if extension.get("CFBundleIdentifier") != args.extension_bundle_id:
        raise SystemExit("Unexpected Keyboard Extension bundle identifier")
    for label, info in (("app", app), ("extension", extension)):
        if info.get("CFBundleShortVersionString") != args.version:
            raise SystemExit(f"{label} version does not match the selected build version")
        if info.get("CFBundleVersion") != args.build:
            raise SystemExit(f"{label} build number does not match the selected build")
    if extension.get("NSExtension", {}).get("NSExtensionPointIdentifier") != "com.apple.keyboard-service":
        raise SystemExit("Embedded extension is not registered as an iOS keyboard")
    icon_assets = [name for name in names if name.startswith(app_root) and name.endswith("Assets.car")]
    if not icon_assets:
        raise SystemExit("Compiled app asset catalog is missing")
    for language in ("en", "ru", "uk"):
        if not any(name.endswith(f"lexicon_{language}.txt") for name in names):
            raise SystemExit(f"Bundled {language} dictionary is missing from the IPA")
print(f"IPA verified: {args.app_bundle_id} + {args.extension_bundle_id}, v{args.version} ({args.build})")
