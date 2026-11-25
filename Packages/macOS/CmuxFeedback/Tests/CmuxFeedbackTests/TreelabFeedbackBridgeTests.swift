import AppKit
import CmuxFoundation
import Foundation
import Testing

@testable import CmuxFeedback

/// Treelab sends no feedback to Manaflow, whatever the entry point (`cmux feedback` on the
/// socket, a bound shortcut): the bridge refuses before any network and opens no composer.
/// cmux keeps sending. The endpoint is a closed local port, so a bridge that does try to send
/// fails with a transport error, never with "unavailable".
@Suite("Treelab feedback bridge")
struct TreelabFeedbackBridgeTests {
    private static let unavailable = "Feedback is unavailable right now. Email founders@cmux.com instead."

    private func bridge(_ branding: AppBranding, defaults: UserDefaults) -> FeedbackComposerBridge {
        let settings = FeedbackComposerSettings(defaultEndpoint: "http://127.0.0.1:9/api/feedback")
        return FeedbackComposerBridge(
            client: FeedbackComposerClient(settings: settings),
            userDefaults: defaults,
            branding: branding
        )
    }

    private func submitError(_ branding: AppBranding, defaults: UserDefaults) async -> String? {
        do {
            _ = try await bridge(branding, defaults: defaults)
                .submit(email: "valid@example.com", message: "Real message", imagePaths: [])
            return nil
        } catch {
            return (error as? FeedbackComposerBridgeError)?.errorDescription
        }
    }

    @Test func treelabRefusesBeforeAnyNetwork() async throws {
        let defaults = try #require(UserDefaults(suiteName: "treelab-feedback-\(UUID().uuidString)"))
        #expect(await submitError(.treelab, defaults: defaults) == Self.unavailable)
        #expect(defaults.string(forKey: FeedbackComposerSettings().storedEmailKey) == nil)
    }

    @Test func cmuxStillTriesToSend() async throws {
        let defaults = try #require(UserDefaults(suiteName: "cmux-feedback-\(UUID().uuidString)"))
        let message = await submitError(.cmux, defaults: defaults)
        #expect(message != nil)
        #expect(message != Self.unavailable)
    }

    @Test @MainActor func treelabOpensNoComposer() {
        var requests = 0
        let token = NotificationCenter.default.addObserver(
            forName: .feedbackComposerRequested, object: nil, queue: nil
        ) { _ in requests += 1 }
        defer { NotificationCenter.default.removeObserver(token) }

        bridge(.treelab, defaults: .standard).openComposer(in: nil)
        #expect(requests == 0)
        bridge(.cmux, defaults: .standard).openComposer(in: nil)
        #expect(requests == 1)
    }
}
