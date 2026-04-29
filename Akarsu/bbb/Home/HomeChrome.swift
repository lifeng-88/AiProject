//
//  HomeChrome.swift
//  bbb
//
//  参考: home_layout_switch_tooltip_guide, home_premium_generating_notification_capsule
//

import SwiftUI
import UIKit

struct HomeTopBar: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @Binding var layoutMode: HomeLayoutMode
    @Binding var primaryTab: Int
    let primaryTabs: [String]
    let coinBalance: String
    var onLayoutToggle: () -> Void
    var onCoinTap: () -> Void = {}
    /// `true`：信息流铺满顶栏区域后方，顶栏为半透明叠层（勿再用不透明底挡住封面）
    var feedExtendsBehindChrome: Bool = false
    /// `true`：下方紧接 Video 二级分类条时去掉顶栏底内边距，使分类条贴住顶栏下缘
    var tightBottomForSecondaryStrip: Bool = false

    /// iPhone SE 等窄屏上 Image/Video/Dance 与左右按钮横向重叠；`ZStack` 后绘制的子视图在上层接收触摸，原先 Tab 盖住菜单/金币。改为 Tab 在底、左右在顶，中间 `Spacer` 不参与命中测试以便点到 Tab。
    private var isCompactWidth: Bool {
        horizontalSizeClass == .compact
    }

    private var primaryTabSpacing: CGFloat {
        isCompactWidth ? 12 : 32
    }

    private var primaryTabFontSize: CGFloat {
        isCompactWidth ? 12.5 : 15
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack(spacing: primaryTabSpacing) {
                    ForEach(primaryTabs.indices, id: \.self) { i in
                        let selected = primaryTab == i
                        Button(action: { primaryTab = i }) {
                            Text(primaryTabs[i])
                                .font(.system(size: primaryTabFontSize, weight: selected ? .bold : .semibold))
                                .foregroundStyle(
                                    selected ? AppTheme.primary : AppTheme.onSurfaceVariant.opacity(0.42)
                                )
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                                .padding(.bottom, 10)
                                .background(alignment: .bottom) {
                                    if selected {
                                        Capsule()
                                            .fill(
                                                LinearGradient(
                                                    colors: [AppTheme.primary, AppTheme.primaryDim],
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                )
                                            )
                                            .frame(height: 3.5)
                                            .frame(maxWidth: .infinity)
                                            .shadow(color: AppTheme.primary.opacity(0.45), radius: 4, y: 0)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack(spacing: 0) {
                    chromeIconButton(
                        icon: layoutMode == .immersive ? "line.3.horizontal" : "square.grid.2x2.fill",
                        action: onLayoutToggle,
                        accessibilityLabel: layoutMode == .immersive ? AppLanguageStore.localized("home.chrome.layout.grid") : AppLanguageStore.localized("home.chrome.layout.feed")
                    )
                    Spacer(minLength: 0)
                        .allowsHitTesting(false)
                    Button(action: onCoinTap) {
                        HStack(spacing: 6) {
                            AppCoinIcon(size: 15)
                            Text(coinBalance)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(AppTheme.onSurface)
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background {
                            ZStack {
                                Capsule().fill(Color.black.opacity(0.45))
                                Capsule().fill(.ultraThinMaterial.opacity(0.85))
                            }
                        }
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(AppTheme.outlineVariant.opacity(0.35), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(format: AppLanguageStore.localized("home.chrome.coin_a11y"), coinBalance))
                    .accessibilityHint(AppLanguageStore.localized("home.chrome.recharge_hint"))
                }
                .padding(.horizontal, 14)
            }
            .padding(.top, 10)
            .padding(.bottom, tightBottomForSecondaryStrip ? 0 : 10)
        }
        .background(chromeBackdropGradient)
    }

    private var chromeBackdropGradient: some View {
        Group {
            if feedExtendsBehindChrome {
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.52),
                        Color.black.opacity(0.22),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                LinearGradient(
                    colors: [
                        AppTheme.background.opacity(0.97),
                        AppTheme.background.opacity(0.55),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }

    private func chromeIconButton(icon: String, action: @escaping () -> Void, accessibilityLabel: String) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                /// iOS 15：`symbolRenderingMode(.monochrome)` 与 `foregroundStyle(LinearGradient)` 组合会导致 SF Symbol 发灰/消失/错位；渐变图标用默认 hierarchical 渲染即可。
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            AppTheme.primary.opacity(0.98),
                            AppTheme.primary.opacity(0.82),
                            AppTheme.primaryDim.opacity(0.96)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 40, height: 40)
                /// iOS 15：`Circle().fill(...).background(.ultraThinMaterial, in: Circle())` 叠层在部分设备上异常；改为 `ZStack` 明确顺序。
                .background(
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial.opacity(0.45))
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        AppTheme.primary.opacity(0.14),
                                        Color.black.opacity(0.38)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                )
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    AppTheme.primary.opacity(0.42),
                                    AppTheme.outlineVariant.opacity(0.28)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.28), value: icon)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// 与 `TaskPollingService` 同步：仅在真实排队/生成中时显示，可收起、可跳转「我的」查看任务
struct HomeGeneratingBanner: View {
    @ObservedObject private var taskService = TaskPollingService.shared
    var onDismiss: () -> Void
    var onViewCreations: () -> Void

    private var subtitle: String {
        switch taskService.taskStatus {
        case .pending:
            if let w = taskService.waitTime, !w.isEmpty {
                return String(format: AppLanguageStore.localized("home.generating.pending_wait"), w)
            }
            return AppLanguageStore.localized("home.generating.pending")
        case .running:
            let p = Int((min(1, taskService.progress) * 100).rounded())
            if p > 0 {
                return String(format: AppLanguageStore.localized("home.generating.running_percent"), p)
            }
            return AppLanguageStore.localized("home.generating.running")
        default:
            return ""
        }
    }

    var body: some View {
        Group {
            if taskService.isGenerationInProgress {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(AppTheme.primary.opacity(0.14))
                                .frame(width: 40, height: 40)
                                .overlay(Circle().stroke(AppTheme.primary.opacity(0.38), lineWidth: 1))
                            Image(systemName: taskService.taskStatus == .pending ? "hourglass" : "wand.and.stars")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(AppTheme.primary)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(AppLanguageStore.localized("home.generating.title"))
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(AppTheme.onSurface)
                            Text(subtitle)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(AppTheme.onSurfaceVariant)
                                .lineLimit(2)
                                .minimumScaleFactor(0.85)
                        }

                        Spacer(minLength: 8)

                        Button(action: onDismiss) {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AppTheme.onSurfaceVariant)
                                .frame(width: 36, height: 36)
                                .background(Color.white.opacity(0.06))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(AppLanguageStore.localized("home.generating.dismiss_a11y"))
                    }

                    if taskService.taskStatus == .running {
                        ProgressView(value: min(1, taskService.progress))
                            .progressViewStyle(.linear)
                            .tint(AppTheme.primary)
                            .frame(height: 5)
                            .clipShape(Capsule())
                    }

                    Button(action: onViewCreations) {
                        HStack(spacing: 6) {
                            Text(AppLanguageStore.localized("home.generating.view_my"))
                                .font(.system(size: 13, weight: .semibold))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundStyle(AppTheme.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(AppLanguageStore.localized("home.generating.view_my_hint"))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(AppTheme.surfaceContainerLow.opacity(0.98))
                )
                .background(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [AppTheme.primary.opacity(0.5), AppTheme.primaryDim.opacity(0.32)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: AppTheme.primary.opacity(0.18), radius: 16, y: 5)
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .opacity
                ))
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: taskService.isGenerationInProgress)
        .animation(.easeInOut(duration: 0.2), value: taskService.taskStatus)
        .animation(.easeInOut(duration: 0.15), value: taskService.progress)
    }
}

/// Video 二级分类：固定行高 + 全宽底条（顶内边距在 `HomeSecondaryTagScrollUIKit` 中与顶栏衔接）
private enum HomeSecondaryTagStripMetrics {
    static let barHeight: CGFloat = 52
}

/// 横滑胶囊按钮：圆角随高度为「半高」，与 `Capsule` 一致，避免固定半径与真实高度不一致时两端过尖或过圆
private final class HomeSecondaryTagPillButton: UIButton {
    override func layoutSubviews() {
        super.layoutSubviews()
        let h = bounds.height
        guard h > 1 else { return }
        layer.cornerRadius = h * 0.5
        layer.cornerCurve = .continuous
    }
}

/// 与 `AppTheme` 一致；避免 `UIColor(Color)`（iOS 17+）以便 iOS 15 编译
private enum HomeSecondaryTagUIKitColors {
    static let pillSelectedBg = UIColor(red: 149 / 255, green: 71 / 255, blue: 247 / 255, alpha: 0.72)
    static let pillUnselectedBg = UIColor(red: 24 / 255, green: 24 / 255, blue: 39 / 255, alpha: 0.42)
    static let pillSelectedText = UIColor(white: 1, alpha: 0.98)
    static let pillUnselectedText = UIColor(red: 197 / 255, green: 154 / 255, blue: 255 / 255, alpha: 0.88)
    static let pillSelectedBorder = UIColor(red: 197 / 255, green: 154 / 255, blue: 255 / 255, alpha: 0.65)
    static let pillUnselectedBorder = UIColor(red: 71 / 255, green: 71 / 255, blue: 85 / 255, alpha: 0.22)
}

/// iOS 15 上 SwiftUI `ScrollView` + `ScrollViewReader` 在 Tab 切换后易出现内容偏移错位；用 `UIScrollView` 在布局完成后 `setContentOffset` 居中选中项，避免二级条「整体位移」。
private struct HomeSecondaryTagScrollUIKit: UIViewRepresentable {
    let tags: [String]
    @Binding var selected: Int

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.alwaysBounceHorizontal = true
        scroll.backgroundColor = .clear
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.clipsToBounds = true

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 12
        stack.isLayoutMarginsRelativeArrangement = true
        /// 顶边收紧，与 `HomeTopBar` 底缘对齐（贴住自定义导航栏底部）
        stack.layoutMargins = UIEdgeInsets(top: 4, left: 14, bottom: 10, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        ])

        context.coordinator.scrollView = scroll
        context.coordinator.stackView = stack
        return scroll
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        context.coordinator.tags = tags
        context.coordinator.selectedBinding = $selected
        context.coordinator.syncFromSwiftUI()
    }

    final class Coordinator: NSObject {
        weak var scrollView: UIScrollView?
        weak var stackView: UIStackView?
        private var buttons: [UIButton] = []
        private var lastTags: [String] = []
        private var lastSyncedSelected: Int = -1

        var tags: [String] = []
        var selectedBinding: Binding<Int>?

        @objc func pillTapped(_ sender: UIButton) {
            selectedBinding?.wrappedValue = sender.tag
        }

        func syncFromSwiftUI() {
            guard let stack = stackView, let binding = selectedBinding else { return }
            let sel = binding.wrappedValue

            if tags != lastTags {
                stack.arrangedSubviews.forEach { v in
                    stack.removeArrangedSubview(v)
                    v.removeFromSuperview()
                }
                buttons.removeAll()
                for (i, title) in tags.enumerated() {
                    let btn = HomeSecondaryTagPillButton(type: .custom)
                    btn.tag = i
                    btn.accessibilityLabel = title
                    btn.addTarget(self, action: #selector(pillTapped(_:)), for: .touchUpInside)
                    btn.clipsToBounds = true
                    btn.contentEdgeInsets = UIEdgeInsets(top: 8, left: 18, bottom: 8, right: 18)
                    HomeSecondaryTagUIKitStyle.apply(to: btn, title: title, isSelected: i == sel)
                    stack.addArrangedSubview(btn)
                    buttons.append(btn)
                }
                lastTags = tags
                lastSyncedSelected = sel
                scheduleScrollToSelected(animated: false)
                return
            }

            for (i, btn) in buttons.enumerated() where i < tags.count {
                HomeSecondaryTagUIKitStyle.apply(to: btn, title: tags[i], isSelected: i == sel)
            }

            if sel != lastSyncedSelected {
                lastSyncedSelected = sel
                scheduleScrollToSelected(animated: true)
            }
        }

        private func scheduleScrollToSelected(animated: Bool) {
            scrollToSelected(animated: animated)
            DispatchQueue.main.async { [weak self] in
                self?.scrollToSelected(animated: false)
            }
        }

        private func scrollToSelected(animated: Bool) {
            guard let scroll = scrollView, let binding = selectedBinding else { return }
            let idx = binding.wrappedValue
            guard idx >= 0, idx < buttons.count else { return }
            scroll.layoutIfNeeded()
            let btn = buttons[idx]
            btn.layoutIfNeeded()
            guard scroll.bounds.width > 8 else { return }

            let rect = btn.convert(btn.bounds, to: scroll)
            let midX = rect.midX
            let rawX = midX - scroll.bounds.width * 0.5
            let maxX = max(0, scroll.contentSize.width - scroll.bounds.width)
            let x = min(max(0, rawX), maxX)
            scroll.setContentOffset(CGPoint(x: x, y: 0), animated: animated)
        }
    }
}

private enum HomeSecondaryTagUIKitStyle {
    static func apply(to button: UIButton, title: String, isSelected: Bool) {
        let bg: UIColor
        let text: UIColor
        let border: UIColor
        if isSelected {
            bg = HomeSecondaryTagUIKitColors.pillSelectedBg
            text = HomeSecondaryTagUIKitColors.pillSelectedText
            border = HomeSecondaryTagUIKitColors.pillSelectedBorder
        } else {
            bg = HomeSecondaryTagUIKitColors.pillUnselectedBg
            text = HomeSecondaryTagUIKitColors.pillUnselectedText
            border = HomeSecondaryTagUIKitColors.pillUnselectedBorder
        }
        button.backgroundColor = bg
        button.layer.borderWidth = 1
        button.layer.borderColor = border.cgColor

        let m = NSMutableAttributedString(string: title)
        let r = NSRange(location: 0, length: m.length)
        let font = UIFont.systemFont(ofSize: 10, weight: .heavy)
        m.addAttribute(.kern, value: 1.4, range: r)
        m.addAttribute(.font, value: font, range: r)
        m.addAttribute(.foregroundColor, value: text, range: r)
        button.setAttributedTitle(m, for: .normal)
    }
}

struct HomeSecondaryTagStrip: View {
    let tags: [String]
    @Binding var selected: Int

    var body: some View {
        HomeSecondaryTagScrollUIKit(tags: tags, selected: $selected)
            .frame(height: HomeSecondaryTagStripMetrics.barHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct HomeLayoutTooltip: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.onSurface)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(AppTheme.surfaceContainer.opacity(0.92))
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppTheme.primary.opacity(0.3), lineWidth: 1)
                )
                .shadow(color: AppTheme.primaryDim.opacity(0.28), radius: 12, y: 4)
        }
    }
}

