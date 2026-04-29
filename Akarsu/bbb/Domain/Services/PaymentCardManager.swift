//
//  PaymentCardManager.swift
//  glam
//
//  Created by Dev on 2026/1/26.
//

import Foundation
import SwiftUI
import Combine

/// 支付卡管理器
@MainActor
class PaymentCardManager: ObservableObject {
    static let shared = PaymentCardManager()
    
    @Published var paymentCards: [PaymentCard] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let rechargeRepository = RechargeRepository.shared
    private var currentUserId: Int64?
    
    private init() {}
    
    /// 加载支付卡列表
    func loadPaymentCards(userId: Int64) async {
        // 如果用户ID相同且已有数据，不重复加载
        if currentUserId == userId && !paymentCards.isEmpty {
            return
        }
        
        currentUserId = userId
        isLoading = true
        errorMessage = nil
        
        let result = await rechargeRepository.getPaymentCards(userId: userId)
        
        switch result {
        case .success(let cards):
            self.paymentCards = cards
            print("✅ [PaymentCardManager] Loaded \(cards.count) payment cards")
        case .failure(let error):
            self.errorMessage = error.localizedDescription
            print("❌ [PaymentCardManager] Failed to load payment cards: \(error.localizedDescription)")
        }
        
        isLoading = false
    }
    
    /// 刷新支付卡列表
    func refresh(userId: Int64) async {
        currentUserId = nil // 清除缓存，强制重新加载
        await loadPaymentCards(userId: userId)
    }
    
    /// 创建支付卡
    func createPaymentCard(request: CreatePaymentCardRequest) async -> Result<Int64, AppError> {
        let result = await rechargeRepository.createPaymentCard(request: request)
        
        if case .success(let cardId) = result {
            // 创建成功后刷新列表
            if let userId = currentUserId {
                await refresh(userId: userId)
            }
        }
        
        return result
    }
    
    /// 删除支付卡
    func deletePaymentCard(id: Int64) async -> Result<Void, AppError> {
        let result = await rechargeRepository.deletePaymentCard(id: id)
        
        if case .success = result {
            // 删除成功后刷新列表
            if let userId = currentUserId {
                await refresh(userId: userId)
            }
        }
        
        return result
    }
    
    /// 获取默认支付卡
    var defaultCard: PaymentCard? {
        paymentCards.first { $0.isDefault } ?? paymentCards.first
    }
}
