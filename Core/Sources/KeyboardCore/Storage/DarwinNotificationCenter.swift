import CoreFoundation
import Foundation

private let glassTypeDarwinNotificationCallback: CFNotificationCallback = { _, observer, _, _, _ in
    guard let observer else { return }
    Unmanaged<DarwinNotificationObserver>.fromOpaque(observer)
        .takeUnretainedValue()
        .deliver()
}

/// Retained token for a Darwin notification subscription.
public final class DarwinNotificationObserver: @unchecked Sendable {
    private let notificationName: CFNotificationName
    private let lock = NSLock()
    private var handler: (@Sendable () -> Void)?
    private let center = CFNotificationCenterGetDarwinNotifyCenter()

    fileprivate init(name: String, handler: @escaping @Sendable () -> Void) {
        notificationName = CFNotificationName(rawValue: name as CFString)
        self.handler = handler
        CFNotificationCenterAddObserver(center, Unmanaged.passUnretained(self).toOpaque(),
                                        glassTypeDarwinNotificationCallback,
                                        notificationName.rawValue, nil, .deliverImmediately)
    }

    fileprivate func deliver() {
        lock.lock(); let callback = handler; lock.unlock()
        callback?()
    }

    public func cancel() {
        lock.lock()
        guard handler != nil else { lock.unlock(); return }
        handler = nil
        lock.unlock()
        CFNotificationCenterRemoveObserver(center, Unmanaged.passUnretained(self).toOpaque(), notificationName.rawValue, nil)
    }

    deinit { cancel() }
}

/// Posts/observes process-independent notifications; payloads stay in the
/// shared container and notifications only signal that data should be re-read.
public enum DarwinNotificationCenter {
    public static let settingsUpdatedName = "com.glasstype.shared.settings-updated"

    public static func post(name: String) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFNotificationName(rawValue: name as CFString), nil, nil, true)
    }

    @discardableResult
    public static func observe(name: String, handler: @escaping @Sendable () -> Void) -> DarwinNotificationObserver {
        DarwinNotificationObserver(name: name, handler: handler)
    }
}
