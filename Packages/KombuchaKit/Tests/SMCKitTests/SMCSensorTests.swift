import Testing
@testable import SMCKit

@Test func theKeysAreTheFourCharacterCodes() {
    #expect(SMCSensor.systemPower == 0x5053_5452)   // "PSTR"
    #expect(SMCSensor.adapterPower == 0x5044_5452)  // "PDTR"
}

@Test func fourLittleEndianBytesAreAFloat() {
    #expect(SMCSensor.decodeFloat([0x00, 0x00, 0xA8, 0x40]) == 5.25)
    #expect(SMCSensor.decodeFloat([0, 0, 0, 0]) == 0)
}

@Test(arguments: [[UInt8](), [0x00], [0x00, 0x00, 0xA8], [0x00, 0x00, 0xA8, 0x40, 0x00]])
func aValueOfAnotherSizeIsNotAFloat(bytes: [UInt8]) {
    #expect(SMCSensor.decodeFloat(bytes) == nil)
}

@Test func aNotANumberPatternDecodesAndIsLeftToTheCaller() throws {
    let value = try #require(SMCSensor.decodeFloat([0x00, 0x00, 0xC0, 0x7F]))
    #expect(value.isNaN)
}
