//
//  IOS15Compat.swift
//  bbb
//
//  iOS 15 最低版本下的 SwiftUI API 兼容（16+ API 做可用性分支）
//

import SwiftUI
import UIKit

// MARK: - 导航栏返回与全局着色

/// 统一导航栏返回箭头 / BarButton 主色，以及可复用的自定义返回按钮（易点、轻触反馈）。
enum BBBNavigationChrome {
    /// 在 App 启动时调用一次：系统返回箭头与导航栏按钮使用品牌主色。
    static func applyGlobalTint() {
        UINavigationBar.appearance().tintColor = UIColor(AppTheme.primary)
    }
}

/// 自定义返回（隐藏系统返回时）：仅箭头或「箭头 + 返回」、`contentShape` 保证整块可点，轻触反馈。
struct BBBNavigationBackButton: View {
    /// `true` 时显示本地化「返回」文案；`false` 仅箭头（更紧凑，依赖无障碍读屏标签）。
    var showsLocalizedTitle: Bool = false
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 17, weight: .semibold))
                if showsLocalizedTitle {
                    Text(AppLanguageStore.localized("common.back"))
                        .font(.system(size: 17, weight: .medium))
                }
            }
            .foregroundStyle(AppTheme.primary)
            .frame(minWidth: 44, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppLanguageStore.localized("common.back"))
    }
}

/// 用 `BBBNavigationBackButton` + `common.back` 替换系统返回，使文案与 `AppLanguageStore` 一致（而非仅跟随系统区域设置）。
private struct BBBLocalizedNavigationBackButtonModifier: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    var showsLocalizedTitle: Bool

    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    BBBNavigationBackButton(showsLocalizedTitle: showsLocalizedTitle) {
                        dismiss()
                    }
                }
            }
    }
}

extension View {
    /// 自定义返回按钮，文案与读屏标签使用 `common.back` 的 String Catalog 翻译。
    func bbbLocalizedNavigationBackButton(showsLocalizedTitle: Bool = false) -> some View {
        modifier(BBBLocalizedNavigationBackButtonModifier(showsLocalizedTitle: showsLocalizedTitle))
    }
}

/// iOS 15：`Text.tracking` / `kerning` 仅 iOS 16+，用 `NSAttributedString` 的 `kern` 实现相同字距
enum BBBTrackedText {
    static func text(
        _ string: String,
        size: CGFloat,
        weight: UIFont.Weight = .regular,
        tracking: CGFloat,
        color: Color? = nil,
        italic: Bool = false,
        serif: Bool = false
    ) -> Text {
        let m = NSMutableAttributedString(string: string)
        let r = NSRange(location: 0, length: m.length)
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        let designed: UIFont
        if serif, let d = base.fontDescriptor.withDesign(.serif) {
            designed = UIFont(descriptor: d, size: size)
        } else {
            designed = base
        }
        let font: UIFont
        if italic {
            let traits = designed.fontDescriptor.symbolicTraits.union(.traitItalic)
            if let d = designed.fontDescriptor.withSymbolicTraits(traits) {
                font = UIFont(descriptor: d, size: size)
            } else {
                font = designed
            }
        } else {
            font = designed
        }
        m.addAttribute(.kern, value: tracking, range: r)
        m.addAttribute(.font, value: font, range: r)
        if let color {
            m.addAttribute(.foregroundColor, value: UIColor(color), range: r)
        }
        return Text(AttributedString(m))
    }
}

/// iOS 16+ `listRowSeparatorTint`；低版本不处理
struct ListRowSeparatorTintIfAvailable: ViewModifier {
    let tint: Color
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.listRowSeparatorTint(tint)
        } else {
            content
        }
    }
}

extension View {
    @ViewBuilder
    func bbbNavigationBarBackground(_ color: Color) -> some View {
        if #available(iOS 16.0, *) {
            self.toolbarBackground(color, for: .navigationBar)
        } else {
            self
        }
    }

    @ViewBuilder
    func bbbToolbarHiddenNavigationBar() -> some View {
        if #available(iOS 16.0, *) {
            self.toolbar(.hidden, for: .navigationBar)
        } else {
            self.navigationBarHidden(true)
        }
    }

    @ViewBuilder
    func bbbToolbarVisibleNavigationBar() -> some View {
        if #available(iOS 16.0, *) {
            self.toolbar(.visible, for: .navigationBar)
        } else {
            self.navigationBarHidden(false)
        }
    }

    @ViewBuilder
    func bbbScrollIndicatorsHidden() -> some View {
        if #available(iOS 16.0, *) {
            self.scrollIndicators(.hidden)
        } else {
            self
        }
    }

    @ViewBuilder
    func bbbScrollBounceBasedOnSize() -> some View {
        if #available(iOS 16.4, *) {
            self.scrollBounceBehavior(.basedOnSize)
        } else {
            self
        }
    }

    /// 关闭 ScrollView 子视图超出滚动边界的裁切（如负 offset 角标）；iOS 17+
    @ViewBuilder
    func bbbScrollClipDisabledIfAvailable() -> some View {
        if #available(iOS 17.0, *) {
            self.scrollClipDisabled(true)
        } else {
            self
        }
    }

    @ViewBuilder
    func bbbListScrollContentHidden() -> some View {
        if #available(iOS 16.0, *) {
            self.scrollContentBackground(.hidden)
        } else {
            self
        }
    }

    /// 大卡片式 sheet；iOS 15 无 `presentationDetents`，仅全屏呈现
    @ViewBuilder
    func bbbSheetLargeIfAvailable() -> some View {
        if #available(iOS 16.0, *) {
            self
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        } else {
            self
        }
    }
}

// MARK: - 底部 TabBar 形状

/// 仅顶部两角圆角；贴屏幕底缘时底边为直线，避免四角 `RoundedRectangle` 与 Home Indicator / 屏底裁切冲突。
struct BBBTopRoundedRectangle: Shape {
    var cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(cornerRadius, min(rect.width, rect.height) / 2)
        let bezier = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: [.topLeft, .topRight],
            cornerRadii: CGSize(width: r, height: r)
        )
        return Path(bezier.cgPath)
    }
}
