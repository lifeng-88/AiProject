//
//  HomeView.swift
//  bbb
//
//  编排：列表（沉浸式）/ 瀑布流（网格）、下拉刷新、主 Tab 联动
//  Image / Video / Dance：经 `TemplateRepository` 拉取（磁盘缓存 + 后台刷新）
//

import SwiftUI
import UIKit

private struct HomeFeedBottomSafeAreaKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Video 列表请求维度（与 `catalogIdForVideoRequest()` 一致）；切回 Video 时若与内存数据一致则不重复拉网
private struct VideoCatalogQuery: Equatable {
    let catalogId: Int32?
}

struct HomeView: View {
    @EnvironmentObject private var wallet: UserWalletStore
    @EnvironmentObject private var tabRouter: AppTabRouter
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var versionConfig: VersionConfigStore
    @EnvironmentObject private var appLanguage: AppLanguageStore
    @ObservedObject private var taskPolling = TaskPollingService.shared

    @AppStorage("bbb.home.layoutMode") private var layoutModeRaw = HomeLayoutMode.immersive.rawValue
    @AppStorage("bbb.home.primaryTab") private var primaryTab = 0
    @AppStorage("bbb.home.selectedTag") private var selectedTag = 0
    /// 沉浸式列表当前条 `likeStateKey`，写入 UserDefaults 以便下次冷启动恢复分页
    @State private var immersiveVisibleItemKey: String?
    /// 本次进入 feed 时尚待应用到 `UIScrollView` 的恢复目标（读完即清空）
    @State private var immersiveScrollRestoreKey: String?
    /// 大列表→小列表：将 `scrollTo` 到该模板 id（`HomeGridCardItem.id`）
    @State private var gridScrollTargetItemId: String?
    /// 小列表→大列表：当前可见格子里数据顺序最靠前的一条 `likeStateKey`
    @State private var gridAnchorLikeKey: String?
    /// `TemplateRepository.getCatalogs` → `/v1/catalogs`；仅 **Video** 展示二级分类条并用 `catalogId` 请求；Image / Dance 无子分类
    @State private var homeCatalogs: [Catalog] = []
    /// `TemplateRepository.getTemplateTabs` → `/v1/template_tabs`；一级 TAB 文案（与 `titleId` 1/2/3 对应 Image / Video / Dance）
    @State private var homeTemplateTabs: [TemplateTab] = []
    @AppStorage("homeLayoutHintSeen") private var layoutHintSeen = false
    /// 大列表滑过第 8 条后的「切小列表」引导，仅展示一次
    @AppStorage("homeGridSwitchGuideSeen") private var homeGridSwitchGuideSeen = false
    @State private var showLayoutHint = false
    @State private var showGridSwitchGuide = false

    /// 已点赞模板键（`templateKind:id`）；与 `LocalFavoriteTemplateStore` 同步，冷启动恢复
    @State private var likedTemplateKeys: Set<String> = []
    @State private var generationSheetItem: HomeFeedItem?
    /// 自模板详情页带入的已选肖像，传给 `HomeTemplateGenerationSheet`
    @State private var generationPrefilledImage: UIImage?
    /// 本次生成是否从首页瀑布流 **模板预览**（`HomeTemplateDetailView`，`gridDetailItem != nil`）进入；用于生成中「返回 / 浏览其他」回到瀑布流上一级还是首页
    @State private var generationOpenedWithPreviewBelow = false
    @State private var showNeedLoginAlert = false
    /// 瀑布流双列点击 cell → 模板详情（`NavigationView` push）
    @State private var gridDetailItem: HomeGridCardItem?
    /// 主内容区底部安全区高度（含 `MainTabView` 自定义 TabBar）；用于补偿 UIKit `UIScrollView` / 网格未完全吃进 `safeAreaInset` 的情况
    @State private var homeFeedBottomSafeInset: CGFloat = 0
    /// 用户关闭「生成进行中」横幅后，直至本次任务结束或新任务开始再显示
    @State private var dismissedGeneratingBanner = false
    /// 6 秒自动收起横幅
    @State private var generatingBannerHideTask: Task<Void, Never>?
    /// 6 秒后自动隐藏「切小列表」引导
    @State private var gridSwitchGuideHideTask: Task<Void, Never>?
    /// 首页曝光去重：大列表（`likeStateKey`）、小列表（`likeStateKey`），随主 Tab / 子分类 / 布局切换清空
    @State private var homeAnalyticsImmersiveExposedKeys: Set<String> = []
    @State private var homeAnalyticsGridExposedKeys: Set<String> = []
    private var layoutMode: HomeLayoutMode {
        HomeLayoutMode(rawValue: layoutModeRaw) ?? .immersive
    }

    private var layoutModeBinding: Binding<HomeLayoutMode> {
        Binding(
            get: { HomeLayoutMode(rawValue: layoutModeRaw) ?? .immersive },
            set: { layoutModeRaw = $0.rawValue }
        )
    }

    /// 与 `immersiveScrollStorageKey()` 对应：持久化当前 Image / Video(含子类) / Dance 下的浏览位置
    private func immersiveScrollStorageKey() -> String {
        let tag = primaryTab == 1 ? selectedTag : 0
        return "bbb.home.scroll.immersive.\(primaryTab).\(tag)"
    }

    /// 与列表数据范围一致，用于曝光去重键
    private func homeAnalyticsScopeTag() -> String {
        "\(primaryTab)-\(primaryTab == 1 ? selectedTag : 0)"
    }

    private func reloadImmersiveScrollRestoreFromDefaults() {
        immersiveScrollRestoreKey = UserDefaults.standard.string(forKey: immersiveScrollStorageKey())
    }

    // MARK: - T1 Image（全量缓存，展示列表由 `selectedTag` + `homeCatalogs` 过滤）
    @State private var imageTemplatesRaw: [ImageTemplate] = []
    @State private var imageTemplatesLoading = false
    @State private var imageTemplatesError: String?

    // MARK: - T3 Video（接口支持 `catalogId`，按子分类请求）
    @State private var videoTemplatesRaw: [VideoTemplate] = []
    @State private var videoTemplatesLoading = false
    @State private var videoTemplatesError: String?

