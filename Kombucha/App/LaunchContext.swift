import Foundation

/// Whether this process is the app itself or the host of the test bundle.
enum LaunchContext: Equatable {
    case app
    case tests

    static func current(environment: [String: String] = ProcessInfo.processInfo.environment) -> LaunchContext {
        environment["XCTestConfigurationFilePath"] == nil ? .app : .tests
    }
}
