@testable import CmuxCloud
import Testing

/// Callers that pass no bundle identifier (the billing checkout URL) follow the running app's
/// brand: a cmux build keeps cmux://, only Treelab gets treelab://.
@Suite struct TreelabAuthEnvironmentTests {
    @Test func missingBundleIdentifierFollowsTheRunningAppNotTreelab() {
        // The package test host is not Treelab, so it keeps upstream's Release scheme.
        #expect(AuthEnvironment.callbackScheme(environment: [:], bundleIdentifier: nil, isDebugBuild: false) == "cmux")
    }

    @Test func explicitIdentifiersKeepTheirOwnScheme() {
        #expect(AuthEnvironment.callbackScheme(environment: [:], bundleIdentifier: "sh.treelab.app", isDebugBuild: false) == "treelab")
        #expect(AuthEnvironment.callbackScheme(environment: [:], bundleIdentifier: "com.cmuxterm.app", isDebugBuild: false) == "cmux")
        #expect(AuthEnvironment.callbackScheme(environment: [:], bundleIdentifier: "org.example.unknown", isDebugBuild: false) == "treelab")
    }
}
