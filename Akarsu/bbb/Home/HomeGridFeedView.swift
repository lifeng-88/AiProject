//
//  HomeGridFeedView.swift
//  bbb
//
//  参考: home_grid_with_refined_card_actions, home_waterfall_skeleton_load
//

import SwiftUI
import UIKit

struct HomeGridFeedView: View {
    let items: [HomeGridCardItem]
    var showSkeleton: Bool
    /// 单元格宽:高（双列均分宽度后，高度由此比例决定；图片超出部分裁剪）
    var cellAspectRatio: CGFloat
    var likedKeys: Set<String>
    var requestingLikeKeys: Set<String>
    var onToggleLike: (HomeGridCardItem) -> Void
    /// 双列瀑布流点击 cell 进入详情（心形按钮不触发）
    var onSelectItem: ((HomeGridCardItem) -> Void)?
    /// 单元格首次进入可视区域（用于曝光去重在 `HomeView`）
    var onTemplateExpose: ((HomeGridCardItem) -> Void)?
    var onRefresh: (() async -> Void)?
    /// 是否还有下一页（用于底部上滑加载更多）
    var hasMore: Bool = false
    var isLoadingMore: Bool = false
    var onLoadMore: (() async -> Void)?
    /// 为 false 时不展示「没有更多」底栏（如「我的喜欢」等无分页场景）
    var showsNoMoreFooter: Bool = true
    /// 大列表切回小列表时：将对应卡片滚至视口顶部（贴近顶栏下缘）
    @Binding var scrollToItemId: String?
    /// 小列表切大列表用：当前可见单元里在数据流中最靠前的一条（双列取左上优先）
    var onVisibleAnchorChange: ((String?) -> Void)?
    /// 为 false 时（离开首页 Tab、进后台、打开详情等）格内视频停播并显示首帧；为 true 且 cell 在屏时才播。
    var allowsCellVideoPlayback: Bool = true

    init(
        items: [HomeGridCardItem],
        showSkeleton: Bool,
        cellAspectRatio: CGFloat = 9 / 16,
        likedKeys: Set<String> = [],
        requestingLikeKeys: Set<String> = [],
        onToggleLike: @escaping (HomeGridCardItem) -> Void = { _ in },
        onSelectItem: ((HomeGridCardItem) -> Void)? = nil,
        onTemplateExpose: ((HomeGridCardItem) -> Void)? = nil,
        onRefresh: (() async -> Void)? = nil,
        hasMore: Bool = false,
        isLoadingMore: Bool = false,
        onLoadMore: (() async -> Void)? = nil,
        showsNoMoreFooter: Bool = true,
        scrollToItemId: Binding<String?> = .constant(nil),
        onVisibleAnchorChange: ((String?) -> Void)? = nil,
        allowsCellVideoPlayback: Bool = true
    ) {
        self.items = items
        self.showSkeleton = showSkeleton
        self.cellAspectRatio = cellAspectRatio
        self.likedKeys = likedKeys
        self.requestingLikeKeys = requestingLikeKeys
        self.onToggleLike = onToggleLike
        self.onSelectItem = onSelectItem
        self.onTemplateExpose = onTemplateExpose
        self.onRefresh = onRefresh
        self.hasMore = hasMore
        self.isLoadingMore = isLoadingMore
        self.onLoadMore = onLoadMore
        self.showsNoMoreFooter = showsNoMoreFooter
        self._scrollToItemId = scrollToItemId
        self.onVisibleAnchorChange = onVisibleAnchorChange
        self.allowsCellVideoPlayback = allowsCellVideoPlayback
    }

    /// 双列：列间距只设在第一列，避免重复；`flexible(minimum:0)` 使剩余宽度两等分
    private var columns: [GridItem] {
        let columnGap: CGFloat = 10
        return [
            GridItem(.flexible(minimum: 0), spacing: columnGap),
            GridItem(.flexible(minimum: 0))
        ]
    }

