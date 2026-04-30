//
//  AuthAPI.swift
//  glam
//
//  Created by Dev on 2026/1/18.
//

import Combine
import Foundation

/// 认证相关 API
struct AuthAPI {
    static let client = APIClient.shared
    
    /// 登录接口响应包装
    struct LoginResponseWrapper: Decodable {
        let userid: String
        let accessToken: String
        let refreshToken: String
    }
    
    /// 刷新 Token 接口响应包装
    struct RefreshResponseWrapper: Decodable {
        let accessToken: String
        let refreshToken: String
    }
    
    /// 登录（push_id 不在登录时上报，登录成功后通过 updatePushId 上报）
    /// T-AF-6: 请求体增加 afId、adId、afAttributionJson（与 login.proto 对齐）
    static func login(request: LoginRequest) async -> Result<LoginResponse, AppError> {
        var requestParams: [String: Any] = [
            "devId": request.devId,
            "version": request.version
        ]
        if let source = request.source { requestParams["source"] = source }
        if let channel = request.channel { requestParams["channel"] = channel }
        if let afId = request.afId, !afId.isEmpty { requestParams["afId"] = afId }
        if let adId = request.adId, !adId.isEmpty { requestParams["adId"] = adId }
        if let afAttributionJson = request.afAttributionJson, !afAttributionJson.isEmpty { requestParams["afAttributionJson"] = afAttributionJson }
        
        print("🔐 [AuthAPI] ========== 登录接口调用 ==========")
        print("🔐 [AuthAPI] 开始调用登录接口")
        print("   📤 devId: \(request.devId), version: \(request.version), channel: \(request.channel ?? "nil"), source: \(request.source ?? "nil"), afId: \(request.afId ?? "nil")")
        
        /// 公开接口：与 glam 一致 — `requiresAuth: false`（不带 Bearer）；`retryOnUnauthorized: false`（与 `/v1/refresh` 同策略，避免无意义刷新链）。
        let result: Result<LoginResponseWrapper, AppError> = await client.request(
            "/v1/login",
            method: .post,
            parameters: requestParams,
            retryOnUnauthorized: false,
            requiresAuth: false
        )
        
        // 输出服务器返回的结果
        switch result {
        case .success(let wrapper):
            print("✅ [AuthAPI] 登录接口调用成功")
            print("✅ [AuthAPI] 输出结果:")
            print("   📥 userid: \(wrapper.userid)")
            print("   📥 accessToken: \(wrapper.accessToken.prefix(50))... (长度: \(wrapper.accessToken.count))")
            print("   📥 refreshToken: \(wrapper.refreshToken.prefix(50))... (长度: \(wrapper.refreshToken.count))")
        case .failure(let error):
            print("❌ [AuthAPI] 登录接口调用失败")
            print("❌ [AuthAPI] 输出结果 (错误):")
            print("   📥 错误类型: \(error)")
            print("   📥 错误描述: \(error.localizedDescription)")
            if case .serverError(let code, let message) = error {
                print("   📥 HTTP状态码: \(code)")
                print("   📥 错误消息: \(message)")
            }
            if case .networkError(let description) = error {
                print("   📥 网络错误: \(description)")
            }
            if case .decodingError(let description) = error {
                print("   📥 解码错误: \(description)")
            }
        }
        print("🔐 [AuthAPI] =====================================")
        
        return result.map { wrapper in
            LoginResponse(
                userid: wrapper.userid,
                accessToken: wrapper.accessToken,
                refreshToken: wrapper.refreshToken
            )
        }
    }
    
    /// 刷新 Token（禁用自动重试，避免死循环）
    static func refreshToken(refreshToken: String) async -> Result<RefreshResponseWrapper, AppError> {
        let parameters: [String: Any] = [
            "refreshToken": refreshToken
        ]
        
        print("🔄 [AuthAPI] 开始调用刷新Token接口")
        print("   📤 请求参数:")
        print("      - refreshToken: \(refreshToken.prefix(50))... (长度: \(refreshToken.count))")
        
        // 禁用自动重试；勿带 access Bearer（仅用 body 内 refreshToken），否则 access 为空时无法刷新且会触发 APIClient 鉴权守卫
        let result: Result<RefreshResponseWrapper, AppError> = await client.request(
            "/v1/refresh",
            method: .post,
            parameters: parameters,
            retryOnUnauthorized: false,
            requiresAuth: false
        )
        
        // 输出服务器返回的结果
        switch result {
        case .success(let wrapper):
            print("✅ [AuthAPI] 刷新Token接口调用成功")
            print("   📥 服务器返回结果:")
            print("      - accessToken: \(wrapper.accessToken.prefix(50))... (长度: \(wrapper.accessToken.count))")
            print("      - refreshToken: \(wrapper.refreshToken.prefix(50))... (长度: \(wrapper.refreshToken.count))")
        case .failure(let error):
            print("❌ [AuthAPI] 刷新Token接口调用失败")
            print("   📥 错误信息: \(error)")
            if case .serverError(let code, let message) = error {
                print("   📥 错误码: \(code), 错误消息: \(message)")
            }
            if case .networkError(let description) = error {
                print("   📥 网络错误: \(description)")
            }
        }
        
        return result
    }
    
    /// 推送 ID 上报（登录成功后调用，协议：POST /v1/push_id，需 Bearer Token）
    static func updatePushId(pushId: String) async -> Result<Bool, AppError> {
        guard !pushId.isEmpty else {
            return .failure(.serverError(code: 400, message: "push_id should not be empty"))
        }
        struct UpdatePushIdReply: Decodable {
            let ok: Bool
        }
        let result: Result<UpdatePushIdReply, AppError> = await client.request(
            "/v1/push_id",
            method: .post,
            parameters: ["push_id": pushId],
            retryOnUnauthorized: true
        )
        switch result {
        case .success(let reply):
            print("✅ [AuthAPI] [push_id] 上报成功 ok=\(reply.ok) \(pushId)")
            return .success(reply.ok)
        case .failure(let error):
            print("❌ [AuthAPI] [push_id] 上报失败 \(pushId): \(error.localizedDescription)")
            return .failure(error)
        }
    }

    /// 登出
    static func logout() async -> Result<Bool, AppError> {
        struct LogoutResponse: Decodable {
            let ok: Bool
        }
        
        let result: Result<LogoutResponse, AppError> = await client.request(
            "/v1/logout",
            method: .post,
            parameters: [:]
        )
        
        return result.map { $0.ok }
    }
}
