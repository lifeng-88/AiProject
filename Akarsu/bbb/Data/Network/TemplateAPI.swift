//
//  TemplateAPI.swift
//  glam
//
//  Created by Dev on 2026/1/18.
//

import Foundation

/// 模板相关 API
struct TemplateAPI {
    static let client = APIClient.shared
    
    /// 获取模板标签列表
    /// - Parameter locale: 语言标识，如 en、zh-Hant，缺省用 en
    static func getTemplateTabs(locale: String = "en") async -> Result<TemplateTabsResponse, AppError> {
        let parameters: [String: Any] = locale.isEmpty ? [:] : ["locale": locale]
        return await client.request(
            "/v1/template_tabs",
            method: .get,
            parameters: parameters.isEmpty ? nil : parameters
        )
    }
    
    /// 获取首页子分类标签列表（`/v1/catalogs`），与 Video `catalogId`、Image/Dance 标题筛选共用
    /// - Parameter locale: 语言标识，如 en、zh-Hant，缺省用 en
    static func getCatalogs(locale: String = "en") async -> Result<CatalogsResponse, AppError> {
        let parameters: [String: Any] = locale.isEmpty ? [:] : ["locale": locale]
        return await client.request(
            "/v1/catalogs",
            method: .get,
            parameters: parameters.isEmpty ? nil : parameters
        )
    }
    
    /// 获取图片模板列表 (T1)
    static func getImageTemplates(pageNum: Int32?, pageSize: Int32?) async -> Result<ImageTemplateListResponse, AppError> {
        var parameters: [String: Any] = [:]
        if let pageNum = pageNum {
            parameters["pageNum"] = pageNum
        }
        if let pageSize = pageSize {
            parameters["pageSize"] = pageSize
        }
        
        return await client.request(
            "/v1/t1",
            method: .get,
            parameters: parameters.isEmpty ? nil : parameters
        )
    }
    
    /// 获取舞蹈模板列表 (T2)
    static func getDancingTemplates(pageNum: Int32?, pageSize: Int32?, titleId: Int32) async -> Result<DancingTemplateListResponse, AppError> {
        var parameters: [String: Any] = [:]
        if let pageNum = pageNum {
            parameters["pageNum"] = pageNum
        }
        if let pageSize = pageSize {
            parameters["pageSize"] = pageSize
        }
        // 添加 titleId 参数：titleId=3 对应 Dancing
        parameters["titleId"] = titleId
        
        return await client.request(
            "/v1/t2",
            method: .get,
            parameters: parameters
        )
    }
    
    /// 获取视频模板列表 (T3)
    /// 注意：如果 catalogId 为 nil（表示 "All"），则不传递 catalogId 参数
    static func getVideoTemplates(pageNum: Int32?, pageSize: Int32?, catalogId: Int32?, titleId: Int32) async -> Result<VideoTemplateListResponse, AppError> {
        var parameters: [String: Any] = [:]
        if let pageNum = pageNum {
            parameters["pageNum"] = pageNum
        }
        if let pageSize = pageSize {
            parameters["pageSize"] = pageSize
        }
        // 只有当 catalogId 不为 nil 时才添加到参数中（nil 表示 "All"，不传递 catalogId）
        if let catalogId = catalogId {
            parameters["catalogId"] = catalogId
            print("🌐 [TemplateAPI] getVideoTemplates with catalogId: \(catalogId)")
        } else {
            print("🌐 [TemplateAPI] getVideoTemplates without catalogId (All categories)")
        }
        // 添加 titleId 参数：titleId=2 对应 Video
        parameters["titleId"] = titleId
        
        return await client.request(
            "/v1/t3",
            method: .get,
            parameters: parameters
        )
    }
    
    /// 获取图片模板详情 (T1)
    static func getImageTemplateDetail(tid: String) async -> Result<ImageTemplate, AppError> {
        return await client.request(
            "/v1/t1/\(tid)",
            method: .get
        )
    }
    
    /// 获取舞蹈模板详情 (T2)
    static func getDancingTemplateDetail(tid: String) async -> Result<DancingTemplate, AppError> {
        return await client.request(
            "/v1/t2/\(tid)",
            method: .get
        )
    }
    
    /// 获取视频模板详情 (T3)
    static func getVideoTemplateDetail(tid: String) async -> Result<VideoTemplate, AppError> {
        return await client.request(
            "/v1/t3/\(tid)",
            method: .get
        )
    }
}
