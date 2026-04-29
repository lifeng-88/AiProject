//
//  HomeImmersiveVideoBackdrop.swift
//  bbb
//
//  T2/T3 沉浸式全屏背景：优先本地缓存 URL，否则网络流；静音循环播放。
//

import AVFoundation
import SwiftUI
import UIKit

// MARK: - AVPlayerLayer 铺满容器

final class HomeVideoFillContainerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var videoLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        /// 沉浸式底栏为 SwiftUI `Button`；视频层必须在 UIKit 层关闭命中，否则触摸被 `AVPlayerLayer` 容器吃掉，SWAP/心形无法点中。
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - 循环播放（AVPlayer + 首尾衔接；避免 AVPlayerLooper 对部分网络 MP4/HLS 不兼容）

/// 静音循环、`resizeAspectFill`、不拦截触摸；沉浸式底与瀑布流网格预览共用。
struct HomeMutedLoopingVideoFillView: UIViewRepresentable {
    let url: URL
    /// `readyToPlay` 且已 seek 到第 0 帧并开始 `play` 后调用（主线程），用于沉浸式「首帧封面再叠视频层」。
    var onReadyToPlayFromFirstFrame: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(onReadyToPlayFromFirstFrame: onReadyToPlayFromFirstFrame)
    }

    func makeUIView(context: Context) -> HomeVideoFillContainerView {
        let v = HomeVideoFillContainerView()
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        context.coordinator.player = player
        context.coordinator.attachLoopEndObserver(item: item, player: player)
        player.isMuted = true
        v.videoLayer.player = player
        v.videoLayer.videoGravity = .resizeAspectFill
        context.coordinator.seekToFirstFrameThenPlay(player: player, item: item)
        return v
    }

    func updateUIView(_ uiView: HomeVideoFillContainerView, context: Context) {
        context.coordinator.onReadyToPlayFromFirstFrame = onReadyToPlayFromFirstFrame
    }

    static func dismantleUIView(_ uiView: HomeVideoFillContainerView, coordinator: Coordinator) {
        coordinator.teardown()
        uiView.videoLayer.player = nil
    }

    final class Coordinator {
        var player: AVPlayer?
        var onReadyToPlayFromFirstFrame: (() -> Void)?
        private var readyObserver: NSKeyValueObservation?
        private var endObserver: NSObjectProtocol?

        init(onReadyToPlayFromFirstFrame: (() -> Void)?) {
            self.onReadyToPlayFromFirstFrame = onReadyToPlayFromFirstFrame
        }

        func attachLoopEndObserver(item: AVPlayerItem, player: AVPlayer) {
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak player] _ in
                player?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
                player?.play()
            }
        }

        /// 就绪后对齐到第 0 帧再播，避免从中间时刻或黑场起播。
        fileprivate func seekToFirstFrameThenPlay(player: AVPlayer, item: AVPlayerItem) {
            cancelReadyObserver()
            readyObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] observed, _ in
                guard let self else { return }
                switch observed.status {
                case .readyToPlay:
                    self.cancelReadyObserver()
                    player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                        player.play()
                        let callback = self.onReadyToPlayFromFirstFrame
                        Task { @MainActor in
                            callback?()
                        }
                    }
                case .failed:
                    self.cancelReadyObserver()
                default:
                    break
                }
            }
        }

        fileprivate func cancelReadyObserver() {
            readyObserver?.invalidate()
            readyObserver = nil
        }

        fileprivate func teardown() {
            cancelReadyObserver()
            if let endObserver {
                NotificationCenter.default.removeObserver(endObserver)
            }
            endObserver = nil
            player?.pause()
            player?.replaceCurrentItem(with: nil)
            player = nil
        }
    }
}

// MARK: - 单次播放到结尾（沉浸式循环 / 瀑布流顺序播）