    // MARK: - T2 Dance（全量缓存 + 标题按子分类名过滤）
    @State private var danceTemplatesRaw: [DancingTemplate] = []
    @State private var danceTemplatesLoading = false
    @State private var danceTemplatesError: String?

    /// 与接口分页一致；下拉刷新与首屏为第 1 页，接近底部再请求下一页
    private let homeListPageSize: Int32 = 10

    @State private var imageListPage: Int32 = 1
    @State private var imageListHasMore = true
    @State private var imageListLoadingMore = false

    @State private var videoListPage: Int32 = 1
    @State private var videoListHasMore = true
    @State private var videoListLoadingMore = false
    @State private var videoListSyncedQuery: VideoCatalogQuery?
    /// 切换 Video 子分类或强制重拉时递增，丢弃过期的网络回调（避免仍 loading 时无法发起新请求、或旧响应覆盖新分类）
    @State private var videoFetchEpoch: UInt = 0

    @State private var danceListPage: Int32 = 1
    @State private var danceListHasMore = true
    @State private var danceListLoadingMore = false

    /// 一级 TAB：优先 `/v1/template_tabs` 返回的 `title`（按 `titleId` 1=Image、2=Video、3=Dance）；缺项或为空时回退 String Catalog
    private var primaryTabs: [String] {
        [
            primaryTabTitleFromAPI(titleId: 1, fallbackKey: "home.primary.image"),
            primaryTabTitleFromAPI(titleId: 2, fallbackKey: "home.primary.video"),
            primaryTabTitleFromAPI(titleId: 3, fallbackKey: "home.primary.dance")
        ]
    }

    private func primaryTabTitleFromAPI(titleId: Int32, fallbackKey: String) -> String {
        if let t = homeTemplateTabs.first(where: { $0.id == titleId }) {
            let s = t.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { return s }
        }
        return AppLanguageStore.localized(fallbackKey)
    }

    /// T3 列表 `titleId`：与接口约定 **2 = Video**；未拉到 tabs 前仍用 2
    private var homeVideoTitleId: Int32 {
        homeTemplateTabs.first(where: { $0.id == 2 })?.id ?? 2
    }

    /// T2 列表 `titleId`：与接口约定 **3 = Dance**
    private var homeDanceTitleId: Int32 {
        homeTemplateTabs.first(where: { $0.id == 3 })?.id ?? 3
    }

    /// 仅 Video（`primaryTab == 1`）使用子分类：`selectedTag == 0` 为「全部」；`1...n` 对应 `homeCatalogs[selectedTag - 1]`。Image / Dance 始终为 `nil`（不按分类过滤）
    private var selectedCatalog: Catalog? {
        guard primaryTab == 1, !homeCatalogs.isEmpty, selectedTag > 0 else { return nil }
        let idx = selectedTag - 1
        guard homeCatalogs.indices.contains(idx) else { return nil }
        return homeCatalogs[idx]
    }

    /// 是否展示二级分类条（仅 Video）
    private var showSecondaryTagStrip: Bool {
        primaryTab == 1
    }

    /// 二级分类文案（与 `selectedTag` 下标一致）；样式统一为紫系胶囊，不再按索引区分 HOT/NEW 等颜色
    private var secondaryTagTitles: [String] {
        let allTag = AppLanguageStore.localized("home.tag.all")
        if homeCatalogs.isEmpty {
            return [allTag]
        }
        return [allTag] + homeCatalogs.map { $0.name.uppercased() }
    }

    private var imageFeedItems: [HomeFeedItem] {
        templatesMatchingCatalog(imageTemplatesRaw, catalog: selectedCatalog).map { HomeFeedItem(imageTemplate: $0) }
    }

    private var imageGridItems: [HomeGridCardItem] {
        templatesMatchingCatalog(imageTemplatesRaw, catalog: selectedCatalog).map { HomeGridCardItem(imageTemplate: $0) }
    }

    private var videoFeedItems: [HomeFeedItem] {
        videoTemplatesRaw.map { HomeFeedItem(videoTemplate: $0) }
    }

    private var videoGridItems: [HomeGridCardItem] {
        videoTemplatesRaw.map { HomeGridCardItem(videoTemplate: $0) }
    }

    private var danceFeedItems: [HomeFeedItem] {
        templatesMatchingCatalog(danceTemplatesRaw, catalog: selectedCatalog).map { HomeFeedItem(dancingTemplate: $0) }
    }

    private var danceGridItems: [HomeGridCardItem] {
        templatesMatchingCatalog(danceTemplatesRaw, catalog: selectedCatalog).map { HomeGridCardItem(dancingTemplate: $0) }
    }

    private var immersiveFeed: [HomeFeedItem] {
        switch primaryTab {
        case 0: return imageFeedItems
        case 1: return videoFeedItems
        case 2: return danceFeedItems
        default: return []
        }
    }

    private var gridItems: [HomeGridCardItem] {
        switch primaryTab {
        case 0: return imageGridItems
        case 1: return videoGridItems
        case 2: return danceGridItems
        default: return []
        }
    }

    private var currentLoading: Bool {
        switch primaryTab {
        case 0: return imageTemplatesLoading
        case 1: return videoTemplatesLoading
        case 2: return danceTemplatesLoading
        default: return false
        }
    }

    private var currentError: String? {
        switch primaryTab {
        case 0: return imageTemplatesError
        case 1: return videoTemplatesError
        case 2: return danceTemplatesError
        default: return nil
        }
    }

    private var currentFeedEmpty: Bool {
        immersiveFeed.isEmpty
    }

    /// T1/T2：无子分类或接口未返回时不过滤；否则按模板 `title` 与分类名匹配
    private func templatesMatchingCatalog<T: TemplateProtocol>(_ templates: [T], catalog: Catalog?) -> [T] {
        guard let catalog else { return templates }
        let name = catalog.name
        return templates.filter { Self.templateTitleMatchesCatalog($0.title, catalogName: name) }
    }

    private static func templateTitleMatchesCatalog(_ title: String, catalogName: String) -> Bool {
        let t = title.folding(options: .diacriticInsensitive, locale: .current).lowercased()
        let c = catalogName.folding(options: .diacriticInsensitive, locale: .current).lowercased()
        if c.isEmpty { return true }
        if t.contains(c) { return true }
        let parts = c.split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { !$0.isEmpty }
        if parts.isEmpty { return false }
        return parts.allSatisfy { t.contains($0) }
    }

