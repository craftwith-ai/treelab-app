#!/usr/bin/env bash
# Tests scripts/treelab/brand-bundle.py on a throwaway app bundle that holds every text format
# found in a built cmux.app: binary, XML (UTF-8 and UTF-16 with BOM) and old-style .strings,
# .stringsdict plurals, Info.plist and InfoPlist.strings, a nested resource bundle, the nested
# Computer Use helper, the AppleScript dictionary (.sdef) and an HTML page title.
#   A. "cmux" naming the app becomes the brand name in English, French, German, Japanese, Arabic,
#      the keys of rules.json "key_overrides" take their text (the accent is not blue), and a
#      package key naming cmux that the main table lacks is added to it (upstream calls without
#      bundle: read the main table), like a main-table key the brand changes that a language lacks;
#   B. technical names stay: `code`, quoted commands, cmux.json, cmux-tui, ~/.cmuxterm, paths,
#      addresses, CMUX_* variables, identifiers, "Usage: cmux", every cli.* key, the GPL line;
#   C. format specifiers (%@, %1$@, %#@n@) and each file's format and encoding are kept,
#      every file still passes plutil -lint;
#   D. a second pass changes nothing;
#   E. "check" fails (rc 1) before the pass and after a new unexplained "cmux", passes after it.
# Usage: scripts/treelab/test-brand-bundle.sh   (exit 0 = all pass)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${BRAND_BUNDLE_SCRIPT:-$HERE/brand-bundle.py}"   # override: red check
WORK="$(mktemp -d "${TMPDIR:-/tmp}/treelab-brand-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
APP="$WORK/Fake.app"

failures=0
pass() { echo "ok: $*"; }
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }
brand() { python3 -I "$SCRIPT" "$@"; }

# Fixture: one entry per case, written in the format a real build uses for that file.
python3 -I - "$APP" <<'PY'
import os, plistlib, sys
app = sys.argv[1]
res = os.path.join(app, "Contents", "Resources")

def write(path, data, kind):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if kind == "binary":
        blob = plistlib.dumps(data, fmt=plistlib.FMT_BINARY, sort_keys=False)
    elif kind == "xml":
        blob = plistlib.dumps(data, fmt=plistlib.FMT_XML, sort_keys=False)
    elif kind == "xml-utf16":  # what SwiftPM copies: UTF-16LE with BOM, declaration says UTF-8
        blob = b"\xff\xfe" + plistlib.dumps(data, fmt=plistlib.FMT_XML, sort_keys=False).decode("utf-8").encode("utf-16-le")
    elif kind == "openstep":
        lines = []
        for key, value in data.items():
            esc = lambda s: s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
            lines.append(f'"{esc(key)}" = "{esc(value)}";')
        blob = ("\n".join(lines) + "\n").encode("utf-8")
    with open(path, "wb") as handle:
        handle.write(blob)

write(os.path.join(app, "Contents", "Info.plist"), {
    "CFBundleIdentifier": "com.cmuxterm.app",
    "NSCameraUsageDescription": "A program running within cmux would like to use your camera.",
    "NSServices": [{"NSMenuItem": {"default": "New cmux Workspace Here"}, "NSMessage": "newCmuxWorkspace"}],
    "UTExportedTypeDeclarations": [{"UTTypeIdentifier": "com.cmux.surface-resource", "UTTypeDescription": "cmux Surface Resource"}],
    "OSAScriptingDefinition": "cmux.sdef",
    "CMUXIrohRelayPolicyKeyID": "cmux-production-relay-policy-2026-07",
}, "xml")

