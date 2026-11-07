#!/usr/bin/env python3
"""Reproduce bundled data from the named upstream files, never from user input.

Usage: PYTHONPATH=<spylls 0.1.7> python3 Scripts/build_lexicons.py SOURCE_DIRECTORY
Download the five sources named in SOURCE_HASHES and license texts first.
spylls is a build-time validator only; the iOS app has no Python dependencies.
"""
import hashlib
import json
from pathlib import Path
import re
import sys

SOURCE_HASHES = {
    "en_50k.txt": "bbf5fa991058ff642732784b31af023f66462e1d",
    "ru_50k.txt": "fa4412020b6409b90a45c1278d07e98812b544e2",
    "uk_50k.txt": "b5c607e7fe06c4ea1f3456a1a41f35f005b0a236",
    "uk_UA.dic": "ff848bbb610332bec2fa867f91d7489154c3585d",
    "uk_UA.aff": "2a604054953b9997b1b7250427fb244736a1c66b",
}

def normalize(word):
    return word.lower().translate(str.maketrans({"’": "'", "ʼ": "'", "‘": "'", "‑": "-"}))

def main():
    from spylls.hunspell import Dictionary
    source = Path(sys.argv[1])
    output = Path(__file__).resolve().parents[1] / "Core/Sources/KeyboardCore/Resources"
    output.mkdir(parents=True, exist_ok=True)
    for name, expected in SOURCE_HASHES.items():
        data = (source / name).read_bytes()
        actual = hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()
        if actual != expected:
            raise ValueError(f"Source changed: {name}: {actual} != {expected}")
    supplements = json.loads(Path(__file__).with_name("lexicon_supplements.json").read_text())
    uk_dictionary = Dictionary.from_files(str(source / "uk_UA"))
    manifest = {"version": 1, "sources_git_blob_sha1": SOURCE_HASHES, "languages": {}}
    for language, alphabet in [("en", "a-z"), ("ru", "а-яё"), ("uk", "а-щьюяєіїґ")]:
        pattern = re.compile("[" + alphabet + "]+(?:['-][" + alphabet + "]+)*")
        words, seen = [], set()
        for line in (source / (language + "_50k.txt")).read_text().splitlines():
            word = normalize(line.rsplit(" ", 1)[0])
            if not (2 <= len(word) <= 24 and pattern.fullmatch(word) and word not in seen):
                continue
            if language == "uk" and not uk_dictionary.lookup(word):
                continue
            words.append(word); seen.add(word)
            if len(words) == 30000:
                break
        extras = [normalize(word) for word in supplements[language] if normalize(word) not in seen]
        assert all(pattern.fullmatch(word) and 2 <= len(word) <= 24 for word in extras)
        # Preserve the corpus ranks; explicitly reviewed modern terms extend it.
        words.extend(dict.fromkeys(extras))
        data = ("\n".join(words) + "\n").encode()
        (output / ("lexicon_" + language + ".txt")).write_bytes(data)
        manifest["languages"][language] = {"words": len(words), "supplemental": len(extras), "sha256": hashlib.sha256(data).hexdigest()}
        print(language, len(words), len(data))
    for name in ["CC-BY-SA-4.0.txt", "MPL-1.1.txt", "README_uk_UA.txt"]:
        (output / name).write_bytes((source / name).read_bytes())
    (output / "lexicon-manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")

if __name__ == "__main__":
    main()
