#!/usr/bin/env bash
# Builds Treelab.app from this checkout: Release, arm64, bundle id sh.treelab.app,
# inert Sparkle feed, ad hoc signature, its own DerivedData, no global CLI links.
#
# Usage: scripts/treelab/build.sh [--output <dir>] [--derived-data <dir>]
#   --output        where Treelab.app is written (default: build/treelab)
#   --derived-data  Xcode DerivedData for this build (default: build/treelab/DerivedData)
#
# The build runs in a scrubbed environment: no CMUX_* or GHOSTTY_* variable inherited
# from the terminal (often the user's own cmux) reaches xcodebuild or the build phases.
# Then it puts the brand on the built copy (texts, icons, terminal themes; scripts/treelab/brand/).
# Prints "App path: <path>" on success; check it with scripts/treelab/check-identity.sh,
# scripts/treelab/check-brand.sh and scripts/treelab/check-icons.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUTPUT_DIR="$ROOT/build/treelab"
DERIVED_DATA=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output) OUTPUT_DIR="${2:?--output needs a value}"; shift 2 ;;
    --derived-data) DERIVED_DATA="${2:?--derived-data needs a value}"; shift 2 ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) echo "error: unknown option $1" >&2; exit 2 ;;
  esac
done
DERIVED_DATA="${DERIVED_DATA:-$OUTPUT_DIR/DerivedData}"

APP_NAME="Treelab"
BUNDLE_ID="sh.treelab.app"
URL_SCHEME="treelab"
UPSTREAM_BUNDLE_ID="com.cmuxterm.app"

cd "$ROOT"

# Submodules first: the Zig pin below is read from ghostty/build.zig.zon, absent in a fresh clone.
echo "==> Submodules (ghostty, vendor/bonsplit)"
env -i HOME="$HOME" PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin" \
  git submodule update --init ghostty vendor/bonsplit

# One environment for every tool below: the user's PATH and home, nothing from cmux.
RUSTUP_BIN="$(brew --prefix rustup 2>/dev/null || echo /opt/homebrew/opt/rustup)/bin"
# Ghostty pins Zig by major.minor (ghostty/build.zig.zon); Homebrew's plain `zig` is often newer.
# shellcheck source=scripts/ghostty-zig-version.sh
source "$ROOT/scripts/ghostty-zig-version.sh"
ZIG_MINOR="$(ghostty_minimum_zig_version "$ROOT" | cut -d. -f1,2)"
ZIG_BIN="$(brew --prefix "zig@$ZIG_MINOR" 2>/dev/null || true)/bin"
[[ -x "$ZIG_BIN/zig" ]] || { echo "error: Zig $ZIG_MINOR missing (brew install zig@$ZIG_MINOR)" >&2; exit 1; }
CLEAN_ENV=(
  env -i
  HOME="$HOME" USER="${USER:-$(id -un)}" LOGNAME="${LOGNAME:-$(id -un)}"
  TMPDIR="${TMPDIR:-/tmp}" LANG="${LANG:-en_US.UTF-8}" TERM="${TERM:-dumb}"
  PATH="$ZIG_BIN:$HOME/.cargo/bin:$RUSTUP_BIN:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
  CMUX_WIREGUARD_GO_REQUIRE="${CMUX_WIREGUARD_GO_REQUIRE:-0}"
  CMUX_GHOSTTYKIT_CACHE_DIR="$HOME/.cache/treelab/ghosttykit"
  # Upstream's build names the Computer Use helper with it (name, permission prompts); the
  # helper's folder keeps upstream's name, the runtime looks it up by that path.
  CMUX_CUA_HELPER_DISPLAY_NAME="$APP_NAME Computer Use"
)
[[ -n "${DEVELOPER_DIR:-}" ]] && CLEAN_ENV+=(DEVELOPER_DIR="$DEVELOPER_DIR")
run() { "${CLEAN_ENV[@]}" "$@"; }

# Global CLI links must stay exactly as they were (C2): record them before the build.
links_state() {
  # shellcheck disable=SC2012
  { ls -la "$HOME"/.local/bin/cmux* /tmp/cmux-cli /tmp/cmux-last-cli-path 2>/dev/null || true; } | sed 's/  */ /g'
}
LINKS_BEFORE="$(links_state)"

