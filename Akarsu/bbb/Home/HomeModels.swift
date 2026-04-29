//
//  HomeModels.swift
//  bbb
//

import Foundation
import SwiftUI

enum HomeLayoutMode: String, CaseIterable {
    case immersive
    case grid
}

// MARK: - 模板资源 URL（相对路径拼 `ResBaseURL`）

enum HomeTemplateMediaURL {
    static func resolve(_ path: String) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            if let u = URL(string: trimmed) { return u }
            /// 接口偶发未编码空格/非法字符，`URL(string:)` 为 nil 导致整条模板无成片地址
            let spaced = trimmed.replacingOccurrences(of: " ", with: "%20")
            if let u = URL(string: spaced) { return u }
            return nil
        }
        let base = ResBaseURL.effective
        if trimmed.hasPrefix("/") {
            return URL(string: trimmed, relativeTo: URL(string: base))?.absoluteURL
        }
        let sep = base.hasSuffix("/") ? "" : "/"
        return URL(string: base + sep + trimmed)
    }
}

// MARK: - transAnimation 与列表转场顺序

/// - 接口语义：`beforePic(s)` 与 `transAnimation` 逗号片段共同构成时间线；**不含** `afterPic` / `afterVideo`（由该字段承载目标帧）。
/// - 客户端 T2/T3：`transAnimation` **非空**时解析顺序为 **转场片段优先、再 before**，沉浸式/预加载与「先播转场」一致。
/// - 为空：图片模板以 `afterPic` 收尾；视频类模板仅 before → `afterVideo`。
private enum HomeTransAnimationMediaParsing {
    /// 从 `transAnimation` 拆出资源路径片段（纯数字视为间隔而非路径）
    static func transAnimationPathSegments(_ raw: String) -> [String] {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return [] }
        var out: [String] = []
        for seg in t.split(separator: ",") {
            let s = seg.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !s.isEmpty else { continue }
            if isLikelyIntervalOnlyToken(s) { continue }
            out.append(s)
        }
        return out
    }

    static func isLikelyIntervalOnlyToken(_ s: String) -> Bool {
        if s.contains("/") || s.contains(":") { return false }
        let lower = s.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") { return false }
        return Double(s) != nil
    }

    static func urlLooksLikeVideo(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if !ext.isEmpty, ["mp4", "mov", "m4v", "webm", "mkv"].contains(ext) { return true }
        /// CDN 签名 URL 常见无 pathExtension，但路径或 query 中含扩展名片段
        let s = url.absoluteString.lowercased()
        if s.contains(".mp4") || s.contains(".mov") || s.contains(".m4v") || s.contains(".webm") || s.contains(".mkv") { return true }
        if s.contains(".m3u8") || s.contains("format=mp4") || s.contains("content-type=video") { return true }
        return false
    }

    static func splitImageAndVideoURLs(_ urls: [URL]) -> (images: [URL], video: URL?) {
        var images: [URL] = []
        var video: URL?
        for u in urls {
            if urlLooksLikeVideo(u) {
                if video == nil { video = u }
            } else {
                images.append(u)
            }
        }
        return (images, video)
    }

    /// T3：`transAnimation` 非空时**先**转场片段、再 `beforePics`，避免首包/封面误用 before。
    static func orderedRawPathsVideo(beforePics: [String], transAnimationRaw: String) -> [String] {
        let ta = transAnimationRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        var paths: [String] = []
        if !ta.isEmpty {
            for seg in transAnimationPathSegments(ta) where !paths.contains(seg) {
                paths.append(seg)
            }
            for p in beforePics {
                let s = p.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !s.isEmpty, !paths.contains(s) else { continue }
                paths.append(s)
            }
        } else {
            for p in beforePics {
                let s = p.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !s.isEmpty, !paths.contains(s) else { continue }
                paths.append(s)
            }
        }
        return paths
    }

    /// T2：同上，单张 `beforePic`。
    static func orderedRawPathsDancing(beforePic: String, transAnimationRaw: String) -> [String] {
        let ta = transAnimationRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        var paths: [String] = []
        if !ta.isEmpty {
            for seg in transAnimationPathSegments(ta) where !paths.contains(seg) {
                paths.append(seg)
            }
            let before = beforePic.trimmingCharacters(in: .whitespacesAndNewlines)
            if !before.isEmpty, !paths.contains(before) {
                paths.append(before)
            }
        } else {
            let before = beforePic.trimmingCharacters(in: .whitespacesAndNewlines)
            if !before.isEmpty {
                paths.append(before)
            }
        }
        return paths
    }

    /// 首页瀑布流 T2/T3 cell：**只**解析 `transAnimation` 逗号片段，**不**包含 `beforePic` / `beforePics`；字段为空时返回空（封面走 `afterSnapshot` 或成片视频，不拉 before）。
    static func gridCellPathsTransAnimationOnly(transAnimationRaw: String) -> [String] {
        let ta = transAnimationRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ta.isEmpty else { return [] }
        var paths: [String] = []
        for seg in transAnimationPathSegments(ta) where !paths.contains(seg) {
            paths.append(seg)
        }
        return paths
    }

    /// 与 `HomeFeedItem.immersivePrimaryLoopVideoURL` / 网格预览成片 URL 一致：有转场字段则只认字段内首个视频或 `afterVideo`，避免误用 before 段视频。
    static func t2t3PlaybackVideoURL(
        transAnimationRaw: String,
        afterVideoURL: URL?,
        transFieldFirstVideo: URL?,
        mergedTimelineFirstVideo: URL?
    ) -> URL? {
        let ta = transAnimationRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !ta.isEmpty {
            if let v = transFieldFirstVideo { return v }
            return afterVideoURL ?? mergedTimelineFirstVideo
        }
        return mergedTimelineFirstVideo ?? afterVideoURL
    }
}

/// 沉浸式轮播：与 `transAnimation` 解析共用同一套「是否视频 URL」判断
enum HomeImmersiveMediaURL {
    static func isVideo(_ url: URL) -> Bool {
        HomeTransAnimationMediaParsing.urlLooksLikeVideo(url)
    }
}

