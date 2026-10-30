//
//  SetupView.swift
//  HueBar · HueBar
//
//  First-run flow: list discovered bridges, let the user pick one and press its link button.
//

import HueKit
import SwiftUI

/// Shown until a bridge is paired: discovery results, manual IP entry and the link-button wait.
struct SetupView: View {
    @Environment(BridgeStore.self) private var store
    @State private var manualHost = ""
    @State private var isProbing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            if let target = store.pairingTarget {
                pairingPanel(for: target)
            } else {
                bridgeList
                manualEntry
            }
            Divider()
            footer
        }
        .padding(14)
    }

    private var header: some View {
        HStack(spacing: 10) {
            HueLogo(size: 36, animated: store.isDiscovering)
            VStack(alignment: .leading, spacing: 2) {
                Text("Connect to a Hue Bridge").font(.headline)
                Text(store.isDiscovering ? "Searching your network…" : "Pick a bridge to pair with.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if store.isDiscovering {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    Task { await store.discover() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Search again")
            }
        }
    }

    private var bridgeList: some View {
        VStack(alignment: .leading, spacing: 6) {
            if store.discovered.isEmpty && !store.isDiscovering {
                ContentUnavailableView {
                    Label("No bridges found", systemImage: "wifi.exclamationmark")
                } description: {
                    Text("Make sure the bridge is powered on and on the same network, or enter its IP address below.")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            ForEach(store.discovered) { bridge in
                Button {
                    store.startPairing(with: bridge)
                } label: {
                    HStack {
                        Image(systemName: "server.rack")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(bridge.name).fontWeight(.medium)
                            Text("\(bridge.host) · \(bridge.id.uppercased())")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .padding(8)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var manualEntry: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField("Bridge IP address", text: $manualHost)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { probe() }
                Button("Add") { probe() }
                    .disabled(manualHost.trimmingCharacters(in: .whitespaces).isEmpty || isProbing)
            }
            if case .failed(let message) = store.pairing {
                Text(message).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private func probe() {
        isProbing = true
        Task {
            if await store.addManualBridge(host: manualHost) { manualHost = "" }
            isProbing = false
        }
    }

    @ViewBuilder
    private func pairingPanel(for bridge: DiscoveredBridge) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "button.programmable")
                .font(.system(size: 44))
                .foregroundStyle(.blue)
                .symbolEffect(.pulse, isActive: isWaiting)
            Text("Press the link button on **\(bridge.name)**")
                .multilineTextAlignment(.center)
            switch store.pairing {
            case .waitingForButton(let seconds):
                ProgressView(value: Double(seconds), total: 30)
                    .progressViewStyle(.linear)
                Text("Waiting… \(seconds)s")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            case .failed(let message):
                Text(message).font(.caption).foregroundStyle(.red).multilineTextAlignment(.center)
                Button("Try Again") { store.startPairing(with: bridge) }
            case .idle:
                ProgressView().controlSize(.small)
            }
            Button("Cancel") { store.cancelPairing() }
                .buttonStyle(.borderless)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    private var isWaiting: Bool {
        if case .waitingForButton = store.pairing { return true }
        return false
    }

    private var footer: some View {
        HStack {
            AppBadge()
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
                .font(.caption)
        }
    }
}
