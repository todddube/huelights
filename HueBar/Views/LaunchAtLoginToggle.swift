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
    @State private var isEnabled = SMAppService.mainApp.status == .enabled
    @State private var errorMessage: String?

    var body: some View {
        Toggle("Launch at Login", isOn: $isEnabled)
            .onChange(of: isEnabled) { _, enabled in
                do {
                    if enabled {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                    errorMessage = nil
                } catch {
                    // Registration fails when the binary is not inside an app bundle, e.g. `swift run`.
                    errorMessage = error.localizedDescription
                    isEnabled = SMAppService.mainApp.status == .enabled
                }
            }
        if let errorMessage {
            Text(errorMessage).font(.caption)
        }
    }
}
