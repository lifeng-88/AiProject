//
//  UserWalletStore.swift
//  bbb
//
//  全应用共享：金币余额、充值流水、已保存支付方式（UserDefaults 持久化）
//

import Combine
import Foundation
import SwiftUI

final class UserWalletStore: ObservableObject {
    @Published var coinBalance: Int
    @Published var transactionHistory: [RechargeRecordItem]
    @Published var savedCards: [SavedPaymentCard]

    private static let balanceFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return f
    }()

    private enum Keys {
        static let balance = "bbb.wallet.coinBalance"
        static let history = "bbb.wallet.transactionHistory"
        static let cards = "bbb.wallet.savedCards"
    }

    private var persistenceCancellables = Set<AnyCancellable>()
    private let defaults = UserDefaults.standard

    init() {
        let d = UserDefaults.standard
        if let balance = d.object(forKey: Keys.balance) as? Int {
            coinBalance = balance
        } else {
            coinBalance = 0
        }

        if let data = d.data(forKey: Keys.history),
           let decoded = try? JSONDecoder().decode([RechargeRecordItem].self, from: data),
           !decoded.isEmpty {
            transactionHistory = decoded
        } else {
            transactionHistory = RechargeRecordItem.sampleList()
        }

        if let data = d.data(forKey: Keys.cards),
           let decoded = try? JSONDecoder().decode([SavedPaymentCard].self, from: data),
           !decoded.isEmpty {
            savedCards = Self.cardsEnsuringDefaultBoundVisa(decoded)
        } else {
            savedCards = [SavedPaymentCard.defaultBoundVisa]
        }

        setupPersistence()
        persist()
    }

    /// 持久化中若无固定 id 的默认 Visa，则补齐；旧版随机 UUID 的 Visa·4242 会合并为同一张默认卡
    private static func cardsEnsuringDefaultBoundVisa(_ cards: [SavedPaymentCard]) -> [SavedPaymentCard] {
        let visa = SavedPaymentCard.defaultBoundVisa
        if cards.isEmpty { return [visa] }
        if cards.contains(where: { $0.id == visa.id }) { return cards }

        var out: [SavedPaymentCard] = []
        var mergedLegacyVisa4242 = false
        for c in cards {
            if !mergedLegacyVisa4242,
               c.brand.caseInsensitiveCompare("Visa") == .orderedSame,
               c.lastFour == "4242" {
                out.append(visa)
                mergedLegacyVisa4242 = true
                continue
            }
            out.append(SavedPaymentCard(id: c.id, brand: c.brand, lastFour: c.lastFour, isDefault: false))
        }
        if !mergedLegacyVisa4242 {
            out = [visa] + out
        }
        return out
    }

    var formattedCoinBalance: String {
        Self.balanceFormatter.string(from: NSNumber(value: coinBalance)) ?? "\(coinBalance)"
    }

    func applySuccessfulPurchase(package: RechargePackageModel, coinsAdded: Int? = nil) {
        let added = coinsAdded ?? package.totalCoins
        coinBalance += added
        transactionHistory.insert(
            RechargeRecordItem(
                createdAt: Date(),
                title: "Coin pack",
                amount: package.price,
                coins: added,
                status: .completed
            ),
            at: 0
        )
    }

    /// IAP 成功后，`BalanceManager` 已将服务端余额写入本地；此处只追加充值流水，避免重复加币
    func appendRechargeRecordOnly(package: RechargePackageModel, coinsAdded: Int? = nil) {
        let added = coinsAdded ?? package.totalCoins
        transactionHistory.insert(
            RechargeRecordItem(
                createdAt: Date(),
                title: "Coin pack",
                amount: package.price,
                coins: added,
                status: .completed
            ),
            at: 0
        )
    }

    /// 创建任务成功后同步扣减本地金币（与模板消耗一致；0 金币模板不扣）
    func applyGenerationSpend(coins: Int) {
        guard coins > 0 else { return }
        coinBalance = max(0, coinBalance - coins)
    }

    /// 将服务端返回的余额字符串解析为金币整数（失败则不变更 `coinBalance`）
    func applyServerBalanceString(_ raw: String?) {
        guard let raw = raw, let n = Self.parseCoinInteger(from: raw) else { return }
        coinBalance = n
    }

    /// 拉取 `/v1/users/{userid}/gold` 并覆盖本地展示余额；未登录或请求失败时保留当前值
    func syncCoinBalanceFromServer(userId: String?) async {
        guard let uid = userId?.trimmingCharacters(in: .whitespacesAndNewlines), !uid.isEmpty else { return }
        let result = await UserAPI.getUserGold(userid: uid)
        await MainActor.run {
            guard case .success(let resp) = result,
                  let n = Self.parseCoinInteger(from: resp.balance) else { return }
            coinBalance = n
        }
    }

    private static func parseCoinInteger(from raw: String) -> Int? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if let v = Int(s) { return max(0, v) }
        if let v = Int64(s) { return max(0, Int(clamping: v)) }
        if let d = Double(s) { return max(0, Int(d.rounded())) }
        return nil
    }

    private func setupPersistence() {
        $coinBalance
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.persist() }
            .store(in: &persistenceCancellables)

        $transactionHistory
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.persist() }
            .store(in: &persistenceCancellables)

        $savedCards
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.persist() }
            .store(in: &persistenceCancellables)
    }

    private func persist() {
        defaults.set(coinBalance, forKey: Keys.balance)
        if let data = try? JSONEncoder().encode(transactionHistory) {
            defaults.set(data, forKey: Keys.history)
        }
        if let data = try? JSONEncoder().encode(savedCards) {
            defaults.set(data, forKey: Keys.cards)
        }
    }
}
