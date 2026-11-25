import Foundation
#if canImport(PostHog)
import PostHog
#endif

/// The PostHog SDK call that sets context on later events, injectable so
/// tests observe it without the SDK. Person identity and groups (`identify`,
/// `group`, `reset`) are owned by the sign-in identity observer.
struct PostHogContextCalls: Sendable {
    var register: @Sendable ([String: Any]) -> Void

    static let live = PostHogContextCalls(
        register: { properties in
#if canImport(PostHog)
            PostHogSDK.shared.register(properties)
#endif
        }
    )
}
