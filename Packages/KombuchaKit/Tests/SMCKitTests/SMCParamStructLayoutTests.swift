import CSMC
import Testing

@Test func paramStructMatchesTheUserClientLayout() {
    #expect(MemoryLayout<SMCParamStruct>.size == 80)
    // SMCConnection.call passes .stride to IOKit, not .size.
    #expect(MemoryLayout<SMCParamStruct>.stride == 80)
    #expect(MemoryLayout<SMCParamStruct>.offset(of: \.key) == 0)
    #expect(MemoryLayout<SMCParamStruct>.offset(of: \.vers) == 4)
    #expect(MemoryLayout<SMCParamStruct>.offset(of: \.pLimitData) == 12)
    #expect(MemoryLayout<SMCParamStruct>.offset(of: \.keyInfo) == 28)
    #expect(MemoryLayout<SMCParamStruct>.offset(of: \.result) == 40)
    #expect(MemoryLayout<SMCParamStruct>.offset(of: \.status) == 41)
    #expect(MemoryLayout<SMCParamStruct>.offset(of: \.data8) == 42)
    #expect(MemoryLayout<SMCParamStruct>.offset(of: \.data32) == 44)
    #expect(MemoryLayout<SMCParamStruct>.offset(of: \.bytes) == 48)
}
