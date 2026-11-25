#!/usr/bin/env python3
"""Puts the brand name in the texts of a built cmux.app, or checks that it is there.

Usage:
  python3 -I scripts/treelab/brand-bundle.py apply --name Treelab <path/to/App.app>
  python3 -I scripts/treelab/brand-bundle.py check <path/to/App.app>

The texts are those of the compiled bundle, in every language and nested bundle: .strings and
.stringsdict (binary, XML in UTF-8 or UTF-16, old-style), the visible keys of each Info.plist,
the names and descriptions of the AppleScript dictionary (.sdef) and the HTML page titles.
Upstream's sources stay untouched: the brand is set on the built copy only.

Each "cmux" is classified with scripts/treelab/brand/rules.json:
  cli       every text of the internal CLI (keys cli.* and *.cli.*),
  gpl       the line that credits cmux by Manaflow under the GPL,
  commande  a command (`code`, a quoted command, "Usage: cmux", "run cmux automation reload"),
  adresse   a web or mail address (cmux.com, support@cmux.com, https://github.com/.../cmux),
  fichier   a technical name glued to other characters (cmux.json, cmux-tui, ~/.cmuxterm, CMUX_*),
and any other one names the app: "apply" replaces it with the brand name, "check" counts it as
unexplained. A key of rules.json "key_overrides" whose text still names cmux takes the override's
text instead (the accent color named "cmux Blue" is the brand's accent, not blue). Format
specifiers are never touched; each file keeps its format and encoding and is written only when
it changes, so a second pass changes nothing.

apply prints "changed: <path>" per rewritten file, then CHANGED_FILES= and REPLACED=.
check prints "CLASS <name>=<count>" per class, UNEXPLAINED=<count> and up to 25 examples;
it exits 1 when one "cmux" is unexplained. Both exit 2 on a usage or read error.
"""

from __future__ import annotations

import argparse
import json
import os
import plistlib
import re
import subprocess
import sys
from collections import Counter
from pathlib import Path

RULES_PATH = Path(__file__).resolve().parent / "brand" / "rules.json"
CLASSES = ("cli", "gpl", "commande", "adresse", "fichier")
ASCII_WORD = re.compile(r"[A-Za-z0-9]")


class Rules:
    def __init__(self, data: dict):
        self.name = data["upstream_name"]
        self.pattern = re.compile(re.escape(self.name), re.IGNORECASE)
        self.cli_keys = [re.compile(p) for p in data["cli_key_patterns"]]
        self.gpl_markers = data["gpl_markers"]
        self.quote_openers = data["quote_openers"]
        self.quote_closers = data["quote_closers"]
        self.usage_prefixes = data["usage_prefixes"]
        self.prose_commands = [
            re.compile(r" " + re.escape(c) + r"(?![A-Za-z0-9-])") for c in data["prose_commands"]
        ]
        self.cli_commands = set(data["cli_commands"])
        self.hyphen_suffixes = re.compile(
            r"-(?:" + "|".join(map(re.escape, data["technical_hyphen_suffixes"])) + r")(?![A-Za-z0-9])"
        )
        self.address_suffix = re.compile(
            r"\.(?:" + "|".join(map(re.escape, data["address_suffixes"])) + r")(?![A-Za-z0-9])"
        )
        self.brand_file_suffix = re.compile(
            r"\.(?:" + "|".join(map(re.escape, data["brand_file_suffixes"])) + r")(?![A-Za-z0-9])"
        )
        self.glued_prefix = set(data["glued_prefix_chars"])
        self.glued_suffix = set(data["glued_suffix_chars"])
        self.info_keys = [re.compile(p) for p in data["info_plist_visible_keys"]]
        self.sdef_attributes = data["sdef_attributes"]
        self.html_elements = data["html_elements"]
        self.key_overrides = data.get("key_overrides", {})

    def override(self, key: str, language: str | None, brand: str) -> str | None:
        """The text a key takes in `language` (a key_overrides entry), or None."""
        entry = self.key_overrides.get(key)
        if not entry:
            return None
        text = entry.get(language or "", entry.get("*"))
        return None if text is None else text.replace("{name}", brand)

    def is_cli_key(self, key: str) -> bool:
        return any(p.search(key) for p in self.cli_keys)

    def classify(self, text: str, start: int, end: int, key: str) -> str | None:
        """The class of the "cmux" at text[start:end], or None when it names the app."""
        if self.is_cli_key(key):
            return "cli"
        if all(marker in text for marker in self.gpl_markers):
            return "gpl"
        before, after = text[:start], text[end:]
        previous = before[-1:] if before else ""
        if before.count("`") % 2 == 1:
            return "commande"
        if previous and previous in self.quote_openers:
            if after[:1] and after[0] in self.quote_closers:
                return "commande"
            word = re.match(r" ([a-z][a-z0-9-]*)", after)
            if word and word.group(1) in self.cli_commands:
                return "commande"
        if any(before.endswith(prefix) for prefix in self.usage_prefixes):
            return "commande"
        if any(p.match(after) for p in self.prose_commands):
            return "commande"
        token_start = max(before.rfind(c) for c in " \n\t") + 1
        token_end = min([i for i in (after.find(" "), after.find("\n")) if i >= 0] or [len(after)])
        token = before[token_start:] + text[start:end] + after[:token_end]
        if previous == "@" or "://" in token or self.address_suffix.match(after):
            return "adresse"
        if self.brand_file_suffix.match(after):
            return None  # cmux.app is the app's own bundle name
        if previous and (ASCII_WORD.match(previous) or previous in self.glued_prefix):
            return "fichier"
        if after[:1] and (ASCII_WORD.match(after[0]) or after[0] in self.glued_suffix):
            return "fichier"
        if re.match(r"[.:][A-Za-z0-9]", after) or self.hyphen_suffixes.match(after):
            return "fichier"
        return None


