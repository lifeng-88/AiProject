//
//  StatisticsAPI.swift
//  glam
//
//  行为事件批量上报。协议文档：协议文档/统计与埋点协议.md
//  若出现 404：请确认 glam-svr 的 statistics 服务已在 8110 启动，且 nginx 将 /v1/statistics 转发到该服务；
//  若 baseURL 直连某端口，则需该端口提供 /v1/statistics/events/batch 或经网关转发。
//

import Foundation

/// 单条行为事件（用于批量上报）
/// 模板类事件 templateId 必填；支付类事件 templateId 可为空，扩展字段放 extra
struct BehaviorEventItem {
    let eventType: String
    let templateId: String
    let taskId: String?
    let ts: Int64
    /// 支付类事件扩展字段（package_id、order_id、payment_method、amount、success、reason、source 等）
    let extra: [String: Any]?

    func toParameters() -> [String: Any] {
        var dict: [String: Any] = [
            "event_type": eventType,
            "template_id": templateId,
            "ts": ts
        ]
        if let t = taskId, !t.isEmpty {
            dict["task_id"] = t
        }
        if let e = extra, !e.isEmpty {
            // 将 extra 字典序列化为 JSON 字符串（服务端 Proto 定义 extra 为 string）
            if let jsonData = try? JSONSerialization.data(withJSONObject: e, options: []),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                dict["extra"] = jsonString
            }
        }
        return dict
    }
}

/// 批量上报响应
struct BatchEventsResponse: Decodable {
    let accepted: Int32
    let rejected: Int32
}

/// 统计与埋点 API
enum StatisticsAPI {
    private static let client = APIClient.shared

    /// 批量上报行为事件 POST /v1/statistics/events/batch
    /// - Parameters:
    ///   - channelId: 渠道 ID，必填
    ///   - userId: 用户 ID，已登录时建议传
    ///   - deviceId: 设备 ID，与 userId 至少其一非空
    ///   - events: 事件列表，单次最多 100 条
    ///   - appVersion: 客户端版本，可选
    ///   - platform: 固定 "iOS"
    static func reportBatch(
        channelId: String,
        userId: Int64?,
        deviceId: String?,
        events: [BehaviorEventItem],
        appVersion: String? = nil,
        platform: String = "iOS"
    ) async -> Result<BatchEventsResponse, AppError> {
        guard !events.isEmpty else {
            return .failure(.serverError(code: 400, message: "events should not be empty"))
        }
        guard events.count <= 100 else {
            return .failure(.serverError(code: 400, message: "events count exceeds 100"))
        }
        guard !channelId.isEmpty else {
            return .failure(.serverError(code: 400, message: "channel_id is required"))
        }
        guard userId != nil || (deviceId != nil && !(deviceId?.isEmpty ?? true)) else {
            return .failure(.serverError(code: 400, message: "user_id or device_id is required"))
        }

        var params: [String: Any] = [
            "channel_id": channelId,
            "events": events.map { $0.toParameters() }
        ]
        if let u = userId {
            params["user_id"] = u
        }
        if let d = deviceId, !d.isEmpty {
            params["device_id"] = d
        }
        if let v = appVersion, !v.isEmpty {
            params["app_version"] = v
        }
        params["platform"] = platform

        return await client.request(
            "/v1/statistics/events/batch",
            method: .post,
            parameters: params,
            retryOnUnauthorized: true
        )
    }
}
