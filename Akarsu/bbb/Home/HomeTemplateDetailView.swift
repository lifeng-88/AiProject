//
//  HomeTemplateDetailView.swift
//  bbb
//
//  瀑布流点击 cell 进入：拉取详情。T1 多图时主图用 `ImmersiveFeedMediaBackdrop` 双图来回扫荡（与瀑布流一致），**不传** `transAnimationCarouselURLs`，避免误走 trans 顺序轮播。
//  T2·T3 预览主图见 `HomeTemplateDetailT2T3PreviewHero`：先展示接口 `transAnimation` 首段（静图或视频解码首帧），成片预加载完成后切换为静音循环成片。
//

import Photos
import SwiftUI
import UIKit

struct HomeTemplateDetailView: View {
    let gridItem: HomeGridCardItem
    /// 已选好人像图后进入全屏生成流程（含上传）
    var onUseTemplate: (HomeFeedItem, UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var wallet: UserWalletStore
    @EnvironmentObject private var tabRouter: AppTabRouter
    @EnvironmentObject private var versionConfig: VersionConfigStore
    @EnvironmentObject private var appLanguage: AppLanguageStore

    @AppStorage("homeUploadTipsSuppressed") private var uploadTipsSuppressed = false
    @State private var phase: LoadPhase = .loading
    @State private var likedTemplateKeys: Set<String> = []
    @State private var pickedImage: UIImage?
    @State private var showUploadTips = false
    @State private var dontShowAgainTips = false
    @State private var showLegacyPhotoPicker = false
    @State private var showPhotoPermissionAlert = false
    /// 金币不足时全屏充值套餐层（与 `HomeTemplateGenerationSheet` 一致）
    @State private var showRechargeUpsell = false

    private enum LoadPhase {
        case loading
        case failed(String)
        case loaded(LoadedDetail)
    }

    private enum LoadedDetail {
        case t1(ImageTemplate)
        case t2(DancingTemplate)
        case t3(VideoTemplate)
    }

    private let cardCorner: CGFloat = 14

    private var isLocked: Bool {
        if case .locked = gridItem.bottomLeft { return true }
        return false
    }

    private var likeKey: String { gridItem.likeStateKey }
    private var isLiked: Bool { likedTemplateKeys.contains(likeKey) }

    /// 导航栏标题「预览」
    private var previewPrincipalTitle: AttributedString {
        let m = NSMutableAttributedString(string: AppLanguageStore.localized("home.template.detail.preview_title"))
        let range = NSRange(location: 0, length: m.length)
        m.addAttribute(.kern, value: 1.2, range: range)
        m.addAttribute(.font, value: UIFont.systemFont(ofSize: 16, weight: .heavy), range: range)
        m.addAttribute(.foregroundColor, value: UIColor(AppTheme.primary), range: range)
        return AttributedString(m)
    }

    private let smallPickSlotWidth: CGFloat = 92
    private var smallPickSlotHeight: CGFloat { smallPickSlotWidth * 16.0 / 9.0 }

    /// 与瀑布流 cell 同源：`loading` / `failed` 用列表带入的 `gridItem`；`loaded` 用详情构建的 `HomeFeedItem` 再合并角标。
    private var heroGridCardItem: HomeGridCardItem {
        switch phase {
        case .loaded(let detail):
            return feedItem(from: detail).gridCardItemMatchingList(chrome: gridItem)
        case .loading, .failed:
            return gridItem
        }
    }

    private var detailHeroPhaseLoaded: Bool {
        if case .loaded = phase { return true }
        return false
    }

    private var heroMediaIdentityKey: String {
        switch phase {
        case .loaded(let detail):
            let feed = feedItem(from: detail)
            return "loaded-\(feed.id)-\(feed.templateKind.rawValue)"
        case .loading:
            return "loading-\(gridItem.id)"
        case .failed:
            return "failed-\(gridItem.id)"
        }
    }

    @ViewBuilder
    private func heroPrimaryMedia(width w: CGFloat, height h: CGFloat) -> some View {
        switch phase {
        case .loaded(let detail):
            let feed = feedItem(from: detail)
            if feed.templateKind == .t1, feed.slideshowURLs.count >= 2 {
                /// `transAnimationCarouselURLs` 非空时会优先走 `HomeImmersiveTransAnimationCarouselBackdrop`（多段轮播）。T1 预览只要与瀑布流一致的**双图扫荡**，故传空，由 `imageURLs`≥2 走 `ImmersiveFeedScanCompareBackdrop`。
                ImmersiveFeedMediaBackdrop(
                    itemId: feed.id,
                    playbackVideoURL: nil,
                    imageURLs: feed.immersiveImageURLs,
                    interval: feed.slideshowInterval,
                    width: w,
                    height: h,
                    isSwitchingActive: true,
                    stoppedPosterVideoURL: nil,
                    aspectFit: true,
                    transAnimationCarouselURLs: []
                )
            } else if feed.templateKind == .t2 || feed.templateKind == .t3 {
                HomeTemplateDetailT2T3PreviewHero(
                    itemId: feed.id,
                    placeholderMediaURL: feed.templateDetailPreviewPlaceholderURL,
                    playbackVideoURL: feed.immersivePrimaryLoopVideoURL ?? feed.playbackVideoURL,
                    fallbackImageURL: feed.imageURL ?? gridItem.imageURL,
                    width: w,
                    height: h,
                    aspectFit: true
                )
            } else {
                HomeGridCardSharedMediaStack(
                    item: heroGridCardItem,
                    isPlaybackActive: true,
                    onPlaybackFinished: nil,
                    fixedWidthHeight: CGSize(width: w, height: h),
                    cellAspectRatio: gridItem.aspectRatio,
                    showsBottomLeftBadge: true
                )
            }
        case .loading, .failed:
            /// T2/T3：先展示 trans 首帧占位，等详情加载后由 `HomeTemplateDetailT2T3PreviewHero` 预加载完成再叠循环成片；勿在 loading 时直接播网格视频。
            HomeGridCardSharedMediaStack(
                item: gridItem,
                isPlaybackActive: gridItem.templateKind != .t2 && gridItem.templateKind != .t3,
                onPlaybackFinished: nil,
                fixedWidthHeight: CGSize(width: w, height: h),
                cellAspectRatio: gridItem.aspectRatio,
                showsBottomLeftBadge: true
            )
        }
    }

    var body: some View {
        let _ = appLanguage.preference
        ZStack {
            VStack(spacing: 0) {
                heroMatchingGridCard
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)

                templateBottomBar
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity)
                    .background(AppTheme.background)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.background)

            if showUploadTips {
                HomeUploadTipsOverlay(
                    dontShowAgain: $dontShowAgainTips,
                    onClose: {
                        withAnimation(.easeOut(duration: 0.22)) { showUploadTips = false }
                    },
                    onConfirm: {
                        if dontShowAgainTips { uploadTipsSuppressed = true }
                        withAnimation(.easeOut(duration: 0.22)) { showUploadTips = false }
                        DispatchQueue.main.async { presentPhotoPickerIfAuthorized() }
                    }
                )
                .transition(.opacity)
                .zIndex(4)
            }

            LegacyImagePicker(image: $pickedImage, isPresented: $showLegacyPhotoPicker)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
                .zIndex(-1)

            if showRechargeUpsell {
                HomeGenerationRechargeUpsellView(
                    onClose: { showRechargeUpsell = false },
                    onExploreFullRecharge: {
                        showRechargeUpsell = false
                        tabRouter.select(.recharge)
                    }
                )
                .environmentObject(wallet)
                .environmentObject(auth)
                .environmentObject(versionConfig)
                .environmentObject(tabRouter)
                .environmentObject(appLanguage)
                .transition(.opacity)
                .zIndex(3)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        /// 首页根视图隐藏导航栏后，详情页需显式恢复，否则可能继承隐藏状态
        .bbbToolbarVisibleNavigationBar()
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                BBBNavigationBackButton {
                    dismiss()
                }
            }
            ToolbarItem(placement: .principal) {
                Text(previewPrincipalTitle)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(AppTheme.primary)
            }
        }
        /// 顶栏：仅金币；收藏已叠在大图右上角
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    tabRouter.select(.recharge)
                } label: {
                    HStack(spacing: 4) {
                        AppCoinIcon(size: 18)
                        Text(wallet.formattedCoinBalance)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(AppTheme.onSurface)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .bbbNavigationBarBackground(AppTheme.background)
        .task {
            await loadDetail()
        }
        .onAppear {
            likedTemplateKeys = LocalFavoriteTemplateStore.load(userId: auth.userId)
        }
        .onChange(of: auth.userId) { _ in
            likedTemplateKeys = LocalFavoriteTemplateStore.load(userId: auth.userId)
        }
        .onReceive(NotificationCenter.default.publisher(for: .localFavoriteTemplateStoreDidChange)) { _ in
            likedTemplateKeys = LocalFavoriteTemplateStore.load(userId: auth.userId)
        }
        .alert(AppLanguageStore.localized("home.template.photo_permission.title"), isPresented: $showPhotoPermissionAlert) {
            Button(AppLanguageStore.localized("common.cancel"), role: .cancel) {}
            Button(AppLanguageStore.localized("home.template.photo_permission.open_settings")) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        } message: {
            Text(AppLanguageStore.localized("home.template.photo_permission.message"))
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.88), value: showUploadTips)
        .bbbRefreshOnAppLanguage()
    }

    private var smallUserPhotoPickSlot: some View {
        Button(action: { requestPhotoPickerAfterTipsIfNeeded() }) {
            ZStack(alignment: .topLeading) {
                Group {
                    if let pickedImage {
                        Image(uiImage: pickedImage)
                            .resizable()
                            .scaledToFill()
                    } else {
                        ZStack {
                            AppTheme.surfaceContainerHighest
                            Image(systemName: "person.crop.rectangle.badge.plus")
                                .font(.system(size: 26))
                                .foregroundStyle(AppTheme.onSurfaceVariant.opacity(0.9))
                        }
                    }
                }
                .frame(width: smallPickSlotWidth, height: smallPickSlotHeight)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppTheme.outlineVariant.opacity(0.5), lineWidth: 1.5)
                )

                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(AppTheme.primary)
                            .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
                    )
                    .offset(x: -10, y: -10)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppLanguageStore.localized("home.template.sheet.pick_photo"))
        .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
    }

    private func requestPhotoPickerAfterTipsIfNeeded() {
        if uploadTipsSuppressed {
            presentPhotoPickerIfAuthorized()
        } else {
            dontShowAgainTips = false
            showUploadTips = true
        }
    }

    private func presentPhotoPickerIfAuthorized() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            showLegacyPhotoPicker = true
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                DispatchQueue.main.async {
                    switch newStatus {
                    case .authorized, .limited:
                        showLegacyPhotoPicker = true
                    case .denied, .restricted:
                        showPhotoPermissionAlert = true
                    default:
                        break
                    }
                }
            }
        case .denied, .restricted:
            showPhotoPermissionAlert = true
        @unknown default:
            showLegacyPhotoPicker = true
        }
    }

    // MARK: - 主图区（T1 多图：`ImmersiveFeedMediaBackdrop` 双图扫荡；T1 单图 / 加载失败：同瀑布流 `HomeGridCardSharedMediaStack`；T2·T3：`ImmersiveFeedMediaBackdrop` trans 轮播）

    private var heroMatchingGridCard: some View {
        GeometryReader { outer in
            let w = outer.size.width
            let h = outer.size.height
            ZStack {
                heroPrimaryMedia(width: w, height: h)
                    .animation(.easeInOut(duration: 0.45), value: detailHeroPhaseLoaded)
                    .id(heroMediaIdentityKey)
                /// 列表 cell 心形在右下；此处与人像选区同侧，改为右上避免重叠。
                .overlay(alignment: .topTrailing) {
                    detailHeartButton
                        .padding(10)
                }

                if case .loaded = phase, !isLocked {
                    VStack {
                        Spacer(minLength: 0)
                        HStack {
                            Spacer(minLength: 0)
                            smallUserPhotoPickSlot
                                .padding(10)
                        }
                    }
                }
            }
            .frame(width: w, height: h)
        }
        /// 避免 `GeometryReader` 在栈布局首帧高度为 0，导致主图区不可见。
        .aspectRatio(gridItem.aspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cardCorner, style: .continuous))
        .background(AppTheme.surfaceContainer)
        .clipShape(RoundedRectangle(cornerRadius: cardCorner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cardCorner, style: .continuous)
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

    private var formattedCoinDisplay: String {
        let n = displayCoinValue
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private var displayCoinValue: Int {
        if let c = resolvedCoinsFromDetail { return c }
        if case .coins(let n) = gridItem.bottomLeft { return n }
        return 0
    }

    private var resolvedCoinsFromDetail: Int? {
        switch phase {
        case .loaded(let d):
            switch d {
            case .t1(let t): return Self.parseGold(t.consumedGold)
            case .t2(let t): return Self.parseGold(t.consumedGold)
            case .t3(let t): return Self.parseGold(t.consumedGold)
            }
        case .loading, .failed:
            return nil
        }
    }

    private var detailHeartButton: some View {
        Button(action: { toggleLike() }) {
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
    }

    private func toggleLike() {
        let willLike = !likedTemplateKeys.contains(likeKey)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        if willLike {
            likedTemplateKeys.insert(likeKey)
        } else {
            likedTemplateKeys.remove(likeKey)
        }
        LocalFavoriteTemplateStore.save(likedTemplateKeys, userId: auth.userId)
    }

    // MARK: - 文案与 CTA

    @ViewBuilder
    private var templateBottomBar: some View {
        switch phase {
        case .loading:
            HStack {
                Spacer()
                ProgressView()
                    .tint(AppTheme.primary)
                Spacer()
            }
            .padding(.vertical, 8)
        case .failed(let msg):
            Text(msg)
                .font(.footnote)
                .foregroundStyle(Color.red.opacity(0.9))
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(AppLanguageStore.localized("common.retry")) {
                Task { await loadDetail() }
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.primary)
        case .loaded(let detail):
            if isLocked {
                Label(AppLanguageStore.localized("home.template.detail.unavailable"), systemImage: "lock.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.onSurfaceVariant)
            } else {
                Button(action: {
                    guard let img = pickedImage else { return }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    let cost = displayCoinValue
                    if cost > 0, wallet.coinBalance < cost {
                        showRechargeUpsell = true
                        return
                    }
                    onUseTemplate(feedItem(from: detail), img)
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 18, weight: .semibold))
                        Text(AppLanguageStore.localized("home.template.detail.generate"))
                            .font(.system(size: 17, weight: .heavy))
                        Rectangle()
                            .fill(Color.white.opacity(0.28))
                            .frame(width: 1, height: 18)
                        HStack(spacing: 5) {
                            AppCoinIcon(size: 18)
                            Text("\(displayCoinValue)")
                                .font(.system(size: 16, weight: .bold).monospacedDigit())
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .foregroundStyle(.white)
                    .background(
                        Group {
                            if pickedImage == nil {
                                AppTheme.surfaceContainerHighest
                            } else {
                                AppTheme.premiumButtonGradient
                            }
                        }
                    )
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(pickedImage == nil)
            }
        }
    }

    private func feedItem(from detail: LoadedDetail) -> HomeFeedItem {
        switch detail {
        case .t1(let t): return HomeFeedItem(imageTemplate: t)
        case .t2(let t): return HomeFeedItem(dancingTemplate: t)
        case .t3(let t): return HomeFeedItem(videoTemplate: t)
        }
    }

    private func loadDetail() async {
        await MainActor.run { phase = .loading }
        let result: Result<LoadedDetail, AppError>
        switch gridItem.templateKind {
        case .t1:
            let r = await TemplateRepository.shared.getImageTemplateDetail(tid: gridItem.id)
            result = r.map { .t1($0) }
        case .t2:
            let r = await TemplateRepository.shared.getDancingTemplateDetail(tid: gridItem.id)
            result = r.map { .t2($0) }
        case .t3:
            let r = await TemplateRepository.shared.getVideoTemplateDetail(tid: gridItem.id)
            result = r.map { .t3($0) }
        }
        await MainActor.run {
            switch result {
            case .success(let d):
                phase = .loaded(d)
            case .failure(let err):
                phase = .failed(err.userMessage)
            }
        }
    }

    private static func parseGold(_ s: String) -> Int {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if let v = Int(t) { return v }
        if let d = Double(t) { return Int(d.rounded()) }
        return 0
    }
}

// MARK: - T2/T3 预览主图：trans 首段 → 成片循环

/// 先展示 `transAnimation` **首段**占位（图片用 `HomeCachedImage`；视频段用解码首帧）；`immersivePrimaryLoopVideoURL` 预加载完成后再叠 `HomeImmersiveVideoBackdrop` 静音循环（与沉浸式列表同源）。
private struct HomeTemplateDetailT2T3PreviewHero: View {
    let itemId: String
    /// 优先接口 `transAnimation` 字段首段，见 `HomeFeedItem.templateDetailPreviewPlaceholderURL`
    let placeholderMediaURL: URL?
    let playbackVideoURL: URL?
    let fallbackImageURL: URL?
    let width: CGFloat
    let height: CGFloat
    var aspectFit: Bool = true

    @State private var showLoopingPlayback = false

    var body: some View {
        ZStack {
            Color.black
            if showLoopingPlayback, let pv = playbackVideoURL {
                HomeImmersiveVideoBackdrop(remoteURL: pv, width: width, height: height)
                    .id("\(itemId)-detail-loop-\(pv.absoluteString)")
                    .transition(.opacity)
            } else {
                firstTransPlaceholder
                    .transition(.opacity)
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .animation(.easeInOut(duration: 0.38), value: showLoopingPlayback)
        .task(id: "\(itemId)-\(playbackVideoURL?.absoluteString ?? "nil")") {
            await MainActor.run { showLoopingPlayback = false }
            guard let pv = playbackVideoURL else { return }
            let s = pv.absoluteString
            await VideoCacheManager.shared.preloadVideo(videoURL: s, priority: .userInitiated, isCurrentDisplay: true)
            await MainActor.run {
                showLoopingPlayback = true
            }
        }
    }

    @ViewBuilder
    private var firstTransPlaceholder: some View {
        if let u = placeholderMediaURL {
            if HomeImmersiveMediaURL.isVideo(u) {
                HomeGridTransAnimationVideoPosterView(videoURL: u)
                    .frame(width: width, height: height)
                    .clipped()
            } else {
                HomeCachedImage(
                    url: u,
                    priority: .userInitiated,
                    aspectFit: aspectFit,
                    showsLoadingIndicator: true
                )
                .frame(width: width, height: height)
                .clipped()
            }
        } else if let u = fallbackImageURL {
            HomeCachedImage(
                url: u,
                priority: .userInitiated,
                aspectFit: aspectFit,
                showsLoadingIndicator: true
            )
            .frame(width: width, height: height)
            .clipped()
        } else if let pv = playbackVideoURL {
            HomeGridTransAnimationVideoPosterView(videoURL: pv)
                .frame(width: width, height: height)
                .clipped()
        } else {
            AppTheme.surfaceContainer
        }
    }
}
