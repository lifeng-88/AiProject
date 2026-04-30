//
//  HomeGenerationRechargeUpsellView.swift
//  bbb
//
//  模板生成页金币不足时：全屏推广弹层（对齐充值营销稿：权益列表 + 双套餐卡 + CTA）
//

import SwiftUI
import UIKit

/// 充值推广弹层（效果图）：背景 #0F0F1B、紫粉 CTA、粉角标 #FF2D78、金币 #FFD700
private enum HomeUpsellDesign {
    /// 稿图背景 #0F0F1B
    static let background = Color(red: 15 / 255, green: 15 / 255, blue: 27 / 255)
    static let purple = Color(red: 168 / 255, green: 85 / 255, blue: 247 / 255) // #A855F7
    static let purpleDeep = Color(red: 124 / 255, green: 58 / 255, blue: 237 / 255) // #7C3AED
    /// 角标强调粉 #FF2D78
    static let accentPink = Color(red: 255 / 255, green: 45 / 255, blue: 120 / 255)
    /// 副行赠送数字金色 #FFD700
    static let bonusGold = Color(red: 255 / 255, green: 215 / 255, blue: 0 / 255)
    /// 主按钮：紫 → 粉 横向渐变（与稿一致）
    static let ctaGradient = LinearGradient(
        colors: [purple, accentPink.opacity(0.95)],
        startPoint: .leading,
        endPoint: .trailing
    )
    static let cardFill = Color.white.opacity(0.045)
    static let cardFillSelected = Color.white.opacity(0.085)
    /// 未选中描边：深灰细线
    static let cardStrokeIdle = Color.white.opacity(0.14)
    /// 弹层总高度上限（相对屏高），避免过长
    static let panelMaxHeightRatio: CGFloat = 0.78
    static let panelMaxHeightCap: CGFloat = 520
    /// 双列套餐卡最小高度（右上胶囊不占正文流高度）
    static let packageCardMinHeight: CGFloat = 118
    static let panelCornerRadius: CGFloat = 24
    /// 面板整体相对屏底留白（数值越大弹层离屏底越远）
    static let panelBottomLiftFromScreen: CGFloat = 22
    static let scrollBottomPaddingAboveCTA: CGFloat = 12
    static let bottomBarItemSpacing: CGFloat = 14
    static let benefitsToCardsSpacing: CGFloat = 18
    /// 「+%」胶囊：字号与内边距略大；半高用于中心对齐卡片顶边
    static let upsellBadgeFontSize: CGFloat = 11
    static let upsellBadgeHPadding: CGFloat = 11
    static let upsellBadgeVPadding: CGFloat = 5
    static let upsellBadgeHalfHeight: CGFloat = 13
}

struct HomeGenerationRechargeUpsellView: View {
    @EnvironmentObject private var wallet: UserWalletStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var versionConfig: VersionConfigStore
    @EnvironmentObject private var appLanguage: AppLanguageStore
    @EnvironmentObject private var tabRouter: AppTabRouter
    @Environment(\.scenePhase) private var scenePhase

    var onClose: () -> Void
    /// 跳转完整充值 Tab（EXPLORE MORE）；会先关闭弹层
    var onExploreFullRecharge: () -> Void

    @State private var packages: [RechargePackageModel] = []
    @State private var domainPackages: [Package] = []
    @State private var selectedId: String?
    @State private var isLoadingPackages = true
    @State private var packagesError: String?
    @State private var checkoutPackage: RechargePackageModel?
    @State private var isPurchasing = false
    @State private var paymentOutcome: RechargePaymentOutcome?
    @State private var isQueryingBrowserPayment = false

    /// 弹层内仅展示排序后的前 N 个套餐，与完整充值页列表解耦
    private static let upsellVisiblePackageCount = 2

    private var savedCardsBinding: Binding<[SavedPaymentCard]> {
        Binding(
            get: { wallet.savedCards },
            set: { wallet.savedCards = $0 }
        )
    }

    /// 与 `RechargeView` 一致按 `packageId` 升序后，只取前两条用于双卡展示
    private var sortedPackagesForUpsell: [RechargePackageModel] {
        packages.sorted { $0.packageId < $1.packageId }
    }

    private var displayPackages: [RechargePackageModel] {
        Array(sortedPackagesForUpsell.prefix(Self.upsellVisiblePackageCount))
    }

    private var selectedPackage: RechargePackageModel? {
        if let id = selectedId, let p = displayPackages.first(where: { $0.id == id }) {
            return p
        }
        if displayPackages.count >= 2 { return displayPackages[1] }
        return displayPackages.first
    }

