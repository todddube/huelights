//
//  HueDiscovery.swift
//  HueKit · HueBar
//
//  Finds Hue bridges via Bonjour, with the Hue cloud and manual IP entry as fallbacks.
//

import Foundation
import Network
import os

/// A bridge found on the network, before or after pairing.
public struct DiscoveredBridge: Identifiable, Hashable, Sendable {
    /// How the bridge was found.
    public enum Source: String, Sendable {
        case bonjour
        case cloud
        case manual
    }

    /// The bridge id (lowercase, 16 hex characters).
    public let id: String
    public var name: String
    public var host: String
    public var modelID: String?
    public var softwareVersion: String?
    public var source: Source

    public init(id: String, name: String, host: String, modelID: String? = nil, softwareVersion: String? = nil, source: Source) {
        self.id = id.lowercased()
        self.name = name
        self.host = host
        self.modelID = modelID
        self.softwareVersion = softwareVersion
        self.source = source
    }
}

/// Bridge discovery.
///
/// Bonjour (`_hue._tcp`) is authoritative on the LAN. The cloud endpoint only knows the
/// address a bridge last reported to Signify, so it is used to fill in bridges that
/// mDNS missed (for example across a VLAN that forwards unicast but not multicast).
public enum HueDiscovery {
    private static let logger = Logger(subsystem: "com.todddube.HueBar", category: "discovery")

    /// Searches for bridges for `duration` and returns every bridge that answered `/api/0/config`.
    public static func discover(duration: Duration = .seconds(4)) async -> [DiscoveredBridge] {
        async let bonjour = BonjourBrowser.browse(for: duration)
        async let cloud = cloudLookup()

        var byID: [String: DiscoveredBridge] = [:]
        for bridge in await bonjour { byID[bridge.id] = bridge }
        for bridge in await cloud where byID[bridge.id] == nil { byID[bridge.id] = bridge }

        // Confirm each candidate and pick up its friendly name and firmware version.
        var confirmed: [DiscoveredBridge] = []
        await withTaskGroup(of: DiscoveredBridge?.self) { group in
            for candidate in byID.values {
                group.addTask {
                    guard var probed = try? await probe(host: candidate.host) else { return nil }
                    probed.source = candidate.source
                    return probed
                }
            }
            for await result in group {
                // A Bonjour hit without a bridgeid TXT record is keyed by host above and can
                // duplicate the cloud entry once probed, so de-duplicate on the real id here.
                if let result, !confirmed.contains(where: { $0.id == result.id }) { confirmed.append(result) }
            }
        }
        return confirmed.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Asks a specific address whether it is a bridge. Used for manual entry and to confirm candidates.
    public static func probe(host: String) async throws -> DiscoveredBridge {
        let client = HueClient(host: host, applicationKey: nil, trust: .permissive)
        let config = try await client.fetchConfig()
        return DiscoveredBridge(
            id: config.bridgeID,
            name: config.name,
            host: host,
            modelID: config.modelID,
            softwareVersion: config.softwareVersion,
            source: .manual
        )
    }

    // MARK: - Cloud

    private struct CloudEntry: Decodable {
        let id: String
        let internalipaddress: String
    }

    static func cloudLookup() async -> [DiscoveredBridge] {
        guard let url = URL(string: "https://discovery.meethue.com") else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            let entries = try JSONDecoder().decode([CloudEntry].self, from: data)
            return entries.map {
                DiscoveredBridge(id: $0.id, name: "Hue Bridge", host: $0.internalipaddress, source: .cloud)
            }
        } catch {
            // The cloud is optional; being offline must not block LAN discovery.
            logger.info("Cloud discovery unavailable: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}

// MARK: - Bonjour

/// Browses `_hue._tcp` and resolves each result to an IPv4 address.
enum BonjourBrowser {
    private static let logger = Logger(subsystem: "com.todddube.HueBar", category: "bonjour")
    private static let queue = DispatchQueue(label: "com.todddube.HueBar.bonjour")

    /// A service seen by the browser, reduced to the Sendable bits we need.
    private struct Candidate: Sendable {
        let endpoint: NWEndpoint
        let bridgeID: String?
        let modelID: String?
    }

    static func browse(for duration: Duration) async -> [DiscoveredBridge] {
        let candidates = await collectCandidates(for: duration)
        var bridges: [DiscoveredBridge] = []
        await withTaskGroup(of: DiscoveredBridge?.self) { group in
            for candidate in candidates {
                group.addTask {
                    guard let host = await resolveIPv4(candidate.endpoint) else { return nil }
                    let name: String
                    if case .service(let serviceName, _, _, _) = candidate.endpoint {
                        name = serviceName
                    } else {
                        name = "Hue Bridge"
                    }
                    return DiscoveredBridge(
                        id: candidate.bridgeID ?? host,
                        name: name,
                        host: host,
                        modelID: candidate.modelID,
                        source: .bonjour
                    )
                }
            }
            for await bridge in group {
                if let bridge { bridges.append(bridge) }
            }
        }
        return bridges
    }

    private static func collectCandidates(for duration: Duration) async -> [Candidate] {
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = false
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_hue._tcp", domain: nil), using: parameters)

        let results = OSAllocatedUnfairLock<[Candidate]>(initialState: [])
        browser.browseResultsChangedHandler = { all, _ in
            let mapped = all.map { result -> Candidate in
                var bridgeID: String?
                var modelID: String?
                if case .bonjour(let txt) = result.metadata {
                    bridgeID = txt.dictionary["bridgeid"]
                    modelID = txt.dictionary["modelid"]
                }
                return Candidate(endpoint: result.endpoint, bridgeID: bridgeID, modelID: modelID)
            }
            results.withLock { $0 = mapped }
        }
        browser.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                logger.error("Bonjour browse failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        browser.start(queue: queue)
        defer { browser.cancel() }

        // Cancellation just shortens the search; whatever was found so far is still returned.
        try? await Task.sleep(for: duration)
        return results.withLock { $0 }
    }

    /// Opens a short TCP connection to learn the IPv4 address behind a Bonjour endpoint.
    ///
    /// Bonjour hands back a service name, not an address, and the HTTPS client needs
    /// something it can put in a URL. IPv4 is forced because link-local IPv6 addresses
    /// carry an interface scope that URLs cannot express.
    private static func resolveIPv4(_ endpoint: NWEndpoint) async -> String? {
        let parameters = NWParameters.tcp
        if let ip = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ip.version = .v4
        }
        let connection = NWConnection(to: endpoint, using: parameters)
        let finished = OSAllocatedUnfairLock(initialState: false)

        return await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            @Sendable func finish(_ value: String?) {
                let first = finished.withLock { done -> Bool in
                    if done { return false }
                    done = true
                    return true
                }
                guard first else { return }
                connection.cancel()
                continuation.resume(returning: value)
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if case .hostPort(let host, _) = connection.currentPath?.remoteEndpoint,
                       case .ipv4(let address) = host {
                        // Interpolating IPv4Address appends the interface scope ("%en1"), which URLs reject.
                        finish(address.rawValue.map(String.init).joined(separator: "."))
                    } else {
                        finish(nil)
                    }
                case .failed, .cancelled:
                    finish(nil)
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 3) { finish(nil) }
        }
    }
}
