//
//  BehaviorEventQueue.swift
//  glam
//
//  本地行为事件队列与批量上报策略。协议文档：协议文档/统计与埋点协议.md
//  触发条件：队列长度 ≥ N、距上次成功上报 ≥ T 秒、应用进入后台（由调用方在 scenePhase 中调用 flush）。
//  与 glam `BehaviorEventQueue` 对齐：`template_type`、`push_open` 即时上报等。
//

import Foundation

/// 行为事件队列：内存队列 + 条数/时间/后台触发，满足条件时调用批量上报接口
actor BehaviorEventQueue {
    static let shared = BehaviorEventQueue()

    private var queue: [BehaviorEventItem] = []
    private var lastSuccessFlushTime: Date?
    /// 统计 batch 前节流刷新 access，减轻 OpenResty 对「临近过期 JWT」直接 401 HTML 的情况（秒）
    private var lastStatisticsBatchAuthRefreshAt: Date?
    private let statisticsBatchAuthRefreshMinInterval: TimeInterval = 180

    /// 条数达到该值时触发上报（提高以减少请求次数）
    private let countThreshold: Int = 20
    /// 距上次成功上报超过该秒数且队列非空时触发上报
    private let timeThresholdSeconds: TimeInterval = 60
    /// 自动上报的最小间隔（秒），避免短时间内重复请求；仅影响 tryFlush，不影响进入后台时的 flush()
    private let minIntervalBetweenAutoFlushSeconds: TimeInterval = 45

    private init() {}

    /// 推送点击打开（`push_open`），含 campaign_id、push_type 等 extra；与协议中模板/支付类并列上报
    func enqueuePushOpen(taskId: String?, extra: [String: Any]?) {
        enqueue(
            eventType: "push_open",
            templateId: "",
            taskId: taskId,
            ts: Int64(Date().timeIntervalSince1970),
            templateType: nil,
            extra: extra
        )
    }

    /// 写入一条事件并入队；若满足触发条件则执行一次上报
    /// - Parameters:
    ///   - extra: 支付类事件扩展字段（package_id、order_id、payment_method、amount 等）；模板类不传
    ///   - templateType: 对应 proto 字段 `template_type`（1/2/3）；支付/推送等不传
    func enqueue(eventType: String, templateId: String, taskId: String? = nil, ts: Int64? = nil, templateType: Int? = nil, extra: [String: Any]? = nil) {
        let item = BehaviorEventItem(
            eventType: eventType,
            templateId: templateId,
            taskId: taskId,
            ts: ts ?? Int64(Date().timeIntervalSince1970),
            templateType: templateType,
            extra: extra
        )
        queue.append(item)
        print("📊 [BehaviorEventQueue] 事件入队: eventType=\(eventType), templateId=\(templateId), queueSize=\(queue.count), hasExtra=\(extra != nil)")
        Task { await tryFlushIfNeeded() }
    }

    /// 外部在应用进入后台时调用，立即上报当前队列
    func flush() async {
        print("📊 [BehaviorEventQueue] 应用进入后台，立即上报队列（当前队列长度: \(queue.count)）")
        await doFlush()
    }

    /// 若队列长度 ≥ 阈值、距上次成功上报 ≥ T 秒且队列非空、或队列中含支付类事件，则执行上报。
    /// 支付类事件（recharge_*）较少，单独依赖 20 条/60 秒会漏报，故有支付事件时也触发上报。
    /// 在 minIntervalBetweenAutoFlushSeconds 内不重复自动上报，除非队列积压过多（≥50）或有支付事件。
    private func tryFlushIfNeeded() async {
        let now = Date()
        let elapsed = lastSuccessFlushTime.map { now.timeIntervalSince($0) } ?? .infinity
        let withinMinInterval = lastSuccessFlushTime != nil && elapsed < minIntervalBetweenAutoFlushSeconds
        let shouldByCount = queue.count >= countThreshold
        let shouldByTime = queue.count > 0 && elapsed >= timeThresholdSeconds
        let tooManyPending = queue.count >= 50
        let hasPaymentEvents = queue.contains { $0.eventType.hasPrefix("recharge_") }
        let hasFeedbackEvents = queue.contains { $0.eventType.hasPrefix("feedback_") }
        let hasPushEvents = queue.contains { $0.eventType == "push_open" }

        if hasPaymentEvents || hasFeedbackEvents || hasPushEvents || ((shouldByCount || shouldByTime) && (!withinMinInterval || tooManyPending)) {
            if hasPaymentEvents {
                print("📊 [BehaviorEventQueue] 队列含支付类事件，触发上报（queueSize=\(queue.count)）")
            } else if hasFeedbackEvents {
                print("📊 [BehaviorEventQueue] 队列含反馈类事件，触发上报（queueSize=\(queue.count)）")
            } else if hasPushEvents {
                print("📊 [BehaviorEventQueue] 队列含 push_open 事件，触发上报（queueSize=\(queue.count)）")
            } else {
                print("📊 [BehaviorEventQueue] 满足上报条件: shouldByCount=\(shouldByCount), shouldByTime=\(shouldByTime), queueSize=\(queue.count)")
            }
            await doFlush()
        }
    }

    private func doFlush() async {
        guard !queue.isEmpty else {
            print("📊 [BehaviorEventQueue] 队列为空，跳过上报")
            return
        }

        let batch = Array(queue.prefix(100))
        let channelId = await AppConfig.shared.getChannel()
        // 与线上 OpenResty 一致：`/v1/statistics/events/batch` 需带有效 Bearer；无会话时发请求会得到 HTML 401 Authorization Required。
        guard await AuthRepository.shared.getCurrentAuthInfo() != nil else {
            print("📊 [BehaviorEventQueue] 无本地会话，跳过 events/batch（避免无 Authorization 被网关拒绝）；登录后下次入队或切后台会再上报")
            return
        }
        await refreshAccessTokenForStatisticsBatchIfStale()
        guard let auth = await AuthRepository.shared.getCurrentAuthInfo() else {
            print("📊 [BehaviorEventQueue] 刷新后会话丢失，跳过 events/batch")
            return
        }
        let userId: Int64? = Int64(auth.userid.trimmingCharacters(in: .whitespacesAndNewlines))
        let deviceId = await DeviceManager.shared.getDeviceId()
        let appVersion = await DeviceManager.shared.getAppVersion()

        print("📊 [BehaviorEventQueue] 开始上报: batchSize=\(batch.count), channelId=\(channelId), userId=\(userId.map { "\($0)" } ?? auth.userid), deviceId=\(deviceId)")
        for (index, event) in batch.enumerated() {
            print("   [\(index + 1)] eventType=\(event.eventType), templateId=\(event.templateId), hasExtra=\(event.extra != nil)")
        }

        let result = await StatisticsAPI.reportBatch(
            channelId: channelId,
            userId: userId,
            deviceId: deviceId,
            events: batch,
            appVersion: appVersion,
            platform: "iOS"
        )

        switch result {
        case .success(let response):
            let n = batch.count
            if queue.count >= n {
                queue.removeFirst(n)
            } else {
                queue.removeAll()
            }
            lastSuccessFlushTime = Date()
            print("✅ [BehaviorEventQueue] 上报成功: accepted=\(response.accepted), rejected=\(response.rejected), 剩余队列长度=\(queue.count)")
        case .failure(let error):
            // 保留本批，下次满足条件时重试
            print("❌ [BehaviorEventQueue] 上报失败: \(error.localizedDescription), 保留本批待重试（队列长度: \(queue.count)）")
        }
    }

    /// 在发 `events/batch` 前尝试刷新 access（`AuthRepository` 成功时会写 Keychain 并同步 `APIClient`），节流避免频繁打 `/v1/refresh`。
    private func refreshAccessTokenForStatisticsBatchIfStale() async {
        let now = Date()
        if let last = lastStatisticsBatchAuthRefreshAt,
           now.timeIntervalSince(last) < statisticsBatchAuthRefreshMinInterval {
            return
        }
        lastStatisticsBatchAuthRefreshAt = now
        guard let info = await AuthRepository.shared.getCurrentAuthInfo() else { return }
        switch await AuthRepository.shared.refreshToken(refreshToken: info.refreshToken) {
        case .success:
            print("📊 [BehaviorEventQueue] 统计上报前已刷新 access token（节流间隔 \(Int(statisticsBatchAuthRefreshMinInterval))s）")
        case .failure:
            print("📊 [BehaviorEventQueue] 统计上报前 token 刷新失败，沿用当前 access token 尝试 batch")
        }
    }
}
