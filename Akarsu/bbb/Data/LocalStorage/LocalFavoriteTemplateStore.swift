//
//  LocalFavoriteTemplateStore.swift
//  bbb
//
//  首页模板「爱心」收藏状态本地缓存（与 `HomeFeedItem.likeStateKey` 一致：`t1|t2|t3:templateId`）
//

import Foundation

extension Notification.Name {
    /// 本地收藏键集合变更（首页爱心、My Likes 移除等）
    static let localFavoriteTemplateStoreDidChange = Notification.Name("bbb.LocalFavoriteTemplateStore.didChange")
}

/// 单条收藏（由 `likeStateKey` 解析，供「My Likes」列表展示）
struct LocalFavoriteEntry: Identifiable, Hashable {
    let likeStateKey: String
    let kind: TemplateResourceKind
    let templateId: String
    var id: String { likeStateKey }
}

/// 按当前用户分桶持久化；未登录时使用 `anonymous` 桶（仅本机）。
enum LocalFavoriteTemplateStore {
    private static let defaults = UserDefaults.standard
    private static let prefix = "bbb.favorite.templateKeys.v1."

    private static func bucketId(userId: String?) -> String {
        let raw = userId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? "anonymous" : raw
    }

    private static func storageKey(userId: String?) -> String {
        prefix + bucketId(userId: userId)
    }

    /// 读取本地已收藏键集合
    static func load(userId: String?) -> Set<String> {
        let key = storageKey(userId: userId)
        guard let data = defaults.data(forKey: key),
              let arr = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(arr)
    }

    /// 覆盖保存（首页 `likedTemplateKeys` 全量写入 `UserDefaults`，点击爱心后立即调用）
    static func save(_ keys: Set<String>, userId: String?) {
        let key = storageKey(userId: userId)
        let sorted = Array(keys).sorted()
        if let data = try? JSONEncoder().encode(sorted) {
            defaults.set(data, forKey: key)
            NotificationCenter.default.post(name: .localFavoriteTemplateStoreDidChange, object: nil)
        }
    }

    /// 本地收藏条数（Profile 角标与「My Likes」一致）
    static func favoriteCount(forUserId userId: String?) -> Int {
        load(userId: userId).count
    }

    /// 解析为列表项（仅本地键，不请求网络）
    static func favoriteEntries(forUserId userId: String?) -> [LocalFavoriteEntry] {
        entries(from: load(userId: userId))
    }

    static func entries(from keys: Set<String>) -> [LocalFavoriteEntry] {
        keys.compactMap { parseKey($0) }
            .sorted { lhs, rhs in
                if lhs.kind != rhs.kind { return lhs.kind.rawValue < rhs.kind.rawValue }
                return lhs.templateId < rhs.templateId
            }
    }

    private static func parseKey(_ key: String) -> LocalFavoriteEntry? {
        let parts = key.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let kindStr = String(parts[0])
        let tid = String(parts[1])
        guard !tid.isEmpty, let kind = TemplateResourceKind(rawValue: kindStr) else { return nil }
        return LocalFavoriteEntry(likeStateKey: key, kind: kind, templateId: tid)
    }
}
