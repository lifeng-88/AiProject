//
//  HomeTemplateGenerationSheet.swift
//  bbb
//
//  首页主按钮：选图 → 上传 → 创建任务 → 接入任务轮询
//

import Photos
import SwiftUI
import UIKit

struct HomeTemplateGenerationSheet: View {
    let item: HomeFeedItem
    /// 自瀑布流详情等预选的肖像图；非空时进入 sheet 即带入，无需再点「选择照片」
    var prefilledImage: UIImage?
    var onDismiss: () -> Void
    /// 排队页「浏览其他内容」与顶栏「返回」共用：由 `HomeView.finishGenerationQueuingExit` 注入（从首页预览进入则关预览回瀑布流，否则回首页）
    var onBrowseOtherLeaveToFeed: (() -> Void)?

    @EnvironmentObject private var wallet: UserWalletStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var versionConfig: VersionConfigStore
    @EnvironmentObject private var tabRouter: AppTabRouter
    @EnvironmentObject private var appLanguage: AppLanguageStore

    @AppStorage("homeUploadTipsSuppressed") private var uploadTipsSuppressed = false
    @State private var showUploadTips = false
    @State private var dontShowAgainTips = false
    @State private var pickedImage: UIImage?
    @State private var showLegacyPhotoPicker = false
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var showErrorAlert = false
    @State private var showRechargeUpsell = false
    /// 相册读取权限被拒 / 受限时提示前往系统设置
    @State private var showPhotoPermissionAlert = false
    /// 上传并创建任务成功后（或预览页预填图直接进入）：全屏排队 UI；顶栏「返回」与「浏览其他内容」均由首页统一决定回到预览上一级或首页
    @State private var showQueuingExperience = false
    @State private var didAutoSubmitFromPrefill = false
    /// 生成完成：自动弹出与「我的创作」一致的 `GenerationSuccessView`
    @State private var completedTaskForSuccess: TaskListItem?

    init(
        item: HomeFeedItem,
        prefilledImage: UIImage?,
        onDismiss: @escaping () -> Void,
        onBrowseOtherLeaveToFeed: (() -> Void)? = nil
    ) {
        self.item = item
        self.prefilledImage = prefilledImage
        self.onDismiss = onDismiss
        self.onBrowseOtherLeaveToFeed = onBrowseOtherLeaveToFeed
        _showQueuingExperience = State(initialValue: prefilledImage != nil)
    }

    /// 顶栏「Back」与排队页「浏览其他内容」共用：收起排队 UI 后走 `onBrowseOtherLeaveToFeed`（首页注入为「从预览进入则关预览回瀑布流上一级，否则回首页 Tab」）。
    private func leaveQueuingSameAsBrowseOther() {
        showQueuingExperience = false
        if let leave = onBrowseOtherLeaveToFeed {
            leave()
        } else {
            onDismiss()
        }
    }

