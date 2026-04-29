//
//  FeedbackModels.swift
//  glam
//
//  User feedback entities (PRD §10.4, user-feedback-api 2.1–2.3).
//

import Foundation

// MARK: - Category (API enum values)

enum FeedbackCategory: String, CaseIterable {
    case aiGenerationQuality = "ai_generation_quality"
    case poorGenerationResult = "poor_generation_result"
    case paymentIssue = "payment_issue"
    case appBug = "app_bug"
    case other = "other"

    var displayName: String {
        switch self {
        case .aiGenerationQuality: return AppLanguageStore.localized("feedback.category.ai_generation_quality")
        case .poorGenerationResult: return AppLanguageStore.localized("feedback.category.poor_generation_result")
        case .paymentIssue: return AppLanguageStore.localized("feedback.category.payment_issue")
        case .appBug: return AppLanguageStore.localized("feedback.category.app_bug")
        case .other: return AppLanguageStore.localized("feedback.category.other")
        }
    }

    /// For SwiftUI Text rendering with environment locale.
    var displayNameKey: String {
        switch self {
        case .aiGenerationQuality: return "feedback.category.ai_generation_quality"
        case .poorGenerationResult: return "feedback.category.poor_generation_result"
        case .paymentIssue: return "feedback.category.payment_issue"
        case .appBug: return "feedback.category.app_bug"
        case .other: return "feedback.category.other"
        }
    }

    var sfSymbolName: String {
        switch self {
        case .aiGenerationQuality: return "wand.and.stars"
        case .poorGenerationResult: return "exclamationmark.triangle"
        case .paymentIssue: return "creditcard"
        case .appBug: return "ladybug"
        case .other: return "ellipsis"
        }
    }
}

// MARK: - Status (API enum values)

enum FeedbackStatus: String, Codable {
    case pending
    case inProgress = "in_progress"
    case resolved
    case rewarded
}

// MARK: - Create Feedback Request (API: POST /v1/feedback)

struct CreateFeedbackRequest: Encodable {
    let category: String
    let details: String
    let title: String?
    let taskId: Int64?
    let actualSpentAmount: Int64?
    /// 渠道 ID，与 AppConfig 一致（如 IOS10052），与接口文档 channel_id 对应；未传或为空时 BFF 使用默认值
    let channelId: String?

    enum CodingKeys: String, CodingKey {
        case category, details, title
        case taskId = "task_id"
        case actualSpentAmount = "actual_spent_amount"
        case channelId = "channel_id"
    }

    func toParameters() -> [String: Any] {
        var params: [String: Any] = [
            "category": category,
            "details": details
        ]
        if let t = title, !t.isEmpty { params["title"] = t }
        if let tid = taskId, tid > 0 { params["task_id"] = tid }
        if let amt = actualSpentAmount, amt >= 0 { params["actual_spent_amount"] = amt }
        if let ch = channelId, !ch.isEmpty { params["channel_id"] = ch }
        return params
    }
}

// MARK: - Create Feedback Response

struct CreateFeedbackResponse: Decodable {
    let id: Int64
    let createdAt: Int64

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case created_at
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // 服务端可能返回 id 为字符串 "1" 或数字，兼容两种格式
        id = try Self.decodeInt64(from: c, keys: [.id])
        // 服务端可能返回 "createdAt" 或 "created_at"，且可能是字符串
        createdAt = try Self.decodeInt64(from: c, keys: [.createdAt, .created_at])
    }

    init(id: Int64, createdAt: Int64) {
        self.id = id
        self.createdAt = createdAt
    }

    private static func decodeInt64(from c: KeyedDecodingContainer<CodingKeys>, keys: [CodingKeys]) throws -> Int64 {
        for key in keys {
            if let v = try? c.decode(Int64.self, forKey: key) { return v }
            if let s = try? c.decode(String.self, forKey: key), let v = Int64(s) { return v }
        }
        throw DecodingError.keyNotFound(keys[0], DecodingError.Context(codingPath: c.codingPath, debugDescription: "Expected one of \(keys) as Int64 or numeric String"))
    }
}

// MARK: - Feedback List Item (API: items[] in GET /v1/feedbacks)

struct FeedbackItem: Identifiable, Decodable, Equatable {
    let id: Int64
    let channelId: String?
    let category: String
    let title: String
    let details: String
    let userId: Int64?
    let status: String
    let supportResponse: String?
    let rewardCoins: Int32
    let taskId: Int64?
    let actualSpentAmount: Int64?
    let createdAt: Int64
    let updatedAt: Int64?

    enum CodingKeys: String, CodingKey {
        case id, category, title, details, status, channelId, userId, supportResponse, rewardCoins, taskId, actualSpentAmount, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try FeedbackItem.decodeInt64(from: c, key: .id)
        channelId = try c.decodeIfPresent(String.self, forKey: .channelId)
        category = try c.decode(String.self, forKey: .category)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        details = try c.decodeIfPresent(String.self, forKey: .details) ?? ""
        userId = try FeedbackItem.decodeInt64Optional(from: c, key: .userId)
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "pending"
        supportResponse = try c.decodeIfPresent(String.self, forKey: .supportResponse)
        rewardCoins = try FeedbackItem.decodeInt32(from: c, key: .rewardCoins)
        taskId = try FeedbackItem.decodeInt64Optional(from: c, key: .taskId)
        actualSpentAmount = try FeedbackItem.decodeInt64Optional(from: c, key: .actualSpentAmount)
        createdAt = try FeedbackItem.decodeInt64(from: c, key: .createdAt)
        updatedAt = try FeedbackItem.decodeInt64Optional(from: c, key: .updatedAt)
    }

    private static func decodeInt64(from c: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) throws -> Int64 {
        if let v = try? c.decode(Int64.self, forKey: key) { return v }
        if let s = try? c.decode(String.self, forKey: key), let v = Int64(s) { return v }
        throw DecodingError.typeMismatch(Int64.self, DecodingError.Context(codingPath: c.codingPath + [key], debugDescription: "Expected Int64 or numeric String for \(key)"))
    }

    private static func decodeInt64Optional(from c: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) throws -> Int64? {
        guard c.contains(key) else { return nil }
        if let v = try? c.decode(Int64.self, forKey: key) { return v }
        if let s = try? c.decode(String.self, forKey: key), let v = Int64(s) { return v }
        return nil
    }

    private static func decodeInt32(from c: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) throws -> Int32 {
        if let v = try? c.decode(Int32.self, forKey: key) { return v }
        if let s = try? c.decode(String.self, forKey: key), let v = Int32(s) { return v }
        return 0
    }

    var categoryDisplayName: String {
        FeedbackCategory(rawValue: category)?.displayName ?? category
    }

    var submittedAtText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let date = Date(timeIntervalSince1970: TimeInterval(createdAt))
        return "Submitted on \(formatter.string(from: date))"
    }
}

// MARK: - List Feedbacks Response

struct ListFeedbacksResponse: Decodable {
    let items: [FeedbackItem]
    let nextPageToken: String?

    enum CodingKeys: String, CodingKey {
        case items
        case nextPageToken = "next_page_token"
    }
}
