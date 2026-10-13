import Testing
@testable import SMCKit

@Test func adapterInhibitKeyCode() {
    #expect(SMCKey.adapterInhibit == 0x4348_4945)
    #expect(SMCKey.code("CHIE") == 0x4348_4945)
}

@Test func onWritesZeroAndOffWritesEight() {
    #expect(AdapterFlag.byteCount == 1)
    #expect(AdapterFlag.payload(enabled: true) == [0x00])
    #expect(AdapterFlag.payload(enabled: false) == [0x08])
}

@Test(arguments: [
    ([UInt8]([0x00]), Bool?.some(true)),
    ([0x08], Bool?.some(false)),
    ([0x01], nil),
    ([0x00, 0x00], nil),
    ([], nil),
])
func decodesOnlyTheTwoAdapterValues(bytes: [UInt8], expected: Bool?) {
    #expect(AdapterFlag.isEnabled(bytes) == expected)
}
