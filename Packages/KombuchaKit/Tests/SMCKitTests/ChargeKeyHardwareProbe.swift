import Foundation
import Testing
@testable import SMCKit

// Reads the real key; runs only with KOMBUCHA_HARDWARE=1.
@Test(.enabled(if: ProcessInfo.processInfo.environment["KOMBUCHA_HARDWARE"] == "1"))
func readChargeKey() throws {
    let bytes = try ChargeSwitch.arm().currentBytes()
    let hex = bytes.map { String(format: "0x%02x", $0) }.joined(separator: " ")
    print("CHTE = \(hex), allowed: \(String(describing: ChargeFlag.isAllowed(bytes)))")
    #expect(bytes.count == ChargeFlag.byteCount)
}

// Reads the adapter key without writing it; runs only with KOMBUCHA_HARDWARE=1.
@Test(.enabled(if: ProcessInfo.processInfo.environment["KOMBUCHA_HARDWARE"] == "1"))
func readAdapterKey() throws {
    let enabled = try AdapterSwitch.arm().currentlyEnabled()
    print("CHIE enabled: \(String(describing: enabled))")
    #expect(enabled != nil)
}
