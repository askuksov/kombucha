import AppIntents

/// Why an intent did not do what it was asked. Every sentence is one the panel already uses.
enum GatewayError: Error, Equatable {
    case notReady
    case unsupported
    case gate(String)
    case failed(ActionFailure)

    var message: String {
        switch self {
        case .notReady: Copy.intentNotReady
        case .unsupported: Copy.unsupportedHeading
        case .gate(let heading): heading
        case .failed(let failure): Copy.failure(failure)
        }
    }
}

extension GatewayError: CustomLocalizedStringResourceConvertible {
    /// `message` is localized already; the lookup finds the same text under its own key or falls back to it.
    var localizedStringResource: LocalizedStringResource { LocalizedStringResource(stringLiteral: message) }
}
