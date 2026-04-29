//
//  APIBaseURL.swift
//  glam
//
//  统一 API 基地址：HTTP 与 WebSocket 均使用此值。默认 http://127.0.0.1。
//

import Combine
import Foundation

enum APIBaseURL {
    private static let infoKey = "APIBaseURL"
    
    /// 当前生效的 API 基地址（与 APIClient 一致）
    /// 优先级：Info.plist(APIBaseURL) > 默认值
    static var effective: String {
        if let value = Bundle.main.object(forInfoDictionaryKey: infoKey) as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, !(trimmed.hasPrefix("$(") && trimmed.hasSuffix(")")) {
                return trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
            }
        }
//        return "https://api.musefit.it.com"//正式服10002
        return "https://api.goddess.xin"
//        return "https://api.glamai01.it.com"
    }

    /// 根据 HTTP(S) 基地址生成 WebSocket URL
    /// - Parameters:
    ///   - path: 如 "/ws"
    ///   - queryItems: 如 [("token", token)]
    static func webSocketURL(path: String = "/ws", queryItems: [(String, String)]) -> URL? {
        let base = effective
        guard let parsed = URL(string: base), let host = parsed.host else { return nil }
        let wsScheme = (parsed.scheme == "https") ? "wss" : "ws"
        var comp = URLComponents()
        comp.scheme = wsScheme
        comp.host = host
        comp.port = parsed.port
        comp.path = path
        comp.queryItems = queryItems.map { URLQueryItem(name: $0.0, value: $0.1) }
        return comp.url
    }
}
