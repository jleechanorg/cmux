import AppKit
import Foundation

/// Tracks the macOS screensaver's running state via passive
/// `NSWorkspace` notifications, replacing the previous approach of
/// enumerating running applications to find
/// `com.apple.ScreenSaver.Engine`.
///
/// ## Why this exists
///
/// `NSWorkspace.shared.runningApplications` triggers the macOS
/// **App Management** privacy prompt
/// ("X would like to access data from other apps"). For cmux DEV builds
/// the App Management permission is keyed to bundle ID, and
/// `scripts/reload.sh --tag <name>` derives a unique bundle ID per tag
/// (line 519: `BUNDLE_ID="com.cmuxterm.app.debug.${TAG_ID}"`). That meant
/// every fresh tagged build re-prompted the user once the first
/// phone-forwarding notification reached the screensaver signal.
///
/// The fix subscribes to `NSWorkspace.screensaverDidStartNotification`
/// and `NSWorkspace.screensaverDidStopNotification`, which are passive
/// system events. They never enumerate apps and never trigger App
/// Management TCC.
///
/// ## Default state and edge case
///
/// `isRunning` is initialized to `false` (screensaver not running). If the
/// screensaver was already running when cmux launched, we won't detect
/// it until the user wakes the screen and a stop notification fires. For
/// the phone-forwarding "only when away" heuristic this means one push
/// may leak to the phone before we re-detect — a deliberate trade-off
/// for not enumerating apps at launch.
@MainActor
final class ScreensaverStateTracker {
    /// Single source of truth, owned by the main actor (subscribing to
    /// AppKit notifications is a main-actor operation).
    static let shared = ScreensaverStateTracker()

    /// Last observed screensaver running state. `true` after a
    /// `screensaverDidStartNotification`, `false` after
    /// `screensaverDidStopNotification`, `false` before either fires.
    private(set) var isRunning: Bool = false

    /// Strong refs to the observer tokens — `addObserver` returns
    /// `NSObjectProtocol` tokens that must outlive the closure
    /// subscriptions.
    private var observers: [NSObjectProtocol] = []

    private init() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(
            forName: NSWorkspace.screensaverDidStartNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isRunning = true
        })
        observers.append(center.addObserver(
            forName: NSWorkspace.screensaverDidStopNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isRunning = false
        })
    }

    deinit {
        let center = NSWorkspace.shared.notificationCenter
        for observer in observers {
            center.removeObserver(observer)
        }
    }
}