    private let cardCorner: CGFloat = 14
    private let rowSpacing: CGFloat = 10
    private let horizontalPadding: CGFloat = 10
    private let skeletonPlaceholderCount = 6

    /// 当前在屏上的 cell（`LazyVGrid` onAppear/onDisappear 维护）
    @State private var visibleItemIds: Set<String> = []

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: rowSpacing) {
                    LazyVGrid(columns: columns, spacing: rowSpacing) {
                        if showSkeleton {
                            ForEach(0..<skeletonPlaceholderCount, id: \.self) { _ in
                                HomeGridSkeletonCell(aspectRatio: cellAspectRatio, cornerRadius: cardCorner)
                            }
                        } else {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                HomeGridCard(
                                    item: item,
                                    cellAspectRatio: cellAspectRatio,
                                    cornerRadius: cardCorner,
                                    likedKeys: likedKeys,
                                    requestingLikeKeys: requestingLikeKeys,
                                    onToggleLike: onToggleLike,
                                    onTap: onSelectItem.map { handler in { handler(item) } },
                                    loopsGridVideo: true,
                                    onGridPlaybackFinished: nil,
                                    allowsVideoPlayback: allowsCellVideoPlayback,
                                    isTrackedVisibleByGrid: visibleItemIds.contains(item.id)
                                )
                                .id(item.id)
                                .onAppear {
                                    gridCellDidAppear(item.id)
                                    guard index == items.count - 1, hasMore, !isLoadingMore, let onLoadMore else { return }
                                    Task { await onLoadMore() }
                                }
                                .onDisappear {
                                    gridCellDidDisappear(item.id)
                                }
                            }
                        }
                    }
                    if !showSkeleton, hasMore {
                        loadMoreFooter
                    } else if !showSkeleton, !items.isEmpty, !hasMore, showsNoMoreFooter {
                        noMoreFooter
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 0)
                /// 与 TabBar 的底部间距由 `HomeView` 对主 feed 统一 `.padding(.bottom:)` 处理
                .padding(.bottom, 0)
            }
            .bbbScrollIndicatorsHidden()
            .onAppear {
                performScrollToTargetIfNeeded(proxy: proxy)
            }
            .onChange(of: scrollToItemId) { newId in
                guard newId != nil else { return }
                performScrollToTargetIfNeeded(proxy: proxy)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .refreshable {
            if let onRefresh {
                await onRefresh()
            }
        }
        .onChange(of: items.map(\.id)) { newIds in
            let valid = Set(newIds)
            visibleItemIds = visibleItemIds.intersection(valid)
        }
    }

    private func gridCellDidAppear(_ id: String) {
        visibleItemIds.insert(id)
        if let item = items.first(where: { $0.id == id }) {
            onTemplateExpose?(item)
        }
        notifyVisibleAnchorIfNeeded()
        scheduleViewportAdjacentVideoPreload()
    }

    private func gridCellDidDisappear(_ id: String) {
        visibleItemIds.remove(id)
        notifyVisibleAnchorIfNeeded()
        scheduleViewportAdjacentVideoPreload()
    }

    /// 视口内及上下各约 2 格：优先预加载「即将滚入」的下方 1～2 条视频，再补上方与邻域（不阻塞 UI）
    private func scheduleViewportAdjacentVideoPreload() {
        guard !items.isEmpty, !visibleItemIds.isEmpty else { return }
        let visibleOffsets = items.enumerated()
            .filter { visibleItemIds.contains($0.element.id) }
            .map(\.offset)
        guard let minV = visibleOffsets.min(), let maxV = visibleOffsets.max() else { return }

        var orderedIndices: [Int] = []
        for o in 1...2 {
            let j = maxV + o
            if j < items.count { orderedIndices.append(j) }
        }
        for o in 1...2 {
            let j = minV - o
            if j >= 0 { orderedIndices.append(j) }
        }
        let spanLow = max(0, minV - 2)
        let spanHigh = min(items.count - 1, maxV + 2)
        for i in spanLow...spanHigh where !orderedIndices.contains(i) {
            orderedIndices.append(i)
        }

        var seen = Set<String>()
        let urls: [String] = orderedIndices.compactMap { idx in
            guard let s = items[idx].gridPlaybackVideoURL?.absoluteString else { return nil }
            return seen.insert(s).inserted ? s : nil
        }
        guard !urls.isEmpty else { return }

        Task(priority: .userInitiated) {
            await withTaskGroup(of: Void.self) { group in
                for s in urls {
                    group.addTask {
                        await VideoCacheManager.shared.preloadVideo(videoURL: s, priority: .userInitiated)
                    }
                }
            }
        }
    }

    /// 双列瀑布流：视口内「数据顺序最靠前」的可见项作为切入大列表的锚点（与「左上优先」一致）
    private func notifyVisibleAnchorIfNeeded() {
        guard !items.isEmpty, !visibleItemIds.isEmpty else {
            onVisibleAnchorChange?(nil)
            return
        }
        let best = items.enumerated()
            .filter { visibleItemIds.contains($0.element.id) }
            .min(by: { $0.offset < $1.offset })
        onVisibleAnchorChange?(best?.element.likeStateKey)
    }

    private func performScrollToTargetIfNeeded(proxy: ScrollViewProxy) {
        guard let id = scrollToItemId, items.contains(where: { $0.id == id }) else { return }
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
                proxy.scrollTo(id, anchor: .top)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                scrollToItemId = nil
            }
        }
    }

    private var loadMoreFooter: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            if isLoadingMore {
                ProgressView()
                    .tint(AppTheme.primary)
            } else {
                Text(AppLanguageStore.localized("home.grid.load_more"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.onSurfaceVariant)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .id("home-grid-load-more-\(items.count)")
        .onAppear {
            guard hasMore, !isLoadingMore, let onLoadMore else { return }
            Task { await onLoadMore() }
        }
    }

    private var noMoreFooter: some View {
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
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

/// 双列 `HomeGridCard` 与沉浸式列表 T2/T3 全屏层共用的媒体叠层（底图 + 预览 + 渐变 + 角标），与网格 cell 内层一致
struct HomeGridCardSharedMediaStack: View {
    let item: HomeGridCardItem
    var isPlaybackActive: Bool = false
    var onPlaybackFinished: (() -> Void)?
    /// 瀑布流多格同时播时 `true`：网格内视频循环；沉浸式全屏镜像为 `false` 以保持单次结束回调
    var loopsGridVideoWhilePlaying: Bool = true
    /// `true`（默认）：≥2 段 trans 时间线时用顺序轮播（沉浸式镜像）。`false`：瀑布流仅首帧底图 + 循环 `gridPlaybackVideoURL`。
    var prefersTransAnimationCarousel: Bool = true
    /// 单段 `HomeGridSequentialVideoPreview` 是否等缓存再叠播放器；瀑布流建议 `false` 以便与沉浸式一致立即用网络 URL 起播。
    var deferSequentialVideoUntilCached: Bool = false
    /// 非空时按固定宽高铺满（列表全屏）；为空时按 `cellAspectRatio` 与双列一致
    var fixedWidthHeight: CGSize?
    var cellAspectRatio: CGFloat = 9 / 16
    /// 首页沉浸式列表可对 Dance（T2）/ Video（T3）关闭左下角金币；双列网格保持默认 `true`
    var showsBottomLeftBadge: Bool = true
    /// `nil` 时栈内自持 `@State`；瀑布流 `HomeGridCard` 传入 `$state` 并把 `rendersVoiceToggleInStack` 设为 `false`，喇叭画在按钮外以免被整格点穿。
    var voiceUnmuted: Binding<Bool>? = nil
    var rendersVoiceToggleInStack: Bool = true

    @State private var internalVoiceUnmuted = false

    private var effectiveVoiceUnmuted: Bool {
        voiceUnmuted?.wrappedValue ?? internalVoiceUnmuted
    }

    private var gridVideoPlaybackMuted: Bool {
        !item.hasTemplateVoice || !effectiveVoiceUnmuted
    }

    private var showsVoiceToggleInStack: Bool {
        guard rendersVoiceToggleInStack else { return false }
        return item.shouldShowTemplateVoiceToggle(prefersTransAnimationCarousel: prefersTransAnimationCarousel)
    }

    private var usesGridTransAnimationCarousel: Bool {
        prefersTransAnimationCarousel
            && (item.templateKind == .t2 || item.templateKind == .t3)
            && item.gridTransAnimationCarouselURLs.count >= 2
    }

    var body: some View {
        ZStack {
            if usesGridTransAnimationCarousel {
                GeometryReader { g in
                    let w = g.size.width
                    let h = g.size.height
                    Group {
                        if isPlaybackActive {
                            HomeImmersiveTransAnimationCarouselBackdrop(
                                itemId: item.id,
                                urls: item.gridTransAnimationCarouselURLs,
                                interval: item.gridSlideshowInterval,
                                width: w,
                                height: h,
                                imageAspectFit: false,
                                isVideoMuted: gridVideoPlaybackMuted
                            )
                        } else if let first = item.gridTransAnimationCarouselURLs.first {
                            if HomeImmersiveMediaURL.isVideo(first) {
                                HomeGridTransAnimationVideoPosterView(videoURL: first)
                                    .frame(width: w, height: h)
                                    .clipped()
                            } else {
                                ZStack {
                                    Color.black
                                    HomeCachedImage(url: first, priority: .utility)
                                }
                                .frame(width: w, height: h)
                                .clipped()
                            }
                        } else {
                            AppTheme.surfaceContainer
                        }
                    }
                }
            } else {
                gridMediaBase
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let v = item.gridPlaybackVideoURL {
                    HomeGridSequentialVideoPreview(
                        remoteURL: v,
                        isPlaying: isPlaybackActive,
                        loops: loopsGridVideoWhilePlaying,
                        deferPlaybackUntilCached: deferSequentialVideoUntilCached,
                        isMuted: gridVideoPlaybackMuted,
                        onFinished: { onPlaybackFinished?() }
                    )
                    /// `isPlaybackActive` 变化时重建，确保 `.task` 重新拉流（避免首帧停在 `guard isPlaying` 后永不补播）。
                    .id("\(v.absoluteString)-play-\(isPlaybackActive)")
                }
            }

            LinearGradient(
                colors: [Color.black.opacity(0.2), Color.clear, Color.black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
        }
        .modifier(HomeGridCardMediaSizingModifier(fixedWidthHeight: fixedWidthHeight, cellAspectRatio: cellAspectRatio))
        .clipped()
        .onChange(of: item.id) { _ in
            if voiceUnmuted == nil {
                internalVoiceUnmuted = false
            }
        }
        .overlay(alignment: .topLeading) {
            if let tag = item.topTag {
                HomeGridTopTagView(tag: tag)
                    .padding(10)
            }
        }
        .overlay(alignment: .topTrailing) {
            if showsVoiceToggleInStack {
                HomeTemplateVoiceToggleChip(isVoiceOn: effectiveVoiceUnmuted) {
                    if let b = voiceUnmuted {
                        b.wrappedValue.toggle()
                    } else {
                        internalVoiceUnmuted.toggle()
                    }
                }
                .padding(10)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if showsBottomLeftBadge {
                HomeGridCardBottomLeftBadge(bottomLeft: item.bottomLeft)
                    .padding(8)
            }
        }
    }

    @ViewBuilder
    private var gridMediaBase: some View {
        if item.templateKind == .t2 || item.templateKind == .t3 {
            gridVideoTemplateBaseLayer
        } else if !item.gridSlideshowURLs.isEmpty {
            if isPlaybackActive {
                HomeGridScanCompareView(
                    cardItemId: item.id,
                    urls: item.gridSlideshowURLs,
                    interval: item.gridSlideshowInterval,
                    onCycleFinished: onPlaybackFinished
                )
            } else if let url = item.imageURL ?? item.gridSlideshowURLs.first {
                HomeCachedImage(url: url, priority: .utility)
            } else {
                AppTheme.surfaceContainer
            }
        } else if let url = item.imageURL {
            HomeCachedImage(url: url, priority: .utility)
        } else {
            AppTheme.surfaceContainer
        }
    }

    @ViewBuilder
    private var gridVideoTemplateBaseLayer: some View {
        if let u = item.gridTransAnimationFirstPlaceholderURL {
            if HomeImmersiveMediaURL.isVideo(u) {
                HomeGridTransAnimationVideoPosterView(videoURL: u)
            } else {
                HomeCachedImage(url: u, priority: .utility)
            }
        } else {
            AppTheme.surfaceContainer
        }
    }
}

private struct HomeGridCardMediaSizingModifier: ViewModifier {
    var fixedWidthHeight: CGSize?
    var cellAspectRatio: CGFloat

    func body(content: Content) -> some View {
        if let s = fixedWidthHeight {
            content.frame(width: s.width, height: s.height)
        } else {
            content.frame(maxWidth: .infinity).aspectRatio(cellAspectRatio, contentMode: .fit)
        }
    }
}

/// 与 `HomeGridCard` 左下角金币/锁定一致，供共享媒体层使用
private struct HomeGridCardBottomLeftBadge: View {
    let bottomLeft: HomeGridBottomLeft

    var body: some View {
        switch bottomLeft {
        case .coins(let n):
            HStack(spacing: 4) {
                AppCoinIcon(size: 10)
                Text("\(n)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color(red: 91 / 255, green: 75 / 255, blue: 0))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(AppTheme.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
        case .locked:
            Image(systemName: "lock.fill")
                .font(.system(size: 16))
                .foregroundStyle(.white)
                .padding(8)
                .background(Color.black.opacity(0.4))
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
        }
    }
}

struct HomeGridCard: View {
    let item: HomeGridCardItem
    /// 与 `HomeGridFeedView.cellAspectRatio` 一致，布局用；忽略 `item.aspectRatio` 以实现统一双列高度
    var cellAspectRatio: CGFloat = 9 / 16
    var cornerRadius: CGFloat = 14
    var likedKeys: Set<String> = []
    var requestingLikeKeys: Set<String> = []
    var onToggleLike: (HomeGridCardItem) -> Void = { _ in }
    var onTap: (() -> Void)? = nil
    /// 瀑布流多格同时播时一般为 `true`（视频循环）；沉浸式镜像条为 `false`
    var loopsGridVideo: Bool = true
    var onGridPlaybackFinished: (() -> Void)? = nil
    /// 父级允许且 cell 在屏内时才播（视频/T1 动效）；否则停播，视频格显示解码首帧。
    var allowsVideoPlayback: Bool = true
    /// `HomeGridFeedView` 根据 `onAppear`/`onDisappear` 维护；与内层 `onAppear` 二选一即可视为在屏，避免 LazyVGrid 首帧不同步导致不自动播。
    var isTrackedVisibleByGrid: Bool = false

    private var likeKey: String { item.likeStateKey }
    private var isLiked: Bool { likedKeys.contains(likeKey) }
    private var likeBusy: Bool { requestingLikeKeys.contains(likeKey) }

    /// 与 cell 自身 `onAppear` 绑定，避免 LazyVGrid 首帧尚未写入父级 `visibleItemIds` 时不播
    @State private var isCellVisibleForPlayback = false
    @State private var gridVoiceUnmuted = false

    private var effectiveGridPlaybackActive: Bool {
        let cellVisible = isCellVisibleForPlayback || isTrackedVisibleByGrid
        guard allowsVideoPlayback, cellVisible else { return false }
        switch item.templateKind {
        case .t2, .t3:
            return item.gridPlaybackVideoURL != nil
        case .t1:
            /// 扫荡动效依赖 `gridSlideshowURLs`；仅成片/预览视频走 `gridPlaybackVideoURL` 时也要进入播放态，否则叠层 `HomeGridSequentialVideoPreview` 的 `isPlaying` 恒为 false。
            return !item.gridSlideshowURLs.isEmpty || item.gridPlaybackVideoURL != nil
        }
    }

    var body: some View {
        ZStack {
            Button(action: { onTap?() }) {
                HomeGridCardSharedMediaStack(
                    item: item,
                    isPlaybackActive: effectiveGridPlaybackActive,
                    onPlaybackFinished: onGridPlaybackFinished,
                    loopsGridVideoWhilePlaying: loopsGridVideo,
                    prefersTransAnimationCarousel: false,
                    deferSequentialVideoUntilCached: false,
                    fixedWidthHeight: nil,
                    cellAspectRatio: cellAspectRatio,
                    voiceUnmuted: $gridVoiceUnmuted,
                    rendersVoiceToggleInStack: false
                )
            }
            .buttonStyle(.plain)
            /// 子层含 `allowsHitTesting(false)` 的视频/扫荡层时，否则触摸会穿透整格导致不触发 `onTap`。
            .contentShape(Rectangle())

            VStack {
                Spacer(minLength: 0)
                HStack {
                    Spacer(minLength: 0)
                    heartButton
                        .padding(8)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if item.shouldShowTemplateVoiceToggle(prefersTransAnimationCarousel: false) {
                HomeTemplateVoiceToggleChip(isVoiceOn: gridVoiceUnmuted) {
                    gridVoiceUnmuted.toggle()
                }
                .padding(10)
            }
        }
        .onChange(of: item.id) { _ in
            gridVoiceUnmuted = false
        }
        /// 挂在整格上，避免 LazyVGrid + `Button` 嵌套时内层 `onAppear` 过晚，`isPlaybackActive` 长期为 false 导致视频不自动播。
        .onAppear { isCellVisibleForPlayback = true }
        .onDisappear { isCellVisibleForPlayback = false }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .background(AppTheme.surfaceContainer)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.1), AppTheme.outlineVariant.opacity(0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
    }

    private var heartButton: some View {
        Button(action: { onToggleLike(item) }) {
            Image(systemName: isLiked ? "heart.fill" : "heart")
                .font(.system(size: 16))
                .foregroundStyle(isLiked ? AppTheme.primary : .white)
                .padding(8)
                .background(Color.black.opacity(0.4))
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(likeBusy)
        .opacity(likeBusy ? 0.55 : 1)
    }
}

/// T2/T3：`transAnimation` 内视频或成片 URL 的首帧，经 `VideoCacheManager` 解码；无视频 URL 时由上层改用静态图。
struct HomeGridTransAnimationVideoPosterView: View {
    let videoURL: URL
    @State private var poster: UIImage?

    var body: some View {
        Group {
            if let poster {
                Image(uiImage: poster)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.black
                    .overlay {
                        ProgressView()
                            .tint(.white.opacity(0.45))
                    }
            }
        }
        .task(id: videoURL.absoluteString) {
            poster = await VideoCacheManager.shared.thumbnailUIImage(forVideoURLString: videoURL.absoluteString)
        }
    }
}

/// T1 瀑布流：多图用来回扫荡对比；可见 cell 同时播时不再用定时器切「下一格」（改由可见性控制）
private struct HomeGridScanCompareView: View {
    /// 与模板唯一绑定，避免仅按首图 URL 作为 `itemId` 时多卡片状态串台。
    let cardItemId: String
    let urls: [URL]
    let interval: TimeInterval
    /// 仅沉浸式镜像等需单次结束回调时传入；瀑布流并发播传 `nil`
    var onCycleFinished: (() -> Void)?

    @State private var finishTask: Task<Void, Never>?
    /// 每次 cell 进入可视区递增，强制扫荡层 `itemId` / `.task` 与双图加载会话刷新（避免 LazyVGrid 复用导致未加载完就开扫荡）。
    @State private var gridAppearNonce = 0

    private var step: TimeInterval {
        min(max(interval, 0.9), 45)
    }

    var body: some View {
        Group {
            if urls.count >= 2 {
                GeometryReader { g in
                    ImmersiveFeedScanCompareBackdrop(
                        itemId: "grid-\(cardItemId)-\(gridAppearNonce)",
                        beforeURL: urls.first!,
                        afterURL: urls.last!,
                        width: g.size.width,
                        height: g.size.height,
                        aspectFit: false
                    )
                }
            } else if let u = urls.first {
                HomeCachedImage(url: u, priority: .utility)
            } else {
                AppTheme.surfaceContainer
            }
        }
        .onAppear {
            gridAppearNonce += 1
            scheduleFinishIfNeeded()
        }
        .onDisappear {
            finishTask?.cancel()
            finishTask = nil
        }
    }

    private func scheduleFinishIfNeeded() {
        finishTask?.cancel()
        guard let onCycleFinished else { return }
        guard !urls.isEmpty else {
            onCycleFinished()
            return
        }
        let total = TimeInterval(max(1, urls.count)) * step
        finishTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(total * 1_000_000_000))
            guard !Task.isCancelled else { return }
            onCycleFinished()
        }
    }
}

/// 与首页网格卡片共用（模板详情页主图区复用）
struct HomeGridTopTagView: View {
    let tag: HomeGridTopTag

    var body: some View {
        BBBTrackedText.text(label, size: 9, weight: .heavy, tracking: 2, color: .white, italic: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(background)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(border, lineWidth: 0.5))
    }

    private var label: String {
        switch tag {
        case .free: return AppLanguageStore.localized("grid.tag.free")
        case .hot: return AppLanguageStore.localized("grid.tag.hot")
        case .new: return AppLanguageStore.localized("grid.tag.new")
        }
    }

    private var background: LinearGradient {
        switch tag {
        case .free:
            return LinearGradient(
                colors: [Color.cyan.opacity(0.65), Color.blue.opacity(0.65)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .hot:
            return LinearGradient(
                colors: [Color.orange.opacity(0.75), Color.orange.opacity(0.55)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .new:
            return LinearGradient(
                colors: [Color.green.opacity(0.7), Color.green.opacity(0.5)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var border: Color {
        switch tag {
        case .free: return Color.cyan.opacity(0.45)
        case .hot: return Color.orange.opacity(0.45)
        case .new: return Color.green.opacity(0.45)
        }
    }
}

struct HomeGridSkeletonCell: View {
    var aspectRatio: CGFloat = 9 / 16
    var cornerRadius: CGFloat = 14

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 45, paused: false)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let phase = (sin(t * 2.1) + 1) * 0.5

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(AppTheme.surfaceContainerHighest.opacity(0.38 + phase * 0.12))
                .frame(maxWidth: .infinity)
                .aspectRatio(aspectRatio, contentMode: .fit)
                .overlay {
                    GeometryReader { g in
                        let w = g.size.width
                        LinearGradient(
                            colors: [
                                Color.clear,
                                Color.white.opacity(0.1 + phase * 0.06),
                                Color.clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: w * 0.5)
                        .offset(x: (phase - 0.5) * w * 1.1)
                        .blur(radius: 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                }
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(AppTheme.outlineVariant.opacity(0.14), lineWidth: 1)
                )
        }
    }
}

#Preview {
    HomeGridFeedView(items: HomeGridCardItem.sampleGrid, showSkeleton: false)
        .background(AppTheme.background)
        .preferredColorScheme(.dark)
}
