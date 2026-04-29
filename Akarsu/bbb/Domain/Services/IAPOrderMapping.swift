//
//  IAPOrderMapping.swift
//  glam
//
//  StoreKit 2 内购：orderId 与 appAccountToken(UUID) 的本地映射
//  用于购买完成后从 transaction.appAccountToken 反查业务 orderId，再调服务端验证
//

import Foundation

/// 订单号与 appAccountToken(UUID) 的映射，供 IAPManager 购买与漏单处理使用
final class IAPOrderMapping {
    static let shared = IAPOrderMapping()

    private let mappingKeyPrefix = "IAP_Order_UUID_Map_"
    private let channelKeyPrefix = "IAP_Channel_UUID_Map_"
    private let defaults = UserDefaults.standard

    private init() {}

    /// 存储：orderId、`pay_channel_id`（与下单时一致，供确认/漏单使用）
    func save(orderId: String, payChannelId: Int32, for uuid: UUID) {
        defaults.set(orderId, forKey: mappingKeyPrefix + uuid.uuidString)
        defaults.set(Int(payChannelId), forKey: channelKeyPrefix + uuid.uuidString)
    }

    /// 通过 UUID 字符串查回业务 orderId
    func getOrderId(from uuidString: String) -> String {
        guard !uuidString.isEmpty else { return "" }
        return defaults.string(forKey: mappingKeyPrefix + uuidString) ?? ""
    }

    /// 与 `save` 时写入的 `pay_channel_id` 一致；无记录时回退 1（兼容旧版仅存 orderId）
    func getPayChannelId(from uuidString: String) -> Int32 {
        guard !uuidString.isEmpty else { return 1 }
        if let n = defaults.object(forKey: channelKeyPrefix + uuidString) as? Int {
            return Int32(n)
        }
        return 1
    }

    /// 验证成功后移除映射
    func remove(for uuidString: String) {
        guard !uuidString.isEmpty else { return }
        defaults.removeObject(forKey: mappingKeyPrefix + uuidString)
        defaults.removeObject(forKey: channelKeyPrefix + uuidString)
    }
}
