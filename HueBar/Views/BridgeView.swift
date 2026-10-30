//
//  BridgeView.swift
//  HueBar · HueBar
//
//  Bridge management: identity, firmware, light search, paired devices and unpairing.
//

import HueKit
import SwiftUI

/// The Bridge tab: rename, firmware, light search, device removal and forgetting the pairing.
struct BridgeView: View {
    @Environment(BridgeStore.self) private var store
    @State private var bridgeName = ""
    @State private var isBusy = false
    @State private var deviceToDelete: HueDevice?
    @State private var searchStartedAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            identitySection
            firmwareSection
            lightsSection
            devicesSection
            dangerSection
        }
        .task { await store.refreshV1Config() }
        .onAppear { bridgeName = store.paired?.name ?? "" }
        .confirmationDialog(
            "Remove “\(deviceToDelete?.metadata.name ?? "")” from the bridge?",
            isPresented: Binding(get: { deviceToDelete != nil }, set: { if !$0 { deviceToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove Device", role: .destructive) {
                if let device = deviceToDelete {
                    Task { await store.deleteDevice(device) }
                }
                deviceToDelete = nil
            }
        } message: {
            Text("The device will need to be re-added before it can be controlled again.")
        }
    }

    // MARK: - Sections

    private var identitySection: some View {
        section("Bridge") {
            HStack {
                TextField("Bridge name", text: $bridgeName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { renameBridge() }
                Button("Rename") { renameBridge() }
                    .disabled(bridgeName.trimmingCharacters(in: .whitespaces).isEmpty || bridgeName == store.paired?.name || isBusy)
            }
            infoRow("Address", store.paired?.host)
            infoRow("Bridge ID", store.paired?.id.uppercased())
            infoRow("Model", store.bridgeConfig?.modelID)
            infoRow("Firmware", store.bridgeConfig?.softwareVersion)
            infoRow("API", store.bridgeConfig?.apiVersion)
            infoRow("Zigbee channel", store.v1Config?.zigbeechannel.map(String.init))
            infoRow("Time zone", store.bridgeResource?.timeZone?.timeZone)
            if let fingerprint = store.paired?.certificateFingerprint {
                infoRow("Certificate", String(fingerprint.prefix(16)) + "…")
            }
        }
    }

    private var firmwareSection: some View {
        section("Firmware") {
            let state = store.v1Config?.swupdate2?.state ?? "unknown"
            HStack {
                Text(firmwareDescription(state))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if state.contains("readytoinstall") {
                    Button("Install") {
                        run { await store.installFirmwareUpdate() }
                    }
                    .controlSize(.small)
                }
                Button("Check") {
                    run { await store.checkForFirmwareUpdate() }
                }
                .controlSize(.small)
                .disabled(isBusy)
            }
            if let last = store.v1Config?.swupdate2?.bridge?.lastinstall {
                infoRow("Last installed", last.replacingOccurrences(of: "T", with: " "))
            }
        }
    }

    private var lightsSection: some View {
        section("Lights") {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Search for new lights")
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(searchStatus(at: context.date)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Search") {
                    searchStartedAt = .now
                    run {
                        await store.searchForNewLights()
                        try? await Task.sleep(for: .seconds(45))
                        await store.refresh()
                        searchStartedAt = nil
                    }
                }
                .controlSize(.small)
                .disabled(searchStartedAt != nil)
            }
        }
    }

    private var devicesSection: some View {
        section("Devices (\(store.devices.filter { !$0.isBridge }.count))") {
            ForEach(store.devices.filter { !$0.isBridge }.sorted { $0.metadata.name.localizedCaseInsensitiveCompare($1.metadata.name) == .orderedAscending }) { device in
                HStack(spacing: 8) {
                    Image(systemName: device.lightServiceIDs.isEmpty ? "sensor" : "lightbulb")
                        .foregroundStyle(.secondary)
                        .frame(width: 14)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(device.metadata.name).font(.caption).lineLimit(1)
                        Text([device.productData?.productName, device.productData?.softwareVersion].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button {
                        deviceToDelete = device
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Remove from bridge")
                }
            }
        }
    }

    private var dangerSection: some View {
        section("This Mac") {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Forget this bridge")
                    Text("Deletes the saved key from this Mac. The bridge keeps its copy until you remove HueBar in the Hue app’s settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Forget", role: .destructive) { store.forgetBridge() }
                    .controlSize(.small)
            }
        }
    }

    // MARK: - Helpers

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            VStack(alignment: .leading, spacing: 6) {
                content()
            }
            .padding(10)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private func infoRow(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            HStack {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(value).font(.caption).monospaced().textSelection(.enabled)
            }
        }
    }

    private func firmwareDescription(_ state: String) -> String {
        switch state {
        case "noupdates": "Up to date"
        case "unknown": "Not checked yet"
        case "transferring": "Downloading update…"
        case "anyreadytoinstall", "allreadytoinstall": "Update ready to install"
        case "installing": "Installing…"
        default: state
        }
    }

    private func searchStatus(at now: Date) -> String {
        if let started = searchStartedAt {
            let remaining = max(0, 45 - Int(now.timeIntervalSince(started)))
            return "Searching… about \(remaining)s left"
        }
        return "Starts a 40 second Zigbee search; set new bulbs to pairing mode first."
    }

    private func renameBridge() {
        run { await store.renameBridge(to: bridgeName) }
    }

    private func run(_ work: @escaping @MainActor () async -> Void) {
        isBusy = true
        Task {
            await work()
            isBusy = false
        }
    }
}