    /// 远程推送 `template_category`：`template_tab_id` 1/2/3 → 首页 Image/Video/Dance；Video 时按 `catalog_id` 选二级分类。
    private func applyPendingHomeTemplateCategoryFromPush() {
        guard let push = tabRouter.pendingHomeTemplateCategoryPush else { return }

        let titleId = push.templateTabId
        let newPrimary: Int
        switch titleId {
        case 1: newPrimary = 0
        case 2: newPrimary = 1
        case 3: newPrimary = 2
        default: newPrimary = 0
        }

        DispatchQueue.main.async {
            if self.primaryTab != newPrimary {
                self.primaryTab = newPrimary
            }

            if newPrimary == 1 {
                if let cid = push.catalogId {
                    if self.homeCatalogs.isEmpty { return }
                    if let idx = self.homeCatalogs.firstIndex(where: { $0.id == cid }) {
                        self.selectedTag = idx + 1
                    } else {
                        self.selectedTag = 0
                    }
                    self.tabRouter.clearPendingHomeTemplateCategoryPush()
                } else {
                    self.selectedTag = 0
                    self.tabRouter.clearPendingHomeTemplateCategoryPush()
                }
            } else {
                self.selectedTag = 0
                self.tabRouter.clearPendingHomeTemplateCategoryPush()
            }
        }
    }

    private var gridShowSkeleton: Bool {
        currentLoading && gridItems.isEmpty
    }

    private var homeHasMore: Bool {
        switch primaryTab {
        case 0: return imageListHasMore
        case 1: return videoListHasMore
        case 2: return danceListHasMore
        default: return false
        }
    }

