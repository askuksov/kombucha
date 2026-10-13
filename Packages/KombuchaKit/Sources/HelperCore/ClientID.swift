import Foundation

/// Which XPC connection a command came over. Two live connections never share one.
public struct ClientID: Hashable, Sendable {
    private let identifier: ObjectIdentifier

    public init(_ connection: NSXPCConnection) {
        self.init(object: connection)
    }

    /// Tests only: any object that stays alive while its identifier is in use.
    init(object: AnyObject) {
        identifier = ObjectIdentifier(object)
    }
}
