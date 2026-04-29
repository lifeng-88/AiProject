//
//  RechargeResultOverlay.swift
//  bbb
//
//  充值结果浮层：成功态对齐产品稿（RECHARGE SUCCESS + 套餐金币/赠送 + GET STARTED）
//

import SwiftUI

enum RechargePaymentOutcome: Equatable {
    /// 展示数值为所选套餐的 `totalCoins` / `bonus`（与套餐卡一致）；`newBalanceFormatted` 为同步后的本地展示余额（千分位）
    case success(totalCoins: Int, bonusCoins: Int, newBalanceFormatted: String?)
    case failed(message: String)
    /// 已跳转系统浏览器 / 外链支付页；`orderId` 用于回到前台或点「好」时查询 `/v1/orders/{id}/payment_status`
    case openedPaymentPage(message: String, orderId: String, package: RechargePackageModel)
}

struct RechargeResultOverlay: View {
    let outcome: RechargePaymentOutcome
    var onDismiss: () -> Void
    /// 浏览器支付提示页：点「好」时主动查询订单状态（与前台自动查询互补）
    var onOpenedPaymentPageOK: (() async -> Void)? = nil
    /// 查询进行中，禁用按钮并显示进度
    var isQueryingBrowserPayment: Bool = false

    private let modalFill = Color(red: 28 / 255, green: 27 / 255, blue: 33 / 255)
    private let bonusYellow = Color(red: 250 / 255, green: 204 / 255, blue: 21 / 255)
    private let headerLavender = Color(red: 192 / 255, green: 132 / 255, blue: 252 / 255)

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            Group {
                switch outcome {
                case .success(let total, let bonus, let newBalance):
                    successCard(totalCoins: total, bonusCoins: bonus, newBalanceFormatted: newBalance)
                case .failed(let message):
                    compactCard(
                        title: AppLanguageStore.localized("recharge.result.pay_failed"),
                        subtitle: message,
                        iconSystemName: "xmark",
                        circleColors: [Color.red.opacity(0.85), Color.red.opacity(0.45)]
                    )
                case .openedPaymentPage(let message, _, _):
                    compactCard(
                        title: AppLanguageStore.localized("recharge.result.page_opened"),
                        subtitle: message,
                        iconSystemName: "safari",
                        circleColors: [Color.cyan.opacity(0.75), AppTheme.primary.opacity(0.55)],
                        primaryShowsProgress: isQueryingBrowserPayment,
                        onPrimary: {
                            guard let onOpenedPaymentPageOK else {
                                onDismiss()
                                return
                            }
                            Task { await onOpenedPaymentPageOK() }
                        }
                    )
                }
            }
            .padding(.horizontal, 28)
        }
        .bbbRefreshOnAppLanguage()
    }

    // MARK: - 成功态（设计稿）

    private func successCard(totalCoins: Int, bonusCoins: Int, newBalanceFormatted: String?) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 6) {
                Color.clear.frame(width: 28, height: 28)
                BBBTrackedText.text(AppLanguageStore.localized("recharge.result.title"), size: 13, weight: .heavy, tracking: 1.4, color: headerLavender)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.88))
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppLanguageStore.localized("recharge.result.close_a11y"))
            }
            .padding(.bottom, 22)

            HStack(alignment: .center, spacing: 14) {
                AppCoinIcon(size: 52, symbol: "$")

                VStack(alignment: .leading, spacing: 6) {
                    Text(String(format: AppLanguageStore.localized("recharge.result.coins_format"), totalCoins))
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundStyle(Color.white)
                        .fixedSize(horizontal: false, vertical: true)
                    if bonusCoins > 0 {
                        Text(String(format: AppLanguageStore.localized("recharge.result.bonus_format"), bonusCoins))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(bonusYellow)
                    }
                    if let bal = newBalanceFormatted, !bal.isEmpty {
                        Text(String(format: AppLanguageStore.localized("recharge.result.balance_format"), bal))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppTheme.onSurfaceVariant)
                            .padding(.top, 4)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.bottom, 26)

            Button(action: onDismiss) {
                Text(AppLanguageStore.localized("recharge.result.get_started"))
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(Color(red: 0.12, green: 0.1, blue: 0.2))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 200 / 255, green: 160 / 255, blue: 1.0),
                                AppTheme.primary,
                                AppTheme.primaryDim
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
                    .shadow(color: AppTheme.primary.opacity(0.35), radius: 12, y: 4)
            }
            .buttonStyle(.plain)
        }
        .padding(22)
        .frame(maxWidth: 340)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(modalFill.opacity(0.98))
        )
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.35))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [AppTheme.primary.opacity(0.35), Color.white.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.5), radius: 28, y: 14)
    }

    // MARK: - 失败 / 外链（紧凑卡片）

    private func compactCard(
        title: String,
        subtitle: String,
        iconSystemName: String,
        circleColors: [Color],
        primaryShowsProgress: Bool = false,
        onPrimary: (() -> Void)? = nil
    ) -> some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: circleColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)
                Image(systemName: iconSystemName)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)
            }

            Text(title)
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppTheme.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            Button(action: {
                if let onPrimary {
                    onPrimary()
                } else {
                    onDismiss()
                }
            }) {
                Group {
                    if primaryShowsProgress {
                        ProgressView()
                            .tint(.white)
                    } else {
                        BBBTrackedText.text(AppLanguageStore.localized("common.ok"), size: 14, weight: .heavy, tracking: 1.2)
                            .foregroundStyle(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppTheme.primaryGradient)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(primaryShowsProgress)
            .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: 300)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(AppTheme.surfaceContainer.opacity(0.96))
        )
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AppTheme.primary.opacity(0.2), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
    }
}

#Preview("Success") {
    ZStack {
        AppTheme.background
        RechargeResultOverlay(outcome: .success(totalCoins: 500, bonusCoins: 100, newBalanceFormatted: "12,580"), onDismiss: {})
    }
    .environmentObject(AppLanguageStore())
    .preferredColorScheme(.dark)
}

#Preview("Failed") {
    ZStack {
        AppTheme.background
        RechargeResultOverlay(outcome: .failed(message: "Network error"), onDismiss: {})
    }
    .environmentObject(AppLanguageStore())
    .preferredColorScheme(.dark)
}
