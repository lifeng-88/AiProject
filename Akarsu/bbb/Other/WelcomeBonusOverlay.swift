//
//  WelcomeBonusOverlay.swift
//  bbb
//
//  首次登录成功：欢迎奖励弹窗（与产品稿一致，金币为 $ 圆标）
//

import SwiftUI

struct WelcomeBonusOverlay: View {
    /// 赠送金币数量（展示用；与服务端首登赠送一致时可改为接口值）
    var freeCoins: Int = 2
    var onCreateNow: () -> Void

    private let cardFill = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)
    private let highlightGold = Color(red: 250 / 255, green: 204 / 255, blue: 21 / 255)

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text(AppLanguageStore.localized("welcome.bonus.title"))
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundStyle(Color.white)
                    Text("🎁")
                        .font(.system(size: 22))
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 22)

                VStack(spacing: 14) {
                    HStack(alignment: .center, spacing: 6) {
                        Text(AppLanguageStore.localized("welcome.bonus.added_prefix"))
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(AppTheme.onSurface.opacity(0.92))
                        AppCoinIcon(size: 22, symbol: "$")
                        Text("\(freeCoins)")
                            .font(.system(size: 24, weight: .heavy))
                            .foregroundStyle(highlightGold)
                        Text(AppLanguageStore.localized("welcome.bonus.free_coins"))
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(AppTheme.onSurface.opacity(0.92))
                    }
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                    Text(AppLanguageStore.localized("welcome.bonus.body"))
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(AppTheme.onSurfaceVariant)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 26)

                Button(action: onCreateNow) {
                    Text(AppLanguageStore.localized("welcome.bonus.cta"))
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(Color(red: 0.12, green: 0.1, blue: 0.2))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(red: 147 / 255, green: 91 / 255, blue: 1.0),
                                    AppTheme.primary,
                                    Color(red: 0.95, green: 0.65, blue: 1.0)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                        .shadow(color: AppTheme.primary.opacity(0.4), radius: 14, y: 6)
                }
                .buttonStyle(.plain)
            }
            .padding(26)
            .frame(maxWidth: 340)
            .background(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.55), radius: 32, y: 16)
            .padding(.horizontal, 24)
        }
        .bbbRefreshOnAppLanguage()
    }
}

#Preview {
    ZStack {
        AppTheme.background
        WelcomeBonusOverlay(onCreateNow: {})
    }
    .environmentObject(AppLanguageStore())
    .preferredColorScheme(.dark)
}