    /// 与效果图一致：有双档时默认选中第二档（高亮 / 更高赠送比例）
    private func syncDefaultSelectedIfNeeded() {
        guard !displayPackages.isEmpty else {
            selectedId = nil
            return
        }
        if selectedId == nil || displayPackages.first(where: { $0.id == selectedId }) == nil {
            selectedId = displayPackages.count >= 2 ? displayPackages[1].id : displayPackages[0].id
        }
    }

    /// 弹层总高度上限（屏高比例与硬上限取小）
    private var upsellPanelMaxHeight: CGFloat {
        min(UIScreen.main.bounds.height * HomeUpsellDesign.panelMaxHeightRatio, HomeUpsellDesign.panelMaxHeightCap)
    }

    /// 底部固定区下留白：与屏底 / Home Indicator 保留舒适间距
    private var bottomBarPaddingUnderPanel: CGFloat {
        let inset = Self.keyWindowSafeAreaBottomInset
        let base: CGFloat = 14
        if inset <= 0 { return base }
        return max(base, inset * 0.52 + 6)
    }

    private static var keyWindowSafeAreaBottomInset: CGFloat {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first(where: { $0.isKeyWindow }) else {
            return 0
        }
        return window.safeAreaInsets.bottom
    }

    var body: some View {
        let _ = appLanguage.preference
        ZStack {
            Color.black.opacity(0.62)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            VStack(spacing: 0) {
                headerRow
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 2)

                ScrollView {
                    scrollableUpsellBlock
                        .padding(.horizontal, 20)
                        .padding(.bottom, HomeUpsellDesign.scrollBottomPaddingAboveCTA)
                }
                .bbbScrollClipDisabledIfAvailable()
                .frame(maxHeight: .infinity)

                upsellBottomFixedBar
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .padding(.bottom, bottomBarPaddingUnderPanel)
            }
            .frame(maxWidth: 420)
            .frame(maxHeight: upsellPanelMaxHeight)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: HomeUpsellDesign.panelCornerRadius, style: .continuous)
                    .fill(HomeUpsellDesign.background)
                    .overlay(
                        RoundedRectangle(cornerRadius: HomeUpsellDesign.panelCornerRadius, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        HomeUpsellDesign.purple.opacity(0.35),
                                        Color.white.opacity(0.06),
                                        HomeUpsellDesign.accentPink.opacity(0.15)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
            .padding(.horizontal, 14)
            .padding(.bottom, HomeUpsellDesign.panelBottomLiftFromScreen)
            .shadow(color: HomeUpsellDesign.purple.opacity(0.32), radius: 32, y: 14)
        }
        .task {
            await versionConfig.refresh()
            await loadPackages()
        }
        .onChange(of: packages.map(\.id)) { _ in
            syncDefaultSelectedIfNeeded()
        }
        .sheet(item: $checkoutPackage) { pkg in
            RechargePaymentSelectionView(
                package: pkg,
                cards: savedCardsBinding,
                isPurchasing: $isPurchasing,
                onPay: { channel in await completePurchase(package: pkg, payChannel: channel) },
                onDismiss: {
                    if !isPurchasing { checkoutPackage = nil }
                }
            )
            .bbbSheetLargeIfAvailable()
        }
        .overlay {
            if let outcome = paymentOutcome {
                RechargeResultOverlay(
                    outcome: outcome,
                    onDismiss: {
                        let wasSuccess: Bool = {
                            if case .success = outcome { return true }
                            return false
                        }()
                        paymentOutcome = nil
                        if wasSuccess { onClose() }
                    },
                    onOpenedPaymentPageOK: {
                        await queryBrowserRedirectPaymentIfNeeded(isUserInitiated: true)
                    },
                    isQueryingBrowserPayment: isQueryingBrowserPayment
                )
                .zIndex(5000)
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                Task { await queryBrowserRedirectPaymentIfNeeded(isUserInitiated: false) }
            }
        }
    }

