//
//  IdleTimer.swift
//  HueBar · HueBar
//
//  Popup idle timeout: the saved setting and the restartable one-shot timer behind it.
//

import Foundation

/// Where the popup idle timeout is stored and what it defaults to.
enum PopoverTimeout {
    /// `UserDefaults` key shared by ``current`` and the settings menu's `@AppStorage`.
    static let defaultsKey = "popoverTimeoutSeconds"
    /// Seconds of inactivity before the popup closes by itself.
    static let defaultSeconds: Double = 30
    /// Choices offered in the settings menu; `0` means never.
    static let choices: [(label: String, seconds: Double)] = [
        ("15 seconds", 15), ("30 seconds", 30), ("1 minute", 60), ("5 minutes", 300), ("Never", 0),
    ]

    /// The saved timeout in seconds, or the default when nothing has been chosen.
    static var current: Double {
        UserDefaults.standard.object(forKey: defaultsKey) as? Double ?? defaultSeconds
    }
}

/// Calls `onExpire` once `seconds` pass without another ``arm(after:)``.
@MainActor
final class IdleTimer {
    private var task: Task<Void, Never>?
    private let onExpire: @MainActor () -> Void

    init(onExpire: @escaping @MainActor () -> Void) {
        self.onExpire = onExpire
    }

    /// Restarts the countdown. A value of zero or less disables the timeout.
    func arm(after seconds: TimeInterval) {
        task?.cancel()
        task = nil
        guard seconds > 0 else { return }
        task = Task { [onExpire] in
            // Cancellation is the normal way a restart or stop ends this sleep.
            guard (try? await Task.sleep(for: .seconds(seconds))) != nil else { return }
            // A cancel that lands after the sleep finished but before this resumes does not make
            // the sleep throw; without this check a stopped timer could still close the popup.
            guard !Task.isCancelled else { return }
            onExpire()
        }
    }

    /// Cancels any pending countdown without firing.
    func stop() {
        task?.cancel()
        task = nil
    }
}
