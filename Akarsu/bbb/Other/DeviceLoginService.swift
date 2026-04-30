//
//  DeviceLoginService.swift
//  bbb
//
//  轻量设备登录：POST /v1/login，与 Data/AuthAPI 约定一致；基址与 `APIClient` 相同，使用 `APIBaseURL.effective`。
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
    /// 请求体字段与 `AuthAPI.login` / glam 一致；优先走 `AuthRepository.login` + `AuthAPI`，本方法仅保留作独立 URLSession 调试路径。
    static func login(
        channel: String? = "ios",
        source: String? = "app",
        afId: String? = nil,
        adId: String? = nil,
        afAttributionJson: String? = nil
    ) async -> Result<DeviceLoginResponse, DeviceLoginError> {
        let (devId, version) = await MainActor.run {
            let d = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
            let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
            return (d, v)
        }

        guard let url = URL(string: APIBaseURL.effective + "/v1/login") else {
            return .failure(.invalidURL)
        }

        var body: [String: Any] = [
            "devId": devId,
            "version": version
        ]
        if let source { body["source"] = source }
        if let channel { body["channel"] = channel }
        if let afId, !afId.isEmpty { body["afId"] = afId }
        if let adId, !adId.isEmpty { body["adId"] = adId }
        if let afAttributionJson, !afAttributionJson.isEmpty { body["afAttributionJson"] = afAttributionJson }

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
