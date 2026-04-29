//
//  RechargePaymentSelectionView.swift
//  bbb
//
//  Select Payment：TOTAL AMOUNT、币拆分；支付方式来自 `/v3/pay_channels`（PayChannelManager）
//

import SwiftUI

struct RechargePaymentSelectionView: View {
    let package: RechargePackageModel
    @Binding var cards: [SavedPaymentCard]
    @Binding var isPurchasing: Bool
    @ObservedObject private var payChannelManager = PayChannelManager.shared

    @State private var selectedChannelId: Int32?
    @State private var isLoadingChannels = true
    @State private var showAddCardSheet = false
    /// 与 `SKPaymentQueue.canMakePayments()` 一致；关闭时无法走 StoreKit / App Store 支付
    @State private var appStorePaymentsAllowed = true

    var onPay: (PayChannel) async -> Void
    var onDismiss: () -> Void

    private var selectedPayChannel: PayChannel? {
        guard let id = selectedChannelId else { return nil }
        return payChannelManager.payChannels.first { $0.id == id }
    }

    /// 顶部 TOTAL 中的「支付方式奖励」：仅当接口 `extraBonusPercent` 有值且非 Apple 渠道时展示（与 cell 一致：`base × 百分比 / 100`）
    private var paymentBonusCoins: Int {
        guard let pc = selectedPayChannel, !pc.isApplePay else { return 0 }
        return Self.estimatedChannelBonusCoins(packageBase: package.base, channel: pc)
    }

    private var displayedTotalCoins: Int {
        package.totalCoins + paymentBonusCoins
    }

    private var canSubmitPayment: Bool {
        if isPurchasing || isLoadingChannels { return false }
        guard selectedPayChannel != nil else { return false }
        if let pc = selectedPayChannel, pc.isApplePay {
            return appStorePaymentsAllowed
        }
        return true
    }

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                headerBar

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        totalAmountCard

