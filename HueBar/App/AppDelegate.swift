//
//  AppDelegate.swift
//  HueBar · HueBar
//
//  Owns the model and the status item for the life of the process.
//

import AppKit

/// Application delegate: hides the Dock icon and creates the status item.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: BridgeStore?
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Keep the app out of the Dock even when launched outside a bundle (for example `swift run`).
        NSApp.setActivationPolicy(.accessory)
        let store = BridgeStore()
        store.start()
        self.store = store
        statusItem = StatusItemController(store: store)
    }
}
