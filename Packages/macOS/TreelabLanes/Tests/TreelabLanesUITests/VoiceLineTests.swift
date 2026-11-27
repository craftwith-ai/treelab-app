import AppKit
import Testing
@testable import TreelabLanesUI

/// The voice line under the heart: when the levels stop, the whole line goes back to rest, not
/// only its last bar (a frozen voice under "Microphone closed" would say the opposite of the words).
@MainActor
@Suite("Voice line")
struct VoiceLineTests {
    private func heights(_ view: NSView) -> [CGFloat] {
        (view.layer?.sublayers ?? []).map(\.frame.height)
    }

    @Test("after the levels stop, every bar is back to the thin line at rest")
    func restAfterLevels() {
        let view = GinkgoVoiceLineView(frame: NSRect(x: 0, y: 0, width: 288, height: 36))
        view.layout()
        for _ in 0..<48 { view.push(1) }
        #expect(heights(view).max() ?? 0 > 3, "the line moved with the levels")
        view.rest()
        #expect(heights(view).allSatisfy { $0 == 3 }, "bars still up after rest: \(heights(view).filter { $0 != 3 }.count)")
    }
}
