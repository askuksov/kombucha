import Foundation
import KombuchaCore
import Testing
@testable import Kombucha

private let start = Date(timeIntervalSince1970: 1_800_000_000)

private func point(_ level: Int) -> HistoryRecord {
    .point(HistoryPoint(time: start.addingTimeInterval(Double(level)), level: level, onAC: true, charging: false,
                        resting: true, temperatureCelsius: 30))
}

/// A file in a fresh temporary directory that does not exist yet, removed afterwards.
private func withFile(_ body: (HistoryFile, URL) throws -> Void) rethrows {
    let directory = FileManager.default.temporaryDirectory.appending(path: "kombucha-tests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "Kombucha/history.jsonl")
    try body(HistoryFile(url: url), url)
}

@Test func aMissingFileLoadsAsNothing() {
    withFile { file, _ in #expect(file.load().isEmpty) }
}

@Test func appendCreatesTheFolderAndTheFileAndLoadReadsItBack() {
    withFile { file, url in
        #expect(file.append(point(70)))
        #expect(file.append(.baseline(92)))
        #expect(file.load() == [point(70), .baseline(92)])
        #expect(FileManager.default.fileExists(atPath: url.path))
    }
}

@Test func theFileAndItsFolderAreSetUpForTheOwnerOnly() throws {
    try withFile { file, url in
        #expect(file.append(point(70)))
        let fileMode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        let folderMode = try FileManager.default.attributesOfItem(atPath: url.deletingLastPathComponent().path)[.posixPermissions] as? Int
        #expect(fileMode == 0o600)
        #expect(folderMode == 0o700)
    }
}

@Test func aDamagedLineIsSkippedAndTheRestLoads() throws {
    try withFile { file, url in
        #expect(file.append(point(70)))
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("not json at all\n{\"k\":\"p\",\"t\":1".utf8))
        try handle.close()
        #expect(file.load() == [point(70)])
    }
}

@Test func replacingRewritesTheWholeFile() throws {
    try withFile { file, url in
        #expect(file.append(point(70)))
        #expect(file.append(point(71)))
        #expect(file.replaceAll(with: [point(72)]))
        #expect(file.load() == [point(72)])
        let fileMode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(fileMode == 0o600)
        #expect(file.append(point(73)))
        #expect(file.load() == [point(72), point(73)])
    }
}

@Test func aWriteThatCannotHappenReportsFailureInsteadOfThrowing() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: "kombucha-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    // The "folder" the file would live in is a regular file.
    let blocker = directory.appending(path: "blocker")
    try Data().write(to: blocker)
    let file = HistoryFile(url: blocker.appending(path: "history.jsonl"))
    #expect(!file.append(point(70)))
    #expect(!file.replaceAll(with: [point(70)]))
    #expect(file.load().isEmpty)
}
