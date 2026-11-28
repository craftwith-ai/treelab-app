#!/usr/bin/env python3
"""Checks that every Treelab text is translated in every language the app ships.

The languages are those of the app's main catalogue (Resources/Localizable.xcstrings). Checked keys:
- every key of the Treelab catalogue(s) given with --catalog (default: the TreelabLanesUI catalogue);
- with --new-since <rev>, the keys of Resources/Localizable.xcstrings that did not exist at <rev>
  (upstream's own gaps stay out: they are not Treelab's texts).
A key counts as translated in a language when it has a non-empty stringUnit there, or plural or
device variations whose every stringUnit is non-empty. French values must use "tu": a "vous",
"votre" or "vos" word in a French value is reported. French spacing: a value inserted after a word is
joined by a normal no-break space (U+00A0), never a narrow one (U+202F reads "de14"; it stays right
inside « »), and an inserted number keeps its unit on its line (no plain space after "%lld").

Usage: scripts/treelab/check-langs.py [--catalog PATH]... [--new-since REV]
Prints MISSING=<n> FRENCH_VOUS=<n> FRENCH_SPACE=<n> LANGUAGES=<n> KEYS=<n>, one line per problem; exits 1 on any.
"""
import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MAIN = ROOT / "Resources/Localizable.xcstrings"
DEFAULT = ROOT / "Packages/macOS/TreelabLanes/Sources/TreelabLanesUI/Resources/Localizable.xcstrings"
VOUS = re.compile(r"\b(vous|votre|vos)\b", re.IGNORECASE)
# A narrow no-break space before an inserted value (not right after «), or a breakable space after a number.
FRENCH_SPACE = re.compile(r"(?<!«)\u202f%|%(?:\d+\$)?lld [^\W\d]")


def units(node):
    """Every stringUnit value under a localization node (plain, plural or device variations)."""
    if not isinstance(node, dict):
        return []
    found = []
    unit = node.get("stringUnit")
    if isinstance(unit, dict):
        found.append(unit.get("value") or "")
    for variants in (node.get("variations") or {}).values():
        for child in (variants or {}).values():
            found.extend(units(child))
    return found


def translated(node):
    values = units(node)
    return bool(values) and all(v.strip() for v in values)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--catalog", action="append", type=Path)
    parser.add_argument("--new-since")
    args = parser.parse_args()

    main_catalog = json.loads(MAIN.read_text())
    languages = sorted({lang for entry in main_catalog["strings"].values()
                        for lang in (entry.get("localizations") or {})})
    checked = []  # (catalog name, key, entry)
    for path in args.catalog or [DEFAULT]:
        for key, entry in json.loads(path.read_text())["strings"].items():
            if entry.get("shouldTranslate") is False:
                continue
            checked.append((path.name if path != DEFAULT else "TreelabLanesUI", key, entry))
    if args.new_since:
        old = subprocess.run(["git", "-C", str(ROOT), "show", f"{args.new_since}:Resources/Localizable.xcstrings"],
                             check=True, capture_output=True, text=True).stdout
        old_keys = set(json.loads(old)["strings"])
        for key, entry in main_catalog["strings"].items():
            if key not in old_keys and entry.get("shouldTranslate") is not False:
                checked.append(("Resources", key, entry))

    missing = vous = spacing = 0
    for catalog, key, entry in checked:
        locs = entry.get("localizations") or {}
        absent = [lang for lang in languages if not translated(locs.get(lang))]
        if absent:
            missing += len(absent)
            print(f"missing {catalog} {key!r}: {' '.join(absent)}")
        for value in units(locs.get("fr")):
            if VOUS.search(value):
                vous += 1
                print(f"vous {catalog} {key!r}: {value!r}")
            if FRENCH_SPACE.search(value):
                spacing += 1
                print(f"french-space {catalog} {key!r}: {value!r}")
    print(f"MISSING={missing} FRENCH_VOUS={vous} FRENCH_SPACE={spacing} LANGUAGES={len(languages)} KEYS={len(checked)}")
    return 1 if missing or vous or spacing else 0


if __name__ == "__main__":
    sys.exit(main())
