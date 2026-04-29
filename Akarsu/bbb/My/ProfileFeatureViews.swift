//
//  ProfileFeatureViews.swift
//  bbb
//
//  参考: my_creations_empty_state, recharge_record_refined_en, my_likes_empty_state
//

import SwiftUI
import UIKit

// MARK: - My Likes（本地收藏键 + 双列网格；封面/金币按需请求详情）

struct MyLikesView: View {
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var tabRouter: AppTabRouter
    @EnvironmentObject private var appLanguage: AppLanguageStore
    @State private var entries: [LocalFavoriteEntry] = []
    @State private var selectedTab: MyLikesTab = .all
    @State private var detailCard: HomeGridCardItem?
    /// 与首页瀑布流一致：详情接口构建的 `HomeGridCardItem`（含预览视频 / T1 转场图）
    @State private var likesGridItems: [HomeGridCardItem] = []
    @State private var likesGridLoading = false

    private var filteredEntries: [LocalFavoriteEntry] {
        switch selectedTab {
        case .all: return entries
        case .kind(let k): return entries.filter { $0.kind == k }
        }
    }

    /// 收藏集合或分类切换时重建网格数据
    private var likesGridSignature: String {
        "\(selectedTab.signatureKey)|" + filteredEntries.map(\.likeStateKey).joined(separator: "|")
    }

    var body: some View {
        let _ = appLanguage.preference
        ZStack {
            AppTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                MyLikesKindTabBar(selected: $selectedTab)
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 12)

                if entries.isEmpty {
                    emptyStateAll
                } else if filteredEntries.isEmpty {
                    emptyStateForTab
                } else {
                    gridContent
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                BBBTrackedText.text(AppLanguageStore.localized("my.likes.title"), size: 16, weight: .heavy, tracking: 1.5, color: AppTheme.primary)
            }
        }
        .onAppear(perform: reload)
        .onChange(of: auth.userId) { _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: .localFavoriteTemplateStoreDidChange)) { _ in reload() }
        .background(
            NavigationLink(
                destination: likesDetailDestination,
                isActive: Binding(
                    get: { detailCard != nil },
                    set: { if !$0 { detailCard = nil } }
                )
            ) {
                EmptyView()
            }
            .frame(width: 0, height: 0)
            .opacity(0)
        )
        .onChange(of: detailCard) { new in
            tabRouter.profileDetailPushed = (new != nil)
        }
        .onDisappear {
            tabRouter.profileDetailPushed = false
        }
    }

    @ViewBuilder
    private var likesDetailDestination: some View {
        if let card = detailCard {
            HomeTemplateDetailView(
                gridItem: card,
                onUseTemplate: { feedItem, image in
                    detailCard = nil
                    tabRouter.select(.home)
                    NotificationCenter.default.post(
                        name: .homeRequestPrimaryGenerate,
                        object: feedItem,
                        userInfo: [
                            "prefilledImage": image,
                            "browseOtherReturnTabRaw": AppTab.my.rawValue
                        ]
                    )
                }
            )
        } else {
            EmptyView()
        }
    }

    private var emptyStateAll: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)
            Image(systemName: "heart")
                .font(.system(size: 56))
                .foregroundStyle(AppTheme.primary.opacity(0.4))
            Text(AppLanguageStore.localized("my.likes.empty"))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppTheme.onSurface)
            Text(AppLanguageStore.localized("my.likes.empty_detail"))
                .font(.subheadline)
                .foregroundStyle(AppTheme.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Spacer(minLength: 0)
        }
    }

    private var emptyStateForTab: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 40)
            Text(String(format: AppLanguageStore.localized("my.likes.empty_tab_format"), selectedTab.localizedTabKindName))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppTheme.onSurface)
            Text(AppLanguageStore.localized("my.likes.empty_switch"))
                .font(.subheadline)
                .foregroundStyle(AppTheme.onSurfaceVariant)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private var gridContent: some View {
        HomeGridFeedView(
            items: likesGridItems,
            showSkeleton: likesGridLoading && likesGridItems.isEmpty,
            cellAspectRatio: 9 / 16,
            likedKeys: Set(likesGridItems.map(\.likeStateKey)),
            requestingLikeKeys: [],
            onToggleLike: { unlikeGridItem($0) },
            onSelectItem: { detailCard = $0 },
            onRefresh: { await loadLikesGridItems(entries: filteredEntries) },
            hasMore: false,
            isLoadingMore: false,
            onLoadMore: nil,
            showsNoMoreFooter: false
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: likesGridSignature) {
            await loadLikesGridItems(entries: filteredEntries)
        }
    }

    private func reload() {
        entries = LocalFavoriteTemplateStore.favoriteEntries(forUserId: auth.userId)
    }

    private func unlikeGridItem(_ item: HomeGridCardItem) {
        var keys = LocalFavoriteTemplateStore.load(userId: auth.userId)
        keys.remove(item.likeStateKey)
        LocalFavoriteTemplateStore.save(keys, userId: auth.userId)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        reload()
    }

    private func loadLikesGridItems(entries: [LocalFavoriteEntry]) async {
        guard !entries.isEmpty else {
            await MainActor.run {
                likesGridItems = []
                likesGridLoading = false
            }
            return
        }
        await MainActor.run { likesGridLoading = true }
        var built: [HomeGridCardItem] = []
        for entry in entries {
            if let card = await gridCard(for: entry) {
                built.append(card)
            }
        }
        await MainActor.run {
            likesGridItems = built
            likesGridLoading = false
        }
    }

    private func gridCard(for entry: LocalFavoriteEntry) async -> HomeGridCardItem? {
        switch entry.kind {
        case .t1:
            let r = await TemplateRepository.shared.getImageTemplateDetail(tid: entry.templateId)
            if case .success(let t) = r { return HomeGridCardItem(imageTemplate: t) }
        case .t2:
            let r = await TemplateRepository.shared.getDancingTemplateDetail(tid: entry.templateId)
            if case .success(let t) = r { return HomeGridCardItem(dancingTemplate: t) }
        case .t3:
            let r = await TemplateRepository.shared.getVideoTemplateDetail(tid: entry.templateId)
            if case .success(let t) = r { return HomeGridCardItem(videoTemplate: t) }
        }
        return nil
    }
}

