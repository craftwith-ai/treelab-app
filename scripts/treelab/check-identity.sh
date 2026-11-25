#!/usr/bin/env bash
# Checks a built Treelab.app: arm64, ad hoc signature that verifies, sh.treelab.app,
# named Treelab, empty update feed, treelab URL scheme, own keychain group,
# no PostHog or Sentry SDK (files, symbols, collection domains).
# Exits non-zero at the first mismatch (every SDK leftover is listed before failing).
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

# An empty feed falls back to cmux's public appcast: the feed must be the loopback one.
feed="$(key SUFeedURL)"
[[ "$feed" == https://127.0.0.1:9/* ]] || fail "SUFeedURL is '$feed', expected the inert loopback feed"
[[ "$(key SUEnableAutomaticChecks)" == "false" ]] || fail "SUEnableAutomaticChecks is not false"
ok "Sparkle feed inert ($feed), automatic checks off"

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

# No measurement tool ships: no PostHog or Sentry file (CmuxSentryScrubbing has no SDK and may
# stay), and no executable anywhere in the bundle (helpers in Contents/Library included) names
# their SDK or their collection domains. Every finding is listed.
sdk_findings=()
while IFS= read -r path; do
  sdk_findings+=("file ${path#"$APP"/}")
done < <(find "$APP" \( -iname '*posthog*' -o -iname '*sentry*' \) ! -iname '*CmuxSentryScrubbing*' | sort)
while IFS= read -r -d '' binary; do
  file -b "$binary" | grep -q '^Mach-O' || continue
  label="${binary#"$APP"/}"
  for symbol in PostHogSDK SentrySDK; do
    if LC_ALL=C grep -a -q "$symbol" "$binary"; then sdk_findings+=("symbol $symbol in $label"); fi
  done
  domains="$(LC_ALL=C strings -a "$binary" | grep -E -i -o '[a-z0-9.-]*(posthog\.com|sentry\.io)([^a-z0-9-]|$)' | sort -u | tr '\n' ' ' || true)"
  [[ -z "$domains" ]] || sdk_findings+=("domains in $label: $domains")
done < <(find "$APP" -type f -print0)
if ((${#sdk_findings[@]} > 0)); then
  printf 'FAIL: measurement SDK leftover: %s\n' "${sdk_findings[@]}" >&2
  exit 1
fi
ok "no PostHog or Sentry file, symbol or collection domain"

echo "PASS: $APP"
