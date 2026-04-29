//
//  GenerationSuccessView.swift
//  bbb
//
//  成功任务详情：设计稿 GENERATION SUCCESS（大图、信息条、收藏、Reroll、下载、反馈）
//

import AVKit
import Photos
import SwiftUI
import UIKit

struct GenerationSuccessView: View {
    let item: TaskListItem
    /// 关闭成功页后回调（例如刷新「我的创作」列表）；Reroll 现改为跳转首页生成流程，仍会调用以便列表更新
    var onRerollSuccess: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var wallet: UserWalletStore
    @EnvironmentObject private var appLanguage: AppLanguageStore
    @EnvironmentObject private var tabRouter: AppTabRouter

    @State private var likedTemplateKeys: Set<String> = []
    @State private var isRerolling = false
    @State private var isDownloading = false
    @State private var showFeedback = false
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    /// 相册权限被拒后用户再次点「下载」的次数；第 2 次起在弹窗中提供「去设置」
    @State private var photoSavePermissionDeniedAttempts = 0
    /// 当前 Alert 是否在「无法保存（相册权限）」场景下展示「打开系统设置」按钮（第二次及以后）
    @State private var alertShowsOpenSettingsButton = false
    @State private var videoPlayer: AVPlayer?

    init(item: TaskListItem, onRerollSuccess: (() -> Void)? = nil) {
        self.item = item
        self.onRerollSuccess = onRerollSuccess
    }

