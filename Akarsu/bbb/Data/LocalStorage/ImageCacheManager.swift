//
//  ImageCacheManager.swift
//  glam
//
//  Created by Dev on 2026/1/18.
//

import Combine
import Foundation
import UIKit

/// 图片缓存管理器（使用 NSCache 管理内存缓存）
/// 按照需求文档：最大内存占用 100MB，超出时自动释放最久未使用的图片
@MainActor
class ImageCacheManager {
    static let shared = ImageCacheManager()
    
    /// 内存缓存（NSCache 会自动管理内存压力）
    private let memoryCache: NSCache<NSString, UIImage>
    
    /// 磁盘缓存目录
    private let cacheDirectory: URL
    
    /// 缓存过期时间（7天）
    private let cacheExpirationTime: TimeInterval = 7 * 24 * 60 * 60
    
    /// 最大内存占用（100MB）
    private let maxMemoryCost: Int = 100 * 1024 * 1024
    
    /// 自定义 URLSession 配置（增加超时时间）
    private let urlSession: URLSession
    
    /// 下载队列项
    private struct DownloadQueueItem {
        let urlString: String
        let priority: TaskPriority
        let continuation: CheckedContinuation<Void, Never>
    }
    
    /// 下载队列管理器（使用 Actor 确保线程安全）
    private actor DownloadQueueManager {
        private var downloadQueue: [DownloadQueueItem] = []
        private var isProcessingQueue = false
        private var currentDownloadingURLs: Set<String> = [] // 支持并发3个下载
        private let maxConcurrentDownloads = 3
        
        /// 添加到队列（按优先级插入）
        func enqueue(item: DownloadQueueItem) -> Bool {
            // 检查是否已在队列中或正在下载
            if downloadQueue.contains(where: { $0.urlString == item.urlString }) {
                return false // 已在队列中
            }
            if currentDownloadingURLs.contains(item.urlString) {
                return false // 正在下载中
            }
            
            // 按优先级插入（高优先级在前）
            let priorityOrder: [TaskPriority] = [.userInitiated, .utility, .background]
            let itemPriorityIndex = priorityOrder.firstIndex(of: item.priority) ?? 999
            
            var inserted = false
            for (index, existingItem) in downloadQueue.enumerated() {
                let existingPriorityIndex = priorityOrder.firstIndex(of: existingItem.priority) ?? 999
                if itemPriorityIndex < existingPriorityIndex {
                    downloadQueue.insert(item, at: index)
                    inserted = true
                    break
                }
            }
            
            if !inserted {
                downloadQueue.append(item)
            }
            
            return true
        }
        
        /// 获取下一个要下载的项目（如果有并发槽位）
        func dequeue() -> DownloadQueueItem? {
            guard !downloadQueue.isEmpty else {
                if currentDownloadingURLs.isEmpty {
                    print("   🔍 [QueueManager] dequeue: queue empty, setting isProcessingQueue=false")
                    isProcessingQueue = false
                }
                return nil
            }
            
            // 检查是否有并发槽位
            guard currentDownloadingURLs.count < maxConcurrentDownloads else {
                return nil // 已达最大并发数
            }
            
            let item = downloadQueue.removeFirst()
            currentDownloadingURLs.insert(item.urlString)
            isProcessingQueue = true
            print("   📋 [QueueManager] dequeue: \(item.urlString), remaining queue: \(downloadQueue.count), concurrent: \(currentDownloadingURLs.count)")
            return item
        }
        
        /// 标记指定URL的下载完成
        func markDownloadComplete(urlString: String) {
            currentDownloadingURLs.remove(urlString)
            print("   ✅ [QueueManager] markDownloadComplete: \(urlString), remaining concurrent: \(currentDownloadingURLs.count)")
            
            // 如果队列已空且没有正在下载的，停止处理
            if downloadQueue.isEmpty && currentDownloadingURLs.isEmpty {
                isProcessingQueue = false
            }
        }
        
        /// 检查是否应该开始处理队列（不修改状态，只检查）
        func canStartProcessing() -> Bool {
            // 有队列项且还有并发槽位
            let canStart = !downloadQueue.isEmpty && currentDownloadingURLs.count < maxConcurrentDownloads
            if !canStart {
                print("   🔍 [QueueManager] canStartProcessing = false: isProcessingQueue=\(isProcessingQueue), queueCount=\(downloadQueue.count), concurrent=\(currentDownloadingURLs.count)/\(maxConcurrentDownloads)")
            }
            return canStart
        }
        
        /// 检查是否在队列中或正在下载
        func isInQueueOrDownloading(urlString: String) -> Bool {
            return downloadQueue.contains(where: { $0.urlString == urlString }) || currentDownloadingURLs.contains(urlString)
        }
        
        /// 取消队列中的任务（不包括正在下载的）
        func cancelQueued(urlString: String) {
            if currentDownloadingURLs.contains(urlString) {
                return // 正在下载，不能取消
            }
            downloadQueue.removeAll { $0.urlString == urlString }
        }
    }
    
