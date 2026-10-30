//
//  BridgeTrustDelegate.swift
//  HueKit · HueBar
//
//  URLSession delegate that trusts a Hue bridge's self-signed certificate by pinning it.
//

import CryptoKit
import Foundation
import os

/// Accepts the bridge's TLS certificate using trust-on-first-use pinning.
///
/// Hue bridges present a certificate signed by Signify's private root CA, which the
/// system does not trust, and whose common name is the bridge id rather than the IP
/// address the app connects to. Instead of disabling TLS checks outright, the delegate:
///
/// 1. On first contact, accepts the leaf only if its common name matches the bridge id
///    the caller expects, then records the SHA-256 fingerprint of the DER certificate.
/// 2. On every later connection, requires the same fingerprint.
///
/// When no bridge id is known yet (probing an IP during discovery) the delegate runs in
/// `permissive` mode, which accepts any certificate. Callers must only send
/// unauthenticated requests through a permissive session.
public final class BridgeTrustDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    /// How strictly to verify the peer.
    public enum Mode: Sendable {
        /// Accept anything. Only for the unauthenticated `/api/0/config` probe.
        case permissive
        /// Require the certificate common name to match `bridgeID` (case-insensitive) and
        /// pin the fingerprint after the first successful match.
        case pinned(bridgeID: String, fingerprint: String?)
    }

    private struct State {
        var mode: Mode
        var pinnedFingerprint: String?
        var didRejectPeer = false
    }

    private let state: OSAllocatedUnfairLock<State>
    private let logger = Logger(subsystem: "com.todddube.HueBar", category: "tls")

    public init(mode: Mode) {
        var pinned: String?
        if case .pinned(_, let fingerprint) = mode { pinned = fingerprint }
        state = OSAllocatedUnfairLock(initialState: State(mode: mode, pinnedFingerprint: pinned))
        super.init()
    }

    /// The fingerprint accepted on first use, or the one supplied at init.
    public var pinnedFingerprint: String? {
        state.withLock { $0.pinnedFingerprint }
    }

    /// Whether this delegate has refused a peer certificate; lets callers tell a pin failure
    /// apart from an ordinary cancelled request, since both surface as `URLError.cancelled`.
    public var didRejectPeer: Bool {
        state.withLock { $0.didRejectPeer }
    }

    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        guard let leaf = Self.leafCertificate(of: trust) else {
            logger.error("Bridge presented no certificate chain")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        let fingerprint = Self.fingerprint(of: leaf)
        let accepted: Bool = state.withLock { state in
            switch state.mode {
            case .permissive:
                return true
            case .pinned(let bridgeID, _):
                if let pinned = state.pinnedFingerprint {
                    return pinned == fingerprint
                }
                let summary = (SecCertificateCopySubjectSummary(leaf) as String?) ?? ""
                guard summary.lowercased() == bridgeID.lowercased() else { return false }
                state.pinnedFingerprint = fingerprint
                return true
            }
        }

        if accepted {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            state.withLock { $0.didRejectPeer = true }
            logger.error("Rejected bridge certificate with fingerprint \(fingerprint, privacy: .public)")
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    // MARK: - Helpers

    private static func leafCertificate(of trust: SecTrust) -> SecCertificate? {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate] else { return nil }
        return chain.first
    }

    /// Lowercase hex SHA-256 of the DER-encoded certificate.
    static func fingerprint(of certificate: SecCertificate) -> String {
        let der = SecCertificateCopyData(certificate) as Data
        return SHA256.hash(data: der).map { String(format: "%02x", $0) }.joined()
    }
}