    private var rawResult: String {
        item.resultUrl?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var resolvedMediaURL: URL? {
        GenerationSuccessMediaURL.resolve(rawResult)
    }

    private var isVideo: Bool {
        let lower = rawResult.lowercased()
        return lower.hasSuffix(".mp4") || lower.hasSuffix(".mov") || lower.hasSuffix(".m4v")
    }

    private var templateKind: TemplateResourceKind? {
        switch item.taskType {
        case 1: return .t1
        case 2: return .t2
        case 3: return .t3
        default: return nil
        }
    }

    private var likeKey: String? {
        guard let k = templateKind, !item.tid.isEmpty else { return nil }
        return "\(k.rawValue):\(item.tid)"
    }

    private var typeBarLabel: String {
        switch item.taskType {
        case 1: return AppLanguageStore.localized("kind.image")
        case 2: return AppLanguageStore.localized("kind.dance")
        case 3: return AppLanguageStore.localized("kind.video")
        default: return AppLanguageStore.localized("kind.media")
        }
    }

    /// 与模板详情主图、首页网格卡片一致：竖版 9:16，宽度随屏幕自适应。
    private let mainMediaAspectRatio: CGFloat = 9 / 16

    private var successGradientBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 18 / 255, green: 10 / 255, blue: 42 / 255),
                AppTheme.background,
                Color(red: 28 / 255, green: 14 / 255, blue: 52 / 255)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        let _ = appLanguage.preference
        ZStack {
            successGradientBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    mainMediaBlock
                        .padding(.horizontal, 16)

                    infoActionBar
                        .padding(.horizontal, 16)

                    bottomActions
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                }
                .padding(.top, 8)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                BBBTrackedText.text(AppLanguageStore.localized("generation.success.title"), size: 13, weight: .heavy, tracking: 1.0, color: Color.white)
            }
        }
        .bbbToolbarVisibleNavigationBar()
        .bbbNavigationBarBackground(Color.black.opacity(0.2))
        .bbbLocalizedNavigationBackButton()
        .onAppear {
            likedTemplateKeys = LocalFavoriteTemplateStore.load(userId: auth.userId)
            if isVideo, let u = resolvedMediaURL {
                let key = u.absoluteString
                Task {
                    await VideoCacheManager.shared.preloadVideo(videoURL: key, priority: .userInitiated, isCurrentDisplay: true)
                    let playURL = await VideoCacheManager.shared.getVideoURL(for: key) ?? u
                    await MainActor.run {
                        videoPlayer = AVPlayer(url: playURL)
                    }
                }
            }
        }
        .onDisappear {
            videoPlayer?.pause()
            videoPlayer = nil
        }
        .sheet(isPresented: $showFeedback) {
            NavigationView {
                FeedbackCenterView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(AppLanguageStore.localized("common.close")) { showFeedback = false }
                        }
                    }
            }
            .navigationViewStyle(StackNavigationViewStyle())
        }
        .alert(alertTitle, isPresented: $showAlert) {
            if alertShowsOpenSettingsButton {
                Button(AppLanguageStore.localized("home.template.photo_permission.open_settings")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
            Button(AppLanguageStore.localized("common.ok"), role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    @ViewBuilder
    private var mainMediaBlock: some View {
        if let url = resolvedMediaURL {
            if isVideo {
                VideoPlayer(player: videoPlayer)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(mainMediaAspectRatio, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(AppTheme.outlineVariant.opacity(0.25), lineWidth: 1)
                    )
            } else {
                HomeCachedImage(url: url, priority: .userInitiated)
                    .aspectRatio(mainMediaAspectRatio, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(AppTheme.outlineVariant.opacity(0.25), lineWidth: 1)
                    )
            }
        }
    }

    private var infoActionBar: some View {
        HStack(spacing: 12) {
            thumbnailTiny
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                BBBTrackedText.text(AppLanguageStore.localized("generation.success.type_label"), size: 9, weight: .semibold, tracking: 0.6, color: AppTheme.outlineVariant)
                Text(typeBarLabel)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.white)
            }

            Spacer(minLength: 8)

            if let key = likeKey {
                Button {
                    toggleFavorite(likeKey: key)
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 44, height: 44)
                        Image(systemName: likedTemplateKeys.contains(key) ? "heart.fill" : "heart")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(
                                likedTemplateKeys.contains(key)
                                    ? AppTheme.primary
                                    : AppTheme.onSurfaceVariant
                            )
                    }
                }
                .buttonStyle(.plain)
            }

            Button {
                Task { await reroll() }
            } label: {
                HStack(spacing: 6) {
                    if isRerolling {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.85)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 13, weight: .bold))
                    }
                    BBBTrackedText.text(AppLanguageStore.localized("generation.success.reroll"), size: 11, weight: .heavy, tracking: 0.8)
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(AppTheme.premiumButtonGradient)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isRerolling || (item.userParams?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppTheme.surfaceContainer.opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppTheme.outlineVariant.opacity(0.2), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var thumbnailTiny: some View {
        if let url = resolvedMediaURL {
            if isVideo {
                ZStack {
                    AppTheme.surfaceContainerHighest
                    Image(systemName: "film.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(AppTheme.primary)
                }
            } else {
                HomeCachedImage(url: url, priority: .utility)
            }
        } else {
            AppTheme.surfaceContainerHighest
        }
    }

    private var bottomActions: some View {
        HStack(spacing: 12) {
            Button {
                Task { await saveToPhotos() }
            } label: {
                HStack(spacing: 8) {
                    if isDownloading {
                        ProgressView()
                            .tint(Color(red: 42 / 255, green: 18 / 255, blue: 72 / 255))
                    } else {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    BBBTrackedText.text(AppLanguageStore.localized("generation.success.download"), size: 13, weight: .heavy, tracking: 0.6)
                }
                .foregroundStyle(Color(red: 42 / 255, green: 18 / 255, blue: 72 / 255))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AppTheme.primary.opacity(0.92))
                )
            }
            .buttonStyle(.plain)
            .disabled(isDownloading || resolvedMediaURL == nil)

            Button {
                showFeedback = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 15, weight: .semibold))
                    BBBTrackedText.text(AppLanguageStore.localized("generation.success.feedback"), size: 13, weight: .heavy, tracking: 0.6)
                }
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(AppTheme.primary.opacity(0.55), lineWidth: 1.2)
                )
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func toggleFavorite(likeKey: String) {
        let willLike = !likedTemplateKeys.contains(likeKey)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if willLike {
            likedTemplateKeys.insert(likeKey)
        } else {
            likedTemplateKeys.remove(likeKey)
        }
        LocalFavoriteTemplateStore.save(likedTemplateKeys, userId: auth.userId)
    }

    /// 重新走该模板的完整生成流程（首页 `HomeTemplateGenerationSheet`：选图 → 上传 → 建单），与主站生成入口一致。
    private func reroll() async {
        let tid = item.tid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tid.isEmpty else {
            await MainActor.run {
                alertShowsOpenSettingsButton = false
                alertTitle = AppLanguageStore.localized("common.tip")
                alertMessage = AppLanguageStore.localized("generation.success.reroll.template_load_failed")
                showAlert = true
            }
            return
        }
        guard auth.isAuthenticated else {
            await MainActor.run {
                alertShowsOpenSettingsButton = false
                alertTitle = AppLanguageStore.localized("home.alert.login.title")
                alertMessage = AppLanguageStore.localized("home.alert.login.message")
                showAlert = true
            }
            return
        }

        await MainActor.run { isRerolling = true }
        let feedItem = await loadHomeFeedItemForReroll()
        await MainActor.run { isRerolling = false }

        guard let feedItem else {
            await MainActor.run {
                alertShowsOpenSettingsButton = false
                alertTitle = AppLanguageStore.localized("common.tip")
                alertMessage = AppLanguageStore.localized("generation.success.reroll.template_load_failed")
                showAlert = true
            }
            return
        }

        await MainActor.run {
            dismiss()
        }
        onRerollSuccess?()
        tabRouter.select(.home)
        let payload = feedItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NotificationCenter.default.post(
                name: .homeRequestPrimaryGenerate,
                object: payload,
                userInfo: ["browseOtherReturnTabRaw": AppTab.my.rawValue]
            )
        }
    }

    private func loadHomeFeedItemForReroll() async -> HomeFeedItem? {
        let tid = item.tid.trimmingCharacters(in: .whitespacesAndNewlines)
        switch item.taskType {
        case 1:
            let r = await TemplateRepository.shared.getImageTemplateDetail(tid: tid)
            if case .success(let t) = r { return HomeFeedItem(imageTemplate: t) }
        case 2:
            let r = await TemplateRepository.shared.getDancingTemplateDetail(tid: tid)
            if case .success(let t) = r { return HomeFeedItem(dancingTemplate: t) }
        case 3:
            let r = await TemplateRepository.shared.getVideoTemplateDetail(tid: tid)
            if case .success(let t) = r { return HomeFeedItem(videoTemplate: t) }
        default:
            break
        }
        return nil
    }

    private func saveToPhotos() async {
        guard let url = resolvedMediaURL else { return }
        let ok = await requestAddOnlyPhotoAccess()
        guard ok else {
            await MainActor.run {
                photoSavePermissionDeniedAttempts += 1
                alertShowsOpenSettingsButton = photoSavePermissionDeniedAttempts >= 2
                alertTitle = AppLanguageStore.localized("generation.success.save.denied.title")
                alertMessage = AppLanguageStore.localized("generation.success.save.denied.message")
                showAlert = true
            }
            return
        }

        await MainActor.run {
            photoSavePermissionDeniedAttempts = 0
            isDownloading = true
        }
        do {
            if isVideo {
                let (fileURL, isTemporaryCopy) = try await resolveVideoFileForSaving(from: url)
                try await saveVideoFileToLibrary(at: fileURL)
                if isTemporaryCopy {
                    try? FileManager.default.removeItem(at: fileURL)
                }
            } else {
                let key = url.absoluteString
                var image = await ImageCacheManager.shared.getImage(for: key)
                if image == nil {
                    await ImageCacheManager.shared.preloadImage(urlString: key, priority: .userInitiated)
                    image = await ImageCacheManager.shared.getImage(for: key)
                }
                guard let image else {
                    throw NSError(
                        domain: "bbb",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: AppLanguageStore.localized("generation.success.save.error.invalid_image")]
                    )
                }
                try await saveImageToLibrary(image)
            }
            await MainActor.run {
                isDownloading = false
                photoSavePermissionDeniedAttempts = 0
                alertShowsOpenSettingsButton = false
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                alertTitle = AppLanguageStore.localized("generation.success.save.ok.title")
                alertMessage = AppLanguageStore.localized("generation.success.save.ok.message")
                showAlert = true
            }
        } catch {
            await MainActor.run {
                isDownloading = false
                alertShowsOpenSettingsButton = false
                alertTitle = AppLanguageStore.localized("generation.success.save.error.title")
                alertMessage = error.localizedDescription
                showAlert = true
            }
        }
    }

    private func requestAddOnlyPhotoAccess() async -> Bool {
        await withCheckedContinuation { cont in
            if #available(iOS 14, *) {
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                    cont.resume(returning: status == .authorized || status == .limited)
                }
            } else {
                PHPhotoLibrary.requestAuthorization { status in
                    cont.resume(returning: status == .authorized)
                }
            }
        }
    }

    private func saveImageToLibrary(_ image: UIImage) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }
    }

    /// 优先使用 `VideoCacheManager` 已下载的本地文件；否则下载到临时目录。返回 `(文件 URL, 是否为临时文件需删除)`。
    private func resolveVideoFileForSaving(from url: URL) async throws -> (URL, Bool) {
        let key = url.absoluteString
        if let cached = await VideoCacheManager.shared.getVideoURL(for: key) {
            return (cached, false)
        }
        await VideoCacheManager.shared.preloadVideo(videoURL: key, priority: .userInitiated, isCurrentDisplay: true)
        if let cached = await VideoCacheManager.shared.getVideoURL(for: key) {
            return (cached, false)
        }
        let tmp = try await downloadToTemporaryFile(from: url)
        return (tmp, true)
    }

    private func downloadToTemporaryFile(from url: URL) async throws -> URL {
        let (localURL, _) = try await URLSession.shared.download(from: url)
        let ext = url.pathExtension.isEmpty ? "mp4" : url.pathExtension
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.moveItem(at: localURL, to: dest)
        return dest
    }

    private func saveVideoFileToLibrary(at fileURL: URL) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
        }
    }
}

// MARK: - Media URL（与 `MyCreationsView` 中 `TaskResultMediaURL` 一致）

private enum GenerationSuccessMediaURL {
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
