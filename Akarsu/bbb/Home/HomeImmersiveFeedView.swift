//
//  HomeImmersiveFeedView.swift
//  bbb
//
//  参考: home_immersive_full_screen_with_collection_icon_refined_tabs
//

import SwiftUI
import UIKit

private enum HomeImmersiveFeedLayout {
    /// 最后一页下方「没有更多」条高度（计入 `contentSize`）
    static let noMoreFooterHeight: CGFloat = 88
}

/// 沉浸式列表无更多数据：接在最后一屏下方，随 `UIScrollView` 滑动
fileprivate struct HomeImmersiveFeedNoMoreFooter: View {
    var body: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.onSurfaceVariant.opacity(0.85))
            Text(AppLanguageStore.localized("home.grid.no_more"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.onSurfaceVariant)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 18)
    }
}

// MARK: - 单页 UI（UIKit 分页容器复用）

fileprivate struct HomeImmersiveFeedPageView: View {
    let item: HomeFeedItem
    let pageWidth: CGFloat
    let pageHeight: CGFloat
    let showScrollHint: Bool
    let likedKeys: Set<String>
    let requestingLikeKeys: Set<String>
    let onToggleLike: (HomeFeedItem) -> Void
    let onPrimaryAction: (HomeFeedItem) -> Void
    let isBackdropSwitchingActive: Bool

    @State private var immersiveUserVoiceOn = false

    /// 与底栏 `VStack` 左右 `padding(16)`、`HStack` 间距 `10`、心形 `54` 对齐；写死宽度避免窄屏（SE）在点按 / 弹层后依赖 `maxWidth: .infinity` 二次布局抖动
    private var primaryCapsuleWidth: CGFloat {
        let horizontalInset: CGFloat = 16 * 2
        let heartColumn: CGFloat = 54
        let betweenSpacing: CGFloat = 10
        return max(96, pageWidth - horizontalInset - betweenSpacing - heartColumn)
    }

    private var immersiveVideoMuted: Bool {
        !item.hasTemplateVoice || !immersiveUserVoiceOn
    }

    /// 背板 `allowsHitTesting(false)`，喇叭放在本页叠层；T2/T3 走单段成片，T1 仅当 trans 轮播含视频段时显示。
    private var immersiveShowsVoiceChip: Bool {
        guard item.hasTemplateVoice else { return false }
        if item.templateKind == .t2 || item.templateKind == .t3 {
            return (item.immersivePrimaryLoopVideoURL ?? item.playbackVideoURL) != nil
        }
        return item.immersiveTransAnimationCarouselURLs.contains { HomeImmersiveMediaURL.isVideo($0) }
    }

    var body: some View {
        let likeKey = item.likeStateKey
        let isLiked = likedKeys.contains(likeKey)
        let likeBusy = requestingLikeKeys.contains(likeKey)
        /// 勿使用 `VStack { Spacer(); 底栏 }` 撑满全高：会把整页变成可命中区域，全屏视频/图（UIKit）层在上层或同层竞争时，SWAP/心形无法稳定接收点击。
        return ZStack(alignment: .bottom) {
            /// T2/T3：不复用瀑布流 `HomeGridCardSharedMediaStack`（格内转场/顺序播）；全屏仅按 `transAnimation`/`afterVideo` 静音循环成片，见 `immersivePrimaryLoopVideoURL`。
            ImmersiveFeedMediaBackdrop(
                itemId: item.likeStateKey,
                playbackVideoURL: item.immersivePrimaryLoopVideoURL ?? item.playbackVideoURL,
                imageURLs: item.immersiveListBackdropImageURLs,
                interval: item.slideshowInterval,
                width: pageWidth,
                height: pageHeight,
                isSwitchingActive: isBackdropSwitchingActive,
                stoppedPosterVideoURL: item.immersiveStoppedPosterVideoURL,
                transAnimationCarouselURLs: (item.templateKind == .t2 || item.templateKind == .t3)
                    ? []
                    : item.immersiveTransAnimationCarouselURLs,
                isVideoMuted: immersiveVideoMuted
            )
            .onChange(of: item.id) { _ in
                immersiveUserVoiceOn = false
            }

            LinearGradient(
                colors: [
                    Color.black.opacity(0.38),
                    Color.black.opacity(0.06),
                    Color.clear,
                    Color.black.opacity(0.12),
                    Color.black.opacity(0.62)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: pageWidth, height: pageHeight)
            .allowsHitTesting(false)

            if let tag = item.topTag {
                VStack {
                    HStack {
                        HomeGridTopTagView(tag: tag)
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, 16)
                    .padding(.top, 52)
                    Spacer(minLength: 0)
                }
                .frame(width: pageWidth, height: pageHeight)
                .allowsHitTesting(false)
            }

            VStack(spacing: 14) {
                if showScrollHint {
                    HomeScrollHintPill()
                }

                HStack(alignment: .center, spacing: 10) {
                    Button(action: { onPrimaryAction(item) }) {
                            HStack(spacing: 0) {
                                HStack(spacing: 10) {
                                    Image(systemName: item.mediaIcon)
                                        .font(.title3)
                                    Text(item.actionTitle.uppercased(with: .current))
                                        .font(.system(size: 14, weight: .heavy))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.85)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                HStack(spacing: 8) {
                                    Rectangle()
                                        .fill(Color.white.opacity(0.22))
                                        .frame(width: 1, height: 20)
                                    Text("\(item.consumedCoins)")
                                        .font(.system(size: 15, weight: .bold))
                                        .monospacedDigit()
                                        .frame(minWidth: 40, alignment: .trailing)
                                    AppCoinIcon(size: 17)
                                }
                                .layoutPriority(1)
                                .fixedSize(horizontal: true, vertical: false)
                            }
                            .foregroundStyle(.white)
                            .padding(.leading, 22)
                            .padding(.trailing, 18)
                            .padding(.vertical, 16)
                            .frame(width: primaryCapsuleWidth, alignment: .center)
                            .background(
                                LinearGradient(
                                    colors: [
                                        Color(red: 200 / 255, green: 150 / 255, blue: 255 / 255),
                                        AppTheme.primaryDim,
                                        Color(red: 110 / 255, green: 45 / 255, blue: 210 / 255)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(
                                        LinearGradient(
                                            colors: [Color.white.opacity(0.35), Color.white.opacity(0.1)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                            .shadow(color: AppTheme.primaryDim.opacity(0.65), radius: 24, y: 10)
                        }
                        .buttonStyle(.plain)

                    /// 收藏按钮布局与改喇叭前一致；喇叭叠在按钮上方，不占底栏纵向排版
                    Button(action: { onToggleLike(item) }) {
                        Image(systemName: isLiked ? "heart.fill" : "heart")
                            .font(.title2)
                            .foregroundStyle(isLiked ? AppTheme.primary : Color.white.opacity(0.92))
                            .frame(width: 54, height: 54)
                            .background(Color.black.opacity(0.35))
                            .background(.ultraThinMaterial.opacity(0.7))
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(AppTheme.outlineVariant.opacity(0.3), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
                    }
                    .buttonStyle(.plain)
                    .disabled(likeBusy)
                    .opacity(likeBusy ? 0.55 : 1)
                    .overlay(alignment: .top) {
                        if immersiveShowsVoiceChip {
                            /// `HomeTemplateVoiceToggleChip` 为 36×36；与心形顶缘留 10pt 间隙
                            let chipSide: CGFloat = 36
                            let gapAboveHeart: CGFloat = 10
                            HomeTemplateVoiceToggleChip(isVoiceOn: immersiveUserVoiceOn) {
                                immersiveUserVoiceOn.toggle()
                            }
                            .offset(y: -(chipSide + gapAboveHeart))
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            /// 与 `MainTabView.safeAreaInset` 配合：内容区底即 TabBar 顶；主按钮底缘再上移 20pt
            .padding(.bottom, 20)
        }
        .frame(width: pageWidth, height: pageHeight)
    }
}

// MARK: - UIKit 纵向分页（`isPagingEnabled` 步长 = `bounds.height`，避免 SwiftUI 分页错位）

fileprivate struct ImmersiveFeedPagingStack: View {
    /// 当前应开启轮播/转场的条目键（`HomeFeedItem.likeStateKey`，避免 t1/t2/t3 模板 id 与接口撞号）
    let backdropActiveItemId: String?
    let feed: [HomeFeedItem]
    let pageWidth: CGFloat
    let pageHeight: CGFloat
    let showScrollHintOnFirstPage: Bool
    var likedKeys: Set<String>
    var requestingLikeKeys: Set<String>
    var onToggleLike: (HomeFeedItem) -> Void
    var onPrimaryAction: (HomeFeedItem) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(feed.enumerated()), id: \.element.likeStateKey) { index, item in
                HomeImmersiveFeedPageView(
                    item: item,
                    pageWidth: pageWidth,
                    pageHeight: pageHeight,
                    showScrollHint: showScrollHintOnFirstPage && index == 0,
                    likedKeys: likedKeys,
                    requestingLikeKeys: requestingLikeKeys,
                    onToggleLike: onToggleLike,
                    onPrimaryAction: onPrimaryAction,
                    isBackdropSwitchingActive: backdropActiveItemId == item.likeStateKey
                )
                .frame(width: pageWidth, height: pageHeight)
                .clipped()
            }
        }
        .frame(width: pageWidth, alignment: .top)
    }
}

fileprivate struct HomeImmersivePagingScrollRepresentable: UIViewRepresentable {
    var feed: [HomeFeedItem]
    var showScrollHintOnFirstPage: Bool
    /// 与 `feed` 等无关时也要触发 `updateUIView`（内嵌 `UIHostingController` 否则不会随语言切换刷新文案）
    var localizationRefreshToken: String
    var likedKeys: Set<String>
    var requestingLikeKeys: Set<String>
    var onToggleLike: (HomeFeedItem) -> Void
    var onPrimaryAction: (HomeFeedItem) -> Void
    var onRefresh: (() async -> Void)?
    /// 接近列表底部时上滑加载更多（与网格一致）
    var onLoadMore: (() -> Void)?
    /// 是否仍有服务端下一页（避免无效请求）
    var hasMore: Bool = true
    /// 正在请求下一页时不重复触发
    var isLoadingMore: Bool = false
    /// 冷启动或切回该分类时恢复到上次停留的条目（`likeStateKey`）；应用后由 `onScrollRestoreApplied` 清空
    var scrollRestoreKey: String?
    var onScrollRestoreApplied: (() -> Void)?
    @Binding var visibleFeedItemId: String?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.isPagingEnabled = true
        scroll.delegate = context.coordinator
        scroll.showsVerticalScrollIndicator = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.bounces = true
        scroll.alwaysBounceVertical = true
        scroll.backgroundColor = .clear
        scroll.clipsToBounds = true
        /// 禁止系统自动加 `contentInset`（安全区等），否则与 `isPagingEnabled` 的整页步长不一致，会出现第 2 页起整体上移/错位
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.contentInset = .zero
        scroll.scrollIndicatorInsets = .zero
        /// 默认：允许滚动在拖动时取消子视图触摸，否则 `UIHostingController` 全屏占满时纵向分页无法接管手势。
        /// `delaysContentTouches = false` 保留，减轻内嵌 `Button` 的首次响应延迟。
        scroll.delaysContentTouches = false
        scroll.canCancelContentTouches = true
        context.coordinator.scrollView = scroll
        return scroll
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.update(scrollView: scrollView, visibleBinding: $visibleFeedItemId, retryCount: 0)
    }

    static func dismantleUIView(_ uiView: UIScrollView, coordinator: Coordinator) {
        coordinator.hostingController?.view.removeFromSuperview()
        coordinator.hostingController = nil
        coordinator.footerHostingController?.view.removeFromSuperview()
        coordinator.footerHostingController = nil
        coordinator.scrollView = nil
        coordinator.visibleBinding = nil
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: HomeImmersivePagingScrollRepresentable!
        var visibleBinding: Binding<String?>?
        weak var scrollView: UIScrollView?
        var hostingController: UIHostingController<ImmersiveFeedPagingStack>?
        /// 无更多数据时接在最后一页下方，随 `UIScrollView` 滚动
        var footerHostingController: UIHostingController<HomeImmersiveFeedNoMoreFooter>?
        private var lastNearBottomFire: TimeInterval = 0
        /// 上一帧列表首项键；变化时表示换了数据源或筛选，需回到第一页避免 `contentOffset` 落在新列表范围外导致空白
        private var lastFeedHeadKey: String?
        /// 避免同一 `scrollRestoreKey` 在 `updateUIView` 多帧重复应用
        private var lastAppliedScrollRestoreKey: String?

        func attachRefreshIfNeeded() {
            guard let scrollView else { return }
            guard parent.onRefresh != nil else {
                scrollView.refreshControl = nil
                return
            }
            if scrollView.refreshControl == nil {
                let rc = UIRefreshControl()
                rc.addTarget(self, action: #selector(refreshPulled), for: .valueChanged)
                scrollView.refreshControl = rc
            }
        }

        @objc func refreshPulled() {
            guard let onRefresh = parent.onRefresh else {
                scrollView?.refreshControl?.endRefreshing()
                return
            }
            Task {
                await onRefresh()
                await MainActor.run { [weak self] in
                    self?.scrollView?.refreshControl?.endRefreshing()
                }
            }
        }

        func update(scrollView: UIScrollView, visibleBinding: Binding<String?>, retryCount: Int = 0) {
            self.scrollView = scrollView
            self.visibleBinding = visibleBinding
            attachRefreshIfNeeded()

            let bounds = scrollView.bounds
            guard bounds.width > 1, bounds.height > 1 else {
                /// 切换主分类后新建的 `UIScrollView` 常在这一帧仍为 `.zero`，直接 `return` 会导致之后不再刷新 → 一直无内容
                guard retryCount < 20 else { return }
                DispatchQueue.main.async { [weak self] in
                    guard let self, let sv = self.scrollView else { return }
                    var v: UIView? = sv
                    for _ in 0 ..< 8 {
                        v?.layoutIfNeeded()
                        v = v?.superview
                    }
                    self.update(scrollView: sv, visibleBinding: visibleBinding, retryCount: retryCount + 1)
                }
                return
            }
            let w = bounds.width
            let h = bounds.height

            guard !parent.feed.isEmpty else {
                lastFeedHeadKey = nil
                hostingController?.view.isHidden = true
                scrollView.contentOffset = .zero
                /// 勿将 `contentSize.height` 置 0：若干布局路径下会固定子视图高度为 0，后续即使有数据也不再测量
                return
            }
            hostingController?.view.isHidden = false

            /// 仅在「首条模板已变」时回到顶部（如下拉刷新后列表替换）；首帧 `lastFeedHeadKey == nil` 时不强制归零，以便 `scrollRestoreKey` 恢复偏移。
            if let headKey = parent.feed.first?.likeStateKey {
                if let last = lastFeedHeadKey {
                    if last != headKey {
                        lastFeedHeadKey = headKey
                        scrollView.contentOffset = .zero
                    }
                } else {
                    lastFeedHeadKey = headKey
                }
            } else {
                lastFeedHeadKey = nil
            }

            scrollView.layoutIfNeeded()

            let count = parent.feed.count
            let feedStackHeight = h * CGFloat(count)
            let footerH: CGFloat = (!parent.hasMore && count > 0) ? HomeImmersiveFeedLayout.noMoreFooterHeight : 0
            let contentHeight = feedStackHeight + footerH
            let maxY = max(0, contentHeight - h)

            if let restore = parent.scrollRestoreKey, !restore.isEmpty,
               restore != lastAppliedScrollRestoreKey {
                if let idx = parent.feed.firstIndex(where: { $0.likeStateKey == restore }) {
                    let targetY = min(CGFloat(idx) * h, maxY)
                    scrollView.contentOffset = CGPoint(x: 0, y: targetY)
                    lastAppliedScrollRestoreKey = restore
                    DispatchQueue.main.async {
                        self.parent.onScrollRestoreApplied?()
                    }
                } else {
                    lastAppliedScrollRestoreKey = restore
                    DispatchQueue.main.async {
                        self.parent.onScrollRestoreApplied?()
                    }
                }
            } else if parent.scrollRestoreKey == nil || (parent.scrollRestoreKey?.isEmpty ?? true) {
                lastAppliedScrollRestoreKey = nil
            }

            var offset = scrollView.contentOffset
            if offset.y > maxY {
                scrollView.contentOffset = CGPoint(x: 0, y: maxY)
                offset = scrollView.contentOffset
            }

            // 必须先对齐 `visibleFeedItemId`，再构建 `ImmersiveFeedPagingStack`；否则首帧仍用 nil/旧键，`isBackdropSwitchingActive` 为 false，转场不会挂载
            let page = min(max(0, Int(round(offset.y / h))), max(0, count - 1))
            let expectedKey = parent.feed[page].likeStateKey
            if visibleBinding.wrappedValue != expectedKey {
                /// 不可在 `updateUIView` 同步写 `Binding`，否则会触发 “Modifying state during view update”
                let binding = visibleBinding
                let key = expectedKey
                DispatchQueue.main.async {
                    if binding.wrappedValue != key {
                        binding.wrappedValue = key
                    }
                }
            }

            let root = ImmersiveFeedPagingStack(
                backdropActiveItemId: expectedKey,
                feed: parent.feed,
                pageWidth: w,
                pageHeight: h,
                showScrollHintOnFirstPage: parent.showScrollHintOnFirstPage,
                likedKeys: parent.likedKeys,
                requestingLikeKeys: parent.requestingLikeKeys,
                onToggleLike: parent.onToggleLike,
                onPrimaryAction: parent.onPrimaryAction
            )

            if hostingController == nil {
                let host = UIHostingController(rootView: root)
                host.view.backgroundColor = .clear
                scrollView.addSubview(host.view)
                hostingController = host
            } else {
                hostingController?.rootView = root
            }

            hostingController?.view.frame = CGRect(x: 0, y: 0, width: w, height: feedStackHeight)

            if footerH > 0 {
                if footerHostingController == nil {
                    let host = UIHostingController(rootView: HomeImmersiveFeedNoMoreFooter())
                    host.view.backgroundColor = .clear
                    scrollView.addSubview(host.view)
                    footerHostingController = host
                } else {
                    footerHostingController?.rootView = HomeImmersiveFeedNoMoreFooter()
                }
                footerHostingController?.view.isHidden = false
                footerHostingController?.view.frame = CGRect(x: 0, y: feedStackHeight, width: w, height: footerH)
            } else {
                footerHostingController?.view.isHidden = true
            }

            scrollView.contentSize = CGSize(width: w, height: contentHeight)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard let parent, let binding = visibleBinding else { return }
            let h = scrollView.bounds.height
            guard h > 1, !parent.feed.isEmpty else { return }
            let rawPage = Int(round(scrollView.contentOffset.y / h))
            let page = min(max(0, rawPage), parent.feed.count - 1)
            let key = parent.feed[page].likeStateKey
            if binding.wrappedValue != key {
                binding.wrappedValue = key
            }

            tryFireLoadMoreIfNeeded(scrollView: scrollView, onLoadMore: parent.onLoadMore, hasMore: parent.hasMore, isLoadingMore: parent.isLoadingMore, feedEmpty: parent.feed.isEmpty)
        }

        /// 仅一页高时 `contentSize.height == bounds.height`，若用 `>` 判断会永远不触发上拉加载
        private func tryFireLoadMoreIfNeeded(
            scrollView: UIScrollView,
            onLoadMore: (() -> Void)?,
            hasMore: Bool,
            isLoadingMore: Bool,
            feedEmpty: Bool
        ) {
            let h = scrollView.bounds.height
            guard let onLoadMore,
                  hasMore,
                  !isLoadingMore,
                  !feedEmpty,
                  h > 1,
                  scrollView.contentSize.height >= h else { return }
            let distanceBottom = scrollView.contentSize.height - scrollView.contentOffset.y - h
            let pageFromBottom = distanceBottom / h
            guard pageFromBottom < 1.6 else { return }
            let now = Date().timeIntervalSinceReferenceDate
            if now - lastNearBottomFire > 0.55 {
                lastNearBottomFire = now
                DispatchQueue.main.async { onLoadMore() }
            }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            guard let parent else { return }
            tryFireLoadMoreIfNeeded(
                scrollView: scrollView,
                onLoadMore: parent.onLoadMore,
                hasMore: parent.hasMore,
                isLoadingMore: parent.isLoadingMore,
                feedEmpty: parent.feed.isEmpty
            )
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            guard !decelerate, let parent else { return }
            tryFireLoadMoreIfNeeded(
                scrollView: scrollView,
                onLoadMore: parent.onLoadMore,
                hasMore: parent.hasMore,
                isLoadingMore: parent.isLoadingMore,
                feedEmpty: parent.feed.isEmpty
            )
        }
    }
}

struct HomeImmersiveFeedView: View {
    @EnvironmentObject private var appLanguage: AppLanguageStore

    let feed: [HomeFeedItem]
    let showScrollHintOnFirstPage: Bool
    var likedKeys: Set<String>
    var requestingLikeKeys: Set<String>
    var onToggleLike: (HomeFeedItem) -> Void
    /// 底部主按钮（如 SWAP FACE / CREATE VIDEO）
    var onPrimaryAction: (HomeFeedItem) -> Void
    var onRefresh: (() async -> Void)?
    var onLoadMore: (() -> Void)?
    /// 与 `HomeView.homeHasMore` / `homeLoadingMore` 对齐
    var hasMore: Bool = true
    var isLoadingMore: Bool = false
    /// 当前分页落在屏幕上的条目；由首页持有并持久化，便于杀进程后恢复
    @Binding var visibleFeedItemId: String?
    /// 冷启动恢复：目标条目 `likeStateKey`，应用一次后由 `onScrollRestoreApplied` 清空
    var scrollRestoreKey: String?
    var onScrollRestoreApplied: (() -> Void)?

    /// 「已加载全部内容」短时提示，显示约 2 秒后隐藏
    @State private var showAllLoadedHint = false
    @State private var allLoadedHintHideTask: Task<Void, Never>?

    init(
        feed: [HomeFeedItem],
        showScrollHintOnFirstPage: Bool,
        likedKeys: Set<String> = [],
        requestingLikeKeys: Set<String> = [],
        onToggleLike: @escaping (HomeFeedItem) -> Void = { _ in },
        onPrimaryAction: @escaping (HomeFeedItem) -> Void = { _ in },
        onRefresh: (() async -> Void)? = nil,
        onLoadMore: (() -> Void)? = nil,
        hasMore: Bool = true,
        isLoadingMore: Bool = false,
        visibleFeedItemId: Binding<String?> = .constant(nil),
        scrollRestoreKey: String? = nil,
        onScrollRestoreApplied: (() -> Void)? = nil
    ) {
        self.feed = feed
        self.showScrollHintOnFirstPage = showScrollHintOnFirstPage
        self.likedKeys = likedKeys
        self.requestingLikeKeys = requestingLikeKeys
        self.onToggleLike = onToggleLike
        self.onPrimaryAction = onPrimaryAction
        self.onRefresh = onRefresh
        self.onLoadMore = onLoadMore
        self.hasMore = hasMore
        self.isLoadingMore = isLoadingMore
        self._visibleFeedItemId = visibleFeedItemId
        self.scrollRestoreKey = scrollRestoreKey
        self.onScrollRestoreApplied = onScrollRestoreApplied
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            HomeImmersivePagingScrollRepresentable(
                feed: feed,
                showScrollHintOnFirstPage: showScrollHintOnFirstPage,
                localizationRefreshToken: "\(appLanguage.preference.storageValue)|\(Locale.current.identifier)",
                likedKeys: likedKeys,
                requestingLikeKeys: requestingLikeKeys,
                onToggleLike: onToggleLike,
                onPrimaryAction: onPrimaryAction,
                onRefresh: onRefresh,
                onLoadMore: onLoadMore,
                hasMore: hasMore,
                isLoadingMore: isLoadingMore,
                scrollRestoreKey: scrollRestoreKey,
                onScrollRestoreApplied: onScrollRestoreApplied,
                visibleFeedItemId: $visibleFeedItemId
            )
            /// 铺满 `HomeView` 分给主内容区的高度；`MainTabView.safeAreaInset` 已避开 TabBar。仅忽略左右安全区以全宽背景
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(edges: .horizontal)
            .clipped()
            .onChange(of: hasMore) { new in
                if !new, !feed.isEmpty {
                    triggerAllLoadedHintBriefly()
                }
            }
            .onChange(of: feed.count) { _ in
                if !hasMore, !feed.isEmpty {
                    triggerAllLoadedHintBriefly()
                }
            }
            .onDisappear {
                allLoadedHintHideTask?.cancel()
                allLoadedHintHideTask = nil
            }

            if isLoadingMore, hasMore {
                HStack(spacing: 10) {
                    Text(AppLanguageStore.localized("home.immersive.loading_more"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.onSurface)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.45))
                        .background(.ultraThinMaterial.opacity(0.85), in: Capsule())
                )
                .overlay(
                    Capsule()
                        .stroke(AppTheme.outlineVariant.opacity(0.25), lineWidth: 1)
                )
                .padding(.bottom, 100)
                .allowsHitTesting(false)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .animation(.easeOut(duration: 0.2), value: isLoadingMore)
            }

            if showAllLoadedHint {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.onSurfaceVariant.opacity(0.9))
                    Text(AppLanguageStore.localized("home.immersive.all_loaded"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.onSurfaceVariant)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.42))
                        .background(.ultraThinMaterial.opacity(0.82), in: Capsule())
                )
                .overlay(
                    Capsule()
                        .stroke(AppTheme.outlineVariant.opacity(0.22), lineWidth: 1)
                )
                .padding(.bottom, 100)
                .allowsHitTesting(false)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .animation(.spring(response: 0.38, dampingFraction: 0.86), value: showAllLoadedHint)
            }
        }
    }

    /// 在无更多数据且列表非空时弹出，约 2 秒后收起；重复触发会重置计时
    private func triggerAllLoadedHintBriefly() {
        guard !feed.isEmpty, !hasMore else { return }
        allLoadedHintHideTask?.cancel()
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            showAllLoadedHint = true
        }
        allLoadedHintHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.22)) {
                showAllLoadedHint = false
            }
        }
    }
}