    private let queueManager = DownloadQueueManager()
    
    private init() {
        // 初始化内存缓存
        self.memoryCache = NSCache<NSString, UIImage>()
        self.memoryCache.totalCostLimit = maxMemoryCost
        self.memoryCache.countLimit = 200 // 最多缓存200张图片
        
        // 配置 URLSession（增加超时时间，避免网络慢时超时）
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30 // 请求超时时间：30秒
        configuration.timeoutIntervalForResource = 60 // 资源超时时间：60秒
        configuration.httpMaximumConnectionsPerHost = 3 // 每个主机最大连接数：3个（并发下载）
        self.urlSession = URLSession(configuration: configuration)
        
        // 设置缓存目录
        let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.cacheDirectory = cacheURL.appendingPathComponent("TemplateImages", isDirectory: true)
        
        // 创建缓存目录
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        
        // 监听内存警告，清理缓存
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
        
        // 监听应用进入后台，清理内存缓存（保留磁盘缓存）
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
    
    /// 仅同步读内存缓存（用于 `HomeCachedImage` 首帧免闪；完整加载仍用 `getImage`）
    func memoryCachedImage(for urlString: String) -> UIImage? {
        memoryCache.object(forKey: urlString as NSString)
    }

    /// 获取图片（优先从内存缓存，其次从磁盘缓存）
    func getImage(for urlString: String) async -> UIImage? {
        let cacheKey = urlString as NSString
        
        // 1. 先检查内存缓存
        if let cachedImage = memoryCache.object(forKey: cacheKey) {
            return cachedImage
        }
        
        // 2. 检查磁盘缓存
        if let diskImage = await loadFromDisk(urlString: urlString) {
            // 恢复到内存缓存
            let cost = diskImage.size.width * diskImage.size.height * 4 // 估算内存成本（RGBA）
            memoryCache.setObject(diskImage, forKey: cacheKey, cost: Int(cost))
            return diskImage
        }
        
        return nil
    }
    
    /// 保存图片到缓存（内存 + 磁盘）
    func setImage(_ image: UIImage, for urlString: String) async {
        let cacheKey = urlString as NSString
        
        // 1. 保存到内存缓存
        let cost = image.size.width * image.size.height * 4 // 估算内存成本（RGBA）
        memoryCache.setObject(image, forKey: cacheKey, cost: Int(cost))
        
        // 2. 异步保存到磁盘缓存
        Task.detached(priority: .utility) {
            await self.saveToDisk(image: image, urlString: urlString)
        }
    }
    
    /// 预加载图片（下载并缓存）
    /// 使用串行队列，一次只下载一个，按优先级排队
    /// - Parameters:
    ///   - urlString: 图片URL
    ///   - priority: 任务优先级，默认为.utility。当前模板的图片应使用.userInitiated
    func preloadImage(urlString: String, priority: TaskPriority = .utility) async {
        // 如果已缓存，直接返回
        if await getImage(for: urlString) != nil {
            return
        }
        
        // 创建队列项，使用 continuation 等待完成
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let item = DownloadQueueItem(urlString: urlString, priority: priority, continuation: continuation)
            
            // 在一个 actor 调用中完成检查和入队，避免竞态条件
            Task { @MainActor in
                // 再次检查缓存（可能在等待期间已缓存）
                if await self.getImage(for: urlString) != nil {
                    continuation.resume()
                    return
                }
                
                // 检查是否在队列中或正在下载（与 enqueue 在同一个 actor 调用中，避免竞态）
                if await self.queueManager.isInQueueOrDownloading(urlString: urlString) {
                    print("⏳ [ImageCacheManager] Image already in queue or downloading, waiting: \(urlString)")
                    // 已在队列中或正在下载，等待完成后 resume continuation
                    Task.detached(priority: priority) {
                        await self.waitForDownloadInQueue(urlString: urlString)
                        continuation.resume()
                    }
                    return
                }
                
                print("📥 [ImageCacheManager] Adding to queue: \(urlString), priority: \(priority)")
                
                // 添加到队列（在同一 actor 调用中，确保线程安全）
                let added = await self.queueManager.enqueue(item: item)
                if !added {
                    print("⚠️ [ImageCacheManager] Failed to enqueue (already in queue), waiting: \(urlString)")
                    // 未添加（可能在此期间被其他任务添加），等待完成后 resume continuation
                    Task.detached(priority: priority) {
                        await self.waitForDownloadInQueue(urlString: urlString)
                        continuation.resume()
                    }
                    return
                }
                
                print("✅ [ImageCacheManager] Enqueued successfully, starting queue processor: \(urlString)")
                
                // 启动队列处理（如果尚未在处理）
                // 注意：continuation 会在 processDownloadQueue 中的 item.continuation.resume() 处 resume
                await self.processDownloadQueue()
            }
        }
        
        print("✅ [ImageCacheManager] Preload completed for: \(urlString)")
    }
    
