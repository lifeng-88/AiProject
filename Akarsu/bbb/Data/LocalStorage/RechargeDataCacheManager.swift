//
//  RechargeDataCacheManager.swift
//  glam
//
//  Created by Dev on 2026/1/20.
//

import Combine
import Foundation

/// 充值数据缓存管理器
/// 负责缓存充值套餐和支付渠道数据
@MainActor
class RechargeDataCacheManager {
    static let shared = RechargeDataCacheManager()
    
    private let cacheDirectory: URL
    private let fileManager = FileManager.default
    
    /// 缓存过期时间（1天）
    private let cacheExpirationTime: TimeInterval = 24 * 60 * 60
    
    private init() {
        let cacheURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.cacheDirectory = cacheURL.appendingPathComponent("RechargeData", isDirectory: true)
        
        // 创建缓存目录
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    // MARK: - Packages 缓存（按channel_id）
    
    func getCachedPackages(channelId: String) -> [Package]? {
        let fileName = "packages_\(channelId).json"
        return getCachedData(fileName: fileName, as: [Package].self)
    }
    
    func setCachedPackages(_ packages: [Package], channelId: String) {
        let fileName = "packages_\(channelId).json"
        setCachedData(fileName: fileName, data: packages)
    }
    
    // MARK: - Pay Channels 缓存（按channel_id）
    
    func getCachedPayChannels(channelId: String) -> [PayChannel]? {
        let fileName = "payChannels_\(channelId).json"
        return getCachedData(fileName: fileName, as: [PayChannel].self)
    }
    
    func setCachedPayChannels(_ channels: [PayChannel], channelId: String) {
        let fileName = "payChannels_\(channelId).json"
        setCachedData(fileName: fileName, data: channels)
    }
    
    // MARK: - 兼容旧版本（向后兼容）
    
    /// 获取缓存的套餐（不指定channel_id，用于兼容旧代码）
    func getCachedPackages() -> [Package]? {
        return getCachedData(fileName: "packages.json", as: [Package].self)
    }
    
    /// 设置缓存的套餐（不指定channel_id，用于兼容旧代码）
    func setCachedPackages(_ packages: [Package]) {
        setCachedData(fileName: "packages.json", data: packages)
    }
    
    /// 获取缓存的支付渠道（不指定channel_id，用于兼容旧代码）
    func getCachedPayChannels() -> [PayChannel]? {
        return getCachedData(fileName: "payChannels.json", as: [PayChannel].self)
    }
    
    /// 设置缓存的支付渠道（不指定channel_id，用于兼容旧代码）
    func setCachedPayChannels(_ channels: [PayChannel]) {
        setCachedData(fileName: "payChannels.json", data: channels)
    }
    
    // MARK: - Private Helpers
    
    /// 获取缓存数据
    private func getCachedData<T: Codable>(fileName: String, as type: T.Type) -> T? {
        let fileURL = cacheDirectory.appendingPathComponent(fileName)
        
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }
        
        // 检查是否过期
        if let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
           let creationDate = attributes[.creationDate] as? Date,
           Date().timeIntervalSince(creationDate) > cacheExpirationTime {
            try? fileManager.removeItem(at: fileURL)
            return nil
        }
        
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
        } catch {
            print("⚠️ [RechargeDataCacheManager] Failed to decode cached data from \(fileName): \(error)")
            return nil
        }
    }
    
    /// 保存缓存数据
    private func setCachedData<T: Codable>(fileName: String, data: T) {
        let fileURL = cacheDirectory.appendingPathComponent(fileName)
        
        do {
            let encoder = JSONEncoder()
            let jsonData = try encoder.encode(data)
            try jsonData.write(to: fileURL)
        } catch {
            print("⚠️ [RechargeDataCacheManager] Failed to cache data to \(fileName): \(error)")
        }
    }
    
    /// 清理过期缓存
    func cleanExpiredCache() {
        guard let files = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles) else {
            return
        }
        
        let now = Date()
        for file in files {
            if let attributes = try? fileManager.attributesOfItem(atPath: file.path),
               let creationDate = attributes[.creationDate] as? Date,
               now.timeIntervalSince(creationDate) > cacheExpirationTime {
                try? fileManager.removeItem(at: file)
            }
        }
    }
    
    /// 清理所有缓存
    func clearAllCache() {
        guard let files = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [], options: .skipsHiddenFiles) else {
            return
        }
        
        for file in files {
            try? fileManager.removeItem(at: file)
        }
        print("🗑️ [RechargeDataCacheManager] Cleared all cache")
    }
}