// MARK: - All / IMAGE / VIDEO / DANCE

private enum MyLikesTab: Hashable {
    case all
    case kind(TemplateResourceKind)

    var signatureKey: String {
        switch self {
        case .all: return "all"
        case .kind(let k): return k.rawValue
        }
    }
}

private struct MyLikesKindTabBar: View {
    @Binding var selected: MyLikesTab

    private let options: [(MyLikesTab, String)] = [
        (.all, "kind.all"),
        (.kind(.t1), "kind.image"),
        (.kind(.t3), "kind.video"),
        (.kind(.t2), "kind.dance")
    ]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(options, id: \.0) { tab, titleKey in
                let isOn = selected == tab
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selected = tab
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    BBBTrackedText.text(AppLanguageStore.localized(titleKey), size: 10, weight: .heavy, tracking: 1.2)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .foregroundStyle(isOn ? Color.white : AppTheme.onSurfaceVariant.opacity(0.55))
                        .background(
                            Capsule()
                                .fill(isOn ? AppTheme.primary.opacity(0.22) : Color.white.opacity(0.06))
                        )
                        .overlay(
                            Capsule()
                                .stroke(isOn ? AppTheme.primary.opacity(0.85) : Color.clear, lineWidth: 1.2)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private extension TemplateResourceKind {
    var tabLabel: String {
        switch self {
        case .t1: return AppLanguageStore.localized("kind.image")
        case .t2: return AppLanguageStore.localized("kind.dance")
        case .t3: return AppLanguageStore.localized("kind.video")
        }
    }

    /// 用于 `my.likes.empty_tab_format`（%@ 占位）
    var localizedTabKindName: String {
        tabLabel
    }
}

private extension MyLikesTab {
    /// 用于 `my.likes.empty_tab_format`（%@ 占位）
    var localizedTabKindName: String {
        switch self {
        case .all: return AppLanguageStore.localized("kind.all")
        case .kind(let k): return k.localizedTabKindName
        }
    }
}

struct ProfileSettingsView: View {
    @EnvironmentObject private var appLanguage: AppLanguageStore
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var notificationPermission = NotificationPermissionStore()
    /// 預設關閉；未寫入過 `UserDefaults` 時為 `false`（已升級用戶若先前開啟過仍讀持久化值）
    @AppStorage("profileProductUpdates") private var productUpdatesOn = false
    @State private var showNotificationPrePrompt = false
    @State private var showNotificationDeniedAlert = false

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        if let v, let b { return "\(v) (\(b))" }
        return v ?? "—"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                settingsSection(title: AppLanguageStore.localized("settings.section.notifications")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 14) {
                            Image(systemName: "bell.badge.fill")
                                .foregroundStyle(AppTheme.primary)
                                .frame(width: 22)
                            Text(AppLanguageStore.localized("settings.product_updates"))
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(AppTheme.onSurface)
                            Spacer()
                            Toggle("", isOn: productUpdatesToggleBinding)
                                .labelsHidden()
                                .tint(AppTheme.primary)
                        }
                        if notificationPermission.authorizationStatus == .denied {
                            Text(AppLanguageStore.localized("notification.status.denied.hint"))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(AppTheme.onSurfaceVariant)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(16)
                }

                settingsSection(title: AppLanguageStore.localized("settings.section.general")) {
                    VStack(spacing: 0) {
                        NavigationLink {
                            LanguageSettingsView()
                        } label: {
                            HStack {
                                Image(systemName: "globe")
                                    .foregroundStyle(AppTheme.onSurfaceVariant)
                                    .frame(width: 22)
                                Text(AppLanguageStore.localized("settings.language"))
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(AppTheme.onSurface)
                                Spacer()
                                Text(appLanguage.currentLanguageDisplayName)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(AppTheme.onSurfaceVariant)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.outlineVariant)
                            }
                            .padding(16)
                        }
                        .buttonStyle(.plain)

                        Rectangle()
                            .fill(AppTheme.outlineVariant.opacity(0.1))
                            .frame(height: 1)
                            .padding(.horizontal, 16)

                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundStyle(AppTheme.onSurfaceVariant)
                                .frame(width: 22)
                            Text(AppLanguageStore.localized("settings.build"))
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(AppTheme.onSurface)
                            Spacer()
                            Text(appVersion)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(AppTheme.onSurfaceVariant)
                                .multilineTextAlignment(.trailing)
                        }
                        .padding(16)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .padding(.bottom, 12)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle(AppLanguageStore.localized("settings.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await notificationPermission.refreshAuthorizationStatus()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                Task { await notificationPermission.refreshAuthorizationStatus() }
            }
        }
        .alert(AppLanguageStore.localized("notification.pre_prompt.title"), isPresented: $showNotificationPrePrompt) {
            Button(AppLanguageStore.localized("notification.pre_prompt.not_now"), role: .cancel) {}
            Button(AppLanguageStore.localized("notification.pre_prompt.confirm")) {
                Task {
                    let ok = await notificationPermission.requestSystemAuthorization()
                    if ok { productUpdatesOn = true }
                }
            }
        } message: {
            Text(AppLanguageStore.localized("notification.pre_prompt.body"))
        }
        .alert(AppLanguageStore.localized("notification.denied.title"), isPresented: $showNotificationDeniedAlert) {
            Button(AppLanguageStore.localized("notification.pre_prompt.not_now"), role: .cancel) {}
            Button(AppLanguageStore.localized("notification.denied.open_settings")) {
                notificationPermission.openAppSettings()
            }
        } message: {
            Text(AppLanguageStore.localized("notification.denied.body"))
        }
        .bbbRefreshOnAppLanguage()
    }

    private var productUpdatesToggleBinding: Binding<Bool> {
        Binding(
            get: { productUpdatesOn },
            set: { newValue in
                if !newValue {
                    productUpdatesOn = false
                    return
                }
                Task { @MainActor in
                    await notificationPermission.refreshAuthorizationStatus()
                    switch notificationPermission.authorizationStatus {
                    case .authorized, .provisional, .ephemeral:
                        productUpdatesOn = true
                    case .notDetermined:
                        showNotificationPrePrompt = true
                    case .denied:
                        showNotificationDeniedAlert = true
                    @unknown default:
                        break
                    }
                }
            }
        )
    }

    private func settingsSection(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            BBBTrackedText.text(title.uppercased(), size: 10, weight: .semibold, tracking: 3, color: AppTheme.outlineVariant)
                .padding(.horizontal, 8)

            content()
                .background(AppTheme.surfaceContainerLow)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppTheme.outlineVariant.opacity(0.12), lineWidth: 1)
                )
        }
    }
}

