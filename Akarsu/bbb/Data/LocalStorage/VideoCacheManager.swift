//
//  VideoCacheManager.swift
//  glam
//
//  Created by Dev on 2026/1/18.
//

import AVFoundation
import Combine
import Foundation
import UIKit

/// 视频资源缓存管理器（参考 ImageCacheManager 的实现）
/// 负责视频文件缓存到本地，以及视频首帧缩略图缓存
@MainActor
class VideoCacheManager {
    static let shared = VideoCacheManager()
    
    /// 磁盘缓存目录
    private let cacheDirectory: URL
    
    /// 缓存过期时间（7天）
    private let cacheExpirationTime: TimeInterval = 7 * 24 * 60 * 60
    
    /// 自定义 URLSession 配置
    private let urlSession: URLSession
    
    /// 下载队列项
    private struct DownloadQueueItem {
        let urlString: String
        let priority: TaskPriority
        let isCurrentDisplay: Bool
        let continuation: CheckedContinuation<Void, Never>
    }
    
    /// 下载队列管理器（使用 Actor 确保线程安全）
    private actor DownloadQueueManager {
        private var downloadQueue: [DownloadQueueItem] = []
        private var isProcessingQueue = false
        private var currentDownloadingURLs: Set<String> = []
        /// 当前正在下载的、被标记为「当前显示」的 URL；有此类 URL 时不允许开始「其它」的下载
        private var currentURLsInProgress: Set<String> = []
        private let maxConcurrentDownloads = 3
        
        /// 添加到队列（当前显示最前，其余按 TaskPriority）
        func enqueue(item: DownloadQueueItem) -> Bool {
            if downloadQueue.contains(where: { $0.urlString == item.urlString }) {
                return false
            }
            if currentDownloadingURLs.contains(item.urlString) {
                return false
            }
            
            let priorityOrder: [TaskPriority] = [.userInitiated, .utility, .background]
            let itemPriorityIndex = priorityOrder.firstIndex(of: item.priority) ?? 999
            
            var inserted = false
            for (index, existingItem) in downloadQueue.enumerated() {
                let existingIsCurrent = existingItem.isCurrentDisplay
                let itemIsCurrent = item.isCurrentDisplay
                if itemIsCurrent && !existingIsCurrent {
                    downloadQueue.insert(item, at: index)
                    inserted = true
                    break
                }
                if itemIsCurrent == existingIsCurrent {
                    let existingPriorityIndex = priorityOrder.firstIndex(of: existingItem.priority) ?? 999
                    if itemPriorityIndex < existingPriorityIndex {
                        downloadQueue.insert(item, at: index)
                        inserted = true
                        break
                    }
                }
            }
            if !inserted {
                downloadQueue.append(item)
            }
            return true
        }
        
        /// 获取下一个要下载的项目（有「当前显示」未完成时只出队当前显示，且一次一个）
        func dequeue() -> DownloadQueueItem? {
            guard !downloadQueue.isEmpty else {
                if currentDownloadingURLs.isEmpty {
                    isProcessingQueue = false
                }
                return nil
            }
            
            let hasCurrentInQueue = downloadQueue.contains(where: { $0.isCurrentDisplay })
            if hasCurrentInQueue {
                if !currentURLsInProgress.isEmpty {
                    return nil
                }
                if let idx = downloadQueue.firstIndex(where: { $0.isCurrentDisplay }) {
                    let item = downloadQueue.remove(at: idx)
                    currentDownloadingURLs.insert(item.urlString)
                    currentURLsInProgress.insert(item.urlString)
                    isProcessingQueue = true
                    print("   📋 [VideoQueueManager] dequeue (current): \(item.urlString), remaining: \(downloadQueue.count), concurrent: \(currentDownloadingURLs.count)")
                    return item
                }
                return nil
            }
            
            guard currentDownloadingURLs.count < maxConcurrentDownloads else {
                return nil
            }
            let item = downloadQueue.removeFirst()
            currentDownloadingURLs.insert(item.urlString)
            isProcessingQueue = true
            print("   📋 [VideoQueueManager] dequeue: \(item.urlString), remaining queue: \(downloadQueue.count), concurrent: \(currentDownloadingURLs.count)")
            return item
        }
        
        /// 标记指定URL的下载完成
        func markDownloadComplete(urlString: String) {
            currentDownloadingURLs.remove(urlString)
            currentURLsInProgress.remove(urlString)
            print("   ✅ [VideoQueueManager] markDownloadComplete: \(urlString), remaining concurrent: \(currentDownloadingURLs.count)")
            if downloadQueue.isEmpty && currentDownloadingURLs.isEmpty {
                isProcessingQueue = false
            }
        }
        
        /// 检查是否应该开始处理队列
        func canStartProcessing() -> Bool {
            return !downloadQueue.isEmpty && currentDownloadingURLs.count < maxConcurrentDownloads
        }
        
        /// 检查是否在队列中或正在下载
        func isInQueueOrDownloading(urlString: String) -> Bool {
            return downloadQueue.contains(where: { $0.urlString == urlString }) || currentDownloadingURLs.contains(urlString)
        }
        
        /// 取消队列中的任务
        func cancelQueued(urlString: String) {
            if currentDownloadingURLs.contains(urlString) {
                return
            }
            downloadQueue.removeAll { $0.urlString == urlString }
        }
    }
    
