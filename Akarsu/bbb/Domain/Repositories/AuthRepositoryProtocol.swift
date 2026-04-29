//
//  AuthRepositoryProtocol.swift
//  glam
//
//  Created by Dev on 2026/1/18.
//

import Foundation

/// 认证 Repository 协议
protocol AuthRepositoryProtocol {
    /// 登录（push_id 不在登录时传，登录成功后通过推送 ID 上报接口上报）
    /// T-AF-6: 可选传入 afId、adId、afAttributionJson
    func login(devId: String, source: String?, channel: String?, version: String, afId: String?, adId: String?, afAttributionJson: String?) async -> Result<AuthInfo, AppError>

    /// 冷启动：若 Keychain 已有会话则 `getCurrentAuthInfo` 并注入 `APIClient`；否则用设备信息调用 `login`。
    /// Token 过期后的刷新由 `APIClient` 收到 401 时经 `TokenManager` → `refreshToken` 完成；刷新失败时再走本方法同路径的设备登录。
    func ensureAuthenticatedOnLaunch() async -> Result<AuthInfo, AppError>

    /// 刷新 Token 失败后：与冷启动「无会话」一致，用设备信息重新请求 `/v1/login`。
    func loginWithDeviceCredentials() async -> Result<AuthInfo, AppError>
    
    /// 刷新 Token
    func refreshToken(refreshToken: String) async -> Result<AuthInfo, AppError>
    
    /// 登出
    func logout() async -> Result<Bool, AppError>
    
    /// 获取当前认证信息
    func getCurrentAuthInfo() async -> AuthInfo?
    
    /// 保存认证信息
    func saveAuthInfo(_ authInfo: AuthInfo) async throws
    
    /// 清除认证信息
    func clearAuthInfo() async
}
