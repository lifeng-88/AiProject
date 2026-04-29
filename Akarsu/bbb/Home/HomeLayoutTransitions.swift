//
//  HomeLayoutTransitions.swift
//  bbb
//
//  首页沉浸式 / 网格布局切换的叠化 + 位移 + 缩放组合转场（与 `applyLayoutSwitch` 的 spring 配合）
//

import SwiftUI

enum HomeLayoutTransitions {
    /// 进入全屏流：略放大入场；离开时缩小下沉
    static let immersiveChrome: AnyTransition = .asymmetric(
        insertion: .opacity
            .combined(with: .scale(scale: 0.92, anchor: .center)),
        removal: .opacity
            .combined(with: .scale(scale: 1.06, anchor: .center))
            .combined(with: .offset(y: 20))
    )

    /// 进入网格：自底向上、略缩小锚在顶；离开时向上收起
    static let gridChrome: AnyTransition = .asymmetric(
        insertion: .opacity
            .combined(with: .move(edge: .bottom))
            .combined(with: .scale(scale: 0.94, anchor: .top)),
        removal: .opacity
            .combined(with: .move(edge: .top))
            .combined(with: .scale(scale: 0.97, anchor: .bottom))
    )

    /// `applyLayoutSwitch` / 布局按钮共用的 spring，略长于默认以便看清转场
    static var layoutSwitchAnimation: Animation {
        .spring(response: 0.48, dampingFraction: 0.78, blendDuration: 0.12)
    }
}