    /// 等待队列中的下载完成
    private func waitForDownloadInQueue(urlString: String) async {
        // 轮询检查是否已下载完成
        var attempts = 0
        while attempts < 600 { // 最多等待30秒（每次50ms）
            if await getImage(for: urlString) != nil {
                return
            }
            
            // 检查是否仍在队列中或正在下载
            let inQueueOrDownloading = await queueManager.isInQueueOrDownloading(urlString: urlString)
            if !inQueueOrDownloading {
                // 不在队列中也不在下载，说明可能出错了，不再等待
                return
            }
            
            try? await Task.sleep(nanoseconds: 50_000_000)
            attempts += 1
        }
    }
    
    /// 并发处理下载队列（同时处理最多3个）
    private func processDownloadQueue() async {
        print("🚀 [ImageCacheManager] Queue processor started")
        
        // 并发处理队列，使用 TaskGroup 同时处理多个下载
        while await queueManager.canStartProcessing() {
            // 启动新的下载任务（最多3个并发）
            let tasks = await withTaskGroup(of: Void.self) { group in
                var startedTasks = 0
                
                // 启动最多3个并发下载任务
                while startedTasks < 3, let item = await queueManager.dequeue() {
                    startedTasks += 1
                    
                    group.addTask { [weak self] in
                        guard let self = self else { return }
                        let urlString = item.urlString
                        print("⬇️ [ImageCacheManager] Processing queue item: \(urlString), priority: \(item.priority)")
                        
                        // 清理函数：在所有路径调用
                        func complete() async {
                            await self.queueManager.markDownloadComplete(urlString: urlString)
                            item.continuation.resume()
                        }
                        
                        // 再次检查缓存（可能在等待期间已经被其他任务缓存）
                        if await self.getImage(for: urlString) != nil {
                            await complete()
                            return
                        }
                        
                        // 检查URL是否有效
                        guard let url = URL(string: urlString) else {
                            print("❌ [ImageCacheManager] Invalid URL: \(urlString)")
                            await complete()
                            return
                        }
                        
                        // 下载并重试逻辑（最多3次）
                        let maxRetries = 3
                        var lastError: Error?
                        
                        for attempt in 1...maxRetries {
                            do {
                                if attempt > 1 {
                                    // 重试前等待一小段时间（指数退避）
                                    let delay = min(Double(attempt - 1) * 0.5, 2.0) // 最多2秒
                                    print("   🔄 Retrying download (attempt \(attempt)/\(maxRetries)) after \(delay)s: \(urlString)")
                                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                                } else {
                                    print("   🌐 Starting download: \(urlString)")
                                }
                                
                                // 使用超时包装器，确保即使 URLSession 超时未触发，也能在 45 秒后抛出错误
                                let session = ImageCacheManager.urlSession
                                let data: Data
                                
                                do {
                                    (data, _) = try await self.withTimeout(seconds: 45) {
                                        try await session.data(from: url)
                                    }
                                } catch is TimeoutError {
                                    print("   ⏱️ Download timeout after 45 seconds: \(urlString)")
                                    throw URLError(.timedOut)
                                } catch {
                                    throw error
                                }
                                
                                print("   📥 Download completed, data size: \(data.count) bytes")
                                
                                guard let image = UIImage(data: data) else {
                                    // 无法解析图片数据，不重试（重试也不会成功）
                                    print("❌ [ImageCacheManager] Failed to create UIImage from data (size: \(data.count) bytes)")
                                    await complete()
                                    return
                                }
                                
                                print("   🖼️ UIImage created, decoding...")
                                
                                // 解码图片
                                let decodedImage = await Task.detached(priority: item.priority) {
                                    return await ImageCacheManager.shared.decodeImage(image)
                                }.value
                                
                                print("   ✅ Image decoded, saving to cache...")
                                
                                // 保存到缓存（内存 + 磁盘）
                                await self.setImage(decodedImage, for: urlString)
                                print("💾 [ImageCacheManager] Image saved to memory cache: \(urlString)")
                                
                                print("✅ [ImageCacheManager] Downloaded and cached: \(urlString)")
                                
                                // 下载成功，通知等待者完成并清理
                                await complete()
                                return
                                
                            } catch {
                                lastError = error
                                
                                // 判断是否应该重试
                                let shouldRetry: Bool
                                if let urlError = error as? URLError {
                                    // 网络错误可以重试（超时、网络不可用、服务器错误等）
                                    shouldRetry = attempt < maxRetries && (
                                        urlError.code == .timedOut ||
                                        urlError.code == .networkConnectionLost ||
                                        urlError.code == .notConnectedToInternet ||
                                        urlError.code == .cannotConnectToHost ||
                                        urlError.code == .cannotFindHost ||
                                        urlError.code == .badServerResponse ||
                                        urlError.code == .zeroByteResource
                                    )
                                    
                                    if !shouldRetry {
                                        print("❌ [ImageCacheManager] Failed to download (non-retryable error): \(urlString)")
                                        print("   - URLError code: \(urlError.code.rawValue)")
                                        print("   - URLError description: \(urlError.localizedDescription)")
                                    }
                                } else {
                                    // 非网络错误，不重试
                                    shouldRetry = false
                                    print("❌ [ImageCacheManager] Failed to download (non-retryable error): \(urlString)")
                                    print("   - Error: \(error)")
                                }
                                
                                if !shouldRetry {
                                    // 不再重试，最终失败
                                    if attempt == maxRetries {
                                        print("❌ [ImageCacheManager] Failed to download after \(maxRetries) attempts: \(urlString)")
                                    }
                                    
                                    // 通知等待者完成并清理（即使失败）
                                    await complete()
                                    return
                                }
                                
                                // 会继续下一次循环进行重试
                            }
                        }
                        
                        // 如果所有重试都失败（理论上不会到这里，因为上面的循环会返回）
                        if let error = lastError {
                            print("❌ [ImageCacheManager] Failed to download after \(maxRetries) attempts: \(urlString)")
                            print("   - Last error: \(error)")
                        }
                        await complete()
                    }
                }
                
                return startedTasks
            }
            
            // 等待所有任务完成后再继续处理下一批
            if tasks == 0 {
                // 没有任务启动，可能队列为空或已达并发上限，等待一小段时间
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
        }
        
        print("✅ [ImageCacheManager] Queue empty, processor stopping")
    }
    
    /// 取消队列中的任务（不包括正在下载的）
    func cancelQueuedDownload(urlString: String) async {
        await queueManager.cancelQueued(urlString: urlString)
    }
    
    /// 清理内存缓存（保留磁盘缓存）
    @objc private func handleMemoryWarning() {
        memoryCache.removeAllObjects()
    }
    
    /// 应用进入后台时清理内存缓存
    @objc private func handleDidEnterBackground() {
        memoryCache.removeAllObjects()
    }
    
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
    
    /// 清理所有缓存（内存 + 磁盘）
    func clearAllCache() async {
        // 清理内存缓存
        memoryCache.removeAllObjects()
        print("🗑️ [ImageCacheManager] Cleared memory cache")
        
        // 清理磁盘缓存
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [], options: .skipsHiddenFiles) else {
            return
        }
        
        for file in files {
            try? fileManager.removeItem(at: file)
        }
        print("🗑️ [ImageCacheManager] Cleared disk cache")
    }
    