/// 首屏模板加载中与沉浸式分页同区域占位，避免仅中央 `ProgressView`
struct HomeImmersiveFeedLoadingPlaceholder: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 45, paused: false)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let phase = (sin(t * 2.1) + 1) * 0.5
            let base = 0.32 + phase * 0.12

            ZStack(alignment: .bottom) {
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.94),
                        AppTheme.surfaceContainer.opacity(0.82),
                        Color.black.opacity(0.9)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    VStack(alignment: .leading, spacing: 14) {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(AppTheme.surfaceContainerHighest.opacity(base))
                            .frame(width: 168, height: 15)
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(AppTheme.surfaceContainerHighest.opacity(base * 0.88))
                            .frame(width: 236, height: 13)
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(AppTheme.surfaceContainerHighest.opacity(base * 1.05))
                                .frame(width: 128, height: 48)
                            Spacer(minLength: 0)
                            Circle()
                                .fill(AppTheme.surfaceContainerHighest.opacity(base))
                                .frame(width: 54, height: 54)
                        }
                    }
                    .padding(.horizontal, 20)
                    /// 与 `HomeImmersiveFeedPageView` 底栏大致对齐
                    .padding(.bottom, 20)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - 列表背景：T1 可按 trans 多段轮播或双图扫荡；T2/T3 仅单段成片循环（`transAnimation`/`afterVideo`，无多段转场）

