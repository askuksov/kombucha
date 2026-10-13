import AppIntents
import KombuchaCore

struct GetBatteryStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Battery Status"

    @Dependency private var gateway: any EngineGateway

    func perform() async throws -> some IntentResult & ReturnsValue<BatteryStatusEntity> & ProvidesDialog {
        let (entity, dialog) = try await Self.run(gateway)
        return .result(value: entity, dialog: IntentDialog(stringLiteral: dialog))
    }

    static func run(_ gateway: any EngineGateway) async throws -> (BatteryStatusEntity, String) {
        let status = try await gateway.status()
        return (BatteryStatusEntity(status), Copy.statusDialog(status))
    }
}

struct SetBatteryProtectionIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Set Battery Protection"

    @Parameter(title: "Battery Protection") var value: Bool
    @Dependency private var gateway: any EngineGateway

    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        .result(value: try await gateway.setProtection(value))
    }
}

struct SetChargeLimitIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Charge Limit"

    @Parameter(title: "Stop charging at", inclusiveRange: (55, 95)) var stopAt: Int
    @Parameter(title: "Resume charging at", inclusiveRange: (40, 85)) var resumeAt: Int
    @Dependency private var gateway: any EngineGateway

    func perform() async throws -> some IntentResult & ReturnsValue<ChargeLimitEntity> {
        .result(value: ChargeLimitEntity(try await gateway.setThresholds(stop: stopAt, resume: resumeAt)))
    }
}

struct StartFullChargeIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Full Charge"

    @Dependency private var gateway: any EngineGateway

    func perform() async throws -> some IntentResult {
        try await gateway.startFullCharge()
        return .result()
    }
}

struct StopFullChargeIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Full Charge"

    @Dependency private var gateway: any EngineGateway

    func perform() async throws -> some IntentResult {
        try await gateway.stopFullCharge()
        return .result()
    }
}

/// The toggle form of Start and Stop Full Charge, for a control; not listed in Shortcuts.
struct SetFullChargeIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Full Charge"
    static let isDiscoverable = false

    @Parameter(title: "Full Charge") var value: Bool
    @Dependency private var gateway: any EngineGateway

    func perform() async throws -> some IntentResult {
        try await Self.apply(value, through: gateway)
        return .result()
    }

    static func apply(_ on: Bool, through gateway: any EngineGateway) async throws {
        if on {
            try await gateway.startFullCharge()
        } else {
            try await gateway.stopFullCharge()
        }
    }
}