    /// 与 `RechargeView` 一致：浏览器支付返回后查单；图1「好」为手动查。
    private func queryBrowserRedirectPaymentIfNeeded(isUserInitiated: Bool) async {
        let snapshot = await MainActor.run { paymentOutcome }
        guard case .openedPaymentPage(_, let orderId, let package) = snapshot else { return }

        let busy = await MainActor.run { isQueryingBrowserPayment }
        if busy { return }

        await MainActor.run { isQueryingBrowserPayment = true }
        let result = await RechargeRepository.shared.getOrderPaymentStatus(orderId: orderId)
        switch result {
        case .failure(let err):
            await MainActor.run {
                isQueryingBrowserPayment = false
                if isUserInitiated {
                    paymentOutcome = .failed(message: err.userMessage)
                }
            }
        case .success(let resp):
            let raw = resp.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let paid = raw == "success" || raw == "paid" || raw == "completed"
            if paid {
                let fromApi = resp.goldAmount.map { Int($0) } ?? 0
                let coins = fromApi > 0 ? fromApi : package.totalCoins
                await MainActor.run { isQueryingBrowserPayment = false }
                await finalizeRechargeSuccessUI(
                    package: package,
                    coinsAddedForRecord: coins,
                    skipServerBalanceSync: false
                )
            } else if raw == "pending" || raw == "processing" {
                await MainActor.run {
                    isQueryingBrowserPayment = false
                    if isUserInitiated {
                        paymentOutcome = .failed(message: AppLanguageStore.localized("recharge.browser_pay.still_pending"))
                    }
                }
            } else {
                await MainActor.run {
                    isQueryingBrowserPayment = false
                    paymentOutcome = .failed(message: resp.message ?? AppLanguageStore.localized("recharge.error.payment_incomplete"))
                }
            }
        }
    }

    private func finalizeRechargeSuccessUI(
        package: RechargePackageModel,
        coinsAddedForRecord: Int,
        skipServerBalanceSync: Bool = false
    ) async {
        if !skipServerBalanceSync, let uid = auth.userId {
            await wallet.syncCoinBalanceFromServer(userId: uid)
        }
        await MainActor.run {
            wallet.appendRechargeRecordOnly(package: package, coinsAdded: coinsAddedForRecord)
            paymentOutcome = .success(
                totalCoins: package.totalCoins,
                bonusCoins: package.bonus,
                newBalanceFormatted: wallet.formattedCoinBalance
            )
        }
    }

    private var headerRow: some View {
        HStack(alignment: .center) {
            BBBTrackedText.text(
                AppLanguageStore.localized("recharge.list_title"),
                size: 12,
                weight: .heavy,
                tracking: 2.8,
                color: HomeUpsellDesign.purple.opacity(0.92)
            )
            Spacer(minLength: 8)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var benefitsBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            benefitRow(emoji: "🔒", key: "recharge.upsell.benefit.templates")
            benefitRow(emoji: "🪄", key: "recharge.upsell.benefit.effects")
            benefitRow(emoji: "🚀", key: "recharge.upsell.benefit.priority")
            benefitRow(emoji: "🖼️", key: "recharge.upsell.benefit.quality")
        }
    }

