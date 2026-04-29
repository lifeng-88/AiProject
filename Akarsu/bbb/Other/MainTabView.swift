//
//  MainTabView.swift
//  bbb
//

import SwiftUI
import UIKit

/// 与 `customTabBar` 内边距 + 图标/文案区大致一致，供子页面在底部 `safeAreaInsets` 异常为 0 时与 TabBar 顶缘对齐留白
enum MainTabBarMetrics {
    /// 与 `customTabBar` 内边距 + 顶圆角栏高度大致一致（底边平直贴底，不含底部「假圆角」占位）
    static let estimatedContentHeight: CGFloat = 78
}

private enum MainTabBarChrome {
    /// 仅上侧两角；下缘与屏底对齐时为 0°，避免四角圆与底安全区冲突
    static let topCornerRadius: CGFloat = 26
}

enum AppTab: Int, CaseIterable {
    case home
    case recharge
    case my

    var title: String {
        switch self {
        case .home: return AppLanguageStore.localized("tab.home")
        case .recharge: return AppLanguageStore.localized("tab.recharge")
        case .my: return AppLanguageStore.localized("tab.my")
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .recharge: return "creditcard.fill"
        case .my: return "person.fill"
        }
    }

    var iconInactive: String {
        switch self {
        case .home: return "house"
        case .recharge: return "creditcard"
        case .my: return "person"
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject private var tabRouter: AppTabRouter

    /// 已进入过的 Tab 保留根视图实例，避免 `switch` 销毁视图导致 Home / Recharge 每次切换都重新 `.task` 拉数。
    /// 未访问过的 Tab 不挂载（如首次不进 Recharge 则不请求套餐列表）。
    @State private var retainedTabs: Set<AppTab> = [.home]

    var body: some View {
        ZStack {
            ZStack {
                tabRoot(.home) { HomeView() }
                tabRoot(.recharge) { RechargeView() }
                tabRoot(.my) { MyProfileView() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        /// 将 TabBar 作为底部 inset；栏背景 `.ignoresSafeArea(edges: .bottom)` 铺满屏幕底缘（含 Home Indicator 区域）
        /// 进入各 Tab 内二级导航时隐藏，避免与内页底部操作区重叠
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !tabRouter.shouldHideTabBar {
                customTabBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: tabRouter.shouldHideTabBar)
        .onAppear {
            retainedTabs.insert(tabRouter.selected)
        }
        .onChange(of: tabRouter.selected) { new in
            DispatchQueue.main.async {
                retainedTabs.insert(new)
            }
        }
        .ignoresSafeArea(.keyboard)
    }

    @ViewBuilder
    private func tabRoot<Content: View>(_ tab: AppTab, @ViewBuilder content: () -> Content) -> some View {
        if retainedTabs.contains(tab) {
            content()
                /// 与 `safeAreaInset` 配合：子页面底边对齐 TabBar 顶边（不延伸到自定义 TabBar 下方）
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                /// 勿对整页（含首页 `UIScrollView`/分页）做 `scaleEffect`：切 Tab 时与 UIKit 滚动布局冲突，易出现卡顿与 cell 错位；仅用透明度切换。
                .opacity(tabRouter.selected == tab ? 1 : 0)
                .allowsHitTesting(tabRouter.selected == tab)
                .accessibilityHidden(tabRouter.selected != tab)
                .zIndex(tabRouter.selected == tab ? 1 : 0)
                .animation(.easeInOut(duration: 0.22), value: tabRouter.selected)
        }
    }

    private var customTabBar: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.rawValue) { tab in
                tabButton(tab)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                AppTheme.tabBarBackground
            }
            .clipShape(topTabBarRoundedShape())
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(AppTheme.outlineVariant.opacity(0.2))
                    .frame(height: 1)
            }
            .shadow(color: Color.purple.opacity(0.12), radius: 20, y: -6)
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private func tabButton(_ tab: AppTab) -> some View {
        let isSelected = tabRouter.selected == tab
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            tabRouter.select(tab)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: isSelected ? tab.icon : tab.iconInactive)
                    .font(.system(size: 22))
                BBBTrackedText.text(tab.title.uppercased(), size: 9, weight: .heavy, tracking: 0.8)
            }
            .foregroundStyle(isSelected ? AppTheme.primary : AppTheme.onSurface.opacity(0.45))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    Capsule()
                        .fill(AppTheme.primary.opacity(0.12))
                        .shadow(color: AppTheme.primary.opacity(0.25), radius: 12)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// iOS 16+ 用 `continuous` 与全局圆角一致；iOS 15 用 `BBBTopRoundedRectangle`
    private func topTabBarRoundedShape() -> AnyShape {
        if #available(iOS 16.0, *) {
            return AnyShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: MainTabBarChrome.topCornerRadius,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: MainTabBarChrome.topCornerRadius,
                    style: .continuous
                )
            )
        }
        return AnyShape(BBBTopRoundedRectangle(cornerRadius: MainTabBarChrome.topCornerRadius))
    }
}

/// 用于 `clipShape` 在 iOS 15/16 间切换不同 `Shape` 具体类型
private struct AnyShape: Shape {
    private let pathBuilder: (CGRect) -> Path

    init<S: Shape>(_ shape: S) {
        pathBuilder = { shape.path(in: $0) }
    }

    func path(in rect: CGRect) -> Path {
        pathBuilder(rect)
    }
}

#Preview {
    MainTabView()
        .environmentObject(UserWalletStore())
        .environmentObject(AppTabRouter())
        .environmentObject(AuthSessionStore())
        .environmentObject(AppLanguageStore())
        .environment(\.locale, Locale.current)
        .preferredColorScheme(.dark)
}
