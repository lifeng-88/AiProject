//
//  PayChannelManager.swift
//  glam
//
//  Created by Dev on 2026/1/20.
//

import Foundation
import SwiftUI
import Combine

/// 支付渠道管理器 - 在应用启动时加载一次，后续从缓存读取（按channel_id）
@MainActor
class PayChannelManager: ObservableObject {
    static let shared = PayChannelManager()
    
    @Published var payChannels: [PayChannel] = []
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
        if let cachedChannels = RechargeDataCacheManager.shared.getCachedPayChannels(channelId: channelId), !cachedChannels.isEmpty {
            self.payChannels = cachedChannels
            print("✅ [PayChannelManager] Loaded \(cachedChannels.count) channels from cache for channel: \(channelId)")
        }
    }
    
    /// 获取当前channel_id（从AppConfig中获取）
    private func getCurrentChannelId() async -> String {
        let appConfig = AppConfig.shared
        return await appConfig.getChannel()
    }
    
    /// 加载支付渠道列表（只在应用启动时调用一次）
    func loadPayChannelsOnce() async {
        // 获取当前channel_id（从AppConfig获取）
        let channelId = await getCurrentChannelId()
        
        // 如果channel_id变化，需要重新加载
        if let currentChannelId = currentChannelId, currentChannelId != channelId {
            print("ℹ️ [PayChannelManager] Channel ID changed from \(currentChannelId) to \(channelId), will reload")
            hasLoadedOnce = false
        }
        
        // 如果已经加载过且channel_id未变化，直接返回
        if hasLoadedOnce && currentChannelId == channelId {
            print("ℹ️ [PayChannelManager] Pay channels already loaded for channel: \(channelId), skipping...")
            return
        }
        
        hasLoadedOnce = true
        currentChannelId = channelId
        isLoading = true
        
        // 先尝试从缓存加载
        loadFromCache(channelId: channelId)
        
        // 然后从网络请求最新数据
        let result = await rechargeRepository.getPayChannels()
        
        switch result {
        case .success(let channels):
            // 仅当拿到有效列表时才更新；空列表不覆盖已有缓存
            if !channels.isEmpty || self.payChannels.isEmpty {
                self.payChannels = channels
                RechargeDataCacheManager.shared.setCachedPayChannels(channels, channelId: channelId)
                lastLoadTime = Date()
                print("✅ [PayChannelManager] Loaded \(channels.count) channels from network for channel: \(channelId)")
            } else {
                print("⚠️ [PayChannelManager] Ignored empty network result to preserve existing cache for channel: \(channelId)")
            }
        case .failure(let error):
            print("❌ [PayChannelManager] Failed to load pay channels: \(error.localizedDescription), keeping existing cache")
            // 失败时不覆盖内存与缓存，继续使用之前可用的缓存
        }
        
        isLoading = false
    }
    
    /// 最近一次选择的支付渠道 ID（用于下次打开时默认选中）
    var lastSelectedPayChannelId: Int32? {
        let value = UserDefaults.standard.object(forKey: UserDefaultsKey.lastSelectedPayChannelId)
        guard let intValue = value as? Int else { return nil }
        return Int32(intValue)
    }
    
    /// 保存最近选择的支付渠道
    func setLastSelectedPayChannelId(_ id: Int32) {
        UserDefaults.standard.set(Int(id), forKey: UserDefaultsKey.lastSelectedPayChannelId)
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
        
        let result = await rechargeRepository.getPayChannels()
        
        switch result {
        case .success(let channels):
            if !channels.isEmpty || self.payChannels.isEmpty {
                self.payChannels = channels
                RechargeDataCacheManager.shared.setCachedPayChannels(channels, channelId: channelId)
                lastLoadTime = Date()
                print("✅ [PayChannelManager] Refreshed \(channels.count) channels for channel: \(channelId)")
            } else {
                print("⚠️ [PayChannelManager] Ignored empty refresh result to preserve existing cache for channel: \(channelId)")
            }
        case .failure(let error):
            print("❌ [PayChannelManager] Failed to refresh pay channels: \(error.localizedDescription), keeping existing cache")
            // 失败时不覆盖 self.payChannels 与缓存
        }
        
        isLoading = false
    }
}