write(os.path.join(res, "en.lproj", "Localizable.strings"), {
    "quit": "Quit cmux",
    "restart": "Restart cmux.",
    "possessive": "cmux's browser",
    "start": "cmux could not open %@.",
    "format": "%@ opened in cmux (%1$@)",
    "upper": "Install a CMUX sidebar extension",
    "banner": "[cmux] Press Enter to reconnect.",
    "quotedLabel": "“cmux processes only” accepts only local processes.",
    "appFile": "Move cmux.app to /Applications and retry.",
    "backtick": "Run `cmux docs settings` to list them.",
    "quotedCommand": "Retry 'cmux restore --surface'.",
    "proseCommand": "Edit automations.json, then run cmux automation reload.",
    "json": "Edit cmux.json in ~/.config/cmux/ first.",
    "tui": "Open cmux-tui in a terminal.",
    "home": "Events go to ~/.cmuxterm/events.jsonl.",
    "address": "See https://cmux.com/docs or write to support@cmux.com.",
    "env": "Set CMUX_SOCKET_PATH before launch.",
    "identifier": "openMarkdownInCmuxViewer",
    "usage": "Usage: cmux ssh <host>",
    "gpl": "Based on cmux by Manaflow — GPL-3.0-or-later",
    "cli.help.open": "cmux opens a workspace",
    "glaeda.cli.usage": "cmux glaeda request",
    "settings.app.accentColor.cmux": "cmux Blue",
    "settings.notifications.paneFlashThemeColor.subtitle": "Use the terminal theme foreground for flashes; unread rings stay cmux blue.",
}, "binary")
write(os.path.join(res, "en.lproj", "InfoPlist.strings"), {
    "NSCameraUsageDescription": "A program running within cmux would like to use your camera.",
}, "binary")
write(os.path.join(res, "en.lproj", "Localizable.stringsdict"), {
    "windows.count": {
        "NSStringLocalizedFormatKey": "%#@n@ open in cmux",
        "n": {
            "NSStringFormatSpecTypeKey": "NSStringPluralRuleType",
            "NSStringFormatValueTypeKey": "lld",
            "one": "%lld cmux window",
            "other": "%lld cmux windows",
        },
    },
}, "xml")
write(os.path.join(res, "fr.lproj", "Localizable.strings"), {
    "quit": "Quitter cmux",
    "format": "%1$@ ouvert dans cmux",
    "backtick": "Exécutez `cmux docs settings` pour les lister.",
    "settings.app.accentColor.cmux": "Bleu cmux",
}, "xml-utf16")
write(os.path.join(res, "de.lproj", "Localizable.strings"), {
    "profile": "Das cmux-Browserprofil fehlt.",
}, "binary")
write(os.path.join(res, "ja.lproj", "Localizable.strings"), {
    "launch": "cmuxを起動",
    "installCLI": "シェルコマンド: 'cmux'をPATHにインストール",
    "settings.app.accentColor.cmux": "cmux ブルー",
}, "openstep")
write(os.path.join(res, "ar.lproj", "Localizable.strings"), {
    "lost": "فقد CMUX الاتصال بالامتداد.",
    "load": "تعذر على cmux تحميل الإعدادات.",
}, "binary")
write(os.path.join(res, "bs.lproj", "Localizable.strings"), {
    "load": "cmux ne može učitati postavke.",
}, "binary")
write(os.path.join(res, "CmuxFoundation_CmuxFoundation.bundle", "Contents", "Resources", "en.lproj", "Localizable.strings"), {
    "nested": "cmux could not reach the server.",
}, "xml-utf16")
# A package catalog whose keys some upstream calls look up in the app's main table (no bundle:).
sub = os.path.join(res, "CmuxSettingsUI_CmuxSettingsUI.bundle", "Contents", "Resources")
write(os.path.join(sub, "en.lproj", "Localizable.strings"), {
    "settings.sub.note": "cmux keeps it.",
    "settings.sub.plain": "No brand here.",
    "quit": "Quit cmux (package copy)",
    "cli.sub.help": "cmux sub-command",
}, "xml-utf16")
write(os.path.join(sub, "fr.lproj", "Localizable.strings"), {
    "settings.sub.note": "cmux le garde.",
    "settings.sub.plain": "Pas de marque ici.",
}, "xml-utf16")
write(os.path.join(app, "Contents", "Library", "cmux Computer Use.app", "Contents", "Resources", "en.lproj", "InfoPlist.strings"), {
    "NSAccessibilityUsageDescription": "cmux Computer Use controls apps only when you ask.",
}, "openstep")

os.makedirs(os.path.join(res, "agent-session"), exist_ok=True)
with open(os.path.join(res, "agent-session", "index.html"), "w", encoding="utf-8") as handle:
    handle.write('<!doctype html>\n<html><head><title>cmux Agent Session</title>'
                 '<script src="cmux-session.js"></script></head><body></body></html>\n')
with open(os.path.join(res, "cmux.sdef"), "w", encoding="utf-8") as handle:
    handle.write('<?xml version="1.0" encoding="UTF-8"?>\n'
                 '<dictionary title="cmux Scripting Dictionary">\n'
                 '  <suite name="cmux Suite" code="Cmux" description="cmux scripting support.">\n'
                 '    <class name="window" code="CMwn" description="A cmux window.">\n'
                 '      <cocoa class="CmuxScriptWindow"/>\n'
                 '    </class>\n'
                 '  </suite>\n'
                 '</dictionary>\n')
