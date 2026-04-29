//
//  IAPManager.swift
//  glam
//
//  StoreKit 2 消耗型内购：先下单再购买，用 transaction.id 调服务端验证，支持 Transaction.updates 漏单
//

import Combine
import Foundation
import StoreKit

/// 消耗型内购结果：(success, goldAmount)，success 且 goldAmount>0 为支付成功，success 且 goldAmount==0 表示用户取消
typealias IAPPurchaseCallback = (Bool, Int) -> Void

@MainActor
final class IAPManager: ObservableObject {
    static let shared = IAPManager()

    private let rechargeRepository = RechargeRepository.shared
    private let authRepository = AuthRepository.shared
    private let mapping = IAPOrderMapping.shared

    /// 是否正在购买（防重复点击）
    private(set) var isPurchasing = false

    private init() {}

    /// 统一上报支付失败（runIAPPurchaseFlow 早期失败、模拟器无商品等场景也会上报）
    private func reportPayFail(package: Package, orderId: String?, reason: String, payChannelId: Int32) {
        Task {
            var extra: [String: Any] = [
                "package_id": String(package.id),
                "payment_method": "apple_pay",
                "pay_channel_id": Int(payChannelId),
                "amount": package.discountPrice,
                "success": false,
                "reason": reason
            ]
            if let oid = orderId, !oid.isEmpty {
                extra["order_id"] = oid
            }
            await BehaviorEventQueue.shared.enqueue(
                eventType: "recharge_pay_fail",
                templateId: "",
                taskId: nil,
                ts: nil,
                extra: extra
            )
        }
    }

    // MARK: - 方案1 按需取 Product 的完整流程（供 RechargeView / PayChannelSelectionView / InsufficientBalancePackageSheet 调用）

    /// 按需取 Product → 先下单再购买，返回 (success, gold)，success 且 gold>0 为支付成功，success 且 gold==0 为用户取消
    /// - Parameter payChannelId: 与 `/v3/pay_channels` 中 Apple 渠道一致（常为 1，也可能由服务端配置）
    func runIAPPurchaseFlow(package: Package, payChannelId: Int32) async -> (success: Bool, gold: Int) {
        /// 与「Apple Pay / App Store 支付」一致：数字商品仅允许 IAP；设备关闭 App 内购买时不可发起
        guard Self.deviceAllowsInAppPurchases() else {
            reportPayFail(package: package, orderId: nil, reason: "payments_disabled", payChannelId: payChannelId)
            return (false, 0)
        }
        guard let authInfo = await authRepository.getCurrentAuthInfo() else {
            reportPayFail(package: package, orderId: nil, reason: "auth_required", payChannelId: payChannelId)
            return (false, 0)
        }
        guard let productId = package.resolvedAppleProductId else {
            reportPayFail(package: package, orderId: nil, reason: "no_product_id", payChannelId: payChannelId)
            return (false, 0)
        }
        guard let products = try? await Product.products(for: [productId]),
              let product = products.first else {
            // 模拟器上 StoreKit 常无法加载商品，会走这里
            reportPayFail(package: package, orderId: nil, reason: "no_product", payChannelId: payChannelId)
            return (false, 0)
        }
        let orderResult = await rechargeRepository.createRechargeOrder(
            userId: authInfo.userid,
            packageId: package.id,
            payChannelId: payChannelId,
            transactionId: nil
        )
        guard case .success(let orderId) = orderResult else {
            reportPayFail(package: package, orderId: nil, reason: "order_create_failed", payChannelId: payChannelId)
            return (false, 0)
        }
        // AF 充值上报：Apple Pay 成功/漏单时按 orderId 取金额上报
        RechargeAFLogger.cacheRevenue(Double(package.discountPrice) / 100.0, forOrderId: orderId)
        // 支付类埋点：发起支付
        Task {
            var extra: [String: Any] = [
                "order_id": orderId,
                "package_id": String(package.id),
                "payment_method": "apple_pay",
                "pay_channel_id": Int(payChannelId),
                "amount": package.discountPrice
            ]
            await BehaviorEventQueue.shared.enqueue(
                eventType: "recharge_pay_start",
                templateId: "",
                taskId: nil,
                ts: nil,
                extra: extra
            )
        }
        return await withCheckedContinuation { cont in
            Task { @MainActor in
                await self.purchaseConsumableProduct(
                    product,
                    orderId: orderId,
                    package: package,
                    payChannelId: payChannelId
                ) { success, gold in
                    cont.resume(returning: (success, gold))
                }
            }
        }
    }

