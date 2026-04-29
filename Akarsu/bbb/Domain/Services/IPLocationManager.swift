//
//  IPLocationManager.swift
//  glam
//
//  Created by Dev on 2026/1/26.
//

import Foundation
import Combine

/// IP定位管理器 - 在应用启动后异步获取IP定位信息并缓存
@MainActor
class IPLocationManager: ObservableObject {
    static let shared = IPLocationManager()
    
    @Published var locationData: IPLocationData?
    @Published var isLoading = false
    
    private let userDefaults = UserDefaultsManager.shared
    private let cacheKey = "ip_location_cache"
    private let cacheExpirationTime: TimeInterval = 24 * 60 * 60 // 24小时
    
    private init() {
        // 从缓存加载
        loadFromCache()
    }
    
    /// IP定位数据
    struct IPLocationData: Codable {
        let country: String?
        let administrativeArea: String?
        let locality: String?
        let postalCode: String?
        let cachedAt: Date
        
        init(country: String?, administrativeArea: String?, locality: String?, postalCode: String?) {
            self.country = country
            self.administrativeArea = administrativeArea
            self.locality = locality
            self.postalCode = postalCode
            self.cachedAt = Date()
        }
    }
    
    /// 从缓存加载
    private func loadFromCache() {
        Task {
            if let cachedData = await userDefaults.getData(forKey: cacheKey),
               let locationData = try? JSONDecoder().decode(IPLocationData.self, from: cachedData) {
                // 检查缓存是否过期
                let age = Date().timeIntervalSince(locationData.cachedAt)
                if age < cacheExpirationTime {
                    self.locationData = locationData
                    print("✅ [IPLocationManager] 从缓存加载IP定位信息")
                } else {
                    print("⚠️ [IPLocationManager] 缓存已过期，将重新获取")
                }
            }
        }
    }
    
    /// 保存到缓存
    private func saveToCache(_ data: IPLocationData) async {
        if let encoded = try? JSONEncoder().encode(data) {
            await userDefaults.set(encoded, forKey: cacheKey)
            print("✅ [IPLocationManager] IP定位信息已保存到缓存")
        }
    }
    
    /// 异步获取IP定位信息。服务端要求必须登录，仅登录后调用；未登录时直接返回。
    func fetchLocationInBackground() async {
        // 未登录不请求，避免 401
        let auth = await AuthRepository.shared.getCurrentAuthInfo()
        guard auth != nil else {
            print("ℹ️ [IPLocationManager] 未登录，跳过 IP 定位请求")
            return
        }
        
        // 如果缓存有效，不重复获取
        if let cached = locationData {
            let age = Date().timeIntervalSince(cached.cachedAt)
            if age < cacheExpirationTime {
                print("ℹ️ [IPLocationManager] 使用缓存的IP定位信息（年龄: \(Int(age/60))分钟）")
                return
            }
        }
        
        isLoading = true
        
        // 调用服务器端接口 /v1/locations/ip，须传 token
        // 不传ip参数，服务器会自动从请求头获取客户端IP
        print("🔍 [IPLocationManager] 即将请求 GET /v1/locations/ip（此后应看到 APIClient 的 🌐 请求日志）")
        let result: Result<IPLocationResponse, AppError> = await APIClient.shared.request(
            "/v1/locations/ip",
            method: .get,
            parameters: nil,
            requiresAuth: true
        )
        
        switch result {
        case .success(let response):
            // 打印返回的原始数据用于调试
            print("📡 [IPLocationManager] ========== IP定位接口返回值 ==========")
            print("📡 [IPLocationManager] 服务器返回的IP定位数据:")
            print("   - country: \"\(response.country ?? "nil")\"")
            print("   - administrativeArea: \"\(response.administrativeArea ?? "nil")\"")
            print("   - locality: \"\(response.locality ?? "nil")\"")
            print("   - postalCode: \"\(response.postalCode ?? "nil")\"")
            print("📡 [IPLocationManager] ======================================")
            
            let locationData = IPLocationData(
                country: response.country,
                administrativeArea: response.administrativeArea,
                locality: response.locality,
                postalCode: response.postalCode
            )
            self.locationData = locationData
            await saveToCache(locationData)
            print("✅ [IPLocationManager] IP定位信息获取成功并已缓存")
        case .failure(let error):
            print("⚠️ [IPLocationManager] IP定位信息获取失败: \(error.localizedDescription)，将使用缓存或默认值")
        }
        
        isLoading = false
    }
    
    /// 获取缓存的定位数据（用于支付页面填充）
    func getCachedLocation() -> IPLocationData? {
        return locationData
    }
}

/// 服务器端IP定位响应格式
extension IPLocationManager {
    struct IPLocationResponse: Codable {
        let country: String?
        let administrativeArea: String?
        let locality: String?
        let postalCode: String?
        
        // 注意：服务器返回的是camelCase格式（administrativeArea, postalCode）
        // APIClient使用了convertFromSnakeCase，但服务器返回的已经是camelCase
        // 所以我们需要直接匹配字段名，不需要CodingKeys映射
        // 如果服务器返回snake_case，APIClient会自动转换；如果已经是camelCase，直接匹配
    }
}
