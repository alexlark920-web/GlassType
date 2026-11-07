#!/usr/bin/env python3
"""Validate a SideStore source using the official JSON Schema plus invariants."""
import argparse
import json
from pathlib import Path
import sys

parser = argparse.ArgumentParser()
parser.add_argument("source", type=Path)
parser.add_argument("schema", type=Path)
args = parser.parse_args()
try:
    import jsonschema
except ImportError as error:
    raise SystemExit("Install CI validator with: python3 -m pip install jsonschema") from error

source = json.loads(args.source.read_text(encoding="utf-8"))
schema = json.loads(args.schema.read_text(encoding="utf-8"))
jsonschema.validate(instance=source, schema=schema)
if not source.get("apps"):
    raise SystemExit("AltSource must contain the GlassType app")
app = source["apps"][0]
if app.get("bundleIdentifier") != "org.opentype.GlassType":
    raise SystemExit("AltSource bundle identifier does not match GlassType")
for obsolete in ("versionDate", "versionDescription", "version", "size", "downloadURL"):
    if obsolete in app:
        raise SystemExit(f"Deprecated app-level field is not allowed: {obsolete}")
versions = app.get("versions", [])
if not versions:
    raise SystemExit("AltSource has no release versions")
if any("buildVersion" in item for item in versions):
    raise SystemExit("Unsupported buildVersion field found")
dates = [item["date"] for item in versions]
if dates != sorted(dates, reverse=True):
    raise SystemExit("Version history must be in reverse chronological order")
if any(type(item.get("size")) is not int or item["size"] <= 0 for item in versions):
    raise SystemExit("Every version must contain a positive IPA byte size")
print(f"Valid SideStore source: {source['identifier']} ({len(versions)} versions)")
