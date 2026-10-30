//
//  LightsListView.swift
//  HueBar · HueBar
//
//  Every light on the bridge, each expanding into brightness, temperature and colour controls.
//

import HueKit
import SwiftUI

/// The Lights tab: every light in bridge order, each row expandable in place.
struct LightsListView: View {
    @Environment(BridgeStore.self) private var store
    @State private var expanded: Set<String> = []

    var body: some View {
        if store.lights.isEmpty {
            ContentUnavailableView("No lights", systemImage: "lightbulb.slash", description: Text("Add lights to the bridge with the Hue app, or use Search for New Lights in the Bridge tab."))
        } else {
            LazyVStack(spacing: 6) {
                ForEach(store.lights) { light in
                    LightRow(light: light, isExpanded: expanded.contains(light.id)) {
                        if expanded.contains(light.id) { expanded.remove(light.id) } else { expanded.insert(light.id) }
                    }
                }
            }
        }
    }
}

/// One light: power toggle and inline rename, and when expanded its full controls.
struct LightRow: View {
    @Environment(BridgeStore.self) private var store
    let light: HueLight
    let isExpanded: Bool
    let toggleExpanded: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Button(action: toggleExpanded) {
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 12)
                }
                .buttonStyle(.plain)

                ColorSwatch(color: displayColor(for: light))

                EditableName(name: light.metadata.name) { store.rename(light, to: $0) }

                Spacer(minLength: 4)

                if let brightness = light.dimming?.brightness, light.on.on, !isExpanded {
                    Text("\(Int(brightness))%")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Toggle("On", isOn: Binding(
                    get: { light.on.on },
                    set: { store.setLight(light, on: $0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 1) { toggleExpanded() }

            if isExpanded {
                expandedControls
                    .padding(.leading, 22)
            }
        }
        .padding(8)
        .background(.quaternary.opacity(isExpanded ? 0.6 : 0.35), in: RoundedRectangle(cornerRadius: 8))
        .animation(.easeInOut(duration: 0.15), value: isExpanded)
    }

    @ViewBuilder
    private var expandedControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            if light.supportsDimming {
                BrightnessSlider(value: Binding(
                    get: { light.dimming?.brightness ?? 100 },
                    set: { store.setLight(light, brightness: $0) }
                ))
            }

            if let schema = light.colorTemperature?.mirekSchema {
                ColorTemperatureSlider(
                    mirek: Binding(
                        get: { Double(light.colorTemperature?.mirek ?? (schema.mirekMinimum + schema.mirekMaximum) / 2) },
                        set: { store.setLight(light, mirek: Int($0)) }
                    ),
                    schema: schema
                )
            }

            HStack(spacing: 10) {
                if light.supportsColor {
                    ColorPicker("Colour", selection: Binding(
                        get: { light.color.map { Color(HueColor.rgb(from: $0.xy)) } ?? .white },
                        set: { if let rgb = $0.rgbValue() { store.setLight(light, rgb: rgb) } }
                    ), supportsOpacity: false)
                    .font(.caption)

                    presetColors
                }
                Spacer()
                Button {
                    store.identify(light)
                } label: {
                    Label("Identify", systemImage: "light.beacon.max")
                }
                .controlSize(.small)
                .help("Blink this light")
            }

            if let device = store.device(for: light), let product = device.productData?.productName {
                Text("\(product)\(device.productData?.modelId.map { " · \($0)" } ?? "")")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var presetColors: some View {
        HStack(spacing: 4) {
            ForEach(Self.presets, id: \.name) { preset in
                Button {
                    store.setLight(light, rgb: preset.rgb)
                } label: {
                    ColorSwatch(color: Color(preset.rgb), size: 16)
                }
                .buttonStyle(.plain)
                .help(preset.name)
            }
        }
    }

    private static let presets: [(name: String, rgb: RGB)] = [
        ("Red", RGB(red: 1, green: 0.2, blue: 0.15)),
        ("Orange", RGB(red: 1, green: 0.55, blue: 0.1)),
        ("Yellow", RGB(red: 1, green: 0.9, blue: 0.3)),
        ("Green", RGB(red: 0.3, green: 0.9, blue: 0.4)),
        ("Blue", RGB(red: 0.25, green: 0.5, blue: 1)),
        ("Purple", RGB(red: 0.65, green: 0.3, blue: 1)),
        ("Pink", RGB(red: 1, green: 0.4, blue: 0.75)),
    ]
}
