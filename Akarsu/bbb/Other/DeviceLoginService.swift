//
//  DeviceLoginService.swift
//  bbb
//
//  轻量设备登录：POST /v1/login，与 Data/AuthAPI 约定一致，不依赖 APIClient 目标成员。
//

import Foundation
import UIKit

enum DeviceLoginError: LocalizedError {
    case invalidURL
    case badStatus(Int, String)
    case decoding(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid API address"
        case .badStatus(let code, let msg): return msg.isEmpty ? "Server error (\(code))" : msg
        case .decoding(let msg): return msg
        case .network(let msg): return msg
        }
    }
}

/// 与 `APIBaseURL.effective` 一致：Info.plist `APIBaseURL` > 默认
enum LoginAPIConfig {
    private static let infoKey = "APIBaseURL"

    static var baseURL: String {
        if let value = Bundle.main.object(forInfoDictionaryKey: infoKey) as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, !(trimmed.hasPrefix("$(") && trimmed.hasSuffix(")")) {
                return trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
            }
        }
        return "https://api.musefit.it.com"
    }
}

struct DeviceLoginResponse: Decodable {
    let userid: String
    let accessToken: String
    let refreshToken: String
}

private struct ErrorPayload: Decodable {
    let message: String
}

enum DeviceLoginService {
    /// 设备登录（devId 使用 identifierForVendor，缺失时 fallback UUID）
    static func login(
        channel: String? = "ios",
        source: String? = "app"
    ) async -> Result<DeviceLoginResponse, DeviceLoginError> {
        let (devId, version) = await MainActor.run {
            let d = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
            let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
            return (d, v)
        }

        guard let url = URL(string: LoginAPIConfig.baseURL + "/v1/login") else {
            return .failure(.invalidURL)
        }

        var body: [String: Any] = [
            "devId": devId,
            "version": version
        ]
        if let channel { body["channel"] = channel }
        if let source { body["source"] = source }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        } catch {
            return .failure(.network(error.localizedDescription))
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(.network("Invalid response"))
            }
            guard (200 ... 299).contains(http.statusCode) else {
                let msg: String
                if let err = try? JSONDecoder().decode(ErrorPayload.self, from: data) {
                    msg = err.message
                } else if let s = String(data: data, encoding: .utf8), !s.isEmpty {
                    msg = s
                } else {
                    msg = ""
                }
                return .failure(.badStatus(http.statusCode, msg))
            }
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            do {
                let decoded = try decoder.decode(DeviceLoginResponse.self, from: data)
                return .success(decoded)
            } catch {
                return .failure(.decoding(error.localizedDescription))
            }
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }
}
