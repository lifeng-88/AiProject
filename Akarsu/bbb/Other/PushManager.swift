//
//  PushManager.swift
//  bbb
//

import Foundation

/// 推送标识（接入 APNs / 三方推送后可在此返回 device token 或别名）。
final class PushManager {
    static let shared = PushManager()

    private init() {}

    func currentPushId() -> String? {
        nil
    }
}
