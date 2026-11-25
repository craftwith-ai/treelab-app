#!/usr/bin/env bash
# Checks a built Treelab.app: arm64, ad hoc signature that verifies, sh.treelab.app,
# named Treelab, empty update feed, treelab URL scheme, own keychain group.
# Exits non-zero at the first mismatch.
#
# Usage: scripts/treelab/check-identity.sh [path/to/Treelab.app]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP="${1:-$ROOT/build/treelab/Treelab.app}"
PLIST="$APP/Contents/Info.plist"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "ok: $*"; }
key() { /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST" 2>/dev/null || true; }

[[ -d "$APP" && -f "$PLIST" ]] || fail "no app bundle at $APP"

identifier="$(key CFBundleIdentifier)"
[[ "$identifier" == "sh.treelab.app" ]] || fail "CFBundleIdentifier is '$identifier', expected sh.treelab.app"
ok "CFBundleIdentifier = $identifier"

for name_key in CFBundleName CFBundleDisplayName CFBundleExecutable; do
  value="$(key "$name_key")"
  [[ "$value" == "Treelab" ]] || fail "$name_key is '$value', expected Treelab"
done
ok "CFBundleName, CFBundleDisplayName and CFBundleExecutable = Treelab"

executable="$APP/Contents/MacOS/Treelab"
[[ -x "$executable" ]] || fail "missing executable $executable"
archs="$(lipo -archs "$executable")"
[[ "$archs" == "arm64" ]] || fail "executable architectures are '$archs', expected arm64"
ok "architecture = $archs"

signature="$(/usr/bin/codesign -dv "$APP" 2>&1)"
grep -q '^Signature=adhoc$' <<< "$signature" || fail "signature is not ad hoc: $(grep -E '^(Signature|Authority)=' <<< "$signature" | head -1)"
ok "codesign -dv: Signature=adhoc"
grep -q '^Identifier=sh\.treelab\.app$' <<< "$signature" || fail "code signing identifier is not sh.treelab.app"
/usr/bin/codesign --verify --deep --strict "$APP" 2>&1 || fail "codesign --verify --deep --strict failed"
ok "codesign --verify --deep --strict"

feed="$(key SUFeedURL)"
[[ -z "$feed" ]] || fail "SUFeedURL is '$feed', expected empty"
[[ "$(key SUEnableAutomaticChecks)" == "false" ]] || fail "SUEnableAutomaticChecks is not false"
ok "Sparkle feed empty, automatic checks off"

schemes="$(key CFBundleURLTypes | awk '/CFBundleURLSchemes/{f=1; next} f && /\}/{f=0} f{gsub(/^ +/, ""); print}')"
grep -qx 'treelab' <<< "$schemes" || fail "URL scheme treelab not registered"
if grep -qx 'cmux' <<< "$schemes"; then fail "URL scheme cmux still registered"; fi
if key CFBundleURLTypes | grep -q 'com\.cmuxterm\.app'; then fail "URL types still named after com.cmuxterm.app"; fi
ok "URL scheme treelab (no cmux)"

entitlements="$(/usr/bin/codesign -d --entitlements :- "$APP" 2>/dev/null || true)"
if grep -q 'com\.cmuxterm\.app' <<< "$entitlements"; then fail "entitlements still name com.cmuxterm.app"; fi
ok "entitlements do not name com.cmuxterm.app"

[[ -x "$APP/Contents/Resources/bin/cmux" ]] || fail "bundled CLI missing (Contents/Resources/bin/cmux)"
ok "bundled CLI present"

echo "PASS: $APP"