    /// 仅中间可滚动：权益 + 套餐（主按钮与底部说明固定在面板底部）
    private var scrollableUpsellBlock: some View {
        VStack(alignment: .leading, spacing: HomeUpsellDesign.benefitsToCardsSpacing) {
            benefitsBlock
                .padding(.top, 4)

            if isLoadingPackages && packages.isEmpty {
                ProgressView()
                    .tint(HomeUpsellDesign.purple)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else if let err = packagesError, packages.isEmpty {
                Text(err)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.onSurface.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            } else if displayPackages.isEmpty {
                Text(AppLanguageStore.localized("recharge.no_packages"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.onSurface.opacity(0.55))
                    .frame(maxWidth: .infinity)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(displayPackages) { pkg in
                        packageMiniCard(
                            pkg,
                            isSelected: selectedId == pkg.id
                        )
                    }
                }
                /// 胶囊一半在卡片顶边之上，预留顶距避免 ScrollView 裁切
                .padding(.top, HomeUpsellDesign.upsellBadgeHalfHeight)
            }
        }
    }

    /// 贴面板下缘：立即充值 → Explore more → 安全说明
    private var upsellBottomFixedBar: some View {
        VStack(spacing: HomeUpsellDesign.bottomBarItemSpacing) {
            rechargeNowButton
            exploreMoreButton
            secureFooter
        }
    }

    private func benefitRow(emoji: String, key: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(emoji)
                .font(.system(size: 17))
                .frame(width: 28, alignment: .center)
            Text(AppLanguageStore.localized(key))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 「+X%」：仅表示赠送金币相对**基础金币**的比例（与稿 +10% / +20% 一致）；不用售价折扣 `discountPercent`
    private func upsellBadgePlusPercent(_ pkg: RechargePackageModel) -> Int? {
        guard pkg.bonus > 0, pkg.base > 0 else { return nil }
        let rounded = (pkg.bonus * 100 + pkg.base / 2) / pkg.base
        return max(1, rounded)
    }

    /// 副行：基础量 + **金色赠送量** + 后缀（与 `recharge.package_bonus_format` 语义一致，仅突出赠送数字）
    private func packageUpsellBonusLine(_ pkg: RechargePackageModel) -> some View {
        let dim = Color.white.opacity(0.4)
        let suffix = AppLanguageStore.localized("recharge.package_bonus_suffix")
        return HStack(spacing: 3) {
            Text("\(pkg.base)")
                .foregroundStyle(dim)
            Text("+")
                .foregroundStyle(dim)
            Text("\(pkg.bonus)")
                .foregroundStyle(HomeUpsellDesign.bonusGold)
            Text(suffix)
                .foregroundStyle(dim)
        }
        .font(.system(size: 9, weight: .semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.78)
    }

    private func packageMiniCard(_ pkg: RechargePackageModel, isSelected: Bool) -> some View {
        let badgePct = upsellBadgePlusPercent(pkg)
        let badgeGlow: CGFloat = isSelected ? 10 : 5
        return Button {
            selectedId = pkg.id
        } label: {
            VStack(spacing: 4) {
                HStack(spacing: 5) {
                    AppCoinIcon(size: 20)
                    Text("\(pkg.totalCoins)")
                        .font(.system(size: 21, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.white)
                }
                .padding(.top, 2)

                if pkg.bonus > 0 {
                    packageUpsellBonusLine(pkg)
                }

                Text(pkg.price)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.white)
                    .padding(.top, 1)
            }
            .frame(maxWidth: .infinity, minHeight: HomeUpsellDesign.packageCardMinHeight, alignment: .center)
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? HomeUpsellDesign.cardFillSelected : HomeUpsellDesign.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? LinearGradient(
                                colors: [HomeUpsellDesign.purple, HomeUpsellDesign.purpleDeep, HomeUpsellDesign.accentPink.opacity(0.85)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            : LinearGradient(
                                colors: [HomeUpsellDesign.cardStrokeIdle, HomeUpsellDesign.cardStrokeIdle.opacity(0.5)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                        lineWidth: isSelected ? 2.5 : 1
                    )
            )
            .overlay(alignment: .topTrailing) {
                if let pct = badgePct {
                    Text("+\(pct)%")
                        .font(.system(size: HomeUpsellDesign.upsellBadgeFontSize, weight: .heavy))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, HomeUpsellDesign.upsellBadgeHPadding)
                        .padding(.vertical, HomeUpsellDesign.upsellBadgeVPadding)
                        .background(
                            Capsule(style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [HomeUpsellDesign.accentPink, HomeUpsellDesign.accentPink.opacity(0.78)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .shadow(color: HomeUpsellDesign.accentPink.opacity(0.5), radius: badgeGlow, y: 1)
                        .padding(.trailing, 8)
                        /// 顶对齐时胶囊几何中心落在卡片顶边（向上偏移约半高）
                        .offset(y: -HomeUpsellDesign.upsellBadgeHalfHeight)
                }
            }
            .shadow(color: isSelected ? HomeUpsellDesign.purple.opacity(0.55) : .clear, radius: isSelected ? 14 : 0, y: 5)
        }
        .buttonStyle(.plain)
    }

    private var rechargeNowButton: some View {
        Button {
            guard let pkg = selectedPackage else { return }
            Task {
                await versionConfig.refresh()
                let mode = await MainActor.run { versionConfig.rechargePresentationType }
                if mode == 1 {
                    await completePurchaseDirectIAP(package: pkg)
                } else {
                    await presentPaymentSelectionOrDirectAppleIfOnly(package: pkg)
                }
            }
        } label: {
            HStack(spacing: 10) {
                if isPurchasing {
                    ProgressView()
                        .tint(.white)
                }
                BBBTrackedText.text(
                    isPurchasing
                        ? AppLanguageStore.localized("recharge.processing").uppercased()
                        : AppLanguageStore.localized("recharge.now").uppercased(),
                    size: 14,
                    weight: .heavy,
                    tracking: 2.2,
                    color: .white
                )
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(HomeUpsellDesign.ctaGradient)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: HomeUpsellDesign.accentPink.opacity(0.35), radius: 20, y: 8)
        }
        .buttonStyle(.plain)
        .disabled(selectedPackage == nil || isLoadingPackages || isPurchasing)
    }

    private var exploreMoreButton: some View {
        Button {
            onClose()
            onExploreFullRecharge()
        } label: {
            HStack(spacing: 5) {
                Text(AppLanguageStore.localized("recharge.upsell.explore_more").uppercased())
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(HomeUpsellDesign.purple.opacity(0.88))
        }
        .buttonStyle(.plain)
    }

    private var secureFooter: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.4))
            BBBTrackedText.text(
                AppLanguageStore.localized("recharge.secure_footer"),
                size: 9,
                weight: .semibold,
                tracking: 1.4,
                color: Color.white.opacity(0.38)
            )
        }
        .frame(maxWidth: .infinity)
    }

    private func loadPackages() async {
        await MainActor.run {
            isLoadingPackages = true
            packagesError = nil
        }
        let result = await RechargeRepository.shared.getPackages()
        await MainActor.run {
            isLoadingPackages = false
            switch result {
            case .success(let list):
                domainPackages = list
                packages = list.map(RechargePackageModel.init(package:)).sorted { $0.packageId < $1.packageId }
                syncDefaultSelectedIfNeeded()
            case .failure(let err):
                domainPackages = []
                packages = []
                packagesError = err.userMessage
            }
        }
    }

    // MARK: - 支付逻辑（与 `RechargeView` 一致）

    /// 支付方式弹窗模式：若接口仅配置 Apple 内购一条，则不弹 Sheet，直接拉起 StoreKit
    private func presentPaymentSelectionOrDirectAppleIfOnly(package: RechargePackageModel) async {
        let mode = await MainActor.run { versionConfig.rechargePresentationType }
        if mode == 1 {
            await completePurchaseDirectIAP(package: package)
            return
        }
        await MainActor.run { isPurchasing = true }
        await PayChannelManager.shared.loadPayChannelsOnce()
        let channels = await MainActor.run { PayChannelManager.shared.payChannels }
        if channels.count == 1, let only = channels.first, only.isApplePay {
            await MainActor.run { isPurchasing = false }
            await completePurchase(package: package, payChannel: only)
            return
        }
        await MainActor.run {
            isPurchasing = false
            checkoutPackage = package
        }
    }

    private func completePurchaseDirectIAP(package: RechargePackageModel) async {
        await PayChannelManager.shared.loadPayChannelsOnce()
        let channels = await MainActor.run { PayChannelManager.shared.payChannels }
        let apple: PayChannel = channels.first(where: { $0.isApplePay })
            ?? channels.first(where: { $0.id == 1 })
            ?? PayChannel.fallbackApplePayForIAP
        await completePurchase(package: package, payChannel: apple)
    }

    private func completePurchase(package: RechargePackageModel, payChannel: PayChannel) async {
        guard auth.isAuthenticated else {
            await MainActor.run {
                paymentOutcome = .failed(message: AppLanguageStore.localized("recharge.error.login_first"))
            }
            return
        }
        guard let domain = domainPackages.first(where: { $0.id == package.packageId }) else {
            await MainActor.run {
                paymentOutcome = .failed(message: AppLanguageStore.localized("recharge.error.package_stale"))
            }
            return
        }

        let offerId = domain.offerIdForPushAttributedCreateOrderIfMatching()

        if !payChannel.isApplePay {
            await completeNonIAPPurchase(package: package, domain: domain, payChannel: payChannel, offerId: offerId)
            return
        }

        guard domain.resolvedAppleProductId != nil else {
            await MainActor.run {
                paymentOutcome = .failed(message: AppLanguageStore.localized("recharge.error.no_iap_product"))
            }
            return
        }
        guard IAPManager.deviceAllowsInAppPurchases() else {
            await MainActor.run {
                paymentOutcome = .failed(message: IAPManager.appStorePaymentsDisabledMessage)
            }
            return
        }
        await MainActor.run { isPurchasing = true }
        let iapChannelId = domain.iapPayChannelId ?? payChannel.id
        let result = await IAPManager.shared.runIAPPurchaseFlow(package: domain, payChannelId: iapChannelId, offerId: offerId)
        await MainActor.run {
            isPurchasing = false
            checkoutPackage = nil
        }
        if result.success, result.gold > 0 {
            await finalizeRechargeSuccessUI(package: package, coinsAddedForRecord: result.gold, skipServerBalanceSync: true)
        } else if result.success, result.gold == 0 {
            await MainActor.run { paymentOutcome = nil }
        } else {
            await MainActor.run {
                paymentOutcome = .failed(message: AppLanguageStore.localized("recharge.error.iap_failed_generic"))
            }
        }
    }

    private func completeNonIAPPurchase(
        package: RechargePackageModel,
        domain: Package,
        payChannel: PayChannel,
        offerId: String?
    ) async {
        guard let uid = auth.userId else {
            await MainActor.run { paymentOutcome = .failed(message: AppLanguageStore.localized("recharge.error.login_first")) }
            return
        }

        let payChannelId = payChannel.id
        let useCreditCardFlow = payChannel.isCreditCard
            || (payChannel.id == 2 && !payChannel.isRedirectPayment && !payChannel.isApplePay)
        let pageReturnURL = "\(APIBaseURL.effective)/payment/return"

        await MainActor.run { isPurchasing = true }

        if useCreditCardFlow {
            let orderResult = await RechargeAPI.createRechargeOrder(
                userId: uid,
                packageId: domain.id,
                payChannelId: payChannelId,
                returnUrl: nil,
                pageUrl: nil,
                payload: nil,
                offerId: offerId
            )
            switch orderResult {
            case .failure(let err):
                await MainActor.run {
                    isPurchasing = false
                    paymentOutcome = .failed(message: err.userMessage)
                }
                return
            case .success(let resp):
                let orderId = resp.orderId
                guard let uid64 = Int64(uid) else {
                    await MainActor.run {
                        isPurchasing = false
                        paymentOutcome = .failed(message: AppLanguageStore.localized("recharge.error.user_id_invalid"))
                    }
                    return
                }
                await PaymentCardManager.shared.loadPaymentCards(userId: uid64)
                guard let card = PaymentCardManager.shared.defaultCard else {
                    await MainActor.run {
                        isPurchasing = false
                        paymentOutcome = .failed(message: AppLanguageStore.localized("recharge.error.bind_card_first"))
                    }
                    return
                }
                let payload = "{\"payment_card_id\":\(card.id)}"
                let confirmResult = await RechargeRepository.shared.confirmRecharge(
                    orderId: orderId,
                    transactionId: "",
                    payChannelId: payChannelId,
                    payload: payload
                )
                await MainActor.run { isPurchasing = false }
                await handleNonIAPConfirmResult(confirmResult, package: package)
                return
            }
        }

        let redirectResult = await RechargeAPI.createRechargeOrder(
            userId: uid,
            packageId: domain.id,
            payChannelId: payChannelId,
            returnUrl: nil,
            pageUrl: pageReturnURL,
            payload: "{}",
            offerId: offerId
        )

        await MainActor.run { isPurchasing = false }

        switch redirectResult {
        case .failure(let err):
            await MainActor.run { paymentOutcome = .failed(message: err.userMessage) }
        case .success(let resp):
            if let urlStr = resp.paymentUrl,
               !urlStr.isEmpty,
               let url = URL(string: urlStr) {
                await MainActor.run {
                    checkoutPackage = nil
                    UIApplication.shared.open(url)
                    paymentOutcome = .openedPaymentPage(
                        message: AppLanguageStore.localized("recharge.error.open_browser_pay"),
                        orderId: resp.orderId,
                        package: package
                    )
                }
            } else {
                await MainActor.run {
                    paymentOutcome = .failed(message: AppLanguageStore.localized("recharge.error.no_payment_url"))
                }
            }
        }
    }

    private func handleNonIAPConfirmResult(
        _ result: Result<ConfirmRechargeResponse, AppError>,
        package: RechargePackageModel
    ) async {
        switch result {
        case .failure(let err):
            await MainActor.run { paymentOutcome = .failed(message: err.userMessage) }
        case .success(let response):
            let dup = !response.success && RechargeOrderVerification.isDuplicateOrderSuccess(response.message)
            if response.success || dup {
                let coins = Int(response.goldAmount ?? "") ?? 0
                if coins > 0 {
                    let balanceRaw = response.balance?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    await MainActor.run {
                        checkoutPackage = nil
                        if !balanceRaw.isEmpty {
                            wallet.applyServerBalanceString(balanceRaw)
                        }
                    }
                    await finalizeRechargeSuccessUI(
                        package: package,
                        coinsAddedForRecord: coins,
                        skipServerBalanceSync: !balanceRaw.isEmpty
                    )
                } else {
                    await MainActor.run {
                        checkoutPackage = nil
                        paymentOutcome = nil
                    }
                }
            } else {
                await MainActor.run {
                    paymentOutcome = .failed(message: response.message ?? AppLanguageStore.localized("recharge.error.payment_incomplete"))
                }
            }
        }
    }
}
