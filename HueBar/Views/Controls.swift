//
//  Controls.swift
//  HueBar · HueBar
//
//  Reusable pieces: colour swatch, brightness and colour temperature sliders, inline rename.
//

import HueKit
import SwiftUI

extension Color {
    /// A SwiftUI colour from a HueKit gamma-encoded sRGB triple.
    init(_ rgb: RGB) {
        self.init(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: 1)
    }

    /// The colour an RGB `Color` resolves to in sRGB, or `nil` if it has no RGB representation.
    func rgbValue() -> RGB? {
        guard let converted = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return RGB(red: converted.redComponent, green: converted.greenComponent, blue: converted.blueComponent)
    }
}

/// The colour a light is currently showing, for swatches.
func displayColor(for light: HueLight) -> Color {
    guard light.on.on else { return Color(nsColor: .tertiaryLabelColor) }
    if let temperature = light.colorTemperature, temperature.mirekValid == true, let mirek = temperature.mirek {
        return Color(HueColor.rgb(fromKelvin: HueColor.kelvin(fromMirek: mirek)))
    }
    if let xy = light.color?.xy {
        return Color(HueColor.rgb(from: xy))
    }
    return .yellow.opacity(0.8)
}

/// A small filled circle with a faint outline, so dark or off colours stay visible.
struct ColorSwatch: View {
    let color: Color
    var size: CGFloat = 14

    var body: some View {
        Circle()
            .fill(color)
            .overlay(Circle().strokeBorder(.primary.opacity(0.15)))
            .frame(width: size, height: size)
    }
}

/// A 1–100 brightness slider with a sun icon.
struct BrightnessSlider: View {
    @Binding var value: Double
    var isEnabled = true

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sun.min").foregroundStyle(.secondary).font(.caption)
            Slider(value: $value, in: 1...100, step: 1)
                .controlSize(.small)
            Image(systemName: "sun.max").foregroundStyle(.secondary).font(.caption)
            Text("\(Int(value))%")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
        }
        .disabled(!isEnabled)
    }
}

/// A colour temperature slider in kelvin, drawn over a warm-to-cool gradient.
struct ColorTemperatureSlider: View {
    @Binding var mirek: Double
    let schema: MirekSchema

    private var kelvin: Int { HueColor.kelvin(fromMirek: Int(mirek)) }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "thermometer.low").foregroundStyle(.secondary).font(.caption)
            Slider(
                value: Binding(get: { -mirek }, set: { mirek = -$0 }),
                in: Double(-schema.mirekMaximum)...Double(-schema.mirekMinimum),
                step: 1
            )
            .controlSize(.small)
            .background(
                LinearGradient(
                    colors: [
                        Color(HueColor.rgb(fromKelvin: HueColor.kelvin(fromMirek: schema.mirekMaximum))),
                        Color(HueColor.rgb(fromKelvin: HueColor.kelvin(fromMirek: schema.mirekMinimum))),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 4)
                .clipShape(Capsule())
                .padding(.horizontal, 6)
                .opacity(0.5)
            )
            Image(systemName: "thermometer.high").foregroundStyle(.secondary).font(.caption)
            Text("\(kelvin)K")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
    }
}

/// A label that turns into a text field on double-click and commits on return.
struct EditableName: View {
    let name: String
    let onCommit: (String) -> Void

    @State private var isEditing = false
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        if isEditing {
            TextField("Name", text: $draft)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit { commit() }
                .onExitCommand { isEditing = false }
                .onChange(of: isFocused) { _, focused in
                    if !focused { commit() }
                }
        } else {
            Text(name)
                .fontWeight(.medium)
                .lineLimit(1)
                .onTapGesture(count: 2) {
                    draft = name
                    isEditing = true
                    isFocused = true
                }
                .help("Double-click to rename")
        }
    }

    private func commit() {
        guard isEditing else { return }
        isEditing = false
        onCommit(draft)
    }
}
