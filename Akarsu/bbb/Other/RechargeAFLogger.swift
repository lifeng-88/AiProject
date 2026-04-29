//
//  RechargeAFLogger.swift
//  bbb
//
//  充值金额缓存与 AppsFlyer 收入上报占位；接入 AF 后可实现 logRechargeSuccess
//

import Foundation

@MainActor
enum RechargeAFLogger {
    private static var revenueByOrderId: [String: Double] = [:]

    static func cacheRevenue(_ amount: Double, forOrderId orderId: String) {
        revenueByOrderId[orderId] = amount
    }

    static func getAndClearCachedRevenue(forOrderId orderId: String) -> Double? {
        revenueByOrderId.removeValue(forKey: orderId)
    }

    static func logRechargeSuccess(revenueUSD: Double) async {
        print("📊 [RechargeAFLogger] revenue USD: \(revenueUSD)")
    }
}
