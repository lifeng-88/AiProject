//
//  BehaviorEventQueue.swift
//  glam
//
//  本地行为事件队列与批量上报策略。协议文档：协议文档/统计与埋点协议.md
//  触发条件：队列长度 ≥ N、距上次成功上报 ≥ T 秒、应用进入后台（由调用方在 scenePhase 中调用 flush）。
//

import Foundation

/// 行为事件队列：内存队列 + 条数/时间/后台触发，满足条件时调用批量上报接口
actor BehaviorEventQueue {
    static let shared = BehaviorEventQueue()

    private var queue: [BehaviorEventItem] = []
    private var lastSuccessFlushTime: Date?

    /// 条数达到该值时触发上报（提高以减少请求次数）
    private let countThreshold: Int = 20
    /// 距上次成功上报超过该秒数且队列非空时触发上报
    private let timeThresholdSeconds: TimeInterval = 60
    /// 自动上报的最小间隔（秒），避免短时间内重复请求；仅影响 tryFlush，不影响进入后台时的 flush()
    private let minIntervalBetweenAutoFlushSeconds: TimeInterval = 45

    private init() {}

    /// 写入一条事件并入队；若满足触发条件则执行一次上报
    /// - Parameter extra: 支付类扩展字段；首页模板类事件可传 `list_source`、`click_action` 等
    func enqueue(eventType: String, templateId: String, taskId: String? = nil, ts: Int64? = nil, extra: [String: Any]? = nil) {
        let item = BehaviorEventItem(
            eventType: eventType,
            templateId: templateId,
            taskId: taskId,
            ts: ts ?? Int64(Date().timeIntervalSince1970),
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
        let hasTemplateEvents = queue.contains { $0.eventType.hasPrefix("template_") }

        if hasPaymentEvents || hasFeedbackEvents || hasTemplateEvents || ((shouldByCount || shouldByTime) && (!withinMinInterval || tooManyPending)) {
            if hasPaymentEvents {
                print("📊 [BehaviorEventQueue] 队列含支付类事件，触发上报（queueSize=\(queue.count)）")
            } else if hasFeedbackEvents {
                print("📊 [BehaviorEventQueue] 队列含反馈类事件，触发上报（queueSize=\(queue.count)）")
            } else if hasTemplateEvents {
                print("📊 [BehaviorEventQueue] 队列含模板类事件，触发上报（queueSize=\(queue.count)）")
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
        let auth = await AuthRepository.shared.getCurrentAuthInfo()
        let userId: Int64? = (auth?.userid).flatMap { Int64($0) }
        let deviceId = await DeviceManager.shared.getDeviceId()
        let appVersion = await DeviceManager.shared.getAppVersion()

        print("📊 [BehaviorEventQueue] 开始上报: batchSize=\(batch.count), channelId=\(channelId), userId=\(userId ?? 0), deviceId=\(deviceId)")
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
}
