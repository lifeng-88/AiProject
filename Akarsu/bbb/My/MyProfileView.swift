//
//  MyProfileView.swift
//  bbb
//
//  参考设计稿：Profile 标题、居中 ID、双入口大卡、PERSONAL ASSETS / SUPPORT & ASSETS 分组、VERSION
//

import SwiftUI
import UIKit

struct MyProfileView: View {
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var tabRouter: AppTabRouter
    @EnvironmentObject private var appLanguage: AppLanguageStore

    @State private var selectedRoute: ProfileRoute?
    @State private var showCopiedToast = false
    @State private var showLoginSheet = false
    /// 连续点击用户 ID 区计数（10 次触发 RefreshToken）；超时清零
    @State private var userIdSecretTapCount = 0
    @State private var userIdSecretTapResetTask: Task<Void, Never>?
    @State private var refreshTokenDebugToast: String?
#if false
    /// 点击底部版本号：按序循环模拟远程推送（调试用）；`#if false` 关闭入口，改为 `true` 可恢复
    @State private var simPushStep: Int = 0
    @State private var simPushPayload: SimPushDebugPayload?
#endif

    private let horizontalPadding: CGFloat = 20

    var body: some View {
        let _ = appLanguage.preference
        NavigationView {
            ZStack {
                VStack(spacing: 0) {
                    headerBar

                    GeometryReader { geo in
                        ScrollView {
                            VStack(spacing: 24) {
                                profileIdSection

                                shortcutCardsRow

                                personalAssetsSection

                                supportAssetsSection

                                // 底部「版本 x.x」：原 `Button` 内为模拟推送调试；入口已关闭，仅展示文案
                                BBBTrackedText.text(versionFooterText, size: 10, weight: .semibold, tracking: 2.4, color: AppTheme.outlineVariant)
                                    .textCase(.uppercase)
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 12)
                            }
                            .padding(.horizontal, horizontalPadding)
                            .padding(.top, 8 + geo.safeAreaInsets.top)
                            /// 与 `HomeView` 一致：`GeometryReader` 在部分机型（如 iPhone SE）上 `safeAreaInsets.bottom` 为 0，
                            /// 未包含 `MainTabView.safeAreaInset` 自定义 TabBar 高度，需与 `MainTabBarMetrics` 取较大值，避免底部被挡。
                            .padding(.bottom, profileScrollBottomPadding(safeBottom: geo.safeAreaInsets.bottom))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .background(AppTheme.background.ignoresSafeArea())
                .bbbToolbarHiddenNavigationBar()

                NavigationLink(
                    destination: profilePushDestination,
                    isActive: Binding(
                        get: { selectedRoute != nil },
                        set: { if !$0 { selectedRoute = nil } }
                    )
                ) {
                    EmptyView()
                }
                .frame(width: 0, height: 0)
                .opacity(0)
            }
            .overlay(alignment: .top) {
                VStack(spacing: 8) {
                    if showCopiedToast {
                        Text(AppLanguageStore.localized("my.profile.id_copied"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppTheme.onSurface)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(AppTheme.surfaceContainerHigh)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(AppTheme.outlineVariant.opacity(0.2), lineWidth: 1))
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    if let msg = refreshTokenDebugToast {
                        Text(msg)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppTheme.onSurface)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(AppTheme.surfaceContainerHigh)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(AppTheme.outlineVariant.opacity(0.2), lineWidth: 1))
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .padding(.top, 8)
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: showCopiedToast)
            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: refreshTokenDebugToast)
            .sheet(isPresented: $showLoginSheet) {
                LoginView()
                    .environmentObject(auth)
            }
#if false
            .alert(
                "模拟推送",
                isPresented: Binding(
                    get: { simPushPayload != nil },
                    set: { if !$0 { simPushPayload = nil } }
                ),
                actions: {
                    Button("关闭", role: .cancel) {
                        simPushPayload = nil
                    }
                    Button("模拟发送") {
                        if let p = simPushPayload {
                            tabRouter.dispatchRemotePush(p.route)
                        }
                        simPushPayload = nil
                    }
                },
                message: {
                    if let p = simPushPayload {
                        Text(p.detailText)
                    }
                }
            )
#endif
            .onAppear {
                syncProfileNavDepth()
                pushProfileRouteIfDeepLinkPending()
                pushMyCreationsIfDeepLinkPending()
            }
            .onChange(of: tabRouter.selected) { _ in
                pushProfileRouteIfDeepLinkPending()
                pushMyCreationsIfDeepLinkPending()
            }
            .onChange(of: tabRouter.myCreationsDeepLinkToken) { _ in
                pushMyCreationsIfDeepLinkPending()
            }
            .onChange(of: tabRouter.pendingProfileRoute) { _ in
                pushProfileRouteIfDeepLinkPending()
            }
            .onChange(of: tabRouter.profileRouteDeepLinkToken) { _ in
                pushProfileRouteIfDeepLinkPending()
            }
            .onChange(of: selectedRoute) { _ in
                if selectedRoute == nil {
                    tabRouter.profileDetailPushed = false
                }
                syncProfileNavDepth()
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .tint(AppTheme.primary)
        .bbbRefreshOnAppLanguage()
    }

    @ViewBuilder
    private var profilePushDestination: some View {
        if let route = selectedRoute {
            ProfileRouteDestination(route: route)
                .bbbNavigationBarBackground(AppTheme.background)
                .bbbLocalizedNavigationBackButton()
        } else {
            EmptyView()
        }
    }

    private func syncProfileNavDepth() {
        let count = selectedRoute != nil ? 1 : 0
        DispatchQueue.main.async {
            tabRouter.profileNavigationStackCount = count
        }
    }

    /// 远程推送 `feedback_reply`：跳转「我的」并自动 push 反馈历史（可选滚动到 `feedback_id`）
    private func pushProfileRouteIfDeepLinkPending() {
        guard tabRouter.selected == .my, let route = tabRouter.pendingProfileRoute else { return }
        selectedRoute = route
        tabRouter.clearPendingProfileRoute()
    }

    /// 首页「生成中」横幅：跳转「我的」并自动打开「我的创作」且预选筛选
    private func pushMyCreationsIfDeepLinkPending() {
        guard tabRouter.selected == .my, tabRouter.myCreationsPendingFilter != nil else { return }
        selectedRoute = .creations
    }

    /// 列表底部与自定义 TabBar 的间距：测量可靠时用测量值，否则至少留出 `MainTabBarMetrics` 估算高度
    private func profileScrollBottomPadding(safeBottom: CGFloat) -> CGFloat {
        let base: CGFloat = 24
        let clearance: CGFloat
        if safeBottom >= 1 {
            clearance = max(safeBottom, MainTabBarMetrics.estimatedContentHeight)
        } else {
            clearance = MainTabBarMetrics.estimatedContentHeight
        }
        return base + clearance
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(AppLanguageStore.localized("my.profile.title"))
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [AppTheme.primary, AppTheme.primaryDim.opacity(0.92)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                Text(auth.isAuthenticated ? AppLanguageStore.localized("my.profile.subtitle_signed_in") : AppLanguageStore.localized("my.profile.subtitle_guest"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.onSurfaceVariant.opacity(0.9))
            }

            Spacer(minLength: 0)

            if !auth.isAuthenticated {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showLoginSheet = true
                } label: {
                    Text(AppLanguageStore.localized("my.profile.sign_in"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(
                            Capsule()
                                .fill(AppTheme.primary.opacity(0.14))
                                .overlay(
                                    Capsule()
                                        .stroke(AppTheme.primary.opacity(0.35), lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppLanguageStore.localized("my.profile.sign_in_a11y"))
            }

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                selectedRoute = .settings
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(AppTheme.onSurfaceVariant)
                    .frame(width: 44, height: 44)
                    .background(AppTheme.surfaceContainerHigh.opacity(0.9))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(AppTheme.outlineVariant.opacity(0.2), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppLanguageStore.localized("my.profile.settings_a11y"))
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, 10)
        .padding(.bottom, 18)
        .background(AppTheme.background)
    }

    // MARK: - ID（居中 + 复制）

    private var profileIdSection: some View {
        Button(action: handleProfileIdSectionTap) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "person.text.rectangle.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(AppTheme.primary.opacity(0.9))

                Text(String(format: AppLanguageStore.localized("my.profile.id_format"), auth.displayUserId))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppTheme.onSurface)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .minimumScaleFactor(0.75)

                Spacer(minLength: 8)

                Image(systemName: "doc.on.doc")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppTheme.surfaceContainerHigh.opacity(0.65))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AppTheme.outlineVariant.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 双入口大卡

    private var shortcutCardsRow: some View {
        HStack(alignment: .top, spacing: 12) {
            shortcutCard(
                icon: "sparkles",
                title: AppLanguageStore.localized("my.profile.shortcut.creations"),
                iconCircleFill: AppTheme.primary.opacity(0.22),
                iconColor: .white,
                action: { selectedRoute = .creations }
            )
            shortcutCard(
                icon: "wallet.pass.fill",
                title: AppLanguageStore.localized("recharge.record.title"),
                iconCircleFill: Color(red: 0.92, green: 0.72, blue: 0.2).opacity(0.28),
                iconColor: Color(red: 0.98, green: 0.88, blue: 0.45),
                action: { selectedRoute = .rechargeRecord }
            )
        }
    }

    private func shortcutCard(
        icon: String,
        title: String,
        iconCircleFill: Color,
        iconColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            VStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 56, height: 56)
                    .background(iconCircleFill)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.onSurface)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .padding(.horizontal, 10)
            .background(cardBackground(cornerRadius: 18))
            .shadow(color: Color.black.opacity(0.22), radius: 16, y: 6)
        }
        .buttonStyle(.plain)
    }

    // MARK: - PERSONAL ASSETS

    private var personalAssetsSection: some View {
        profileSection(title: AppLanguageStore.localized("my.profile.section.personal_assets")) {
            listRow(
                icon: "heart.fill",
                title: AppLanguageStore.localized("my.profile.row.likes"),
                iconTint: .white,
                action: { selectedRoute = .likes }
            )
        }
    }

    // MARK: - SUPPORT & ASSETS

    private var supportAssetsSection: some View {
        profileSection(title: AppLanguageStore.localized("my.profile.section.support_assets")) {
            VStack(spacing: 0) {
                listRow(icon: "doc.text", title: AppLanguageStore.localized("legal.user_agreement"), iconTint: AppTheme.onSurfaceVariant) {
                    selectedRoute = .userAgreement
                }
                thinDivider
                listRow(icon: "checkmark.shield", title: AppLanguageStore.localized("legal.privacy"), iconTint: AppTheme.onSurfaceVariant) {
                    selectedRoute = .privacy
                }
                thinDivider
                listRow(icon: "headphones", title: AppLanguageStore.localized("my.profile.row.feedback"), iconTint: AppTheme.onSurfaceVariant) {
                    selectedRoute = .feedback
                }
            }
        }
    }

    private func profileSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            BBBTrackedText.text(title, size: 10, weight: .semibold, tracking: 2.2, color: AppTheme.outlineVariant)

            content()
                .background(cardBackground(cornerRadius: 16))
        }
    }

    private func cardBackground(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(AppTheme.surfaceContainerLow)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(AppTheme.outlineVariant.opacity(0.14), lineWidth: 1)
            )
    }

    private var thinDivider: some View {
        Rectangle()
            .fill(AppTheme.outlineVariant.opacity(0.12))
            .frame(height: 1)
            .padding(.leading, 52)
    }

    private func listRow(
        icon: String,
        title: String,
        iconTint: Color = AppTheme.onSurfaceVariant,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(iconTint)
                    .frame(width: 24, alignment: .center)

                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppTheme.onSurface)

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.outlineVariant.opacity(0.85))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var versionFooterText: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        return String(format: AppLanguageStore.localized("legal.version_format"), short.uppercased())
    }

