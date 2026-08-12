import CodexAwakeCore
import Foundation

final class HelperService: NSObject, ClosedLidHelperXPCProtocol {
    private let store: LeaseStore

    init(store: LeaseStore) {
        self.store = store
    }

    func status(withReply reply: @escaping (Bool, TimeInterval, String?) -> Void) {
        store.status(reply: reply)
    }

    func acquireLease(
        token: String,
        duration: TimeInterval,
        withReply reply: @escaping (Bool, TimeInterval, String?) -> Void
    ) {
        store.acquire(token: token, duration: duration, reply: reply)
    }

    func renewLease(
        token: String,
        duration: TimeInterval,
        withReply reply: @escaping (Bool, TimeInterval, String?) -> Void
    ) {
        store.renew(token: token, duration: duration, reply: reply)
    }

    func releaseLease(token: String, withReply reply: @escaping (Bool, TimeInterval, String?) -> Void) {
        store.release(token: token, reply: reply)
    }
}

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let service: HelperService

    init(service: HelperService) {
        self.service = service
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection)
        -> Bool
    {
        connection.exportedInterface = NSXPCInterface(with: ClosedLidHelperXPCProtocol.self)
        connection.exportedObject = service
        connection.activate()
        return true
    }
}
