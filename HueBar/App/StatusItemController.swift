//
//  StatusItemController.swift
//  HueBar · HueBar
//
//  Menu bar status item whose popover resizes to the SwiftUI content it hosts.
//

import AppKit
import Observation
import SwiftUI

/// Drives the status item and its popover.
///
/// SwiftUI's `MenuBarExtra(.window)` sizes its panel once and never shrinks it when the
/// content gets shorter, so switching from a long Lights list to a short Rooms list leaves
/// empty space. An `NSPopover` tracks its content controller's `preferredContentSize`, which
/// `NSHostingController` keeps current when asked to, so the popup follows the content both ways.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let store: BridgeStore
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var idleTimer: IdleTimer?
    private var activityMonitor: Any?
    private var isMenuTracking = false

    init(store: BridgeStore) {
        self.store = store
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        let hosting = NSHostingController(rootView: RootView().environment(store))
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        idleTimer = IdleTimer { [weak self] in self?.idleExpired() }

        // Lets macOS remember where the user dragged the item in the menu bar.
        statusItem.autosaveName = "HueBarStatusItem"
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.toolTip = "HueBar"
        }
        updateIcon()
        observeLightState()
        observeWake()
        observeIdleInputs()
    }

    // MARK: - Wake

    /// Resyncs shortly after wake; the network and the bridge need a moment to come back.
    private func observeWake() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let store = self?.store else { return }
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    await store.resync()
                }
            }
        }
    }

    // MARK: - Icon

    /// Keeps the menu bar icon in step with `anyLightOn` via Observation's one-shot tracking.
    ///
    /// `anyLightOn` is computed, so this fires on every `lights` mutation, not only when the
    /// result flips. `onChange` runs during `willSet`, so the refresh and re-registration are
    /// deferred to a main-actor task that reads the settled value.
    private func observeLightState() {
        withObservationTracking {
            _ = store.anyLightOn
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.updateIcon()
                self?.observeLightState()
            }
        }
    }

    private func updateIcon() {
        let name = store.anyLightOn ? "lightbulb.fill" : "lightbulb"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "HueBar")?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .medium))
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.setAccessibilityLabel(store.anyLightOn ? "HueBar, lights on" : "HueBar, lights off")
    }

    // MARK: - Idle timeout

    /// Any interaction inside the app restarts the countdown, so dragging a slider or typing a
    /// name never gets cut off; only a popup left sitting open closes itself.
    private func startIdleTracking() {
        idleTimer?.arm(after: PopoverTimeout.current)
        guard activityMonitor == nil else { return }
        let events: NSEvent.EventTypeMask = [
            .leftMouseDown, .rightMouseDown, .leftMouseDragged, .scrollWheel, .keyDown,
        ]
        activityMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            MainActor.assumeIsolated {
                self?.idleTimer?.arm(after: PopoverTimeout.current)
            }
            return event
        }
    }

    /// Closes the popup unless the user is mid-gesture. Local monitors do not see events consumed by
    /// nested tracking loops (slider drags, open menus), so those are checked here instead.
    private func idleExpired() {
        if NSEvent.pressedMouseButtons != 0 || isMenuTracking {
            idleTimer?.arm(after: PopoverTimeout.current)
        } else {
            popover.performClose(nil)
        }
    }

    /// Picking a new timeout happens inside menu tracking, which the monitor cannot see, and
    /// leaving a menu is activity too, so both restart the countdown.
    private func observeIdleInputs() {
        let center = NotificationCenter.default
        center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.isMenuTracking = true }
        }
        center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.isMenuTracking = false; self?.rearmIfShown() }
        }
        center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rearmIfShown() }
        }
    }

    private func rearmIfShown() {
        if popover.isShown { idleTimer?.arm(after: PopoverTimeout.current) }
    }

    private func stopIdleTracking() {
        idleTimer?.stop()
        if let monitor = activityMonitor {
            NSEvent.removeMonitor(monitor)
            activityMonitor = nil
        }
    }

    // MARK: - Popover

    /// Every close path (toggle, outside click, idle expiry) ends here, so the monitor goes too.
    func popoverDidClose(_ notification: Notification) {
        stopIdleTracking()
    }

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            Task { await store.resync() }
            startIdleTracking()
            // Transient popovers only close on outside clicks while the app is active.
            NSApp.activate()
        }
    }
}
