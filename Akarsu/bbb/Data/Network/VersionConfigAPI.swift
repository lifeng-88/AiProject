//
//  VersionConfigAPI.swift
//  bbb
//
//  GET /v1/version_config?channel=&version=
//

import Foundation

struct VersionConfigResponse: Decodable {
    /// 1：充值页「Recharge Now」直接走内购；2：保持现有支付选择弹窗
    let type: Int?

    enum CodingKeys: String, CodingKey {
        case type
        /// 部分环境可能只返回 snake_case
        case rechargePresentationType = "recharge_presentation_type"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fromTypeKey = Self.decodeFlexibleInt(from: c, forKey: .type)
        let fromSnake = Self.decodeFlexibleInt(from: c, forKey: .rechargePresentationType)
        type = fromTypeKey ?? fromSnake
    }

    private static func decodeFlexibleInt(from c: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Int? {
        if let v = try? c.decode(Int.self, forKey: key) { return v }
        if let s = try? c.decode(String.self, forKey: key), let v = Int(s) { return v }
        if let i32 = try? c.decode(Int32.self, forKey: key) { return Int(i32) }
        return nil
    }
}

enum VersionConfigAPI {
    static func fetchVersionConfig(channel: String, version: String) async -> Result<VersionConfigResponse, AppError> {
        await APIClient.shared.request(
            "/v1/version_config",
            method: .get,
            parameters: [
                "channel": channel,
                "version": version
            ],
            requiresAuth: false
        )
    }
}
