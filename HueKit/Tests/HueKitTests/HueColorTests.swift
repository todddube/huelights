//
//  HueColorTests.swift
//  HueKitTests · HueBar
//
//  Round-trip and clamping checks for the colour conversions.
//

import Testing

@testable import HueKit

struct HueColorTests {
    @Test func whiteMapsNearD65() {
        let xy = HueColor.xy(from: .white)
        #expect(abs(xy.x - 0.3127) < 0.02)
        #expect(abs(xy.y - 0.3290) < 0.01)
    }

    @Test func primariesRoundTrip() {
        for rgb in [RGB(red: 1, green: 0.1, blue: 0.1), RGB(red: 0.1, green: 1, blue: 0.1), RGB(red: 0.1, green: 0.1, blue: 1)] {
            let xy = HueColor.xy(from: rgb)
            let back = HueColor.rgb(from: xy)
            // The dominant channel must survive the trip.
            let input = [rgb.red, rgb.green, rgb.blue]
            let output = [back.red, back.green, back.blue]
            #expect(input.firstIndex(of: input.max()!) == output.firstIndex(of: output.max()!))
        }
    }

    @Test func outOfGamutPointsAreClamped() {
        let gamut = Gamut.fallback
        let farOutside = XYPoint(x: 0.9, y: 0.9)
        let clamped = HueColor.clamp(farOutside, to: gamut)
        #expect(HueColor.contains(gamut, clamped) || HueColor.distance(clamped, farOutside) < HueColor.distance(XYPoint(x: 0.33, y: 0.33), farOutside))
        #expect(clamped != farOutside)
        let inside = XYPoint(x: 0.3, y: 0.3)
        #expect(HueColor.clamp(inside, to: gamut) == inside)
    }

    @Test func mirekKelvinInverse() {
        #expect(HueColor.kelvin(fromMirek: 153) == 6536)
        #expect(HueColor.mirek(fromKelvin: 2700) == 370)
        #expect(HueColor.kelvin(fromMirek: 0) == 1_000_000)
    }

    @Test func kelvinSwatchIsWarmAtLowTemperature() {
        let warm = HueColor.rgb(fromKelvin: 2200)
        let cool = HueColor.rgb(fromKelvin: 6500)
        #expect(warm.red > warm.blue)
        #expect(cool.blue >= warm.blue)
    }
}
