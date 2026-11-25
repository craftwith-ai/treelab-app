import CmuxFoundation
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Treelab never fetches Manaflow's remote flags: a value an older build cached in its defaults
/// must not override the built-in default forever. cmux keeps reading its cache.
@MainActor
@Suite struct TreelabFeatureFlagsTests {
    @Test func treelabIgnoresRemoteValuesCachedByAnOlderBuild() throws {
        let flag = try #require(CmuxFeatureFlags.allFlags.first { $0.defaultWhenUnavailable })
        let suiteName = "treelab.feature.flags.stale-cache.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(false, forKey: "cmux.flags.remote.\(flag.key)")

        let treelab = CmuxFeatureFlags(
            defaults: defaults,
            remoteFlagValueProvider: { _ in nil },
            remoteFlagLoader: { nil },
            branding: .treelab
        )
        #expect(treelab.remoteValue(for: flag) == nil)
        #expect(treelab.effectiveValue(for: flag))

        let cmux = CmuxFeatureFlags(
            defaults: defaults,
            remoteFlagValueProvider: { _ in nil },
            remoteFlagLoader: { nil },
            branding: .cmux
        )
        #expect(cmux.remoteValue(for: flag) == false)
        #expect(!cmux.effectiveValue(for: flag))
    }
}
