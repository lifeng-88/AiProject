//
//  RemotePushRoute.swift
//  bbb
//
//  远程推送 data 载荷解析（与网关约定 push_type 及字段名一致，兼容部分值为数字类型）。
//
//  正式约定（自定义段可放在根级或与 `data` 嵌套，二者会拍平后解析）：
//  - `generation_success` / `generation_failure`：`task_id`（字符串）
//  - `feedback_reply`：`feedback_id`，`campaign_id`（可选）
//  - `return_user_coins_claim`：`claim_id`，`campaign_id`（可选），`reward_coins`
//  - `recharge_incentive_new_user`：`offer_id`，`apple_product_id`，`campaign_id`（可选），`amount_cents_usd`，`base_coins`，`bonus_coins`
//  - `template_category`：`template_tab_id`，`catalog_id`（可选），`campaign_id`（可选）
//

import Foundation

extension Notification.Name {
    /// `object` 为 `RemotePushRoute`；主线程投递，由 `ContentView` 交给 `AppTabRouter.dispatchRemotePush`。
    static let bbbRemotePushRoute = Notification.Name("bbbRemotePushRoute")
}

/// 新用户充值激励（push_type: `recharge_incentive_new_user`）
struct RechargeNewUserOfferPayload: Equatable {
    let offerId: String
    let appleProductId: String
    let campaignId: String?
    let amountCentsUsd: Int
    let baseCoins: Int
    let bonusCoins: Int
}

/// 首页上新：模板一级 Tab + 可选视频二级分类（push_type: `template_category`）
struct HomeTemplateCategoryPush: Equatable {
    /// 与 `/v1/template_tabs` 的 `titleId` 一致：1 Image / 2 Video / 3 Dance
    let templateTabId: Int32
    let catalogId: Int32?
    let campaignId: String?
}

/// 老用户回归送金币（push_type: `return_user_coins_claim`）
struct ReturnUserCoinsClaimPayload: Equatable {
    let claimId: String
    let campaignId: String?
    let rewardCoins: Int
}

/// 待打开的创作任务（生成成功/失败推送）
struct PendingCreationOpen: Equatable {
    let taskId: String
    /// `true`：优先进「生成成功」全屏；`false`：进任务详情
    let preferSuccessSheet: Bool
}

enum RemotePushRoute: Equatable {
    case generationSuccess(taskId: String)
    case generationFailure(taskId: String)
    case feedbackReply(feedbackId: String, campaignId: String?)
    case returnUserCoinsClaim(ReturnUserCoinsClaimPayload)
    case rechargeIncentiveNewUser(RechargeNewUserOfferPayload)
    case templateCategory(HomeTemplateCategoryPush)

    /// 从 APNs `userInfo` 根级或 `data` 嵌套字典解析。
    static func parse(userInfo: [AnyHashable: Any]) -> RemotePushRoute? {
        let flat = flattenUserInfo(userInfo)
        guard let rawType = stringValue(flat["push_type"])?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawType.isEmpty
        else {
            return nil
        }

        switch rawType {
        case "generation_success":
            guard let tid = stringValue(flat["task_id"]) else { return nil }
            return .generationSuccess(taskId: tid)
        case "generation_failure":
            guard let tid = stringValue(flat["task_id"]) else { return nil }
            return .generationFailure(taskId: tid)
        case "feedback_reply":
            guard let fid = stringValue(flat["feedback_id"]) else { return nil }
            let campaign = stringValue(flat["campaign_id"])
            return .feedbackReply(feedbackId: fid, campaignId: campaign)
        case "return_user_coins_claim":
            guard let claimId = stringValue(flat["claim_id"]) else { return nil }
            let coins = intValue(flat["reward_coins"]) ?? 0
            let campaign = stringValue(flat["campaign_id"])
            return .returnUserCoinsClaim(
                ReturnUserCoinsClaimPayload(claimId: claimId, campaignId: campaign, rewardCoins: coins)
            )
        case "recharge_incentive_new_user":
            guard let offerId = stringValue(flat["offer_id"]),
                  let applePid = stringValue(flat["apple_product_id"])
            else { return nil }
            let campaign = stringValue(flat["campaign_id"])
            let cents = intValue(flat["amount_cents_usd"]) ?? 0
            let base = intValue(flat["base_coins"]) ?? 0
            let bonus = intValue(flat["bonus_coins"]) ?? 0
            return .rechargeIncentiveNewUser(
                RechargeNewUserOfferPayload(
                    offerId: offerId,
                    appleProductId: applePid,
                    campaignId: campaign,
                    amountCentsUsd: cents,
                    baseCoins: base,
                    bonusCoins: bonus
                )
            )
        case "template_category":
            guard let tabId = int32Value(flat["template_tab_id"]) else { return nil }
            let cat = int32Value(flat["catalog_id"])
            let campaign = stringValue(flat["campaign_id"])
            return .templateCategory(
                HomeTemplateCategoryPush(templateTabId: tabId, catalogId: cat, campaignId: campaign)
            )
        default:
            return nil
        }
    }

    /// 启动 / 调试日志用：提取 `push_type` 等关键键，避免打印整份 `userInfo`。
    static func diagnosticSummary(userInfo: [AnyHashable: Any]) -> String {
        let flat = flattenUserInfo(userInfo)
        let pushType = stringValue(flat["push_type"]) ?? "(nil)"
        let taskId = stringValue(flat["task_id"])
        let keysSample = flat.keys.sorted().prefix(12).joined(separator: ",")
        if let tid = taskId {
            return "push_type=\(pushType) task_id=\(tid) keys[\(keysSample)]"
        }
        return "push_type=\(pushType) keys[\(keysSample)]"
    }

