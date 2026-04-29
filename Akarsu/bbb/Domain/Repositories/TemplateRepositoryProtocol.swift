//
//  TemplateRepositoryProtocol.swift
//  glam
//
//  Created by Dev on 2026/1/18.
//

import Foundation

/// 模板 Repository 协议
protocol TemplateRepositoryProtocol {
    /// 获取模板标签列表
    /// - Parameter locale: 语言标识，如 en、zh-Hant
    func getTemplateTabs(locale: String) async -> Result<[TemplateTab], AppError>
    
    /// 获取分类列表（`/v1/catalogs`，首页横向子分类标签 + Video 的 `catalogId`）
    /// - Parameters:
    ///   - locale: 语言标识，如 en、zh-Hant
    ///   - forceRefresh: 为 `true` 时跳过磁盘缓存，直接请求接口
    func getCatalogs(locale: String, forceRefresh: Bool) async -> Result<[Catalog], AppError>
    
    /// 获取图片模板列表 (T1)
    func getImageTemplates(pageNum: Int32?, pageSize: Int32?) async -> Result<ImageTemplateListResponse, AppError>
    
    /// 获取舞蹈模板列表 (T2)
    func getDancingTemplates(pageNum: Int32?, pageSize: Int32?, titleId: Int32) async -> Result<DancingTemplateListResponse, AppError>
    
    /// 获取视频模板列表 (T3)
    func getVideoTemplates(pageNum: Int32?, pageSize: Int32?, catalogId: Int32?, titleId: Int32) async -> Result<VideoTemplateListResponse, AppError>
    
    /// 获取图片模板详情 (T1)
    func getImageTemplateDetail(tid: String) async -> Result<ImageTemplate, AppError>
    
    /// 获取舞蹈模板详情 (T2)
    func getDancingTemplateDetail(tid: String) async -> Result<DancingTemplate, AppError>
    
    /// 获取视频模板详情 (T3)
    func getVideoTemplateDetail(tid: String) async -> Result<VideoTemplate, AppError>
}