struct ImmersiveFeedMediaBackdrop: View {
    let itemId: String
    let playbackVideoURL: URL?
    let imageURLs: [URL]
    let interval: TimeInterval
    let width: CGFloat
    let height: CGFloat
    /// 仅当前分页落在视口内时为 true，才运行动画与轮播
    let isSwitchingActive: Bool
    /// T2/T3：非当前条时首帧兜底；T1 为 nil。
    var stoppedPosterVideoURL: URL? = nil
    /// 模板详情等：`true` 时主图等比例完整显示（留边）；首页沉浸式为 `false`。
    var aspectFit: Bool = false
    /// T1：多段 `transAnimation` 顺序轮播；T2/T3 传空（仅走 `playbackVideoURL` 单段循环）
    var transAnimationCarouselURLs: [URL] = []
    /// 成片 / trans 内视频段是否静音（有声模板未开喇叭时为 `true`）。
    var isVideoMuted: Bool = true

    var body: some View {
        Group {
            if isSwitchingActive {
                if !transAnimationCarouselURLs.isEmpty {
                    HomeImmersiveTransAnimationCarouselBackdrop(
                        itemId: itemId,
                        urls: transAnimationCarouselURLs,
                        interval: interval,
                        width: width,
                        height: height,
                        imageAspectFit: aspectFit,
                        isVideoMuted: isVideoMuted
                    )
                    .id("\(itemId)-trans-carousel-\(transAnimationCarouselURLs.map(\.absoluteString).joined(separator: "|"))")
                } else if let videoURL = playbackVideoURL {
                    HomeImmersiveVideoBackdrop(
                        remoteURL: videoURL,
                        width: width,
                        height: height,
                        hasTemplateVoice: false,
                        externalPlaybackMuted: isVideoMuted
                    )
                        .id("\(itemId)-loop-\(videoURL.absoluteString)")
                } else if imageURLs.count >= 2 {
                    ImmersiveFeedScanCompareBackdrop(
                        itemId: itemId,
                        beforeURL: imageURLs.first!,
                        afterURL: imageURLs.last!,
                        width: width,
                        height: height,
                        aspectFit: aspectFit
                    )
                } else if let first = imageURLs.first {
                    ImmersiveFeedStaticBackdrop(imageURLs: [first], width: width, height: height, aspectFit: aspectFit)
                } else {
                    AppTheme.surfaceContainer
                }
            } else if let first = transAnimationCarouselURLs.first {
                if HomeImmersiveMediaURL.isVideo(first) {
                    ImmersiveFeedVideoPosterBackdrop(
                        videoURL: first,
                        width: width,
                        height: height,
                        aspectFit: aspectFit
                    )
                } else {
                    ImmersiveFeedStaticBackdrop(imageURLs: [first], width: width, height: height, aspectFit: aspectFit)
                }
            } else if let posterURL = stoppedPosterVideoURL {
                ImmersiveFeedVideoPosterBackdrop(
                    videoURL: posterURL,
                    width: width,
                    height: height,
                    aspectFit: aspectFit
                )
            } else {
                ImmersiveFeedStaticBackdrop(imageURLs: imageURLs, width: width, height: height, aspectFit: aspectFit)
            }
        }
        .allowsHitTesting(false)
    }
}