                        if let pc = selectedPayChannel, pc.isApplePay, !appStorePaymentsAllowed {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 16))
                                Text(IAPManager.appStorePaymentsDisabledMessage)
                                    .font(.system(size: 11, weight: .medium))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .foregroundStyle(Color.orange.opacity(0.95))
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.orange.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.orange.opacity(0.25), lineWidth: 1)
                            )
                        }

                        BBBTrackedText.text(AppLanguageStore.localized("recharge.payment.method_section"), size: 10, weight: .bold, tracking: 2, color: AppTheme.outlineVariant)

                        if isLoadingChannels {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .tint(AppTheme.primary)
                                Spacer()
                            }
                            .padding(.vertical, 24)
                        } else if payChannelManager.payChannels.isEmpty {
                            Text(AppLanguageStore.localized("recharge.payment.none"))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(AppTheme.onSurface.opacity(0.75))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 8)
                        } else {
                            VStack(spacing: 10) {
                                ForEach(payChannelManager.payChannels) { channel in
                                    paymentChannelRow(channel)
                                }
                            }
                        }

                        Button {
                            guard canSubmitPayment, let pc = selectedPayChannel else { return }
                            Task { await onPay(pc) }
                        } label: {
                            HStack(spacing: 10) {
                                if isPurchasing {
                                    ProgressView()
                                        .tint(Color(red: 0.06, green: 0.05, blue: 0.12))
                                }
                                BBBTrackedText.text(isPurchasing ? AppLanguageStore.localized("recharge.processing") : AppLanguageStore.localized("recharge.payment.btn_now"), size: 13, weight: .heavy, tracking: 1.8)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .foregroundStyle(Color(red: 0.08, green: 0.06, blue: 0.14))
                            .background(AppTheme.premiumButtonGradient)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .shadow(color: AppTheme.primaryDim.opacity(0.35), radius: 10, y: 4)
                        }
                        .disabled(!canSubmitPayment)
                        .opacity(canSubmitPayment ? 1 : 0.55)

                        footerSecure
                    }
                    .padding(20)
                    .padding(.bottom, 28)
                }
            }
        }
        .tint(AppTheme.primary)
        .task {
            await loadPayChannels()
        }
        .onChange(of: payChannelManager.payChannels.map(\.id)) { _ in
            syncSelectionWithList()
        }
        .onAppear {
            appStorePaymentsAllowed = IAPManager.deviceAllowsInAppPurchases()
        }
        .sheet(isPresented: $showAddCardSheet) {
            AddPaymentCardView(cards: $cards) {
                showAddCardSheet = false
            }
        }
        .bbbRefreshOnAppLanguage()
    }

    private func loadPayChannels() async {
        await MainActor.run { isLoadingChannels = true }
        await payChannelManager.loadPayChannelsOnce()
        await MainActor.run {
            isLoadingChannels = false
            syncSelectionWithList()
        }
    }

    private func syncSelectionWithList() {
        let list = payChannelManager.payChannels
        guard !list.isEmpty else {
            selectedChannelId = nil
            return
        }
        if selectedChannelId == nil || !list.contains(where: { $0.id == selectedChannelId }) {
            selectedChannelId = list.first?.id
        }
    }

    private var headerBar: some View {
        HStack(alignment: .center) {
            Text(AppLanguageStore.localized("recharge.payment.title"))
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(AppTheme.onSurface)
            Spacer()
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppTheme.onSurface.opacity(0.9))
                    .frame(width: 32, height: 32)
                    .background(AppTheme.surfaceContainerHigh)
                    .clipShape(Circle())
            }
            .disabled(isPurchasing)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var totalAmountCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            BBBTrackedText.text(AppLanguageStore.localized("recharge.payment.total_amount"), size: 10, weight: .bold, tracking: 2, color: AppTheme.outlineVariant)

            HStack(alignment: .firstTextBaseline) {
                Text(String(format: AppLanguageStore.localized("recharge.payment.coins_format"), displayedTotalCoins))
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(AppTheme.onSurface)
                Spacer()
                Text(priceUSDDisplay)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AppTheme.primary)
            }

            coinsBreakdownRow

            Text(AppLanguageStore.localized("recharge.payment.disclaimer"))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppTheme.outlineVariant.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surfaceContainerHigh.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppTheme.outlineVariant.opacity(0.18), lineWidth: 1)
        )
    }

    private var coinsBreakdownRow: some View {
        HStack(spacing: 8) {
            Text("\(package.base)")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(AppTheme.onSurface)

            if package.bonus > 0 {
                Text(String(format: AppLanguageStore.localized("recharge.payment.bonus_label"), package.bonus))
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(AppTheme.onSurface)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppTheme.primaryDim.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            if paymentBonusCoins > 0 {
                Text(String(format: AppLanguageStore.localized("recharge.payment.channel_bonus_format"), paymentBonusCoins))
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(AppTheme.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(AppTheme.secondary, lineWidth: 1.5)
                    )
            }

            Spacer(minLength: 0)
        }
    }

    private var priceUSDDisplay: String {
        let p = package.price
        if p.hasPrefix("$") {
            return "USD " + String(p.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        return p
    }

    @ViewBuilder
    private func paymentChannelRow(_ channel: PayChannel) -> some View {
        let isSelected = selectedChannelId == channel.id
        HStack(spacing: 14) {
            payChannelIcon(channel)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .center, spacing: 8) {
                    Text(channel.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.onSurface)
                        .multilineTextAlignment(.leading)
                    if channel.isCreditCard {
                        Button {
                            showAddCardSheet = true
                        } label: {
                            BBBTrackedText.text(AppLanguageStore.localized("recharge.payment.add_card_short"), size: 11, weight: .heavy, tracking: 0.5, color: AppTheme.primary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(AppTheme.primary.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                if let typeSub = channel.paymentTypeSubtitle {
                    Text(typeSub)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppTheme.outlineVariant.opacity(0.88))
                }
                if let bonusText = bonusLineFromAPI(for: channel) {
                    Text(bonusText)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppTheme.secondary)
                }
                if channel.isApplePay {
                    Text(
                        appStorePaymentsAllowed
                            ? AppLanguageStore.localized("iap.store_purchases_label")
                            : IAPManager.appStorePaymentsDisabledMessage
                    )
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(appStorePaymentsAllowed ? AppTheme.outlineVariant.opacity(0.92) : Color.orange.opacity(0.95))
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            radioDot(isSelected: isSelected)
        }
        .padding(14)
        .background(AppTheme.surfaceContainerLow)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    isSelected ? AppTheme.primary.opacity(0.65) : AppTheme.outlineVariant.opacity(0.22),
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {
            selectedChannelId = channel.id
        }
    }

    /// 仅当接口 `extraBonusPercent` 解析出百分比时展示；奖励金币 = **套餐基础金币 × 百分比 / 100**（展示用，到账以后端为准）
    private func bonusLineFromAPI(for channel: PayChannel) -> String? {
        guard !channel.isApplePay else { return nil }
        guard let pct = channel.displayBonusPercentForUI else { return nil }
        let bonusCoins = Self.estimatedChannelBonusCoins(packageBase: package.base, channel: channel)
        guard bonusCoins > 0 else { return nil }
        let pctLabel = pct == floor(pct) ? "\(Int(pct))" : String(format: "%.1f", pct)
        return String(
            format: AppLanguageStore.localized("recharge.payment.bonus_api_format"),
            pctLabel,
            bonusCoins
        )
    }

    /// 渠道额外奖励金币（展示）：`package.base × displayBonusPercent / 100`
    private static func estimatedChannelBonusCoins(packageBase: Int, channel: PayChannel) -> Int {
        guard packageBase > 0, let pct = channel.displayBonusPercentForUI, pct > 0 else { return 0 }
        return Int((Double(packageBase) * pct / 100.0).rounded())
    }

    @ViewBuilder
    private func payChannelIcon(_ channel: PayChannel) -> some View {
        if let urlStr = channel.icon?.trimmingCharacters(in: .whitespacesAndNewlines),
           !urlStr.isEmpty,
           let url = URL(string: urlStr) {
            HomeCachedImage(url: url, priority: .utility, aspectFit: true)
                .frame(width: 40, height: 40)
                .background(AppTheme.surfaceContainerHighest.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            defaultPayChannelIcon(channel)
        }
    }

    @ViewBuilder
    private func defaultPayChannelIcon(_ channel: PayChannel) -> some View {
        if channel.isApplePay {
            ZStack {
                Circle()
                    .fill(AppTheme.surfaceContainerHighest)
                Image(systemName: "apple.logo")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }
        } else if channel.isCreditCard {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppTheme.surfaceContainerHighest)
                Image(systemName: "creditcard.fill")
                    .font(.title3)
                    .foregroundStyle(AppTheme.primary)
            }
        } else if channel.isRedirectPayment {
            iconPlaceholder(systemName: "safari")
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppTheme.surfaceContainerHighest)
                Image(systemName: "creditcard.fill")
                    .font(.title3)
                    .foregroundStyle(AppTheme.primary.opacity(0.9))
            }
        }
    }

    private func iconPlaceholder(systemName: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppTheme.surfaceContainerHighest)
            Image(systemName: systemName)
                .font(.title3)
                .foregroundStyle(AppTheme.primary.opacity(0.9))
        }
    }

    private func radioDot(isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .stroke(isSelected ? AppTheme.primary : AppTheme.outlineVariant, lineWidth: isSelected ? 6 : 2)
                .frame(width: 22, height: 22)
            if isSelected {
                Circle()
                    .fill(AppTheme.primary)
                    .frame(width: 10, height: 10)
            }
        }
    }

    private var footerSecure: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "shield.checkered")
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.outlineVariant.opacity(0.75))
            Text(AppLanguageStore.localized("recharge.payment.secure_line"))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppTheme.outlineVariant.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    RechargePaymentSelectionView(
        package: RechargePackageModel(
            packageId: 199,
            packageName: "Bundle",
            totalCoins: 600,
            base: 400,
            bonus: 100,
            price: "$4.99",
            originalPrice: nil,
            bonusLabel: "+50%"
        ),
        cards: .constant([SavedPaymentCard.defaultBoundVisa]),
        isPurchasing: .constant(false),
        onPay: { _ in },
        onDismiss: {}
    )
    .preferredColorScheme(.dark)
}
