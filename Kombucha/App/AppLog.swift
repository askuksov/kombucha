import os

enum AppLog {
    static let engine = Logger(subsystem: "dev.kuksov.kombucha", category: "engine")
    static let helper = Logger(subsystem: "dev.kuksov.kombucha", category: "helper")
    static let ui = Logger(subsystem: "dev.kuksov.kombucha", category: "ui")
    static let history = Logger(subsystem: "dev.kuksov.kombucha", category: "history")
    static let update = Logger(subsystem: "dev.kuksov.kombucha", category: "update")
}
