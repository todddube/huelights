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
final class StatusItemController: NSObject {
    private let store: BridgeStore
    private let statusItem: NSStatusItem
    private let popover = NSPopover()

    init(store: BridgeStore) {
        self.store = store
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        let hosting = NSHostingController(rootView: RootView().environment(store))
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.animates = true

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

    // MARK: - Popover

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            Task { await store.resync() }
            // Transient popovers only close on outside clicks while the app is active.
            NSApp.activate()
        }
    }
}
