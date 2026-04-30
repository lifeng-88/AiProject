//
//  MyCreationsView.swift
//  bbb
//
//  我的创作：双列网格、ALL / GENERATING / SUCCESS、各状态卡片（与接口 TaskStatus + 本地过期判断）
//

import AVKit
import SwiftUI
import UIKit

// MARK: - Filter

private enum CreationsFilterTab: Int, CaseIterable {
    case all
    case generating
    case success

    var title: String {
        switch self {
        case .all: return AppLanguageStore.localized("my.creations.filter.all")
        case .generating: return AppLanguageStore.localized("my.creations.filter.generating")
        case .success: return AppLanguageStore.localized("my.creations.filter.success")
        }
    }

    /// `getTaskList` 的 `status` 参数；仅 SUCCESS 走服务端筛选
    var apiStatus: Int32? {
        switch self {
        case .success: return 2
        case .all, .generating: return nil
        }
    }
}

// MARK: - List

struct MyCreationsView: View {
    @EnvironmentObject private var wallet: UserWalletStore
    @EnvironmentObject private var tabRouter: AppTabRouter
    @EnvironmentObject private var appLanguage: AppLanguageStore

    @State private var items: [TaskListItem] = []
    @State private var total: Int32 = 0
    @State private var pageNum: Int32 = 1
    private let pageSize: Int32 = 20
    @State private var loading = false
    @State private var loadingMore = false
    @State private var errorMessage: String?
    @State private var selectedSheet: CreationSheetRoute?
    @State private var filterTab: CreationsFilterTab = .all
    @State private var retryingTaskId: String?
    @State private var showRetryInsufficientCoins = false

    /// 双列横向间距（与 `gridRowSpacing` 一致，避免「横疏竖密」）
    private let gridColumnSpacing: CGFloat = 10
    private let gridRowSpacing: CGFloat = 10

    private var displayedItems: [TaskListItem] {
        switch filterTab {
        case .all:
            return items
        case .generating:
            return items.filter { $0.taskStatus == .pending || $0.taskStatus == .running }
        case .success:
            return items
        }
    }

    /// 双列瀑布流分配结果（短列优先，与 `CreationGridCard` 固定 3:4 比例一致）。
    private var waterfallColumns: (left: [TaskListItem], right: [TaskListItem]) {
        Self.splitWaterfallTwoColumns(displayedItems, rowSpacing: gridRowSpacing)
    }

    /// 首页「生成中」横幅跳转：预选 `GENERATING` 等（与 `AppTabRouter.myCreationsPendingFilter` 对齐）
    private func applyPendingFilterFromTabRouter() {
        guard let raw = tabRouter.myCreationsPendingFilter,
              let tab = CreationsFilterTab(rawValue: raw) else { return }
        filterTab = tab
        tabRouter.consumeMyCreationsPendingFilter()
    }