struct HomeFeedItem: Identifiable {
    let id: String
    /// 网格封面等：取轮播首帧或单图
    let imageURL: URL?
    /// 列表全屏轮播图（接口 before/after 等路径解析结果，去重保序）
    let slideshowURLs: [URL]
    /// 轮播间隔（秒）；来自接口 `transAnimation` 可解析为数字时采用，否则默认
    let slideshowInterval: TimeInterval
    let mediaIcon: String
    /// 底部主按钮文案
    let actionTitle: String
    /// 对应 `/v1/t1|t2|t3` 资源，用于点赞等接口
    let templateKind: TemplateResourceKind
    /// T2/T3 模板 `afterVideo` 解析结果；非空时沉浸式列表优先循环播放视频
    let playbackVideoURL: URL?
    /// T2/T3：`transAnimation` 中解析出的视频 URL（若有）；用于非当前条封面取 trans 视频首帧。
    let transAnimationVideoURL: URL?
    /// 消耗金币（列表主按钮右侧展示）
    let consumedCoins: Int
    /// 接口 `transAnimation`（trim）；驱动「before → 目标」与轮播间隔解析
    let transAnimation: String
    /// T2/T3：完整时间线 URL（含视频段）；列表侧由 `orderedRawPaths*` 拼出（`transAnimation` 非空时 **trans 先于** before）。详情模型另有拼出时同理。
    let carouselTimelineURLs: [URL]
    /// T2/T3：接口 `afterVideo` 单独解析；`transAnimation` 为空时沉浸式单列循环**只**用此地址（不用 before 里误识别的视频）。
    let afterVideoURL: URL?

    /// 沉浸式背景配图序列（T2/T3 与 `slideshowURLs` 一致；trans 非空时已为 **转场配图优先**）
    var immersiveImageURLs: [URL] {
        if !slideshowURLs.isEmpty { return slideshowURLs }
        return [imageURL].compactMap { $0 }
    }

    /// 首页沉浸式列表：`transAnimation` 字段内**静图** URL（T2/T3）；T1 与 `immersiveImageURLs` 相同。不含 beforePic，避免无成片视频时误走双图扫荡。
    var immersiveListBackdropImageURLs: [URL] {
        guard templateKind == .t2 || templateKind == .t3 else { return immersiveImageURLs }
        return transAnimationFieldOnlyURLs.filter { !HomeImmersiveMediaURL.isVideo($0) }
    }

    /// T2/T3：按接口 `transAnimation` 片段顺序排列的媒体 URL（图 + 视频混排，与接口逗号分隔顺序一致）。
    /// 无可用片段时：用「轮播图序列 + 成片视频」拼一条时间线（避免只取封面或只取成片导致无法轮播）。
    var immersiveTransAnimationCarouselURLs: [URL] {
        guard templateKind == .t2 || templateKind == .t3 else { return [] }
        if !carouselTimelineURLs.isEmpty {
            return carouselTimelineURLs
        }
        let ta = transAnimation.trimmingCharacters(in: .whitespacesAndNewlines)
        var transPaths: [String] = []
        if !ta.isEmpty {
            for seg in HomeTransAnimationMediaParsing.transAnimationPathSegments(ta) where !transPaths.contains(seg) {
                transPaths.append(seg)
            }
        }
        let ordered = Self.uniqueResolvedMediaPaths(transPaths)
        if !ordered.isEmpty { return ordered }

        var merged: [URL] = []
        var seen = Set<String>()
        func appendUnique(_ url: URL?) {
            guard let url else { return }
            let s = url.absoluteString
            guard seen.insert(s).inserted else { return }
            merged.append(url)
        }
        for u in slideshowURLs {
            appendUnique(u)
        }
        if merged.isEmpty {
            appendUnique(imageURL)
        }
        appendUnique(playbackVideoURL)
        return merged
    }

    /// 仅接口 `transAnimation` 逗号片段解析出的 URL（不含 `beforePic` / `beforePics`）；与「转场动画」段落一致。
    var transAnimationFieldOnlyURLs: [URL] {
        guard templateKind == .t2 || templateKind == .t3 else { return [] }
        let ta = transAnimation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ta.isEmpty else { return [] }
        var paths: [String] = []
        for seg in HomeTransAnimationMediaParsing.transAnimationPathSegments(ta) where !paths.contains(seg) {
            paths.append(seg)
        }
        return Self.uniqueResolvedMediaPaths(paths)
    }

    /// 模板详情预览主图占位：优先 `transAnimation` 首段（静图或视频解码首帧）；否则回退完整时间线首段。
    var templateDetailPreviewPlaceholderURL: URL? {
        guard templateKind == .t2 || templateKind == .t3 else { return nil }
        if let u = transAnimationFieldOnlyURLs.first { return u }
        return immersiveTransAnimationCarouselURLs.first
    }

    /// 沉浸式单列 T2/T3：与 `immersivePrimaryLoopVideoURL` 一致，用于非当前条首帧解码；再回退旧轮播序列。
    var immersiveStoppedPosterVideoURL: URL? {
        guard templateKind == .t2 || templateKind == .t3 else { return nil }
        if let u = immersivePrimaryLoopVideoURL { return u }
        let carousel = immersiveTransAnimationCarouselURLs
        if let v = carousel.first(where: { HomeImmersiveMediaURL.isVideo($0) }) { return v }
        return transAnimationVideoURL ?? playbackVideoURL
    }

    /// 沉浸式单列：首帧 + 静音循环的**唯一**成片（`transAnimation` 非空 → 字段逗号片段内首个视频；片段中无视频则 `afterVideo`；`transAnimation` 为空 → 仅 `afterVideo` / 再回退）。
    var immersivePrimaryLoopVideoURL: URL? {
        guard templateKind == .t2 || templateKind == .t3 else { return nil }
        let ta = transAnimation.trimmingCharacters(in: .whitespacesAndNewlines)
        if !ta.isEmpty {
            if let v = Self.firstVideoFromTransAnimationFieldOnly(transAnimation) {
                return v
            }
            /// 字段非空但片段里只有图、无视频 URL：与「空字段走成片」一致，优先 `afterVideo`，避免误用时间线里 `before` 段视频。
            if let u = afterVideoURL ?? transAnimationVideoURL ?? playbackVideoURL {
                return u
            }
        } else if let u = afterVideoURL ?? playbackVideoURL {
            return u
        }
        /// 与 `HomeFeedItem` 构建时一致：主链均空时再扫完整 `carouselTimelineURLs`（避免扩展名识别遗漏导致双列/沉浸式均无 URL）
        return carouselTimelineURLs.first(where: { HomeImmersiveMediaURL.isVideo($0) })
    }