/// 大列表滑过第 8 条后的单次引导：设计稿 — 顶栏菜单正下方、深色胶囊 + 上指三角 + 淡紫字 + 紫色外发光
struct HomeLayoutSwitchGuideBubble: View {
    let title: String
    var onTap: () -> Void

    /// 与 `HomeTopBar` 中 `HStack.padding(.horizontal, 14)` + `chromeIconButton` `frame(40)` 一致，使三角中心对准圆形按钮中心
    private let layoutBarHorizontalPadding: CGFloat = 14
    private let layoutIconSide: CGFloat = 40
    private let pointerWidth: CGFloat = 12
    private let pointerHeight: CGFloat = 7
    private var layoutIconCenterX: CGFloat { layoutBarHorizontalPadding + layoutIconSide / 2 }
    /// 三角左缘 x = 中心 - 半宽，保证尖端落在按钮中轴上
    private var pointerLeading: CGFloat { layoutIconCenterX - pointerWidth / 2 }
    /// 仅胶囊相对三角左移，不改变三角位置
    private let capsuleOffsetX: CGFloat = 12

    /// 近黑深紫底（与稿一致）
    private var capsuleFill: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.07, green: 0.04, blue: 0.12),
                Color(red: 0.11, green: 0.05, blue: 0.18)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// 正文淡薰衣草紫
    private var labelLavender: Color {
        Color(red: 0.82, green: 0.76, blue: 0.94)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 0) {
                Color.clear.frame(width: pointerLeading)
                VStack(alignment: .leading, spacing: -1) {
                    HomeLayoutSwitchGuidePointer()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.09, green: 0.05, blue: 0.15),
                                    Color(red: 0.06, green: 0.035, blue: 0.11)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: pointerWidth, height: pointerHeight)
                        .shadow(color: AppTheme.primary.opacity(0.38), radius: 4, y: -1)

                    Text(title)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .tracking(0.95)
                        .textCase(.uppercase)
                        .foregroundStyle(labelLavender)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(
                            Capsule()
                                .fill(capsuleFill)
                        )
                        .overlay(
                            Capsule()
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            AppTheme.primary.opacity(0.42),
                                            AppTheme.primaryDim.opacity(0.18)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 0.6
                                )
                        )
                        .shadow(color: AppTheme.primary.opacity(0.45), radius: 16, y: 0)
                        .shadow(color: Color.black.opacity(0.4), radius: 8, y: 4)
                        .offset(x: -capsuleOffsetX)
                }
                .fixedSize(horizontal: true, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: 268, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
    }
}

/// 实心三角，顶点朝上，指向顶栏左侧布局按钮
private struct HomeLayoutSwitchGuidePointer: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        p.move(to: CGPoint(x: w * 0.5, y: 0))
        p.addLine(to: CGPoint(x: w, y: h))
        p.addLine(to: CGPoint(x: 0, y: h))
        p.closeSubpath()
        return p
    }
}