struct HomeMutedVideoOnceFillView: UIViewRepresentable {
    let url: URL
    let onFinished: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinished: onFinished)
    }

    func makeUIView(context: Context) -> HomeVideoFillContainerView {
        let v = HomeVideoFillContainerView()
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        context.coordinator.player = player
        context.coordinator.observeEnd(of: item)
        player.isMuted = true
        v.videoLayer.player = player
        v.videoLayer.videoGravity = .resizeAspectFill
        context.coordinator.seekToFirstFrameThenPlay(player: player, item: item)
        return v
    }

    func updateUIView(_ uiView: HomeVideoFillContainerView, context: Context) {}

    static func dismantleUIView(_ uiView: HomeVideoFillContainerView, coordinator: Coordinator) {
        uiView.videoLayer.player = nil
        coordinator.teardown()
    }

    final class Coordinator {
        var player: AVPlayer?
        private var endObserver: NSObjectProtocol?
        private var readyObserver: NSKeyValueObservation?
        private let onFinished: () -> Void
        private var didFireEnd = false

        init(onFinished: @escaping () -> Void) {
            self.onFinished = onFinished
        }

        /// 就绪后对齐到第 0 帧再播，避免从中间时刻或黑场起播。
        fileprivate func seekToFirstFrameThenPlay(player: AVPlayer, item: AVPlayerItem) {
            readyObserver?.invalidate()
            readyObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] observed, _ in
                guard let self else { return }
                switch observed.status {
                case .readyToPlay:
                    self.readyObserver?.invalidate()
                    self.readyObserver = nil
                    player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                        player.play()
                    }
                case .failed:
                    self.readyObserver?.invalidate()
                    self.readyObserver = nil
                default:
                    break
                }
            }
        }

        func observeEnd(of item: AVPlayerItem) {
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] _ in
                guard let self, !self.didFireEnd else { return }
                self.didFireEnd = true
                self.onFinished()
            }
        }

        func teardown() {
            readyObserver?.invalidate()
            readyObserver = nil
            if let o = endObserver {
                NotificationCenter.default.removeObserver(o)
                endObserver = nil
            }
            player?.pause()
            player?.replaceCurrentItem(with: nil)
            player = nil
        }
    }
}

// MARK: - T2/T3：按 `transAnimation` 顺序轮播（图 / 视频），无图↔成片「转场」阶段

/// 顺序与接口 `transAnimation` 逗号片段一致；视频段单次播完进下一段，图片段按 `interval` 停留。
struct HomeImmersiveTransAnimationCarouselBackdrop: View {
    let itemId: String
    let urls: [URL]
    let interval: TimeInterval
    let width: CGFloat
    let height: CGFloat
    var imageAspectFit: Bool = false

    @State private var index = 0
    @State private var imageHoldTask: Task<Void, Never>?

    private var step: TimeInterval {
        min(max(interval, 0.9), 45)
    }

    private var currentURL: URL? {
        guard urls.indices.contains(index) else { return nil }
        return urls[index]
    }

    var body: some View {
        ZStack {
            Color.black
            if let u = currentURL {
                if HomeImmersiveMediaURL.isVideo(u) {
                    HomeMutedVideoOnceFillView(url: u) {
                        advance()
                    }
                    .frame(width: width, height: height)
                    .clipped()
                    .id("\(itemId)-tcvid-\(index)-\(u.absoluteString)")
                } else {
                    ZStack {
                        Color.black
                        HomeCachedImage(
                            url: u,
                            priority: .userInitiated,
                            onSettled: { scheduleImageHold() },
                            aspectFit: imageAspectFit,
                            showsLoadingIndicator: true
                        )
                        .frame(width: width, height: height)
                    }
                    .id("\(itemId)-tcimg-\(index)-\(u.absoluteString)")
                }
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .onDisappear {
            imageHoldTask?.cancel()
            imageHoldTask = nil
        }
        .onChange(of: index) { _ in
            imageHoldTask?.cancel()
            imageHoldTask = nil
        }
        .onChange(of: itemId) { _ in
            index = 0
        }
        .onChange(of: urls.map(\.absoluteString).joined(separator: "|")) { _ in
            index = 0
        }
        .task(id: "\(itemId)|\(urls.map(\.absoluteString).joined(separator: "|"))") {
            for u in urls.prefix(16) {
                if HomeImmersiveMediaURL.isVideo(u) {
                    await VideoCacheManager.shared.preloadVideo(videoURL: u.absoluteString, priority: .userInitiated)
                } else {
                    await ImageCacheManager.shared.preloadImage(urlString: u.absoluteString, priority: .userInitiated)
                }
            }
        }
    }

    private func scheduleImageHold() {
        imageHoldTask?.cancel()
        imageHoldTask = nil
        guard let u = currentURL, !HomeImmersiveMediaURL.isVideo(u) else { return }
        let nanos = UInt64(step * 1_000_000_000)
        let holdIndex = index
        imageHoldTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled else { return }
            guard holdIndex == index else { return }
            advance()
        }
    }

    private func advance() {
        imageHoldTask?.cancel()
        imageHoldTask = nil
        guard !urls.isEmpty else { return }
        index = (index + 1) % urls.count
    }
}

// MARK: - 仅循环视频（保留供其它场景使用）

/// 沉浸式 T2/T3：先解码同 URL 视频首帧作封面，就绪后从第 0 帧起静音循环（与 `immersivePrimaryLoopVideoURL` 同源）。
struct HomeImmersiveVideoBackdrop: View {
    let remoteURL: URL
    let width: CGFloat
    let height: CGFloat