    init(
        id: String = UUID().uuidString,
        imageURL: URL?,
        slideshowURLs: [URL] = [],
        slideshowInterval: TimeInterval = 3.2,
        mediaIcon: String,
        actionTitle: String = AppLanguageStore.localized("home.action.swap_face"),
        templateKind: TemplateResourceKind = .t1,
        playbackVideoURL: URL? = nil,
        transAnimationVideoURL: URL? = nil,
        consumedCoins: Int = 0,
        transAnimation: String = "",
        carouselTimelineURLs: [URL] = [],
        afterVideoURL: URL? = nil
    ) {
        self.id = id
        let resolved = slideshowURLs.isEmpty ? [imageURL].compactMap { $0 } : slideshowURLs
        self.slideshowURLs = resolved
        self.imageURL = imageURL ?? resolved.first
        self.slideshowInterval = slideshowInterval
        self.mediaIcon = mediaIcon
        self.actionTitle = actionTitle
        self.templateKind = templateKind
        self.playbackVideoURL = playbackVideoURL
        self.transAnimationVideoURL = transAnimationVideoURL
        self.consumedCoins = consumedCoins
        self.transAnimation = transAnimation
        self.carouselTimelineURLs = carouselTimelineURLs
        self.afterVideoURL = afterVideoURL
    }

    /// 点赞状态在客户端集合中的键（区分 t1/t2/t3 下同 id 的极端情况）
    var likeStateKey: String {
        "\(templateKind.rawValue):\(id)"
    }

    /// T2/T3：与双列 `HomeGridCardItem` 同源字段，供沉浸式列表复用同一套媒体/角标 UI
    var gridMirrorCardItem: HomeGridCardItem? {
        guard templateKind == .t2 || templateKind == .t3 else { return nil }
        return HomeGridCardItem(
            id: id,
            imageURL: imageURL,
            previewVideoURL: playbackVideoURL,
            gridSlideshowURLs: slideshowURLs,
            gridTransAnimationVideoURL: transAnimationVideoURL,
            gridVideoTransAnimationImageURLs: slideshowURLs,
            gridCarouselTimelineURLs: carouselTimelineURLs,
            gridSlideshowInterval: slideshowInterval,
            topTag: nil,
            bottomLeft: .coins(consumedCoins),
            aspectRatio: 9 / 16,
            templateKind: templateKind,
            transAnimation: transAnimation
        )
    }

    /// 与瀑布流 `HomeGridCard` / `HomeGridCardSharedMediaStack` 同源媒体字段；顶角标与左下角金币与列表 cell 的 `chrome` 一致。
    func gridCardItemMatchingList(chrome: HomeGridCardItem) -> HomeGridCardItem {
        if templateKind == .t2 || templateKind == .t3, let m = gridMirrorCardItem {
            return HomeGridCardItem(
                id: m.id,
                imageURL: m.imageURL,
                previewVideoURL: m.previewVideoURL,
                gridSlideshowURLs: m.gridSlideshowURLs,
                gridTransAnimationVideoURL: m.gridTransAnimationVideoURL,
                gridVideoTransAnimationImageURLs: m.gridVideoTransAnimationImageURLs,
                gridCarouselTimelineURLs: m.gridCarouselTimelineURLs,
                gridSlideshowInterval: m.gridSlideshowInterval,
                topTag: chrome.topTag,
                bottomLeft: chrome.bottomLeft,
                aspectRatio: chrome.aspectRatio,
                templateKind: m.templateKind,
                transAnimation: m.transAnimation
            )
        }
        return HomeGridCardItem(
            id: id,
            imageURL: imageURL,
            previewVideoURL: nil,
            gridSlideshowURLs: slideshowURLs,
            gridTransAnimationVideoURL: nil,
            gridVideoTransAnimationImageURLs: [],
            gridCarouselTimelineURLs: [],
            gridSlideshowInterval: slideshowInterval,
            topTag: chrome.topTag,
            bottomLeft: chrome.bottomLeft,
            aspectRatio: chrome.aspectRatio,
            templateKind: .t1,
            transAnimation: transAnimation
        )
    }

    /// 解析 `transAnimation`：纯数字视为秒；大于 50 且无小数点时按毫秒
    fileprivate static func slideshowInterval(fromTransAnimation raw: String) -> TimeInterval {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let v = Double(t) else { return 3.2 }
        if v > 0.25, v < 120, v <= 50 || t.contains(".") {
            return v
        }
        if v >= 50, v <= 600_000 {
            return min(max(v / 1000.0, 0.8), 30)
        }
        return 3.2
    }

    fileprivate static func uniqueResolvedMediaPaths(_ paths: [String]) -> [URL] {
        var seen = Set<String>()
        var out: [URL] = []
        for p in paths {
            let s = p.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !s.isEmpty, seen.insert(s).inserted, let u = HomeTemplateMediaURL.resolve(s) else { continue }
            out.append(u)
        }
        return out
    }

    /// 仅从接口 `transAnimation` 逗号片段解析出的 URL 序列里取首个视频（不含 before）。
    fileprivate static func firstVideoFromTransAnimationFieldOnly(_ transAnimationRaw: String) -> URL? {
        let t = transAnimationRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        let segs = HomeTransAnimationMediaParsing.transAnimationPathSegments(t)
        let urls = uniqueResolvedMediaPaths(segs)
        return HomeTransAnimationMediaParsing.splitImageAndVideoURLs(urls).video
    }
}

extension HomeFeedItem {
    /// 由 `TemplateAPI.getImageTemplates`（T1）条目构建
    init(imageTemplate: ImageTemplate) {
        self.id = imageTemplate.id
        let ta = imageTemplate.transAnimation.trimmingCharacters(in: .whitespacesAndNewlines)
        var paths: [String] = []
        for p in imageTemplate.beforePics {
            let s = p.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !s.isEmpty, !paths.contains(s) else { continue }
            paths.append(s)
        }
        if !ta.isEmpty {
            for seg in HomeTransAnimationMediaParsing.transAnimationPathSegments(ta) where !paths.contains(seg) {
                paths.append(seg)
            }
        }
        /// `afterPic` 为接口单独字段（目标成片），**不在** `transAnimation` 逗号串内；`transAnimation` 非空时也必须追加，否则瀑布流/沉浸式扫荡的 `last` 不是成片，表现为 after 缺图或一直加载。
        let after = imageTemplate.afterPic.trimmingCharacters(in: .whitespacesAndNewlines)
        if !after.isEmpty, !paths.contains(after) {
            paths.append(after)
        }
        let urls = Self.uniqueResolvedMediaPaths(paths)
        self.slideshowURLs = urls
        self.imageURL = urls.first
        self.slideshowInterval = Self.slideshowInterval(fromTransAnimation: imageTemplate.transAnimation)
        self.mediaIcon = "photo.fill"
        self.actionTitle = AppLanguageStore.localized("home.action.swap_face")
        self.templateKind = .t1
        self.playbackVideoURL = nil
        self.consumedCoins = Self.parseConsumedGold(imageTemplate.consumedGold)
        self.transAnimation = ta
        self.transAnimationVideoURL = nil
        self.carouselTimelineURLs = []
        self.afterVideoURL = nil
    }