echo "==> Checking tools"
run xcrun clang --version >/dev/null || { echo "error: Xcode cannot run (license: sudo xcodebuild -license accept)" >&2; exit 1; }
run xcrun metal --version >/dev/null 2>&1 || { echo "error: Metal toolchain missing (xcodebuild -downloadComponent MetalToolchain)" >&2; exit 1; }
run cargo --version >/dev/null || { echo "error: cargo not found (rustup default stable)" >&2; exit 1; }
DIFF_RUST_TOOLCHAIN="$(awk -F '"' '/^[[:space:]]*channel[[:space:]]*=/{print $2; exit}' Native/DiffSidecar/rust-toolchain.toml)"
run rustup toolchain install "$DIFF_RUST_TOOLCHAIN" --profile minimal --component clippy,rustfmt >/dev/null
run rustup target add --toolchain "$DIFF_RUST_TOOLCHAIN" aarch64-apple-darwin x86_64-apple-darwin >/dev/null

echo "==> Computer Use helper source (cmux-cua without its PostHog telemetry)"
# Upstream compiles the Computer Use helper from cmux-cua, whose binary carries a PostHog capture URL
# and an install ping that ignores CMUX_CUA_TELEMETRY_ENABLED. Treelab hands upstream's build
# (CMUX_CUA_SRC, its option for a local checkout with edits) the same pinned commit with that
# telemetry removed; when upstream moves the pin and the patch no longer applies, the build stops here.
CUA_PIN="$(sed -n 's/^CMUX_CUA_PINNED_SHA="\([0-9a-f]\{40\}\)"$/\1/p' scripts/build-cmux-cua.sh)"
# shellcheck disable=SC2016 # the ${...} is upstream's literal text, matched as is
CUA_REPO="$(sed -n 's/^CMUX_CUA_REPO_URL="${CMUX_CUA_REPO_URL:-\(.*\)}"$/\1/p' scripts/build-cmux-cua.sh)"
[[ -n "$CUA_PIN" && -n "$CUA_REPO" ]] || { echo "error: cmux-cua pin unreadable in scripts/build-cmux-cua.sh" >&2; exit 1; }
CUA_MIRROR="$HOME/.cache/treelab/cmux-cua.git"
CUA_SRC="$OUTPUT_DIR/cmux-cua-src"
[[ -d "$CUA_MIRROR" ]] || run git clone --quiet --bare "$CUA_REPO" "$CUA_MIRROR"
run git -C "$CUA_MIRROR" cat-file -e "$CUA_PIN^{commit}" 2>/dev/null || run git -C "$CUA_MIRROR" fetch --quiet origin "$CUA_PIN"
run git -C "$CUA_MIRROR" update-ref refs/treelab/pinned "$CUA_PIN"
rm -rf "$CUA_SRC"
run git clone --quiet --shared --no-checkout "$CUA_MIRROR" "$CUA_SRC"
run git -C "$CUA_SRC" checkout --quiet --detach "$CUA_PIN"
run git -C "$CUA_SRC" apply "$ROOT/scripts/treelab/cmux-cua-no-telemetry.patch"
CLEAN_ENV+=(CMUX_CUA_SRC="$CUA_SRC")

echo "==> GhosttyKit (pinned prebuilt, Zig build as fallback)"
run "$ROOT/scripts/ensure-ghosttykit.sh"

echo "==> xcodebuild Release arm64 -> $DERIVED_DATA"
run xcodebuild \
  -project cmux.xcodeproj \
  -scheme cmux \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$DERIVED_DATA" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGN_IDENTITY=- \
  DEVELOPMENT_TEAM= \
  CODE_SIGN_ENTITLEMENTS= \
  CMUX_AUTH_CALLBACK_SCHEME="$URL_SCHEME" \
  build

BUILT_APP="$DERIVED_DATA/Build/Products/Release/cmux.app"
[[ -d "$BUILT_APP" ]] || { echo "error: $BUILT_APP not found" >&2; exit 1; }

echo "==> Branding the bundle as $APP_NAME ($BUNDLE_ID)"
mkdir -p "$OUTPUT_DIR"
APP="$OUTPUT_DIR/$APP_NAME.app"
rm -rf "$APP"
ditto "$BUILT_APP" "$APP"
PLIST="$APP/Contents/Info.plist"
pb() { /usr/libexec/PlistBuddy -c "$1" "$PLIST"; }
set_string() { pb "Set :$1 $2" 2>/dev/null || pb "Add :$1 string $2"; }
OLD_EXECUTABLE="$(pb 'Print :CFBundleExecutable')"
mv "$APP/Contents/MacOS/$OLD_EXECUTABLE" "$APP/Contents/MacOS/$APP_NAME"
set_string CFBundleExecutable "$APP_NAME"
set_string CFBundleName "$APP_NAME"
set_string CFBundleDisplayName "$APP_NAME"
set_string CFBundleIdentifier "$BUNDLE_ID"
# Inert update feed on this Mac: upstream falls back to cmux's public appcast when SUFeedURL is
# empty (UpdateFeedResolver) and forces automatic checks on at first launch, so an empty feed would
# offer to replace Treelab with cmux. The loopback discard port refuses at once; nothing leaves.
TREELAB_FEED_URL="https://127.0.0.1:9/treelab-appcast.xml"
plutil -replace SUFeedURL -string "$TREELAB_FEED_URL" "$PLIST"
plutil -replace SUEnableAutomaticChecks -bool NO "$PLIST"
# URL types are named after the bundle id at build time.
count="$(pb 'Print :CFBundleURLTypes' | grep -c '^    Dict {' || true)"
for ((i = 0; i < count; i++)); do
  name="$(pb "Print :CFBundleURLTypes:$i:CFBundleURLName" 2>/dev/null || true)"
  [[ "$name" == "$UPSTREAM_BUNDLE_ID"* ]] && pb "Set :CFBundleURLTypes:$i:CFBundleURLName ${BUNDLE_ID}${name#"$UPSTREAM_BUNDLE_ID"}"
