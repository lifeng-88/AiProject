//
//  TemplateModels.swift
//  glam
//
//  Created by Dev on 2026/1/18.
//

import Foundation

/// 模板标签
struct TemplateTab: Identifiable, Codable {
    let id: Int32
    let title: String
    
    enum CodingKeys: String, CodingKey {
        case id = "titleId"
        case title
    }
}

/// 模板标签列表响应
struct TemplateTabsResponse: Codable {
    let list: [TemplateTab]
}

// MARK: - Catalog (二级分类)

/// 二级分类（用于视频模板筛选）
struct Catalog: Identifiable, Codable {
    let id: Int32
    let name: String
    
    enum CodingKeys: String, CodingKey {
        case id = "catalogId"
        case name = "catalog"
    }
}

/// Catalog 列表响应
struct CatalogsResponse: Codable {
    let list: [Catalog]
}

// MARK: - 模板类型

/// 模板类型枚举
enum TemplateType {
    case image       // T1 - 图片模板
    case dancing     // T2 - 舞蹈模板
    case video       // T3 - 视频模板
}

/// 与网关路径 `/v1/t1`、`/v1/t2`、`/v1/t3` 一致；收藏接口 `targetType`：1 t1；2 t2；3 t3（见 `v1Favorite`）
enum TemplateResourceKind: String, Codable {
    case t1
    case t2
    case t3

    /// `ShopInterface` 收藏 `targetType`
    var favoriteTargetType: Int32 {
        switch self {
        case .t1: return 1
        case .t2: return 2
        case .t3: return 3
        }
    }

    /// 创建任务接口 `taskType`（与 `favoriteTargetType` 一致：1 T1 / 2 T2 / 3 T3）
    var apiTaskType: Int32 { favoriteTargetType }
}

/// 基础模板协议
protocol TemplateProtocol: Identifiable {
    var id: String { get }
    var title: String { get }
    var consumedGold: String { get }
}

// MARK: - T1: 图片模板 (UndressTemplate)

/// 图片模板
struct ImageTemplate: TemplateProtocol, Codable {
    let id: String
    let title: String
    let beforePics: [String]
    let beforePicsType: [Int32]
    let afterPic: String
    let changeBackground: Bool
    let transAnimation: String
    let consumedGold: String
    
    enum CodingKeys: String, CodingKey {
        case id = "tid"
        case title
        case beforePics
        case beforePicsType
        case afterPic
        case changeBackground
        case transAnimation
        case consumedGold
    }
}

/// 图片模板列表响应
struct ImageTemplateListResponse: Codable {
    let list: [ImageTemplate]
    let total: Int32
}

// MARK: - T2: 舞蹈模板 (NudeDancingTemplate)

/// 舞蹈模板
struct DancingTemplate: TemplateProtocol, Codable {
    let id: String
    let title: String
    let beforePic: String
    let afterVideo: String
    let duration: Int32
    let transAnimation: String
    let changeBackground: Bool
    let afterSnapshot: String? // 详情接口可能不返回此字段
    let consumedGold: String
    
    enum CodingKeys: String, CodingKey {
        case id = "tid"
        case title
        case beforePic
        case afterVideo
        case duration
        case transAnimation
        case changeBackground
        case afterSnapshot
        case consumedGold
    }
}

/// 舞蹈模板列表响应
struct DancingTemplateListResponse: Codable {
    let list: [DancingTemplate]
    let total: Int32
}

// MARK: - T3: 视频模板 (UndressVideoTemplate)

/// 视频模板
struct VideoTemplate: TemplateProtocol, Codable {
    let id: String
    let title: String
    let beforePics: [String]
    let beforePicsType: [Int32]
    let changeBackground: Bool
    let afterVideo: String
    let duration: Int32
    let catalogId: Int32?
    let labelIds: [Int32]?
    let transAnimation: String
    let afterSnapshot: String? // 详情接口可能不返回此字段
    let consumedGold: String // 480p 价格
    let consumedGold720: String? // 720p 价格（可选，列表接口可能不返回）
    
    enum CodingKeys: String, CodingKey {
        case id = "tid"
        case title
        case beforePics
        case beforePicsType
        case changeBackground
        case afterVideo
        case duration
        case catalogId
        case labelIds
        case transAnimation
        case afterSnapshot
        case consumedGold
        case consumedGold720
    }
}

/// 视频模板列表响应
struct VideoTemplateListResponse: Codable {
    let list: [VideoTemplate]
    let total: Int32
}