def occurrences(rules: Rules, text: str, key: str):
    for match in rules.pattern.finditer(text):
        yield match, rules.classify(text, match.start(), match.end(), key)


def rebrand(rules: Rules, text: str, key: str, brand: str) -> tuple[str, int]:
    pieces, last, replaced = [], 0, 0
    for match, kind in occurrences(rules, text, key):
        if kind is None:
            pieces.append(text[last:match.start()])
            pieces.append(brand)
            last = match.end()
            replaced += 1
    pieces.append(text[last:])
    return "".join(pieces), replaced


# --- Property list files, read and written in their own format -------------------------------

def load_plist(path: Path):
    raw = path.read_bytes()
    if raw.startswith(b"bplist"):
        return plistlib.loads(raw), ("binary", None)
    for bom, codec in ((b"\xff\xfe", "utf-16-le"), (b"\xfe\xff", "utf-16-be"), (b"\xef\xbb\xbf", "utf-8")):
        if raw.startswith(bom):
            text = raw[len(bom):].decode(codec)
            break
    else:
        bom, codec = b"", "utf-8"
        text = raw.decode("utf-8")
    if text.lstrip().startswith(("<?xml", "<!DOCTYPE", "<plist")):
        declared = re.sub(r'encoding="[^"]*"', 'encoding="UTF-8"', text, count=1)
        return plistlib.loads(declared.encode("utf-8")), ("xml", (bom, codec))
    converted = subprocess.run(
        ["plutil", "-convert", "json", "-o", "-", str(path)], capture_output=True, check=True
    ).stdout
    return json.loads(converted), ("openstep", (bom, codec))


def openstep_quote(value: str) -> str:
    escaped = value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", "\\t")
    return f'"{escaped}"'


def dump_plist(data, form) -> bytes:
    kind, encoding = form
    if kind == "binary":
        return plistlib.dumps(data, fmt=plistlib.FMT_BINARY, sort_keys=False)
    if kind == "xml":
        text = plistlib.dumps(data, fmt=plistlib.FMT_XML, sort_keys=False).decode("utf-8")
    else:
        text = "".join(f"{openstep_quote(k)} = {openstep_quote(v)};\n" for k, v in data.items())
    bom, codec = encoding
    return bom + text.encode(codec)


def walk_strings(value, path: tuple):
    """Yields (path, text) for every string leaf; dictionary keys are never texts."""
    if isinstance(value, str):
        yield path, value
    elif isinstance(value, dict):
        for k, v in value.items():
            yield from walk_strings(v, path + (k,))
    elif isinstance(value, list):
        for i, v in enumerate(value):
            yield from walk_strings(v, path + (i,))


def replace_leaf(value, path: tuple, new: str):
    if not path:
        return new
    head, rest = path[0], path[1:]
    value[head] = replace_leaf(value[head], rest, new)
    return value


def info_plist_visible(rules: Rules, path: tuple) -> bool:
    keys = "/".join(str(p) for p in path if not isinstance(p, int))
    last = next((p for p in reversed(path) if isinstance(p, str)), "")
    return any(p.search(last) or p.search(keys) for p in rules.info_keys)


# --- Units of text in a bundle -----------------------------------------------------------------

