import Testing
@testable import SMCKit

@Test func chargeInhibitKeyCode() {
    #expect(SMCKey.chargeInhibit == 0x4348_5445)
    #expect(SMCKey.code("CHTE") == 0x4348_5445)
}

@Test func allowWritesZeroAndInhibitWritesOne() {
    #expect(ChargeFlag.payload(allow: true) == [0x00, 0, 0, 0])
    #expect(ChargeFlag.payload(allow: false) == [0x01, 0, 0, 0])
}

@Test(arguments: [
    ([UInt8]([0x00, 0, 0, 0]), Bool?.some(true)),
    ([0x01, 0, 0, 0], Bool?.some(false)),
    ([0x02, 0, 0, 0], nil),
    ([0x01, 0, 0, 1], nil),
    ([0x01], nil),
])
func decodesOnlyTheTwoFlags(bytes: [UInt8], expected: Bool?) {
    #expect(ChargeFlag.isAllowed(bytes) == expected)
}
