//
//  AuthSessionStore.swift
//  bbb
//
//  登录态：冷启动通过 `AuthRepositoryProtocol.ensureAuthenticatedOnLaunch` 恢复或设备登录；
//  Token 刷新由 APIClient 401 → TokenManager → `refreshToken` 完成。
//

import SwiftUI

@MainActor
final class AuthSessionStore: ObservableObject {
    @Published private(set) var isAuthenticated: Bool
    @Published private(set) var userId: String?
    @Published var isLoading = false
    @Published var lastError: String?

    /// 冷启动会话是否已解析（成功或失败都会置为 true）
    @Published private(set) var launchSessionResolved = false
    /// 正在执行 `ensureAuthenticatedOnLaunch`（可选用于遮罩）
    @Published private(set) var isResolvingLaunchAuth = false

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let loggedIn = "bbb.auth.loggedIn"
        static let userId = "bbb.auth.userId"
        static let accessToken = "bbb.auth.accessToken"
        static let refreshToken = "bbb.auth.refreshToken"
    }

    init() {
        isAuthenticated = defaults.bool(forKey: Keys.loggedIn)
        userId = defaults.string(forKey: Keys.userId)
    }

    var accessToken: String? { defaults.string(forKey: Keys.accessToken) }

    var displayUserId: String {
        userId ?? "—"
    }

    /// 应用启动时调用：迁移旧 UserDefaults → Keychain，再经协议恢复会话或设备登录。
    func performLaunchAuthentication(repository: AuthRepositoryProtocol = AuthRepository.shared) async {
        isResolvingLaunchAuth = true
        lastError = nil
        defer {
            isResolvingLaunchAuth = false
            launchSessionResolved = true
        }

        await migrateUserDefaultsToKeychainIfNeeded(repository: repository)

        let result = await repository.ensureAuthenticatedOnLaunch()
        switch result {
        case .success(let info):
            isAuthenticated = true
            userId = info.userid
            defaults.set(true, forKey: Keys.loggedIn)
            defaults.set(info.userid, forKey: Keys.userId)
            defaults.set(info.accessToken, forKey: Keys.accessToken)
            defaults.set(info.refreshToken, forKey: Keys.refreshToken)
        case .failure(let error):
            lastError = error.userMessage
            if await repository.getCurrentAuthInfo() == nil {
                isAuthenticated = false
                userId = nil
                defaults.set(false, forKey: Keys.loggedIn)
                defaults.removeObject(forKey: Keys.userId)
                defaults.removeObject(forKey: Keys.accessToken)
                defaults.removeObject(forKey: Keys.refreshToken)
            }
        }
    }

    private func migrateUserDefaultsToKeychainIfNeeded(repository: AuthRepositoryProtocol) async {
        if await repository.getCurrentAuthInfo() != nil { return }
        guard let access = defaults.string(forKey: Keys.accessToken),
              let refresh = defaults.string(forKey: Keys.refreshToken),
              let uid = defaults.string(forKey: Keys.userId),
              !access.isEmpty, !refresh.isEmpty else { return }
        let info = AuthInfo(userid: uid, accessToken: access, refreshToken: refresh)
        do {
            try await repository.saveAuthInfo(info)
        } catch {
            print("⚠️ [AuthSessionStore] 迁移 token 到 Keychain 失败: \(error)")
        }
    }

    func loginWithDevice(repository: AuthRepositoryProtocol = AuthRepository.shared) async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        let result = await AuthReloginHelper.login(with: await AFService.shared.getAttributionForLogin())

        switch result {
        case .success(let info):
            defaults.set(true, forKey: Keys.loggedIn)
            defaults.set(info.userid, forKey: Keys.userId)
            defaults.set(info.accessToken, forKey: Keys.accessToken)
            defaults.set(info.refreshToken, forKey: Keys.refreshToken)
            userId = info.userid
            isAuthenticated = true
        case .failure(let err):
            lastError = err.userMessage
        }
    }

    func logout() {
        defaults.removeObject(forKey: Keys.loggedIn)
        defaults.removeObject(forKey: Keys.userId)
        defaults.removeObject(forKey: Keys.accessToken)
        defaults.removeObject(forKey: Keys.refreshToken)
        userId = nil
        isAuthenticated = false
        lastError = nil
        Task {
            await AuthRepository.shared.clearAuthInfo()
        }
    }

    /// 与 `loginWithDevice` 成功分支一致：刷新或静默重登后同步 Keychain/UserDefaults 到 UI 层
    func applySessionFromAuthInfo(_ info: AuthInfo) {
        defaults.set(true, forKey: Keys.loggedIn)
        defaults.set(info.userid, forKey: Keys.userId)
        defaults.set(info.accessToken, forKey: Keys.accessToken)
        defaults.set(info.refreshToken, forKey: Keys.refreshToken)
        userId = info.userid
        isAuthenticated = true
        lastError = nil
    }
}

extension Notification.Name {
    static let bbbAuthSessionDidUpdate = Notification.Name("bbb.auth.sessionDidUpdate")
}
