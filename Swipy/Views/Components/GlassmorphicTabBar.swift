//
//  GlassmorphicTabBar.swift
//  CleanSwipe
//

import SwiftUI

struct GlassmorphicTabBar: View {
    @Binding var selectedTab: Int
    let reviewBinCount: Int

    private let haptic = UIImpactFeedbackGenerator(style: .soft)

    private let tabs: [(icon: String, label: String)] = [
            ("line.3.horizontal.decrease.circle", String(localized: "tab.filters")),
            ("rectangle.stack", String(localized: "tab.swipe")),
            ("trash", String(localized: "tab.review"))
        ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<tabs.count, id: \.self) { index in
                tabButton(index: index)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 4)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay {
                    Color.white.opacity(0.05)
                }
                .overlay(alignment: .top) {
                    LinearGradient(
                        colors: [Color.white.opacity(0.25), Color.white.opacity(0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(height: 0.5)
                }
                .shadow(color: .black.opacity(0.08), radius: 20, x: 0, y: -10)
                .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: -2)
        }
        .onAppear { haptic.prepare() }
    }

    @ViewBuilder
    private func tabButton(index: Int) -> some View {
        let isSelected = selectedTab == index
        let tab = tabs[index]

        Button {
            guard selectedTab != index else { return }
            haptic.impactOccurred()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                selectedTab = index
            }
        } label: {
            ZStack {
                // Iridescent glow
                if isSelected {
                    AngularGradient(
                        colors: [.cyan, .purple, .pink, Color(red: 1, green: 0.8, blue: 0.2), .cyan],
                        center: .center
                    )
                    .blur(radius: 15)
                    .opacity(0.25)
                    .frame(width: 60, height: 60)
                    .clipShape(Circle())
                }

                VStack(spacing: 4) {
                    ZStack {
                        Image(systemName: isSelected ? tab.icon + ".fill" : tab.icon)
                            .font(.system(size: 22, weight: isSelected ? .semibold : .regular))
                            .foregroundColor(isSelected ? .primary : .secondary)
                            .scaleEffect(isSelected ? 1.15 : 1.0)
                            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)

                        if index == 2 && reviewBinCount > 0 {
                            Text("\(min(reviewBinCount, 99))")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .padding(3)
                                .background(Circle().fill(Color.red))
                                .offset(x: 12, y: -12)
                        }
                    }

                    Text(tab.label)
                        .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(isSelected ? .primary : .secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
        }
        .buttonStyle(.plain)
    }
}
