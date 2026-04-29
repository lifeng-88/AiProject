//
//  KeychainManager.swift
//  glam
//
//  Created by Dev on 2026/1/18.
//

import Foundation
import Security

/// Keychain 管理器 - 用于安全存储敏感数据（Token 等）
actor KeychainManager {
    static let shared = KeychainManager()
    
    private let service: String
    
    private init() {
        self.service = Bundle.main.bundleIdentifier ?? "glam"
    }
    
    /// 保存数据到 Keychain
    func save(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw AppError.storageError("Failed to convert string to data")
        }
        
        // 删除已存在的项
        delete(key: key)
        
        // 创建查询字典
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        
        // 添加项
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw AppError.storageError("Failed to save to keychain: \(status)")
        }
    }
    
    /// 从 Keychain 读取数据
    func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return value
    }
    
    /// 从 Keychain 删除数据
    func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        SecItemDelete(query as CFDictionary)
    }
    
    /// 清空所有 Keychain 数据
    func clearAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}