    // MARK: - Private Helpers
    
    /// 超时错误
    private struct TimeoutError: Error {}
    
    /// 带超时的异步操作包装器
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
            // 添加下载任务
            group.addTask {
                try await operation()
            }
            
            // 添加超时任务
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError()
            }
            
            // 等待第一个完成的任务
            guard let result = try await group.next() else {
                throw TimeoutError()
            }
            
            // 取消剩余任务
            group.cancelAll()
            
            return result
        }
    }
    
    /// 磁盘文件名：优先 `.jpg`（新写入），兼容历史 `.png`
    private func diskImageURLs(md5Hash: String) -> [URL] {
        [
            cacheDirectory.appendingPathComponent(md5Hash + ".jpg"),
            cacheDirectory.appendingPathComponent(md5Hash + ".png")
        ]
    }

    private func diskCacheReferenceDate(fileURL: URL) -> Date? {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .creationDateKey]
        guard let vals = try? fileURL.resourceValues(forKeys: keys) else { return nil }
        return vals.contentModificationDate ?? vals.creationDate
    }

    /// 从磁盘加载图片
    private func loadFromDisk(urlString: String) async -> UIImage? {
        let md5Hash = urlString.md5
        let fm = FileManager.default

        for fileURL in diskImageURLs(md5Hash: md5Hash) {
            guard fm.fileExists(atPath: fileURL.path) else { continue }
            if let ref = diskCacheReferenceDate(fileURL: fileURL),
               Date().timeIntervalSince(ref) > cacheExpirationTime {
                try? fm.removeItem(at: fileURL)
                continue
            }
            guard let data = try? Data(contentsOf: fileURL),
                  let image = UIImage(data: data) else { continue }
            return image
        }
        return nil
    }
    
    /// 保存图片到磁盘（无透明通道优先 JPEG 减小体积；含 alpha 仍用 PNG）
    nonisolated private func saveToDisk(image: UIImage, urlString: String) async {
        let md5Hash = urlString.md5
        let cacheDir = Self.getCacheDirectory()

        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: cacheDir.path) {
            try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        }

        let legacyPNG = cacheDir.appendingPathComponent(md5Hash + ".png")
        let legacyJPG = cacheDir.appendingPathComponent(md5Hash + ".jpg")

        let (data, fileURL): (Data, URL)
        if let cg = image.cgImage {
            let ai = cg.alphaInfo
            let hasAlpha: Bool = {
                switch ai {
                case .first, .last, .premultipliedFirst, .premultipliedLast: return true
                default: return false
                }
            }()
            if hasAlpha, let png = image.pngData() {
                data = png
                fileURL = legacyPNG
            } else if let jpg = image.jpegData(compressionQuality: 0.88) {
                data = jpg
                fileURL = legacyJPG
            } else if let png = image.pngData() {
                data = png
                fileURL = legacyPNG
            } else {
                return
            }
        } else if let jpg = image.jpegData(compressionQuality: 0.88) {
            data = jpg
            fileURL = legacyJPG
        } else if let png = image.pngData() {
            data = png
            fileURL = legacyPNG
        } else {
            return
        }

        if fileURL.pathExtension.lowercased() == "jpg" {
            try? fileManager.removeItem(at: legacyPNG)
        } else {
            try? fileManager.removeItem(at: legacyJPG)
        }

        do {
            try data.write(to: fileURL)
        } catch {
            print("❌ [ImageCacheManager] Failed to save image to disk: \(urlString), error: \(error)")
        }
    }
    
    /// 解码图片（避免主线程阻塞）
    nonisolated private func decodeImage(_ image: UIImage) async -> UIImage {
        guard let cgImage = image.cgImage else {
            return image
        }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: cgImage.width,
            height: cgImage.height,
            bitsPerComponent: 8,
            bytesPerRow: cgImage.width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        
        guard let ctx = context else {
            return image
        }
        
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        
        guard let decodedCGImage = ctx.makeImage() else {
            return image
        }
        
        return UIImage(cgImage: decodedCGImage)
    }
}