PY

# Reads one value (a key path separated by "/") from any plist or .strings file.
value() {
  python3 -I - "$1" "$2" <<'PY'
import json, plistlib, subprocess, sys
path, keypath = sys.argv[1], sys.argv[2]
data = json.loads(subprocess.run(["plutil", "-convert", "json", "-o", "-", path], capture_output=True, check=True).stdout)
for part in keypath.split("/"):
    data = data[int(part)] if isinstance(data, list) else data[part]
print(data, end="")
PY
}
expect_value() {
  local file="$1" key="$2" want="$3" got
  got="$(value "$APP/$file" "$key" 2>/dev/null || echo "<missing>")"
  if [[ "$got" == "$want" ]]; then pass "$file $key = $want"; else fail "$file $key = '$got', want '$want'"; fi
}
tree_hash() { (cd "$APP" && find . -type f -print0 | sort -z | xargs -0 shasum -a 256 | shasum -a 256); }
format_of() { head -c 1 "$1" | xxd -p; }   # b(plist), UTF-16 BOM (ff), " (old-style) or < (XML)

EN=Contents/Resources/en.lproj/Localizable.strings
FORMATS_BEFORE="$(for f in "$APP"/Contents/Resources/{en,fr,de,ja,ar}.lproj/Localizable.strings; do format_of "$f"; done)"

# E (before). The untouched bundle has unexplained "cmux": check fails and counts them.
rc=0; out="$(brand check "$APP" 2>&1)" || rc=$?
if [[ "$rc" == 1 ]] && grep -Eq '^UNEXPLAINED=[1-9][0-9]*$' <<< "$out"; then
  pass "check before the pass: rc 1, $(grep '^UNEXPLAINED=' <<< "$out")"
else
  fail "check before the pass: rc $rc, want 1 with UNEXPLAINED>0"; echo "$out" | tail -5 >&2
fi

rc=0; out="$(brand apply --name Treelab "$APP" 2>&1)" || rc=$?
[[ "$rc" == 0 ]] && pass "apply rc 0" || { fail "apply rc $rc"; echo "$out" | tail -5 >&2; }

# A. The app's name.
expect_value "$EN" quit "Quit Treelab"
expect_value "$EN" restart "Restart Treelab."
expect_value "$EN" possessive "Treelab's browser"
expect_value "$EN" upper "Install a Treelab sidebar extension"
expect_value "$EN" banner "[Treelab] Press Enter to reconnect."
expect_value "$EN" quotedLabel "“Treelab processes only” accepts only local processes."
expect_value "$EN" appFile "Move Treelab.app to /Applications and retry."
expect_value Contents/Resources/fr.lproj/Localizable.strings quit "Quitter Treelab"
expect_value Contents/Resources/de.lproj/Localizable.strings profile "Das Treelab-Browserprofil fehlt."
expect_value Contents/Resources/ja.lproj/Localizable.strings launch "Treelabを起動"
expect_value Contents/Resources/ar.lproj/Localizable.strings lost "فقد Treelab الاتصال بالامتداد."
expect_value Contents/Resources/ar.lproj/Localizable.strings load "تعذر على Treelab تحميل الإعدادات."
expect_value Contents/Resources/en.lproj/InfoPlist.strings NSCameraUsageDescription \
  "A program running within Treelab would like to use your camera."
expect_value Contents/Resources/CmuxFoundation_CmuxFoundation.bundle/Contents/Resources/en.lproj/Localizable.strings \
  nested "Treelab could not reach the server."
expect_value "Contents/Library/cmux Computer Use.app/Contents/Resources/en.lproj/InfoPlist.strings" \
  NSAccessibilityUsageDescription "Treelab Computer Use controls apps only when you ask."
expect_value Contents/Info.plist NSCameraUsageDescription "A program running within Treelab would like to use your camera."
expect_value Contents/Info.plist NSServices/0/NSMenuItem/default "New Treelab Workspace Here"
expect_value Contents/Info.plist UTExportedTypeDeclarations/0/UTTypeDescription "Treelab Surface Resource"
expect_value Contents/Resources/en.lproj/Localizable.stringsdict windows.count/n/one "%lld Treelab window"
expect_value Contents/Resources/en.lproj/Localizable.stringsdict windows.count/n/other "%lld Treelab windows"

