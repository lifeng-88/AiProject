//
//  RechargeRepositoryProtocol.swift
//  glam
//
//  Created by Dev on 2026/1/19.
//

import Foundation

/// 充值 Repository 协议
protocol RechargeRepositoryProtocol {
    /// 获取充值套餐列表
    func getPackages() async -> Result<[Package], AppError>
    
    /// 获取支付渠道列表
    func getPayChannels() async -> Result<[PayChannel], AppError>
    
    /// 检查官方 Apple Pay 可用性
    func getOfficialApplePay() async -> Result<Bool, AppError>
    
    /// 获取 Apple Pay Session
    func getApplePaySession(validationURL: String) async -> Result<String, AppError>
    
    /// 创建充值订单（`offerId` 仅新用户活动套餐由用户点击套餐时传入）
    func createRechargeOrder(userId: String, packageId: Int32, payChannelId: Int32, offerId: String?) async -> Result<String, AppError>
    
    /// 创建重定向支付订单（33001/33002/33003），返回 orderId 与 paymentUrl
    func createRedirectRechargeOrder(userId: String, packageId: Int32, payChannelId: Int32, pageUrl: String, payload: String, offerId: String?) async -> Result<CreateRechargeOrderResponse, AppError>
    
    /// 查询订单支付状态（重定向支付 return_url 回调后调用）
    func getOrderPaymentStatus(orderId: String) async -> Result<OrderPaymentStatusResponse, AppError>
    
    /// 确认充值
    /// - Parameters:
    ///   - payload: 信用卡支付时必填（新卡 JSON 或 {"payment_card_id": id}）；Apple Pay 等传 nil
    func confirmRecharge(orderId: String, transactionId: String?, payChannelId: Int32, payload: String?) async -> Result<ConfirmRechargeResponse, AppError>
    
    /// 获取充值记录列表（支持分页）
    /// - Parameters:
    ///   - userId: 用户 ID
    ///   - pageToken: 分页游标，首次传 nil
    /// - Returns: (list, nextPageToken)
    func getRechargeRecords(userId: String, pageToken: String?) async -> Result<(list: [RechargeRecord], nextPageToken: String?), AppError>
    
    // MARK: - Payment Cards
    
    /// 获取支付卡列表
    func getPaymentCards(userId: Int64) async -> Result<[PaymentCard], AppError>
    
    /// 创建支付卡
    func createPaymentCard(request: CreatePaymentCardRequest) async -> Result<Int64, AppError>
    
    /// 删除支付卡
    func deletePaymentCard(id: Int64) async -> Result<Void, AppError>
}