    // MARK: - 漏单监听

    /// 应用启动时调用：`unfinished` 与 `updates` 分别监听（避免遗漏未 finish 的消耗型交易；服务端确认幂等）
    func startListening() {
        Task.detached(priority: .background) {
            for await result in Transaction.unfinished {
                await Self.handleTransactionResult(result)
            }
        }
        Task.detached(priority: .background) {
            for await result in Transaction.updates {
                await Self.handleTransactionResult(result)
            }
        }
    }

    private static func handleTransactionResult(_ result: VerificationResult<Transaction>) async {
        switch result {
        case .verified(let transaction):
            let uuidString = transaction.appAccountToken?.uuidString ?? ""
            let orderId = IAPOrderMapping.shared.getOrderId(from: uuidString)
            if orderId.isEmpty {
                return
            }
            let payChannelId = IAPOrderMapping.shared.getPayChannelId(from: uuidString)
            let confirmResult = await RechargeRepository.shared.confirmRecharge(
                orderId: orderId,
                transactionId: String(transaction.id),
                payChannelId: payChannelId
            )
            switch confirmResult {
            case .success(let response):
                let isDuplicateSuccess = !response.success && RechargeOrderVerification.isDuplicateOrderSuccess(response.message)
                if response.success || isDuplicateSuccess {
                    await transaction.finish()
                    IAPOrderMapping.shared.remove(for: uuidString)
                    if isDuplicateSuccess {
                        await BalanceManager.shared.refreshBalance()
                    } else if let balance = response.balance {
                        await MainActor.run {
                            BalanceManager.shared.updateBalance(balance)
                        }
                    } else {
                        await BalanceManager.shared.refreshBalance()
                    }
                    if let revenueUSD = RechargeAFLogger.getAndClearCachedRevenue(forOrderId: orderId) {
                        await RechargeAFLogger.logRechargeSuccess(revenueUSD: revenueUSD)
                    }
                }
            case .failure(let error):
                if error.isOrderDuplicateError {
                    await transaction.finish()
                    IAPOrderMapping.shared.remove(for: uuidString)
                    await BalanceManager.shared.refreshBalance()
                }
            }
        case .unverified:
            break
        }
    }

    // MARK: - 发起消耗型内购

