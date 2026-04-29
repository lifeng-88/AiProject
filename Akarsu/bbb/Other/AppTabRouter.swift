//
//  AppTabRouter.swift
//  bbb
//
//  全应用底部 Tab 选中状态，供 Home 金币入口等跳转充值 / 我的
//

import SwiftUI

/// 与 `MyCreationsView` 内筛选分段 `rawValue` 一致（`all` / `generating` / `success`）
enum MyCreationsListFilter: Int {
    case all = 0
    case generating = 1
    case success = 2
}

final class AppTabRouter: ObservableObject {
    @Published var selected: AppTab = .home

    /// `My` Tab 内导航层级（>0 表示已进入二级页，隐藏底部自定义 TabBar）；含子页中再 push（如创作详情）
    @Published var profileNavigationStackCount: Int = 0
    /// `My` 子页内再 push（`MyCreationsView` / `MyLikesView` 详情），iOS 15 下与根 push 分列统计
    @Published var profileDetailPushed: Bool = false
    /// `Recharge` Tab 内导航栈层级
    @Published var rechargeNavigationStackCount: Int = 0
    /// `Home` Tab 内模板详情等 push 层级（如瀑布流进入 `HomeTemplateDetailView`）
    @Published var homeNavigationStackCount: Int = 0
    /// 首页「换脸 / 模板生成」全屏层打开时隐藏底部 TabBar，并与系统 `.sheet` 解耦，避免 iOS 15 上关相册误关该层
    @Published var homeTemplateGenerationPresented: Bool = false

    /// 从其它 Tab（如「我的 · My Likes」）发起全屏生成后，点「浏览其他内容」时切回该 Tab；为 nil 时仅关闭生成层（如回到首页瀑布流）
    @Published var browseOtherGenerationReturnTab: AppTab? = nil

    /// 从首页「生成中」横幅跳转：打开「我的创作」并预选该筛选；由 `MyCreationsView` 应用后调用 `consumeMyCreationsPendingFilter()`
    @Published private(set) var myCreationsPendingFilter: Int?

    /// 已在「我的」Tab 时需刷新令牌，否则 `select(.my)` 被跳过导致无法 push 创作页
    @Published private(set) var myCreationsDeepLinkToken = UUID()

    /// 当前选中 Tab 处于「非根级」导航时隐藏 TabBar（自定义 `safeAreaInset` 与系统 TabView 行为对齐）
    var shouldHideTabBar: Bool {
        switch selected {
        case .my:
            return profileNavigationStackCount > 0 || profileDetailPushed
        case .recharge:
            return rechargeNavigationStackCount > 0
        case .home:
            return homeNavigationStackCount > 0 || homeTemplateGenerationPresented
        }
    }

    /// 不在此处 `withAnimation`：`MainTabView` 已对 Tab 根视图做显隐动画；再包弹簧会与内含 `UIScrollView` 的首页列表叠加重绘，切回 Home 时易卡顿、cell 错位。
    func select(_ tab: AppTab) {
        guard selected != tab else { return }
        selected = tab
    }

    /// 切换到「我的」并打开「我的创作」且选中指定筛选（如生成中）
    func openMyCreations(filter: MyCreationsListFilter) {
        myCreationsPendingFilter = filter.rawValue
        if selected == .my {
            myCreationsDeepLinkToken = UUID()
        } else {
            select(.my)
        }
    }

    func consumeMyCreationsPendingFilter() {
        myCreationsPendingFilter = nil
    }
}
