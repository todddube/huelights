//
//  LiveDiscoveryTests.swift
//  HueKitTests · HueBar
//
//  Opt-in checks against a real bridge on the LAN. Run with HUEBAR_LIVE=1 swift test.
//

import Foundation
import Testing

@testable import HueKit

@Suite(.enabled(if: ProcessInfo.processInfo.environment["HUEBAR_LIVE"] == "1"))
struct LiveDiscoveryTests {
    @Test func discoversAtLeastOneBridge() async throws {
        let bridges = await HueDiscovery.discover(duration: .seconds(4))
        let first = try #require(bridges.first)
        #expect(first.id.count == 16)
        #expect(!first.host.isEmpty)
        #expect(!first.name.isEmpty)
        print("Discovered:", bridges)
    }

    @Test func pinnedTrustRejectsWrongBridgeID() async {
        let bridges = await HueDiscovery.discover(duration: .seconds(3))
        guard let bridge = bridges.first else { return }
        let client = HueClient(host: bridge.host, applicationKey: nil, trust: .pinned(bridgeID: "0000000000000000", fingerprint: nil))
        await #expect(throws: HueError.certificateRejected) {
            _ = try await client.fetchConfig()
        }
    }

    @Test func pinnedTrustAcceptsMatchingBridgeID() async throws {
        let bridges = await HueDiscovery.discover(duration: .seconds(3))
        guard let bridge = bridges.first else { return }
        let client = HueClient(host: bridge.host, applicationKey: nil, trust: .pinned(bridgeID: bridge.id, fingerprint: nil))
        let config = try await client.fetchConfig()
        #expect(config.bridgeID.lowercased() == bridge.id)
        #expect(await client.pinnedFingerprint?.count == 64)
    }
}