    private var homeLoadingMore: Bool {
        switch primaryTab {
        case 0: return imageListLoadingMore
        case 1: return videoListLoadingMore
        case 2: return danceListLoadingMore
        default: return false
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                homeRootContent
                    .bbbToolbarHiddenNavigationBar()

                NavigationLink(
                    destination: homeGridDetailDestination,
                    isActive: Binding(
                        get: { gridDetailItem != nil },
                        set: { if !$0 { gridDetailItem = nil } }
                    )
                ) {
                    EmptyView()
                }
                .frame(width: 0, height: 0)
                .opacity(0)
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .alert(AppLanguageStore.localized("home.alert.login.title"), isPresented: $showNeedLoginAlert) {
            Button(AppLanguageStore.localized("home.alert.login.go_my")) { tabRouter.select(.my) }
            Button(AppLanguageStore.localized("home.alert.cancel"), role: .cancel) {}
        } message: {
            Text(AppLanguageStore.localized("home.alert.login.message"))
        }
        /// 不用 SwiftUI `.sheet`：iOS 15 上再 `present` 系统相册时，关相册易连带关掉外层 sheet。改为全屏 `overlay`，与相册 modal 同一窗口层级。
        .overlay {
            if let item = generationSheetItem {
                ZStack {
                    /// 仅遮罩铺满含刘海区域；生成页本身勿 `ignoresSafeArea`，否则内层 `safeAreaInset` 顶栏会与状态栏重叠。
                    Color.black.opacity(0.48)
                        .ignoresSafeArea()
                    HomeTemplateGenerationSheet(
                        item: item,
                        prefilledImage: generationPrefilledImage,
                        onDismiss: {
                            generationSheetItem = nil
                            generationPrefilledImage = nil
                            tabRouter.browseOtherGenerationReturnTab = nil
                            generationOpenedWithPreviewBelow = false
                        },
                        // 生成中：顶栏 Back 与「浏览其他内容」均走 finishGenerationQueuingExit
                        onBrowseOtherLeaveToFeed: {
                            finishGenerationQueuingExit()
                        }
                    )
                    .environmentObject(wallet)
                    .environmentObject(auth)
                    .environmentObject(versionConfig)
                    .environmentObject(tabRouter)
                    .environmentObject(appLanguage)
                    .background(AppTheme.background)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.22), value: generationSheetItem?.id)
        .onChange(of: generationSheetItem?.id) { _ in
            tabRouter.homeTemplateGenerationPresented = generationSheetItem != nil
        }
        /// 进入首页：认证与分类并行拉取（分类供子标签与 Video 请求维度）
        .task {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { _ = await AuthRepository.shared.getCurrentAuthInfo() }
                group.addTask { await loadHomeCatalogs(forceRefresh: false) }
                group.addTask { await loadHomeTemplateTabs() }
            }
        }
        .task(id: primaryTab) {
            await loadTemplatesForPrimaryTab(onlyIfEmpty: true)
        }
        .onChange(of: selectedTag) { _ in
            lightHaptic()
            homeAnalyticsImmersiveExposedKeys.removeAll()
            homeAnalyticsGridExposedKeys.removeAll()
            if primaryTab == 1 {
                reloadImmersiveScrollRestoreFromDefaults()
            }
            // Video 子分类由接口 `catalogId` 筛选；Image/Dance 仅本地过滤
            guard primaryTab == 1 else { return }
            Task { await loadVideoTemplates() }
        }
        .onChange(of: homeCatalogs.count) { newCount in
            // 推迟到下一 runloop，避免在视图更新周期内写 `selectedTag` 触发 “Modifying state during view update”
            DispatchQueue.main.async {
                if newCount == 0 {
                    selectedTag = 0
                    return
                }
                if selectedTag > newCount {
                    selectedTag = 0
                }
                guard primaryTab == 1 else { return }
                Task { await loadVideoTemplates() }
            }
        }
        .onChange(of: showGridSwitchGuide) { new in
            if new {
                scheduleGridSwitchGuideAutoHide()
            } else {
                cancelGridSwitchGuideAutoHide()
            }
        }
        .onChange(of: primaryTab) { newTab in
            lightHaptic()
            showGridSwitchGuide = false
            homeAnalyticsImmersiveExposedKeys.removeAll()
            homeAnalyticsGridExposedKeys.removeAll()
            reloadImmersiveScrollRestoreFromDefaults()
        }
        .onChange(of: layoutModeRaw) { _ in
            homeAnalyticsImmersiveExposedKeys.removeAll()
            homeAnalyticsGridExposedKeys.removeAll()
        }
        .onChange(of: immersiveVisibleItemKey) { new in
            guard let new, !new.isEmpty else { return }
            UserDefaults.standard.set(new, forKey: immersiveScrollStorageKey())
            if layoutMode == .immersive,
               let idx = immersiveFeed.firstIndex(where: { $0.likeStateKey == new }),
               idx >= 8,
               !homeGridSwitchGuideSeen {
                showGridSwitchGuide = true
            }
            guard layoutMode == .immersive, let item = immersiveFeed.first(where: { $0.likeStateKey == new }) else { return }
            let dedup = "i-\(homeAnalyticsScopeTag())-\(item.likeStateKey)"
            guard !homeAnalyticsImmersiveExposedKeys.contains(dedup) else { return }
            homeAnalyticsImmersiveExposedKeys.insert(dedup)
            HomeTemplateAnalytics.logExposure(templateId: item.id, listSource: .immersive, templateType: item.templateKind.behaviorEventTemplateType)
        }
        .onChange(of: taskPolling.isGenerationInProgress) { isActive in
            if isActive {
                dismissedGeneratingBanner = false
                if generationSheetItem == nil {
                    scheduleGeneratingBannerAutoHide()
                }
            } else {
                cancelGeneratingBannerAutoHide()
            }
        }
        .onChange(of: generationSheetItem?.id) { newId in
            if newId != nil {
                cancelGeneratingBannerAutoHide()
            } else if taskPolling.isGenerationInProgress {
                dismissedGeneratingBanner = false
                scheduleGeneratingBannerAutoHide()
            }
        }
        .onAppear {
            if taskPolling.isGenerationInProgress, !dismissedGeneratingBanner {
                scheduleGeneratingBannerAutoHide()
            }
        }
        .onChange(of: appLanguage.preference) { _ in
            Task {
                await loadHomeCatalogs(forceRefresh: true)
                await loadHomeTemplateTabs()
                await loadTemplatesForPrimaryTab(onlyIfEmpty: false)
            }
        }
        .task(id: auth.userId) {
            likedTemplateKeys = LocalFavoriteTemplateStore.load(userId: auth.userId)
            if auth.isAuthenticated {
                await wallet.syncCoinBalanceFromServer(userId: auth.userId)
            }
        }
        .onChange(of: tabRouter.selected) { new in
            guard new == .home, auth.isAuthenticated else { return }
            /// 略推迟拉余额，避免与切回 Home 的首帧布局、`UIScrollView` 复算叠在同一帧，加重卡顿或错位感
            Task {
                try? await Task.sleep(nanoseconds: 280_000_000)
                await wallet.syncCoinBalanceFromServer(userId: auth.userId)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .localFavoriteTemplateStoreDidChange)) { _ in
            likedTemplateKeys = LocalFavoriteTemplateStore.load(userId: auth.userId)
        }
        .onReceive(NotificationCenter.default.publisher(for: .homeRequestPrimaryGenerate)) { note in
            if let raw = note.userInfo?["browseOtherReturnTabRaw"] as? Int,
               let t = AppTab(rawValue: raw) {
                tabRouter.browseOtherGenerationReturnTab = t
            } else {
                tabRouter.browseOtherGenerationReturnTab = nil
            }
            guard let item = note.object as? HomeFeedItem else { return }
            let prefilled = note.userInfo?["prefilledImage"] as? UIImage
            handlePrimaryGenerate(item, prefilledImage: prefilled)
        }
        .onChange(of: gridDetailItem) { new in
            let count = (new != nil) ? 1 : 0
            DispatchQueue.main.async {
                tabRouter.homeNavigationStackCount = count
            }
        }
        .onAppear {
            reloadImmersiveScrollRestoreFromDefaults()
            let count = gridDetailItem != nil ? 1 : 0
            DispatchQueue.main.async {
                tabRouter.homeNavigationStackCount = count
            }
        }
        .onChange(of: tabRouter.pendingHomeTemplateCategoryPush) { _ in
            applyPendingHomeTemplateCategoryFromPush()
        }
        .onChange(of: homeCatalogs.map(\.id)) { _ in
            applyPendingHomeTemplateCategoryFromPush()
        }
        .bbbRefreshOnAppLanguage()
    }

    @ViewBuilder
    private var homeGridDetailDestination: some View {
        if let card = gridDetailItem {
            HomeTemplateDetailView(
                gridItem: card,
                onUseTemplate: { feedItem, image in
                    handlePrimaryGenerate(feedItem, clickListSource: .grid, prefilledImage: image)
                }
            )
            .bbbNavigationBarBackground(AppTheme.background)
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private func homeTopChrome(feedExtendsBehindChrome: Bool) -> some View {
        VStack(spacing: 0) {
            HomeTopBar(
                layoutMode: layoutModeBinding,
                primaryTab: $primaryTab,
                primaryTabs: primaryTabs,
                coinBalance: wallet.formattedCoinBalance,
                onLayoutToggle: handleLayoutToggle,
                onCoinTap: {
                    lightHaptic()
                    tabRouter.select(.recharge)
                },
                feedExtendsBehindChrome: feedExtendsBehindChrome,
                tightBottomForSecondaryStrip: showSecondaryTagStrip
            )

            if showSecondaryTagStrip {
                HomeSecondaryTagStrip(
                    tags: secondaryTagTitles,
                    selected: $selectedTag
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// 首页根内容（内嵌于 `NavigationView`，瀑布流详情以 push 打开）
    /// - **信息流**：主列表铺满整页，`HomeTopBar` / 二级分类以叠层盖在内容上方，图片在 TAB 后方可见。
    /// - **网格**：顶栏与分类仍在内容上方（传统自上而下布局）。
    /// 「生成中」横幅为叠层贴底栏上方，不参与主列测量。
    private var homeRootContent: some View {
        ZStack(alignment: .topLeading) {
            Group {
                if layoutMode == .immersive {
                    ZStack(alignment: .top) {
                        homeMainFeedBlock
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .ignoresSafeArea(edges: .top)
                        homeTopChrome(feedExtendsBehindChrome: true)
                            .zIndex(1)
                    }
                    .transition(HomeLayoutTransitions.immersiveChrome)
                } else {
                    VStack(spacing: 0) {
                        homeTopChrome(feedExtendsBehindChrome: false)
                        homeMainFeedBlock
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .layoutPriority(1)
                    }
                    .transition(HomeLayoutTransitions.gridChrome)
                }
            }
            if taskPolling.isGenerationInProgress && !dismissedGeneratingBanner {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    HomeGeneratingBanner(
                        onDismiss: {
                            cancelGeneratingBannerAutoHide()
                            dismissedGeneratingBanner = true
                        },
                        onViewCreations: {
                            lightHaptic()
                            tabRouter.openMyCreations(filter: .generating)
                        }
                    )
                    .padding(.horizontal, 16)
                    /// 与主列表 `homeFeedBottomPadding` 对齐，避免仅 `Spacer` 贴底时落在 TabBar 下方或缝隙不对
                    .padding(.bottom, homeFeedBottomPadding + 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .zIndex(2)
            }

            if showLayoutHint {
                HomeLayoutTooltip(text: AppLanguageStore.localized("home.layout.hint"))
                    .padding(.leading, 18)
                    .padding(.top, 52)
                    .zIndex(1)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if showGridSwitchGuide, layoutMode == .immersive {
                HomeLayoutSwitchGuideBubble(
                    title: AppLanguageStore.localized("home.layout.switch_guide"),
                    onTap: {
                        applyLayoutSwitch(to: .grid)
                    }
                )
                /// 三角与顶栏布局按钮同竖直中轴（`HomeLayoutSwitchGuideBubble` 内 `14+40` 几何）；纵向贴在按钮圆下方
                .padding(.leading, 0)
                .padding(.top, 54)
                .zIndex(3)
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.88, anchor: .topLeading)),
                        removal: .opacity
                    )
                )
                .animation(.spring(response: 0.52, dampingFraction: 0.76), value: showGridSwitchGuide)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
        .background(AppTheme.background)
    }

    /// 列表/网格与 TabBar 之间的留白：`UIKit` 分页/网格往往仍盖住自定义栏；取 `max(测量, TabBar 估算)`，避免只测到 Home Indicator 时仍被挡
    private var homeFeedBottomPadding: CGFloat {
        resolvedHomeFeedBottomPadding()
    }

    /// 首页瀑布流：当前 Tab 为 Home、未进后台、且未打开网格详情时允许格内视频播放（`!= .background` 避免首帧短暂 `.inactive` 导致永不自动播）。
    private var homeGridAllowsCellVideoPlayback: Bool {
        tabRouter.selected == .home && scenePhase != .background && gridDetailItem == nil
    }

    private func resolvedHomeFeedBottomPadding() -> CGFloat {
        let fallback = MainTabBarMetrics.estimatedContentHeight
        let m = homeFeedBottomSafeInset
        if m >= 1 { return max(m, fallback) }
        return fallback
    }

    /// 分类条下方主内容区：`MainTabView.safeAreaInset` 已把 TabBar 从安全区底部顶起，列表只需占满剩余空间。
    /// 不再用外层 `GeometryReader` 固定宽高——否则会干扰 `VStack` 对剩余高度的分配，导致首页滚动区域高度异常。
    private var homeMainFeedBlock: some View {
        ZStack {
            Group {
                switch layoutMode {
                case .immersive:
                    HomeImmersiveFeedView(
                        feed: immersiveFeed,
                        showScrollHintOnFirstPage: true,
                        likedKeys: likedTemplateKeys,
                        requestingLikeKeys: [],
                        onToggleLike: { item in toggleLike(for: item) },
                        onPrimaryAction: { item in handlePrimaryGenerate(item, clickListSource: .immersive) },
                        onRefresh: { await refreshFeed() },
                        onLoadMore: {
                            guard homeHasMore, !homeLoadingMore else { return }
                            Task { await loadMoreCurrentTabAsync() }
                        },
                        hasMore: homeHasMore,
                        isLoadingMore: homeLoadingMore,
                        visibleFeedItemId: $immersiveVisibleItemKey,
                        scrollRestoreKey: immersiveScrollRestoreKey,
                        onScrollRestoreApplied: {
                            immersiveScrollRestoreKey = nil
                        }
                    )
                    /// `selectedTag` 仅影响 Video 列表；Image/Dance 不包含在 id 中，避免从 Video 切回时因子分类选中状态无意义重建
                    .id("\(primaryTab)-\(primaryTab == 1 ? selectedTag : 0)-immersive")
                case .grid:
                    HomeGridFeedView(
                        items: gridItems,
                        showSkeleton: gridShowSkeleton,
                        likedKeys: likedTemplateKeys,
                        requestingLikeKeys: [],
                        onToggleLike: { item in toggleLike(for: item) },
                        onSelectItem: { item in
                            lightHaptic()
                            HomeTemplateAnalytics.logClick(templateId: item.id, listSource: .grid, action: .openDetail, templateType: item.templateKind.behaviorEventTemplateType)
                            gridDetailItem = item
                        },
                        onTemplateExpose: { item in
                            let dedup = "g-\(homeAnalyticsScopeTag())-\(item.likeStateKey)"
                            guard !homeAnalyticsGridExposedKeys.contains(dedup) else { return }
                            homeAnalyticsGridExposedKeys.insert(dedup)
                            HomeTemplateAnalytics.logExposure(templateId: item.id, listSource: .grid, templateType: item.templateKind.behaviorEventTemplateType)
                        },
                        onRefresh: { await refreshFeed() },
                        hasMore: homeHasMore,
                        isLoadingMore: homeLoadingMore,
                        onLoadMore: {
                            guard homeHasMore, !homeLoadingMore else { return }
                            await loadMoreCurrentTabAsync()
                        },
                        scrollToItemId: $gridScrollTargetItemId,
                        onVisibleAnchorChange: { key in
                            gridAnchorLikeKey = key
                        },
                        allowsCellVideoPlayback: homeGridAllowsCellVideoPlayback
                    )
                    .id("\(primaryTab)-\(primaryTab == 1 ? selectedTag : 0)-grid")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .preference(
                            key: HomeFeedBottomSafeAreaKey.self,
                            value: proxy.safeAreaInsets.bottom
                        )
                }
                .allowsHitTesting(false)
            )
            .onPreferenceChange(HomeFeedBottomSafeAreaKey.self) { newBottom in
                // GeometryReader 在布局阶段上报 safeArea；同步写 State 会触发 “Modifying state during view update”
                DispatchQueue.main.async {
                    homeFeedBottomSafeInset = newBottom
                }
            }
            .padding(.bottom, homeFeedBottomPadding)

            if currentLoading, currentFeedEmpty {
                if layoutMode == .immersive {
                    HomeImmersiveFeedLoadingPlaceholder()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)
                }
                /// 网格模式由 `HomeGridFeedView` 内骨架展示，此处不再叠转圈避免重复
            }

            if let err = currentError, currentFeedEmpty, !currentLoading {
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(Color.red.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }

        }
    }

    private func scheduleGeneratingBannerAutoHide() {
        generatingBannerHideTask?.cancel()
        generatingBannerHideTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 6_000_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            dismissedGeneratingBanner = true
            generatingBannerHideTask = nil
        }
    }

    private func cancelGeneratingBannerAutoHide() {
        generatingBannerHideTask?.cancel()
        generatingBannerHideTask = nil
    }

    private func scheduleGridSwitchGuideAutoHide() {
        gridSwitchGuideHideTask?.cancel()
        gridSwitchGuideHideTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 6_000_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            showGridSwitchGuide = false
            homeGridSwitchGuideSeen = true
            gridSwitchGuideHideTask = nil
        }
    }

    private func cancelGridSwitchGuideAutoHide() {
        gridSwitchGuideHideTask?.cancel()
        gridSwitchGuideHideTask = nil
    }

    /// 切换大/小列表并同步锚点：Big→Small 滚网格至当前全屏条；Small→Big 恢复至可见流最前一条
    private func applyLayoutSwitch(to target: HomeLayoutMode) {
        guard layoutMode != target else { return }
        /// 沉浸式 → 瀑布流：关掉引导浮层；若引导从未弹出过，用户已通过左上角手动切换，视为已引导，不再在滑到第 9 条时弹出。
        if layoutMode == .immersive, target == .grid {
            showGridSwitchGuide = false
            if !homeGridSwitchGuideSeen {
                homeGridSwitchGuideSeen = true
            }
        } else if showGridSwitchGuide {
            showGridSwitchGuide = false
            homeGridSwitchGuideSeen = true
        }
        lightHaptic()
        homeAnalyticsImmersiveExposedKeys.removeAll()
        homeAnalyticsGridExposedKeys.removeAll()

        if layoutMode == .immersive, target == .grid {
            if let key = immersiveVisibleItemKey,
               let item = immersiveFeed.first(where: { $0.likeStateKey == key }) {
                gridScrollTargetItemId = item.id
            }
        } else if layoutMode == .grid, target == .immersive {
            if let key = gridAnchorLikeKey,
               immersiveFeed.contains(where: { $0.likeStateKey == key }) {
                immersiveScrollRestoreKey = key
            } else {
                immersiveScrollRestoreKey = nil
            }
        }

        withAnimation(HomeLayoutTransitions.layoutSwitchAnimation) {
            layoutModeRaw = target.rawValue
        }
    }

    private func handleLayoutToggle() {
        /// 仅首页左上角布局按钮：一点击即视为已见过引导（`homeGridSwitchGuideSeen`），关闭浮层；回到沉浸式后也不会再触发滑列表引导。
        showGridSwitchGuide = false
        homeGridSwitchGuideSeen = true
        applyLayoutSwitch(to: layoutMode == .immersive ? .grid : .immersive)
        if !layoutHintSeen {
            layoutHintSeen = true
            showLayoutHint = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
                withAnimation(.easeOut(duration: 0.25)) {
                    showLayoutHint = false
                }
            }
        }
    }

    private func refreshFeed() async {
        await loadHomeCatalogs(forceRefresh: true)
        await loadHomeTemplateTabs()
        await loadTemplatesForPrimaryTab(onlyIfEmpty: false)
    }

    private func loadHomeTemplateTabs() async {
        let locale = appLanguage.templateAPICatalogLocaleIdentifier
        let result = await TemplateRepository.shared.getTemplateTabs(locale: locale)
        await MainActor.run {
            switch result {
            case .success(let list):
                homeTemplateTabs = list
            case .failure:
                break
            }
        }
    }

    private func loadHomeCatalogs(forceRefresh: Bool) async {
        let locale = appLanguage.templateAPICatalogLocaleIdentifier
        let result = await TemplateRepository.shared.getCatalogs(locale: locale, forceRefresh: forceRefresh)
        await MainActor.run {
            switch result {
            case .success(let list):
                homeCatalogs = list
                // 0 = 全部，有效下标最大为 list.count
                if selectedTag > list.count {
                    selectedTag = 0
                }
            case .failure:
                break
            }
        }
    }

    private func loadTemplatesForPrimaryTab(onlyIfEmpty: Bool) async {
        switch primaryTab {
        case 0:
            await loadImageTemplates(onlyIfEmpty: onlyIfEmpty)
        case 1:
            await loadVideoTemplates(onlyIfEmpty: onlyIfEmpty)
        case 2:
            await loadDanceTemplates(onlyIfEmpty: onlyIfEmpty)
        default:
            break
        }
    }

    private func mergeTemplates<T: TemplateProtocol>(_ existing: [T], _ new: [T]) -> [T] {
        var seen = Set(existing.map(\.id))
        var out = existing
        for t in new where seen.insert(t.id).inserted {
            out.append(t)
        }
        return out
    }

    private func loadMoreCurrentTabAsync() async {
        switch primaryTab {
        case 0:
            guard imageListHasMore, !imageListLoadingMore, !imageTemplatesLoading else { return }
            await fetchImageTemplates(reset: false)
        case 1:
            guard videoListHasMore, !videoListLoadingMore, !videoTemplatesLoading else { return }
            await fetchVideoTemplates(reset: false)
        case 2:
            guard danceListHasMore, !danceListLoadingMore, !danceTemplatesLoading else { return }
            await fetchDanceTemplates(reset: false)
        default:
            break
        }
    }

    private func loadImageTemplates(onlyIfEmpty: Bool) async {
        if onlyIfEmpty, !imageTemplatesRaw.isEmpty { return }
        await fetchImageTemplates(reset: true)
    }

    private func fetchImageTemplates(reset: Bool) async {
        if reset {
            let proceed = await MainActor.run { () -> Bool in
                guard !imageTemplatesLoading else { return false }
                imageTemplatesLoading = true
                imageTemplatesError = nil
                return true
            }
            guard proceed else { return }
        } else {
            let proceed = await MainActor.run { () -> Bool in
                guard imageListHasMore, !imageListLoadingMore, !imageTemplatesLoading else { return false }
                imageListLoadingMore = true
                return true
            }
            guard proceed else { return }
        }

        let page: Int32 = await MainActor.run { reset ? 1 : imageListPage + 1 }
        let result = await TemplateRepository.shared.getImageTemplates(pageNum: page, pageSize: homeListPageSize)

        await MainActor.run {
            imageTemplatesLoading = false
            imageListLoadingMore = false
            switch result {
            case .success(let resp):
                if reset {
                    imageTemplatesRaw = resp.list
                    imageListPage = 1
                } else {
                    imageTemplatesRaw = mergeTemplates(imageTemplatesRaw, resp.list)
                    imageListPage = page
                }
                if resp.total > 0 {
                    imageListHasMore = imageTemplatesRaw.count < Int(resp.total)
                } else {
                    imageListHasMore = !resp.list.isEmpty && resp.list.count >= homeListPageSize
                }
                let feed = imageFeedItems
                let grid = imageGridItems
                prefetchHomeImageURLs(feed: feed, grid: grid)
            case .failure(let err):
                imageTemplatesError = err.userMessage
            }
        }
    }

    /// `nil`：不传 `catalogId`，与接口约定一致表示全部分类
    private func catalogIdForVideoRequest() -> Int32? {
        guard selectedTag > 0, !homeCatalogs.isEmpty else { return nil }
        let idx = selectedTag - 1
        guard homeCatalogs.indices.contains(idx) else { return nil }
        return homeCatalogs[idx].id
    }

    private func loadVideoTemplates(onlyIfEmpty: Bool = false) async {
        let query = VideoCatalogQuery(catalogId: catalogIdForVideoRequest())
        if onlyIfEmpty, !videoTemplatesRaw.isEmpty, videoListSyncedQuery == query {
            return
        }
        await fetchVideoTemplates(reset: true)
    }

    private func fetchVideoTemplates(reset: Bool) async {
        if reset {
            let epoch = await MainActor.run { () -> UInt in
                videoFetchEpoch += 1
                let e = videoFetchEpoch
                videoTemplatesLoading = true
                videoTemplatesError = nil
                return e
            }

            let (page, cid) = await MainActor.run { () -> (Int32, Int32?) in
                (1, catalogIdForVideoRequest())
            }
            let result = await TemplateRepository.shared.getVideoTemplates(
                pageNum: page,
                pageSize: homeListPageSize,
                catalogId: cid,
                titleId: homeVideoTitleId
            )

            await MainActor.run {
                guard epoch == videoFetchEpoch else { return }
                videoTemplatesLoading = false
                videoListLoadingMore = false
                switch result {
                case .success(let resp):
                    videoTemplatesRaw = resp.list
                    videoListPage = 1
                    videoListSyncedQuery = VideoCatalogQuery(catalogId: cid)
                    if resp.total > 0 {
                        videoListHasMore = videoTemplatesRaw.count < Int(resp.total)
                    } else {
                        videoListHasMore = !resp.list.isEmpty && resp.list.count >= homeListPageSize
                    }
                    let feed = videoFeedItems
                    let grid = videoGridItems
                    prefetchHomeImageURLs(feed: feed, grid: grid)
                case .failure(let err):
                    videoTemplatesError = err.userMessage
                }
            }
        } else {
            let (proceed, page, startCid) = await MainActor.run { () -> (Bool, Int32, Int32?) in
                guard videoListHasMore, !videoListLoadingMore, !videoTemplatesLoading else {
                    return (false, 1, nil)
                }
                videoListLoadingMore = true
                let nextPage = videoListPage + 1
                return (true, nextPage, catalogIdForVideoRequest())
            }
            guard proceed else { return }

            let result = await TemplateRepository.shared.getVideoTemplates(
                pageNum: page,
                pageSize: homeListPageSize,
                catalogId: startCid,
                titleId: homeVideoTitleId
            )

            await MainActor.run {
                videoListLoadingMore = false
                guard startCid == catalogIdForVideoRequest() else {
                    return
                }
                switch result {
                case .success(let resp):
                    videoTemplatesRaw = mergeTemplates(videoTemplatesRaw, resp.list)
                    videoListPage = page
                    if resp.total > 0 {
                        videoListHasMore = videoTemplatesRaw.count < Int(resp.total)
                    } else {
                        videoListHasMore = !resp.list.isEmpty && resp.list.count >= homeListPageSize
                    }
                    let feed = videoFeedItems
                    let grid = videoGridItems
                    prefetchHomeImageURLs(feed: feed, grid: grid)
                case .failure(let err):
                    videoTemplatesError = err.userMessage
                }
            }
        }
    }

    private func loadDanceTemplates(onlyIfEmpty: Bool) async {
        if onlyIfEmpty, !danceTemplatesRaw.isEmpty { return }
        await fetchDanceTemplates(reset: true)
    }

    private func fetchDanceTemplates(reset: Bool) async {
        if reset {
            let proceed = await MainActor.run { () -> Bool in
                guard !danceTemplatesLoading else { return false }
                danceTemplatesLoading = true
                danceTemplatesError = nil
                return true
            }
            guard proceed else { return }
        } else {
            let proceed = await MainActor.run { () -> Bool in
                guard danceListHasMore, !danceListLoadingMore, !danceTemplatesLoading else { return false }
                danceListLoadingMore = true
                return true
            }
            guard proceed else { return }
        }

        let page: Int32 = await MainActor.run { reset ? 1 : danceListPage + 1 }
        let result = await TemplateRepository.shared.getDancingTemplates(
            pageNum: page,
            pageSize: homeListPageSize,
            titleId: homeDanceTitleId
        )

        await MainActor.run {
            danceTemplatesLoading = false
            danceListLoadingMore = false
            switch result {
            case .success(let resp):
                if reset {
                    danceTemplatesRaw = resp.list
                    danceListPage = 1
                } else {
                    danceTemplatesRaw = mergeTemplates(danceTemplatesRaw, resp.list)
                    danceListPage = page
                }
                if resp.total > 0 {
                    danceListHasMore = danceTemplatesRaw.count < Int(resp.total)
                } else {
                    danceListHasMore = !resp.list.isEmpty && resp.list.count >= homeListPageSize
                }
                let feed = danceFeedItems
                let grid = danceGridItems
                prefetchHomeImageURLs(feed: feed, grid: grid)
            case .failure(let err):
                danceTemplatesError = err.userMessage
            }
        }
    }

    /// 列表轮播图 + 网格封面 URL 去重后低优先级预加载；仅在底部 Tab 为 Home 时执行，避免后台 Tab 仍占用带宽
    private func prefetchHomeImageURLs(feed: [HomeFeedItem], grid: [HomeGridCardItem]) {
        Task(priority: .utility) {
            let onHome = await MainActor.run { tabRouter.selected == .home }
            guard onHome else { return }
            var seen = Set<String>()
            var ordered: [String] = []
            for item in feed.prefix(28) {
                let feedImageURLs = (item.templateKind == .t2 || item.templateKind == .t3)
                    ? item.immersiveListBackdropImageURLs
                    : item.immersiveImageURLs
                for u in feedImageURLs {
                    let s = u.absoluteString
                    if seen.insert(s).inserted { ordered.append(s) }
                }
            }
            for item in grid.prefix(28) {
                if let u = item.imageURL {
                    let s = u.absoluteString
                    if seen.insert(s).inserted { ordered.append(s) }
                }
                for u in item.gridSlideshowURLs {
                    let s = u.absoluteString
                    if seen.insert(s).inserted { ordered.append(s) }
                }
            }
            for key in ordered.prefix(48) {
                let stillHome = await MainActor.run { tabRouter.selected == .home }
                guard stillHome else { return }
                await ImageCacheManager.shared.preloadImage(urlString: key, priority: .utility)
            }
            var videoPosterKeys: [String] = []
            var seenVideo = Set<String>()
            for item in grid.prefix(28) where item.templateKind == .t2 || item.templateKind == .t3 {
                if let v = item.gridPlaybackVideoURL {
                    let s = v.absoluteString
                    if seenVideo.insert(s).inserted { videoPosterKeys.append(s) }
                }
            }
            for item in feed.prefix(28) where item.templateKind == .t2 || item.templateKind == .t3 {
                if let v = item.immersiveStoppedPosterVideoURL {
                    let s = v.absoluteString
                    if seenVideo.insert(s).inserted { videoPosterKeys.append(s) }
                }
            }
            for key in videoPosterKeys.prefix(24) {
                let stillHome = await MainActor.run { tabRouter.selected == .home }
                guard stillHome else { return }
                _ = await VideoCacheManager.shared.thumbnailUIImage(forVideoURLString: key)
            }
        }
    }

    private func lightHaptic() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// 生成中全屏页：从首页 **`HomeTemplateDetailView` 预览** 进入时关掉预览回瀑布流上一级；从 **`homeRequestPrimaryGenerate`** 等带 `browseOtherGenerationReturnTab`（如 My Likes）进入则切回对应 Tab；否则回首页 Tab。顶栏 Back 与「浏览其他内容」均走此逻辑。
    private func finishGenerationQueuingExit() {
        let fromHomeTemplatePreview = generationOpenedWithPreviewBelow
        let returnTab = tabRouter.browseOtherGenerationReturnTab
        generationSheetItem = nil
        generationPrefilledImage = nil
        tabRouter.browseOtherGenerationReturnTab = nil
        generationOpenedWithPreviewBelow = false
        if fromHomeTemplatePreview {
            gridDetailItem = nil
        } else if let t = returnTab {
            tabRouter.select(t)
        } else {
            tabRouter.select(.home)
        }
    }

    private func handlePrimaryGenerate(_ item: HomeFeedItem, clickListSource: HomeFeedListSource = .other, prefilledImage: UIImage? = nil) {
        lightHaptic()
        HomeTemplateAnalytics.logClick(templateId: item.id, listSource: clickListSource, action: .primaryGenerate, templateType: item.templateKind.behaviorEventTemplateType)
        guard auth.isAuthenticated else {
            showNeedLoginAlert = true
            return
        }
        generationOpenedWithPreviewBelow = (gridDetailItem != nil)
        generationPrefilledImage = prefilledImage
        generationSheetItem = item
    }

    private func toggleLike(for item: HomeFeedItem) {
        let willLike = !likedTemplateKeys.contains(item.likeStateKey)
        lightHaptic()

        if willLike {
            likedTemplateKeys.insert(item.likeStateKey)
        } else {
            likedTemplateKeys.remove(item.likeStateKey)
        }
        LocalFavoriteTemplateStore.save(likedTemplateKeys, userId: auth.userId)
    }

    private func toggleLike(for item: HomeGridCardItem) {
        let willLike = !likedTemplateKeys.contains(item.likeStateKey)
        lightHaptic()

        if willLike {
            likedTemplateKeys.insert(item.likeStateKey)
        } else {
            likedTemplateKeys.remove(item.likeStateKey)
        }
        LocalFavoriteTemplateStore.save(likedTemplateKeys, userId: auth.userId)
    }
}

extension Notification.Name {
    /// 从「我的 · My Likes」模板详情等处发起生成，由 `HomeView` 统一走登录与上传提示逻辑
    static let homeRequestPrimaryGenerate = Notification.Name("bbb.home.requestPrimaryGenerate")
}

#Preview {
    HomeView()
        .environmentObject(UserWalletStore())
        .environmentObject(AppTabRouter())
        .environmentObject(AuthSessionStore())
        .environmentObject(VersionConfigStore())
        .environmentObject(AppLanguageStore())
        .preferredColorScheme(.dark)
}
