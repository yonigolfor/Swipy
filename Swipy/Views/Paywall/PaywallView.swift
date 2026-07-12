import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var premiumManager = PremiumManager.shared
    @ObservedObject private var dailyLimit = DailyLimitService.shared

    // Decided once per presentation, before first render — avoids a post-layout flash.
    @State private var headerVariant: Bool = Bool.random()
    @State private var selectedTier: PremiumTier = .yearly
    // Starts nil (not `.yearly.id`) so the `.task` below is a genuine transition —
    // `.scrollPosition(id:)` only drives a scroll-to when the bound value actually
    // changes, so seeding it with the same value it already holds is a no-op.
    @State private var scrollPosition: PremiumTier.ID?

    @State private var shimmerPhase: CGFloat = -1.0
    @State private var crownGlow: Double = 0.5
    @State private var appeared = false
    @State private var showShareSheet = false
    @State private var showBonusToast = false

    private let bottomFadeColor = Color(red: 0.03, green: 0.02, blue: 0.10)

    var body: some View {
        ZStack {
            background

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    headerSection
                        .padding(.bottom, 36)
                    benefitsCard
                        .padding(.bottom, 32)
                    pricingRow
                        .padding(.bottom, 16)

                    if !dailyLimit.hasSharedToday {
                        shareButton
                            .padding(.bottom, 16)
                    }

                    restoreButton
                }
                .padding(.horizontal, 28)
                .padding(.top, 76)
                .padding(.bottom, 24)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 30)
            .safeAreaInset(edge: .bottom) {
                bottomCTASection
            }

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
                        .padding(.bottom, 160)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: ShareSheet.makeShareItems()) {
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
                    bottomFadeColor,
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
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 10) {
                Text(String(localized: headerVariant ? "paywall.title.a" : "paywall.title.b"))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(String(localized: "paywall.subtitle"))
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.60))
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
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
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
    }

    // MARK: - Pricing

    private struct PricingCardView: View {
        let tier: PremiumTier
        let product: Product?
        let isSelected: Bool
        let isPurchasing: Bool
        let onTap: () -> Void

        var body: some View {
            Button(action: onTap) {
                VStack(spacing: 10) {
                    if tier == .yearly {
                        Text(String(localized: "paywall.tier.bestValue"))
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(.black.opacity(0.25)))
                            .foregroundStyle(
                                isSelected
                                    ? Color.black.opacity(0.75)
                                    : Color(red: 1.0, green: 0.86, blue: 0.3)
                            )
                    }

                    Text(tier.displayName)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))

                    Text(product?.displayPrice ?? "—")
                        .font(.system(size: 24, weight: .bold, design: .rounded))

                    if tier == .yearly {
                        Text(String(localized: "paywall.tier.savings"))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                    }
                }
                .foregroundStyle(.white)
                .frame(width: 148, height: 148)
                .background(
                    Group {
                        if isSelected {
                            Color.clear.premiumGoldBackground(cornerRadius: 20)
                        } else {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(.white.opacity(0.055))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(.white.opacity(0.10), lineWidth: 1)
                                )
                        }
                    }
                )
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isSelected)
            }
            .disabled(isPurchasing)
        }
    }

    private var pricingRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(PremiumTier.allCases) { tier in
                    PricingCardView(
                        tier: tier,
                        product: premiumManager.products[tier],
                        isSelected: selectedTier == tier,
                        isPurchasing: premiumManager.isPurchasing,
                        onTap: { selectedTier = tier }
                    )
                }
            }
            .padding(.horizontal, 28)
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $scrollPosition, anchor: .center)
        .padding(.horizontal, -28)
        // Re-assert the centered position once layout has settled — the initial
        // @State value alone doesn't reliably stick for a ScrollView nested inside
        // another ScrollView inside a fullScreenCover. Content is still opacity 0
        // at this point (see `appeared`), so the correction is invisible.
        .task { scrollPosition = selectedTier.id }
        .onChange(of: selectedTier) { _, newTier in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                scrollPosition = newTier.id
            }
        }
    }

    // MARK: - Share

    private var shareButton: some View {
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
                    .fill(.ultraThinMaterial.opacity(0.4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(.white.opacity(0.25), lineWidth: 1.25)
                    )
            )
        }
    }

    // MARK: - Floating Bottom CTA

    /// Dynamic label: falls back to the plain tier name while the product hasn't
    /// resolved yet (card stays selectable, but the CTA can't show a price).
    /// Recurring tiers show a per-period price ("$4.99/month"), not "total" —
    /// only Lifetime is an actual one-time total charge.
    private var ctaTitle: String {
        guard let product = premiumManager.products[selectedTier] else {
            return String(localized: selectedTier == .lifetime ? "paywall.cta.lifetime" : "paywall.cta.subscribe")
        }
        switch selectedTier {
        case .monthly:
            return String(format: String(localized: "paywall.cta.subscribe.monthly.withPrice"), product.displayPrice)
        case .yearly:
            return String(format: String(localized: "paywall.cta.subscribe.yearly.withPrice"), product.displayPrice)
        case .lifetime:
            return String(format: String(localized: "paywall.cta.lifetime.withPrice"), product.displayPrice)
        }
    }

    private var bottomCTASection: some View {
        VStack(spacing: 10) {
            if let error = premiumManager.errorMessage {
                Text(error)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Color.swipeRed)
                    .multilineTextAlignment(.center)
            }

            if selectedTier == .lifetime && premiumManager.hasActiveSubscription {
                Text(String(localized: "paywall.tier.lifetime.doubleBillingNote"))
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
            }

            Button {
                guard let product = premiumManager.products[selectedTier] else { return }
                Task { await premiumManager.purchase(product) }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.clear)
                        .frame(height: 58)
                        .premiumGoldBackground(cornerRadius: 18)

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
                            Text(ctaTitle)
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                    }
                }
            }
            .disabled(premiumManager.isPurchasing || premiumManager.products[selectedTier] == nil)
        }
        .padding(.horizontal, 28)
        .padding(.top, 22)
        .padding(.bottom, 14)
        .background(
            LinearGradient(
                colors: [bottomFadeColor.opacity(0), bottomFadeColor.opacity(0.92), bottomFadeColor],
                startPoint: .top,
                endPoint: .bottom
            )
            .padding(.top, -44)
            .allowsHitTesting(false)
        )
        .opacity(appeared ? 1 : 0)
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
