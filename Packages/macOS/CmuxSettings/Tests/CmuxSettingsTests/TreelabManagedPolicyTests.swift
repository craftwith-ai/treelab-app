import CmuxFoundation
import CmuxSettings
import Foundation
import Testing

/// Treelab (`sh.treelab.app`) talks to no Manaflow service and no measurement tool: it forces
/// in code the managed-device rules an administrator would push with a configuration profile.
/// SSH and Mosh stay available, and upstream cmux forces nothing without a profile.
@Suite struct TreelabManagedPolicyTests {
    /// The rules Treelab forces, whatever the user or a profile says.
    private static let treelabForcedKeys: Set<ManagedDevicePolicyKey> = [
        .disableCloud,
        .disableRemoteControl,
        .disableIrohNetworking,
        .disableDeviceDiscovery,
        .disableIncomingDeviceAccess,
        .disableTelemetry,
        .disableAutoUpdate,
        .disableAICredentialUpload,
    ]

    private func makeSuite(_ label: String) throws -> (UserDefaults, () -> Void) {
        let suiteName = "TreelabManagedPolicyTests.\(label).\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        return (defaults, { defaults.removePersistentDomain(forName: suiteName) })
    }

    /// A resolver for `bundleIdentifier` with no configuration profile installed.
    private func policy(bundleIdentifier: String, defaults: UserDefaults) -> ManagedDevicePolicy {
        ManagedDevicePolicy(
            defaults: defaults,
            releaseDomainDefaults: nil,
            forcedObject: { _, _ in nil },
            branding: AppBranding.resolve(bundleIdentifier: bundleIdentifier)
        )
    }

    private func enforcedKeys(_ policy: ManagedDevicePolicy) -> Set<ManagedDevicePolicyKey> {
        Set(ManagedDevicePolicyKey.allCases.filter { policy.isEnforced($0) })
    }

    @Test func treelabForcesExactlyTheEightManaflowRules() throws {
        let (defaults, cleanup) = try makeSuite("treelab")
        defer { cleanup() }

        let policy = policy(bundleIdentifier: "sh.treelab.app", defaults: defaults)

        #expect(enforcedKeys(policy) == Self.treelabForcedKeys)
        for key in Self.treelabForcedKeys {
            #expect(policy.forcedBool(for: key) == true, "\(key.rawValue) is not forced")
            #expect(policy.forcedValueSource(forUserDefaultsKey: key.rawValue) == .appDomain)
        }
        #expect(policy.isDeviceDiscoveryDisabled)
        #expect(policy.isIncomingDeviceAccessDisabled)
    }

    @Test func treelabLeavesSSHAndMoshConnectionsFree() throws {
        let (defaults, cleanup) = try makeSuite("remote")
        defer { cleanup() }

        let policy = policy(bundleIdentifier: "sh.treelab.app", defaults: defaults)

        #expect(!policy.isEnforced(.disableRemoteConnections))
        #expect(policy.forcedBool(for: .disableRemoteConnections) == nil)
    }

    @Test func aUserValueCannotLiftATreelabRule() throws {
        let (defaults, cleanup) = try makeSuite("user")
        defer { cleanup() }

        for key in Self.treelabForcedKeys {
            defaults.set(false, forKey: key.rawValue)
        }
        let policy = policy(bundleIdentifier: "sh.treelab.app", defaults: defaults)

        #expect(enforcedKeys(policy) == Self.treelabForcedKeys)
    }

    @Test func cmuxForcesNothingWithoutAProfile() throws {
        let (defaults, cleanup) = try makeSuite("cmux")
        defer { cleanup() }

        for identifier in ["com.cmuxterm.app", "com.cmuxterm.app.debug"] {
            let policy = policy(bundleIdentifier: identifier, defaults: defaults)

            #expect(enforcedKeys(policy).isEmpty, "\(identifier) forces \(enforcedKeys(policy))")
            #expect(!policy.isDeviceDiscoveryDisabled)
            #expect(!policy.isIncomingDeviceAccessDisabled)
        }
    }

    @Test func cmuxStillHonorsAProfile() throws {
        let (defaults, cleanup) = try makeSuite("profile")
        defer { cleanup() }

        let policy = ManagedDevicePolicy(
            defaults: defaults,
            releaseDomainDefaults: nil,
            forcedObject: { _, key in key == ManagedDevicePolicyKey.disableTelemetry.rawValue ? true : nil },
            branding: .cmux
        )

        #expect(enforcedKeys(policy) == [.disableTelemetry])
    }
}
