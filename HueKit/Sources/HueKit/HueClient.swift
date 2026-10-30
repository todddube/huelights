//
//  HueClient.swift
//  HueKit · HueBar
//
//  HTTPS client for one Hue bridge: pairing, CLIP v2 resources, legacy v1 config and events.
//

import Foundation
import os

/// Talks to a single bridge over HTTPS.
///
/// All CLIP v2 calls go to `/clip/v2/resource/...` with the `hue-application-key` header.
/// A few maintenance operations (firmware update, light search, bridge rename) still only
/// exist in the v1 API at `/api/<key>/...`, so those are wrapped here too.
public actor HueClient {
    public let host: String
    public let applicationKey: String?

    private let session: URLSession
    private let streamSession: URLSession
    private let trust: BridgeTrustDelegate
    private let decoder = HueCoding.makeDecoder()
    private let encoder = HueCoding.makeEncoder()
    private let logger = Logger(subsystem: "com.todddube.HueBar", category: "client")

    /// Creates a client.
    ///
    /// - Parameters:
    ///   - host: IP address or hostname of the bridge.
    ///   - applicationKey: the key issued at pairing, or `nil` before pairing.
    ///   - trust: the certificate policy. Pass `.permissive` only for unauthenticated probes.
    public init(host: String, applicationKey: String?, trust mode: BridgeTrustDelegate.Mode) {
        self.host = host
        self.applicationKey = applicationKey
        self.trust = BridgeTrustDelegate(mode: mode)

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.waitsForConnectivity = false
        session = URLSession(configuration: config, delegate: trust, delegateQueue: nil)

        // The event stream is a long poll that should never time out on its own.
        let streamConfig = URLSessionConfiguration.ephemeral
        streamConfig.timeoutIntervalForRequest = 60 * 60
        streamConfig.timeoutIntervalForResource = .infinity
        streamSession = URLSession(configuration: streamConfig, delegate: trust, delegateQueue: nil)
    }

    deinit {
        // A URLSession retains its delegate until invalidated, so without this every client leaks.
        session.invalidateAndCancel()
        streamSession.invalidateAndCancel()
    }

    /// The certificate fingerprint pinned on first contact, for persisting alongside the key.
    public var pinnedFingerprint: String? { trust.pinnedFingerprint }

    // MARK: - Unauthenticated

    /// Reads `/api/0/config`, which works without a key and identifies the bridge.
    public func fetchConfig() async throws -> BridgeConfig {
        let (data, _) = try await perform("GET", path: "/api/0/config", body: nil, authenticated: false)
        return try decode(BridgeConfig.self, from: data)
    }

    /// Attempts one link-button pairing. Throws ``HueError/linkButtonNotPressed`` until pressed.
    public func pair(deviceType: String) async throws -> PairingResult {
        struct Request: Encodable {
            let devicetype: String
            let generateclientkey: Bool
        }
        struct Reply: Decodable {
            struct Success: Decodable {
                let username: String
                let clientkey: String?
            }
            struct Failure: Decodable {
                let type: Int
                let description: String
            }
            let success: Success?
            let error: Failure?
        }

        let body = try JSONEncoder().encode(Request(devicetype: deviceType, generateclientkey: true))
        let (data, _) = try await perform("POST", path: "/api", body: body, authenticated: false)
        let replies = try decode([Reply].self, from: data)
        guard let first = replies.first else { throw HueError.emptyResponse }
        if let success = first.success {
            return PairingResult(applicationKey: success.username, clientKey: success.clientkey)
        }
        if let failure = first.error {
            if failure.type == 101 { throw HueError.linkButtonNotPressed }
            throw HueError.bridgeError(failure.description)
        }
        throw HueError.emptyResponse
    }

    // MARK: - CLIP v2 reads

    public func lights() async throws -> [HueLight] { try await resources("light") }
    public func groupedLights() async throws -> [HueGroupedLight] { try await resources("grouped_light") }
    public func rooms() async throws -> [HueGroup] { try await resources("room") }
    public func zones() async throws -> [HueGroup] { try await resources("zone") }
    public func scenes() async throws -> [HueScene] { try await resources("scene") }
    public func devices() async throws -> [HueDevice] { try await resources("device") }
    public func bridges() async throws -> [HueBridgeResource] { try await resources("bridge") }

    private func resources<T: Decodable & Sendable>(_ type: String) async throws -> [T] {
        let (data, _) = try await perform("GET", path: "/clip/v2/resource/\(type)", body: nil, authenticated: true)
        let envelope = try decode(ClipResponse<T>.self, from: data)
        if let error = envelope.errors.first, envelope.data.isEmpty {
            throw HueError.bridgeError(error.description)
        }
        return envelope.data
    }

    // MARK: - CLIP v2 writes

    /// Sends a partial state change to one light.
    public func update(light id: String, _ update: LightUpdate) async throws {
        try await put("/clip/v2/resource/light/\(id)", body: update)
    }

    /// Sends a partial state change to every light in a room or zone at once.
    public func update(groupedLight id: String, _ update: LightUpdate) async throws {
        try await put("/clip/v2/resource/grouped_light/\(id)", body: update)
    }

    /// Recalls a scene on its group.
    public func recall(scene id: String) async throws {
        struct Body: Encodable {
            struct Recall: Encodable { let action: String }
            let recall: Recall
        }
        try await put("/clip/v2/resource/scene/\(id)", body: Body(recall: .init(action: "active")))
    }

    /// Renames a light. The light's own metadata name is what the Hue app shows.
    public func rename(light id: String, to name: String) async throws {
        struct Body: Encodable {
            struct Meta: Encodable { let name: String }
            let metadata: Meta
        }
        try await put("/clip/v2/resource/light/\(id)", body: Body(metadata: .init(name: name)))
    }

    /// Renames a room or zone.
    public func rename(group: HueGroup, to name: String) async throws {
        struct Body: Encodable {
            struct Meta: Encodable { let name: String }
            let metadata: Meta
        }
        try await put("/clip/v2/resource/\(group.type.rawValue)/\(group.id)", body: Body(metadata: .init(name: name)))
    }

    /// Removes a device (and its lights) from the bridge. This cannot be undone from the app.
    public func delete(device id: String) async throws {
        _ = try await perform("DELETE", path: "/clip/v2/resource/device/\(id)", body: nil, authenticated: true)
    }

    private func put<Body: Encodable>(_ path: String, body: Body) async throws {
        let data = try encoder.encode(body)
        let (reply, _) = try await perform("PUT", path: path, body: data, authenticated: true)
        // Writes return `{"errors":[],"data":[{"rid":..,"rtype":..}]}`; surface any error text.
        if let envelope = try? decoder.decode(ClipResponse<ResourceReference>.self, from: reply),
           let error = envelope.errors.first {
            throw HueError.bridgeError(error.description)
        }
    }

    // MARK: - Legacy v1 maintenance

    /// Reads the authenticated v1 config, mainly for the firmware-update state.
    public func fetchV1Config() async throws -> BridgeV1Config {
        let (data, _) = try await perform("GET", path: try v1Path("config"), body: nil, authenticated: true)
        return try decode(BridgeV1Config.self, from: data)
    }

    /// Asks the bridge to look for a firmware update.
    public func checkForFirmwareUpdate() async throws {
        try await writeV1("PUT", "config", json: ["swupdate2": ["checkforupdate": true]])
    }

    /// Installs a downloaded firmware update. The bridge reboots afterwards.
    public func installFirmwareUpdate() async throws {
        try await writeV1("PUT", "config", json: ["swupdate2": ["install": true]])
    }

    /// Renames the bridge itself (the bridge limits names to 32 characters).
    public func renameBridge(to name: String) async throws {
        try await writeV1("PUT", "config", json: ["name": name])
    }

    /// Starts a 40-second Zigbee search for new lights.
    public func searchForNewLights() async throws {
        try await writeV1("POST", "lights", json: [:])
    }

    private func v1Path(_ suffix: String) throws -> String {
        guard let applicationKey else { throw HueError.notAuthenticated }
        return "/api/\(applicationKey)/\(suffix)"
    }

    /// Sends a v1 write and surfaces its result. The v1 API answers HTTP 200 with
    /// `[{"error": {...}}]` on failure, so the status code alone is not enough.
    private func writeV1(_ method: String, _ suffix: String, json: [String: Any]) async throws {
        struct Reply: Decodable {
            struct Failure: Decodable {
                let description: String
            }
            let error: Failure?
        }
        let body = try JSONSerialization.data(withJSONObject: json)
        let (data, _) = try await perform(method, path: try v1Path(suffix), body: body, authenticated: true)
        let replies = try decode([Reply].self, from: data)
        if let failure = replies.compactMap(\.error).first {
            throw HueError.bridgeError(failure.description)
        }
    }

    // MARK: - Events

    /// Streams server-sent events until cancelled or the connection drops.
    ///
    /// The caller is responsible for reconnecting; the bridge closes idle streams now and then.
    public func events() -> AsyncThrowingStream<HueEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let applicationKey else { throw HueError.notAuthenticated }
                    var request = try makeRequest("GET", path: "/eventstream/clip/v2", body: nil)
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.setValue(applicationKey, forHTTPHeaderField: "hue-application-key")

                    let (bytes, response) = try await streamSession.bytes(for: request)
                    try Self.validate(response, body: Data())

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
                        guard let data = payload.data(using: .utf8) else { continue }
                        do {
                            for event in try decoder.decode([HueEvent].self, from: data) {
                                continuation.yield(event)
                            }
                        } catch {
                            // Unknown resource shapes are expected as Hue adds types; skip, don't tear down.
                            logger.debug("Skipping undecodable event: \(error.localizedDescription, privacy: .public)")
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Transport

    private func makeRequest(_ method: String, path: String, body: Data?) throws -> URLRequest {
        guard let url = URL(string: "https://\(host)\(path)") else {
            throw HueError.invalidURL("https://\(host)\(path)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func perform(_ method: String, path: String, body: Data?, authenticated: Bool) async throws -> (Data, HTTPURLResponse) {
        var request = try makeRequest(method, path: path, body: body)
        if authenticated {
            guard let applicationKey else { throw HueError.notAuthenticated }
            request.setValue(applicationKey, forHTTPHeaderField: "hue-application-key")
        }
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled || error.code == .serverCertificateUntrusted {
            // URLSession reports both a cancelled Swift task and a refused TLS challenge as
            // `.cancelled`; the delegate records which one happened.
            if trust.didRejectPeer { throw HueError.certificateRejected }
            if Task.isCancelled { throw CancellationError() }
            throw error
        }
        return (data, try Self.validate(response, body: data))
    }

    @discardableResult
    private static func validate(_ response: URLResponse, body: Data) throws -> HTTPURLResponse {
        guard let http = response as? HTTPURLResponse else { throw HueError.emptyResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw HueError.httpStatus(http.statusCode, body: String(decoding: body, as: UTF8.self))
        }
        return http
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw HueError.decoding(String(describing: error))
        }
    }
}
