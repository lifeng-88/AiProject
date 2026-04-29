//
//  AuthRepository.swift
//  glam
//
//  Created by Dev on 2026/1/18.
//

import Foundation

/// 认证 Repository 实现
actor AuthRepository: AuthRepositoryProtocol {
    static let shared = AuthRepository()
    
    private let keychain = KeychainManager.shared
    private var currentAuthInfo: AuthInfo?
    
    private init() {}
    
    // MARK: - AuthRepositoryProtocol
    
    func login(devId: String, source: String?, channel: String?, version: String, afId: String? = nil, adId: String? = nil, afAttributionJson: String? = nil) async -> Result<AuthInfo, AppError> {
        let request = LoginRequest(
            devId: devId,
            source: source,
            channel: channel,
            version: version,
            afId: afId,
            adId: adId,
            afAttributionJson: afAttributionJson
        )
        
        let result = await AuthAPI.login(request: request)
        
        switch result {
        case .success(let response):
            print("🔐 [AuthRepository] 登录成功，处理响应数据")
            print("   📋 响应数据:")
            print("      - userid: \(response.userid)")
            print("      - accessToken: \(response.accessToken.prefix(20))...")
            print("      - refreshToken: \(response.refreshToken.prefix(20))...")
            
            let authInfo = AuthInfo(from: response)
            
            // 保存 Token 到 Keychain
            do {
                try await saveAuthInfo(authInfo)
                await AFService.shared.markLoginCompleted()
                // 更新 APIClient 的 Token
                await APIClient.shared.setAccessToken(authInfo.accessToken)
                print("✅ [AuthRepository] Token 已保存到 Keychain 并更新到 APIClient")
                await MainActor.run {
                    NotificationCenter.default.post(name: .bbbAuthSessionDidUpdate, object: authInfo)
                }
                return .success(authInfo)
            } catch {
                print("❌ [AuthRepository] 保存 Token 失败: \(error)")
                return .failure(error as? AppError ?? .storageError("Failed to save auth info"))
            }
            
        case .failure(let error):
            print("❌ [AuthRepository] 登录失败: \(error)")
            return .failure(error)
        }
    }

    func ensureAuthenticatedOnLaunch() async -> Result<AuthInfo, AppError> {
        if let info = await getCurrentAuthInfo() {
            print("🔐 [AuthRepository] ensureAuthenticatedOnLaunch: 已存在本地会话，已同步 APIClient")
            return .success(info)
        }
        let devId = await DeviceManager.shared.deviceIdForLogin()
        let version = await DeviceManager.shared.getAppVersion()
        let channel = await AppConfig.shared.getChannel()
        print("🔐 [AuthRepository] ensureAuthenticatedOnLaunch: 无本地会话，发起设备登录 channel=\(channel)")
        return await login(
            devId: devId,
            source: "app",
            channel: channel,
            version: version,
            afId: nil,
            adId: nil,
            afAttributionJson: nil
        )
    }

    func loginWithDeviceCredentials() async -> Result<AuthInfo, AppError> {
        let devId = await DeviceManager.shared.deviceIdForLogin()
        let version = await DeviceManager.shared.getAppVersion()
        let channel = await AppConfig.shared.getChannel()
        print("🔐 [AuthRepository] loginWithDeviceCredentials: refresh 失败后的设备重登 channel=\(channel)")
        return await login(
            devId: devId,
            source: "app",
            channel: channel,
            version: version,
            afId: nil,
            adId: nil,
            afAttributionJson: nil
        )
    }

    func refreshToken(refreshToken: String) async -> Result<AuthInfo, AppError> {
        print("🔄 [AuthRepository] 开始刷新Token")
        print("   📤 输入参数:")
        print("      - refreshToken: \(refreshToken.prefix(50))... (长度: \(refreshToken.count))")
        
        let result = await AuthAPI.refreshToken(refreshToken: refreshToken)
        
        switch result {
        case .success(let response):
            print("✅ [AuthRepository] 刷新Token成功，处理响应数据")
            print("   📋 服务器返回数据:")
            print("      - accessToken: \(response.accessToken.prefix(50))... (长度: \(response.accessToken.count))")
            print("      - refreshToken: \(response.refreshToken.prefix(50))... (长度: \(response.refreshToken.count))")
            
            // 需要获取当前 userid，如果没有则从存储中读取
            var currentAuth = currentAuthInfo
            if currentAuth == nil {
                currentAuth = await getCurrentAuthInfo()
            }
            guard let currentAuth = currentAuth else {
                print("❌ [AuthRepository] 无法获取当前userid")
                return .failure(.unauthorized)
            }
            
            let authInfo = AuthInfo(
                userid: currentAuth.userid,
                accessToken: response.accessToken,
                refreshToken: response.refreshToken
            )
            
            print("   📋 构建的AuthInfo:")
            print("      - userid: \(authInfo.userid)")
            print("      - accessToken: \(authInfo.accessToken.prefix(50))... (长度: \(authInfo.accessToken.count))")
            print("      - refreshToken: \(authInfo.refreshToken.prefix(50))... (长度: \(authInfo.refreshToken.count))")
            
            // 保存新的 Token 到 Keychain
            do {
                try await saveAuthInfo(authInfo)
                await APIClient.shared.setAccessToken(authInfo.accessToken)
                print("✅ [AuthRepository] Token已保存到Keychain并更新到APIClient")
                await MainActor.run {
                    NotificationCenter.default.post(name: .bbbAuthSessionDidUpdate, object: authInfo)
                }
                // 协议：token 刷新后上报 push_id
                if let pushId = PushManager.shared.currentPushId(), !pushId.isEmpty {
                    _ = await AuthAPI.updatePushId(pushId: pushId)
                }
                print("   📥 输出结果: 成功")
                return .success(authInfo)
            } catch {
                print("❌ [AuthRepository] 保存Token失败: \(error)")
                print("   📥 输出结果: 失败 - \(error)")
                return .failure(error as? AppError ?? .storageError("Failed to save auth info"))
            }
            
        case .failure(let error):
            print("❌ [AuthRepository] 刷新Token失败")
            print("   📥 输出结果: 失败 - \(error)")
            if case .serverError(let code, let message) = error {
                print("   📥 错误码: \(code), 错误消息: \(message)")
            }
            return .failure(error)
        }
    }
    
    func logout() async -> Result<Bool, AppError> {
        let result = await AuthAPI.logout()
        
        // 无论接口是否成功，都清除本地认证信息
        await clearAuthInfo()
        
        return result
    }
    
    func getCurrentAuthInfo() async -> AuthInfo? {
        // 如果内存中有，直接返回（并保证 APIClient 与内存一致，冷启动后 APIClient 可能未注入）
        if let authInfo = currentAuthInfo {
            await APIClient.shared.setAccessToken(authInfo.accessToken)
            return authInfo
        }

        // 从 Keychain 读取
        guard let accessToken = await keychain.load(key: "accessToken"),
              let refreshToken = await keychain.load(key: "refreshToken"),
              let userid = await keychain.load(key: "userid") else {
            return nil
        }

        let authInfo = AuthInfo(userid: userid, accessToken: accessToken, refreshToken: refreshToken)
        currentAuthInfo = authInfo
        await APIClient.shared.setAccessToken(accessToken)
        return authInfo
    }
    
    func saveAuthInfo(_ authInfo: AuthInfo) async throws {
        // 保存到 Keychain
        try await keychain.save(key: "accessToken", value: authInfo.accessToken)
        try await keychain.save(key: "refreshToken", value: authInfo.refreshToken)
        try await keychain.save(key: "userid", value: authInfo.userid)

        // 更新内存中的认证信息
        currentAuthInfo = authInfo
        await APIClient.shared.setAccessToken(authInfo.accessToken)
    }
    
    func clearAuthInfo() async {
        // 清除 Keychain
        await keychain.delete(key: "accessToken")
        await keychain.delete(key: "refreshToken")
        await keychain.delete(key: "userid")
        
        // 清除内存
        currentAuthInfo = nil
        
        // 清除 APIClient 的 Token
        await APIClient.shared.setAccessToken(nil)
        
        // 清除 TokenManager 的刷新状态
        await TokenManager.shared.clearRefreshState()
    }
}
