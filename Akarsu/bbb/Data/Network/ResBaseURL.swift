//
//  ResBaseURL.swift
//  glam
//
//  静态资源基地址：Privacy Policy、Terms & Conditions 等 H5 页。默认 http://127.0.0.1。
//

import Combine
import Foundation

enum ResBaseURL {
    private static let infoKey = "ResBaseURL"
    
    /// 当前生效的资源基地址
    /// 优先级：Info.plist(ResBaseURL) > 默认值
    static var effective: String {
        if let value = Bundle.main.object(forInfoDictionaryKey: infoKey) as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, !(trimmed.hasPrefix("$(") && trimmed.hasSuffix(")")) {
                return trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
            }
        }
//        return "https://res.musefit.it.com"//10002渠道
//        return "https://res.glamai01.it.com"
        return "https://res.goddess.xin";
    }

    /// Privacy Policy 页面 URL（H5，固定链接）
    static var privacyPolicyURL: URL {
        URL(string: "https://res.goddess.xin/akarsu/akarsu-privacy.html")!
    }

    /// 用户协议页面 URL（H5，固定链接）
    static var termsAndConditionsURL: URL {
        URL(string: "https://res.goddess.xin/akarsu/akarsu-user-agreement.html")!
    }
}