# A2. Key overrides (rules.json): a color named after cmux becomes the brand's accent.
expect_value "$EN" settings.app.accentColor.cmux "Treelab"
expect_value Contents/Resources/fr.lproj/Localizable.strings settings.app.accentColor.cmux "Treelab"
expect_value Contents/Resources/ja.lproj/Localizable.strings settings.app.accentColor.cmux "Treelab"
expect_value "$EN" settings.notifications.paneFlashThemeColor.subtitle \
  "Use the terminal theme foreground for flashes; unread rings keep the accent color."

# A3. Package keys naming cmux and missing from the main table are added to it, translated.
expect_value "$EN" settings.sub.note "Treelab keeps it."
expect_value Contents/Resources/fr.lproj/Localizable.strings settings.sub.note "Treelab le garde."
expect_value Contents/Resources/de.lproj/Localizable.strings settings.sub.note "Treelab keeps it."
expect_value Contents/Resources/ja.lproj/Localizable.strings settings.sub.note "Treelab keeps it."
expect_value "$EN" quit "Quit Treelab"
for missing in settings.sub.plain cli.sub.help; do
  if value "$APP/$EN" "$missing" >/dev/null 2>&1; then fail "$missing copied to the main table"; else pass "$missing not copied"; fi
done

# A4. Main-table keys the brand changes and a language lacks get the branded English text there:
#     macOS shows the binary's English default (cmux included) for a missing key, never the en table.
expect_value Contents/Resources/de.lproj/Localizable.strings restart "Restart Treelab."
expect_value Contents/Resources/ja.lproj/Localizable.strings quit "Quit Treelab"
expect_value Contents/Resources/ar.lproj/Localizable.strings possessive "Treelab's browser"
expect_value Contents/Resources/fr.lproj/Localizable.strings quit "Quitter Treelab"
expect_value Contents/Resources/bs.lproj/Localizable.strings settings.notifications.paneFlashThemeColor.subtitle \
  "Use the terminal theme foreground for flashes; unread rings keep the accent color."
expect_value Contents/Resources/bs.lproj/Localizable.strings restart "Restart Treelab."
for missing in json backtick env identifier; do
  if value "$APP/Contents/Resources/de.lproj/Localizable.strings" "$missing" >/dev/null 2>&1; then
    fail "$missing (technical name only) copied to de"
  else
    pass "$missing not copied to de"
  fi
done

# B. Technical names stay.
expect_value "$EN" backtick "Run \`cmux docs settings\` to list them."
expect_value "$EN" quotedCommand "Retry 'cmux restore --surface'."
expect_value "$EN" proseCommand "Edit automations.json, then run cmux automation reload."
expect_value "$EN" json "Edit cmux.json in ~/.config/cmux/ first."
expect_value "$EN" tui "Open cmux-tui in a terminal."
expect_value "$EN" home "Events go to ~/.cmuxterm/events.jsonl."
expect_value "$EN" address "See https://cmux.com/docs or write to support@cmux.com."
expect_value "$EN" env "Set CMUX_SOCKET_PATH before launch."
expect_value "$EN" identifier "openMarkdownInCmuxViewer"
expect_value "$EN" usage "Usage: cmux ssh <host>"
expect_value "$EN" gpl "Based on cmux by Manaflow — GPL-3.0-or-later"
expect_value "$EN" cli.help.open "cmux opens a workspace"
expect_value "$EN" glaeda.cli.usage "cmux glaeda request"
expect_value Contents/Resources/fr.lproj/Localizable.strings backtick "Exécutez \`cmux docs settings\` pour les lister."
expect_value Contents/Resources/ja.lproj/Localizable.strings installCLI "シェルコマンド: 'cmux'をPATHにインストール"
expect_value Contents/Info.plist CFBundleIdentifier "com.cmuxterm.app"
expect_value Contents/Info.plist OSAScriptingDefinition "cmux.sdef"
expect_value Contents/Info.plist NSServices/0/NSMessage "newCmuxWorkspace"
expect_value Contents/Info.plist UTExportedTypeDeclarations/0/UTTypeIdentifier "com.cmux.surface-resource"
expect_value Contents/Info.plist CMUXIrohRelayPolicyKeyID "cmux-production-relay-policy-2026-07"
html="$(cat "$APP/Contents/Resources/agent-session/index.html")"
if grep -q '<title>Treelab Agent Session</title>' <<< "$html" && grep -q 'src="cmux-session.js"' <<< "$html"; then
  pass "HTML title branded, script path kept"
else
  fail "HTML: $html"
