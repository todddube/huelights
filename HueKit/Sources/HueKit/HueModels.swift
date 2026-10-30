//
//  HueModels.swift
//  HueKit · HueBar
//
//  Codable models for the Hue CLIP v2 resources and the legacy v1 config the app still needs.
//

import Foundation

// MARK: - Shared fragments

/// A pointer from one CLIP v2 resource to another (`rid` + `rtype`).
public struct ResourceReference: Codable, Hashable, Sendable {
    public let rid: String
    public let rtype: String

    public init(rid: String, rtype: String) {
        self.rid = rid
        self.rtype = rtype
    }
}

/// The on/off state of a light or grouped light.
public struct OnState: Codable, Hashable, Sendable {
    public var on: Bool

    public init(on: Bool) { self.on = on }
}

/// Brightness as a percentage in `1...100`.
public struct Dimming: Codable, Hashable, Sendable {
    public var brightness: Double
    public var minDimLevel: Double?

    public init(brightness: Double, minDimLevel: Double? = nil) {
        self.brightness = brightness
        self.minDimLevel = minDimLevel
    }
}

/// A CIE 1931 xy chromaticity coordinate.
public struct XYPoint: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// The colour gamut triangle a light can reproduce.
public struct Gamut: Codable, Hashable, Sendable {
    public var red: XYPoint
    public var green: XYPoint
    public var blue: XYPoint

    public init(red: XYPoint, green: XYPoint, blue: XYPoint) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Gamut C, the widest of Philips' published gamuts, used when a light reports none.
    public static let fallback = Gamut(
        red: XYPoint(x: 0.6915, y: 0.3083),
        green: XYPoint(x: 0.17, y: 0.7),
        blue: XYPoint(x: 0.1532, y: 0.0475)
    )
}

/// Current colour of a light plus the gamut it is constrained to.
public struct ColorState: Codable, Hashable, Sendable {
    public var xy: XYPoint
    public var gamut: Gamut?
    public var gamutType: String?

    public init(xy: XYPoint, gamut: Gamut? = nil, gamutType: String? = nil) {
        self.xy = xy
        self.gamut = gamut
        self.gamutType = gamutType
    }
}

/// The range of colour temperatures a light supports, in mirek (1,000,000 / kelvin).
public struct MirekSchema: Codable, Hashable, Sendable {
    public var mirekMinimum: Int
    public var mirekMaximum: Int

    public init(mirekMinimum: Int, mirekMaximum: Int) {
        self.mirekMinimum = mirekMinimum
        self.mirekMaximum = mirekMaximum
    }
}

/// Colour temperature state. `mirek` is `nil` while the light is showing an xy colour.
public struct ColorTemperature: Codable, Hashable, Sendable {
    public var mirek: Int?
    public var mirekValid: Bool?
    public var mirekSchema: MirekSchema?

    public init(mirek: Int? = nil, mirekValid: Bool? = nil, mirekSchema: MirekSchema? = nil) {
        self.mirek = mirek
        self.mirekValid = mirekValid
        self.mirekSchema = mirekSchema
    }
}

/// User-visible name and archetype of a resource.
public struct ResourceMetadata: Codable, Hashable, Sendable {
    public var name: String
    public var archetype: String?

    public init(name: String, archetype: String? = nil) {
        self.name = name
        self.archetype = archetype
    }
}

// MARK: - Resources

/// A `light` resource.
public struct HueLight: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let idV1: String?
    public let owner: ResourceReference
    public var metadata: ResourceMetadata
    public var on: OnState
    public var dimming: Dimming?
    public var colorTemperature: ColorTemperature?
    public var color: ColorState?

    public var supportsDimming: Bool { dimming != nil }
    public var supportsColor: Bool { color != nil }
    public var supportsColorTemperature: Bool { colorTemperature?.mirekSchema != nil }

    /// Numeric v1 id (`/lights/7` → 7), used only for stable sorting.
    public var legacyNumber: Int {
        guard let idV1, let last = idV1.split(separator: "/").last else { return Int.max }
        return Int(last) ?? Int.max
    }
}

/// A `grouped_light` resource: the aggregate switch and dimmer for a room or zone.
public struct HueGroupedLight: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let owner: ResourceReference
    public var on: OnState?
    public var dimming: Dimming?
}

/// A `room` or `zone` resource. Rooms contain devices; zones contain lights directly.
public struct HueGroup: Codable, Identifiable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case room
        case zone
    }

    public let id: String
    public let children: [ResourceReference]
    public let services: [ResourceReference]
    public var metadata: ResourceMetadata
    public let type: Kind

    /// The `grouped_light` service that controls every light in this group.
    public var groupedLightID: String? {
        services.first { $0.rtype == "grouped_light" }?.rid
    }
}

/// A `scene` resource.
public struct HueScene: Codable, Identifiable, Hashable, Sendable {
    public struct Status: Codable, Hashable, Sendable {
        public var active: String

        public init(active: String) { self.active = active }
    }

    public let id: String
    public var metadata: ResourceMetadata
    public let group: ResourceReference
    public var status: Status?

    public var isActive: Bool {
        guard let active = status?.active else { return false }
        return active != "inactive"
    }
}

/// A `device` resource: the physical product behind one or more lights or sensors.
public struct HueDevice: Codable, Identifiable, Hashable, Sendable {
    public struct ProductData: Codable, Hashable, Sendable {
        public var modelId: String?
        public var manufacturerName: String?
        public var productName: String?
        public var productArchetype: String?
        public var softwareVersion: String?
    }

    public let id: String
    public var productData: ProductData?
    public var metadata: ResourceMetadata
    public let services: [ResourceReference]