    /// 发起一次消耗型内购（调用前需已通过 createRechargeOrder 拿到 orderId）
    /// - Parameters:
    ///   - product: StoreKit Product（按需通过 Product.products(for: [appleProductId]) 获取）
    ///   - orderId: 服务端返回的订单号
    ///   - package: 套餐信息（用于埋点）
    ///   - completion: (success, goldAmount)，success 且 goldAmount>0 为支付成功，success 且 goldAmount==0 为用户取消，success==false 为失败
    func purchaseConsumableProduct(
        _ product: Product,
        orderId: String,
        package: Package,
        payChannelId: Int32,
        completion: @escaping IAPPurchaseCallback
    ) async {
        guard product.type == .consumable else {
            // 支付类埋点：支付失败（非消耗型商品）
            Task {
                var extra: [String: Any] = [
                    "order_id": orderId,
                    "package_id": String(package.id),
                    "payment_method": "apple_pay",
                    "pay_channel_id": Int(payChannelId),
                    "amount": package.discountPrice,
                    "success": false,
                    "reason": "invalid_product"
                ]
                await BehaviorEventQueue.shared.enqueue(
                    eventType: "recharge_pay_fail",
                    templateId: "",
                    taskId: nil,
                    ts: nil,
                    extra: extra
                )
            }
            completion(false, 0)
            return
        }
        if isPurchasing {
            completion(false, 0)
            return
        }

        isPurchasing = true
        defer { isPurchasing = false }

        let orderUUID = UUID()
        mapping.save(orderId: orderId, payChannelId: payChannelId, for: orderUUID)

        do {
            let purchaseResult = try await product.purchase(options: [.appAccountToken(orderUUID)])

            switch purchaseResult {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    let uuidString = transaction.appAccountToken?.uuidString ?? ""
                    let mappedOrderId = mapping.getOrderId(from: uuidString)
                    // 某些设备/时序下 appAccountToken 可能丢失，回退到本次下单得到的 orderId，避免已支付却被误判失败
                    let originalOrderId = mappedOrderId.isEmpty ? orderId : mappedOrderId

                    let confirmResult = await rechargeRepository.confirmRecharge(
                        orderId: originalOrderId,
                        transactionId: String(transaction.id),
                        payChannelId: payChannelId
                    )

                    switch confirmResult {
                    case .success(let response):
                        let isDuplicateSuccess = !response.success && RechargeOrderVerification.isDuplicateOrderSuccess(response.message)
                        let treatedAsSuccess = response.success || isDuplicateSuccess
                        if treatedAsSuccess {
                            await transaction.finish()
                            if !uuidString.isEmpty {
                                mapping.remove(for: uuidString)
                            }
                            if isDuplicateSuccess {
                                await BalanceManager.shared.refreshBalance()
                            } else if let balance = response.balance {
                                BalanceManager.shared.updateBalance(balance)
                            } else {
                                await BalanceManager.shared.refreshBalance()
                            }
                            let gold = isDuplicateSuccess ? (Int(package.gold) + Int(package.bonus)) : (Int(response.goldAmount ?? "0") ?? 0)
                            Task {
                                var extra: [String: Any] = [
                                    "order_id": originalOrderId,
                                    "package_id": String(package.id),
                                    "payment_method": "apple_pay",
                                    "pay_channel_id": Int(payChannelId),
                                    "amount": package.discountPrice,
                                    "success": true
                                ]
                                await BehaviorEventQueue.shared.enqueue(
                                    eventType: "recharge_pay_success",
                                    templateId: "",
                                    taskId: nil,
                                    ts: nil,
                                    extra: extra
                                )
                                let revenueUSD = RechargeAFLogger.getAndClearCachedRevenue(forOrderId: originalOrderId) ?? Double(package.discountPrice) / 100.0
                                await RechargeAFLogger.logRechargeSuccess(revenueUSD: revenueUSD)
                            }
                            completion(true, gold)
                        } else {
                            Task {
                                var extra: [String: Any] = [
                                    "order_id": originalOrderId,
                                    "package_id": String(package.id),
                                    "payment_method": "apple_pay",
                                    "pay_channel_id": Int(payChannelId),
                                    "amount": package.discountPrice,
                                    "success": false,
                                    "reason": "server_failed"
                                ]
                                await BehaviorEventQueue.shared.enqueue(
                                    eventType: "recharge_pay_fail",
                                    templateId: "",
                                    taskId: nil,
                                    ts: nil,
                                    extra: extra
                                )
                            }
                            completion(false, 0)
                        }
                    case .failure(let error):
                        if error.isOrderDuplicateError {
                            await transaction.finish()
                            if !uuidString.isEmpty {
                                mapping.remove(for: uuidString)
                            }
                            await BalanceManager.shared.refreshBalance()
                            Task {
                                var extra: [String: Any] = [
                                    "order_id": originalOrderId,
                                    "package_id": String(package.id),
                                    "payment_method": "apple_pay",
                                    "pay_channel_id": Int(payChannelId),
                                    "amount": package.discountPrice,
                                    "success": true
                                ]
                                await BehaviorEventQueue.shared.enqueue(
                                    eventType: "recharge_pay_success",
                                    templateId: "",
                                    taskId: nil,
                                    ts: nil,
                                    extra: extra
                                )
                                let revenueUSD = RechargeAFLogger.getAndClearCachedRevenue(forOrderId: originalOrderId) ?? Double(package.discountPrice) / 100.0
                                await RechargeAFLogger.logRechargeSuccess(revenueUSD: revenueUSD)
                            }
                            // 重复订单视为已到账，返回套餐金币数以便 UI 显示成功（否则 gold==0 会被 RechargeView 判为失败）
                            let duplicateGold = Int(package.gold) + Int(package.bonus)
                            completion(true, duplicateGold)
                        } else {
                            Task {
                                var extra: [String: Any] = [
                                    "order_id": originalOrderId,
                                    "package_id": String(package.id),
                                    "payment_method": "apple_pay",
                                    "pay_channel_id": Int(payChannelId),
                                    "amount": package.discountPrice,
                                    "success": false,
                                    "reason": "confirm_failed"
                                ]
                                await BehaviorEventQueue.shared.enqueue(
                                    eventType: "recharge_pay_fail",
                                    templateId: "",
                                    taskId: nil,
                                    ts: nil,
                                    extra: extra
                                )
                            }
                            completion(false, 0)
                        }
                    }

                case .unverified:
                    Task {
                        var extra: [String: Any] = [
                            "order_id": orderId,
                            "package_id": String(package.id),
                            "payment_method": "apple_pay",
                            "pay_channel_id": Int(payChannelId),
                            "amount": package.discountPrice,
                            "success": false,
                            "reason": "unverified"
                        ]
                        await BehaviorEventQueue.shared.enqueue(
                            eventType: "recharge_pay_fail",
                            templateId: "",
                            taskId: nil,
                            ts: nil,
                            extra: extra
                        )
                    }
                    completion(false, 0)
                }

            case .userCancelled:
                mapping.remove(for: orderUUID.uuidString)
                // 支付类埋点：用户取消
                Task {
                    var extra: [String: Any] = [
                        "order_id": orderId,
                        "package_id": String(package.id),
                        "payment_method": "apple_pay",
                        "pay_channel_id": Int(payChannelId),
                        "amount": package.discountPrice,
                        "success": false,
                        "reason": "user_cancelled"
                    ]
                    await BehaviorEventQueue.shared.enqueue(
                        eventType: "recharge_pay_fail",
                        templateId: "",
                        taskId: nil,
                        ts: nil,
                        extra: extra
                    )
                }
                completion(true, 0) // 约定：success=true, gold=0 表示用户取消

            case .pending:
                // 支付类埋点：支付失败（待处理/审核中）
                Task {
                    var extra: [String: Any] = [
                        "order_id": orderId,
                        "package_id": String(package.id),
                        "payment_method": "apple_pay",
                        "pay_channel_id": Int(payChannelId),
                        "amount": package.discountPrice,
                        "success": false,
                        "reason": "pending"
                    ]
                    await BehaviorEventQueue.shared.enqueue(
                        eventType: "recharge_pay_fail",
                        templateId: "",
                        taskId: nil,
                        ts: nil,
                        extra: extra
                    )
                }
                completion(false, 0)

            @unknown default:
                // 支付类埋点：支付失败（未知结果）
                Task {
                    var extra: [String: Any] = [
                        "order_id": orderId,
                        "package_id": String(package.id),
                        "payment_method": "apple_pay",
                        "pay_channel_id": Int(payChannelId),
                        "amount": package.discountPrice,
                        "success": false,
                        "reason": "unknown"
                    ]
                    await BehaviorEventQueue.shared.enqueue(
                        eventType: "recharge_pay_fail",
                        templateId: "",
                        taskId: nil,
                        ts: nil,
                        extra: extra
                    )
                }
                completion(false, 0)
        }
        } catch {
            mapping.remove(for: orderUUID.uuidString)
            Task {
                var extra: [String: Any] = [
                    "order_id": orderId,
                    "package_id": String(package.id),
                    "payment_method": "apple_pay",
                    "pay_channel_id": Int(payChannelId),
                    "amount": package.discountPrice,
                    "success": false,
                    "reason": "exception"
                ]
                await BehaviorEventQueue.shared.enqueue(
                    eventType: "recharge_pay_fail",
                    templateId: "",
                    taskId: nil,
                    ts: nil,
                    extra: extra
                )
            }
            completion(false, 0)
        }
    }
}

// MARK: - App Store / Apple Pay（数字商品仅 IAP）

extension IAPManager {
    /// 设备是否允许 App 内购买（「屏幕使用时间 → App 内购买」关闭、家长控制等为 false）。
    /// iOS 上虚拟商品通过 **App Store / StoreKit** 扣款，支付方式由系统 sheet 决定（含 Apple ID 已绑定的银行卡、Apple Pay 钱包等）。
    nonisolated static func deviceAllowsInAppPurchases() -> Bool {
        SKPaymentQueue.canMakePayments()
    }

    /// 人类可读说明：用于充值页提示（随 `AppLanguageStore` / 系统语言切换）
    static var appStorePaymentsDisabledMessage: String {
        AppLanguageStore.localized("iap.payments_disabled")
    }

    /// 商店是否已上架该消耗型商品 ID（模拟器未配置 StoreKit 配置时常为 false）
    func storeProductIsListed(appleProductId: String) async -> Bool {
        guard !appleProductId.isEmpty else { return false }
        guard let products = try? await Product.products(for: [appleProductId]) else { return false }
        return products.first != nil
    }
}
