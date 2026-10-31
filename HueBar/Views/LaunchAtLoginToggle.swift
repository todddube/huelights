//
//  LaunchAtLoginToggle.swift
//  HueBar · HueBar
//
//  Menu toggle backed by SMAppService; only works when running from a real .app bundle.
//

import ServiceManagement
import SwiftUI

/// Registers or unregisters the app as a login item, reverting the toggle if that fails.
struct LaunchAtLoginToggle: View {
    @Environment(BridgeStore.self) private var store
    @State private var isEnabled = Self.isRegistered

    /// True once registered, including while the user still has to approve it in System Settings.
    private static var isRegistered: Bool {
        let status = SMAppService.mainApp.status
        return status == .enabled || status == .requiresApproval
    }

    var body: some View {
        Toggle("Launch at Login", isOn: $isEnabled)
            .onAppear { isEnabled = Self.isRegistered }
            .onChange(of: isEnabled) { _, enabled in
                // Also fires when this view reverts the toggle after a failure; nothing to do then.
                guard enabled != Self.isRegistered else { return }
                do {
                    if enabled {
                        try SMAppService.mainApp.register()
                        if SMAppService.mainApp.status == .requiresApproval {
                            store.report("Allow HueBar in System Settings › General › Login Items.")
                            SMAppService.openSystemSettingsLoginItems()
                        }
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    // Registration fails when the binary is not inside an app bundle, e.g. `swift run`.
                    store.report("Launch at Login: \(error.localizedDescription)")
                    isEnabled = Self.isRegistered
                }
            }
    }
}