    /// 由 `TemplateAPI.getVideoTemplates`（T3）条目构建；`transAnimation` 非空时路径 **trans 先于** `beforePics`。
    init(videoTemplate: VideoTemplate) {
        self.id = videoTemplate.id
        let ta = videoTemplate.transAnimation.trimmingCharacters(in: .whitespacesAndNewlines)
        let afterVideoRaw = videoTemplate.afterVideo.trimmingCharacters(in: .whitespacesAndNewlines)
        let afterResolved = HomeTemplateMediaURL.resolve(afterVideoRaw)

        let rawPaths = HomeTransAnimationMediaParsing.orderedRawPathsVideo(
            beforePics: videoTemplate.beforePics,
            transAnimationRaw: videoTemplate.transAnimation
        )
        let urls = Self.uniqueResolvedMediaPaths(rawPaths)
        let split = HomeTransAnimationMediaParsing.splitImageAndVideoURLs(urls)
        let transFieldFirstVideo = Self.firstVideoFromTransAnimationFieldOnly(videoTemplate.transAnimation)

        self.slideshowURLs = split.images
        self.imageURL = split.images.first
            ?? HomeTemplateMediaURL.resolve(videoTemplate.afterSnapshot ?? "")
        self.slideshowInterval = Self.slideshowInterval(fromTransAnimation: videoTemplate.transAnimation)
        self.mediaIcon = "film.fill"
        self.actionTitle = AppLanguageStore.localized("home.action.create_video")
        self.templateKind = .t3
        self.transAnimationVideoURL = !ta.isEmpty ? transFieldFirstVideo : split.video
        self.playbackVideoURL = HomeTransAnimationMediaParsing.t2t3PlaybackVideoURL(
            transAnimationRaw: videoTemplate.transAnimation,
            afterVideoURL: afterResolved,
            transFieldFirstVideo: transFieldFirstVideo,
            mergedTimelineFirstVideo: split.video
        )
        self.consumedCoins = Self.parseConsumedGold(videoTemplate.consumedGold)
        self.transAnimation = ta
        self.carouselTimelineURLs = urls
        self.afterVideoURL = afterResolved
    }

    /// 由 `TemplateAPI.getDancingTemplates`（T2）条目构建；`transAnimation` 非空时路径 **trans 先于** `beforePic`。
    init(dancingTemplate: DancingTemplate) {
        self.id = dancingTemplate.id
        let ta = dancingTemplate.transAnimation.trimmingCharacters(in: .whitespacesAndNewlines)
        let afterVideoRaw = dancingTemplate.afterVideo.trimmingCharacters(in: .whitespacesAndNewlines)
        let afterResolved = HomeTemplateMediaURL.resolve(afterVideoRaw)

        let rawPaths = HomeTransAnimationMediaParsing.orderedRawPathsDancing(
            beforePic: dancingTemplate.beforePic,
            transAnimationRaw: dancingTemplate.transAnimation
        )
        let urls = Self.uniqueResolvedMediaPaths(rawPaths)
        let split = HomeTransAnimationMediaParsing.splitImageAndVideoURLs(urls)
        let transFieldFirstVideo = Self.firstVideoFromTransAnimationFieldOnly(dancingTemplate.transAnimation)

        self.slideshowURLs = split.images
        self.imageURL = split.images.first
            ?? HomeTemplateMediaURL.resolve(dancingTemplate.afterSnapshot ?? dancingTemplate.beforePic)
        self.slideshowInterval = Self.slideshowInterval(fromTransAnimation: dancingTemplate.transAnimation)
        self.mediaIcon = "figure.dance"
        self.actionTitle = AppLanguageStore.localized("home.action.start_dance")
        self.templateKind = .t2
        self.transAnimationVideoURL = !ta.isEmpty ? transFieldFirstVideo : split.video
        self.playbackVideoURL = HomeTransAnimationMediaParsing.t2t3PlaybackVideoURL(
            transAnimationRaw: dancingTemplate.transAnimation,
            afterVideoURL: afterResolved,
            transFieldFirstVideo: transFieldFirstVideo,
            mergedTimelineFirstVideo: split.video
        )
        self.consumedCoins = Self.parseConsumedGold(dancingTemplate.consumedGold)
        self.transAnimation = ta
        self.carouselTimelineURLs = urls
        self.afterVideoURL = afterResolved
    }

    fileprivate static func parseConsumedGold(_ s: String) -> Int {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if let v = Int(t) { return v }
        if let d = Double(t) { return Int(d.rounded()) }
        return 0
    }
}

enum HomeGridTopTag: Hashable {
    case free
    case hot
    case new
}

enum HomeGridBottomLeft: Hashable {
    case coins(Int)
    case locked
}

struct HomeGridCardItem: Identifiable, Hashable {
    let id: String
    let imageURL: URL?
    /// 瀑布流格内静音循环预览（T2/T3 的 `afterVideo`）；与封面图叠加，类似小红书 feed。
    let previewVideoURL: URL?
    /// T1：与 `HomeFeedItem.slideshowURLs` 同源，用于瀑布流格内转场（before…+after）；无视频模板时使用。
    let gridSlideshowURLs: [URL]
    /// T2/T3：仅由接口 `transAnimation` 逗号片段解析出的时间线里**首个视频**（不含 `beforePic` / `beforePics`）；瀑布流 `gridPlaybackVideoURL` 优先用它。
    let gridTransAnimationVideoURL: URL?
    /// T2/T3：`transAnimation` 中解析出的配图 URL（无 trans 内视频时的静态兜底）。
    let gridVideoTransAnimationImageURLs: [URL]
    /// T2/T3：完整时间线 URL（与 `HomeFeedItem.carouselTimelineURLs` 同源；trans 非空时 **trans 先于** before）。
    let gridCarouselTimelineURLs: [URL]
    /// T1：轮播/转场间隔（秒），来自 `transAnimation`，与沉浸式列表一致。
    let gridSlideshowInterval: TimeInterval
    let topTag: HomeGridTopTag?
    let bottomLeft: HomeGridBottomLeft
    /// 对应 `/v1/t1|t2|t3`，与 `HomeFeedItem` 一致
    let templateKind: TemplateResourceKind
    let transAnimation: String
    /// 宽:高；双列列表由 `HomeGridFeedView.cellAspectRatio` 统一控制，此项仅作数据保留或自定义用途。
    var aspectRatio: CGFloat = 9 / 16

    var likeStateKey: String {
        "\(templateKind.rawValue):\(id)"
    }

    /// 网格列表 T2/T3：优先 `previewVideoURL`（与 `HomeFeedItem` 的 `t2t3PlaybackVideoURL` / 合并时间线一致）；再 `transAnimation` 字段首个视频；最后扫格内时间线。
    var gridPlaybackVideoURL: URL? {
        if let v = previewVideoURL { return v }
        if let v = gridTransAnimationVideoURL { return v }
        guard templateKind == .t2 || templateKind == .t3 else { return nil }
        return gridCarouselTimelineURLs.first(where: { HomeImmersiveMediaURL.isVideo($0) })
    }

