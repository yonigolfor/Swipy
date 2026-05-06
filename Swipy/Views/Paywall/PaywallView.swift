import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var premiumManager = PremiumManager.shared
    @ObservedObject private var dailyLimit = DailyLimitService.shared

    @State private var shimmerPhase: CGFloat = -1.0
    @State private var crownGlow: Double = 0.5
    @State private var appeared = false
    @State private var showShareSheet = false
    @State private var showBonusToast = false

    var body: some View {
        ZStack {
            background

            // Animated main content
            VStack(spacing: 0) {
                Spacer()
                headerSection
                    .padding(.bottom, 36)
                benefitsCard
                    .padding(.bottom, 32)
                ctaSection
                // Reserve space so the CTA doesn't drift too low
                Spacer().frame(height: 80)
            }
            .padding(.horizontal, 28)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 30)

            // X dismiss button — static, not animated
            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.55))
                            .padding(10)
                            .background(Circle().fill(.white.opacity(0.10)))
                    }
                    .padding(.leading, 20)
                    .padding(.top, 20)
                    Spacer()
                }
                Spacer()
            }

            // Debug reset button — DEBUG builds only
            #if DEBUG
            VStack {
                HStack {
                    Spacer()
                    Button {
                        DailyLimitService.shared.resetDailyCount()
                        dismiss()
                    } label: {
                        Text("🧪")
                            .font(.system(size: 22))
                            .padding(8)
                            .background(Circle().fill(.white.opacity(0.10)))
                    }
                    .padding(.trailing, 20)
                    .padding(.top, 20)
                }
                Spacer()
            }
            #endif

            // Restore Purchases — static at the bottom, never animated
            VStack {
                Spacer()
                restoreButton
                    .padding(.bottom, 48)
            }

            // Bonus toast — appears after a successful share
            if showBonusToast {
                VStack {
                    Spacer()
                    Text(String(localized: "paywall.share.bonus.toast"))
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            Capsule()
                                .fill(Color(red: 0.2, green: 0.8, blue: 0.4).opacity(0.92))
                                .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
                        )
                        .padding(.bottom, 110)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: [URL(string: "https://apps.apple.com/app/id6745854678")!]) {
                DailyLimitService.shared.applyShareBonus()
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    showBonusToast = true
                }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    withAnimation(.easeOut(duration: 0.3)) { showBonusToast = false }
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    dismiss()
                }
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) { appeared = true }
            startShimmer()
            startGlowPulse()
        }
        .onChange(of: premiumManager.isPremium) { _, isPremium in
            if isPremium { dismiss() }
        }
    }

    // MARK: - Background

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.04, blue: 0.12),
                    Color(red: 0.08, green: 0.06, blue: 0.20),
                    Color(red: 0.03, green: 0.02, blue: 0.10),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color(red: 0.5, green: 0.35, blue: 1.0).opacity(0.13))
                .frame(width: 350)
                .blur(radius: 90)
                .offset(x: -80, y: -220)

            Circle()
                .fill(Color(red: 1.0, green: 0.78, blue: 0.18).opacity(0.10))
                .frame(width: 280)
                .blur(radius: 80)
                .offset(x: 100, y: 260)
        }
        .ignoresSafeArea()
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 1.0, green: 0.86, blue: 0.3),
                                Color(red: 0.95, green: 0.60, blue: 0.08),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 84, height: 84)
                    .shadow(
                        color: Color(red: 1.0, green: 0.80, blue: 0.2).opacity(crownGlow),
                        radius: 30
                    )

                Image(systemName: "crown.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 10) {
                Text(String(localized: "paywall.title"))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text(String(format: String(localized: "paywall.subtitle"), dailyLimit.dailyLimit))
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.60))
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
            }
        }
    }

    // MARK: - Benefits

    private var benefitsCard: some View {
        VStack(spacing: 16) {
            benefitRow(icon: "infinity",    text: String(localized: "paywall.benefit.unlimited"))
            benefitRow(icon: "bolt.fill",   text: String(localized: "paywall.benefit.speed"))
            benefitRow(icon: "heart.fill",  text: String(localized: "paywall.benefit.support"))
            benefitRow(icon: "star.fill",   text: String(localized: "paywall.benefit.features"))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(.white.opacity(0.055))
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(.white.opacity(0.10), lineWidth: 1)
                )
        )
    }

    private func benefitRow(icon: String, text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(red: 1.0, green: 0.86, blue: 0.3), Color(red: 0.95, green: 0.60, blue: 0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 26)

            Text(text)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.88))

            Spacer()
        }
    }

    // MARK: - CTA

    private var ctaSection: some View {
        VStack(spacing: 10) {
            if let product = premiumManager.product {
                Text(product.displayPrice)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.42))
            }

            Button {
                Task { await premiumManager.purchase() }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.86, blue: 0.3),
                                    Color(red: 0.95, green: 0.63, blue: 0.10),
                                    Color(red: 0.82, green: 0.50, blue: 0.02),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(height: 58)
                        .shadow(
                            color: Color(red: 1.0, green: 0.75, blue: 0.15).opacity(0.55),
                            radius: 22,
                            y: 8
                        )

                    // Shimmer sweep
                    RoundedRectangle(cornerRadius: 18)
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0),
                                    .init(color: .white.opacity(0.38), location: 0.44),
                                    .init(color: .white.opacity(0.58), location: 0.50),
                                    .init(color: .white.opacity(0.38), location: 0.56),
                                    .init(color: .clear, location: 1.0),
                                ],
                                startPoint: UnitPoint(x: shimmerPhase - 0.35, y: 0.2),
                                endPoint: UnitPoint(x: shimmerPhase + 0.35, y: 0.8)
                            )
                        )
                        .frame(height: 58)

                    if premiumManager.isPurchasing {
                        ProgressView().tint(.white)
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 16, weight: .semibold))
                            Text(String(localized: "paywall.cta"))
                                .font(.system(size: 19, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(.white)
                    }
                }
            }
            .disabled(premiumManager.isPurchasing)

            if !dailyLimit.hasSharedToday {
                Button {
                    showShareSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .semibold))
                        Text(String(localized: "paywall.share.button"))
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(.white.opacity(0.80))
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.white.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(.white.opacity(0.15), lineWidth: 1)
                            )
                    )
                }
            }

            if let error = premiumManager.errorMessage {
                Text(error)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Color.swipeRed)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
        }
    }

    // MARK: - Restore

    private var restoreButton: some View {
        Button {
            Task { await premiumManager.restorePurchases() }
        } label: {
            Text(String(localized: "paywall.restore"))
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.38))
                .underline()
        }
        .disabled(premiumManager.isPurchasing)
    }

    // MARK: - Animations

    private func startShimmer() {
        shimmerPhase = -1.0
        withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false).delay(0.6)) {
            shimmerPhase = 2.0
        }
    }

    private func startGlowPulse() {
        withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
            crownGlow = 1.0
        }
    }
}

#Preview {
    PaywallView()
}
