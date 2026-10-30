//
//  ScenesView.swift
//  HueBar · HueBar
//
//  All scenes grouped by the room or zone they belong to.
//

import HueKit
import SwiftUI

/// The Scenes tab: one recall button per scene, grouped under its room or zone.
struct ScenesView: View {
    @Environment(BridgeStore.self) private var store

    var body: some View {
        let groupsWithScenes = store.groups.filter { !store.scenes(for: $0).isEmpty }
        if groupsWithScenes.isEmpty {
            ContentUnavailableView("No scenes", systemImage: "theatermasks", description: Text("Scenes created in the Hue app will show up here."))
        } else {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(groupsWithScenes) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.metadata.name)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 6)], spacing: 6) {
                            ForEach(store.scenes(for: group)) { scene in
                                Button {
                                    store.recall(scene)
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: scene.isActive ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(scene.isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                                            .font(.caption)
                                        Text(scene.metadata.name).font(.caption).lineLimit(1)
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .frame(maxWidth: .infinity)
                                    .background(
                                        scene.isActive ? AnyShapeStyle(.tint.opacity(0.2)) : AnyShapeStyle(.quaternary.opacity(0.5)),
                                        in: RoundedRectangle(cornerRadius: 6)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }
}
