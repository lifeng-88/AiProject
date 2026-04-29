//
//  RechargeAPI.swift
//  glam
//
//  Created by Dev on 2026/1/19.
//

import Combine
import Foundation

/// 充值相关 API
struct RechargeAPI {
    static let client = APIClient.shared
    
    /// 获取充值套餐列表
    /// - Parameter channelId: 渠道ID（必填）
    static func getPackages(channelId: String) async -> Result<PackagesResponse, AppError> {
        let parameters: [String: Any] = [
            "channel_id": channelId
        ]
        return await client.request(
            "/v1/packages",
            method: .get,
            parameters: parameters
        )
    }
    
    /// 获取支付渠道列表
    /// - Parameter channelId: 渠道ID（必填）
    static func getPayChannels(channelId: String) async -> Result<PayChannelsResponse, AppError> {
        let parameters: [String: Any] = [
            "channel_id": channelId
        ]
        return await client.request(
            "/v3/pay_channels",
            method: .get,
            parameters: parameters
        )
    }
    
    /// 检查官方 Apple Pay 可用性
    static func getOfficialApplePay() async -> Result<OfficialApplePayResponse, AppError> {
        return await client.request(
            "/v1/official_apple_pay",
            method: .get
        )
    }
    
    /// 获取 Apple Pay Session
    static func getApplePaySession(validationURL: String) async -> Result<ApplePaySessionResponse, AppError> {
        let request = ApplePaySessionRequest(validationURL: validationURL)
        return await client.request(
            "/v1/apple_pay/sessions",
            method: .post,
            parameters: try? request.toDictionary()
        )
    }
    
    /// 创建充值订单
    /// - Parameters:
    ///   - returnUrl: 三方回调服务端的 Webhook URL（可选，不传时服务端从 pay_channel 配置取）
    ///   - pageUrl: 支付完成后客户端跳转地址（仅 33001/33002/33003，如 {api_base}/payment/return）
    ///   - payload: 重定向支付用户填写信息 JSON
    /// - Note: 协议已调整，无 cancel_url；取消场景由客户端或三方页面自行处理
    static func createRechargeOrder(
        userId: String,
        packageId: Int32,
        payChannelId: Int32,
        transactionId: String? = nil,
        returnUrl: String? = nil,
        pageUrl: String? = nil,
        payload: String? = nil
    ) async -> Result<CreateRechargeOrderResponse, AppError> {
        var params: [String: Any] = [
            "package_id": packageId,
            "pay_channel_id": payChannelId
        ]
        if let t = transactionId, !t.isEmpty { params["transaction_id"] = t }
        if let r = returnUrl, !r.isEmpty { params["return_url"] = r }
        if let u = pageUrl, !u.isEmpty { params["page_url"] = u }
        if let p = payload, !p.isEmpty { params["payload"] = p }
        return await client.request(
            "/v1/users/\(userId)/recharges",
            method: .post,
            parameters: params
        )
    }

    /// 查询订单支付状态（重定向支付 return_url 回调后调用）
    static func getOrderPaymentStatus(orderId: String) async -> Result<OrderPaymentStatusResponse, AppError> {
        return await client.request(
            "/v1/orders/\(orderId)/payment_status",
            method: .get
        )
    }
    
    /// 确认充值
    /// - Parameters:
    ///   - orderId: 订单 ID
    ///   - transactionId: 支付方交易号（Apple Pay 等必填；信用卡支付传 nil 或空字符串）
    ///   - payChannelId: 支付渠道 ID（信用卡为 2）
    ///   - payload: 信用卡支付时必填（新卡 JSON 或 {"payment_card_id": id}）；其他渠道传 nil
    static func confirmRecharge(orderId: String, transactionId: String?, payChannelId: Int32, payload: String? = nil) async -> Result<ConfirmRechargeResponse, AppError> {
        let request = ConfirmRechargeRequest(
            orderId: orderId,
            transactionId: transactionId ?? "",
            payChannelId: payChannelId,
            payload: payload
        )
        return await client.request(
            "/v1/recharges/confirm",
            method: .post,
            parameters: try? request.toDictionary()
        )
    }
    
    /// 获取充值记录列表（支持分页）
    /// - Parameters:
    ///   - userId: 用户 ID
    ///   - pageToken: 分页游标，首次不传
    ///   - pageSize: 每页条数，默认 20
    static func getRechargeRecords(userId: String, pageToken: String? = nil, pageSize: Int32 = 20) async -> Result<RechargeRecordsResponse, AppError> {
        var parameters: [String: Any] = ["page_size": pageSize]
        if let token = pageToken, !token.isEmpty {
            parameters["page_token"] = token
        }
        return await client.request(
            "/v1/users/\(userId)/recharges",
            method: .get,
            parameters: parameters
        )
    }
    
    // MARK: - Payment Cards
    
    /// 获取支付卡列表
    static func getPaymentCards(userId: Int64) async -> Result<PaymentCardsResponse, AppError> {
        let parameters: [String: Any] = [
            "user_id": userId
        ]
        return await client.request(
            "/v1/payment-cards",
            method: .get,
            parameters: parameters
        )
    }
    
    /// 创建支付卡
    static func createPaymentCard(request: CreatePaymentCardRequest) async -> Result<CreatePaymentCardResponse, AppError> {
        return await client.request(
            "/v1/payment-cards",
            method: .post,
            parameters: try? request.toDictionary()
        )
    }
    
    /// 删除支付卡
    static func deletePaymentCard(id: Int64) async -> Result<EmptyResponse, AppError> {
        return await client.request(
            "/v1/payment-cards/\(id)",
            method: .delete
        )
    }
}

// MARK: - Empty Response

/// 空响应（用于 DELETE 等不需要返回数据的接口）
struct EmptyResponse: Codable {
}

// MARK: - Codable Extension for Dictionary

extension Encodable {
    func toDictionary() throws -> [String: Any] {
        let data = try JSONEncoder().encode(self)
        guard let dictionary = try JSONSerialization.jsonObject(with: data, options: .allowFragments) as? [String: Any] else {
            throw NSError(domain: "EncodingError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert to dictionary"])
        }
        return dictionary
    }
}
