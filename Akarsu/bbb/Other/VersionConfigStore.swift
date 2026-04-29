//
//  VersionConfigStore.swift
//  bbb
//
//  启动时拉取 `/v1/version_config`：`type == 1` → 充值只走 StoreKit，不弹支付方式 Sheet；`type == 2` → 弹 `RechargePaymentSelectionView`（或其它值/失败时默认 2）
//

import Foundation
import SwiftUI

@MainActor
final class VersionConfigStore: ObservableObject {
    /// 1：点充值直接拉起系统内购（不弹支付方式选择）；2：先弹支付方式选择 Sheet（其它值或接口失败时默认 2）
    @Published private(set) var rechargePresentationType: Int = 2

    func refresh() async {
        let channel = await AppConfig.shared.getChannel()
        let version = await DeviceManager.shared.getAppVersion()
        let result = await VersionConfigAPI.fetchVersionConfig(channel: channel, version: version)
        switch result {
        case .success(let resp):
            /// `type`：1 = Recharge Now 直接内购；2 = 支付选择弹窗（与 `VersionConfigResponse` 注释一致）
            if let t = resp.type, t == 1 || t == 2 {
                rechargePresentationType = t
            } else {
                rechargePresentationType = 2
            }
        case .failure:
            rechargePresentationType = 2
        }
    }
}
