//
//  TemplateModels.swift
//  glam
//
//  Created by Dev on 2026/1/18.
//

import Foundation

/// 解码列表项 **`isNew` / `isHot`**（JSON 常见 `isNew`/`isHot` 或 `is_new`/`is_hot`，配合 `convertFromSnakeCase`）：值为布尔或 0/1 数字；缺省或解析失败视为关。
struct TemplateListTruthyFlag: Codable, Hashable {
    var isOn: Bool

    init(isOn: Bool) {
        self.isOn = isOn
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            isOn = false
            return
        }
        if let b = try? c.decode(Bool.self) {
            isOn = b
            return
        }
        if let i = try? c.decode(Int32.self) {
            isOn = i != 0
            return
        }
        if let i = try? c.decode(Int.self) {
            isOn = i != 0
            return
        }
        if let i = try? c.decode(Int64.self) {
            isOn = i != 0
            return
        }
        if let d = try? c.decode(Double.self) {
            isOn = d != 0
            return
        }
        if let s = try? c.decode(String.self) {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            isOn = ["1", "true", "yes", "y", "on"].contains(t)
            return
        }
        isOn = false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(isOn)
    }
}

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

    /// 与 proto `BehaviorEventItem.template_type` / 统计批量上报一致：1=t1，2=t2，3=t3
    var behaviorEventTemplateType: Int {
        switch self {
        case .t1: return 1
        case .t2: return 2
        case .t3: return 3
        }
    }
}

/// 模板行为埋点：`template_type`（与 glam `TemplateBehaviorReport` 一致）
enum TemplateBehaviorReport {
    static func templateType(for template: Any?) -> Int? {
        if template is ImageTemplate { return TemplateResourceKind.t1.behaviorEventTemplateType }
        if template is DancingTemplate { return TemplateResourceKind.t2.behaviorEventTemplateType }
        if template is VideoTemplate { return TemplateResourceKind.t3.behaviorEventTemplateType }
        return nil
    }
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
    /// 首页角标：为真则展示 **NEW**（与 `isHot` 同时为真时 UI 优先 **NEW**）
    let isNew: TemplateListTruthyFlag?
    /// 首页角标：为真则展示 **HOT**
    let isHot: TemplateListTruthyFlag?
    /// 成片/预览是否带声轨（接口 `hasAudio` / `has_audio`，见 `TemplateListTruthyFlag`）；客户端默认静音，由用户点喇叭开启。
    let hasAudio: TemplateListTruthyFlag?

    enum CodingKeys: String, CodingKey {
        case id = "tid"
        case title
        case beforePics
        case beforePicsType
        case afterPic
        case changeBackground
        case transAnimation
        case consumedGold
        case isNew
        case isHot
        case hasAudio
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
    /// 首页角标 **NEW**（与 `isHot` 同时为真时优先 NEW）
    let isNew: TemplateListTruthyFlag?
    /// 首页角标 **HOT**
    let isHot: TemplateListTruthyFlag?
    /// 成片是否带声轨（`hasAudio` / `has_audio`）；默认静音，用户点喇叭开声。
    let hasAudio: TemplateListTruthyFlag?

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
        case isNew
        case isHot
        case hasAudio
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
    /// 首页角标 **NEW**（与 `isHot` 同时为真时优先 NEW）
    let isNew: TemplateListTruthyFlag?
    /// 首页角标 **HOT**
    let isHot: TemplateListTruthyFlag?
    /// 成片是否带声轨（`hasAudio` / `has_audio`）；默认静音，用户点喇叭开声。
    let hasAudio: TemplateListTruthyFlag?

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
        case isNew
        case isHot
        case hasAudio
    }
}

/// 视频模板列表响应
struct VideoTemplateListResponse: Codable {
    let list: [VideoTemplate]
    let total: Int32
}