    public var lightServiceIDs: [String] {
        services.filter { $0.rtype == "light" }.map(\.rid)
    }

    public var isBridge: Bool {
        services.contains { $0.rtype == "bridge" }
    }
}

/// The `bridge` resource.
public struct HueBridgeResource: Codable, Identifiable, Hashable, Sendable {
    public struct TimeZone: Codable, Hashable, Sendable {
        public var timeZone: String
    }

    public let id: String
    public let owner: ResourceReference
    public let bridgeId: String
    public var timeZone: TimeZone?
}

// MARK: - Legacy v1

/// The unauthenticated `/api/0/config` document. Keys are lowercase without underscores.
public struct BridgeConfig: Codable, Hashable, Sendable {
    public let name: String
    public let bridgeID: String
    public let modelID: String?
    public let softwareVersion: String?
    public let apiVersion: String?
    public let mac: String?

    enum CodingKeys: String, CodingKey {
        case name
        case bridgeID = "bridgeid"
        case modelID = "modelid"
        case softwareVersion = "swversion"
        case apiVersion = "apiversion"
        case mac
    }
}

/// The parts of the authenticated v1 `/config` document the app uses for firmware updates.
public struct BridgeV1Config: Codable, Hashable, Sendable {
    public struct SoftwareUpdate: Codable, Hashable, Sendable {
        public struct Bridge: Codable, Hashable, Sendable {
            public var state: String?
            public var lastinstall: String?
        }

        public var checkforupdate: Bool?
        public var lastchange: String?
        public var state: String?
        public var bridge: Bridge?
    }

    public let name: String?
    public let zigbeechannel: Int?
    public let swupdate2: SoftwareUpdate?
    public let internetservices: [String: String]?
}

// MARK: - Envelopes and updates

/// The `{ "errors": [], "data": [] }` wrapper every CLIP v2 response uses.
public struct ClipResponse<Resource: Decodable & Sendable>: Decodable, Sendable {
    public struct ClipError: Decodable, Sendable {
        public let description: String
    }

    public let errors: [ClipError]
    public let data: [Resource]
}

/// A partial `light` or `grouped_light` body for `PUT` requests. Only the set fields are sent.
public struct LightUpdate: Encodable, Sendable {
    public struct DimmingValue: Encodable, Sendable {
        public var brightness: Double
    }

    public struct ColorValue: Encodable, Sendable {
        public var xy: XYPoint
    }

    public struct MirekValue: Encodable, Sendable {
        public var mirek: Int
    }

    public struct Dynamics: Encodable, Sendable {
        /// Transition duration in milliseconds.
        public var duration: Int
    }

    public struct Alert: Encodable, Sendable {
        public var action: String
    }

    public var on: OnState?
    public var dimming: DimmingValue?
    public var color: ColorValue?
    public var colorTemperature: MirekValue?
    public var dynamics: Dynamics?
    public var alert: Alert?

    public init(
        on: Bool? = nil,
        brightness: Double? = nil,
        xy: XYPoint? = nil,
        mirek: Int? = nil,
        transitionMilliseconds: Int? = nil,
        alert: String? = nil
    ) {
        self.on = on.map(OnState.init(on:))
        self.dimming = brightness.map { DimmingValue(brightness: $0) }
        self.color = xy.map { ColorValue(xy: $0) }
        self.colorTemperature = mirek.map { MirekValue(mirek: $0) }
        self.dynamics = transitionMilliseconds.map { Dynamics(duration: $0) }
        self.alert = alert.map { Alert(action: $0) }
    }
}

/// The result of a successful link-button pairing.
public struct PairingResult: Hashable, Sendable {
    public let applicationKey: String
    public let clientKey: String?

    public init(applicationKey: String, clientKey: String?) {
        self.applicationKey = applicationKey
        self.clientKey = clientKey
    }
}

// MARK: - Event stream

/// One message from `/eventstream/clip/v2`: a list of partial resources that changed.
public struct HueEvent: Decodable, Sendable {
    public let type: String
    public let data: [HueEventResource]
}

/// A partial resource carried by an event. Every field except `id` and `type` is optional.
///
/// `status` is only decoded for scenes: other resource types (`zigbee_connectivity`,
/// `device_software_update`, ...) use `status` as a plain string, and a type mismatch there
/// would otherwise fail the whole event batch, dropping unrelated light updates with it.
public struct HueEventResource: Decodable, Sendable {
    public struct PartialMetadata: Decodable, Sendable {
        public var name: String?
    }

    public let id: String
    public let type: String
    public var on: OnState?
    public var dimming: Dimming?
    public var color: ColorState?
    public var colorTemperature: ColorTemperature?
    public var status: HueScene.Status?
    public var metadata: PartialMetadata?

    enum CodingKeys: String, CodingKey {
        case id, type, on, dimming, color, colorTemperature, status, metadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(String.self, forKey: .type)
        on = try container.decodeIfPresent(OnState.self, forKey: .on)
        dimming = try container.decodeIfPresent(Dimming.self, forKey: .dimming)
        color = try container.decodeIfPresent(ColorState.self, forKey: .color)
        colorTemperature = try container.decodeIfPresent(ColorTemperature.self, forKey: .colorTemperature)
        metadata = try container.decodeIfPresent(PartialMetadata.self, forKey: .metadata)
        // Non-scene resources carry a string here; ignore it rather than fail the batch.
        status = try? container.decodeIfPresent(HueScene.Status.self, forKey: .status)
    }
}

// MARK: - Coding helpers

/// Shared JSON coders so every CLIP v2 call agrees on snake_case key mapping.
public enum HueCoding {
    /// Decoder configured for CLIP v2's snake_case keys.
    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    /// Encoder configured for CLIP v2's snake_case keys.
    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }
}
