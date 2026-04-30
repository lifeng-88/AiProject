//
//  PushMarketingSheets.swift
//  bbb
//
//  参考 glam：`return_user_coins_claim` / `recharge_incentive_new_user` 全屏弹层（叠在 Tab 上，非系统 alert）。
//

import SwiftUI

// MARK: - 老用户回归领金币

struct PushCoinsClaimContext: Equatable, Identifiable {
    let campaignId: String?
    let claimId: String
    let rewardCoins: Int64

    var id: String { "\(claimId)-\(rewardCoins)" }
}

struct PushCoinsClaimSheet: View {
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var wallet: UserWalletStore
    @EnvironmentObject private var appLanguage: AppLanguageStore

    let context: PushCoinsClaimContext
    @Binding var isPresented: Bool

    @State private var isClaiming = false
    @State private var claimErrorMessage: String?

    var dimBackgroundOpacity: CGFloat = 0.48
    var showGradientBackdrop: Bool = false
    var tapOutsideToDismiss: Bool = true

    private let primaryPink = Color(red: 255 / 255, green: 79 / 255, blue: 163 / 255)
    private let primaryPurple = Color(red: 120 / 255, green: 55 / 255, blue: 180 / 255)
    private let goldAccent = Color(red: 255 / 255, green: 214 / 255, blue: 120 / 255)
    private let coinOrange = Color(red: 255 / 255, green: 160 / 255, blue: 60 / 255)

    var body: some View {
        let _ = appLanguage.preference
        ZStack {
            if showGradientBackdrop {
                RadialGradient(
                    colors: [primaryPurple.opacity(0.45), Color.clear],
                    center: .topTrailing,
                    startRadius: 40,
                    endRadius: 320
                )
                RadialGradient(
                    colors: [primaryPink.opacity(0.28), Color.clear],
                    center: .bottomLeading,
                    startRadius: 20,
                    endRadius: 260
                )
            }
            Color.black.opacity(dimBackgroundOpacity)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    if tapOutsideToDismiss { isPresented = false }
                }

            rewardCard
                .padding(.horizontal, 22)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(.dark)
    }

    private var rewardCard: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                coinCluster
                    .padding(.top, 8)
                    .padding(.bottom, 22)

