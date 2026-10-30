//
//  HueError.swift
//  HueKit · HueBar
//
//  Errors raised by the bridge client and discovery.
//

import Foundation

/// Failures talking to a Hue bridge.
public enum HueError: Error, LocalizedError, Sendable, Equatable {
    case invalidURL(String)
    case notAuthenticated
    case httpStatus(Int, body: String)
    case linkButtonNotPressed
    case bridgeError(String)
    case emptyResponse
    case decoding(String)
    case certificateRejected

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "The bridge address “\(url)” is not valid."
        case .notAuthenticated:
            return "This bridge has not been paired yet."
        case .httpStatus(let code, let body):
            let detail = body.isEmpty ? "" : ": \(body.prefix(200))"
            return "The bridge answered with HTTP \(code)\(detail)"
        case .linkButtonNotPressed:
            return "Press the round button on top of the bridge."
        case .bridgeError(let message):
            return message
        case .emptyResponse:
            return "The bridge returned an empty response."
        case .decoding(let message):
            return "Could not read the bridge’s reply: \(message)"
        case .certificateRejected:
            return "The bridge’s certificate did not match the one pinned at pairing time."
        }
    }
}
