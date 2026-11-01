//
//  AboutView.swift
//  HueBar · HueBar
//
//  Compact About panel: logo, version and build date, author, license and source links.
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
                Text("Version \(AppInfo.version)\(AppInfo.build.map { " (build \($0))" } ?? "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if let built = AppInfo.buildDateText {
                    Text("Built \(built)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Text("Philips Hue lights and bridge control from your menu bar.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Divider()
            VStack(spacing: 6) {
                row("Author", AppInfo.author)
                row("License", AppInfo.license)
                row("Source", AppInfo.repositoryDisplay)
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
            Text(value).textSelection(.enabled)
        }
        .font(.caption)
    }
}
