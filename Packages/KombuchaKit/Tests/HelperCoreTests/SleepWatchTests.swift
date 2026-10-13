import Testing
@testable import HelperCore

// The numbers are IOMessage.h's iokit_common_msg() values, written out so the tests pin them.

@Test func theHelperAllowsASleepQueryAtOnce() {
    #expect(SleepWatch.response(to: 0xE000_0270) == .allow)  // can system sleep
}

@Test func aComingSleepSwitchesTheAdapterOnFirst() {
    #expect(SleepWatch.response(to: 0xE000_0280) == .willSleep)  // system will sleep
}

@Test func aFullWakeLiftsTheRefusal() {
    #expect(SleepWatch.response(to: 0xE000_0300) == .woke)  // system has powered on
}

@Test func otherPowerMessagesAreIgnoredByTheHelper() {
    #expect(SleepWatch.response(to: 0xE000_0290) == .ignore)  // system will not sleep
    #expect(SleepWatch.response(to: 0xE000_0320) == .ignore)  // system will power on (also dark wakes)
}