    private let queueManager = DownloadQueueManager()
    
    private init() {
        // 配置 URLSession
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.httpMaximumConnectionsPerHost = 3
        self.urlSession = URLSession(configuration: configuration)
        
        // 设置缓存目录
        let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.cacheDirectory = cacheURL.appendingPathComponent("TemplateVideos", isDirectory: true)
        
        // 创建缓存目录
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        
        // 监听内存警告和应用进入后台
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - 视频文件缓存
    
    /// 获取视频文件的本地 URL（从缓存或下载）
    func getVideoURL(for urlString: String) async -> URL? {
        // 1. 先检查磁盘缓存
        let cachedURL = await getCachedVideoURL(urlString: urlString)

        if let cachedURL = cachedURL {
            return cachedURL
        }
        
        return nil
    }
    
    /// 预加载视频文件（下载并缓存到本地）
    /// - Parameter isCurrentDisplay: 是否为当前显示（Home 当前索引的模板）；为 true 时优先下载，且在其完成前不开始其它预加载
    func preloadVideo(videoURL: String, priority: TaskPriority = .utility, isCurrentDisplay: Bool = false) async {
        // 如果已缓存，直接返回
        if await getVideoURL(for: videoURL) != nil {
            print("✅ [VideoCacheManager] preloadVideo already cached, returning immediately")
            return
        }
        
        // 创建队列项
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let item = DownloadQueueItem(urlString: videoURL, priority: priority, isCurrentDisplay: isCurrentDisplay, continuation: continuation)
            
            Task { @MainActor in
                // 再次检查缓存
                if await self.getVideoURL(for: videoURL) != nil {
                    print("✅ [VideoCacheManager] preloadVideo found in cache during check, resuming continuation")
                    continuation.resume()
                    return
                }
                
                // 检查是否在队列中或正在下载
                if await self.queueManager.isInQueueOrDownloading(urlString: videoURL) {
                    print("⏳ [VideoCacheManager] Video already in queue or downloading, waiting: \(videoURL)")
                    Task.detached(priority: priority) {
                        await self.waitForDownloadInQueue(urlString: videoURL)
                        continuation.resume()
                    }
                    return
                }
                
                print("📥 [VideoCacheManager] Adding to queue: \(videoURL), priority: \(priority)")
                
                // 添加到队列
                let added = await self.queueManager.enqueue(item: item)
                if !added {
                    print("⚠️ [VideoCacheManager] Failed to enqueue, waiting: \(videoURL)")
                    Task.detached(priority: priority) {
                        await self.waitForDownloadInQueue(urlString: videoURL)
                        continuation.resume()
                    }
                    return
                }
                
                print("✅ [VideoCacheManager] Enqueued successfully, starting queue processor: \(videoURL)")
                await self.processDownloadQueue()
            }
        }
        
        print("✅ [VideoCacheManager] preloadVideo EXIT - Preload completed for: \(videoURL)")
    }
    
