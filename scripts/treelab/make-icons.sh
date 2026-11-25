#!/usr/bin/env bash
# Draws Treelab's icons from the treelab.sh logo (scripts/treelab/brand/logo.svg) into
# scripts/treelab/brand/icons/, committed so a build needs no drawing tool:
#   AppIconLight.png, AppIconDark.png    1024 px, the Settings picker and the Dock follow them;
#   appiconset/<size>[@2x][_dark].png    the app icon, light and dark (luminosity) variants;
#   ComputerUseHelper.icns               the Computer Use helper's icon (dark variant).
# Dark = the site's logo (#0c1410 tile); light = an #eef3ea tile with darker arcs.
# The arcs are the logo's own paths (64-unit view box), drawn with CoreGraphics on the macOS
# icon grid (824 px rounded square on a 1024 px canvas, soft shadow).
#
# Usage: scripts/treelab/make-icons.sh   (rewrites the files; exits non-zero on failure)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$HERE/brand/icons"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/treelab-icons.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# The paths must stay those of the site's logo: fail if logo.svg no longer has them.
for path in 'M6 40H50' 'M8 40C8 14 34 12 48 38' 'M14 40C15 24 34 22 45 39' 'M20 40C21 31 33 30 42 39' \
  'M10 40C12 51 34 52 46 41' 'M50 40C54 40 56 36 59 30' 'M50 40C54 40 56 44 59 48'; do
  grep -qF "d=\"$path\"" "$HERE/brand/logo.svg" || { echo "error: logo.svg lost the path $path" >&2; exit 1; }
done

cat > "$WORK/draw.swift" <<'SWIFT'
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct Palette { let tileTop, tileBottom, line, green, orange: (CGFloat, CGFloat, CGFloat) }
func hex(_ value: UInt32) -> (CGFloat, CGFloat, CGFloat) {
    (CGFloat((value >> 16) & 0xff) / 255, CGFloat((value >> 8) & 0xff) / 255, CGFloat(value & 0xff) / 255)
}
let dark = Palette(tileTop: hex(0x142019), tileBottom: hex(0x0c1410), line: hex(0xeef3ea), green: hex(0xb6f27a), orange: hex(0xf5b04a))
let light = Palette(tileTop: hex(0xf6f9f3), tileBottom: hex(0xe3ebdd), line: hex(0x0c1410), green: hex(0x3d6b0f), orange: hex(0xb36b00))
let space = CGColorSpace(name: CGColorSpace.sRGB)!
func color(_ c: (CGFloat, CGFloat, CGFloat), _ alpha: CGFloat = 1) -> CGColor { CGColor(colorSpace: space, components: [c.0, c.1, c.2, alpha])! }

// The logo's strokes, in its 64-unit view box (y down), with their color role.
enum Role { case line, green, orange }
let strokes: [(Role, [CGPoint])] = [
    (.line, [CGPoint(x: 6, y: 40), CGPoint(x: 50, y: 40)]),
    (.green, [CGPoint(x: 8, y: 40), CGPoint(x: 8, y: 14), CGPoint(x: 34, y: 12), CGPoint(x: 48, y: 38)]),
    (.orange, [CGPoint(x: 14, y: 40), CGPoint(x: 15, y: 24), CGPoint(x: 34, y: 22), CGPoint(x: 45, y: 39)]),
    (.green, [CGPoint(x: 20, y: 40), CGPoint(x: 21, y: 31), CGPoint(x: 33, y: 30), CGPoint(x: 42, y: 39)]),
    (.green, [CGPoint(x: 10, y: 40), CGPoint(x: 12, y: 51), CGPoint(x: 34, y: 52), CGPoint(x: 46, y: 41)]),
    (.line, [CGPoint(x: 50, y: 40), CGPoint(x: 54, y: 40), CGPoint(x: 56, y: 36), CGPoint(x: 59, y: 30)]),
    (.line, [CGPoint(x: 50, y: 40), CGPoint(x: 54, y: 40), CGPoint(x: 56, y: 44), CGPoint(x: 59, y: 48)]),
]

func render(_ palette: Palette, pixels: Int, to url: URL) {
    let size = CGFloat(pixels)
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: size)
    ctx.scaleBy(x: 1, y: -1)  // y down, like the SVG
    let unit = size / 1024
    let tile = CGRect(x: 100 * unit, y: 100 * unit, width: 824 * unit, height: 824 * unit)
    let shape = CGPath(roundedRect: tile, cornerWidth: 185 * unit, cornerHeight: 185 * unit, transform: nil)
    // Soft shadow under the tile, as macOS icons have.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 10 * unit), blur: 24 * unit, color: color((0, 0, 0), 0.32))
    ctx.addPath(shape)
    ctx.setFillColor(color(palette.tileBottom))
    ctx.fillPath()
    ctx.restoreGState()
    // Tile with a light vertical gradient.
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: space, colors: [color(palette.tileTop), color(palette.tileBottom)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: tile.minY), end: CGPoint(x: 0, y: tile.maxY), options: [])
    // The logo's arcs, its view box mapped on the tile.
    let scale = tile.width / 64
    ctx.translateBy(x: tile.minX, y: tile.minY)
    ctx.scaleBy(x: scale, y: scale)
    ctx.setLineWidth(4)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    for (role, p) in strokes {
        let path = CGMutablePath()
        path.move(to: p[0])
        if p.count == 2 { path.addLine(to: p[1]) } else { path.addCurve(to: p[3], control1: p[1], control2: p[2]) }
        ctx.addPath(path)
        ctx.setStrokeColor(color(role == .line ? palette.line : role == .green ? palette.green : palette.orange))
        ctx.strokePath()
    }
    ctx.restoreGState()
    let image = ctx.makeImage()!
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("cannot write \(url.path)") }
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = URL(fileURLWithPath: CommandLine.arguments[2])
let appiconset = out.appendingPathComponent("appiconset")
try FileManager.default.createDirectory(at: appiconset, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
render(light, pixels: 1024, to: out.appendingPathComponent("AppIconLight.png"))
render(dark, pixels: 1024, to: out.appendingPathComponent("AppIconDark.png"))
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "\(points)" : "\(points)@2x"
        render(light, pixels: points * scale, to: appiconset.appendingPathComponent("\(name).png"))
        render(dark, pixels: points * scale, to: appiconset.appendingPathComponent("\(name)_dark.png"))
        render(dark, pixels: points * scale, to: iconset.appendingPathComponent("icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"))
    }
}
SWIFT

rm -rf "$OUT"
mkdir -p "$OUT"
env -i HOME="$HOME" PATH="/usr/bin:/bin" xcrun swift "$WORK/draw.swift" "$OUT" "$WORK/helper.iconset"
iconutil -c icns -o "$OUT/ComputerUseHelper.icns" "$WORK/helper.iconset"
echo "icons written to ${OUT#"$HERE/../../"}: $(find "$OUT" -type f | wc -l | tr -d ' ') files"
