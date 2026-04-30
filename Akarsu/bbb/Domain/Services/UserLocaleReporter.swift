//
//  UserLocaleReporter.swift
//  bbb
//
//  POST /v1/users/{userid}/locale：已登录时上报界面语言与时区（与 glam 一致）。
//

import Foundation

enum UserLocaleReporter {
    /// 若本地存在会话则上报；网络在后台执行，勿阻塞 UI。
    /// - Parameter reason: 便于在控制台过滤，如 `cold_start_existing_session`、`after_login`、`language_changed`。
    static func reportIfAuthenticated(reason: String = "default") async {
        guard let auth = await AuthRepository.shared.getCurrentAuthInfo() else {
            print("🌐 [UserLocaleReporter] ⏭️ skip — 无登录会话 | reason=\(reason)")
            return
        }
        let language = AppLanguageStore.localeCodeForUserLocaleAPIReporting()
        let timeZoneId = TimeZone.current.identifier
        let uidShort = auth.userid.count > 4 ? "\(auth.userid.prefix(4))…" : auth.userid
        print("🌐 [UserLocaleReporter] ▶️ POST /v1/users/{userid}/locale | reason=\(reason) | userid=\(uidShort) | language=\(language) | timeZone=\(timeZoneId)")

        let result = await UserAPI.reportUserLocale(userid: auth.userid, language: language, timeZone: timeZoneId)
        switch result {
        case .success(let reply):
            if reply.ok {
                print("🌐 [UserLocaleReporter] ✅ success | reason=\(reason) | server ok=true | language=\(language) | timeZone=\(timeZoneId)")
            } else {
                print("🌐 [UserLocaleReporter] ⚠️ HTTP 200 但 ok=false | reason=\(reason) | language=\(language) | timeZone=\(timeZoneId)")
            }
        case .failure(let error):
            let detail: String
            switch error {
            case .serverError(let code, let message):
                detail = "code=\(code) message=\(message)"
            case .unauthorized:
                detail = "unauthorized(401)"
            case .networkError(let msg):
                detail = "network: \(msg)"
            case .decodingError(let msg):
                detail = "decoding: \(msg)"
            default:
                detail = error.localizedDescription
            }
            print("🌐 [UserLocaleReporter] ❌ failed | reason=\(reason) | \(detail)")
        }
    }
}
