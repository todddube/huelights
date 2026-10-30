//
//  HueModelsTests.swift
//  HueKitTests · HueBar
//
//  Decoding checks against captured CLIP v2 and v1 payload shapes.
//

import Foundation
import Testing

@testable import HueKit

struct HueModelsTests {
    private let decoder = HueCoding.makeDecoder()

    @Test func decodesLightResource() throws {
        let json = """
        {"errors":[],"data":[{"id":"abc","id_v1":"/lights/7","owner":{"rid":"dev","rtype":"device"},
        "metadata":{"name":"Desk","archetype":"sultan_bulb"},"on":{"on":true},
        "dimming":{"brightness":55.5,"min_dim_level":0.2},
        "color_temperature":{"mirek":366,"mirek_valid":true,"mirek_schema":{"mirek_minimum":153,"mirek_maximum":500}},
        "color":{"xy":{"x":0.45,"y":0.41},"gamut":{"red":{"x":0.69,"y":0.31},"green":{"x":0.17,"y":0.7},"blue":{"x":0.15,"y":0.05}},"gamut_type":"C"},
        "type":"light"}]}
        """
        let envelope = try decoder.decode(ClipResponse<HueLight>.self, from: Data(json.utf8))
        let light = try #require(envelope.data.first)
        #expect(light.metadata.name == "Desk")
        #expect(light.legacyNumber == 7)
        #expect(light.dimming?.brightness == 55.5)
        #expect(light.colorTemperature?.mirekSchema?.mirekMaximum == 500)
        #expect(light.supportsColor)
        #expect(light.supportsColorTemperature)
    }

    @Test func decodesRoomAndGroupedLightService() throws {
        let json = """
        {"errors":[],"data":[{"id":"room1","children":[{"rid":"dev","rtype":"device"}],
        "services":[{"rid":"gl1","rtype":"grouped_light"}],"metadata":{"name":"Office","archetype":"office"},"type":"room"}]}
        """
        let room = try #require(try decoder.decode(ClipResponse<HueGroup>.self, from: Data(json.utf8)).data.first)
        #expect(room.type == .room)
        #expect(room.groupedLightID == "gl1")
    }

    @Test func decodesLegacyConfig() throws {
        let json = """
        {"name":"Hue Bridge","datastoreversion":"170","swversion":"1968096020","apiversion":"1.68.0",
        "mac":"ec:b5:fa:00:00:00","bridgeid":"ECB5FAFFFE000000","factorynew":false,"replacesbridgeid":null,"modelid":"BSB002"}
        """
        let config = try decoder.decode(BridgeConfig.self, from: Data(json.utf8))
        #expect(config.bridgeID == "ECB5FAFFFE000000")
        #expect(config.modelID == "BSB002")
        #expect(config.apiVersion == "1.68.0")
    }

    @Test func decodesPartialEvent() throws {
        let json = """
        [{"creationtime":"2026-10-30T12:00:00Z","id":"evt","type":"update",
        "data":[{"id":"abc","id_v1":"/lights/7","on":{"on":false},"owner":{"rid":"dev","rtype":"device"},"type":"light"},
        {"id":"scene1","status":{"active":"static"},"type":"scene"},
        {"id":"weird","type":"some_future_type","unknown_field":{"x":1}}]}]
        """
        let events = try decoder.decode([HueEvent].self, from: Data(json.utf8))
        let event = try #require(events.first)
        #expect(event.data.count == 3)
        #expect(event.data[0].on?.on == false)
        #expect(event.data[0].dimming == nil)
        #expect(event.data[1].status?.active == "static")
    }

    @Test func stringStatusOnOtherResourcesDoesNotBreakBatch() throws {
        let json = """
        [{"creationtime":"2026-10-30T12:00:00Z","id":"evt","type":"update",
        "data":[{"id":"zc","owner":{"rid":"dev","rtype":"device"},"status":"connectivity_issue","type":"zigbee_connectivity"},
        {"id":"abc","on":{"on":true},"type":"light"}]}]
        """
        let events = try decoder.decode([HueEvent].self, from: Data(json.utf8))
        let event = try #require(events.first)
        #expect(event.data.count == 2)
        #expect(event.data[0].status == nil)
        #expect(event.data[1].on?.on == true)
    }

    @Test func lightUpdateOmitsUnsetFields() throws {
        let encoder = HueCoding.makeEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(LightUpdate(brightness: 40, transitionMilliseconds: 400))
        let text = String(decoding: data, as: UTF8.self)
        #expect(text == #"{"dimming":{"brightness":40},"dynamics":{"duration":400}}"#)
    }
}
