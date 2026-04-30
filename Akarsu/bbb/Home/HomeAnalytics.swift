//
//  HomeAnalytics.swift
//  bbb
//
//  首页模板曝光/点击：`extra.list_source` 区分大列表（沉浸式全屏竖滑）与小列表（双列网格）。
//

import Foundation

/// 列表形态，与统计 `extra.list_source` 对齐：`immersive` = 大列表，`grid` = 小列表
enum HomeFeedListSource: String {
    case immersive
    case grid
    /// 从通知等入口发起生成，非首页双列表
    case other

    /// 与 `extra.feed_layout` 对齐：大列表 = 沉浸式全屏竖滑，小列表 = 双列网格
    var feedLayoutRawValue: String {
        switch self {
        case .immersive: return "large_list"
        case .grid: return "small_list"
        case .other: return "other"
        }
    }
}

enum HomeTemplateClickAction: String {
    /// 底部主按钮（SWAP 等）发起生成
    case primaryGenerate = "primary_generate"
    /// 网格点击进详情
    case openDetail = "open_detail"
}

enum HomeTemplateAnalytics {
    /// `templateType`：与 proto `template_type` 一致（1/2/3）；与 glam `HomeView` 埋点一致
    static func logExposure(templateId: String, listSource: HomeFeedListSource, templateType: Int?) {
        guard !templateId.isEmpty else { return }
        Task {
            await BehaviorEventQueue.shared.enqueue(
                eventType: "template_exposure",
                templateId: templateId,
                taskId: nil,
                ts: nil,
                templateType: templateType,
                extra: Self.listExtra(listSource: listSource)
            )
        }
    }

    static func logClick(templateId: String, listSource: HomeFeedListSource, action: HomeTemplateClickAction, templateType: Int?) {
        guard !templateId.isEmpty else { return }
        Task {
            var extra = Self.listExtra(listSource: listSource)
            extra["click_action"] = action.rawValue
            await BehaviorEventQueue.shared.enqueue(
                eventType: "template_click",
                templateId: templateId,
                taskId: nil,
                ts: nil,
                templateType: templateType,
                extra: extra
            )
        }
    }

    /// `list_source`：技术枚举（immersive / grid / other）；`feed_layout`：业务侧大列表/小列表区分
    private static func listExtra(listSource: HomeFeedListSource) -> [String: Any] {
        [
            "list_source": listSource.rawValue,
            "feed_layout": listSource.feedLayoutRawValue
        ]
    }
}
