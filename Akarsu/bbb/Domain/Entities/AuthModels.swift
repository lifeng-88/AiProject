//
//  AuthModels.swift
//  glam
//
//  Created by Dev on 2026/1/18.
//

import Foundation

/// 登录请求模型（push_id 不在登录时上报，登录成功后通过 POST /v1/push_id 上报）
/// T-AF-6: 增加 afId、adId、afAttributionJson，与 login.proto 对齐
struct LoginRequest: Codable {
    let devId: String
    let source: String?
    let channel: String?
    let version: String
    let afId: String?
    let adId: String?
    let afAttributionJson: String?

    init(devId: String, source: String?, channel: String?, version: String, afId: String? = nil, adId: String? = nil, afAttributionJson: String? = nil) {
        self.devId = devId
        self.source = source
        self.channel = channel
        self.version = version
        self.afId = afId
        self.adId = adId
        self.afAttributionJson = afAttributionJson
    }

    enum CodingKeys: String, CodingKey {
        case devId
        case source
        case channel
        case version
        case afId
        case adId
        case afAttributionJson
    }
}

/// 登录响应模型
struct LoginResponse: Codable {
    let userid: String
    let accessToken: String
    let refreshToken: String
    
    enum CodingKeys: String, CodingKey {
        case userid
        case accessToken
        case refreshToken
    }
}

/// 认证信息模型
struct AuthInfo {
    let userid: String
    let accessToken: String
    let refreshToken: String
    
    init(userid: String, accessToken: String, refreshToken: String) {
        self.userid = userid
        self.accessToken = accessToken
        self.refreshToken = refreshToken
    }
    
    init(from response: LoginResponse) {
        self.userid = response.userid
        self.accessToken = response.accessToken
        self.refreshToken = response.refreshToken
    }
}
