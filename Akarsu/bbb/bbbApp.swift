//
//  bbbApp.swift
//  bbb
//
//  Created by MAC on 2026/03/31.
//

import AVFoundation
import SwiftUI
import UIKit

/// iPad 需在 Info.plist 声明四种方向以满足多任务审核；界面仍只使用竖屏由 `supportedInterfaceOrientationsFor` 锁定。
final class BBBApplicationDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        .portrait
    }
}

@main
struct bbbApp: App {
    @UIApplicationDelegateAdaptor(BBBApplicationDelegate.self) private var applicationDelegate

    @StateObject private var wallet = UserWalletStore()
    @StateObject private var tabRouter = AppTabRouter()
    @StateObject private var auth = AuthSessionStore()
    @StateObject private var versionConfig = VersionConfigStore()
    @StateObject private var appLanguage = AppLanguageStore()

    init() {
        BBBNavigationChrome.applyGlobalTint()
        /// 首页瀑布流 / 沉浸式静音视频：不配置时部分机型上 `AVPlayer` 可能无法自动起播或与其它音频抢占异常。
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {}
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(wallet)
                .environmentObject(tabRouter)
                .environmentObject(auth)
                .environmentObject(versionConfig)
                .environmentObject(appLanguage)
                .environment(\.locale, appLanguage.effectiveLocale)
        }
    }
}
