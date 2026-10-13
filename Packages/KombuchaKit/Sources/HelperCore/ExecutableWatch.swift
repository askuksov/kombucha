import Foundation

/// Calls `onChange` once when the file is deleted, renamed or written. Attribute changes do not count.
public final class ExecutableWatch: @unchecked Sendable {
    /// Why `open` refused the file, with the `errno` read right after the call.
    public struct OpenFailure: Error, Equatable {
        public let code: Int32
        public var reason: String { String(cString: strerror(code)) }
    }

    private let source: any DispatchSourceFileSystemObject
    private let onChange: @Sendable () -> Void

    public init(path: String, queue: DispatchQueue, onChange: @escaping @Sendable () -> Void) throws(OpenFailure) {
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { throw OpenFailure(code: errno) }
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.delete, .rename, .write], queue: queue)
        self.onChange = onChange
        source.setEventHandler { [weak self] in self?.fire() }
        source.setCancelHandler { close(descriptor) }
        source.resume()
    }

    deinit {
        source.cancel()
    }

    // Runs on the source's serial queue; after the cancel no handler runs again.
    private func fire() {
        guard !source.isCancelled else { return }
        source.cancel()
        onChange()
    }
}
