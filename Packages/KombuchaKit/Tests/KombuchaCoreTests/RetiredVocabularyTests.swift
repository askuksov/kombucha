import Foundation
import Testing

/// Words the port used to say and does not any more.
///
/// An outside charge manager is an external battery manager, never a competitor (KOM-56, KOM-60). A rename
/// destroys its own guard: once the word is gone, any check that it is absent from the renamed spot passes for
/// every input. This one fails when the word comes back anywhere in the port — app, helper, package, tests.
/// This file has to name the word to guard it, so it is the one source the scan skips.
private let retired = ["competi", "compete"]

private let thisFile = URL(filePath: #filePath).lastPathComponent

/// `Packages/KombuchaKit/Tests/KombuchaCoreTests/<this file>` → the repository root.
private let repositoryRoot = URL(filePath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

private func swiftSources() -> [URL] {
    let roots = ["Kombucha", "KombuchaHelper", "KombuchaTests", "Packages/KombuchaKit/Sources", "Packages/KombuchaKit/Tests"]
    return roots.flatMap { root in
        let files = FileManager.default.enumerator(at: repositoryRoot.appending(path: root),
                                                   includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? []
        return files.filter { ["swift", "xcstrings"].contains($0.pathExtension) && $0.lastPathComponent != thisFile }
    }
}

@Test func theScanReadsTheWholePort() {
    // A scan that stopped finding files would pass silently, so it must see the port and its known corners.
    let names = Set(swiftSources().map(\.lastPathComponent))
    #expect(names.count >= 70)
    #expect(names.isSuperset(of: ["Engine.swift", "PanelView.swift", "main.swift", "ExternalBatteryManagers.swift", "Localizable.xcstrings"]))
    // An empty list would generate zero cases below, and zero cases report as passing.
    #expect(!retired.isEmpty)
}

@Test(arguments: retired)
func noSourceSaysTheRetiredWord(stem: String) throws {
    var hits: [String] = []
    for url in swiftSources() {
        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false)
        for (index, line) in lines.enumerated() where line.lowercased().contains(stem) {
            hits.append("\(url.lastPathComponent):\(index + 1)")
        }
    }
    #expect(hits.isEmpty, "the word came back: \(hits)")
}
