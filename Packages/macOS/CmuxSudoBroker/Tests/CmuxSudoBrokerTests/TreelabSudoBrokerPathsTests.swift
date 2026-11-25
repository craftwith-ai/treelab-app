@testable import CmuxSudoBroker
import Foundation
import Testing

/// Treelab (`sh.treelab.app`) keeps its sudo spool in its own Application Support folder,
/// never under cmux's; cmux builds keep the shared `cmux` folder.
@Suite struct TreelabSudoBrokerPathsTests {
    private let support = URL(fileURLWithPath: "/Users/test-user/Library/Application Support", isDirectory: true)

    @Test func treelabSpoolLivesInItsOwnFolder() {
        let paths = SudoBrokerPaths(applicationSupportDirectory: support, bundleIdentifier: "sh.treelab.app")
        #expect(paths.base.path == "/Users/test-user/Library/Application Support/sh.treelab.app/sudo/sh.treelab.app")
        #expect(!paths.base.path.contains("/Application Support/cmux/"))
    }

    @Test func cmuxSpoolKeepsTheUpstreamFolder() {
        for identifier in ["com.cmuxterm.app", "com.cmuxterm.app.debug.my-tag"] {
            let paths = SudoBrokerPaths(applicationSupportDirectory: support, bundleIdentifier: identifier)
            #expect(paths.base.path == "/Users/test-user/Library/Application Support/cmux/sudo/\(identifier)")
        }
    }
}
