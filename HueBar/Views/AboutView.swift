//
//  AboutView.swift
//  HueBar · HueBar
//
//  Compact About panel: logo, version, author, license and a link to the source repository.
//

import SwiftUI

/// About panel shown from the gear menu.
struct AboutView: View {
    @Environment(\.openURL) private var openURL
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            HueLogo(size: 72, animated: true)
                .padding(.top, 6)
            VStack(spacing: 2) {
                Text(AppInfo.name).font(.title2.weight(.semibold))
                Text("Version \(AppInfo.version)\(AppInfo.build.map { " (\($0))" } ?? "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Text("Philips Hue lights and bridge control from your menu bar.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Divider()
            VStack(spacing: 6) {
                row("Author", AppInfo.author)
                row("License", AppInfo.license)
            }
            HStack(spacing: 10) {
                Button {
                    openURL(AppInfo.repositoryURL)
                } label: {
                    Label("GitHub Repository", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Button {
                    openURL(AppInfo.licenseURL)
                } label: {
                    Label("License", systemImage: "doc.text")
                }
            }
            .controlSize(.small)
            Text(AppInfo.repositoryURL.absoluteString)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
            Button("Back", action: onBack)
                .buttonStyle(.borderless)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(14)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .font(.caption)
    }
}