def text_files(app: Path):
    for root, dirs, files in os.walk(app):
        dirs.sort()
        for name in sorted(files):
            path = Path(root) / name
            if name.endswith((".strings", ".stringsdict")):
                yield "strings", path
            elif name == "Info.plist" and Path(root).name == "Contents":
                yield "info", path
            elif name.endswith(".sdef"):
                yield "sdef", path
            elif name.endswith((".html", ".htm")):
                yield "html", path


def lproj_language(path: Path) -> str | None:
    """The language of a file inside `<language>.lproj`, or None."""
    for part in reversed(path.parts):
        if part.endswith(".lproj"):
            return part[: -len(".lproj")]
    return None


def plist_units(rules: Rules, kind: str, path: Path):
    data, form = load_plist(path)
    units = []
    for leaf_path, text in walk_strings(data, ()):
        if kind == "info" and not info_plist_visible(rules, leaf_path):
            continue
        key = str(leaf_path[0]) if leaf_path else ""
        units.append((leaf_path, key, text))
    return data, form, units


def markup_spans(rules: Rules, kind: str, text: str):
    """(start, end) of each visible text: sdef attributes, HTML element contents."""
    if kind == "sdef":
        names = "|".join(map(re.escape, rules.sdef_attributes))
        pattern = re.compile(r'\b(?:' + names + r')="([^"]*)"')
    else:
        names = "|".join(map(re.escape, rules.html_elements))
        pattern = re.compile(r"<(?:" + names + r")\b[^>]*>([^<]*)</", re.IGNORECASE)
    return [(m.start(1), m.end(1)) for m in pattern.finditer(text)]


def apply(rules: Rules, app: Path, brand: str) -> int:
    changed_files, replaced_total = 0, 0
    for kind, path in text_files(app):
        replaced = 0
        if kind in ("strings", "info"):
            data, form, units = plist_units(rules, kind, path)
            language = lproj_language(path)
            for leaf_path, key, text in units:
                override = rules.override(key, language, brand) if kind == "strings" and len(leaf_path) == 1 else None
                if override is not None and rules.pattern.search(text):
                    new, count = override, 1
                else:
                    new, count = rebrand(rules, text, key, brand)
                if count:
                    data = replace_leaf(data, leaf_path, new)
                    replaced += count
            if replaced:
                path.write_bytes(dump_plist(data, form))
        else:
            text = path.read_text(encoding="utf-8")
            pieces, last = [], 0
            for start, end in markup_spans(rules, kind, text):
                new, count = rebrand(rules, text[start:end], "", brand)
                pieces.append(text[last:start])
                pieces.append(new)
                last = end
                replaced += count
            pieces.append(text[last:])
            if replaced:
                path.write_text("".join(pieces), encoding="utf-8")
        if replaced:
            changed_files += 1
            replaced_total += replaced
            print(f"changed: {path.relative_to(app)}")
    print(f"CHANGED_FILES={changed_files}")
    print(f"REPLACED={replaced_total}")
    return 0


def check(rules: Rules, app: Path) -> int:
    counts = Counter()
    unexplained = []
    for kind, path in text_files(app):
        if kind in ("strings", "info"):
            _, _, units = plist_units(rules, kind, path)
        else:
            text = path.read_text(encoding="utf-8")
            units = [((), "", text[s:e]) for s, e in markup_spans(rules, kind, text)]
        for _, key, text in units:
            for match, cls in occurrences(rules, text, key):
                if cls is None:
                    unexplained.append(f"{path.relative_to(app)} {key}: {text[:160]!r}")
                else:
                    counts[cls] += 1
    for cls in CLASSES:
        print(f"CLASS {cls}={counts[cls]}")
    print(f"UNEXPLAINED={len(unexplained)}")
    for line in unexplained[:25]:
        print(f"unexplained: {line}")
    return 1 if unexplained else 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)
    apply_parser = sub.add_parser("apply")
    apply_parser.add_argument("--name", required=True, help="the brand name (AppBranding.displayName)")
    apply_parser.add_argument("app")
    check_parser = sub.add_parser("check")
    check_parser.add_argument("app")
    args = parser.parse_args(argv)
    app = Path(args.app)
    if not (app / "Contents").is_dir():
        print(f"error: no app bundle at {app}", file=sys.stderr)
        return 2
    rules = Rules(json.loads(RULES_PATH.read_text(encoding="utf-8")))
    try:
        if args.command == "apply":
            if rules.pattern.search(args.name):
                print("error: the brand name contains the upstream name", file=sys.stderr)
                return 2
            return apply(rules, app, args.name)
        return check(rules, app)
    except (OSError, ValueError, plistlib.InvalidFileException, subprocess.CalledProcessError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