// MARK: - MD5 Helper (使用 CryptoKit)

import CryptoKit

private extension String {
    nonisolated var md5: String {
        let data = Data(self.utf8)
        let hash = Insecure.MD5.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Nonisolated Helper Methods

extension ImageCacheManager {
    nonisolated static func getCacheDirectory() -> URL {
        let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return cacheURL.appendingPathComponent("TemplateImages", isDirectory: true)
    }
    
    /// 获取共享的 URLSession（用于非 MainActor 上下文中访问，如 CachedImageView）
    /// 注意：为了减少连接警告，应该尽量使用 ImageCacheManager.shared 的方法
    nonisolated static var urlSession: URLSession {
        // 使用单例模式的 URLSession，避免创建多个实例导致连接警告
        // 注意：这个 URLSession 主要用于 CachedImageView（但 CachedImageView 现在使用 preloadImage，所以这里可能不会被使用）
        struct SharedURLSession {
            static let shared: URLSession = {
                let configuration = URLSessionConfiguration.default
                configuration.timeoutIntervalForRequest = 30
                configuration.timeoutIntervalForResource = 60
                configuration.httpMaximumConnectionsPerHost = 3 // 每个主机最大连接数：3个（并发下载）
                return URLSession(configuration: configuration)
            }()
        }
        return SharedURLSession.shared
    }
}