done

echo "==> Brand: texts, icons, terminal themes"
BRAND="$ROOT/scripts/treelab/brand"
# Texts of every language and nested bundle, Info.plist, AppleScript dictionary, HTML titles.
python3 -I "$ROOT/scripts/treelab/brand-bundle.py" apply --name "$APP_NAME" "$APP" | grep -E '^(CHANGED_FILES|REPLACED)='
# Icons: upstream's asset catalog recompiled with Treelab's images under upstream's names
# (images from scripts/treelab/make-icons.sh); scripts/treelab/check-icons.sh compares the result.
CATALOG="$OUTPUT_DIR/brand-assets"
rm -rf "$CATALOG"
mkdir -p "$CATALOG/out"
ditto "$ROOT/Assets.xcassets" "$CATALOG/Assets.xcassets"
replace_image() {
  [[ -f "$2" ]] || { echo "error: upstream's catalog has no ${2#"$CATALOG/"} (renamed?)" >&2; exit 1; }
  cp "$1" "$2"
}
for png in "$BRAND"/icons/appiconset/*.png; do
  replace_image "$png" "$CATALOG/Assets.xcassets/AppIcon.appiconset/$(basename "$png")"
done
replace_image "$BRAND/icons/AppIconLight.png" "$CATALOG/Assets.xcassets/AppIconLight.imageset/AppIconLight.png"
replace_image "$BRAND/icons/AppIconDark.png" "$CATALOG/Assets.xcassets/AppIconDark.imageset/AppIconDark.png"
run xcrun actool "$CATALOG/Assets.xcassets" --compile "$CATALOG/out" --platform macosx \
  --minimum-deployment-target "$(pb 'Print :LSMinimumSystemVersion')" --target-device mac --app-icon AppIcon \
  --output-partial-info-plist "$CATALOG/partial.plist" --errors --output-format human-readable-text >/dev/null
cp "$CATALOG/out/Assets.car" "$APP/Contents/Resources/Assets.car"
cp "$CATALOG/out/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
# The Computer Use helper's icon, in the helper and where the app draws it.
HELPER="$APP/Contents/Library/cmux Computer Use.app"
cp "$BRAND/icons/ComputerUseHelper.icns" "$APP/Contents/Resources/ComputerUseHelperIcon.icns"
if [[ -d "$HELPER" ]]; then cp "$BRAND/icons/ComputerUseHelper.icns" "$HELPER/Contents/Resources/AppIcon.icns"; fi
# Terminal themes applied when the user sets none (AppBranding.defaultTerminalThemeNames).
cp "$BRAND/themes/Treelab" "$BRAND/themes/Treelab Light" "$APP/Contents/Resources/ghostty/themes/"

echo "==> Ad hoc signature"
# Nested code whose resources changed first (helper, network extension), keeping its identity.
for nested in "$HELPER" "$APP"/Contents/Library/SystemExtensions/*.systemextension; do
  [[ -d "$nested" ]] || continue
  /usr/bin/codesign --force --sign - --timestamp=none --preserve-metadata=identifier,entitlements,flags,runtime "$nested"
done
# Like upstream's ad hoc Release (scripts/reload.sh), the app is built without entitlements
# (CODE_SIGN_ENTITLEMENTS= above): keychain groups and personal-information access need a
# signing team. check-identity.sh fails if any entitlement still names cmux.
/usr/bin/codesign --force --sign - --timestamp=none "$APP"

LINKS_AFTER="$(links_state)"
if [[ "$LINKS_BEFORE" != "$LINKS_AFTER" ]]; then
  echo "error: global CLI links changed during the build" >&2
  diff <(echo "$LINKS_BEFORE") <(echo "$LINKS_AFTER") >&2 || true
  exit 1
fi

echo "App path: $APP"
