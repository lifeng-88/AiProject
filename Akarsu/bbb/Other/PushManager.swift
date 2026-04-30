//
//  PushManager.swift
//  bbb
//
//  APNs device token 内存持有；上报 `POST /v1/push_id` 在已登录时异步执行（与 glam PushManager 一致：勿在主线程 await 网络）。
//

import Foundation
import UIKit
import UserNotifications

/// 推送标识：上报 `POST /v1/push_id` 时使用 APNs device token 的十六进制串。
final class PushManager {
    static let shared = PushManager()

    private let lock = NSLock()
    private var deviceTokenHex: String?

    private init() {}

    /// 冷启动尽早向 APNs 注册。**横幅/声音权限与 device token 无关**：未决定或已拒绝时也应调用，否则拿不到 token、`/v1/push_id` 无法上报，服务端无法下发（与 Apple「尽早 register」一致）。
    func registerForRemoteNotificationsAtLaunch() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let status = settings.authorizationStatus
            switch status {
            case .authorized, .provisional, .ephemeral:
                print("📲 [PushManager] Launch: UN 已允许/临时授权 (raw=\(status.rawValue))")
            case .notDetermined:
                print("📲 [PushManager] Launch: UN 未决定 (raw=\(status.rawValue))，仍注册 APNs；要收到横幅请到「我的」相关页或系统设置开启通知")
            case .denied:
                print("📲 [PushManager] Launch: UN 已拒绝 (raw=\(status.rawValue))，仍注册 APNs；要收到锁屏/横幅请在 设置 → 通知 中开启本应用")
            @unknown default:
                print("📲 [PushManager] Launch: UN 未知状态 raw=\(status.rawValue)")
            }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
                print("📲 [PushManager] Launch: registerForRemoteNotifications()")
            }
        }
    }

    /// 关键业务成功后：未决定则弹系统权限；已允许则再 register 兜底；已拒绝则忽略（可与 glam 任务成功后请求对齐，按需调用）。
    func requestAuthorizationAfterTaskCreatedSuccess() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                    print("📲 [PushManager] Post-task: registerForRemoteNotifications (already authorized)")
                }
            case .notDetermined:
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    guard granted else {
                        print("📲 [PushManager] Post-task: notification permission denied")
                        return
                    }
                    DispatchQueue.main.async {
                        UIApplication.shared.registerForRemoteNotifications()
                        print("📲 [PushManager] Post-task: registerForRemoteNotifications after grant")
                    }
                }
            case .denied:
                print("📲 [PushManager] Post-task: notification denied in Settings, skip")
            @unknown default:
                break
            }
        }
    }

    func setAPNsDeviceToken(_ data: Data) {
        let hex = data.map { String(format: "%02hhx", $0) }.joined()
        print("📲 [push_id] \(hex)")
        print("📲 [PushManager] Saved device token (\(hex.count) hex chars)")
        lock.lock()
        deviceTokenHex = hex
        lock.unlock()
        Task.detached(priority: .utility) {
            await PushManager.shared.syncPushIdToServerIfAuthenticated()
        }
    }

    func currentPushId() -> String? {
        lock.lock()
        defer { lock.unlock() }
        let s = deviceTokenHex?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (s?.isEmpty == false) ? s : nil
    }

    /// 已有 token 且本地已登录时向服务端同步（token 晚于登录回调、或登录成功后补报）。
    func syncPushIdToServerIfAuthenticated() async {
        guard let hex = currentPushId(), !hex.isEmpty else { return }
        guard await AuthRepository.shared.getCurrentAuthInfo() != nil else { return }
        _ = await AuthAPI.updatePushId(pushId: hex)
    }
}
