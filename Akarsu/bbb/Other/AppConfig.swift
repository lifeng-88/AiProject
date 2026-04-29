//
//  AppConfig.swift
//  bbb
//

import Foundation

final class AppConfig: @unchecked Sendable {
    static let shared = AppConfig()

    private static let channelKey = "ChannelId"

    private init() {}

    func getChannel() async -> String {
        if let v = Bundle.main.object(forInfoDictionaryKey: Self.channelKey) as? String {
            let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty, !(t.hasPrefix("$(") && t.hasSuffix(")")) { return t }
        }
        return "IOS10052"
    }
}