                Text("专属回归礼")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                Text("欢迎回来！领取下方金币奖励，已存入活动资格。")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.white.opacity(0.62))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 6)
                    .padding(.top, 12)

                coinsPill
                    .padding(.top, 22)

                Text("限时活动 · 先到先得")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [goldAccent, Color(red: 230 / 255, green: 180 / 255, blue: 70 / 255)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .bbbLetterSpacing(1.2)
                    .padding(.top, 14)

                claimButton
                    .padding(.top, 22)
                if let claimErrorMessage {
                    Text(claimErrorMessage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(red: 255 / 255, green: 120 / 255, blue: 130 / 255))
                        .multilineTextAlignment(.center)
                        .padding(.top, 10)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 26)
            .padding(.top, 4)

            Button {
                isPresented = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.45))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isClaiming)
            .padding(.top, 10)
            .padding(.trailing, 10)
            .accessibilityLabel("关闭")
        }
        .background(cardBackground)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 32, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 48 / 255, green: 22 / 255, blue: 72 / 255),
                        Color(red: 18 / 255, green: 10 / 255, blue: 28 / 255),
                        Color(red: 8 / 255, green: 6 / 255, blue: 12 / 255)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.18),
                                primaryPink.opacity(0.35),
                                primaryPurple.opacity(0.22)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: primaryPurple.opacity(0.35), radius: 28, y: 14)
    }

    private var coinCluster: some View {
        ZStack {
            coinDisk(size: 36, glow: false)
                .scaleEffect(0.94)
                .rotationEffect(.degrees(-18))
                .offset(x: -50, y: 16)
            coinDisk(size: 36, glow: false)
                .scaleEffect(0.94)
                .rotationEffect(.degrees(18))
                .offset(x: 50, y: 16)
            coinDisk(size: 60, glow: true)
                .offset(y: -10)
                .zIndex(1)
        }
        .frame(height: 92)
    }

    private func coinDisk(size: CGFloat, glow: Bool) -> some View {
        ZStack {
            if glow {
                Circle()
                    .fill(goldAccent.opacity(0.38))
                    .frame(width: size * 1.45, height: size * 1.45)
                    .blur(radius: 14)
            }
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 255 / 255, green: 230 / 255, blue: 140 / 255),
                            Color(red: 220 / 255, green: 165 / 255, blue: 45 / 255)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.38), lineWidth: 1)
                )
                .shadow(color: goldAccent.opacity(glow ? 0.7 : 0.4), radius: glow ? 16 : 7, y: 3)
            Text("$")
                .font(.system(size: size * 0.36, weight: .heavy, design: .rounded))
                .foregroundColor(Color(red: 120 / 255, green: 72 / 255, blue: 18 / 255))
        }
    }

    private var coinsPill: some View {
        Text("\(formatCoins(context.rewardCoins)) 金币")
            .font(.system(size: 26, weight: .heavy, design: .rounded))
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .foregroundStyle(
                LinearGradient(
                    colors: [primaryPink, coinOrange],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.55))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [primaryPink.opacity(0.45), Color.white.opacity(0.08)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
            .shadow(color: primaryPink.opacity(0.4), radius: 14, y: 4)
    }

    private var claimButton: some View {
        Button(action: claimGift) {
            Group {
                if isClaiming {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(.black.opacity(0.75))
                        Text("领取中…")
                            .font(.system(size: 16, weight: .heavy))
                            .foregroundColor(.black.opacity(0.88))
                    }
                } else {
                    Text("立即领取")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundColor(.black.opacity(0.88))
                        .tracking(0.8)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 255 / 255, green: 105 / 255, blue: 180 / 255),
                                primaryPink
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: primaryPink.opacity(0.65), radius: 18, y: 8)
                    .shadow(color: primaryPink.opacity(0.35), radius: 28, y: 12)
            )
        }
        .buttonStyle(.plain)
        .disabled(isClaiming)
    }

    private func claimGift() {
        Task {
            guard let uid = await MainActor.run(body: { auth.userId }), !uid.isEmpty else {
                await MainActor.run {
                    claimErrorMessage = "请先登录"
                }
                return
            }
            await MainActor.run {
                isClaiming = true
                claimErrorMessage = nil
            }
            let result = await UserAPI.redeemRedemptionCode(userid: uid, code: context.claimId)
            await MainActor.run {
                isClaiming = false
            }
            switch result {
            case .success:
                await BalanceManager.shared.refreshBalance()
                await MainActor.run {
                    isPresented = false
                }
            case .failure(let error):
                await MainActor.run {
                    claimErrorMessage = error.userMessage
                }
            }
        }
    }

    private func formatCoins(_ n: Int64) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

// MARK: - 新用户充值加赠

struct RechargeIncentiveSheetContext: Equatable, Identifiable {
    let campaignId: String?
    let offerId: String
    let appleProductId: String
    let amountCentsUsd: Int64
    let baseCoins: Int32
    let bonusCoins: Int32

    var id: String { "\(offerId)-\(appleProductId)-\(amountCentsUsd)-\(baseCoins)-\(bonusCoins)" }

    init(attribution: RechargeOrderPushAttribution) {
        campaignId = attribution.campaignId
        offerId = attribution.offerId
        appleProductId = attribution.appleProductId
        amountCentsUsd = attribution.amountCentsUsd
        baseCoins = attribution.baseCoins
        bonusCoins = attribution.bonusCoins
    }
}

struct RechargeIncentiveSheet: View {
    @EnvironmentObject private var appLanguage: AppLanguageStore

    let context: RechargeIncentiveSheetContext
    @Binding var isPresented: Bool
    var onChoosePayment: (() -> Void)? = nil

    var dimBackgroundOpacity: CGFloat = 0.48
    var showGradientBackdrop: Bool = false
    var tapOutsideToDismiss: Bool = true