    /// T2/T3：与 `HomeFeedItem.immersiveTransAnimationCarouselURLs` 一致，用于瀑布流格内多段图/视频轮播。
    var gridTransAnimationCarouselURLs: [URL] {
        guard templateKind == .t2 || templateKind == .t3 else { return [] }
        if !gridCarouselTimelineURLs.isEmpty {
            return gridCarouselTimelineURLs
        }
        let ta = transAnimation.trimmingCharacters(in: .whitespacesAndNewlines)
        var transPaths: [String] = []
        if !ta.isEmpty {
            for seg in HomeTransAnimationMediaParsing.transAnimationPathSegments(ta) where !transPaths.contains(seg) {
                transPaths.append(seg)
            }
        }
        let ordered = Self.uniqueResolvedMediaPaths(transPaths)
        if !ordered.isEmpty { return ordered }

        var merged: [URL] = []
        var seen = Set<String>()
        func appendUnique(_ url: URL?) {
            guard let url else { return }
            let s = url.absoluteString
            guard seen.insert(s).inserted else { return }
            merged.append(url)
        }
        for u in gridSlideshowURLs {
            appendUnique(u)
        }
        if merged.isEmpty {
            appendUnique(imageURL)
        }
        appendUnique(previewVideoURL)
        return merged
    }

    /// 仅接口 `transAnimation` 逗号片段（不含 `beforePic` / `beforePics`）。
    var gridTransAnimationFieldOnlyURLs: [URL] {
        guard templateKind == .t2 || templateKind == .t3 else { return [] }
        let ta = transAnimation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ta.isEmpty else { return [] }
        var paths: [String] = []
        for seg in HomeTransAnimationMediaParsing.transAnimationPathSegments(ta) where !paths.contains(seg) {
            paths.append(seg)
        }
        return Self.uniqueResolvedMediaPaths(paths)
    }

    /// 瀑布流 cell 底图：优先 `transAnimation` 首段；无字段片段时优先 trans 内视频 / 成片首帧，再退回时间线首段（与详情页占位一致）。
    var gridTransAnimationFirstPlaceholderURL: URL? {
        guard templateKind == .t2 || templateKind == .t3 else { return nil }
        if let u = gridTransAnimationFieldOnlyURLs.first { return u }
        if let v = gridTransAnimationVideoURL { return v }
        if let v = previewVideoURL { return v }
        return gridTransAnimationCarouselURLs.first
    }

    init(
        id: String = UUID().uuidString,
        imageURL: URL?,
        previewVideoURL: URL? = nil,
        gridSlideshowURLs: [URL] = [],
        gridTransAnimationVideoURL: URL? = nil,
        gridVideoTransAnimationImageURLs: [URL] = [],
        gridCarouselTimelineURLs: [URL] = [],
        gridSlideshowInterval: TimeInterval = 3.2,
        topTag: HomeGridTopTag?,
        bottomLeft: HomeGridBottomLeft,
        aspectRatio: CGFloat = 9 / 16,
        templateKind: TemplateResourceKind = .t1,
        transAnimation: String = ""
    ) {
        self.id = id
        self.imageURL = imageURL
        self.previewVideoURL = previewVideoURL
        self.gridSlideshowURLs = gridSlideshowURLs
        self.gridTransAnimationVideoURL = gridTransAnimationVideoURL
        self.gridVideoTransAnimationImageURLs = gridVideoTransAnimationImageURLs
        self.gridCarouselTimelineURLs = gridCarouselTimelineURLs
        self.gridSlideshowInterval = gridSlideshowInterval
        self.topTag = topTag
        self.bottomLeft = bottomLeft
        self.aspectRatio = aspectRatio
        self.templateKind = templateKind
        self.transAnimation = transAnimation
    }

    /// 兼容旧调用点（`imageURL` 后紧跟 `topTag`，无 `previewVideoURL`）；与「喜欢」列表等一致。
    init(
        id: String = UUID().uuidString,
        imageURL: URL?,
        topTag: HomeGridTopTag?,
        bottomLeft: HomeGridBottomLeft,
        aspectRatio: CGFloat = 9 / 16,
        templateKind: TemplateResourceKind = .t1
    ) {
        self.init(
            id: id,
            imageURL: imageURL,
            previewVideoURL: nil,
            gridSlideshowURLs: [],
            gridTransAnimationVideoURL: nil,
            gridVideoTransAnimationImageURLs: [],
            gridCarouselTimelineURLs: [],
            gridSlideshowInterval: 3.2,
            topTag: topTag,
            bottomLeft: bottomLeft,
            aspectRatio: aspectRatio,
            templateKind: templateKind,
            transAnimation: ""
        )
    }
}

extension HomeGridCardItem {
    /// 由 `TemplateAPI.getImageTemplates`（T1）条目构建（双列网格统一比例见 `HomeGridFeedView.cellAspectRatio`）
    init(imageTemplate: ImageTemplate, aspectRatio: CGFloat = 9 / 16) {
        self.id = imageTemplate.id
        let ta = imageTemplate.transAnimation.trimmingCharacters(in: .whitespacesAndNewlines)
        var paths: [String] = []
        for p in imageTemplate.beforePics {
            let s = p.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !s.isEmpty, !paths.contains(s) else { continue }
            paths.append(s)
        }
        if !ta.isEmpty {
            for seg in HomeTransAnimationMediaParsing.transAnimationPathSegments(ta) where !paths.contains(seg) {
                paths.append(seg)
            }
        }
        let after = imageTemplate.afterPic.trimmingCharacters(in: .whitespacesAndNewlines)
        if !after.isEmpty, !paths.contains(after) {
            paths.append(after)
        }
        let urls = Self.uniqueResolvedMediaPaths(paths)
        self.gridSlideshowURLs = urls
        self.gridTransAnimationVideoURL = nil
        self.gridVideoTransAnimationImageURLs = []
        self.gridCarouselTimelineURLs = []
        self.imageURL = urls.first
        self.gridSlideshowInterval = Self.gridSlideshowInterval(fromTransAnimation: imageTemplate.transAnimation)
        self.previewVideoURL = nil
        self.topTag = nil
        self.bottomLeft = .coins(Self.parseGold(imageTemplate.consumedGold))
        self.aspectRatio = aspectRatio
        self.templateKind = .t1
        self.transAnimation = ta
    }

