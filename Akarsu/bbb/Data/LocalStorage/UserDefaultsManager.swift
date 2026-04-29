//
//  UserDefaultsManager.swift
//  glam
//
//  Created by Dev on 2026/1/18.
//

import Combine
import Foundation

/// UserDefaults 管理器 - 用于存储非敏感数据
actor UserDefaultsManager {
    static let shared = UserDefaultsManager()
    
    private let userDefaults: UserDefaults
    
    private init() {
        self.userDefaults = UserDefaults.standard
    }
    
    /// 保存字符串值
    func set(_ value: String, forKey key: String) {
        userDefaults.set(value, forKey: key)
    }
    
    /// 获取字符串值
    func string(forKey key: String) -> String? {
        return userDefaults.string(forKey: key)
    }
    
    /// 保存布尔值
    func set(_ value: Bool, forKey key: String) {
        userDefaults.set(value, forKey: key)
    }
    
    /// 获取布尔值
    func bool(forKey key: String) -> Bool {
        return userDefaults.bool(forKey: key)
    }
    
    /// 保存整数
    func set(_ value: Int, forKey key: String) {
        userDefaults.set(value, forKey: key)
    }
    
    /// 获取整数
    func integer(forKey key: String) -> Int {
        return userDefaults.integer(forKey: key)
    }
    
    /// 保存 Int32 值
    func set(_ value: Int32, forKey key: String) {
        userDefaults.set(Int(value), forKey: key)
    }
    
    /// 获取 Int32 值（如果不存在返回 nil）
    func int32(forKey key: String) -> Int32? {
        let value = userDefaults.integer(forKey: key)
        // UserDefaults.integer 在不存在时返回 0，我们需要区分 0 和不存在
        if userDefaults.object(forKey: key) == nil {
            return nil
        }
        return Int32(value)
    }
    
    /// 删除值
    func remove(forKey key: String) {
        userDefaults.removeObject(forKey: key)
    }
    
    /// 保存 Data 值
    func set(_ value: Data, forKey key: String) {
        userDefaults.set(value, forKey: key)
    }
    
    /// 获取 Data 值
    func getData(forKey key: String) -> Data? {
        return userDefaults.data(forKey: key)
    }
    
    /// 清除所有数据
    func clearAll() {
        if let bundleID = Bundle.main.bundleIdentifier {
            userDefaults.removePersistentDomain(forName: bundleID)
        }
    }
}

/// UserDefaults 键名常量
enum UserDefaultsKey {
    static let shouldShowPhotoTips = "shouldShowPhotoTips"
    static let deviceId = "deviceId"
    static let selectedTemplateTabId = "selectedTemplateTabId"
    static let selectedCatalogId = "selectedCatalogId"
    static let currentTemplateIndex = "currentTemplateIndex"
    static let lastSelectedPayChannelId = "lastSelectedPayChannelId"
}