    @State private var playURL: URL?
    @State private var coverPoster: UIImage?
    @State private var showVideoLayer = false

    var body: some View {
        ZStack {
            Color.black
            if let poster = coverPoster {
                Image(uiImage: poster)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: height)
                    .clipped()
            } else {
                ProgressView()
                    .tint(.white.opacity(0.85))
                    .scaleEffect(1.1)
            }
            let u = playURL ?? remoteURL
            HomeMutedLoopingVideoFillView(
                url: u,
                onReadyToPlayFromFirstFrame: {
                    withAnimation(.easeIn(duration: 0.22)) {
                        showVideoLayer = true
                    }
                }
            )
            .id(u.absoluteString)
            .opacity(showVideoLayer ? 1 : 0)
        }
        .frame(width: width, height: height)
        .clipped()
        .task(id: remoteURL.absoluteString) {
            let s = remoteURL.absoluteString
            await MainActor.run {
                showVideoLayer = false
                coverPoster = nil
            }
            async let thumb: UIImage? = VideoCacheManager.shared.thumbnailUIImage(forVideoURLString: s)
            let local = await VideoCacheManager.shared.getVideoURL(for: s)
            await MainActor.run {
                playURL = local ?? remoteURL
            }
            let p = await thumb
            await MainActor.run {
                coverPoster = p
            }
            if local == nil {
                await VideoCacheManager.shared.preloadVideo(videoURL: s, priority: .userInitiated)
            }
        }
    }
}

// MARK: - 瀑布流网格预览：`isPlaying` 时叠视频；`loops` 时多格同时循环播，否则单次结束回调（沉浸式镜像）

struct HomeGridSequentialVideoPreview: View {
    let remoteURL: URL
    let isPlaying: Bool
    /// 瀑布流多格同时播时为 `true`，静音循环；沉浸式全屏镜像条为 `false`
    var loops: Bool = true
    /// 为 `true` 时先完成预加载再叠播放器，底层首帧海报始终可见；沉浸式顺序轮播单段镜像为 `false`。
    var deferPlaybackUntilCached: Bool = false
    let onFinished: () -> Void

    @State private var playURL: URL?
    @State private var playGeneration = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.06)
            if isPlaying, let u = playURL {
                Group {
                    if loops {
                        HomeMutedLoopingVideoFillView(url: u)
                    } else {
                        HomeMutedVideoOnceFillView(url: u, onFinished: onFinished)
                    }
                }
                .id("\(u.absoluteString)-\(playGeneration)-\(loops)")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .allowsHitTesting(false)
        /// `isPlaying` 纳入 id：首帧常为 false 时若直接 return，待可见后再 true 会重新跑任务并补上 `playURL`
        .task(id: "\(remoteURL.absoluteString)|\(isPlaying)") {
            guard isPlaying else { return }
            let s = remoteURL.absoluteString
            if deferPlaybackUntilCached {
                /// 必须先有 `playURL` 才能叠播放器；网络流立即起播，缓存完成后换本地 URL。
                if let local = await VideoCacheManager.shared.getVideoURL(for: s) {
                    await MainActor.run { playURL = local }
                } else {
                    await MainActor.run { playURL = remoteURL }
                }
                Task(priority: .userInitiated) {
                    await VideoCacheManager.shared.preloadVideo(videoURL: s, priority: .userInitiated)
                    if let local = await VideoCacheManager.shared.getVideoURL(for: s) {
                        await MainActor.run { playURL = local }
                    }
                }
            } else {
                let local = await VideoCacheManager.shared.getVideoURL(for: s)
                await MainActor.run { playURL = local ?? remoteURL }
                if local == nil {
                    Task(priority: .userInitiated) {
                        await VideoCacheManager.shared.preloadVideo(videoURL: s, priority: .userInitiated)
                        if let loc = await VideoCacheManager.shared.getVideoURL(for: s) {
                            await MainActor.run { playURL = loc }
                        }
                    }
                }
            }
        }
        .onChange(of: isPlaying) { playing in
            if playing {
                playGeneration += 1
            } else {
                /// 停播时释放 URL，避免离屏格仍持有播放器；回屏后 `.task` 会重新解析。
                playURL = nil
            }
        }
    }
}
