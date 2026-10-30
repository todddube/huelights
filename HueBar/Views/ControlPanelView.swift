//
//  ControlPanelView.swift
//  HueBar · HueBar
//
//  The main popup once paired: status header, tab picker and the selected tab's content.
//

import HueKit
import SwiftUI

/// The paired-state popup: connection header, tab picker, error banner and footer menu.
struct ControlPanelView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case lights = "Lights"
        case rooms = "Rooms"
        case scenes = "Scenes"
        case bridge = "Bridge"

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .lights: "lightbulb"
            case .rooms: "square.split.bottomrightquarter"
            case .scenes: "theatermasks"
            case .bridge: "server.rack"
            }
        }
    }

    @Environment(BridgeStore.self) private var store
    @AppStorage("selectedTab") private var selectedTab: Tab = .lights
    @State private var showingAbout = false
    @State private var contentHeight: CGFloat = 0

    /// Tallest the scrolling area may grow before it scrolls: the screen minus menu bar and chrome.
    private var maxContentHeight: CGFloat {
        let screen = NSScreen.main?.visibleFrame.height ?? 800
        return max(200, screen - 220)
    }

    var body: some View {
        if showingAbout {
            AboutView { showingAbout = false }
        } else {
            panel
        }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)

            Picker("Section", selection: $selectedTab) {
                ForEach(Tab.allCases) { tab in
                    Label(tab.rawValue, systemImage: tab.symbol).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 14)
            .padding(.bottom, 8)

            Divider()

            // Size the popup to its content so short lists never scroll; only fall back to
            // scrolling when the list is taller than the screen allows.
            ScrollView {
                content
                    .padding(14)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .frame(height: min(max(contentHeight, 60), maxContentHeight))
            .animation(.easeInOut(duration: 0.15), value: contentHeight)

            if let message = store.lastError {
                Divider()
                errorBanner(message)
            }

            Divider()
            footer
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
        }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 9, height: 9)
                .padding(.leading, 2)
            VStack(alignment: .leading, spacing: 1) {
                Text(store.paired?.name ?? "Hue Bridge").font(.headline)
                Text(statusText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if store.isRefreshing {
                ProgressView().controlSize(.small)
            }
            Button {
                store.setAllLights(on: !store.anyLightOn)
            } label: {
                Image(systemName: store.anyLightOn ? "power.circle.fill" : "power.circle")
                    .font(.title3)
            }
            .buttonStyle(.borderless)
            .help(store.anyLightOn ? "Turn all lights off" : "Turn all lights on")
            .disabled(store.connection != .connected)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.connection {
        case .failed(let message) where store.lights.isEmpty:
            ContentUnavailableView {
                Label("Can’t reach the bridge", systemImage: "wifi.slash")
            } description: {
                Text(message)
            } actions: {
                Button("Retry") { Task { await store.connect() } }
                Button("Forget Bridge", role: .destructive) { store.forgetBridge() }
            }
        case .connecting where store.lights.isEmpty:
            ProgressView("Connecting…")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        default:
            switch selectedTab {
            case .lights: LightsListView()
            case .rooms: GroupsListView()
            case .scenes: ScenesView()
            case .bridge: BridgeView()
            }
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            Text(message).font(.caption).lineLimit(3)
            Spacer()
            Button {
                store.clearError()
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.yellow.opacity(0.1))
    }

    private var footer: some View {
        HStack {
            Text("\(store.lightsOnCount) of \(store.lights.count) lights on")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh")
            Menu {
                Button("About HueBar") { showingAbout = true }
                LaunchAtLoginToggle()
                Divider()
                Button("Forget Bridge…", role: .destructive) { store.forgetBridge() }
                Divider()
                Button("Quit HueBar") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private var statusColor: Color {
        switch store.connection {
        case .connected: .green
        case .connecting: .yellow
        case .disconnected: .gray
        case .failed: .red
        }
    }

    private var statusText: String {
        switch store.connection {
        case .connected: store.paired?.host ?? "Connected"
        case .connecting: "Connecting…"
        case .disconnected: "Not connected"
        case .failed: "Offline"
        }
    }
}
