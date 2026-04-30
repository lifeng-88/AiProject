//
//  BBBPushNotificationCenterDelegate.swift
//  bbb
//
//  与 glam `PushNotificationCenterDelegate` 一致：UN 前台展示、点击通知 Deep Link（路由投递在 MainActor）。
//

import Foundation
import UIKit
import UserNotifications

final class BBBPushNotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = BBBPushNotificationCenterDelegate()

    private override init() {
        super.init()
    }

    /// 前台收到通知时仍展示横幅 / 列表（与默认静默相对）。
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        let diag = RemotePushRoute.diagnosticSummary(userInfo: userInfo)
        let ok = RemotePushRoute.recognizesBusinessPayload(userInfo: userInfo)
        print("📲 [PushNotificationCenter] willPresent 前台已收到远程通知 \(diag) businessPayloadOK=\(ok)")
        if #available(iOS 14.0, *) {
            completionHandler([.banner, .list, .sound, .badge])
        } else {
            completionHandler([.alert, .sound, .badge])
        }
    }

    /// 用户点击通知（含从通知冷启动进入）。
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let diag = RemotePushRoute.diagnosticSummary(userInfo: userInfo)
        let ok = RemotePushRoute.recognizesBusinessPayload(userInfo: userInfo)
        print("📲 [PushNotificationCenter] didReceive 用户点击通知 \(diag) businessPayloadOK=\(ok)")
        Task { @MainActor in
            BBBApplicationDelegate.postRemotePushRouteIfParsed(from: userInfo)
        }
        completionHandler()
    }
}