/// 列表非当前条：展示 trans（或成片）视频首帧，与 `VideoCacheManager.thumbnailUIImage` 一致。
private struct ImmersiveFeedVideoPosterBackdrop: View {
    let videoURL: URL
    let width: CGFloat
    let height: CGFloat
    var aspectFit: Bool = false
    @State private var poster: UIImage?

    var body: some View {
        ZStack {
            Color.black
            if let poster {
                Image(uiImage: poster)
                    .resizable()
                    .modifier(ImmersiveFeedPosterScaling(aspectFit: aspectFit))
                    .frame(width: width, height: height)
            } else {
                /// transAnimation 内视频（或成片）首帧解码完成前显示加载指示，与瀑布流 `HomeGridTransAnimationVideoPosterView` 一致
                ProgressView()
                    .tint(AppTheme.primary)
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .task(id: videoURL.absoluteString) {
            poster = await VideoCacheManager.shared.thumbnailUIImage(forVideoURLString: videoURL.absoluteString)
        }
    }
}

private struct ImmersiveFeedPosterScaling: ViewModifier {
    var aspectFit: Bool
    func body(content: Content) -> some View {
        if aspectFit {
            content.scaledToFit()
        } else {
            content.scaledToFill()
        }
    }
}

/// 未滑到当前屏 / 详情未加载完：只显示首图（或占位），不跑定时器与视频
struct ImmersiveFeedStaticBackdrop: View {
    let imageURLs: [URL]
    let width: CGFloat
    let height: CGFloat
    var aspectFit: Bool = false

    var body: some View {
        ZStack {
            Color.black
            if let u = imageURLs.first {
                HomeCachedImage(url: u, priority: .utility, aspectFit: aspectFit, showsLoadingIndicator: false)
                    .frame(width: width, height: height)
            } else {
                AppTheme.surfaceContainer
            }
        }
        .frame(width: width, height: height)
        .clipped()
    }
}

// MARK: - 双图扫荡对比（首帧 before / 末帧 after，竖线来回扫）

/// 用可动画 `Shape` 做左右裁剪，避免 `.mask { Rectangle.frame(width:) }` 在首屏未触发二次布局时
/// 裁剪区域不随 `split` 更新、仅 `GeometryReader` 扫描线移动的问题（上下滑动后布局刷新即恢复）。
private struct HorizontalSplitRevealShape: Shape, Animatable {
    var fraction: CGFloat
    var animatableData: CGFloat {
        get { fraction }
        set { fraction = newValue }
    }
    func path(in rect: CGRect) -> Path {
        let w = max(0, rect.width * fraction)
        return Path(CGRect(x: 0, y: 0, width: w, height: rect.height))
    }
}

/// 首页沉浸式：无成片视频时，多图不再轮播，改为左右扫荡揭示 before/after
struct ImmersiveFeedScanCompareBackdrop: View {
    let itemId: String
    let beforeURL: URL
    let afterURL: URL
    let width: CGFloat
    let height: CGFloat
    var aspectFit: Bool = false

    @State private var beforeImageSettled = false
    @State private var afterImageSettled = false
    /// 每次重新等待两图就绪时递增，用于 `HomeCachedImage` 的 `.id` 与 `onDecoded` 校验。
    @State private var settleSession = 1
    /// 驱动扫荡相位；**不要**放在 `TimelineView` 内与 `HomeCachedImage` 同层，否则每帧重建会导致加载态不可靠。
    @State private var scanTick = Date()

    private var bothImagesReady: Bool { beforeImageSettled && afterImageSettled }

    private func beginNewSettleSession() {
        beforeImageSettled = false
        afterImageSettled = false
        settleSession += 1
    }

    private func noteAfterDecoded(token: Int) {
        Task { @MainActor in
            guard token == settleSession else { return }
            afterImageSettled = true
        }
    }

    private func noteBeforeDecoded(token: Int) {
        Task { @MainActor in
            guard token == settleSession else { return }
            beforeImageSettled = true
        }
    }

    private let scanDuration: TimeInterval = 2.75

    /// 与 `HomeCachedImage` 内加载并行：优先拉取 **after**（底层全屏），再拉 before；避免两图同优先级时 after 普遍偏慢
    private func preloadScanPair() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await ImageCacheManager.shared.preloadImage(
                    urlString: afterURL.absoluteString,
                    priority: .userInitiated
                )
            }
            group.addTask {
                await ImageCacheManager.shared.preloadImage(
                    urlString: beforeURL.absoluteString,
                    priority: .utility
                )
            }
        }
    }

    /// 用时钟相位驱动分界线，避免 `withAnimation(repeatForever)` 在嵌套 `UIHostingController` 首屏
    /// 不向裁剪/遮罩子树提交动画事务（竖线跟 `GeometryReader` 仍动、图不跟），竖滑触发全量布局后才恢复。
    private static func splitFraction(at date: Date, scanDuration: TimeInterval) -> CGFloat {
        let t = date.timeIntervalSinceReferenceDate
        let period = scanDuration * 2
        let amplitude: CGFloat = 0.28
        let mid: CGFloat = 0.5
        return mid + amplitude * sin((t / period) * (2 * .pi) - .pi / 2)
    }

    private var animatedSplit: CGFloat {
        guard bothImagesReady else { return 0.5 }
        return Self.splitFraction(at: scanTick, scanDuration: scanDuration)
    }

    var body: some View {
        Group {
            if !afterImageSettled {
                /// 网格 T1：默认只展示 before；after 在后台拉取，**不**显示扫荡线
                gridBeforeOnlyWhileAfterLoading(token: settleSession)
            } else {
                scanCompareStack(token: settleSession, split: animatedSplit)
                    .onReceive(Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()) { date in
                        guard bothImagesReady else { return }
                        scanTick = date
                    }
                    .onChange(of: bothImagesReady) { ready in
                        if ready {
                            scanTick = Date()
                        }
                    }
            }
        }
        .task(id: "\(itemId)-\(afterURL.absoluteString)-\(beforeURL.absoluteString)") {
            beginNewSettleSession()
            await preloadScanPair()
        }
        .onDisappear {
            beginNewSettleSession()
        }
    }

    /// after 未进缓存：全屏 before + 加载圈；after 用全尺寸透明层拉取，仅用 `onDecoded` 标记就绪（避免失败仍 `onSettled` 误进扫荡）
    @ViewBuilder
    private func gridBeforeOnlyWhileAfterLoading(token: Int) -> some View {
        ZStack {
            Color.black

            HomeCachedImage(
                url: beforeURL,
                priority: .utility,
                onDecoded: { noteBeforeDecoded(token: token) },
                aspectFit: aspectFit,
                showsLoadingIndicator: false
            )
            .frame(width: width, height: height)
            .clipped()
            .id("\(itemId)-grid-before-only-\(token)-\(beforeURL.absoluteString)")

            HomeCachedImage(
                url: afterURL,
                priority: .userInitiated,
                onDecoded: { noteAfterDecoded(token: token) },
                aspectFit: aspectFit,
                showsLoadingIndicator: false
            )
            .frame(width: width, height: height)
            .opacity(0)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
            .id("\(itemId)-grid-after-prefetch-\(token)-\(afterURL.absoluteString)")

            ProgressView()
                .tint(.white.opacity(0.9))
                .scaleEffect(1.05)
        }
        .frame(width: width, height: height)
        .clipped()
    }

    /// 双图与扫线层：与 `animatedSplit` 解耦，避免在 `TimelineView` 内每帧重建 `HomeCachedImage`。
    @ViewBuilder
    private func scanCompareStack(token: Int, split: CGFloat) -> some View {
        ZStack {
            Color.black

            HomeCachedImage(
                url: afterURL,
                priority: .userInitiated,
                onDecoded: { noteAfterDecoded(token: token) },
                aspectFit: aspectFit,
                showsLoadingIndicator: false
            )
            .frame(width: width, height: height)
            .clipped()
            .id("\(itemId)-after-\(token)-\(afterURL.absoluteString)")

            HomeCachedImage(
                url: beforeURL,
                priority: .utility,
                onDecoded: { noteBeforeDecoded(token: token) },
                aspectFit: aspectFit,
                showsLoadingIndicator: false
            )
            .frame(width: width, height: height)
            .clipped()
            .compositingGroup()
            .clipShape(HorizontalSplitRevealShape(fraction: split))
            .id("\(itemId)-before-\(token)-\(beforeURL.absoluteString)")

            if bothImagesReady {
                GeometryReader { g in
                    let w = g.size.width
                    let h = g.size.height
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    AppTheme.primary.opacity(0.08),
                                    AppTheme.primaryDim.opacity(0.55),
                                    Color(red: 238 / 255, green: 228 / 255, blue: 255 / 255).opacity(0.98),
                                    AppTheme.primaryDim.opacity(0.55),
                                    AppTheme.primary.opacity(0.08)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 5, height: h)
                        .position(x: w * split, y: h / 2)
                        .shadow(color: AppTheme.primaryDim.opacity(0.55), radius: 10, y: 0)
                        .shadow(color: AppTheme.primary.opacity(0.35), radius: 4, y: 0)
                }
            }

            /// after 已就绪后若 before 仍未解码完：不挡死整屏，仅轻遮 + 转圈
            if afterImageSettled, !beforeImageSettled {
                ZStack {
                    Color.black.opacity(0.22)
                    ProgressView()
                        .tint(.white.opacity(0.9))
                }
                .frame(width: width, height: height)
                .allowsHitTesting(false)
            }
        }
        .frame(width: width, height: height)
        .clipped()
    }
}

private struct HomeScrollHintPill: View {
    @State private var bounce = false

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Image(systemName: "arrow.down")
                .font(.system(size: 11, weight: .bold))
                .symbolRenderingMode(.monochrome)
                .offset(y: bounce ? 3 : 0)
                .accessibilityHidden(true)
            BBBTrackedText.text(AppLanguageStore.localized("home.scroll.more"), size: 9, weight: .heavy, tracking: 2.2)
        }
        .foregroundStyle(Color.white.opacity(0.88))
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.5))
        .background(.ultraThinMaterial.opacity(0.72))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)) {
                bounce = true
            }
        }
    }
}

#Preview {
    HomeImmersiveFeedView(
        feed: HomeFeedItem.sampleFeed,
        showScrollHintOnFirstPage: true,
        visibleFeedItemId: .constant(nil)
    )
    .environmentObject(AppLanguageStore())
    .frame(width: 390, height: 640)
    .preferredColorScheme(.dark)
}