#Preview("My Likes") {
    NavigationView {
        MyLikesView()
            .environmentObject(AuthSessionStore())
            .environmentObject(AppTabRouter())
    }
    .navigationViewStyle(StackNavigationViewStyle())
    .preferredColorScheme(.dark)
}

#Preview("Settings") {
    NavigationView {
        ProfileSettingsView()
            .environmentObject(AppLanguageStore())
    }
    .navigationViewStyle(StackNavigationViewStyle())
    .preferredColorScheme(.dark)
}

// MARK: - 语言

struct LanguageSettingsView: View {
    @EnvironmentObject private var appLanguage: AppLanguageStore

    var body: some View {
        let _ = appLanguage.preference
        List {
            Section {
                ForEach(AppLanguagePreference.allCases) { option in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        appLanguage.setPreference(option)
                    } label: {
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(title(for: option))
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(AppTheme.onSurface)
                                Text(subtitle(for: option))
                                    .font(.system(size: 13))
                                    .foregroundStyle(AppTheme.onSurfaceVariant)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            if appLanguage.preference == option {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(AppTheme.primary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                Text(AppLanguageStore.localized("language.picker.footer"))
                    .font(.footnote)
                    .foregroundStyle(AppTheme.onSurfaceVariant)
            }
        }
        .listStyle(.insetGrouped)
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle(AppLanguageStore.localized("language.picker.title"))
        .navigationBarTitleDisplayMode(.inline)
        .bbbLocalizedNavigationBackButton()
    }

    private func title(for option: AppLanguagePreference) -> String {
        switch option {
        case .system:
            return AppLanguageStore.localized("language.option.system")
        case .english:
            return AppLanguageStore.localized("language.option.english")
        case .traditionalChinese:
            return AppLanguageStore.localized("language.option.chinese")
        case .portuguese:
            return AppLanguageStore.localized("language.option.portuguese")
        case .spanish:
            return AppLanguageStore.localized("language.option.spanish")
        case .japanese:
            return AppLanguageStore.localized("language.option.japanese")
        case .french:
            return AppLanguageStore.localized("language.option.french")
        case .german:
            return AppLanguageStore.localized("language.option.german")
        }
    }

    private func subtitle(for option: AppLanguagePreference) -> String {
        switch option {
        case .system:
            return AppLanguageStore.localized("language.option.system.subtitle")
        case .english:
            return AppLanguageStore.localized("language.option.english.subtitle")
        case .traditionalChinese:
            return AppLanguageStore.localized("language.option.chinese.subtitle")
        case .portuguese:
            return AppLanguageStore.localized("language.option.portuguese.subtitle")
        case .spanish:
            return AppLanguageStore.localized("language.option.spanish.subtitle")
        case .japanese:
            return AppLanguageStore.localized("language.option.japanese.subtitle")
        case .french:
            return AppLanguageStore.localized("language.option.french.subtitle")
        case .german:
            return AppLanguageStore.localized("language.option.german.subtitle")
        }
    }
}
