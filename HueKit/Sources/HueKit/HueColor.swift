//
//  HueColor.swift
//  HueKit · HueBar
//
//  Conversions between sRGB, CIE xy and colour temperature, including gamut clamping.
//

import Foundation

/// A gamma-encoded sRGB triple in `0...1`.
public struct RGB: Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public static let white = RGB(red: 1, green: 1, blue: 1)
}

/// Colour maths for Hue lights.
///
/// The RGB↔XYZ matrices are the wide-gamut D65 pair Philips publishes for its lights,
/// so round trips agree with what the Hue app shows.
public enum HueColor {
    // MARK: - RGB ↔ xy

    /// Converts a gamma-encoded sRGB colour to the xy point the light should show.
    ///
    /// The result is clamped into `gamut` because the bridge rejects (or silently
    /// relocates) points a light cannot reproduce.
    public static func xy(from rgb: RGB, gamut: Gamut = .fallback) -> XYPoint {
        let r = linearize(rgb.red)
        let g = linearize(rgb.green)
        let b = linearize(rgb.blue)

        let x = r * 0.664511 + g * 0.154324 + b * 0.162028
        let y = r * 0.283881 + g * 0.668433 + b * 0.047685
        let z = r * 0.000088 + g * 0.072310 + b * 0.986039

        let sum = x + y + z
        guard sum > 0 else { return clamp(XYPoint(x: 0.3127, y: 0.3290), to: gamut) }
        return clamp(XYPoint(x: x / sum, y: y / sum), to: gamut)
    }

    /// Converts an xy point back to gamma-encoded sRGB at full luminance, for swatches.
    public static func rgb(from point: XYPoint, brightness: Double = 1) -> RGB {
        let y = 1.0
        let x = point.y > 0 ? (y / point.y) * point.x : 0
        let z = point.y > 0 ? (y / point.y) * (1 - point.x - point.y) : 0

        var r = x * 1.656492 - y * 0.354851 - z * 0.255038
        var g = -x * 0.707196 + y * 1.655397 + z * 0.036152
        var b = x * 0.051713 - y * 0.121364 + z * 1.011530

        // Normalise so the brightest channel is 1, then let brightness scale it down.
        let peak = max(r, g, b, 1e-6)
        r = max(0, r / peak)
        g = max(0, g / peak)
        b = max(0, b / peak)

        let scale = max(0, min(1, brightness))
        return RGB(
            red: gammaEncode(r) * scale,
            green: gammaEncode(g) * scale,
            blue: gammaEncode(b) * scale
        )
    }

    // MARK: - Colour temperature

    /// Converts mirek to kelvin, clamping away from zero.
    public static func kelvin(fromMirek mirek: Int) -> Int {
        Int((1_000_000.0 / Double(max(mirek, 1))).rounded())
    }

    /// Converts kelvin to mirek, clamping away from zero.
    public static func mirek(fromKelvin kelvin: Int) -> Int {
        Int((1_000_000.0 / Double(max(kelvin, 1))).rounded())
    }

    /// An approximate sRGB colour for a black-body temperature, for drawing swatches.
    ///
    /// Uses Tanner Helland's curve fit, which is accurate enough for a 16pt circle.
    public static func rgb(fromKelvin kelvin: Int) -> RGB {
        let t = Double(min(max(kelvin, 1000), 40000)) / 100

        let red: Double
        if t <= 66 {
            red = 255
        } else {
            red = 329.698727446 * pow(t - 60, -0.1332047592)
        }

        let green: Double
        if t <= 66 {
            green = 99.4708025861 * log(t) - 161.1195681661
        } else {
            green = 288.1221695283 * pow(t - 60, -0.0755148492)
        }

        let blue: Double
        if t >= 66 {
            blue = 255
        } else if t <= 19 {
            blue = 0
        } else {
            blue = 138.5177312231 * log(t - 10) - 305.0447927307
        }

        return RGB(
            red: clamp01(red / 255),
            green: clamp01(green / 255),
            blue: clamp01(blue / 255)
        )
    }

    // MARK: - Gamut

    /// Returns `point` if it lies inside `gamut`, otherwise the closest point on the triangle.
    public static func clamp(_ point: XYPoint, to gamut: Gamut) -> XYPoint {
        if contains(gamut, point) { return point }
        let candidates = [
            closestPoint(on: gamut.red, gamut.green, to: point),
            closestPoint(on: gamut.green, gamut.blue, to: point),
            closestPoint(on: gamut.blue, gamut.red, to: point),
        ]
        return candidates.min { distance($0, point) < distance($1, point) } ?? point
    }

    static func contains(_ gamut: Gamut, _ p: XYPoint) -> Bool {
        let a = gamut.red, b = gamut.green, c = gamut.blue
        let v0 = XYPoint(x: c.x - a.x, y: c.y - a.y)
        let v1 = XYPoint(x: b.x - a.x, y: b.y - a.y)
        let v2 = XYPoint(x: p.x - a.x, y: p.y - a.y)

        let dot00 = v0.x * v0.x + v0.y * v0.y
        let dot01 = v0.x * v1.x + v0.y * v1.y
        let dot02 = v0.x * v2.x + v0.y * v2.y
        let dot11 = v1.x * v1.x + v1.y * v1.y
        let dot12 = v1.x * v2.x + v1.y * v2.y

        let denominator = dot00 * dot11 - dot01 * dot01
        guard abs(denominator) > 1e-12 else { return false }
        let inverse = 1 / denominator
        let u = (dot11 * dot02 - dot01 * dot12) * inverse
        let v = (dot00 * dot12 - dot01 * dot02) * inverse
        return u >= 0 && v >= 0 && u + v <= 1
    }

    static func closestPoint(on a: XYPoint, _ b: XYPoint, to p: XYPoint) -> XYPoint {
        let ap = XYPoint(x: p.x - a.x, y: p.y - a.y)
        let ab = XYPoint(x: b.x - a.x, y: b.y - a.y)
        let lengthSquared = ab.x * ab.x + ab.y * ab.y
        guard lengthSquared > 0 else { return a }
        let t = max(0, min(1, (ap.x * ab.x + ap.y * ab.y) / lengthSquared))
        return XYPoint(x: a.x + ab.x * t, y: a.y + ab.y * t)
    }

    static func distance(_ a: XYPoint, _ b: XYPoint) -> Double {
        let dx = a.x - b.x, dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }

    // MARK: - Transfer functions

    static func linearize(_ c: Double) -> Double {
        let v = clamp01(c)
        return v > 0.04045 ? pow((v + 0.055) / 1.055, 2.4) : v / 12.92
    }

    static func gammaEncode(_ c: Double) -> Double {
        let v = clamp01(c)
        return v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055
    }

    static func clamp01(_ v: Double) -> Double {
        v.isNaN ? 0 : max(0, min(1, v))
    }
}