    /// 等待队列中的下载完成
    private func waitForDownloadInQueue(urlString: String) async {
        var attempts = 0
        let maxAttempts = 100 // 最多等待 30 秒（100 * 300ms）
        var lastLoggedAttempt = -1
        
        while attempts < maxAttempts {
            // 检查文件是否已存在（减少日志输出，每 10 次检查打印一次）
            if attempts % 10 == 0 || attempts == 0 {
                if let cachedURL = await getCachedVideoURL(urlString: urlString) {
                    print("✅ [VideoCacheManager] waitForDownloadInQueue found cached file after \(attempts) attempts: \(cachedURL.path)")
                    return
                }
            } else {
                // 非日志轮次，只检查文件是否存在（不调用 getVideoURL，避免日志过多）
                if let cachedURL = await getCachedVideoURL(urlString: urlString) {
                    return
                }
            }
            
            let inQueueOrDownloading = await queueManager.isInQueueOrDownloading(urlString: urlString)
            if !inQueueOrDownloading {
                print("⚠️ [VideoCacheManager] waitForDownloadInQueue - URL no longer in queue or downloading after \(attempts) attempts")
                return
            }
            
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
            attempts += 1
            
            // 每 17 次尝试打印一次进度（避免日志过多，调整为适应新的间隔，约每 5 秒）
            if attempts % 17 == 0 && attempts != lastLoggedAttempt {
                print("⏳ [VideoCacheManager] waitForDownloadInQueue still waiting... attempt \(attempts)/\(maxAttempts) for: \(urlString)")
                lastLoggedAttempt = attempts
            }
        }
        
        print("⚠️ [VideoCacheManager] waitForDownloadInQueue timeout after \(maxAttempts) attempts (30s) for: \(urlString)")
    }
    
    /// 并发处理下载队列
    private func processDownloadQueue() async {
        print("🚀 [VideoCacheManager] Queue processor started")
        
        while await queueManager.canStartProcessing() {
            let tasks: Int
            do {
                tasks = try await withThrowingTaskGroup(of: Void.self) { group in
                    var startedTasks = 0
                    
                    while startedTasks < 3, let item = await queueManager.dequeue() {
                        startedTasks += 1
                        
                        group.addTask { [weak self] in
                            guard let self = self else { return }
                            let urlString = item.urlString
                            print("⬇️ [VideoCacheManager] Processing queue item: \(urlString), priority: \(item.priority)")
                            
                            func complete() async {
                                print("🔄 [VideoCacheManager] complete() called for: \(urlString)")
                                await self.queueManager.markDownloadComplete(urlString: urlString)
                                print("✅ [VideoCacheManager] markDownloadComplete done, about to resume continuation for: \(urlString)")
                                
                                // 验证文件是否真的存在
                                if let cachedURL = await self.getVideoURL(for: urlString) {
                                    print("✅ [VideoCacheManager] File verified exists before resume: \(cachedURL.path)")
                                } else {
                                    print("⚠️ [VideoCacheManager] File NOT found before resume, will retry in getVideoURL")
                                }
                                
                                item.continuation.resume()
                                print("✅ [VideoCacheManager] Continuation resumed for: \(urlString)")
                            }
                            
                            // 再次检查缓存
                            if await self.getVideoURL(for: urlString) != nil {
                                await complete()
                                return
                            }
                            
                            guard let url = URL(string: urlString) else {
                                print("❌ [VideoCacheManager] Invalid URL: \(urlString)")
                                await complete()
                                return
                            }
                            
                            // 下载并重试逻辑（最多3次）
                            let maxRetries = 3
                            var lastError: Error?
                            
                            for attempt in 1...maxRetries {
                                do {
                                    if attempt > 1 {
                                        let delay = min(Double(attempt - 1) * 0.5, 2.0)
                                        print("   🔄 Retrying download (attempt \(attempt)/\(maxRetries)) after \(delay)s: \(urlString)")
                                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                                    } else {
                                        print("   🌐 Starting download: \(urlString)")
                                    }
                                    
                                    // 下载视频文件
                                    let session = VideoCacheManager.urlSession
                                    let (data, _): (Data, URLResponse)
                                    do {
                                        (data, _) = try await withTimeout(seconds: 120) {
                                            try await session.data(from: url)
                                        }
                                    } catch is TimeoutError {
                                        print("   ⏱️ Download timeout after 120 seconds: \(urlString)")
                                        throw URLError(.timedOut)
                                    }
                                    
                                    print("   📥 [VideoCacheManager] Download completed, data size: \(data.count) bytes for: \(urlString)")
                                    
                                    // 保存到磁盘缓存
                                    if await self.saveToDisk(data: data, urlString: urlString) {
                                        print("✅ [VideoCacheManager] Downloaded and cached: \(urlString)")
                                        await complete()
                                        return
                                    } else {
                                        throw NSError(domain: "VideoCacheManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to save video to disk"])
                                    }
                                    
                                } catch {
                                    lastError = error
                                    
                                    let shouldRetry: Bool
                                    if let urlError = error as? URLError {
                                        shouldRetry = attempt < maxRetries && (
                                            urlError.code == .timedOut ||
                                            urlError.code == .networkConnectionLost ||
                                            urlError.code == .notConnectedToInternet ||
                                            urlError.code == .cannotConnectToHost ||
                                            urlError.code == .cannotFindHost ||
                                            urlError.code == .badServerResponse
                                        )
                                        
                                        if !shouldRetry {
                                            print("❌ [VideoCacheManager] Failed to download (non-retryable error): \(urlString)")
                                        }
                                    } else {
                                        shouldRetry = false
                                        print("❌ [VideoCacheManager] Failed to download (non-retryable error): \(urlString)")
                                    }
                                    
                                    if !shouldRetry {
                                        await complete()
                                        return
                                    }
                                }
                            }
                            
                            if let error = lastError {
                                print("❌ [VideoCacheManager] Failed to download after \(maxRetries) attempts: \(urlString)")
                                print("   - Last error: \(error)")
                            }
                            await complete()
                        }
                    }
                    
                    // 等待所有任务完成
                    for try await _ in group {
                        // 任务完成
                    }
                    
                    return startedTasks
                }
            } catch {
                print("❌ [VideoCacheManager] Error in task group: \(error)")
                tasks = 0
            }
            
            if tasks == 0 {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        
        print("✅ [VideoCacheManager] Queue empty, processor stopping")
    }
    
    /// 超时错误
    private struct TimeoutError: Error {}
    
    /// 带超时的异步操作包装器
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError()
            }
            
