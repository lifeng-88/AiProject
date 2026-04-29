//
//  AFConfigManager.swift
//  bbb
//
//  按渠道提供 AppsFlyer 的 Apple App ID 与 Dev Key。
//  默认从 Info.plist 读取；未配置时返回 nil，`AFService` 将跳过 AF 初始化。
//  可在后续接入远程 config 后扩展为异步拉取。
//

import Foundation

final class AFConfigManager: @unchecked Sendable {
    static let shared = AFConfigManager()

    /// Info.plist 键，与后端 / 运营约定一致即可
    private enum InfoKeys {
        static let appleAppID = "AppsFlyerAppleAppID"
        static let devKey = "AppsFlyerDevKey"
    }

    private init() {}

    func getAppleAppID(channelId: String) async -> String? {
        stringFromInfoPlist(InfoKeys.appleAppID)
    }

    func getAppsFlyerDevKey(channelId: String) async -> String? {
        stringFromInfoPlist(InfoKeys.devKey)
    }

    private func stringFromInfoPlist(_ key: String) -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !(trimmed.hasPrefix("$(") && trimmed.hasSuffix(")")) else { return nil }
        return trimmed
    }
}
