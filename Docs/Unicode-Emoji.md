# Emoji catalog

GlassType bundles a local emoji selection catalog generated from Unicode Emoji
18.0 `emoji-test.txt` (dated 2026-04-30). It contains all 3,963
fully-qualified entries plus the nine standalone emoji components, grouped into
ten scrollable categories. No catalog request is made at runtime.

The compressed source data is stored at
[`Docs/Unicode/emoji-test-18.0.txt.gz`](Unicode/emoji-test-18.0.txt.gz). It is
Copyright © 2026 Unicode, Inc.; Unicode and the Unicode Logo are registered
trademarks. The source file includes the Unicode Terms of Use and license URL:
<https://www.unicode.org/terms_of_use.html>. Unicode's emoji-test data defines
the standard sequences and labels; it does not provide glyph artwork.

Regenerate the bundled TSV and manifest after changing the pinned source with:

```sh
python3 Scripts/build_emoji_catalog.py
```

The generator verifies the source version, rejects duplicate sequences, and
writes `Core/Sources/KeyboardCore/Resources/emoji_catalog.tsv` plus a manifest
with counts and a SHA-256 checksum. Tests check the count, category order,
unique sequences, and representative ZWJ, modifier, flag, and recent entries.

UIKit does not expose an API for enumerating the private emoji keyboard database
or checking each sequence's font coverage. The bundled catalog therefore
tracks Unicode Emoji 18.0, while the appearance of newly standardized glyphs
depends on the emoji font in the installed iOS version. The UI displays
Unicode's names for VoiceOver, uses a horizontally scrollable category strip,
and loads only visible grid cells.
