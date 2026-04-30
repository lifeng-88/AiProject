//
//  RechargeAFLogger.swift
//  bbb
//
//  充值 AppsFlyer：首充 `recharge_first_success`、每次 `af_purchase`；与 glam 一致携带 `af_revenue`、`af_currency`
//  （集成伙伴回传「事件值与收入」依赖上述字段；未链接 AppsFlyerLib 时仅打印）。
//

import Foundation
#if canImport(AppsFlyerLib)
import AppsFlyerLib
#endif

enum RechargeAFLogger {
    private static let kHasEverRechargedKeyPrefix = "bbb.hasEverRechargedSuccess"
    private static let kRevenueCacheKeyPrefix = "bbb.rechargeRevenueCache"
    private static let kRevenueCacheTimeKeyPrefix = "bbb.rechargeRevenueCacheTime"
    private static let revenueCacheTTL: TimeInterval = 24 * 60 * 60

    private static let defaults = UserDefaults.standard

    /// 充值成功统一入口：按用户维度判断是否首充，并依次上报 `recharge_first_success`（0 USD）与 `af_purchase`（实付）
    static func logRechargeSuccess(revenueUSD: Double) async {
        let userKey = await currentRechargeUserKey()
        let hasEverRechargedKey = "\(kHasEverRechargedKeyPrefix).\(userKey)"
        let isFirstRecharge = !defaults.bool(forKey: hasEverRechargedKey)

        if isFirstRecharge {
            defaults.set(true, forKey: hasEverRechargedKey)
            logRechargeFirstSuccess()
        }

        logAFPurchase(revenueUSD: revenueUSD)
    }

    /// Apple 支付：下单后缓存金额，成功确认或漏单恢复时用 `orderId` 取出并清除
    static func cacheRevenue(_ revenueUSD: Double, forOrderId orderId: String) {
        guard !orderId.isEmpty else { return }
        let revenueKey = "\(kRevenueCacheKeyPrefix).\(orderId)"
        let timeKey = "\(kRevenueCacheTimeKeyPrefix).\(orderId)"
        defaults.set(revenueUSD, forKey: revenueKey)
        defaults.set(Date().timeIntervalSince1970, forKey: timeKey)
        print("📱 [RechargeAF] cacheRevenue orderId=\(orderId) revenueUSD=\(revenueUSD)")
    }

    /// 取出并清除缓存；过期或金额为 0 返回 nil（与 glam 行为一致）
    static func getAndClearCachedRevenue(forOrderId orderId: String) -> Double? {
        guard !orderId.isEmpty else { return nil }
        let revenueKey = "\(kRevenueCacheKeyPrefix).\(orderId)"
        let timeKey = "\(kRevenueCacheTimeKeyPrefix).\(orderId)"

        let now = Date().timeIntervalSince1970
        let ts = defaults.double(forKey: timeKey)
        guard ts > 0, now - ts <= revenueCacheTTL else {
            defaults.removeObject(forKey: revenueKey)
            defaults.removeObject(forKey: timeKey)
            return nil
        }

        let revenue = defaults.double(forKey: revenueKey)
        defaults.removeObject(forKey: revenueKey)
        defaults.removeObject(forKey: timeKey)
        print("📱 [RechargeAF] getAndClearCachedRevenue orderId=\(orderId) revenueUSD=\(revenue)")
        return revenue == 0 ? nil : revenue
    }

    private static func currentRechargeUserKey() async -> String {
        if let auth = await AuthRepository.shared.getCurrentAuthInfo(), !auth.userid.isEmpty {
            return auth.userid
        }
        return "anonymous"
    }

    /// 首次充值成功：`recharge_first_success`，固定 0 USD（与 Meta 映射 Subscribe 的常见配置一致）
    private static func logRechargeFirstSuccess() {
        #if canImport(AppsFlyerLib)
        let values: [String: Any] = [
            "af_revenue": 0,
            "af_currency": "USD"
        ]
        AppsFlyerLib.shared().logEvent("recharge_first_success", withValues: values)
        print("[AF] event sent: recharge_first_success | af_revenue=0 af_currency=USD")
        #else
        print("⚠️ [AF上报] recharge_first_success: AppsFlyerLib 未链接，未上报")
        #endif
    }

    /// 每次充值成功：`af_purchase`，实付美元（与 Meta 映射 Purchase 的常见配置一致）
    private static func logAFPurchase(revenueUSD: Double) {
        #if canImport(AppsFlyerLib)
        let values: [String: Any] = [
            "af_revenue": revenueUSD,
            "af_currency": "USD"
        ]
        AppsFlyerLib.shared().logEvent("af_purchase", withValues: values)
        print("[AF] event sent: af_purchase | af_revenue=\(revenueUSD) af_currency=USD")
        #else
        print("⚠️ [AF上报] af_purchase: AppsFlyerLib 未链接，revenueUSD=\(revenueUSD)")
        #endif
    }
}
