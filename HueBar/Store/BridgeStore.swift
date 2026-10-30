//
//  BridgeStore.swift
//  HueBar · HueBar
//
//  Main-actor model behind the menu bar UI: discovery, pairing, cached state and control.
//

import Foundation
import HueKit
import Observation
import os

/// Owns everything the views show and every action they can take.
///
/// Network calls run on ``HueClient`` (an actor); results are applied here on the main
/// actor. Slider changes are applied to the local model instantly and sent to the bridge
/// after a short coalescing delay so dragging does not flood it.
@MainActor
@Observable
final class BridgeStore {
    /// Health of the link to the paired bridge, driving the status dot and offline view.
    enum Connection: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)
    }

    /// Progress of a link-button pairing attempt.
    enum PairingState: Equatable {
        case idle
        case waitingForButton(secondsLeft: Int)
        case failed(String)
    }

    // MARK: Discovery and pairing

    private(set) var discovered: [DiscoveredBridge] = []
    private(set) var isDiscovering = false
    private(set) var pairing: PairingState = .idle
    var pairingTarget: DiscoveredBridge?

    // MARK: Paired bridge

    private(set) var paired: PairedBridge?
    private(set) var connection: Connection = .disconnected
    private(set) var lastError: String?
    private(set) var isRefreshing = false

    private(set) var lights: [HueLight] = []
    private(set) var groups: [HueGroup] = []
    private(set) var groupedLights: [String: HueGroupedLight] = [:]
    private(set) var scenes: [HueScene] = []
    private(set) var devices: [HueDevice] = []
    private(set) var bridgeResource: HueBridgeResource?
    private(set) var bridgeConfig: BridgeConfig?
    private(set) var v1Config: BridgeV1Config?

    /// Transition applied to every write, in milliseconds.
    var transitionMilliseconds = 400

    @ObservationIgnored private var client: HueClient?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var pairingTask: Task<Void, Never>?
    /// In-flight or scheduled writes keyed by resource id. The token lets a superseded task
    /// tell whether the entry still belongs to it before removing it.
    @ObservationIgnored private var pendingWrites: [String: (token: UUID, task: Task<Void, Never>)] = [:]
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var isConnecting = false
    @ObservationIgnored private let logger = Logger(subsystem: "com.todddube.HueBar", category: "store")

    init() {
        paired = PairedBridge.load()
    }

    // MARK: - Derived

    var isPaired: Bool { paired != nil }

    var anyLightOn: Bool { lights.contains { $0.on.on } }

    var lightsOnCount: Int { lights.filter(\.on.on).count }

    var rooms: [HueGroup] { groups.filter { $0.type == .room } }
    var zones: [HueGroup] { groups.filter { $0.type == .zone } }

    /// Lights that belong to a room (via its devices) or zone (directly).
    func lights(in group: HueGroup) -> [HueLight] {
        let ids: Set<String>
        switch group.type {
        case .room:
            let deviceIDs = Set(group.children.filter { $0.rtype == "device" }.map(\.rid))
            ids = Set(devices.filter { deviceIDs.contains($0.id) }.flatMap(\.lightServiceIDs))
        case .zone:
            ids = Set(group.children.filter { $0.rtype == "light" }.map(\.rid))
        }
        return lights.filter { ids.contains($0.id) }
    }

    func scenes(for group: HueGroup) -> [HueScene] {
        scenes.filter { $0.group.rid == group.id }
            .sorted { $0.metadata.name.localizedCaseInsensitiveCompare($1.metadata.name) == .orderedAscending }
    }

    func groupedLight(for group: HueGroup) -> HueGroupedLight? {
        group.groupedLightID.flatMap { groupedLights[$0] }
    }

    func device(for light: HueLight) -> HueDevice? {
        devices.first { $0.id == light.owner.rid }
    }

    func group(for scene: HueScene) -> HueGroup? {
        groups.first { $0.id == scene.group.rid }
    }

    // MARK: - Lifecycle

    /// Connects to the saved bridge, or starts discovery when there is none. Safe to call repeatedly.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        if paired != nil {
            Task { await connect() }
        } else {
            Task { await discover() }
        }
    }

    func discover() async {
        guard !isDiscovering else { return }
        isDiscovering = true
        defer { isDiscovering = false }
        discovered = await HueDiscovery.discover()
    }

    /// Probes a user-entered address and adds it to the discovered list.
    func addManualBridge(host: String) async -> Bool {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        do {
            let bridge = try await HueDiscovery.probe(host: trimmed)
            discovered.removeAll { $0.id == bridge.id }
            discovered.append(bridge)
            pairing = .idle
            return true
        } catch {
            pairing = .failed("No Hue bridge answered at \(trimmed).")
            return false
        }
    }

    // MARK: - Pairing

    /// Polls the bridge for up to 30 seconds while the user presses the link button.
    func startPairing(with bridge: DiscoveredBridge) {
        pairingTask?.cancel()
        pairingTarget = bridge
        pairing = .waitingForButton(secondsLeft: 30)

        pairingTask = Task { [weak self] in
            let client = HueClient(host: bridge.host, applicationKey: nil, trust: .pinned(bridgeID: bridge.id, fingerprint: nil))
            let deviceType = "HueBar#\(Host.current().localizedName ?? "mac")".replacingOccurrences(of: " ", with: "-")

            for remaining in stride(from: 30, through: 1, by: -1) {
                guard !Task.isCancelled, let self else { return }
                self.pairing = .waitingForButton(secondsLeft: remaining)
                do {
                    let result = try await client.pair(deviceType: deviceType)
                    let fingerprint = await client.pinnedFingerprint
                    await self.finishPairing(bridge: bridge, result: result, fingerprint: fingerprint)
                    return
                } catch HueError.linkButtonNotPressed {
                    try? await Task.sleep(for: .seconds(1))
                } catch {
                    guard !Task.isCancelled else { return }
                    self.pairing = .failed(error.localizedDescription)
                    return
                }
            }
            guard !Task.isCancelled else { return }
            self?.pairing = .failed("Timed out waiting for the link button. Try again.")
        }
    }

    func cancelPairing() {
        pairingTask?.cancel()
        pairingTask = nil
        pairing = .idle
        pairingTarget = nil
    }

    private func finishPairing(bridge: DiscoveredBridge, result: PairingResult, fingerprint: String?) async {
        let record = PairedBridge(
            id: bridge.id,
            name: bridge.name,
            host: bridge.host,
            modelID: bridge.modelID,
            applicationKey: result.applicationKey,
            clientKey: result.clientKey,
            certificateFingerprint: fingerprint,
            pairedAt: .now
        )
        do {
            try record.save()
        } catch {
            pairing = .failed("Paired, but the key could not be saved to \(PairedBridge.fileURL.path): \(error.localizedDescription)")
            return
        }
        paired = record
        pairing = .idle
        pairingTarget = nil
        await connect()
    }

    /// Drops the saved pairing. The bridge keeps the key until it is removed in the Hue app.
    func forgetBridge() {
        eventTask?.cancel()
        eventTask = nil
        PairedBridge.clear()
        paired = nil
        client = nil
        connection = .disconnected
        lights = []
        groups = []
        groupedLights = [:]
        scenes = []
        devices = []
        bridgeResource = nil
        bridgeConfig = nil
        v1Config = nil
        Task { await discover() }
    }

    // MARK: - Connection

    func connect() async {
        guard let paired, !isConnecting else { return }
        isConnecting = true
        defer { isConnecting = false }
        connection = .connecting
        let client = HueClient(
            host: paired.host,
            applicationKey: paired.applicationKey,
            trust: .pinned(bridgeID: paired.id, fingerprint: paired.certificateFingerprint)
        )
        self.client = client

        do {
            try await refresh(using: client)
            connection = .connected
            startEventStream()
        } catch {
            logger.error("Connect failed: \(error.localizedDescription, privacy: .public)")
            if await relocateBridge() {
                await connect()
            } else {
                connection = .failed(error.localizedDescription)
            }
        }
    }

    /// If the bridge moved to a new IP (DHCP), find it again by id and update the record.
    private func relocateBridge() async -> Bool {
        guard let paired else { return false }
        let found = await HueDiscovery.discover(duration: .seconds(3))
        guard let match = found.first(where: { $0.id == paired.id }), match.host != paired.host else { return false }
        logger.notice("Bridge moved from \(paired.host, privacy: .public) to \(match.host, privacy: .public)")
        var updated = paired
        updated.host = match.host
        updated.name = match.name
        persist(updated)
        return true
    }

    /// Updates the in-memory record and writes it back; a failed write is logged but not fatal.
    private func persist(_ record: PairedBridge) {
        paired = record
        do {
            try record.save()
        } catch {
            logger.error("Could not save credentials: \(error.localizedDescription, privacy: .public)")
            lastError = "Could not save bridge settings: \(error.localizedDescription)"
        }
    }

    func refresh() async {
        guard let client else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            try await refresh(using: client)
            if connection != .connected {
                connection = .connected
                startEventStream()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func refresh(using client: HueClient) async throws {
        async let lights = client.lights()
        async let grouped = client.groupedLights()
        async let rooms = client.rooms()
        async let zones = client.zones()
        async let scenes = client.scenes()
        async let devices = client.devices()
        async let bridges = client.bridges()
        async let config = client.fetchConfig()

        self.lights = try await lights.sorted { lhs, rhs in
            if lhs.legacyNumber != rhs.legacyNumber { return lhs.legacyNumber < rhs.legacyNumber }
            return lhs.metadata.name.localizedCaseInsensitiveCompare(rhs.metadata.name) == .orderedAscending
        }
        self.groupedLights = Dictionary(uniqueKeysWithValues: try await grouped.map { ($0.id, $0) })
        self.groups = (try await rooms + zones).sorted {
            $0.metadata.name.localizedCaseInsensitiveCompare($1.metadata.name) == .orderedAscending
        }
        self.scenes = try await scenes
        self.devices = try await devices
        self.bridgeResource = try await bridges.first
        self.bridgeConfig = try await config

        if var paired, paired.name != bridgeConfig?.name, let name = bridgeConfig?.name {
            paired.name = name
            persist(paired)
        }
    }

    /// Loads the v1 config on demand; it is only needed by the Bridge tab.
    func refreshV1Config() async {
        guard let client else { return }
        do {
            v1Config = try await client.fetchV1Config()
        } catch is CancellationError {
            // The Bridge tab went away before the reply; nothing to report.
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Events

    private func startEventStream() {
        eventTask?.cancel()
        eventTask = Task { [weak self] in
            var backoff: Duration = .seconds(1)
            while !Task.isCancelled {
                guard let self, let client = self.client else { return }
                do {
                    for try await event in await client.events() {
                        backoff = .seconds(1)
                        self.apply(event)
                    }
                } catch is CancellationError {
                    return
                } catch {
                    self.logger.info("Event stream dropped: \(error.localizedDescription, privacy: .public)")
                }
                guard !Task.isCancelled else { return }
                try? await Task.sleep(for: backoff)
                backoff = min(backoff * 2, .seconds(30))
                // Resync after a gap so anything missed while disconnected is picked up.
                await self.refresh()
            }
        }
    }

    private func apply(_ event: HueEvent) {
        guard event.type == "update" || event.type == "add" || event.type == "delete" else { return }
        var needsFullRefresh = false

        for resource in event.data {
            switch (event.type, resource.type) {
            case ("update", "light"):
                guard let index = lights.firstIndex(where: { $0.id == resource.id }) else { continue }
                // Skip if a local write is still in flight so the slider does not jump back.
                if pendingWrites[resource.id] != nil { continue }
                if let on = resource.on { lights[index].on = on }
                if let dimming = resource.dimming { lights[index].dimming?.brightness = dimming.brightness }
                if let color = resource.color { lights[index].color?.xy = color.xy }
                if let temperature = resource.colorTemperature {
                    lights[index].colorTemperature?.mirek = temperature.mirek
                    lights[index].colorTemperature?.mirekValid = temperature.mirekValid
                }
                if let name = resource.metadata?.name { lights[index].metadata.name = name }
            case ("update", "grouped_light"):
                guard var group = groupedLights[resource.id] else { continue }
                if pendingWrites[resource.id] != nil { continue }
                if let on = resource.on { group.on = on }
                if let dimming = resource.dimming { group.dimming = dimming }
                groupedLights[resource.id] = group
            case ("update", "scene"):
                guard let index = scenes.firstIndex(where: { $0.id == resource.id }) else { continue }
                if let status = resource.status { scenes[index].status = status }
                if let name = resource.metadata?.name { scenes[index].metadata.name = name }
            case ("update", "room"), ("update", "zone"):
                guard let index = groups.firstIndex(where: { $0.id == resource.id }) else { continue }
                if let name = resource.metadata?.name { groups[index].metadata.name = name }
            case ("add", _), ("delete", _):
                needsFullRefresh = true
            default:
                continue
            }
        }

        if needsFullRefresh {
            Task { await refresh() }
        }
    }

    // MARK: - Light control

    func setLight(_ light: HueLight, on: Bool) {
        guard let index = lights.firstIndex(where: { $0.id == light.id }) else { return }
        lights[index].on.on = on
        send(key: light.id) { [transitionMilliseconds] client in
            try await client.update(light: light.id, LightUpdate(on: on, transitionMilliseconds: transitionMilliseconds))
        }
    }

    func setLight(_ light: HueLight, brightness: Double) {
        guard let index = lights.firstIndex(where: { $0.id == light.id }) else { return }
        let clamped = max(1, min(100, brightness))
        lights[index].dimming?.brightness = clamped
        // Hue treats a brightness change on an off light as a no-op, so switch it on too.
        let turnOn = !lights[index].on.on
        if turnOn { lights[index].on.on = true }
        send(key: light.id) { [transitionMilliseconds] client in
            try await client.update(light: light.id, LightUpdate(on: turnOn ? true : nil, brightness: clamped, transitionMilliseconds: transitionMilliseconds))
        }
    }

    func setLight(_ light: HueLight, rgb: RGB) {
        guard let index = lights.firstIndex(where: { $0.id == light.id }) else { return }
        let gamut = light.color?.gamut ?? .fallback
        let xy = HueColor.xy(from: rgb, gamut: gamut)
        lights[index].color?.xy = xy
        lights[index].colorTemperature?.mirek = nil
        lights[index].colorTemperature?.mirekValid = false
        let turnOn = !lights[index].on.on
        if turnOn { lights[index].on.on = true }
        send(key: light.id) { [transitionMilliseconds] client in
            try await client.update(light: light.id, LightUpdate(on: turnOn ? true : nil, xy: xy, transitionMilliseconds: transitionMilliseconds))
        }
    }

    func setLight(_ light: HueLight, mirek: Int) {
        guard let index = lights.firstIndex(where: { $0.id == light.id }),
              let schema = light.colorTemperature?.mirekSchema else { return }
        let clamped = max(schema.mirekMinimum, min(schema.mirekMaximum, mirek))
        lights[index].colorTemperature?.mirek = clamped
        lights[index].colorTemperature?.mirekValid = true
        let turnOn = !lights[index].on.on
        if turnOn { lights[index].on.on = true }
        send(key: light.id) { [transitionMilliseconds] client in
            try await client.update(light: light.id, LightUpdate(on: turnOn ? true : nil, mirek: clamped, transitionMilliseconds: transitionMilliseconds))
        }
    }

    /// Makes the light breathe once so the user can tell which one it is.
    func identify(_ light: HueLight) {
        send(key: "identify-\(light.id)", delay: .zero) { client in
            try await client.update(light: light.id, LightUpdate(alert: "breathe"))
        }
    }

    func rename(_ light: HueLight, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != light.metadata.name,
              let index = lights.firstIndex(where: { $0.id == light.id }) else { return }
        lights[index].metadata.name = trimmed
        send(key: "rename-\(light.id)", delay: .zero) { client in
            try await client.rename(light: light.id, to: trimmed)
        }
    }

    // MARK: - Group control

    func setGroup(_ group: HueGroup, on: Bool) {
        guard let id = group.groupedLightID else { return }
        groupedLights[id]?.on = OnState(on: on)
        for light in lights(in: group) {
            if let index = lights.firstIndex(where: { $0.id == light.id }) { lights[index].on.on = on }
        }
        send(key: id) { [transitionMilliseconds] client in
            try await client.update(groupedLight: id, LightUpdate(on: on, transitionMilliseconds: transitionMilliseconds))
        }
    }

    func setGroup(_ group: HueGroup, brightness: Double) {
        guard let id = group.groupedLightID else { return }
        let clamped = max(1, min(100, brightness))
        groupedLights[id]?.dimming = Dimming(brightness: clamped)
        let turnOn = groupedLights[id]?.on?.on == false
        if turnOn { groupedLights[id]?.on = OnState(on: true) }
        send(key: id) { [transitionMilliseconds] client in
            try await client.update(groupedLight: id, LightUpdate(on: turnOn ? true : nil, brightness: clamped, transitionMilliseconds: transitionMilliseconds))
        }
    }

    func setAllLights(on: Bool) {
        for group in rooms { setGroup(group, on: on) }
        // Lights that are not in any room still need switching individually.
        let covered = Set(rooms.flatMap { lights(in: $0) }.map(\.id))
        for light in lights where !covered.contains(light.id) { setLight(light, on: on) }
    }

    func recall(_ scene: HueScene) {
        for index in scenes.indices {
            if scenes[index].group.rid == scene.group.rid {
                scenes[index].status = HueScene.Status(active: scenes[index].id == scene.id ? "static" : "inactive")
            }
        }
        send(key: "scene-\(scene.group.rid)", delay: .zero) { client in
            try await client.recall(scene: scene.id)
        }
    }

    func rename(_ group: HueGroup, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != group.metadata.name,
              let index = groups.firstIndex(where: { $0.id == group.id }) else { return }
        groups[index].metadata.name = trimmed
        send(key: "rename-\(group.id)", delay: .zero) { client in
            try await client.rename(group: group, to: trimmed)
        }
    }

    // MARK: - Bridge management

    func renameBridge(to name: String) async {
        guard let client else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        do {
            try await client.renameBridge(to: trimmed)
            await refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func checkForFirmwareUpdate() async {
        guard let client else { return }
        do {
            try await client.checkForFirmwareUpdate()
            // The bridge needs a moment before the state changes from "unknown".
            try await Task.sleep(for: .seconds(3))
            await refreshV1Config()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func installFirmwareUpdate() async {
        guard let client else { return }
        do {
            try await client.installFirmwareUpdate()
            await refreshV1Config()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func searchForNewLights() async {
        guard let client else { return }
        do {
            try await client.searchForNewLights()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func deleteDevice(_ device: HueDevice) async {
        guard let client else { return }
        do {
            try await client.delete(device: device.id)
            await refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func clearError() {
        lastError = nil
    }

    // MARK: - Write coalescing

    /// Schedules `operation` after `delay`, replacing any earlier pending write for `key`.
    private func send(
        key: String,
        delay: Duration = .milliseconds(120),
        _ operation: @escaping @Sendable (HueClient) async throws -> Void
    ) {
        guard let client else { return }
        pendingWrites[key]?.task.cancel()
        let token = UUID()
        let task = Task { [weak self] in
            defer {
                if self?.pendingWrites[key]?.token == token {
                    self?.pendingWrites.removeValue(forKey: key)
                }
            }
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled else { return }
            do {
                try await operation(client)
                self?.lastError = nil
            } catch {
                // A newer write replaced this one mid-request; its outcome no longer matters.
                guard !Task.isCancelled, !(error is CancellationError) else { return }
                self?.logger.error("Write \(key, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                self?.lastError = error.localizedDescription
            }
        }
        pendingWrites[key] = (token, task)
    }
}
