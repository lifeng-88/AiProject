//
//  NotificationPermissionStore.swift
//  bbb
//
//  系统推送 / 本地通知权限状态与请求（与设置页「产品更新」开关联动）。
//

import Combine
import Foundation
import UIKit
import UserNotifications

@MainActor
final class NotificationPermissionStore: ObservableObject {
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    init() {
        Task { await refreshAuthorizationStatus() }
    }

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    /// 弹出系统授权面板；成功则注册远程推送（便于后续接入 APNs / device token）。
    func requestSystemAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            await refreshAuthorizationStatus()
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
            }
            return granted
        } catch {
            await refreshAuthorizationStatus()
            return false
        }
    }

    func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
