//
//  DeviceManager.swift
//  bbb
//

import Foundation
import UIKit

actor DeviceManager {
    static let shared = DeviceManager()

    #if DEBUG
    /// Debug 联调：登录与埋点统一使用固定 `devId`（与真机 Keychain / `identifierForVendor` 解耦）
    private static let debugDefaultDeviceId = "C54E5F2F-64C6-4C7A-88CB-7A5F329F2D47"
    #endif

    /// Release：与登录/埋点共用的设备标识；存 Keychain，卸载重装前保持不变（与 `identifierForVendor` 解耦，避免 idfv 为空时每次随机）
    private static let keychainDevIdAccount = "bbb.devId"

    private init() {}

    /// 持久化 `devId`：Debug 固定值；Release 优先读 Keychain，首次写入优先 `identifierForVendor`，否则随机 UUID。
    func getDeviceId() async -> String {
        #if DEBUG
        return Self.debugDefaultDeviceId
        #else
        let keychain = KeychainManager.shared
        if let saved = await keychain.load(key: Self.keychainDevIdAccount),
           !saved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return saved
        }

        let newId: String = await MainActor.run {
            UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        }

        do {
            try await keychain.save(key: Self.keychainDevIdAccount, value: newId)
        } catch {
            // 写入失败仍返回本次 id，避免阻塞登录；下次冷启动会重试生成
        }
        return newId
        #endif
    }

    /// 调用登录/静默设备登录时传入的 `devId`（与 `getDeviceId()` 一致）
    func deviceIdForLogin() async -> String {
        await getDeviceId()
    }

    func getAppVersion() async -> String {
        await MainActor.run {
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        }
    }
}