#if false
    private func presentNextSimulatedPushDialog() {
        let idx = simPushStep % Self.simPushDebugCases.count
        simPushStep += 1
        simPushPayload = Self.simPushDebugCases[idx]
    }

    /// 与网关约定一致的 `RemotePushRoute`，仅用于本机调试。
    private static let simPushDebugCases: [SimPushDebugPayload] = [
        SimPushDebugPayload(
            detailText: "push_type: generation_success\ntask_id: 1021825353905106944",
            route: .generationSuccess(taskId: "1021825353905106944")
        ),
        SimPushDebugPayload(
            detailText: "push_type: generation_failure\ntask_id: 1021825353905106944",
            route: .generationFailure(taskId: "1021825353905106944")
        ),
        SimPushDebugPayload(
            detailText: "push_type: feedback_reply\nfeedback_id: 10001\ncampaign_id: test_d7",
            route: .feedbackReply(feedbackId: "10001", campaignId: "test_d7")
        ),
        SimPushDebugPayload(
            detailText: "push_type: return_user_coins_claim\nclaim_id: claim_001\ncampaign_id: cmp_2\nreward_coins: 500",
            route: .returnUserCoinsClaim(
                ReturnUserCoinsClaimPayload(claimId: "claim_001", campaignId: "cmp_2", rewardCoins: 500)
            )
        ),
        SimPushDebugPayload(
            detailText: """
            push_type: recharge_incentive_new_user
            offer_id: offer_001
            apple_product_id: com.xmglamai.glamai.consumable.coins_20
            campaign_id: cmp_1
            amount_cents_usd: 499 / base_coins: 1000 / bonus_coins: 2000
            """,
            route: .rechargeIncentiveNewUser(
                RechargeNewUserOfferPayload(
                    offerId: "offer_001",
                    appleProductId: "com.xmglamai.glamai.consumable.coins_20",
                    campaignId: "cmp_1",
                    amountCentsUsd: 499,
                    baseCoins: 1000,
                    bonusCoins: 2000
                )
            )
        ),
        SimPushDebugPayload(
            detailText: "push_type: template_category\ntemplate_tab_id: 3\ncatalog_id: 1\ncampaign_id: test_cat",
            route: .templateCategory(
                HomeTemplateCategoryPush(templateTabId: 3, catalogId: 1, campaignId: "test_cat")
            )
        )
    ]
