//
//  GroupsListView.swift
//  HueBar · HueBar
//
//  Rooms and zones with group power, brightness, their scenes and member lights.
//

import HueKit
import SwiftUI

/// The Rooms tab: rooms then zones, each row expandable in place.
struct GroupsListView: View {
    @Environment(BridgeStore.self) private var store
    @State private var expanded: Set<String> = []

    var body: some View {
        if store.groups.isEmpty {
            ContentUnavailableView("No rooms or zones", systemImage: "square.split.bottomrightquarter", description: Text("Create rooms and zones in the Hue app and they will appear here."))
        } else {
            LazyVStack(alignment: .leading, spacing: 6) {
                if !store.rooms.isEmpty {
                    sectionHeader("Rooms")
                    ForEach(store.rooms) { group in groupRow(group) }
                }
                if !store.zones.isEmpty {
                    sectionHeader("Zones").padding(.top, 6)
                    ForEach(store.zones) { group in groupRow(group) }
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.leading, 4)
            .accessibilityAddTraits(.isHeader)
    }

    private func groupRow(_ group: HueGroup) -> some View {
        GroupRow(group: group, isExpanded: expanded.contains(group.id)) {
            if expanded.contains(group.id) { expanded.remove(group.id) } else { expanded.insert(group.id) }
        }
    }
}

/// One room or zone: group power, and when expanded its brightness, scenes and member lights.
struct GroupRow: View {
    @Environment(BridgeStore.self) private var store
    let group: HueGroup
    let isExpanded: Bool
    let toggleExpanded: () -> Void

    private var grouped: HueGroupedLight? { store.groupedLight(for: group) }
    private var members: [HueLight] { store.lights(in: group) }
    private var isOn: Bool { grouped?.on?.on ?? members.contains { $0.on.on } }

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
                .accessibilityLabel(isExpanded ? "Collapse \(group.metadata.name)" : "Expand \(group.metadata.name)")

                Image(systemName: group.type == .room ? "door.left.hand.closed" : "rectangle.3.group")
                    .foregroundStyle(isOn ? .orange : .secondary)
                    .frame(width: 16)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    EditableName(name: group.metadata.name) { store.rename(group, to: $0) }
                    Text(memberSummary).font(.caption2).foregroundStyle(.secondary)
                }

                Spacer(minLength: 4)

                Toggle(group.metadata.name, isOn: Binding(get: { isOn }, set: { store.setGroup(group, on: $0) }))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
            }
            .contentShape(Rectangle())
            .onTapGesture { toggleExpanded() }

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    BrightnessSlider(value: Binding(
                        get: { grouped?.dimming?.brightness ?? 100 },
                        set: { store.setGroup(group, brightness: $0) }
                    ))

                    let scenes = store.scenes(for: group)
                    if !scenes.isEmpty {
                        SceneChips(scenes: scenes)
                    }

                    ForEach(members) { light in
                        HStack(spacing: 8) {
                            ColorSwatch(color: displayColor(for: light), size: 10)
                            Text(light.metadata.name).font(.caption).lineLimit(1)
                            Spacer()
                            if let brightness = light.dimming?.brightness, light.on.on {
                                Text("\(Int(brightness))%").font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                            }
                            Toggle(light.metadata.name, isOn: Binding(get: { light.on.on }, set: { store.setLight(light, on: $0) }))
                                .toggleStyle(.switch)
                                .controlSize(.mini)
                                .labelsHidden()
                        }
                    }
                }
                .padding(.leading, 22)
            }
        }
        .padding(8)
        .background(.quaternary.opacity(isExpanded ? 0.6 : 0.35), in: RoundedRectangle(cornerRadius: 8))
        .animation(.easeInOut(duration: 0.15), value: isExpanded)
    }

    private var memberSummary: String {
        let on = members.filter(\.on.on).count
        switch members.count {
        case 0: return "No lights"
        case 1: return on == 1 ? "1 light, on" : "1 light, off"
        default: return "\(on) of \(members.count) lights on"
        }
    }
}

/// Horizontally scrolling scene buttons for one group.
struct SceneChips: View {
    @Environment(BridgeStore.self) private var store
    let scenes: [HueScene]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(scenes) { scene in
                    Button {
                        store.recall(scene)
                    } label: {
                        Text(scene.metadata.name)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                scene.isActive ? AnyShapeStyle(.tint.opacity(0.25)) : AnyShapeStyle(.quaternary),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(scene.isActive ? .isSelected : [])
                }
            }
        }
    }
}