            guard let result = try await group.next() else {
                throw TimeoutError()
            }
            
            group.cancelAll()
            return result
        }
    }
    
    /// 从磁盘获取缓存的视频 URL
    private func getCachedVideoURL(urlString: String) async -> URL? {
        let md5Hash = urlString.md5
        let fileName = md5Hash + ".mp4"
        let fileURL = cacheDirectory.appendingPathComponent(fileName)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let valueKeys: Set<URLResourceKey> = [.contentModificationDateKey, .creationDateKey]
        if let vals = try? fileURL.resourceValues(forKeys: valueKeys),
           let ref = vals.contentModificationDate ?? vals.creationDate,
           Date().timeIntervalSince(ref) > cacheExpirationTime {
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        }

        return fileURL
    }
    
    /// 保存视频文件到磁盘
    nonisolated private func saveToDisk(data: Data, urlString: String) async -> Bool {
        let md5Hash = urlString.md5
        let fileName = md5Hash + ".mp4"
        let cacheDir = Self.getCacheDirectory()

        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: cacheDir.path) {
            try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        }

        let fileURL = cacheDir.appendingPathComponent(fileName)

        do {
            try data.write(to: fileURL)
            return true
        } catch {
            print("❌ [VideoCacheManager] Failed to save to disk cache: \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - 视频首帧缩略图缓存
    
    /// 获取视频首帧缩略图（使用 ImageCacheManager）
    func getVideoThumbnail(for videoURL: String) async -> UIImage? {
        return await ImageCacheManager.shared.getImage(for: videoURL)
    }

    /// 生成或读取缓存的视频首帧图（全 iOS 版本）；优先已下载的本地文件再解码，写入 `ImageCacheManager` 供网格停止态等复用。
    func thumbnailUIImage(forVideoURLString videoURLString: String) async -> UIImage? {
        if let existing = await ImageCacheManager.shared.getImage(for: videoURLString) {
            return existing
        }
        guard let remoteURL = URL(string: videoURLString) else { return nil }
        let localURL = await getVideoURL(for: videoURLString) ?? remoteURL
        let generated: UIImage? = await Task.detached(priority: .utility) { () -> UIImage? in
            let asset = AVURLAsset(url: localURL)
            let gen = AVAssetImageGenerator(asset: asset)
            gen.appliesPreferredTrackTransform = true
            gen.requestedTimeToleranceAfter = .zero
            gen.requestedTimeToleranceBefore = .zero
            do {
                if #available(iOS 16.0, *) {
                    let cg = try await gen.image(at: .zero).image
                    return UIImage(cgImage: cg)
                } else {
                    let cg = try gen.copyCGImage(at: .zero, actualTime: nil)
                    return UIImage(cgImage: cg)
                }
            } catch {
                return nil
            }
        }.value
        if let generated {
            await ImageCacheManager.shared.setImage(generated, for: videoURLString)
        }
        return generated
    }
    
    /// 预加载视频首帧缩略图（iOS 16+ 使用 AVAssetImageGenerator.image(at:)；iOS 15 跳过）
    func preloadVideoThumbnail(videoURL: String) async {
        if await ImageCacheManager.shared.getImage(for: videoURL) != nil {
            return
        }
        if #available(iOS 16.0, *) {
            await preloadVideoThumbnailiOS16(videoURL: videoURL)
        }
    }
    
    @available(iOS 16.0, *)
    private func preloadVideoThumbnailiOS16(videoURL: String) async {
        await Task.detached(priority: .utility) {
            guard let url = URL(string: videoURL) else { return }
            
            let asset = AVURLAsset(url: url)
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            imageGenerator.requestedTimeToleranceAfter = .zero
            imageGenerator.requestedTimeToleranceBefore = .zero
            
            do {
                let cgImage = try await imageGenerator.image(at: .zero).image
                let thumbnail = UIImage(cgImage: cgImage)
                await ImageCacheManager.shared.setImage(thumbnail, for: videoURL)
            } catch {
                print("⚠️ [VideoCacheManager] Failed to generate thumbnail for \(videoURL): \(error)")
            }
        }.value
    }
    
    // MARK: - 清理缓存
    
    /// 清理过期磁盘缓存（7天）
    func cleanExpiredDiskCache() async {
        let now = Date()
        let fileManager = FileManager.default
        let dirKeys: [URLResourceKey] = [.contentModificationDateKey, .creationDateKey]
        let valueKeys: Set<URLResourceKey> = [.contentModificationDateKey, .creationDateKey]

        guard let files = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: dirKeys, options: .skipsHiddenFiles) else {
            return
        }

        for file in files {
            guard let vals = try? file.resourceValues(forKeys: valueKeys),
                  let ref = vals.contentModificationDate ?? vals.creationDate,
                  now.timeIntervalSince(ref) > cacheExpirationTime else { continue }
            try? fileManager.removeItem(at: file)
        }
    }
    
    /// 清理所有缓存（磁盘）
    func clearAllCache() async {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [], options: .skipsHiddenFiles) else {
            return
        }
        
        for file in files {
            try? fileManager.removeItem(at: file)
        }
        print("🗑️ [VideoCacheManager] Cleared disk cache")
    }
    
    /// 应用进入后台
    @objc private func handleDidEnterBackground() {
        // 可以在这里添加后台处理逻辑
    }
}

