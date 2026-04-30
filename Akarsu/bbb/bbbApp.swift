//
//  bbbApp.swift
//  bbb
//
//  Created by MAC on 2026/03/31.
//

import AVFoundation
import SwiftUI

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
            /// 外放成片：`defaultToSpeaker` 避免部分机型在路由切换后仍走听筒；`mixWithOthers` 与其它 App 音频共存。
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [.defaultToSpeaker, .mixWithOthers])
            try session.setActive(true)
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
