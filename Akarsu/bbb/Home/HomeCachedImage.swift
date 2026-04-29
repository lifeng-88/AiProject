//
//  HomeCachedImage.swift
//  bbb
//
//  使用 ImageCacheManager（内存 + 磁盘）替代 AsyncImage，首页封面与轮播共用。
//

import SwiftUI
import UIKit

struct HomeCachedImage: View {
    let url: URL?
    var priority: TaskPriority = .userInitiated
    /// 当前 URL 一次加载结束（成功出图或失败）时调用，供轮播等「展示后再切换」逻辑使用
    var onSettled: (() -> Void)? = nil
    /// 仅在内存/磁盘解码得到非空 `UIImage` 时调用；加载失败或得到空图**不**调用（避免扫荡等误认已就绪）
    var onDecoded: (() -> Void)? = nil
    /// `false`（默认）：与首页一致铺满裁剪；`true`：等比例完整显示（如模板详情主图区）。
    var aspectFit: Bool = false
    /// 为 `false` 时加载中不显示转圈，仅透明占位（由外层底色透出，沉浸式视频轮播等避免闪圈）
    var showsLoadingIndicator: Bool = true

    @State private var uiImage: UIImage?
    @State private var didFinishLoad = false

    var body: some View {
        let key = url?.absoluteString
        /// 视图重建时 `@State` 先为 nil，但图常在内存缓存里；同步补一帧避免视频→图轮播先闪 loading。
        let memoryHit = key.flatMap { ImageCacheManager.shared.memoryCachedImage(for: $0) }
        let displayImage = uiImage ?? memoryHit

        Group {
            if let img = displayImage {
                Image(uiImage: img)
                    .resizable()
                    .modifier(HomeCachedImageScaling(aspectFit: aspectFit))
            } else if !didFinishLoad {
                Group {
                    if showsLoadingIndicator {
                        AppTheme.surfaceContainer
                            .overlay(ProgressView().tint(AppTheme.primary))
                    } else {
                        Color.clear
                    }
                }
            } else {
                AppTheme.surfaceContainerHighest
            }
        }
        .task(id: url?.absoluteString) {
            await load()
        }
    }

    private func load() async {
        guard let url else {
            await MainActor.run {
                uiImage = nil
                didFinishLoad = true
                onSettled?()
            }
            return
        }
        let key = url.absoluteString
        /// 先查缓存再决定是否清空 `uiImage`。若每次先置 nil，视频→图阶段轮播时 `HomeCachedImage` 会重建，
        /// 已解码的图片仍在内存/磁盘缓存却先闪 loading 再显示。
        if let cached = await ImageCacheManager.shared.getImage(for: key) {
            await MainActor.run {
                uiImage = cached
                didFinishLoad = true
                onDecoded?()
                onSettled?()
            }
            return
        }
        await MainActor.run {
            didFinishLoad = false
            uiImage = nil
        }
        await ImageCacheManager.shared.preloadImage(urlString: key, priority: priority)
        let loaded = await ImageCacheManager.shared.getImage(for: key)
        await MainActor.run {
            uiImage = loaded
            didFinishLoad = true
            if loaded != nil {
                onDecoded?()
            }
            onSettled?()
        }
    }
}

private struct HomeCachedImageScaling: ViewModifier {
    var aspectFit: Bool
    func body(content: Content) -> some View {
        if aspectFit {
            content.scaledToFit()
        } else {
            content.scaledToFill()
        }
    }
}
