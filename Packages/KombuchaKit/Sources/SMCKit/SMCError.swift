public enum SMCError: Error, Equatable, Sendable {
    case serviceNotFound
    case connectionFailed(Int32)
    case callFailed(Int32)
    case keyNotFound
    case smcResult(UInt8)
    case unexpectedSize(expected: Int, actual: Int)
    case permissionDenied
    case writeNotApplied(wrote: [UInt8], read: [UInt8])
}