// MARK: - 图片与视频本地缓存协调

/// 统一入口：`ImageCacheManager`（内存 + 磁盘图片）与 `VideoCacheManager`（磁盘视频；视频首帧缩略图写入图片缓存）。
enum MediaCacheMaintenance {
    /// 清理超出保留期的磁盘条目（各 Manager 内默认 7 天）。
    @MainActor
    static func cleanExpiredCachesIfNeeded() async {
        await ImageCacheManager.shared.cleanExpiredDiskCache()
        await VideoCacheManager.shared.cleanExpiredDiskCache()
    }

    /// 清空图片与视频媒体文件缓存，供设置「清除缓存」等调用。
    @MainActor
    static func clearAllMediaFileCaches() async {
        await ImageCacheManager.shared.clearAllCache()
        await VideoCacheManager.shared.clearAllCache()
    }
}

// MARK: - MD5 Helper

import CryptoKit

private extension String {
    nonisolated var md5: String {
        let data = Data(self.utf8)
        let hash = Insecure.MD5.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Nonisolated Helper Methods

extension VideoCacheManager {
    nonisolated static func getCacheDirectory() -> URL {
        let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return cacheURL.appendingPathComponent("TemplateVideos", isDirectory: true)
    }
    
    nonisolated static var urlSession: URLSession {
        struct SharedURLSession {
            static let shared: URLSession = {
                let configuration = URLSessionConfiguration.default
                configuration.timeoutIntervalForRequest = 30
                configuration.timeoutIntervalForResource = 120
                configuration.httpMaximumConnectionsPerHost = 3
                return URLSession(configuration: configuration)
            }()
        }
        return SharedURLSession.shared
    }
}