    /// 由 `TemplateAPI.getVideoTemplates`（T3）条目构建。**首页 cell 不加载 beforePic**，仅 `transAnimation` 片段 + 成片；与 `HomeFeedItem`（含 before 时间线）不同源。
    init(videoTemplate: VideoTemplate, aspectRatio: CGFloat = 9 / 16) {
        self.id = videoTemplate.id
        let ta = videoTemplate.transAnimation.trimmingCharacters(in: .whitespacesAndNewlines)
        let afterRaw = videoTemplate.afterVideo.trimmingCharacters(in: .whitespacesAndNewlines)
        let afterResolved = afterRaw.isEmpty ? nil : HomeTemplateMediaURL.resolve(afterRaw)

        let rawPaths = HomeTransAnimationMediaParsing.gridCellPathsTransAnimationOnly(transAnimationRaw: videoTemplate.transAnimation)
        let urls = Self.uniqueResolvedMediaPaths(rawPaths)
        let transSplit = HomeTransAnimationMediaParsing.splitImageAndVideoURLs(urls)
        let transFieldFirstVideo = Self.firstVideoURLFromTransAnimationFieldOnly(videoTemplate.transAnimation)

        /// `mergedTimelineFirstVideo` 必须与 `HomeFeedItem(videoTemplate:)` 一致：用 **含 before 的完整时间线** 解析首个视频，否则仅 trans 窄时间线可能漏掉成片，导致网格不播而沉浸式可播/双端均不播。
        let feedTimelinePaths = HomeTransAnimationMediaParsing.orderedRawPathsVideo(
            beforePics: videoTemplate.beforePics,
            transAnimationRaw: videoTemplate.transAnimation
        )
        let feedTimelineUrls = Self.uniqueResolvedMediaPaths(feedTimelinePaths)
        let feedMergedVideo = HomeTransAnimationMediaParsing.splitImageAndVideoURLs(feedTimelineUrls).video

        self.gridCarouselTimelineURLs = urls
        /// 瀑布流静音预览：必须与接口 `transAnimation` 字段一致，不能用「before+trans 整条里第一个视频」误代（before 里若有视频会抢首段）。
        self.gridTransAnimationVideoURL = transFieldFirstVideo
        self.gridVideoTransAnimationImageURLs = transSplit.images
        /// 与播放态底层轮播一致，便于预取；T1 仍用合并序列。
        self.gridSlideshowURLs = transSplit.images
        self.imageURL = transSplit.images.first
            ?? HomeTemplateMediaURL.resolve(videoTemplate.afterSnapshot ?? "")
        self.gridSlideshowInterval = Self.gridSlideshowInterval(fromTransAnimation: videoTemplate.transAnimation)
        self.topTag = nil
        self.bottomLeft = .coins(Self.parseGold(videoTemplate.consumedGold))
        self.aspectRatio = aspectRatio
        self.templateKind = .t3
        self.transAnimation = ta
        self.previewVideoURL = HomeTransAnimationMediaParsing.t2t3PlaybackVideoURL(
            transAnimationRaw: videoTemplate.transAnimation,
            afterVideoURL: afterResolved,
            transFieldFirstVideo: transFieldFirstVideo,
            mergedTimelineFirstVideo: feedMergedVideo
        )
    }

    /// 由 `TemplateAPI.getDancingTemplates`（T2）条目构建。**首页 cell 不加载 beforePic**，仅 `transAnimation` 片段 + 成片。
    init(dancingTemplate: DancingTemplate, aspectRatio: CGFloat = 9 / 16) {
        self.id = dancingTemplate.id
        let ta = dancingTemplate.transAnimation.trimmingCharacters(in: .whitespacesAndNewlines)
        let afterRaw = dancingTemplate.afterVideo.trimmingCharacters(in: .whitespacesAndNewlines)
        let afterResolved = afterRaw.isEmpty ? nil : HomeTemplateMediaURL.resolve(afterRaw)

        let rawPaths = HomeTransAnimationMediaParsing.gridCellPathsTransAnimationOnly(transAnimationRaw: dancingTemplate.transAnimation)
        let urls = Self.uniqueResolvedMediaPaths(rawPaths)
        let transSplit = HomeTransAnimationMediaParsing.splitImageAndVideoURLs(urls)
        let transFieldFirstVideo = Self.firstVideoURLFromTransAnimationFieldOnly(dancingTemplate.transAnimation)

        let feedTimelinePaths = HomeTransAnimationMediaParsing.orderedRawPathsDancing(
            beforePic: dancingTemplate.beforePic,
            transAnimationRaw: dancingTemplate.transAnimation
        )
        let feedTimelineUrls = Self.uniqueResolvedMediaPaths(feedTimelinePaths)
        let feedMergedVideo = HomeTransAnimationMediaParsing.splitImageAndVideoURLs(feedTimelineUrls).video

        self.gridCarouselTimelineURLs = urls
        self.gridTransAnimationVideoURL = transFieldFirstVideo
        self.gridVideoTransAnimationImageURLs = transSplit.images
        self.gridSlideshowURLs = transSplit.images
        self.imageURL = transSplit.images.first
            ?? HomeTemplateMediaURL.resolve(dancingTemplate.afterSnapshot ?? "")
        self.gridSlideshowInterval = Self.gridSlideshowInterval(fromTransAnimation: dancingTemplate.transAnimation)
        self.topTag = nil
        self.bottomLeft = .coins(Self.parseGold(dancingTemplate.consumedGold))
        self.aspectRatio = aspectRatio
        self.templateKind = .t2
        self.transAnimation = ta
        self.previewVideoURL = HomeTransAnimationMediaParsing.t2t3PlaybackVideoURL(
            transAnimationRaw: dancingTemplate.transAnimation,
            afterVideoURL: afterResolved,
            transFieldFirstVideo: transFieldFirstVideo,
            mergedTimelineFirstVideo: feedMergedVideo
        )
    }

    /// 与 `HomeFeedItem` 中 `slideshowInterval(fromTransAnimation:)` 规则一致
    fileprivate static func gridSlideshowInterval(fromTransAnimation raw: String) -> TimeInterval {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let v = Double(t) else { return 3.2 }
        if v > 0.25, v < 120, v <= 50 || t.contains(".") {
            return v
        }
        if v >= 50, v <= 600_000 {
            return min(max(v / 1000.0, 0.8), 30)
        }
        return 3.2
    }

    fileprivate static func uniqueResolvedMediaPaths(_ paths: [String]) -> [URL] {
        var seen = Set<String>()
        var out: [URL] = []
        for p in paths {
            let s = p.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !s.isEmpty, seen.insert(s).inserted, let u = HomeTemplateMediaURL.resolve(s) else { continue }
            out.append(u)
        }
        return out
    }

