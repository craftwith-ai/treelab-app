import AppKit
import Foundation
import SwiftUI
import Testing
@testable import TreelabGinkgo
@testable import TreelabLanesUI

/// The conversation card in a real AppKit window: what its scroll view shows once lines arrive.
/// The stand-in Ginkgo, like the real one, sends lines after the voice screen has appeared,
/// sometimes several in one burst; the latest line must be the one in view.
@MainActor
@Suite("Conversation card scrolling", .serialized)
struct ConversationScrollTests {
    @MainActor @Observable
    final class Feed {
        var session = GinkgoSession()
        private var seq = 0
        func add(_ id: String, _ who: GinkgoSpeaker, _ text: String) {
            seq += 1
            session.apply(GinkgoEnvelope(seq: seq, at: Date(timeIntervalSince1970: 1_795_765_000 + Double(seq)),
                                         event: .line(GinkgoLine(id: id, who: who, text: text, final: true))))
        }
        func listen() {
            seq += 1
            session.apply(GinkgoEnvelope(seq: seq, at: Date(timeIntervalSince1970: 1_795_765_000),
                                         event: .state(.listening, mic: true, focus: nil)))
        }
    }

    struct Host: View {
        let feed: Feed
        var body: some View {
            GinkgoConversationCard(session: feed.session, wholeOnly: false, size: GinkgoScreenSize(width: 1280))
                .frame(width: 640, height: 260)
        }
    }

    private static let long = "Trois demandes t’attendent. La plus ancienne : le plan du paiement d’atelier-photo, "
        + "depuis 28 minutes. Un couloir est arrêté : partage."

    private func window(_ feed: Feed) -> (NSWindow, NSHostingView<Host>) {
        let hosting = NSHostingView(rootView: Host(feed: feed))
        // Off every screen: the test never shows anything to the person using the Mac.
        let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: 640, height: 260),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        window.orderFrontRegardless()
        return (window, hosting)
    }

    /// Lets SwiftUI and AppKit run their updates and layout.
    private func settle(_ seconds: Double = 0.4) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    }

    private func scrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        for sub in view.subviews { if let found = scrollView(in: sub) { return found } }
        return nil
    }

    /// Distance, in points, between the bottom of the content and the bottom of what is shown.
    private func hiddenBelow(_ scroll: NSScrollView) -> CGFloat {
        guard let document = scroll.documentView else { return .infinity }
        let visible = scroll.documentVisibleRect
        let bounds = document.bounds
        return document.isFlipped ? bounds.maxY - visible.maxY : visible.minY - bounds.minY
    }

    /// Distance, in points, between the top of the content and the top of what is shown.
    private func hiddenAbove(_ scroll: NSScrollView) -> CGFloat {
        guard let document = scroll.documentView else { return .infinity }
        let visible = scroll.documentVisibleRect
        let bounds = document.bounds
        return document.isFlipped ? visible.minY - bounds.minY : bounds.maxY - visible.maxY
    }

    @Test("lines arriving in one burst after the card appeared: the latest line is in view")
    func burstAfterAppear() throws {
        let feed = Feed()
        let (window, hosting) = window(feed)
        defer { window.orderOut(nil) }
        feed.listen()
        settle()
        for index in 1...6 { feed.add("l\(index)", index.isMultiple(of: 2) ? .ginkgo : .user, "\(index). " + Self.long) }
        settle()
        let scroll = try #require(scrollView(in: hosting))
        #expect(hiddenBelow(scroll) <= 1, "content hidden below the latest line: \(hiddenBelow(scroll))")
    }

    @Test("lines arriving one by one: each new line is in view")
    func oneByOne() throws {
        let feed = Feed()
        let (window, hosting) = window(feed)
        defer { window.orderOut(nil) }
        feed.listen()
        settle()
        for index in 1...6 {
            feed.add("l\(index)", index.isMultiple(of: 2) ? .ginkgo : .user, "\(index). " + Self.long)
            settle(0.25)
        }
        let scroll = try #require(scrollView(in: hosting))
        #expect(hiddenBelow(scroll) <= 1, "content hidden below the latest line: \(hiddenBelow(scroll))")
    }

    @Test("a short conversation starts at the top of the card")
    func shortStartsAtTop() throws {
        let feed = Feed()
        let (window, hosting) = window(feed)
        defer { window.orderOut(nil) }
        feed.listen()
        settle()
        feed.add("l1", .user, "Ginkgo, qu’est-ce qui m’attend ?")
        settle()
        let scroll = try #require(scrollView(in: hosting))
        #expect(hiddenAbove(scroll) <= 1, "content hidden above the first line: \(hiddenAbove(scroll))")
    }
}
