//
//  TemplateDataCacheManager.swift
//  glam
//
//  Created by Dev on 2026/1/18.
//

import Foundation

/// 模板数据缓存管理器
/// 负责缓存模板标签、分类列表、模板列表等数据
@MainActor
class TemplateDataCacheManager {
    static let shared = TemplateDataCacheManager()
    
    private let cacheDirectory: URL
    private let fileManager = FileManager.default
    
    /// 缓存过期时间（7天）
    private let cacheExpirationTime: TimeInterval = 7 * 24 * 60 * 60
    
    private init() {
        let cacheURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.cacheDirectory = cacheURL.appendingPathComponent("TemplateData", isDirectory: true)
        
        // 创建缓存目录
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    // MARK: - Template Tabs 缓存
    
    func getCachedTemplateTabs(locale: String) -> [TemplateTab]? {
        let fileName = "template_tabs_\(locale).json"
        return getCachedData(fileName: fileName, as: [TemplateTab].self)
    }
    
    func setCachedTemplateTabs(_ tabs: [TemplateTab], locale: String) {
        let fileName = "template_tabs_\(locale).json"
        setCachedData(fileName: fileName, data: tabs)
    }
    
    // MARK: - Catalogs 缓存
    
    func getCachedCatalogs(locale: String) -> [Catalog]? {
        let fileName = "catalogs_\(locale).json"
        return getCachedData(fileName: fileName, as: [Catalog].self)
    }
    
    func setCachedCatalogs(_ catalogs: [Catalog], locale: String) {
        let fileName = "catalogs_\(locale).json"
        setCachedData(fileName: fileName, data: catalogs)
    }
    
    // MARK: - Image Templates 缓存
    
    func getCachedImageTemplates(pageNum: Int32? = nil, pageSize: Int32? = nil) -> ImageTemplateListResponse? {
        let key = "imageTemplates_\(pageNum ?? 1)_\(pageSize ?? 20).json"
        return getCachedData(fileName: key, as: ImageTemplateListResponse.self)
    }
    
    func setCachedImageTemplates(_ response: ImageTemplateListResponse, pageNum: Int32? = nil, pageSize: Int32? = nil) {
        let key = "imageTemplates_\(pageNum ?? 1)_\(pageSize ?? 20).json"
        setCachedData(fileName: key, data: response)
    }
    
    // MARK: - Dancing Templates 缓存
    
    /// `titleId` 须与请求参数一致（如首页 Dance tab 为 3）
    func getCachedDancingTemplates(pageNum: Int32? = nil, pageSize: Int32? = nil, titleId: Int32) -> DancingTemplateListResponse? {
        let key = "dancingTemplates_t\(titleId)_\(pageNum ?? 1)_\(pageSize ?? 20).json"
        return getCachedData(fileName: key, as: DancingTemplateListResponse.self)
    }
    
    func setCachedDancingTemplates(_ response: DancingTemplateListResponse, pageNum: Int32? = nil, pageSize: Int32? = nil, titleId: Int32) {
        let key = "dancingTemplates_t\(titleId)_\(pageNum ?? 1)_\(pageSize ?? 20).json"
        setCachedData(fileName: key, data: response)
    }
    
    // MARK: - Video Templates 缓存
    
    /// `titleId` 须与请求参数一致（如首页 Video tab 为 2）
    func getCachedVideoTemplates(catalogId: Int32? = nil, pageNum: Int32? = nil, pageSize: Int32? = nil, titleId: Int32) -> VideoTemplateListResponse? {
        let catalogKey = catalogId != nil ? "\(catalogId!)" : "all"
        let key = "videoTemplates_\(catalogKey)_t\(titleId)_\(pageNum ?? 1)_\(pageSize ?? 20).json"
        return getCachedData(fileName: key, as: VideoTemplateListResponse.self)
    }
    
    func setCachedVideoTemplates(_ response: VideoTemplateListResponse, catalogId: Int32? = nil, pageNum: Int32? = nil, pageSize: Int32? = nil, titleId: Int32) {
        let catalogKey = catalogId != nil ? "\(catalogId!)" : "all"
        let key = "videoTemplates_\(catalogKey)_t\(titleId)_\(pageNum ?? 1)_\(pageSize ?? 20).json"
        setCachedData(fileName: key, data: response)
    }
    
    // MARK: - Private Helpers
    
    /// 获取缓存数据
    private func getCachedData<T: Codable>(fileName: String, as type: T.Type) -> T? {
        let fileURL = cacheDirectory.appendingPathComponent(fileName)
        
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }
        
        // 检查是否过期（优先用修改时间，覆盖写入后仍能正确失效）
        var isExpired = false
        if let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey]) {
            let ref = values.contentModificationDate ?? values.creationDate
            if let ref, Date().timeIntervalSince(ref) > cacheExpirationTime {
                isExpired = true
            }
        } else if let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
                  let creationDate = attributes[.creationDate] as? Date,
                  Date().timeIntervalSince(creationDate) > cacheExpirationTime {
            isExpired = true
        }
        if isExpired {
            try? fileManager.removeItem(at: fileURL)
            return nil
        }
        
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(T.self, from: data)
        } catch {
            print("⚠️ [TemplateDataCacheManager] Failed to decode cached data from \(fileName): \(error)")
            return nil
        }
    }
    
    /// 保存缓存数据
    private func setCachedData<T: Codable>(fileName: String, data: T) {
        let fileURL = cacheDirectory.appendingPathComponent(fileName)
        
        do {
            let encoder = JSONEncoder()
            let jsonData = try encoder.encode(data)
            try jsonData.write(to: fileURL)
        } catch {
            print("⚠️ [TemplateDataCacheManager] Failed to cache data to \(fileName): \(error)")
        }
    }
    
    /// 清理过期缓存
    func cleanExpiredCache() {
        guard let files = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles) else {
            return
        }
        
        let now = Date()
        for file in files {
            if let attributes = try? fileManager.attributesOfItem(atPath: file.path),
               let creationDate = attributes[.creationDate] as? Date,
               now.timeIntervalSince(creationDate) > cacheExpirationTime {
                try? fileManager.removeItem(at: file)
            }
        }
    }
    
    /// 清理所有缓存
    func clearAllCache() {
        guard let files = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [], options: .skipsHiddenFiles) else {
            return
        }
        
        for file in files {
            try? fileManager.removeItem(at: file)
        }
        print("🗑️ [TemplateDataCacheManager] Cleared all cache")
    }
}
