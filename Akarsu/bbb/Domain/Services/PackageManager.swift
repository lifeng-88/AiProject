//
//  PackageManager.swift
//  glam
//
//  Created by Dev on 2026/1/20.
//

import Foundation
import SwiftUI
import Combine

/// 套餐管理器 - 在应用启动时加载一次，后续从缓存读取（按channel_id）
@MainActor
class PackageManager: ObservableObject {
    static let shared = PackageManager()
    
    @Published var packages: [Package] = []
    @Published var isLoading = false
    @Published var lastLoadTime: Date?
    
    private let rechargeRepository = RechargeRepository.shared
    private var hasLoadedOnce = false // 标记是否已经加载过一次
    private var currentChannelId: String? // 当前使用的channel_id
    
    private init() {
        // 初始化时不从缓存加载，等待获取channel_id后再加载
    }
    
    /// 从缓存加载数据（需要channel_id）
    private func loadFromCache(channelId: String) {
        if let cachedPackages = RechargeDataCacheManager.shared.getCachedPackages(channelId: channelId), !cachedPackages.isEmpty {
            self.packages = cachedPackages
            print("✅ [PackageManager] Loaded \(cachedPackages.count) packages from cache for channel: \(channelId)")
        }
    }
    
    /// 获取当前channel_id（从AppConfig中获取）
    private func getCurrentChannelId() async -> String {
        let appConfig = AppConfig.shared
        return await appConfig.getChannel()
    }
    
    /// 加载套餐列表（只在应用启动时调用一次）
    /// 立即从缓存读取，同时后台更新
    func loadPackagesOnce() async {
        // 获取当前channel_id（从AppConfig获取）
        let channelId = await getCurrentChannelId()
        
        // 如果channel_id变化，需要重新加载
        if let currentChannelId = currentChannelId, currentChannelId != channelId {
            print("ℹ️ [PackageManager] Channel ID changed from \(currentChannelId) to \(channelId), will reload")
            hasLoadedOnce = false
        }
        
        // 如果已经加载过且channel_id未变化，直接返回
        if hasLoadedOnce && currentChannelId == channelId {
            print("ℹ️ [PackageManager] Packages already loaded for channel: \(channelId), skipping...")
            return
        }
        
        hasLoadedOnce = true
        currentChannelId = channelId
        
        // 1. 立即从缓存加载（同步，不等待网络）
        loadFromCache(channelId: channelId)
        
        // 2. 后台异步更新（不阻塞UI，不等待结果）
        Task(priority: .utility) {
            await MainActor.run { isLoading = true }
            
            let result = await rechargeRepository.getPackages()
            
            switch result {
            case .success(let packages):
                // 仅当拿到有效列表时才更新内存与缓存；空列表不覆盖已有缓存
                let currentIsEmpty = await MainActor.run { self.packages.isEmpty }
                let shouldUpdate = !packages.isEmpty || currentIsEmpty
                if shouldUpdate {
                    await MainActor.run {
                        self.packages = packages
                        RechargeDataCacheManager.shared.setCachedPackages(packages, channelId: channelId)
                        lastLoadTime = Date()
                    }
                    print("✅ [PackageManager] Background updated \(packages.count) packages from network for channel: \(channelId)")
                } else {
                    print("⚠️ [PackageManager] Ignored empty network response to preserve existing cache for channel: \(channelId)")
                }
            case .failure(let error):
                print("❌ [PackageManager] Background update failed: \(error.localizedDescription), keeping existing cache")
                // 失败时不覆盖内存与缓存，继续使用之前可用的缓存
            }
            
            await MainActor.run { isLoading = false }
        }
    }
    
    /// 手动刷新（用于下拉刷新等场景）
    func refresh() async {
        // 获取当前channel_id（从AppConfig获取）
        let channelId = await getCurrentChannelId()
        
        // 如果channel_id变化，更新currentChannelId
        if currentChannelId != channelId {
            currentChannelId = channelId
            hasLoadedOnce = false
        }
        
        isLoading = true
        
        let result = await rechargeRepository.getPackages()
        
        switch result {
        case .success(let packages):
            // 仅当拿到有效列表时才更新；失败或空列表不覆盖已有可用缓存
            if !packages.isEmpty || self.packages.isEmpty {
                self.packages = packages
                RechargeDataCacheManager.shared.setCachedPackages(packages, channelId: channelId)
                lastLoadTime = Date()
                print("✅ [PackageManager] Refreshed \(packages.count) packages for channel: \(channelId)")
            } else {
                print("⚠️ [PackageManager] Ignored empty refresh result to preserve existing cache for channel: \(channelId)")
            }
        case .failure(let error):
            print("❌ [PackageManager] Failed to refresh packages: \(error.localizedDescription), keeping existing cache")
            // 失败时不覆盖 self.packages 与缓存
        }
        
        isLoading = false
    }
}
