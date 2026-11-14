import AppKit
import SwiftUI

struct AboutTab: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    private enum Links {
        static let website = URL(string: "https://kombucha.kuksov.dev")!
        static let issues = URL(string: "https://github.com/askuksov/kombucha/issues")!
        static let documentation = URL(string: "https://github.com/askuksov/kombucha#readme")!
        static let source = URL(string: "https://github.com/askuksov/kombucha")!
    }

    private var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return Copy.version(info["CFBundleShortVersionString"] as? String ?? "")
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "Kombucha")
                            .font(.title2.weight(.semibold))
                        Text(version)
                        Text(Copy.tagline)
                            .foregroundStyle(.secondary)
                    }
                }
                // Long translations do not fit four links on one line; they then split into two.
                ViewThatFits(in: .horizontal) {
                    HStack {
                        websiteAndIssues
                        separator
                        documentationAndSource
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack { websiteAndIssues }
                        HStack { documentationAndSource }
                    }
                }
                Text(Copy.license)
                // Dev only: the Welcome toggles duplicate the General tab. Re-enable to test the window.
                // Button(Copy.showWelcomeWindow) { openWindow(id: WelcomeView.windowID) }
            }
            if let updates = model.updates {
                UpdateSection(updates: updates)
            }
        }
        .formStyle(.grouped)
    }

    private var separator: some View {
        Text(verbatim: "·").accessibilityHidden(true)
    }

    @ViewBuilder
    private var websiteAndIssues: some View {
        Link(Copy.website, destination: Links.website)
        separator
        Link(Copy.reportIssue, destination: Links.issues)
    }

    @ViewBuilder
    private var documentationAndSource: some View {
        Link(Copy.documentation, destination: Links.documentation)
        separator
        Link(Copy.sourceCode, destination: Links.source)
    }
}

private struct UpdateSection: View {
    let updates: UpdateController

    /// Nothing is said until a check ran or a newer version is stored.
    private var line: String? {
        switch updates.state {
        case .idle: nil
        case .checking: Copy.checking
        case .upToDate: Copy.updateUpToDate
        case .available(let version): Copy.updateAvailable(version)
        case .failed: Copy.updateFailed
        }
    }

    private var isAvailable: Bool { updates.newerVersion != nil }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                if let line {
                    Text(line)
                }
                if isAvailable {
                    Text(Copy.updateHomebrewHint)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                HStack {
                    Spacer()
                    if isAvailable {
                        Button(Copy.viewRelease) { updates.openReleasePage() }
                    }
                    Button(Copy.checkForUpdates) { Task { await updates.checkNow() } }
                        .disabled(updates.state == .checking)
                }
            }
            .accessibilityElement(children: .contain)
        }
    }
}