    private let primaryPink = Color(red: 255 / 255, green: 124 / 255, blue: 245 / 255)
    private let surfaceColor = Color(red: 28 / 255, green: 22 / 255, blue: 42 / 255)
    private let bonusGold = Color(red: 255 / 255, green: 215 / 255, blue: 9 / 255)
    private let onPrimaryLabel = Color(red: 88 / 255, green: 0 / 255, blue: 88 / 255)
    private let giftGradientTop = Color(red: 74 / 255, green: 58 / 255, blue: 107 / 255)

    var body: some View {
        let _ = appLanguage.preference
        ZStack {
            if showGradientBackdrop {
                RadialGradient(
                    colors: [primaryPink.opacity(0.35), Color.clear],
                    center: .topTrailing,
                    startRadius: 40,
                    endRadius: 320
                )
                RadialGradient(
                    colors: [primaryPink.opacity(0.18), Color.clear],
                    center: .bottomLeading,
                    startRadius: 20,
                    endRadius: 260
                )
            }
            Color.black.opacity(dimBackgroundOpacity)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    if tapOutsideToDismiss { isPresented = false }
                }

            card
                .padding(.horizontal, 22)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(.dark)
    }

    private var card: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                giftHero
                    .padding(.bottom, 8)

                Text("限时加赠")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundColor(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .bbbLetterSpacing(2)

                Text(formatUSDCents(context.amountCentsUsd))
                    .font(.system(size: 48, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, primaryPink],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .minimumScaleFactor(0.45)
                    .lineLimit(1)
                    .shadow(color: primaryPink.opacity(0.45), radius: 12, y: 4)
                    .padding(.top, 8)

                VStack(spacing: 16) {
                    HStack {
                        Text("基础金币")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.55))
                        Spacer()
                        Text(formatCoinInteger(context.baseCoins))
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                    }
                    if context.bonusCoins > 0 {
                        HStack {
                            Text("额外赠送")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.55))
                            Spacer()
                            Text("+\(formatCoinInteger(context.bonusCoins))")
                                .font(.system(size: 18, weight: .black))
                                .foregroundColor(bonusGold)
                        }
                    }
                }
                .padding(.top, 24)
                .padding(.horizontal, 4)

                if let onChoosePayment {
                    Button(action: { onChoosePayment() }) {
                        Text("选择支付")
                            .font(.system(size: 17, weight: .heavy))
                            .foregroundColor(onPrimaryLabel)
                            .textCase(.uppercase)
                            .bbbLetterSpacing(1.2)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(primaryPink)
                                    .shadow(color: primaryPink.opacity(0.45), radius: 16, y: 4)
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 28)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 24)
            .padding(.top, 8)

            Button {
                isPresented = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white.opacity(0.45))
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
            .padding(.trailing, 12)
            .accessibilityLabel("关闭")
        }
        .frame(maxWidth: 400)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(surfaceColor)
                .shadow(color: .black.opacity(0.55), radius: 28, y: 14)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    private var giftHero: some View {
        ZStack {
            Circle()
                .fill(primaryPink.opacity(0.22))
                .frame(width: 200, height: 200)
                .blur(radius: 36)
                .scaleEffect(0.75)
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [giftGradientTop, surfaceColor],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        Circle()
                            .stroke(primaryPink.opacity(0.22), lineWidth: 1)
                    )
                Image(systemName: "gift.fill")
                    .font(.system(size: 58))
                    .foregroundStyle(primaryPink)
                    .shadow(color: primaryPink.opacity(0.55), radius: 14, y: 2)
            }
            .frame(width: 160, height: 160)
            .clipShape(Circle())
        }
        .frame(height: 168)
    }

    private func formatUSDCents(_ cents: Int64) -> String {
        let n = NSDecimalNumber(value: Double(cents)).dividing(by: 100)
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.locale = Locale(identifier: "en_US")
        return f.string(from: n) ?? String(format: "$%.2f", Double(cents) / 100.0)
    }

    private func formatCoinInteger(_ n: Int32) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

// MARK: - iOS 15：`View.tracking` / `Text.tracking` 仅 iOS 16+
private extension View {
    @ViewBuilder
    func bbbLetterSpacing(_ points: CGFloat) -> some View {
        if #available(iOS 16.0, *) {
            self.tracking(points)
        } else {
            self
        }
    }
}
