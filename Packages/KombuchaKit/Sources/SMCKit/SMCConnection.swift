import CSMC
import IOKit

final class SMCConnection: @unchecked Sendable {
    private let connection: io_connect_t

    private static let kernelIndex: UInt32 = 2
    private static let readBytes: UInt8 = 5
    private static let writeBytes: UInt8 = 6
    private static let readKeyInfo: UInt8 = 9
    private static let keyNotFound: UInt8 = 0x84
    private static let notPrivileged = Int32(bitPattern: 0xE000_02C1)

    init() throws {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw SMCError.serviceNotFound }
        defer { IOObjectRelease(service) }

        var connection: io_connect_t = 0
        let result = IOServiceOpen(service, csmc_task_self(), 0, &connection)
        guard result == KERN_SUCCESS else { throw SMCError.connectionFailed(result) }
        self.connection = connection
    }

    deinit {
        IOServiceClose(connection)
    }

    func keySize(_ key: UInt32) throws -> Int {
        var input = SMCParamStruct()
        input.key = key
        input.data8 = Self.readKeyInfo
        return Int(try call(input).keyInfo.dataSize)
    }

    func read(_ key: UInt32) throws -> [UInt8] {
        let size = try keySize(key)
        guard size <= 32 else { throw SMCError.unexpectedSize(expected: 32, actual: size) }
        var input = SMCParamStruct()
        input.key = key
        input.keyInfo.dataSize = UInt32(size)
        input.data8 = Self.readBytes
        return Array(try call(input).byteArray.prefix(size))
    }

    /// The SMC accepts a short write and keeps the rest of the key, so the size must match exactly.
    func write(_ key: UInt32, bytes: [UInt8]) throws {
        let size = try keySize(key)
        guard size <= 32 else { throw SMCError.unexpectedSize(expected: 32, actual: size) }
        guard size == bytes.count else { throw SMCError.unexpectedSize(expected: bytes.count, actual: size) }
        var input = SMCParamStruct()
        input.key = key
        input.keyInfo.dataSize = UInt32(size)
        input.data8 = Self.writeBytes
        input.setBytes(bytes)
        _ = try call(input)
    }

    private func call(_ input: SMCParamStruct) throws -> SMCParamStruct {
        var input = input
        var output = SMCParamStruct()
        var outputSize = MemoryLayout<SMCParamStruct>.stride
        let result = IOConnectCallStructMethod(
            connection, Self.kernelIndex,
            &input, MemoryLayout<SMCParamStruct>.stride,
            &output, &outputSize
        )
        if result == Self.notPrivileged { throw SMCError.permissionDenied }
        guard result == KERN_SUCCESS else { throw SMCError.callFailed(result) }
        if output.result == Self.keyNotFound { throw SMCError.keyNotFound }
        guard output.result == 0 else { throw SMCError.smcResult(output.result) }
        return output
    }
}

extension SMCParamStruct {
    var byteArray: [UInt8] {
        withUnsafeBytes(of: bytes) { Array($0) }
    }

    mutating func setBytes(_ values: [UInt8]) {
        withUnsafeMutableBytes(of: &bytes) { buffer in
            buffer.copyBytes(from: values.prefix(buffer.count))
        }
    }
}
