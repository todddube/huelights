//
//  RootView.swift
//  HueBar · HueBar
//
//  Chooses between the pairing flow and the control panel.
//

import SwiftUI

/// Top-level popup content; switches to the control panel as soon as a pairing exists.
struct RootView: View {
    @Environment(BridgeStore.self) private var store

    var body: some View {
        Group {
            if store.isPaired {
                ControlPanelView()
            } else {
                SetupView()
            }
        }
        .frame(width: 380)
    }
}
