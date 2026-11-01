//
//  AppBadge.swift
//  HueBar · HueBar
//
//  Compact app identity for popup footers: mini logo, name and a spectrum-rimmed version pill.
//

import SwiftUI

/// "HueBar  v1.0.0" with the logo, used in footers.
struct AppBadge: View {
    var body: some View {
        HStack(spacing: 6) {
            HueLogo(size: 14)
            Text(AppInfo.name)
                .font(.caption.weight(.semibold))
            VersionPill()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(AppInfo.name) version \(AppInfo.version)\(AppInfo.buildDateText.map { ", built \($0)" } ?? "")")
    }
}

/// A tiny capsule showing the marketing version with a hue-gradient border; its tooltip adds
/// the build date.
struct VersionPill: View {
    var body: some View {
        Text("v\(AppInfo.version)")
            .font(.caption2.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary.opacity(0.6), in: Capsule())
            .overlay(
                Capsule().strokeBorder(
                    AngularGradient(
                        colors: [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink, .red],
                        center: .center
                    ),
                    lineWidth: 1
                )
                .opacity(0.7)
            )
            .help(AppInfo.buildDateText.map { "HueBar \(AppInfo.version), built \($0)" } ?? "HueBar \(AppInfo.version)")
    }
}
