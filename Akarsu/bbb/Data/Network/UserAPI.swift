//
//  UserAPI.swift
//  glam
//
//  Created by Dev on 2026/1/19.
//

import Foundation

/// 用户余额响应模型
struct UserGoldResponse: Codable {
    let balance: String
    
    enum CodingKeys: String, CodingKey {
        case balance
    }
}

/// 金币交易记录
struct GoldTransaction: Codable, Identifiable {
    let type: Int32
    let amount: String
    let createTs: String
    
    /// 唯一标识符（使用创建时间戳）
    var id: String {
        createTs
    }
    
    /// 交易类型名称
    var typeName: String {
        switch type {
        case 1: return "Recharge"
        case 2: return "Refund"
        case 3: return "Official Gift"
        case 4: return "Spend"
        case 5: return "Official Deduction"
        default: return "Unknown"
        }
    }
    
    /// 是否为收入（1: Recharge, 2: Refund, 3: Official Gift 为收入；4: Spend, 5: Official Deduction 为支出）
    var isIncome: Bool {
        return type == 1 || type == 2 || type == 3
    }
    
    /// 格式化金额
    var formattedAmount: String {
        guard let amountInt = Int64(amount) else {
            return amount
        }
        // 假设金额单位是金币的最小单位，显示时需要转换为金币
        // 如果 1 金币 = 100 最小单位，则需要除以 100
        // 这里假设金额就是金币数，直接显示
        return String(amountInt)
    }
    
    /// 格式化金额（带符号，如果已经是负数，不再加负号）
    var formattedAmountWithSign: String {
        guard let amountInt = Int64(amount) else {
            return amount
        }
        // 如果金额已经是负数，直接显示（不再加负号）
        if amountInt < 0 {
            return String(amountInt)
        }
        // 如果是正数，根据 isIncome 添加符号
        return (isIncome ? "+" : "-") + String(amountInt)
    }
    
    /// 格式化时间
    var formattedTime: String {
        guard let timestamp = Int64(createTs) else {
            return createTs
        }
        // 时间戳可能是毫秒或秒，需要判断
        let timeInterval: TimeInterval
        if timestamp > 1_000_000_000_000 {
            // 毫秒时间戳（13位数字）
            timeInterval = TimeInterval(timestamp / 1000)
        } else {
            // 秒时间戳（10位数字）
            timeInterval = TimeInterval(timestamp)
        }
        let date = Date(timeIntervalSince1970: timeInterval)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }
}

/// 金币交易记录列表响应（支持分页）
struct ListGoldTransactionsResponse: Codable {
    let list: [GoldTransaction]
    let nextPageToken: String?
    
    enum CodingKeys: String, CodingKey {
        case list
        case nextPageToken  // 服务端实际返回 camelCase
    }
}

/// 用户相关 API
struct UserAPI {
    static let client = APIClient.shared
    
    /// 获取用户余额
    /// - Parameter userid: 用户ID
    /// - Returns: 余额响应
    static func getUserGold(userid: String) async -> Result<UserGoldResponse, AppError> {
        return await client.request(
            "/v1/users/\(userid)/gold",
            method: .get
        )
    }
    
    /// 获取用户金币交易记录（支持分页）
    /// - Parameters:
    ///   - userid: 用户ID
    ///   - pageToken: 分页游标，首次不传
    ///   - pageSize: 每页条数，默认 20
    static func getGoldTransactions(userid: String, pageToken: String? = nil, pageSize: Int32 = 20) async -> Result<ListGoldTransactionsResponse, AppError> {
        var parameters: [String: Any] = ["pageSize": pageSize]
        if let token = pageToken, !token.isEmpty {
            parameters["pageToken"] = token
        }
        return await client.request(
            "/v1/users/\(userid)/gold/trans",
            method: .get,
            parameters: parameters
        )
    }
}
