//
//  HueLogo.swift
//  HueBar · HueBar
//
//  The app mark in SwiftUI: a spectrum ring around a glowing bulb, matching the app icon.
//

import SwiftUI

/// The HueBar mark at any size; `animated` spins the ring, used while discovery runs.
struct HueLogo: View {
    var size: CGFloat = 40
    var animated = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotation: Angle = .zero

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(
                    AngularGradient(
                        colors: [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink, .red],
                        center: .center
                    ),
                    lineWidth: size * 0.11
                )
                .rotationEffect(rotation)
                .shadow(color: .white.opacity(0.35), radius: size * 0.08)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(red: 1, green: 0.85, blue: 0.45).opacity(0.9), .clear],
                        center: .center, startRadius: 0, endRadius: size * 0.4
                    )
                )
            Image(systemName: "lightbulb.fill")
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .purple.opacity(0.5), radius: size * 0.05, y: size * 0.02)
        }
        .frame(width: size, height: size)
        .onAppear {
            guard animated, !reduceMotion else { return }
            withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) {
                rotation = .degrees(360)
            }
        }
        .accessibilityHidden(true)
    }
}
