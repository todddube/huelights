//
//  PairedBridgeTests.swift
//  HueBarTests · HueBar
//
//  Round-trip and permission checks for the persisted credentials file, in temporary folders only.
//

import Foundation
import Testing

@testable import HueBar

struct PairedBridgeTests {
    private let record = PairedBridge(
        id: "ECB5FAFFFE000000",
        name: "Hue Bridge",
        host: "192.168.1.20",
        modelID: "BSB002",
        applicationKey: "secret-key",
        clientKey: nil,
        certificateFingerprint: "abcd",
        pairedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )

    /// Runs `body` with a fresh temporary directory, never the user's real credentials folder.
    private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "huebar-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    @Test func saveThenLoadRoundTrips() throws {
        try withTemporaryDirectory { directory in
            try record.save(to: directory)
            #expect(PairedBridge.load(from: directory) == record)
        }
    }

    @Test func credentialsAreOwnerOnly() throws {
        try withTemporaryDirectory { directory in
            try record.save(to: directory)
            let file = try FileManager.default.attributesOfItem(atPath: PairedBridge.fileURL(in: directory).path)
            let folder = try FileManager.default.attributesOfItem(atPath: directory.path)
            #expect((file[.posixPermissions] as? Int) == 0o600)
            #expect((folder[.posixPermissions] as? Int) == 0o700)
        }
    }

    @Test func loadReturnsNilWhenMissingOrCorrupt() throws {
        try withTemporaryDirectory { directory in
            #expect(PairedBridge.load(from: directory) == nil)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("not json".utf8).write(to: PairedBridge.fileURL(in: directory))
            #expect(PairedBridge.load(from: directory) == nil)
        }
    }

    @Test func clearRemovesTheFile() throws {
        try withTemporaryDirectory { directory in
            try record.save(to: directory)
            PairedBridge.clear(in: directory)
            #expect(PairedBridge.load(from: directory) == nil)
        }
    }
}
