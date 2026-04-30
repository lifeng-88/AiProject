//
//  ContentView.swift
//  bbb
//
//  Created by MAC on 2026/03/31.
//

import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var versionConfig: VersionConfigStore
    @EnvironmentObject private var wallet: UserWalletStore
    @EnvironmentObject private var tabRouter: AppTabRouter
    @EnvironmentObject private var appLanguage: AppLanguageStore
    @Environment(\.scenePhase) private var scenePhase

    /// 首次登录成功后仅展示一次（含冷启动已恢复会话且尚未展示过的情况）
    @AppStorage("bbb.welcomeBonusShown") private var welcomeBonusShown = false
    @State private var showWelcomeBonus = false

    var body: some View {
        MainTabView()
            .preferredColorScheme(.dark)
            .onReceive(NotificationCenter.default.publisher(for: .bbbAuthSessionDidUpdate)) { note in
                if let info = note.object as? AuthInfo {
                    auth.applySessionFromAuthInfo(info)
                }
            }
            .onAppear {
                BalanceManager.shared.bindWallet(wallet)
                // 与 `PushManager` 冷启动注册一致：不依赖「已登录」或横幅权限，尽早向 APNs 要 device token。
                UIApplication.shared.registerForRemoteNotifications()
            }
            .onReceive(NotificationCenter.default.publisher(for: .bbbRemotePushRoute)) { note in
                guard let route = note.object as? RemotePushRoute else { return }
                Task { @MainActor in
                    guard auth.isAuthenticated else { return }
                    tabRouter.dispatchRemotePush(route)
                }
            }
            .onChange(of: auth.isAuthenticated) { isAuthed in
                if isAuthed {
                    UIApplication.shared.registerForRemoteNotifications()
                    evaluateWelcomeBonus()
                }
            }
            .overlay {
                if showWelcomeBonus {
                    WelcomeBonusOverlay(freeCoins: 2) {
                        welcomeBonusShown = true
                        showWelcomeBonus = false
                        tabRouter.select(.home)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(999)
                }
            }
            .animation(.spring(response: 0.38, dampingFraction: 0.86), value: showWelcomeBonus)
            .task {
                Task { await MediaCacheMaintenance.cleanExpiredCachesIfNeeded() }
                await versionConfig.refresh()
                await auth.performLaunchAuthentication()
                // 会话恢复后再登记一次，避免 onAppear 早于 `isAuthenticated` 为 true 时漏调。
                await MainActor.run {
                    UIApplication.shared.registerForRemoteNotifications()
                }
                await PushRechargeOrderAttributionStore.shared.loadPersistedIfNeeded()
                IAPManager.shared.startListening()
                evaluateWelcomeBonus()
            }
            .bbbRefreshOnAppLanguage()
            .onChange(of: appLanguage.preference) { _ in
                guard auth.isAuthenticated else { return }
                Task.detached(priority: .utility) {
                    await UserLocaleReporter.reportIfAuthenticated(reason: "language_changed")
                }
            }
            .onChange(of: scenePhase) { phase in
                if phase == .active {
                    appLanguage.refreshUITextForPossibleSystemLocaleChange()
                } else if phase == .background {
                    Task { await BehaviorEventQueue.shared.flush() }
                }
            }
    }

    private func evaluateWelcomeBonus() {
        guard auth.isAuthenticated, !welcomeBonusShown else { return }
        showWelcomeBonus = true
    }
}

#Preview {
    ContentView()
        .environmentObject(UserWalletStore())
        .environmentObject(AppTabRouter())
        .environmentObject(AuthSessionStore())
        .environmentObject(VersionConfigStore())
        .environmentObject(AppLanguageStore())
        .environment(\.locale, Locale.current)
}
