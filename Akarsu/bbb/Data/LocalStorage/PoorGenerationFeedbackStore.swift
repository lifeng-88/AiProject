//
//  PoorGenerationFeedbackStore.swift
//  glam
//
//  本地缓存「已提交过对生成效果不满意反馈」的 taskId 集合，用于客户端判断是否展示「Unsatisfied」入口（每个生成结果仅允许一次）。
//

import Combine
import Foundation

/// 已提交 poor_generation_result 反馈的 taskId 本地缓存
final class PoorGenerationFeedbackStore {
    static let shared = PoorGenerationFeedbackStore()

    private let key = "glam.poor_generation_feedback_task_ids"
    private let userDefaults = UserDefaults.standard

    private init() {}

    /// 标记该 taskId 已提交过不满意反馈
    func markTaskAsSubmitted(taskId: String) {
        guard !taskId.isEmpty else { return }
        var set = loadSet()
        set.insert(taskId)
        saveSet(set)
    }

    /// 标记该 taskId 已提交（Int64 重载）
    func markTaskAsSubmitted(taskId: Int64) {
        markTaskAsSubmitted(taskId: String(taskId))
    }

    /// 是否已对该 taskId 提交过不满意反馈
    func hasSubmittedForTask(taskId: String) -> Bool {
        guard !taskId.isEmpty else { return false }
        return loadSet().contains(taskId)
    }

    /// 是否已对该 taskId 提交过（Int64 重载）
    func hasSubmittedForTask(taskId: Int64) -> Bool {
        hasSubmittedForTask(taskId: String(taskId))
    }

    /// 将反馈列表里属于 poor_generation_result 且带 task_id 的项并入本地缓存（用于与接口拉齐）
    func mergeFromFeedbackItems(_ items: [FeedbackItem]) {
        let ids = items
            .filter { $0.category == "poor_generation_result" }
            .compactMap { $0.taskId }
            .map { String($0) }
            .filter { !$0.isEmpty }
        guard !ids.isEmpty else { return }
        var set = loadSet()
        for id in ids { set.insert(id) }
        saveSet(set)
    }

    private func loadSet() -> Set<String> {
        guard let data = userDefaults.data(forKey: key),
              let arr = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(arr)
    }

    private func saveSet(_ set: Set<String>) {
        let arr = Array(set)
        guard let data = try? JSONEncoder().encode(arr) else { return }
        userDefaults.set(data, forKey: key)
    }
}
