//
//  RechargeRepository.swift
//  glam
//
//  Created by Dev on 2026/1/19.
//

import Foundation

/// 充值 Repository 实现
actor RechargeRepository: RechargeRepositoryProtocol {
    static let shared = RechargeRepository()
    
    private init() {}
    
    // MARK: - RechargeRepositoryProtocol
    
    func getPackages() async -> Result<[Package], AppError> {
        // 从AppConfig中获取channel_id
        let appConfig = AppConfig.shared
        let channelId = await appConfig.getChannel()
        
        let result = await RechargeAPI.getPackages(channelId: channelId)
        return result.map { $0.list }
    }
    
    func getPayChannels() async -> Result<[PayChannel], AppError> {
        // 从AppConfig中获取channel_id
        let appConfig = AppConfig.shared
        let channelId = await appConfig.getChannel()
        
        let result = await RechargeAPI.getPayChannels(channelId: channelId)
        return result.map { $0.list }
    }
    
    func getOfficialApplePay() async -> Result<Bool, AppError> {
        let result = await RechargeAPI.getOfficialApplePay()
        return result.map { $0.enabled }
    }
    
    func getApplePaySession(validationURL: String) async -> Result<String, AppError> {
        let result = await RechargeAPI.getApplePaySession(validationURL: validationURL)
        return result.map { $0.sessionPayload }
    }
    
    func createRechargeOrder(userId: String, packageId: Int32, payChannelId: Int32, offerId: String?) async -> Result<String, AppError> {
        let result = await RechargeAPI.createRechargeOrder(
            userId: userId,
            packageId: packageId,
            payChannelId: payChannelId,
            returnUrl: nil,
            pageUrl: nil,
            payload: nil,
            offerId: offerId
        )
        return result.map { $0.orderId }
    }
    
    func createRedirectRechargeOrder(userId: String, packageId: Int32, payChannelId: Int32, pageUrl: String, payload: String, offerId: String?) async -> Result<CreateRechargeOrderResponse, AppError> {
        return await RechargeAPI.createRechargeOrder(
            userId: userId,
            packageId: packageId,
            payChannelId: payChannelId,
            returnUrl: nil,
            pageUrl: pageUrl,
            payload: payload,
            offerId: offerId
        )
    }
    
    func getOrderPaymentStatus(orderId: String) async -> Result<OrderPaymentStatusResponse, AppError> {
        return await RechargeAPI.getOrderPaymentStatus(orderId: orderId)
    }
    
    func confirmRecharge(orderId: String, transactionId: String?, payChannelId: Int32, payload: String? = nil) async -> Result<ConfirmRechargeResponse, AppError> {
        return await RechargeAPI.confirmRecharge(orderId: orderId, transactionId: transactionId, payChannelId: payChannelId, payload: payload)
    }
    
    func getRechargeRecords(userId: String, pageToken: String? = nil) async -> Result<(list: [RechargeRecord], nextPageToken: String?), AppError> {
        let result = await RechargeAPI.getRechargeRecords(userId: userId, pageToken: pageToken)
        return result.map { ($0.list, $0.nextPageToken.flatMap { $0.isEmpty ? nil : $0 }) }
    }
    
    // MARK: - Payment Cards
    
    func getPaymentCards(userId: Int64) async -> Result<[PaymentCard], AppError> {
        let result = await RechargeAPI.getPaymentCards(userId: userId)
        return result.map { $0.cards }
    }
    
    func createPaymentCard(request: CreatePaymentCardRequest) async -> Result<Int64, AppError> {
        let result = await RechargeAPI.createPaymentCard(request: request)
        return result.map { $0.id }
    }
    
    func deletePaymentCard(id: Int64) async -> Result<Void, AppError> {
        let result = await RechargeAPI.deletePaymentCard(id: id)
        return result.map { _ in () }
    }
}