    /// 仅从 `transAnimation` 逗号片段解析 URL，取其中首个视频（与 `beforePic(s)` 无关）。
    fileprivate static func firstVideoURLFromTransAnimationFieldOnly(_ transAnimationRaw: String) -> URL? {
        let ta = transAnimationRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ta.isEmpty else { return nil }
        let segs = HomeTransAnimationMediaParsing.transAnimationPathSegments(ta)
        let urls = uniqueResolvedMediaPaths(segs)
        return HomeTransAnimationMediaParsing.splitImageAndVideoURLs(urls).video
    }

    fileprivate static func parseGold(_ s: String) -> Int {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if let v = Int(t) { return v }
        if let d = Double(t) { return Int(d.rounded()) }
        return 0
    }
}

extension HomeGridCardItem {
    /// 示例瀑布流：部分卡片带静音循环视频（与封面叠加，便于 Preview 验证多格同时播）
    static let sampleGridPreviewVideoURL: URL? = URL(string: "https://www.w3schools.com/html/mov_bbb.mp4")

    /// 设计稿 home_grid_with_refined_card_actions 中的示例图（Video / Dance 网格占位）
    static let sampleGrid: [HomeGridCardItem] = [
        HomeGridCardItem(
            imageURL: URL(string: "https://lh3.googleusercontent.com/aida-public/AB6AXuBsjIuc6x29CZZRPzkYl0s7CAnJLRJXWZTKUlIKSLixhF1bojOm7T6aXzmHrpM0C8JgEcDDVsSmqzfG_PcB8PiGDTyWtHKAmG_GjBAzZPefDFnlU7dOosN7er9LopuxjQiDDm34WzHKIKwQwoRJx-Ox8akODVO6tfpm_LC66Gnm34tC2APo9KZdSKaWa7dCHU0CKqo815tlV6nfEHiQifVTlia2IsSj61HFrjZr5PmWkSmQddgNAhDwnwT-D1DEasC43dB4HREf6VEA"),
            previewVideoURL: sampleGridPreviewVideoURL,
            topTag: .free,
            bottomLeft: .coins(50),
            aspectRatio: 9 / 16,
            templateKind: .t3
        ),
        HomeGridCardItem(
            imageURL: URL(string: "https://lh3.googleusercontent.com/aida-public/AB6AXuC6F26Q2ytXjFDv5rEJqlADERWlbZfxKC6EOKlR3nmN4cbVc8udviSeJwy5AzI-ViOPr7e6gL5wvQE1fedlppWEAnj5RSEwiW_wGicbBK1yeR73vQIwYRh7BmdBbi4X4OMjvU4je2dnFEsyzbZ1Vro-jd9oJG9SDr5JeZD5gflg2lhxPmvDWd9gC2-TIiX3VkNglZ1xZN9w9TO5-XgIlc09E_QZlWpUmxOA-9czi2l7exxui4M6FUsMZOmYeJsrL1caniKE5QSrPM70"),
            previewVideoURL: sampleGridPreviewVideoURL,
            topTag: .hot,
            bottomLeft: .coins(80),
            aspectRatio: 3 / 5,
            templateKind: .t3
        ),
        HomeGridCardItem(
            imageURL: URL(string: "https://lh3.googleusercontent.com/aida-public/AB6AXuBIrPukjVM7PbasubNiNrCBPNpgPH_oUFhKrUFlcpCoP6hLGdYfTBz8tCnwpUqcn-JAHKvbF0l0-FNAph6vH10ceFw7FMyY4Sb31_CcYdizL7AoX-7KquYNDrvKXBQs8JSn7gx6LtJNSp9kZqfoSKQDd5aFcY81CclXjwMvE-XwNihhXJhiNhZTSyYM4kO0PbwLneCB9cmweA_PM5SwAr5r4fQmuMTmWlNQSxV8Lken3A1tNgiKHOWNVzXPrKTwDs2I7vnte_Sx8efN"),
            previewVideoURL: sampleGridPreviewVideoURL,
            topTag: .new,
            bottomLeft: .locked,
            aspectRatio: 9 / 16,
            templateKind: .t2
        ),
        HomeGridCardItem(
            imageURL: URL(string: "https://lh3.googleusercontent.com/aida-public/AB6AXuCmI1YKGM_13Zvi4U_rSzr8gc69gjwsIMrZqrBt8G2SAv55e59tj26bSdv7L23cfkavjiSzOyp0BTAcM4mAQk25LzY4Y1CpGy7EzRROJWCNG6a0mrCWpt0ZYCUzs1S1T3zLt97PGsaS9p6dHZTJnhMdemaY8GVx-SnRxbChgKc6l_z3gM4462hBpsnjwFiym6fl5jLo3l3sjjnPbOqhfyheK6gHJhvLCRHfV6WyN_Sovl4NVkURjC04YHafKGZZRVsqOqc6152PPubI"),
            previewVideoURL: sampleGridPreviewVideoURL,
            topTag: nil,
            bottomLeft: .locked,
            aspectRatio: 4 / 5,
            templateKind: .t2
        ),
        HomeGridCardItem(
            imageURL: URL(string: "https://lh3.googleusercontent.com/aida-public/AB6AXuCTmfxFmNZ8N_-A0kKPK5QBGEDKYT-cFiY_3a9cSHtanseBUNpDtWHBu9YcL7tD09AcGOHAps_dcqPFppFTHmdUf4yzBqbLyKQ-_5V0nWBhLuDcKUxwzpV403NrkVV5FKxtiHLcPPbCA4t2KeM-tpqLxckQqI5n-Qp42Kd0a0M3iBtq4bKzGjbuv6IcvZTcg5OAreWsaL4UJ4h4qwGXxkXCGLOsp8UlJDUFuhSchrFrZdUteJjxSLVVw2ySZRsKBHF6deBQU-JS-JkN"),
            gridSlideshowURLs: [
                URL(string: "https://lh3.googleusercontent.com/aida-public/AB6AXuCTmfxFmNZ8N_-A0kKPK5QBGEDKYT-cFiY_3a9cSHtanseBUNpDtWHBu9YcL7tD09AcGOHAps_dcqPFppFTHmdUf4yzBqbLyKQ-_5V0nWBhLuDcKUxwzpV403NrkVV5FKxtiHLcPPbCA4t2KeM-tpqLxckQqI5n-Qp42Kd0a0M3iBtq4bKzGjbuv6IcvZTcg5OAreWsaL4UJ4h4qwGXxkXCGLOsp8UlJDUFuhSchrFrZdUteJjxSLVVw2ySZRsKBHF6deBQU-JS-JkN")!,
                URL(string: "https://lh3.googleusercontent.com/aida-public/AB6AXuBXKz2V6Ea0kW-GqCpETP3ghfIRqxMkr5zTGdNljWy_vKvd578ah3e3H2JoX8dM0wyzVolGTOegz3pxJWNXyvQ6fGCd9uGjn554qeqE7ZlIojv3pcM0w5sWMQbXBYliGCH9i0hI0Yf79QnhgCcXdQBiywMwvXpvG9qSuMEQWghiazEBkrgrBm1naWZV6PeA6-9-6440QNG2R5dQ_rBE7IQ2ZF-hDFB4f64gyr0BenQMjMEgcw9qf_C1H4Jkz4x8PnlWEXf_NhuuSUJZ")!
            ],
            gridSlideshowInterval: 2.4,
            topTag: nil,
            bottomLeft: .locked,
            aspectRatio: 9 / 16,
            templateKind: .t1
        ),
        HomeGridCardItem(
            imageURL: URL(string: "https://lh3.googleusercontent.com/aida-public/AB6AXuBXKz2V6Ea0kW-GqCpETP3ghfIRqxMkr5zTGdNljWy_vKvd578ah3e3H2JoX8dM0wyzVolGTOegz3pxJWNXyvQ6fGCd9uGjn554qeqE7ZlIojv3pcM0w5sWMQbXBYliGCH9i0hI0Yf79QnhgCcXdQBiywMwvXpvG9qSuMEQWghiazEBkrgrBm1naWZV6PeA6-9-6440QNG2R5dQ_rBE7IQ2ZF-hDFB4f64gyr0BenQMjMEgcw9qf_C1H4Jkz4x8PnlWEXf_NhuuSUJZ"),
            gridSlideshowURLs: [
                URL(string: "https://lh3.googleusercontent.com/aida-public/AB6AXuBXKz2V6Ea0kW-GqCpETP3ghfIRqxMkr5zTGdNljWy_vKvd578ah3e3H2JoX8dM0wyzVolGTOegz3pxJWNXyvQ6fGCd9uGjn554qeqE7ZlIojv3pcM0w5sWMQbXBYliGCH9i0hI0Yf79QnhgCcXdQBiywMwvXpvG9qSuMEQWghiazEBkrgrBm1naWZV6PeA6-9-6440QNG2R5dQ_rBE7IQ2ZF-hDFB4f64gyr0BenQMjMEgcw9qf_C1H4Jkz4x8PnlWEXf_NhuuSUJZ")!,
                URL(string: "https://lh3.googleusercontent.com/aida-public/AB6AXuCTmfxFmNZ8N_-A0kKPK5QBGEDKYT-cFiY_3a9cSHtanseBUNpDtWHBu9YcL7tD09AcGOHAps_dcqPFppFTHmdUf4yzBqbLyKQ-_5V0nWBhLuDcKUxwzpV403NrkVV5FKxtiHLcPPbCA4t2KeM-tpqLxckQqI5n-Qp42Kd0a0M3iBtq4bKzGjbuv6IcvZTcg5OAreWsaL4UJ4h4qwGXxkXCGLOsp8UlJDUFuhSchrFrZdUteJjxSLVVw2ySZRsKBHF6deBQU-JS-JkN")!
            ],
            gridSlideshowInterval: 2.4,
            topTag: nil,
            bottomLeft: .locked,
            aspectRatio: 2 / 3,
            templateKind: .t1
        )
    ]
}

