//
//  PairedBridge.swift
//  HueBar · HueBar
//
//  The persisted record of the bridge this Mac is paired with, including its application key.
//

import Foundation
import os

/// Everything needed to reconnect to the paired bridge.
///
/// Stored as JSON at `~/Library/Application Support/HueBar/bridges.json` with `0600`
/// permissions rather than in the keychain. The keychain ties an item's access list to the
/// code signature, so every ad-hoc rebuild during development would prompt or lose access,
/// and `swift run` and the bundled app would not share a preferences domain. One file in
/// Application Support is shared by both and survives rebuilds. The application key only
/// grants access to the bridge on the local network, so file permissions are adequate.
struct PairedBridge: Codable, Hashable, Sendable {
    var id: String
    var name: String
    var host: String
    var modelID: String?
    /// The `hue-application-key` issued at pairing.
    var applicationKey: String
    /// The entertainment-API client key, kept for future use.
    var clientKey: String?
    /// SHA-256 of the bridge's certificate, pinned at pairing.
    var certificateFingerprint: String?
    var pairedAt: Date

    private static let logger = Logger(subsystem: "com.todddube.HueBar", category: "credentials")

    /// Directory holding the credentials file. Override with `HUEBAR_CONFIG_DIR` for testing.
    static var directory: URL {
        if let override = ProcessInfo.processInfo.environment["HUEBAR_CONFIG_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
        return base.appending(path: "HueBar", directoryHint: .isDirectory)
    }

    static var fileURL: URL { fileURL(in: directory) }

    static func fileURL(in directory: URL) -> URL { directory.appending(path: "bridges.json") }

    /// The saved pairing, or `nil` when none exists or the file is unreadable.
    ///
    /// Every entry point takes the directory so tests can use a temporary one and never touch
    /// the user's real credentials.
    static func load(from directory: URL = Self.directory) -> PairedBridge? {
        // No file simply means not paired yet, so a read failure is not worth reporting.
        guard let data = try? Data(contentsOf: fileURL(in: directory)) else { return nil }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(PairedBridge.self, from: data)
        } catch {
            logger.error("Credentials file is unreadable: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Writes the record, creating the directory and restricting the file to the current user.
    func save(to directory: URL = Self.directory) throws {
        let fm = FileManager.default
        let file = Self.fileURL(in: directory)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // Tighten the directory even if it already existed (e.g. under HUEBAR_CONFIG_DIR).
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        // createFile applies the mode at creation, so the key is never briefly world-readable.
        guard fm.createFile(atPath: file.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: file.path])
        }
    }

    static func clear(in directory: URL = Self.directory) {
        // A missing file is the desired end state, so a failure to remove it is not an error worth surfacing.
        try? FileManager.default.removeItem(at: fileURL(in: directory))
    }
}
