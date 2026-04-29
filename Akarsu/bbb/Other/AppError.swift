//
//  AppError.swift
//  bbb
//

import Foundation

enum AppError: Error, LocalizedError, Equatable {
    case unauthorized
    case notFound
    case invalidResponse
    case networkError(String)
    case serverError(code: Int, message: String)
    case decodingError(String)
    case encodingError(String)
    case storageError(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Unauthorized"
        case .notFound:
            return "Not found"
        case .invalidResponse:
            return "Invalid response"
        case .networkError(let msg):
            return msg
        case .serverError(_, let message):
            return message.isEmpty ? "Server error" : message
        case .decodingError(let msg):
            return msg
        case .encodingError(let msg):
            return msg
        case .storageError(let msg):
            return msg
        }
    }

    /// 供 UI / 轮询等展示用的简短说明（非网络/服务端分支时的兜底）。
    var userMessage: String {
        errorDescription ?? "Error"
    }
}

extension AppError {
    /// 与 `RechargeOrderVerification` 及 IAP 确认失败分支对齐：服务端表示「订单已存在」时视为重复单。
    var isOrderDuplicateError: Bool {
        switch self {
        case .serverError(_, let message):
            return RechargeOrderVerification.isDuplicateOrderSuccess(message)
        default:
            return false
        }
    }
}
