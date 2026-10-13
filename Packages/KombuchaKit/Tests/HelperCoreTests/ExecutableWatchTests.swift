import Foundation
import Testing
@testable import HelperCore

private func temporaryFile() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("watch-\(UUID().uuidString)")
    try Data("old".utf8).write(to: url)
    return url
}

private func watch(_ url: URL, _ changes: Occurrences) throws -> ExecutableWatch {
    try ExecutableWatch(path: url.path, queue: DispatchQueue(label: "dev.kuksov.kombucha.test.watch")) {
        changes.record()
    }
}

@Test func deletingTheFileFires() throws {
    let url = try temporaryFile()
    let changes = Occurrences()
    let watcher = try watch(url, changes)

    try FileManager.default.removeItem(at: url)

    #expect(changes.wait(seconds: 2))
    #expect(changes.count == 1)
    withExtendedLifetime(watcher) {}
}

@Test func renamingTheFileFires() throws {
    let url = try temporaryFile()
    let moved = url.appendingPathExtension("moved")
    defer { try? FileManager.default.removeItem(at: moved) }
    let changes = Occurrences()
    let watcher = try watch(url, changes)

    try FileManager.default.moveItem(at: url, to: moved)

    #expect(changes.wait(seconds: 2))
    withExtendedLifetime(watcher) {}
}

@Test func manyWritesFireOnce() throws {
    let url = try temporaryFile()
    defer { try? FileManager.default.removeItem(at: url) }
    let changes = Occurrences()
    let watcher = try watch(url, changes)

    let handle = try FileHandle(forWritingTo: url)
    try handle.write(contentsOf: Data("new".utf8))
    try handle.synchronize()
    #expect(changes.wait(seconds: 2))
    try handle.write(contentsOf: Data("more".utf8))
    try handle.close()

    #expect(!changes.wait(seconds: 0.3))
    #expect(changes.count == 1)
    withExtendedLifetime(watcher) {}
}

@Test func anExtendedAttributeIsNotAChange() throws {
    let url = try temporaryFile()
    defer { try? FileManager.default.removeItem(at: url) }
    let changes = Occurrences()
    let watcher = try watch(url, changes)

    let value = Array("1".utf8)
    #expect(setxattr(url.path, "dev.kuksov.kombucha.test", value, value.count, 0, 0) == 0)

    #expect(!changes.wait(seconds: 0.5))
    #expect(changes.count == 0)
    withExtendedLifetime(watcher) {}
}

@Test func aMissingFileCannotBeWatchedAndSaysWhy() {
    #expect(throws: ExecutableWatch.OpenFailure(code: ENOENT)) {
        _ = try ExecutableWatch(path: "/nonexistent/kombucha-helper", queue: .global()) {}
    }
    #expect(ExecutableWatch.OpenFailure(code: ENOENT).reason == "No such file or directory")
}
