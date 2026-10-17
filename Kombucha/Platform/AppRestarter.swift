import AppKit

/// Quits the app and starts a new instance of the same bundle.
@MainActor
protocol Restarting: Sendable {
    /// True when the app is quitting; false when the restart could not start and the app keeps running.
    func restart() -> Bool
}

/// Quits through the normal path, so the engine shuts down as for Quit. A shell waits until the old process is
/// gone and then opens the bundle again; if the shell cannot be started the app keeps running.
struct AppRestarter: Restarting {
    func restart() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", #"while kill -0 "$1" 2>/dev/null; do sleep 0.2; done; exec /usr/bin/open -n "$2""#,
                             "sh", String(ProcessInfo.processInfo.processIdentifier), Bundle.main.bundleURL.path]
        do {
            try process.run()
        } catch {
            AppLog.engine.error("the restart helper did not start: \(error.localizedDescription, privacy: .public)")
            return false
        }
        NSApp.terminate(nil)
        return true
    }
}
