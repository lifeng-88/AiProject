//
//  BBBApplicationDelegate.swift
//  bbb
//
//  与 glam `PushAppDelegate` 对齐：APNs token、`UNUserNotificationCenter` 委托拆分、冷启动 launchOptions、DEBUG 环境变量模拟 payload。
//

import UIKit
import UserNotifications

/// iPad 需在 Info.plist 声明四种方向以满足多任务审核；界面仍只使用竖屏由 `supportedInterfaceOrientationsFor` 锁定。
final class BBBApplicationDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        .portrait
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UNUserNotificationCenter.current().delegate = BBBPushNotificationCenterDelegate.shared
        PushManager.shared.registerForRemoteNotificationsAtLaunch()

        if let userInfo = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            let diag = RemotePushRoute.diagnosticSummary(userInfo: userInfo)
            print("📲 [BBBApplicationDelegate] didFinishLaunching 存在 launchOptions.remoteNotification，将投递路由 \(diag)")
            DispatchQueue.main.async {
                Self.postRemotePushRouteIfParsed(from: userInfo)
            }
        } else {
            // 常规冷启动（点桌面图标等）不会有 `remoteNotification`；从通知进应用时一般由
            // `UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:)` 投递路由，仅少数系统版本会在 launchOptions 里带 payload。
            #if DEBUG
            print("📲 [BBBApplicationDelegate] didFinishLaunching：无 launchOptions.remoteNotification（正常）；推送点进应用走 UN 委托")
            applyDebugPushUserInfoFromEnvironmentIfNeeded()
            #endif
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushManager.shared.setAPNsDeviceToken(deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        let ns = error as NSError
        print("📲 [BBBApplicationDelegate] didFailToRegisterForRemoteNotifications: \(error.localizedDescription) (domain=\(ns.domain) code=\(ns.code))")
        print("📲 [BBBApplicationDelegate] 常见原因：未在 Xcode 开启 Push Notifications、Provisioning 不含 aps、模拟器未配置推送、或网络限制")
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        let diag = RemotePushRoute.diagnosticSummary(userInfo: userInfo)
        let ok = RemotePushRoute.recognizesBusinessPayload(userInfo: userInfo)
        print("📲 [BBBApplicationDelegate] didReceiveRemoteNotification \(diag) businessPayloadOK=\(ok)（系统送达回调：此处不跳转；点通知走 UN 委托）")
        // 勿在此处 `postRemotePushRouteIfParsed`：无用户点击时也会回调，会导致误跳转与重复 `push_open`。
        completionHandler(.noData)
    }

    /// 须在主线程调用：投递 `RemotePushRoute`（与 `ContentView` / `AppTabRouter` 约定一致）；与 glam 一致写入 `push_open` 埋点。
    static func postRemotePushRouteIfParsed(from userInfo: [AnyHashable: Any]) {
        guard let route = RemotePushRoute.parse(userInfo: userInfo) else {
            let diag = RemotePushRoute.diagnosticSummary(userInfo: userInfo)
            print("📲 [PushRoute] 无法解析业务路由（自定义字段须在根级或 `data` 内，且含合法 push_type）。\(diag)")
            return
        }
        print("📲 [PushRoute] 解析成功: \(route) → push_open + UI 投递")
        let extra = RemotePushRoute.pushOpenExtra(userInfo: userInfo, route: route)
        let taskId = RemotePushRoute.taskIdForPushOpen(route: route)
        Task {
            await BehaviorEventQueue.shared.enqueuePushOpen(taskId: taskId, extra: extra.isEmpty ? nil : extra)
        }
        NotificationCenter.default.post(name: .bbbRemotePushRoute, object: route)
    }

    #if DEBUG
    /// Scheme → Run → Arguments → Environment Variables: `BBB_DEBUG_PUSH_USERINFO` = 一行 JSON（与线上下发自定义段一致）。
    private func applyDebugPushUserInfoFromEnvironmentIfNeeded() {
        guard let raw = ProcessInfo.processInfo.environment["BBB_DEBUG_PUSH_USERINFO"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty
        else { return }
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            print("📲 [BBBApplicationDelegate] DEBUG BBB_DEBUG_PUSH_USERINFO JSON 解析失败 raw=\(String(raw.prefix(400)))")
            return
        }
        var userInfo: [AnyHashable: Any] = [:]
        for (k, v) in obj {
            userInfo[AnyHashable(k)] = v
        }
        let diag = RemotePushRoute.diagnosticSummary(userInfo: userInfo)
        print("📲 [BBBApplicationDelegate] DEBUG applyPushUserInfo from BBB_DEBUG_PUSH_USERINFO \(diag)")
        DispatchQueue.main.async {
            Self.postRemotePushRouteIfParsed(from: userInfo)
        }
    }
    #endif
}
