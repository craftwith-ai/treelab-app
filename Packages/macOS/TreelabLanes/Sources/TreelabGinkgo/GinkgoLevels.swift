/// The voice levels, up to 30 a second, kept out of the SwiftUI tree: only the views that draw the
/// voice observe them, through a handler, so a level never invalidates the rest of the screen.
@MainActor
public final class GinkgoLevels {
    /// The person's voice, 0 to 1.
    public private(set) var input = 0.0
    /// Ginkgo's voice as played, 0 to 1.
    public private(set) var output = 0.0
    /// Levels received since launch (measurements).
    public private(set) var received = 0
    private var handlers: [Int: @MainActor (Double, Double) -> Void] = [:]
    private var nextToken = 0

    public init() {}

    /// Calls `handler` with each new level, and once at rest when the levels stop.
    /// - Returns: the token to give back to ``stopObserving(_:)``.
    public func observe(_ handler: @escaping @MainActor (Double, Double) -> Void) -> Int {
        nextToken += 1
        handlers[nextToken] = handler
        return nextToken
    }

    /// Stops calling the handler of `token`.
    public func stopObserving(_ token: Int) {
        handlers[token] = nil
    }

    func update(input: Double, output: Double) {
        self.input = input
        self.output = output
        received += 1
        for handler in handlers.values { handler(input, output) }
    }

    func reset() {
        guard input != 0 || output != 0 else { return }
        input = 0
        output = 0
        for handler in handlers.values { handler(0, 0) }
    }
}
