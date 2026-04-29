//
//  BalanceManager.swift
//  bbb
//
//  与 IAP / 充值确认后余额同步；可后续接入 UserAPI 与 UserWalletStore
//

import Foundation

@MainActor
final class BalanceManager: ObservableObject {
    static let shared = BalanceManager()

    weak var wallet: UserWalletStore?

    private init() {}

    /// 是否已绑定 `UserWalletStore`（`ContentView.onAppear` 注入；未绑定时 `refreshBalance` 无法写余额）
    var isWalletBound: Bool { wallet != nil }

    func bindWallet(_ store: UserWalletStore) {
        wallet = store
    }

    func refreshBalance() async {
        guard let wallet else { return }
        let userId = await AuthRepository.shared.getCurrentAuthInfo()?.userid
        await wallet.syncCoinBalanceFromServer(userId: userId)
    }

    func updateBalance(_ balance: String?) {
        wallet?.applyServerBalanceString(balance)
    }
}
