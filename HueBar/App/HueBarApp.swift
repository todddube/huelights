//
//  HueBarApp.swift
//  HueBar · HueBar
//
//  App entry point: a menu bar extra whose icon reflects whether any light is on.
//

import AppKit
import SwiftUI

/// The app: a single window-style menu bar extra sharing one ``BridgeStore``.
@main
struct HueBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store: BridgeStore

    init() {
        // Start here rather than in a view's `.task`: a `.window` MenuBarExtra re-runs view
        // tasks on every open, and the icon should reflect light state before the first click.
        let store = BridgeStore()
        store.start()
        _store = State(initialValue: store)
    }

    var body: some Scene {
        MenuBarExtra {
            RootView()
                .environment(store)
        } label: {
            Label("HueBar", systemImage: store.anyLightOn ? "lightbulb.fill" : "lightbulb")
                .labelStyle(.iconOnly)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Keeps the app out of the Dock even when launched outside a bundle (for example `swift run`).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