    /// 与 glam `AppRouteCoordinator.logPushOpen` 的 `extra` 对齐（用于 `push_open` 埋点）。
    static func pushOpenExtra(userInfo: [AnyHashable: Any], route: RemotePushRoute) -> [String: Any] {
        var extra: [String: Any] = [:]
        let flat = flattenUserInfo(userInfo)
        if let t = stringValue(flat["push_type"]) { extra["push_type"] = t }
        if let tid = stringValue(flat["task_id"]) { extra["task_id"] = tid }
        if let fid = stringValue(flat["feedback_id"]) { extra["feedback_id"] = fid }
        if let c = stringValue(flat["campaign_id"]) { extra["campaign_id"] = c }
        if let o = stringValue(flat["offer_id"]) { extra["offer_id"] = o }
        if let ap = stringValue(flat["apple_product_id"]) { extra["apple_product_id"] = ap }
        if let ac = int64ForPushExtra(flat["amount_cents_usd"]) { extra["amount_cents_usd"] = ac }
        if let bc = int64ForPushExtra(flat["base_coins"]) { extra["base_coins"] = bc }
        if let bo = int64ForPushExtra(flat["bonus_coins"]) { extra["bonus_coins"] = bo }
        if let cl = stringValue(flat["claim_id"]) { extra["claim_id"] = cl }
        if let rc = int64ForPushExtra(flat["reward_coins"]) { extra["reward_coins"] = rc }
        switch route {
        case .templateCategory(let p):
            extra["template_tab_id"] = Int(p.templateTabId)
            if let c = p.catalogId {
                extra["catalog_id"] = Int(c)
            }
        default:
            break
        }
        return extra
    }

    static func taskIdForPushOpen(route: RemotePushRoute) -> String? {
        switch route {
        case .generationSuccess(let tid), .generationFailure(let tid):
            return tid
        default:
            return nil
        }
    }

    /// 日志用：`userInfo` 能否解析为已知 `push_type` 且必传字段齐全（区分「通知到了但 payload 结构不对」）。
    static func recognizesBusinessPayload(userInfo: [AnyHashable: Any]) -> Bool {
        parse(userInfo: userInfo) != nil
    }

    private static func int64ForPushExtra(_ any: Any?) -> Int64? {
        switch any {
        case let i as Int64:
            return i
        case let i as Int:
            return Int64(i)
        case let n as NSNumber:
            return n.int64Value
        case let s as String:
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return Int64(t)
        default:
            return nil
        }
    }

    private static func flattenUserInfo(_ userInfo: [AnyHashable: Any]) -> [String: Any] {
        var out: [String: Any] = [:]
        for (k, v) in userInfo {
            guard let ks = k as? String else { continue }
            if ks == "aps" { continue }
            out[ks] = v
        }
        if let data = userInfo["data"] as? [String: Any] {
            for (k, v) in data {
                out[k] = v
            }
        }
        if let nested = userInfo["data"] as? [AnyHashable: Any] {
            for (k, v) in nested {
                if let ks = k as? String { out[ks] = v }
            }
        }
        return out
    }

    private static func stringValue(_ any: Any?) -> String? {
        guard let any else { return nil }
        if let s = any as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        if let n = any as? NSNumber {
            return "\(n)"
        }
        return nil
    }

    private static func intValue(_ any: Any?) -> Int? {
        guard let any else { return nil }
        if let i = any as? Int { return i }
        if let i32 = any as? Int32 { return Int(i32) }
        if let i64 = any as? Int64 { return Int(i64) }
        if let n = any as? NSNumber { return n.intValue }
        if let s = any as? String { return Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }

    private static func int32Value(_ any: Any?) -> Int32? {
        guard let any else { return nil }
        if let i = any as? Int32 { return i }
        if let i = any as? Int { return Int32(i) }
        if let i64 = any as? Int64 { return Int32(truncatingIfNeeded: i64) }
        if let n = any as? NSNumber { return n.int32Value }
        if let s = any as? String, let v = Int32(s.trimmingCharacters(in: .whitespacesAndNewlines)) { return v }
        return nil
    }
}

extension RemotePushRoute: CustomStringConvertible {
    var description: String {
        switch self {
        case .generationSuccess(let taskId):
            return "generationSuccess(taskId:\(taskId))"
        case .generationFailure(let taskId):
            return "generationFailure(taskId:\(taskId))"
        case .feedbackReply(let feedbackId, let campaignId):
            return "feedbackReply(feedbackId:\(feedbackId), campaignId:\(campaignId ?? "nil"))"
        case .returnUserCoinsClaim(let p):
            return "returnUserCoinsClaim(claimId:\(p.claimId), rewardCoins:\(p.rewardCoins))"
        case .rechargeIncentiveNewUser(let p):
            return "rechargeIncentiveNewUser(offerId:\(p.offerId), campaignId:\(p.campaignId ?? "nil"))"
        case .templateCategory(let p):
            return "templateCategory(templateTabId:\(p.templateTabId), catalogId:\(p.catalogId.map { "\($0)" } ?? "nil"))"
        }
    }
}