#endif

    private func copyUserId() {
        UIPasteboard.general.string = auth.userId ?? ""
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation { showCopiedToast = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            await MainActor.run {
                withAnimation { showCopiedToast = false }
            }
        }
    }

    /// 第 1 次点击复制 ID；连续 10 次（2s 内无中断则重新计数）触发 `AuthAPI` RefreshToken
    private func handleProfileIdSectionTap() {
        userIdSecretTapResetTask?.cancel()
        userIdSecretTapCount += 1

        if userIdSecretTapCount == 1 {
            copyUserId()
        }

        if userIdSecretTapCount >= 10 {
            userIdSecretTapResetTask?.cancel()
            userIdSecretTapCount = 0
            Task { await performDebugRefreshTokenFromSecretTaps() }
            return
        }

        userIdSecretTapResetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            userIdSecretTapCount = 0
        }
    }

    private func performDebugRefreshTokenFromSecretTaps() async {
        guard auth.isAuthenticated else {
            await MainActor.run {
                briefRefreshTokenToast(AppLanguageStore.localized("my.profile.debug.token_not_signed_in"))
            }
            return
        }
        guard let info = await AuthRepository.shared.getCurrentAuthInfo() else {
            await MainActor.run {
                briefRefreshTokenToast(AppLanguageStore.localized("my.profile.debug.token_no_auth_info"))
            }
            return
        }
        await MainActor.run {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        let result = await AuthRepository.shared.refreshToken(refreshToken: info.refreshToken)
        await MainActor.run {
            switch result {
            case .success:
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                briefRefreshTokenToast(AppLanguageStore.localized("my.profile.debug.token_refreshed"))
            case .failure(let err):
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                briefRefreshTokenToast(err.userMessage)
            }
        }
    }

    private func briefRefreshTokenToast(_ message: String) {
        withAnimation { refreshTokenDebugToast = message }
        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            await MainActor.run {
                withAnimation { refreshTokenDebugToast = nil }
            }
        }
    }
}

#if false
/// 版本号「模拟推送」弹窗携带的说明文案与路由
private struct SimPushDebugPayload {
    let detailText: String
    let route: RemotePushRoute
}
#endif

#Preview {
    MyProfileView()
        .environmentObject(AuthSessionStore())
        .environmentObject(AppTabRouter())
        .environmentObject(AppLanguageStore())
        .preferredColorScheme(.dark)
}