extension HomeFeedItem {
    /// 仅用于 SwiftUI Preview（首条双图演示列表轮播）
    static let sampleFeed: [HomeFeedItem] = [
        HomeFeedItem(
            imageURL: URL(string: "https://lh3.googleusercontent.com/aida-public/AB6AXuDuX54Gg4GBz0LqYteaMvDSHMlQboJPXqhg1blAM2DjkgzgmZ2TORz7OLTbFb6aQ8F15MD0NOqd83hw7SPHr9DwtLYfaHKF7sstjz6O0CODNtjnl4qdiAUg6XNCkHCuYK8rVbzMBwWj61x2TBvZB_b5xw4WtfBXcg0lHVdW0aRlUfPHgfelnADI7qkBUVMckoEou0ybTgCuQ61RICHXJViH16mXapX_tu6BSEUgsHDckdeGgnxOP6rCN8MQMwgS8R2z9v0LzDfvV6t3"),
            slideshowURLs: [
                URL(string: "https://lh3.googleusercontent.com/aida-public/AB6AXuDuX54Gg4GBz0LqYteaMvDSHMlQboJPXqhg1blAM2DjkgzgmZ2TORz7OLTbFb6aQ8F15MD0NOqd83hw7SPHr9DwtLYfaHKF7sstjz6O0CODNtjnl4qdiAUg6XNCkHCuYK8rVbzMBwWj61x2TBvZB_b5xw4WtfBXcg0lHVdW0aRlUfPHgfelnADI7qkBUVMckoEou0ybTgCuQ61RICHXJViH16mXapX_tu6BSEUgsHDckdeGgnxOP6rCN8MQMwgS8R2z9v0LzDfvV6t3")!,
                URL(string: "https://lh3.googleusercontent.com/aida-public/AB6AXuBt6Pl6QmeNu74iUX9PhJPAKCfmGzlCrocUnvLSfJQufbdlGwNWMlJfH4GTf0qFrFqUmjCOqlaV5nN7x_b1XB7_tmckmY38ao6b5TY7MJ4si2r_pIsa8G6rwvgGDecKjZKYt4dhUK1fCliOeabu4aacfTUj8rIL0ZliDqYYOJtC2AInvmQpu7zSg_wWts50UoSWzliUioLGtsmaeaqpHGatFcVv6zIIbJlxjBOw3ixmLhoYRTGInA72MGjPe-iY5MfLxqbS_XY5mlJl")!
            ],
            slideshowInterval: 3,
            mediaIcon: "photo.fill",
            templateKind: .t1,
            consumedCoins: 30
        ),
        HomeFeedItem(
            imageURL: URL(string: "https://lh3.googleusercontent.com/aida-public/AB6AXuBt6Pl6QmeNu74iUX9PhJPAKCfmGzlCrocUnvLSfJQufbdlGwNWMlJfH4GTf0qFrFqUmjCOqlaV5nN7x_b1XB7_tmckmY38ao6b5TY7MJ4si2r_pIsa8G6rwvgGDecKjZKYt4dhUK1fCliOeabu4aacfTUj8rIL0ZliDqYYOJtC2AInvmQpu7zSg_wWts50UoSWzliUioLGtsmaeaqpHGatFcVv6zIIbJlxjBOw3ixmLhoYRTGInA72MGjPe-iY5MfLxqbS_XY5mlJl"),
            mediaIcon: "film.fill",
            templateKind: .t3,
            consumedCoins: 30
        )
    ]
}
