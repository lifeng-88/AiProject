//
//  AuthReloginHelper.swift
//  bbb
//
//  与 glam `Utils/AuthReloginHelper` 对齐：设备登录前走 AF 归因；refresh 失效后与首启无 token 同路径；push_id 异步上报不阻塞主链路。
//

import Foundation

enum AuthReloginHelper {
    /// 使用已准备好的 AF 归因结果调用 `/v1/login`（与 glam `AuthenticationManager.performAutoLogin` 请求体一致）。
    static func login(with attribution: AFAttributionResult?) async -> Result<AuthInfo, AppError> {
        let deviceId = await DeviceManager.shared.getDeviceId()
        let version = await DeviceManager.shared.getAppVersion()
        let channel = await AppConfig.shared.getChannel()
        let result = await AuthRepository.shared.login(
            devId: deviceId,
            source: attribution?.source,
            channel: channel,
            version: version,
            afId: attribution?.afId,
            adId: attribution?.adId,
            afAttributionJson: attribution?.attributionJson
        )
        if case .success = result {
            Task.detached(priority: .utility) {
                await UserLocaleReporter.reportIfAuthenticated(reason: "after_login")
            }
        }
        return result
    }

    /// 冷启动无 Keychain 会话：与 glam 一致，先 `prepareForFirstLaunch` 再登录；归因超时则 `afAttributionJson` 带 `{"timeout":true}`。
    static func loginAfterColdStartWithoutSession(channelId: String) async -> Result<AuthInfo, AppError> {
        let (_, rawAttribution) = await AFService.shared.prepareForFirstLaunch(channelId: channelId)
        let attribution: AFAttributionResult?
        if let raw = rawAttribution {
            attribution = raw
        } else {
            let timeoutJson = (try? JSONSerialization.data(withJSONObject: ["timeout": true])).flatMap { String(data: $0, encoding: .utf8) }
            attribution = AFAttributionResult(afId: nil, adId: nil, source: nil, attributionJson: timeoutJson)
        }
        print("🔐 [AuthReloginHelper] 即将设备登录 source=\(attribution?.source ?? "nil") afId=\(attribution?.afId ?? "nil") jsonLen=\(attribution?.attributionJson?.count ?? 0)")
        return await login(with: attribution)
    }

    /// Refresh 失败后：清会话前由调用方处理；此处重新归因 + 设备 login（与 glam 一致）。
    static func loginAfterRefreshFailure() async -> Result<AuthInfo, AppError> {
        let channel = await AppConfig.shared.getChannel()
        return await loginAfterColdStartWithoutSession(channelId: channel)
    }
}
