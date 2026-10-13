import Foundation
import KombuchaCore

/// Where the history lives, behind a protocol so the recorder is tested with a fake.
protocol HistoryStoring: Sendable {
    /// Every record that decodes, in file order; a damaged line is skipped.
    func load() -> [HistoryRecord]
    /// False when the write failed. History is a convenience: nobody throws over it.
    func append(_ record: HistoryRecord) -> Bool
    func replaceAll(with records: [HistoryRecord]) -> Bool
}

/// One JSON object per line in `Application Support/Kombucha/history.jsonl`, owner-only. A lock serializes the
/// recorder's appends with the History tab's reads, as `SettingsStore` does for the defaults.
final class HistoryFile: HistoryStoring, @unchecked Sendable {
    private let url: URL
    private let lock = NSLock()

    init(url: URL) {
        self.url = url
    }

    static func standard() -> HistoryFile {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return HistoryFile(url: base.appending(path: "Kombucha/history.jsonl"))
    }

    func load() -> [HistoryRecord] {
        lock.withLock {
            guard let data = try? Data(contentsOf: url) else { return [] }
            let decoder = JSONDecoder()
            return data.split(separator: UInt8(ascii: "\n"))
                .compactMap { try? decoder.decode(HistoryRecord.self, from: Data($0)) }
        }
    }

    func append(_ record: HistoryRecord) -> Bool {
        lock.withLock {
            do {
                let line = try Self.line(for: record)
                try prepareFolder()
                if !FileManager.default.fileExists(atPath: url.path) {
                    guard FileManager.default.createFile(atPath: url.path, contents: nil,
                                                         attributes: [.posixPermissions: 0o600]) else { return false }
                }
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
                return true
            } catch {
                return false
            }
        }
    }

    func replaceAll(with records: [HistoryRecord]) -> Bool {
        lock.withLock {
            do {
                try prepareFolder()
                var data = Data()
                for record in records { data.append(try Self.line(for: record)) }
                try data.write(to: url, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                return true
            } catch {
                return false
            }
        }
    }

    private func prepareFolder() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
    }

    private static func line(for record: HistoryRecord) throws -> Data {
        var data = try JSONEncoder().encode(record)
        data.append(UInt8(ascii: "\n"))
        return data
    }
}