    var body: some View {
        let _ = appLanguage.preference
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                filterTabStrip
                noticeBanner
                mainBodyBelowFilters
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .bbbScrollIndicatorsHidden()
        .refreshable {
            await load(reset: true)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                BBBTrackedText.text(AppLanguageStore.localized("my.creations.title"), size: 15, weight: .heavy, tracking: 1.2, color: AppTheme.primary)
            }
        }
        .onAppear { applyPendingFilterFromTabRouter() }
        .onChange(of: tabRouter.myCreationsPendingFilter) { _ in
            applyPendingFilterFromTabRouter()
        }
        .onChange(of: tabRouter.pendingCreationOpen?.taskId) { _ in
            Task { await tryResolvePendingPushCreationOpenAfterListChange() }
        }
        .task {
            await load(reset: true)
        }
        .onChange(of: filterTab) { _ in
            Task { await load(reset: true) }
        }
        .alert(AppLanguageStore.localized("common.tip"), isPresented: $showRetryInsufficientCoins) {
            Button(AppLanguageStore.localized("common.ok"), role: .cancel) {}
        } message: {
            Text(AppLanguageStore.localized("my.creations.alert.coins"))
        }
        .background(
            NavigationLink(
                destination: creationSheetDestination,
                isActive: Binding(
                    get: { selectedSheet != nil },
                    set: { if !$0 { selectedSheet = nil } }
                )
            ) {
                EmptyView()
            }
            .frame(width: 0, height: 0)
            .opacity(0)
        )
        .onChange(of: selectedSheet) { new in
            tabRouter.profileDetailPushed = (new != nil)
        }
        .onDisappear {
            tabRouter.profileDetailPushed = false
        }
    }

    @ViewBuilder
    private var creationSheetDestination: some View {
        if let route = selectedSheet {
            switch route {
            case .generationSuccess(let item):
                GenerationSuccessView(item: item) {
                    Task { await load(reset: true) }
                }
            case .detail(let item):
                CreationDetailView(item: item)
            }
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private var mainBodyBelowFilters: some View {
        if loading && items.isEmpty {
            ProgressView()
                .tint(AppTheme.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 72)
        } else if let err = errorMessage, items.isEmpty {
            errorStateInline(err)
        } else if displayedItems.isEmpty {
            emptyStateInline
        } else {
            gridSection
        }
    }

    private func errorStateInline(_ err: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(AppTheme.secondary.opacity(0.85))
            Text(err)
                .font(.subheadline)
                .foregroundStyle(AppTheme.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
            Button(AppLanguageStore.localized("common.retry")) {
                Task { await load(reset: true) }
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var emptyStateInline: some View {
        VStack(spacing: 18) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(AppTheme.primary.opacity(0.4))
            Text(filterTab == .all ? AppLanguageStore.localized("my.creations.empty.all") : AppLanguageStore.localized("my.creations.empty.filtered"))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppTheme.onSurface)
            Text(AppLanguageStore.localized("my.creations.empty.detail"))
                .font(.subheadline)
                .foregroundStyle(AppTheme.onSurfaceVariant)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, 8)
    }

    private var gridSection: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: gridColumnSpacing) {
                LazyVStack(spacing: gridRowSpacing) {
                    ForEach(waterfallColumns.left, id: \.taskId) { item in
                        creationGridCell(item)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)

                LazyVStack(spacing: gridRowSpacing) {
                    ForEach(waterfallColumns.right, id: \.taskId) { item in
                        creationGridCell(item)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }

            if loadingMore {
                HStack {
                    Spacer()
                    ProgressView()
                        .tint(AppTheme.primary)
                    Spacer()
                }
                .padding(.vertical, 16)
            }
        }
    }

    @ViewBuilder
    private func creationGridCell(_ item: TaskListItem) -> some View {
        CreationGridCard(
            item: item,
            isRetrying: retryingTaskId == item.taskId,
            onSelect: {
                if shouldPresentGenerationSuccess(item) {
                    selectedSheet = .generationSuccess(item)
                } else {
                    selectedSheet = .detail(item)
                }
            },
            onRetry: { Task { await retryTask(item) } }
        )
        .onAppear {
            if item.taskId == displayedItems.last?.taskId {
                Task { await loadMoreIfNeeded() }
            }
        }
    }

    /// 下一项放入当前累计高度更短的一列；卡片高度与 `CreationGridCard` 的 `aspectRatio(3/4)` 一致时用相对高度比较即可。
    private static func splitWaterfallTwoColumns(_ items: [TaskListItem], rowSpacing: CGFloat) -> (left: [TaskListItem], right: [TaskListItem]) {
        var left: [TaskListItem] = []
        var right: [TaskListItem] = []
        let unitCellHeight: CGFloat = 4.0 / 3.0
        for item in items {
            let leftTotal = CGFloat(left.count) * unitCellHeight + CGFloat(max(0, left.count - 1)) * rowSpacing
            let rightTotal = CGFloat(right.count) * unitCellHeight + CGFloat(max(0, right.count - 1)) * rowSpacing
            if leftTotal <= rightTotal {
                left.append(item)
            } else {
                right.append(item)
            }
        }
        return (left, right)
    }

    private var filterTabStrip: some View {
        HStack(spacing: 8) {
            ForEach(CreationsFilterTab.allCases, id: \.rawValue) { tab in
                let on = filterTab == tab
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    filterTab = tab
                } label: {
                    BBBTrackedText.text(tab.title, size: 10, weight: .heavy, tracking: 1)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .foregroundStyle(on ? Color.white : AppTheme.onSurfaceVariant.opacity(0.65))
                        .background(
                            Capsule()
                                .fill(on ? AppTheme.primary.opacity(0.22) : Color.white.opacity(0.06))
                        )
                        .overlay(
                            Capsule()
                                .stroke(on ? AppTheme.primary.opacity(0.9) : Color.clear, lineWidth: 1.2)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var noticeBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.outlineVariant)
            BBBTrackedText.text(AppLanguageStore.localized("my.creations.banner.expire"), size: 9, weight: .semibold, tracking: 0.6, color: AppTheme.outlineVariant)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private func load(reset: Bool) async {
        if reset {
            await MainActor.run {
                loading = true
                errorMessage = nil
                pageNum = 1
            }
        }
        let result = await TaskAPI.getTaskList(
            pageNum: reset ? 1 : pageNum,
            pageSize: pageSize,
            status: filterTab.apiStatus
        )
        await MainActor.run {
            loading = false
            loadingMore = false
            switch result {
            case .success(let resp):
                if reset {
                    items = resp.list
                    pageNum = 1
                } else {
                    let existing = Set(items.map(\.taskId))
                    let merged = resp.list.filter { !existing.contains($0.taskId) }
                    items.append(contentsOf: merged)
                }
                total = resp.total
                errorMessage = nil
            case .failure(let err):
                errorMessage = err.userMessage
            }
        }
        await tryResolvePendingPushCreationOpenAfterListChange()
    }

    private func loadMoreIfNeeded() async {
        guard !loadingMore, !loading else { return }
        guard items.count < Int(total) else { return }
        await MainActor.run { loadingMore = true }
        let next = pageNum + 1
        let result = await TaskAPI.getTaskList(
            pageNum: next,
            pageSize: pageSize,
            status: filterTab.apiStatus
        )
        await MainActor.run {
            loadingMore = false
            if case .success(let resp) = result {
                pageNum = next
                let existing = Set(items.map(\.taskId))
                let merged = resp.list.filter { !existing.contains($0.taskId) }
                items.append(contentsOf: merged)
                total = resp.total
            }
        }
        await tryResolvePendingPushCreationOpenAfterListChange()
    }

    /// 远程推送携带的 `task_id`：在列表含该任务后打开成功页或详情；必要时翻页查找（有上限）。
    private func tryResolvePendingPushCreationOpenAfterListChange() async {
        let pending = await MainActor.run { tabRouter.pendingCreationOpen }
        guard let pending else { return }
        var extraPages = 0
        let maxExtra = 24
        while true {
            let found: TaskListItem? = await MainActor.run {
                items.first { $0.taskId == pending.taskId }
            }
            if let item = found {
                await MainActor.run {
                    tabRouter.consumePendingCreationOpen()
                    if pending.preferSuccessSheet, shouldPresentGenerationSuccess(item) {
                        selectedSheet = .generationSuccess(item)
                    } else {
                        selectedSheet = .detail(item)
                    }
                }
                return
            }
            let canMore: Bool = await MainActor.run {
                !loadingMore && !loading && items.count < Int(total) && total > 0
            }
            if canMore && extraPages < maxExtra {
                extraPages += 1
                await loadMoreIfNeeded()
            } else {
                await MainActor.run { tabRouter.consumePendingCreationOpen() }
                return
            }
        }
    }

    /// 已成功且可解析结果地址时进入「GENERATION SUCCESS」全屏页；其余（进行中/失败/无 URL）仍走通用详情。
    private func shouldPresentGenerationSuccess(_ item: TaskListItem) -> Bool {
        guard item.taskStatus == .success else { return false }
        let raw = item.resultUrl?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty, TaskResultMediaURL.resolve(raw) != nil else { return false }
        return true
    }

    private func retryTask(_ item: TaskListItem) async {
        let params = item.userParams?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !params.isEmpty else { return }
        let cost = Int(max(0, item.consumedGold ?? 0))
        let balance = await MainActor.run { wallet.coinBalance }
        if cost > 0, balance < cost {
            await MainActor.run { showRetryInsufficientCoins = true }
            return
        }
        await MainActor.run { retryingTaskId = item.taskId }
        let req = CreateTaskRequest(taskType: item.taskType, tid: item.tid, userParams: params)
        let result = await TaskAPI.createTask(req)
        await MainActor.run {
            retryingTaskId = nil
            if case .success = result {
                wallet.applyGenerationSpend(coins: cost)
                Task { await load(reset: true) }
            }
        }
    }
}

// MARK: - Grid Card

private struct CreationGridCard: View {
    let item: TaskListItem
    var isRetrying: Bool
    var onSelect: () -> Void
    var onRetry: () -> Void

    private let corner: CGFloat = 20

    var body: some View {
        ZStack {
            cardBackground

            switch displayKind {
            case .successNormal:
                successChrome(showSuccessPill: true, showExpiredOverlay: false)
            case .successExpired:
                successChrome(showSuccessPill: false, showExpiredOverlay: true)
            case .failed:
                failedLayer
            case .generating(let pct):
                generatingLayer(progress: pct)
            case .queuing(let estMin):
                queuingLayer(estimatedMinutes: estMin)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(3 / 4, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .stroke(AppTheme.outlineVariant.opacity(0.14), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }

    private enum DisplayKind {
        case successNormal
        case successExpired
        case failed
        case generating(progress: Int?)
        case queuing(estimatedMinutes: Int?)

        var isFailed: Bool {
            if case .failed = self { return true }
            return false
        }
    }

    private var displayKind: DisplayKind {
        switch item.taskStatus {
        case .failed:
            return .failed
        case .pending:
            let mins: Int? = item.waitSeconds.map { max(1, Int(ceil(Double($0) / 60.0))) }
            return .queuing(estimatedMinutes: mins)
        case .running:
            let p = progressPercent
            return .generating(progress: p)
        case .success:
            return item.isExpired ? .successExpired : .successNormal
        }
    }

    private var progressPercent: Int? {
        guard let t = item.totalStage, t > 0, let c = item.currentStage else { return nil }
        return min(99, max(1, Int((Double(c) / Double(t)) * 100)))
    }

    @ViewBuilder
    private var cardBackground: some View {
        switch displayKind {
        case .successNormal, .successExpired:
            // 与生成中/失败层一致占满单元格，避免 ZStack 仅由子视图内禀高度撑开时在双列流式布局里被垂直居中
            Rectangle()
                .fill(Color.clear)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            AppTheme.surfaceContainerHighest
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .generating, .queuing:
            ZStack {
                if let u = inputPreviewURL {
                    HomeCachedImage(url: u, priority: .utility)
                        .blur(radius: 14)
                } else {
                    LinearGradient(
                        colors: [AppTheme.surfaceContainerHighest, AppTheme.surfaceContainer],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
    }

    @ViewBuilder
    private var resultThumbnail: some View {
        if let urlStr = item.resultUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
           !urlStr.isEmpty,
           let url = TaskResultMediaURL.resolve(urlStr) {
            if Self.isVideoResultURL(resolved: url, rawFallback: urlStr) {
                CreationResultVideoPosterView(url: url)
            } else {
                HomeCachedImage(url: url, priority: .utility)
            }
        } else {
            AppTheme.surfaceContainerHighest
        }
    }

    /// 与详情页、成功页一致：按扩展名判断视频；`URL.pathExtension` 可处理带 query 的地址。
    private static func isVideoResultURL(resolved: URL, rawFallback: String) -> Bool {
        let ext = resolved.pathExtension.lowercased()
        if ext == "mp4" || ext == "mov" || ext == "m4v" { return true }
        let lower = rawFallback.lowercased()
        return lower.hasSuffix(".mp4") || lower.hasSuffix(".mov") || lower.hasSuffix(".m4v")
    }

    @ViewBuilder
    private func successChrome(showSuccessPill: Bool, showExpiredOverlay: Bool) -> some View {
        ZStack {
            resultThumbnail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .saturation(showExpiredOverlay ? 0.28 : 1)
                .brightness(showExpiredOverlay ? -0.12 : 0)

            if showExpiredOverlay {
                Color.black.opacity(0.42)
            }

            VStack {
                HStack(alignment: .top) {
                    if showSuccessPill {
                        successPill
                    }
                    Spacer(minLength: 0)
                    mediaTypeCornerBadge
                }
                .padding(10)
                Spacer()
                if showExpiredOverlay {
                    BBBTrackedText.text(AppLanguageStore.localized("my.creations.expired"), size: 12, weight: .heavy, tracking: 1.2, color: .white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.55))
                        .clipShape(Capsule())
                }
                Spacer()
            }
        }
    }

    private var successPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.green.opacity(0.95))
                .frame(width: 6, height: 6)
            BBBTrackedText.text(AppLanguageStore.localized("my.creations.success_pill"), size: 9, weight: .heavy, tracking: 0.8, color: .white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.black.opacity(0.72))
        .clipShape(Capsule())
    }

    @ViewBuilder
    private var mediaTypeCornerBadge: some View {
        if let raw = item.resultUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty,
           let resolved = TaskResultMediaURL.resolve(raw) {
            let isVideo = Self.isVideoResultURL(resolved: resolved, rawFallback: raw)
            HStack(spacing: 4) {
                Image(systemName: isVideo ? "play.rectangle.fill" : "photo.fill")
                    .font(.system(size: 10))
                Text(AppLanguageStore.localized(isVideo ? "kind.video" : "kind.image"))
                    .font(.system(size: 9, weight: .heavy))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.72))
            .clipShape(Capsule())
        }
    }

    private var failedLayer: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.18))
                    .frame(width: 52, height: 52)
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Color.red.opacity(0.95))
            }
            Text(AppLanguageStore.localized("my.creations.failure"))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
            BBBTrackedText.text(AppLanguageStore.localized("my.creations.refunded"), size: 9, weight: .heavy, tracking: 1, color: AppTheme.outlineVariant)
            Spacer(minLength: 0)
            Button(action: {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onRetry()
            }) {
                Group {
                    if isRetrying {
                        ProgressView()
                            .tint(AppTheme.primary)
                            .scaleEffect(0.9)
                    } else {
                        BBBTrackedText.text(AppLanguageStore.localized("my.creations.tap_retry"), size: 10, weight: .heavy, tracking: 0.8, color: AppTheme.primary)
                    }
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 8)
    }

    private func generatingLayer(progress: Int?) -> some View {
        ZStack {
            LinearGradient(
                colors: [Color.black.opacity(0.5), Color.black.opacity(0.62)],
                startPoint: .top,
                endPoint: .bottom
            )
            VStack(spacing: 5) {
                ZStack {
                    if let p = progress {
                        CreationCircularProgress(progress: CGFloat(p) / 100)
                            .frame(width: 50, height: 50)
                        Text(String(format: AppLanguageStore.localized("my.creations.percent_format"), p))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .minimumScaleFactor(0.65)
                            .lineLimit(1)
                    } else {
                        ProgressView()
                            .scaleEffect(1.05)
                            .tint(.white)
                    }
                }
                .frame(width: 52, height: 52)
                Text(AppLanguageStore.localized("my.creations.generating_label"))
                    .font(.system(size: 8, weight: .heavy))
                    .tracking(1.1)
                    .foregroundStyle(Color.white.opacity(0.92))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 6)
        }
    }

    private func queuingLayer(estimatedMinutes: Int?) -> some View {
        ZStack {
            LinearGradient(
                colors: [Color.black.opacity(0.52), Color.black.opacity(0.65)],
                startPoint: .top,
                endPoint: .bottom
            )
            VStack(spacing: 5) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Color.white.opacity(0.95))
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                Text(AppLanguageStore.localized("my.creations.queuing"))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                if let m = estimatedMinutes {
                    Text(String(format: AppLanguageStore.localized("my.creations.est_mins_format"), m))
                        .font(.system(size: 8, weight: .heavy))
                        .tracking(0.6)
                        .foregroundStyle(Color.white.opacity(0.78))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 6)
        }
    }

    private var inputPreviewURL: URL? {
        guard let raw = item.userParams?.trimmingCharacters(in: .whitespacesAndNewlines),
              let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let paths: [String]? =
            (obj["input_images"] as? [String])
            ?? (obj["inputImages"] as? [String])
        guard let first = paths?.first?.trimmingCharacters(in: .whitespacesAndNewlines), !first.isEmpty else {
            return nil
        }
        return TaskResultMediaURL.resolve(first)
    }
}

/// 成功态视频结果：首帧缩略图（`VideoCacheManager` 与首页瀑布流一致）；失败时回退胶片图标。
private struct CreationResultVideoPosterView: View {
    let url: URL

    @State private var poster: UIImage?
    @State private var didFinishLoading = false

    var body: some View {
        ZStack {
            AppTheme.surfaceContainerHighest
            if let poster {
                Image(uiImage: poster)
                    .resizable()
                    .scaledToFill()
            } else if !didFinishLoading {
                ProgressView()
                    .tint(AppTheme.primary)
            } else {
                Image(systemName: "film.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(AppTheme.primary.opacity(0.9))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task(id: url.absoluteString) {
            let img = await VideoCacheManager.shared.thumbnailUIImage(forVideoURLString: url.absoluteString)
            await MainActor.run {
                poster = img
                didFinishLoading = true
            }
        }
    }
}

// MARK: - Circular progress

private struct CreationCircularProgress: View {
    var progress: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: 4)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(AppTheme.primary, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - 创作详情 · 进行中（与首页排队页视觉一致）

private struct CreationsDetailQueuingRing: View {
    var progress: CGFloat
    var accent: Color

    private var percentText: String {
        let p = max(0, min(100, Int((progress * 100).rounded())))
        return "\(p)%"
    }

    private let ringSize: CGFloat = 112
    private let lineWidth: CGFloat = 7

    var body: some View {
        ZStack {
            Circle()
                .stroke(accent.opacity(0.12), lineWidth: lineWidth + 4)
                .frame(width: ringSize + 6, height: ringSize + 6)
                .blur(radius: 3)

            Circle()
                .stroke(Color.white.opacity(0.1), lineWidth: lineWidth)
                .frame(width: ringSize, height: ringSize)

            Circle()
                .trim(from: 0, to: CGFloat(min(1, max(0, progress))))
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [accent, accent.opacity(0.65), accent]),
                        center: .center,
                        angle: .degrees(-90)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .frame(width: ringSize, height: ringSize)
                .rotationEffect(.degrees(-90))
                .shadow(color: accent.opacity(0.4), radius: 8, y: 0)
                .animation(.easeOut(duration: 0.28), value: progress)

            Text(percentText)
                .font(.system(size: 30, weight: .heavy))
                .foregroundStyle(accent)
                .monospacedDigit()
                .animation(.easeOut(duration: 0.2), value: percentText)
        }
        .frame(width: ringSize + 24, height: ringSize + 24)
        .padding(.vertical, 8)
    }
}

private struct CreationsInProgressHeroView: View {
    let item: TaskListItem
    let templateURL: URL?

    private static let pageBackground = Color(red: 11 / 255, green: 11 / 255, blue: 15 / 255)
    private static let accentLavender = Color(red: 192 / 255, green: 159 / 255, blue: 248 / 255)

    private var inputURL: URL? { item.creationInputImageURL }

    private var showsRing: Bool { item.taskStatus == .running }

    private var ringProgress: CGFloat { item.creationStageProgress01 }

    private var mainTitle: String {
        switch item.taskStatus {
        case .pending:
            return AppLanguageStore.localized("home.generating.queuing.nav_title")
        case .running:
            return AppLanguageStore.localized("home.generating.queuing.hero_generating")
        default:
            return AppLanguageStore.localized("home.generating.title")
        }
    }

    private var subtitle: String? {
        switch item.taskStatus {
        case .pending:
            if let w = item.waitSeconds, w > 0 {
                let mins = max(1, Int(ceil(Double(w) / 60.0)))
                let est = "~\(mins) min"
                return String(format: AppLanguageStore.localized("home.generating.pending_wait"), est)
            }
            return AppLanguageStore.localized("home.generating.pending")
        case .running:
            return AppLanguageStore.localized("home.generating.queuing.detail_running")
        default:
            return nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            dualCardRow
                .padding(.horizontal, 16)
                .padding(.top, 4)

            Spacer(minLength: 10)

            Group {
                if showsRing {
                    CreationsDetailQueuingRing(progress: ringProgress, accent: Self.accentLavender)
                } else {
                    queuingSymbolBlock
                }
            }
            .padding(.bottom, 4)

            Text(mainTitle)
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(AppTheme.onSurface)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            if let sub = subtitle {
                Text(sub)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppTheme.onSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }
        }
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(Self.pageBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var queuingSymbolBlock: some View {
        ZStack {
            Circle()
                .strokeBorder(Self.accentLavender.opacity(0.35), lineWidth: 1)
                .frame(width: 100, height: 100)
            Circle()
                .strokeBorder(Self.accentLavender.opacity(0.55), lineWidth: 1)
                .frame(width: 86, height: 86)
            Circle()
                .fill(Color(red: 24 / 255, green: 22 / 255, blue: 38 / 255))
                .frame(width: 78, height: 78)
            Image(systemName: "hourglass")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Self.accentLavender)
        }
        .padding(.vertical, 8)
    }

    /// 与中间交换按钮宽度共同参与均分；`minWidth: 0` 避免大图固有宽度挤占另一列（部分机型左右不等宽）
    private var dualCardRow: some View {
        HStack(alignment: .center, spacing: 0) {
            sourceCard
                .frame(minWidth: 0, maxWidth: .infinity)
                .layoutPriority(1)
            swapPill
            templateCard
                .frame(minWidth: 0, maxWidth: .infinity)
                .layoutPriority(1)
        }
    }

    private var sourceCard: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let inputURL {
                    HomeCachedImage(url: inputURL, priority: .userInitiated, aspectFit: false)
                } else {
                    AppTheme.surfaceContainerHighest
                        .overlay(
                            Image(systemName: "person.crop.rectangle")
                                .font(.system(size: 36))
                                .foregroundStyle(AppTheme.onSurfaceVariant.opacity(0.35))
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            tagChip(AppLanguageStore.localized("home.generating.queuing.source_tag"), fill: Color.black.opacity(0.45), foreground: Self.accentLavender)
                .padding(8)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var templateCard: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let templateURL {
                    HomeCachedImage(url: templateURL, priority: .userInitiated, aspectFit: false)
                } else {
                    AppTheme.surfaceContainer
                        .overlay(
                            ProgressView()
                                .tint(Self.accentLavender)
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            tagChip(AppLanguageStore.localized("home.generating.queuing.template_tag"), fill: Color.black.opacity(0.45), foreground: AppTheme.secondary)
                .padding(8)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var swapPill: some View {
        ZStack {
            Circle()
                .fill(Color(red: 40 / 255, green: 28 / 255, blue: 62 / 255))
                .frame(width: 40, height: 40)
                .overlay(
                    Circle()
                        .stroke(Self.accentLavender.opacity(0.55), lineWidth: 1)
                )
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 44)
    }

    private func tagChip(_ text: String, fill: Color, foreground: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy))
            .tracking(0.4)
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

// MARK: - Detail

private enum CreationSheetRoute: Identifiable, Hashable {
    case generationSuccess(TaskListItem)
    case detail(TaskListItem)

    var id: String {
        switch self {
        case .generationSuccess(let item):
            return "s:\(item.taskId)"
        case .detail(let item):
            return "d:\(item.taskId)"
        }
    }
}

struct CreationDetailView: View {
    let item: TaskListItem

    @State private var templatePreviewURL: URL?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: item.taskStatus == .pending || item.taskStatus == .running ? 12 : 18) {
                if item.taskStatus == .pending || item.taskStatus == .running {
                    CreationsInProgressHeroView(
                        item: item,
                        templateURL: templatePreviewURL
                    )
                }

                detailMeta

                if item.taskStatus == .success,
                   let raw = item.resultUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !raw.isEmpty,
                   let url = TaskResultMediaURL.resolve(raw) {
                    resultView(url: url, raw: raw)
                } else if item.taskStatus == .failed {
                    Text(AppLanguageStore.localized("my.creations.error.detail"))
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.onSurfaceVariant)
                }
            }
            .padding(20)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle(AppLanguageStore.localized("my.creations.detail.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: item.taskId) {
            await loadTemplatePreviewForDetail()
        }
    }

    /// 拉取模板封面供 SOURCE/TEMPLATE 卡片右侧展示
    private func loadTemplatePreviewForDetail() async {
        let tid = item.tid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tid.isEmpty else { return }
        switch item.taskType {
        case 1:
            let r = await TemplateRepository.shared.getImageTemplateDetail(tid: tid)
            if case .success(let t) = r {
                let feed = HomeFeedItem(imageTemplate: t)
                let u = feed.immersiveImageURLs.first ?? feed.imageURL
                await MainActor.run { templatePreviewURL = u }
            }
        case 2:
            let r = await TemplateRepository.shared.getDancingTemplateDetail(tid: tid)
            if case .success(let t) = r {
                let feed = HomeFeedItem(dancingTemplate: t)
                let u = feed.immersiveImageURLs.first ?? feed.imageURL
                await MainActor.run { templatePreviewURL = u }
            }
        case 3:
            let r = await TemplateRepository.shared.getVideoTemplateDetail(tid: tid)
            if case .success(let t) = r {
                let feed = HomeFeedItem(videoTemplate: t)
                let u = feed.immersiveImageURLs.first ?? feed.imageURL
                await MainActor.run { templatePreviewURL = u }
            }
        default:
            break
        }
    }

    private var detailMeta: some View {
        VStack(alignment: .leading, spacing: 8) {
            CreationMetaRow(AppLanguageStore.localized("creation.meta.type"), value: item.taskTypeDisplayLabel)
            CreationMetaRow(AppLanguageStore.localized("creation.meta.status"), value: item.taskStatusDisplay)
            CreationMetaRow(AppLanguageStore.localized("creation.meta.created"), value: item.createDateFormatted)
            if !item.tid.isEmpty {
                CreationMetaRow(AppLanguageStore.localized("creation.meta.template_id"), value: item.tid)
            }
        }
        .font(.subheadline)
        .foregroundStyle(AppTheme.onSurface)
    }

    @ViewBuilder
    private func resultView(url: URL, raw: String) -> some View {
        let lower = raw.lowercased()
        if lower.hasSuffix(".mp4") || lower.hasSuffix(".mov") || lower.hasSuffix(".m4v") {
            VideoPlayer(player: AVPlayer(url: url))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 220)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            HomeCachedImage(url: url, priority: .userInitiated)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 240)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

// MARK: - TaskListItem + display

private enum TaskResultMediaURL {
    static func resolve(_ path: String) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return URL(string: trimmed)
        }
        let base = ResBaseURL.effective
        if trimmed.hasPrefix("/") {
            return URL(string: trimmed, relativeTo: URL(string: base))?.absoluteURL
        }
        let sep = base.hasSuffix("/") ? "" : "/"
        return URL(string: base + sep + trimmed)
    }
}

private extension TaskListItem {
    /// 与网格卡片一致：从 `userParams` 解析用户上传图 URL
    var creationInputImageURL: URL? {
        guard let raw = userParams?.trimmingCharacters(in: .whitespacesAndNewlines),
              let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let paths: [String]? =
            (obj["input_images"] as? [String])
            ?? (obj["inputImages"] as? [String])
        guard let first = paths?.first?.trimmingCharacters(in: .whitespacesAndNewlines), !first.isEmpty else {
            return nil
        }
        return TaskResultMediaURL.resolve(first)
    }

    /// 生成中环形进度（与列表卡片 `totalStage` / `currentStage` 一致）
    var creationStageProgress01: CGFloat {
        guard taskStatus == .running,
              let t = totalStage, t > 0,
              let c = currentStage else { return 0 }
        return CGFloat(min(1, max(0, Double(c) / Double(t))))
    }

    var taskTypeDisplayLabel: String {
        switch taskType {
        case 1: return "Image"
        case 2: return "Dance"
        case 3: return "Video"
        default: return "Task"
        }
    }

    var taskStatusDisplay: String {
        switch taskStatus {
        case .pending: return "Pending"
        case .running: return "Processing"
        case .success: return "Done"
        case .failed: return "Failed"
        }
    }

    var createDateFormatted: String {
        guard let ts = Int64(createTs.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return createTs
        }
        let interval: TimeInterval = ts > 1_000_000_000_000 ? TimeInterval(ts) / 1000 : TimeInterval(ts)
        let date = Date(timeIntervalSince1970: interval)
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.locale = Locale.current
        return f.string(from: date)
    }
}

private struct CreationMetaRow: View {
    let title: String
    let value: String

    init(_ title: String, value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(AppTheme.onSurfaceVariant)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
    }
}

#Preview {
    NavigationView {
        MyCreationsView()
    }
    .navigationViewStyle(StackNavigationViewStyle())
    .environmentObject(UserWalletStore())
    .environmentObject(AppTabRouter())
    .preferredColorScheme(.dark)
}