fi
sdef="$(cat "$APP/Contents/Resources/cmux.sdef")"
if grep -q 'title="Treelab Scripting Dictionary"' <<< "$sdef" && grep -q 'name="Treelab Suite" code="Cmux" description="Treelab scripting support."' <<< "$sdef" \
  && grep -q 'description="A Treelab window."' <<< "$sdef" && grep -q '<cocoa class="CmuxScriptWindow"/>' <<< "$sdef"; then
  pass "sdef names and descriptions branded, codes and classes kept"
else
  fail "sdef: $sdef"
fi

# C. Format specifiers, file formats and validity.
expect_value "$EN" start "Treelab could not open %@."
expect_value "$EN" format "%@ opened in Treelab (%1\$@)"
expect_value Contents/Resources/fr.lproj/Localizable.strings format "%1\$@ ouvert dans Treelab"
expect_value Contents/Resources/en.lproj/Localizable.stringsdict windows.count/NSStringLocalizedFormatKey "%#@n@ open in Treelab"
FORMATS_AFTER="$(for f in "$APP"/Contents/Resources/{en,fr,de,ja,ar}.lproj/Localizable.strings; do format_of "$f"; done)"
if [[ "$FORMATS_BEFORE" == "$FORMATS_AFTER" ]]; then pass "file formats kept (binary, UTF-16 BOM, old-style)"; else fail "file formats changed: $(echo $FORMATS_BEFORE) -> $(echo $FORMATS_AFTER)"; fi
if [[ "$(head -c 1 "$APP/Contents/Resources/ja.lproj/Localizable.strings")" == '"' ]]; then
  pass "old-style .strings stays old-style"
else
  fail "old-style .strings rewritten in another format"
fi
lint_failures=0
while IFS= read -r -d '' file; do
  plutil -lint -s "$file" >/dev/null || { fail "plutil -lint $file"; lint_failures=$((lint_failures + 1)); }
done < <(find "$APP" \( -name '*.strings' -o -name '*.stringsdict' -o -name Info.plist \) -print0)
((lint_failures == 0)) && pass "plutil -lint on every file"
if xmllint --noout "$APP/Contents/Resources/cmux.sdef" 2>/dev/null; then pass "sdef still well-formed XML"; else fail "sdef not well-formed"; fi

# D. Idempotent.
before="$(tree_hash)"
rc=0; out="$(brand apply --name Treelab "$APP" 2>&1)" || rc=$?
if [[ "$rc" == 0 && "$(tree_hash)" == "$before" ]] && grep -q '^CHANGED_FILES=0$' <<< "$out"; then
  pass "second pass changes nothing"
else
  fail "second pass: rc $rc, $(grep '^CHANGED_FILES=' <<< "$out" || echo 'no CHANGED_FILES line')"
fi

# E (after). Every remaining "cmux" is classified; a new unexplained one fails again.
rc=0; out="$(brand check "$APP" 2>&1)" || rc=$?
if [[ "$rc" == 0 ]] && grep -q '^UNEXPLAINED=0$' <<< "$out" && grep -Eq '^CLASS cli=[1-9]' <<< "$out" \
  && grep -Eq '^CLASS commande=[1-9]' <<< "$out" && grep -Eq '^CLASS fichier=[1-9]' <<< "$out" \
  && grep -Eq '^CLASS adresse=[1-9]' <<< "$out" && grep -Eq '^CLASS gpl=[1-9]' <<< "$out"; then
  pass "check after the pass: rc 0, every class counted"
else
  fail "check after the pass: rc $rc"; echo "$out" | tail -12 >&2
fi
python3 -I - "$APP/Contents/Resources/de.lproj/Localizable.strings" <<'PY'
import plistlib, sys
path = sys.argv[1]
data = plistlib.load(open(path, "rb"))
data["new"] = "cmux hat ein neues Fenster geöffnet."
plistlib.dump(data, open(path, "wb"), fmt=plistlib.FMT_BINARY, sort_keys=False)
PY
rc=0; out="$(brand check "$APP" 2>&1)" || rc=$?
if [[ "$rc" == 1 ]] && grep -q '^UNEXPLAINED=1$' <<< "$out" && grep -q 'cmux hat ein neues Fenster' <<< "$out"; then
  pass "check names a new unexplained cmux (rc 1)"
else
  fail "check after a new cmux: rc $rc"; echo "$out" | tail -5 >&2
fi

if ((failures > 0)); then
  echo "FAIL: $failures check(s) failed" >&2
  exit 1
fi
echo "PASS: test-brand-bundle.sh"
