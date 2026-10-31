//
//  BridgeStoreTests.swift
//  HueBarTests · HueBar
//
//  State-machine checks for the store that need no bridge on the network.
//

import Foundation
import Testing

@testable import HueBar

@MainActor
struct BridgeStoreTests {
    /// A store whose credentials live in an empty temporary folder, so it starts unpaired and
    /// `forgetBridge()` can only ever delete files created here.
    private func unpairedStore() -> (store: BridgeStore, directory: URL) {
        let directory = FileManager.default.temporaryDirectory.appending(path: "huebar-tests-\(UUID().uuidString)")
        return (BridgeStore(credentialsDirectory: directory), directory)
    }

    private let record = PairedBridge(
        id: "ECB5FAFFFE000000", name: "Hue Bridge", host: "192.0.2.1", modelID: nil,
        applicationKey: "key", clientKey: nil, certificateFingerprint: nil, pairedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )

    @Test func startsUnpairedWithoutCredentials() {
        let (store, directory) = unpairedStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(!store.isPaired)
        #expect(store.connection == .disconnected)
        #expect(store.lights.isEmpty)
        #expect(!store.anyLightOn)
    }

    @Test func loadsSavedCredentialsFromItsDirectory() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "huebar-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try record.save(to: directory)
        let store = BridgeStore(credentialsDirectory: directory)
        #expect(store.paired == record)
    }

    @Test func reportAndClearError() {
        let (store, directory) = unpairedStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        store.report("boom")
        #expect(store.lastError == "boom")
        store.clearError()
        #expect(store.lastError == nil)
    }

    @Test func forgetDeletesOnlyItsOwnCredentialsAndResetsState() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "huebar-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try record.save(to: directory)
        let store = BridgeStore(credentialsDirectory: directory)
        store.isConfirmingForget = true
        store.report("stale")

        store.forgetBridge()

        #expect(!store.isPaired)
        #expect(!store.isConfirmingForget)
        #expect(store.lastError == nil)
        #expect(store.connection == .disconnected)
        #expect(PairedBridge.load(from: directory) == nil)
    }

    @Test func cancelPairingClearsTarget() {
        let (store, directory) = unpairedStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        store.cancelPairing()
        #expect(store.pairing == .idle)
        #expect(store.pairingTarget == nil)
    }

    @Test func resyncDoesNothingWhenUnpaired() async {
        let (store, directory) = unpairedStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        await store.resync()
        #expect(store.connection == .disconnected)
    }
}
