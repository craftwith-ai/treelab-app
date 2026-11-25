#!/usr/bin/env bash
# Checks the icons and terminal themes of a built Treelab.app against scripts/treelab/brand/:
#   1. Assets.car holds the same images (name, type, appearance, scale, size) as upstream's
#      Assets.xcassets compiled by actool, so nothing upstream reads is missing;
#   2. AppIconLight, AppIconDark (read from Assets.car like the app and the Dock plugin do) and
#      the largest AppIcon.icns image are Treelab's images (pixels compared with the sources);
#   3. the Computer Use helper's icon (in the helper and in the app) and the two terminal themes
#      are byte for byte the sources.
#
# Usage: scripts/treelab/check-icons.sh [path/to/Treelab.app]   (exit 0 = PASS, 1 = FAIL)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
APP="${1:-$ROOT/build/treelab/Treelab.app}"
BRAND="$HERE/brand"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/treelab-icons-check.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
[[ -d "$APP/Contents" ]] || { echo "error: no app bundle at $APP" >&2; exit 2; }

failures=0
ok() { echo "ok: $*"; }
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }
CLEAN=(env -i HOME="$HOME" PATH="/usr/bin:/bin:/usr/sbin:/sbin")

# 1. Same image set as upstream's catalog.
minimum="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP/Contents/Info.plist")"
mkdir -p "$WORK/upstream"
"${CLEAN[@]}" xcrun actool "$ROOT/Assets.xcassets" --compile "$WORK/upstream" --platform macosx \
  --minimum-deployment-target "$minimum" --target-device mac --app-icon AppIcon \
  --output-partial-info-plist "$WORK/partial.plist" --errors --output-format human-readable-text >/dev/null
"${CLEAN[@]}" xcrun assetutil --info "$WORK/upstream/Assets.car" > "$WORK/upstream.json"
"${CLEAN[@]}" xcrun assetutil --info "$APP/Contents/Resources/Assets.car" > "$WORK/built.json"
if diff_out="$(python3 -I - "$WORK/upstream.json" "$WORK/built.json" <<'PY'
import json, sys
def images(path):
    rows = json.load(open(path))[1:]
    return sorted({(r.get("Name"), r.get("AssetType"), r.get("Appearance"), r.get("Scale"), r.get("PixelWidth"))
                   for r in rows if not str(r.get("Name", "")).startswith("ZZZZPackedAsset")}, key=str)
upstream, built = images(sys.argv[1]), images(sys.argv[2])
missing = [i for i in upstream if i not in built]
extra = [i for i in built if i not in upstream]
print(f"{len(upstream)} renditions upstream, {len(built)} built, {len({i[0] for i in built})} names")
for item in missing: print("missing:", item)
for item in extra: print("extra:", item)
sys.exit(1 if missing or extra else 0)
PY
)"; then ok "Assets.car = upstream's image set ($(head -1 <<< "$diff_out"))"; else fail "Assets.car differs from upstream's image set"; echo "$diff_out" >&2; fi

# 2. Treelab's pixels where the app, the Dock plugin and Finder read the icons.
cat > "$WORK/compare.swift" <<'SWIFT'
import AppKit
let app = URL(fileURLWithPath: CommandLine.arguments[1])
let brand = URL(fileURLWithPath: CommandLine.arguments[2])
func pixels(_ image: NSImage, side: Int) -> [UInt8] {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: side * 4, bitsPerPixel: 32)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: side, height: side), from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return Array(UnsafeBufferPointer(start: rep.bitmapData!, count: side * side * 4))
}
func difference(_ a: NSImage, _ b: NSImage) -> Double {
    let (x, y) = (pixels(a, side: 256), pixels(b, side: 256))
    return Double(zip(x, y).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }) / Double(x.count)
}
var failed = false
let bundle = Bundle(url: app)!
for (name, source) in [("AppIconLight", "icons/AppIconLight.png"), ("AppIconDark", "icons/AppIconDark.png")] {
    guard let built = bundle.image(forResource: name), let expected = NSImage(contentsOf: brand.appendingPathComponent(source)) else {
        print("FAIL: \(name) unreadable"); failed = true; continue
    }
    let d = difference(built, expected)
    let other = NSImage(contentsOf: brand.appendingPathComponent(name == "AppIconLight" ? "icons/AppIconDark.png" : "icons/AppIconLight.png"))!
    print(String(format: "%@ %@: mean pixel difference %.2f with its source, %.2f with the other variant",
                 d < 2 && difference(built, other) > 20 ? "ok:" : "FAIL:", name, d, difference(built, other)))
    if !(d < 2 && difference(built, other) > 20) { failed = true }
}
if let icns = NSImage(contentsOf: app.appendingPathComponent("Contents/Resources/AppIcon.icns")),
   let expected = NSImage(contentsOf: brand.appendingPathComponent("icons/appiconset/512@2x.png")) {
    let d = difference(icns, expected)
    print(String(format: "%@ AppIcon.icns: mean pixel difference %.2f with appiconset/512@2x.png", d < 2 ? "ok:" : "FAIL:", d))
    if d >= 2 { failed = true }
} else { print("FAIL: AppIcon.icns unreadable"); failed = true }
exit(failed ? 1 : 0)
SWIFT
if out="$("${CLEAN[@]}" xcrun swift "$WORK/compare.swift" "$APP" "$BRAND" 2>&1)"; then echo "$out"; else echo "$out" >&2; fail "icon pixels"; fi

# 3. Byte-identical copies.
same() {
  if [[ -f "$2" ]] && cmp -s "$1" "$2"; then ok "${2#"$APP"/} = ${1#"$HERE"/}"; else fail "${2#"$APP"/} is not ${1#"$HERE"/}"; fi
}
same "$BRAND/icons/ComputerUseHelper.icns" "$APP/Contents/Resources/ComputerUseHelperIcon.icns"
same "$BRAND/icons/ComputerUseHelper.icns" "$APP/Contents/Library/cmux Computer Use.app/Contents/Resources/AppIcon.icns"
same "$BRAND/themes/Treelab" "$APP/Contents/Resources/ghostty/themes/Treelab"
same "$BRAND/themes/Treelab Light" "$APP/Contents/Resources/ghostty/themes/Treelab Light"
helper_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$APP/Contents/Library/cmux Computer Use.app/Contents/Info.plist" 2>/dev/null || true)"
if [[ "$helper_name" == "Treelab Computer Use" ]]; then ok "helper CFBundleDisplayName = $helper_name"; else fail "helper CFBundleDisplayName = '$helper_name'"; fi

if ((failures > 0)); then echo "FAIL: $failures check(s)" >&2; exit 1; fi
echo "PASS: $APP"
