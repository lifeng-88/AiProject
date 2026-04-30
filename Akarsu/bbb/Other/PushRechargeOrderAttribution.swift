//
//  PushRechargeOrderAttribution.swift
//  bbb
//
//  与 glam 一致：`recharge_incentive_new_user` 建单归因；支付成功后清除；冷启动按 userId 从 UserDefaults 恢复。
//

import Combine
import Foundation
import SwiftUI

/// 与推送 `recharge_incentive_new_user` 对齐；金额单位为 USD 美分。
struct RechargeOrderPushAttribution: Equatable, Codable {
    var campaignId: String?
    var offerId: String
    var appleProductId: String
    var amountCentsUsd: Int64
    var baseCoins: Int32
    var bonusCoins: Int32
}

@MainActor
final class PushRechargeOrderAttributionStore: ObservableObject {
    static let shared = PushRechargeOrderAttributionStore()

    private static let userDefaultsKeyPrefix = "bbb.rechargeIncentiveNewUser.v1."

    @Published private(set) var pending: RechargeOrderPushAttribution?

    private init() {}

    func loadPersistedIfNeeded() async {
        guard pending == nil else { return }
        guard let info = await AuthRepository.shared.getCurrentAuthInfo() else { return }
        let key = Self.storageKey(userId: info.userid)
        guard let data = UserDefaults.standard.data(forKey: key),
              let attr = try? JSONDecoder().decode(RechargeOrderPushAttribution.self, from: data) else { return }
        pending = attr
    }

    private static func storageKey(userId: String) -> String {
        userDefaultsKeyPrefix + userId
    }

    private func persistToDisk(_ attribution: RechargeOrderPushAttribution?) async {
        guard let info = await AuthRepository.shared.getCurrentAuthInfo() else { return }
        let key = Self.storageKey(userId: info.userid)
        if let attr = attribution, let data = try? JSONEncoder().encode(attr) {
            UserDefaults.standard.set(data, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    func setRechargeIncentive(_ attribution: RechargeOrderPushAttribution?) {
        pending = attribution
        Task { await persistToDisk(attribution) }
    }

    func clearAfterSuccessfulPayment() {
        guard pending != nil else { return }
        pending = nil
        Task { await persistToDisk(nil) }
    }

    static func notifyRechargePaymentSucceeded() {
        Task { @MainActor in
            shared.clearAfterSuccessfulPayment()
        }
    }
}

extension Package {
    /// 与 `recharge_incentive_new_user` 推送里 `apple_product_id` 一致的套餐才返回 `offer_id`，供 `POST .../recharges` 的 `offer_id` 使用。
    @MainActor
    func offerIdForPushAttributedCreateOrderIfMatching() -> String? {
        guard let attr = PushRechargeOrderAttributionStore.shared.pending else { return nil }
        guard let appleId = resolvedAppleProductId, !appleId.isEmpty else { return nil }
        guard appleId == attr.appleProductId else { return nil }
        return attr.offerId
    }
}