    /// 生成层叠在首页 `NavigationView.overlay` 上；若此处再包一层 `NavigationView`，内层导航栏/`.toolbar` 在部分系统上整页不显示，关闭按钮消失。顶栏改为 `safeAreaInset` 自建。
    private var generationSheetTopBar: some View {
        let barBackground = showQueuingExperience ? HomeGenerationQueuingView.pageBackground : AppTheme.background
        let balanceColor: Color = showQueuingExperience ? HomeGenerationQueuingView.accentLavender : AppTheme.onSurface
        return HStack(alignment: .center, spacing: 0) {
            HStack {
                Button {
                    if showQueuingExperience {
                        leaveQueuingSameAsBrowseOther()
                    } else if !isWorking {
                        onDismiss()
                    }
                } label: {
                    Text(showQueuingExperience ? AppLanguageStore.localized("common.back") : AppLanguageStore.localized("common.close"))
                        .font(.body.weight(.medium))
                        .foregroundStyle(
                            (isWorking && !showQueuingExperience)
                                ? AppTheme.onSurfaceVariant.opacity(0.45)
                                : AppTheme.primary
                        )
                }
                .buttonStyle(.plain)
                .disabled(isWorking && !showQueuingExperience)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Group {
                if showQueuingExperience {
                    Text(AppLanguageStore.localized("home.generating.queuing.nav_title"))
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(HomeGenerationQueuingView.accentLavender)
                } else {
                    Text(item.actionTitle)
                        .font(.headline)
                        .foregroundStyle(AppTheme.onSurface)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)

            HStack {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    tabRouter.select(.recharge)
                } label: {
                    HStack(spacing: 4) {
                        AppCoinIcon(size: 15)
                        Text(wallet.formattedCoinBalance)
                            .font(.system(size: 14, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(balanceColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(barBackground)
    }

    var body: some View {
        let _ = appLanguage.preference
        ZStack {
                if showQueuingExperience, let source = pickedImage ?? prefilledImage {
                    HomeGenerationQueuingView(
                        item: item,
                        sourceImage: source,
                        isSubmitting: isWorking,
                        onBrowseOther: {
                            leaveQueuingSameAsBrowseOther()
                        },
                        onTaskSucceeded: { listItem in
                            completedTaskForSuccess = listItem
                        }
                    )
                    .transition(.opacity)
                } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(AppLanguageStore.localized("home.template.sheet.body"))
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.onSurfaceVariant)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 8) {
                            Text(AppLanguageStore.localized("home.template.sheet.cost"))
                                .foregroundStyle(AppTheme.onSurfaceVariant)
                            Text("\(item.consumedCoins)")
                                .font(.headline.monospacedDigit())
                            AppCoinIcon(size: 18)
                        }
                        Button {
                            requestPhotoPickerAfterTipsIfNeeded()
                        } label: {
                            Label(AppLanguageStore.localized("home.template.sheet.pick_photo"), systemImage: "photo.on.rectangle.angled")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(AppTheme.surfaceContainerHigh)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(isWorking)

                        if let pickedImage {
                            Image(uiImage: pickedImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 280)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }

                        Button(action: submit) {
                            Text(AppLanguageStore.localized("home.template.sheet.start"))
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    Group {
                                        if pickedImage == nil || isWorking {
                                            AppTheme.surfaceContainerHighest
                                        } else {
                                            AppTheme.premiumButtonGradient
                                        }
                                    }
                                )
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(pickedImage == nil || isWorking)
                    }
                    .padding(20)
                }

                if showRechargeUpsell {
                    HomeGenerationRechargeUpsellView(
                        onClose: { showRechargeUpsell = false },
                        onExploreFullRecharge: {
                            showRechargeUpsell = false
                            onDismiss()
                            tabRouter.select(.recharge)
                        }
                    )
                    .environmentObject(wallet)
                    .environmentObject(auth)
                    .environmentObject(versionConfig)
                    .environmentObject(tabRouter)
                    .environmentObject(appLanguage)
                    .transition(.opacity)
                    .zIndex(2)
                }
                }

                if showUploadTips {
                    HomeUploadTipsOverlay(
                        dontShowAgain: $dontShowAgainTips,
                        onClose: {
                            withAnimation(.easeOut(duration: 0.22)) {
                                showUploadTips = false
                            }
                        },
                        onConfirm: {
                            if dontShowAgainTips {
                                uploadTipsSuppressed = true
                            }
                            withAnimation(.easeOut(duration: 0.22)) {
                                showUploadTips = false
                            }
                            DispatchQueue.main.async {
                                presentPhotoPickerIfAuthorized()
                            }
                        }
                    )
                    .transition(.opacity)
                    .zIndex(4)
                }

                /// 放在 `ZStack` 内并铺满，保证 Host VC 在 template sheet 的窗口层级里再 `present` 相册，关相册只 dismiss 该 modal。
                LegacyImagePicker(image: $pickedImage, isPresented: $showLegacyPhotoPicker)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                    .zIndex(-1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(showQueuingExperience ? HomeGenerationQueuingView.pageBackground : AppTheme.background)
            .safeAreaInset(edge: .top, spacing: 0) {
                generationSheetTopBar
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
            .alert(AppLanguageStore.localized("home.template.sheet.cannot"), isPresented: $showErrorAlert) {
                Button(AppLanguageStore.localized("common.confirm"), role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .animation(.spring(response: 0.38, dampingFraction: 0.88), value: showUploadTips)
            .fullScreenCover(item: $completedTaskForSuccess, onDismiss: {
                TaskPollingService.shared.reset()
                leaveQueuingSameAsBrowseOther()
            }) { listItem in
                NavigationView {
                    GenerationSuccessView(item: listItem, onRerollSuccess: nil)
                        .environmentObject(wallet)
                        .environmentObject(auth)
                        .environmentObject(tabRouter)
                        .environmentObject(appLanguage)
                }
                .navigationViewStyle(StackNavigationViewStyle())
            }
            .onAppear {
                applyPrefilledImageIfNeeded()
                if prefilledImage != nil, !didAutoSubmitFromPrefill {
                    didAutoSubmitFromPrefill = true
                    submit()
                }
            }
            .onChange(of: item.id) { _ in
                applyPrefilledImageIfNeeded()
            }
    }

    private func applyPrefilledImageIfNeeded() {
        if let p = prefilledImage {
            pickedImage = p
        }
    }

    /// 与首页「Upload Tips」一致：未勾选「不再提示」时先弹窗，再打开系统相册
    private func requestPhotoPickerAfterTipsIfNeeded() {
        if uploadTipsSuppressed {
            presentPhotoPickerIfAuthorized()
        } else {
            dontShowAgainTips = false
            showUploadTips = true
        }
    }

    /// 检查相册读取权限（含「仅添加」以外的读库；`limited` 亦可从相册选图）
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

    private func submit() {
        guard let pickedImage else { return }
        /// 金币不足时弹出充值套餐层（`HomeGenerationRechargeUpsellView`），不发起上传/建单
        if item.consumedCoins > 0, wallet.coinBalance < item.consumedCoins {
            showRechargeUpsell = true
            if prefilledImage != nil {
                showQueuingExperience = false
            }
            return
        }
        guard let jpeg = pickedImage.jpegData(compressionQuality: 0.88) else {
            if prefilledImage != nil {
                showQueuingExperience = false
            }
            errorMessage = AppLanguageStore.localized("photo_validation.encode_failed")
            showErrorAlert = true
            return
        }

        isWorking = true

        Task {
            let uploadResult = await UploadRepository.shared.uploadImage(
                imageData: jpeg,
                fileName: "face_\(item.id).jpg",
                type: "input",
                progressHandler: nil
            )

            switch uploadResult {
            case .failure(let err):
                await MainActor.run {
                    isWorking = false
                    if prefilledImage != nil {
                        showQueuingExperience = false
                    }
                    errorMessage = err.userMessage
                    showErrorAlert = true
                }
                return
            case .success(let urlString):
                let userParams: String
                do {
                    userParams = try CreateTaskUserParams(inputImages: [urlString]).jsonString()
                } catch {
                    await MainActor.run {
                        isWorking = false
                        if prefilledImage != nil {
                            showQueuingExperience = false
                        }
                        errorMessage = error.localizedDescription
                        showErrorAlert = true
                    }
                    return
                }

                let request = CreateTaskRequest(
                    taskType: item.templateKind.apiTaskType,
                    tid: item.id,
                    userParams: userParams
                )
                let createResult = await TaskAPI.createTask(request)

                await MainActor.run {
                    isWorking = false
                    switch createResult {
                    case .success(let resp):
                        wallet.applyGenerationSpend(coins: item.consumedCoins)
                        TaskPollingService.shared.startPolling(taskId: resp.taskId)
                        showQueuingExperience = true
                        PushManager.shared.requestAuthorizationAfterTaskCreatedSuccess()
                    case .failure(let err):
                        if prefilledImage != nil {
                            showQueuingExperience = false
                        }
                        if Self.isInsufficientGoldServerError(err) {
                            showRechargeUpsell = true
                        } else {
                            errorMessage = err.userMessage
                            showErrorAlert = true
                        }
                    }
                }
            }
        }
    }

    /// 服务端返回余额不足时改弹充值层，避免「Cannot continue」类 Alert
    private static func isInsufficientGoldServerError(_ error: AppError) -> Bool {
        let m = error.userMessage.lowercased()
        if m.contains("insufficient"), m.contains("gold") || m.contains("balance") || m.contains("coin") { return true }
        if m.contains("余额"), m.contains("不足") || m.contains("不够") { return true }
        return false
    }
}

/// 创建任务后全屏排队 UI（与预览页预填图进入同一套）；沿用 `TaskPollingService` 状态
private struct HomeGenerationQueuingView: View {
    /// 设计稿主背景约 `#0B0B0F`
    static let pageBackground = Color(red: 11 / 255, green: 11 / 255, blue: 15 / 255)
    /// 主按钮与强调色约 `#C09FF8`
    static let accentLavender = Color(red: 192 / 255, green: 159 / 255, blue: 248 / 255)
    static let onAccentDeep = Color(red: 45 / 255, green: 28 / 255, blue: 72 / 255)

    let item: HomeFeedItem
    let sourceImage: UIImage
    /// 上传 / 创建任务尚未完成
    var isSubmitting: Bool
    let onBrowseOther: () -> Void
    /// `taskStatus == .success` 且 `resultUrl` 有效时调用一次，用于自动弹出生成结果全屏页
    let onTaskSucceeded: (TaskListItem) -> Void

    @ObservedObject private var taskService = TaskPollingService.shared
    @State private var didPresentSuccessScreen = false

    private var templateDisplayURL: URL? {
        item.immersiveImageURLs.first ?? item.imageURL
    }

    /// 大图标题：排队 / 生成中
    private var displayMainTitle: String {
        if isSubmitting {
            return AppLanguageStore.localized("home.generating.queuing.nav_title")
        }
        switch taskService.taskStatus {
        case .pending:
            return AppLanguageStore.localized("home.generating.queuing.nav_title")
        case .running:
            return AppLanguageStore.localized("home.generating.queuing.hero_generating")
        default:
            return AppLanguageStore.localized("home.generating.title")
        }
    }

    /// 标题下方的说明文案（生成中时为融合说明，排队时为等待提示）
    private var displaySubtitle: String? {
        if isSubmitting {
            return AppLanguageStore.localized("home.generating.queuing.creating_task")
        }
        switch taskService.taskStatus {
        case .pending:
            if let w = taskService.waitTime, !w.isEmpty {
                return String(format: AppLanguageStore.localized("home.generating.pending_wait"), w)
            }
            return AppLanguageStore.localized("home.generating.pending")
        case .running:
            return AppLanguageStore.localized("home.generating.queuing.detail_running")
        default:
            return nil
        }
    }

    private var showsCircularProgress: Bool {
        !isSubmitting && taskService.taskStatus == .running
    }

    var body: some View {
        GeometryReader { geo in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    dualCardRow
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                    Color.clear.frame(height: 12)

                    Group {
                        if showsCircularProgress {
                            QueuingCircularProgressView(
                                progress: min(1, max(0, taskService.progress)),
                                accent: Self.accentLavender
                            )
                        } else {
                            queuingSymbolBlock
                        }
                    }
                    .padding(.bottom, 4)

                    Text(displayMainTitle)
                        .font(.system(size: 26, weight: .heavy))
                        .foregroundStyle(AppTheme.onSurface)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)

                    if let sub = displaySubtitle {
                        Text(sub)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AppTheme.onSurfaceVariant)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .padding(.top, 10)
                    }

                    Color.clear.frame(height: 12)

                    VStack(spacing: 12) {
                        Button(action: onBrowseOther) {
                            HStack(spacing: 8) {
                                Text(AppLanguageStore.localized("home.generating.queuing.browse_other"))
                                    .font(.system(size: 13, weight: .heavy))
                                    .tracking(0.6)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .foregroundStyle(Self.onAccentDeep)
                            .background(Self.accentLavender)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Text(AppLanguageStore.localized("home.generating.queuing.footer_short"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppTheme.onSurfaceVariant.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 20)
                    }
                    .padding(.horizontal, 20)
                    /// 小屏上避免底部说明被 Home Indicator 裁切：随安全区加大下边距
                    .padding(.bottom, max(28, geo.safeAreaInsets.bottom + 16))
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Self.pageBackground)
        .onChange(of: taskService.taskStatus) { newStatus in
            guard newStatus == .success else { return }
            guard !didPresentSuccessScreen else { return }
            guard !isSubmitting else { return }
            guard let resp = taskService.taskResponse,
                  let url = resp.resultUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !url.isEmpty else { return }
            didPresentSuccessScreen = true
            onTaskSucceeded(TaskListItem.fromGetTaskResponse(resp))
        }
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
            Image(uiImage: sourceImage)
                .resizable()
                .scaledToFill()
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
            HomeCachedImage(url: templateDisplayURL, aspectFit: false)
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

// MARK: - 生成中环形进度（中央百分比）

private struct QueuingCircularProgressView: View {
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
