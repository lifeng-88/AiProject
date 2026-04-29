//
//  RedirectPaymentInfoStore.swift
//  glam
//
//  本地存储重定向支付信息（First Name、Last Name、Phone 等），用于「记住支付信息」功能
//

import Foundation

struct RedirectPaymentInfo: Codable {
    var firstName: String
    var lastName: String
    var phoneNumber: String
    var phoneCountryCode: String
}

actor RedirectPaymentInfoStore {
    static let shared = RedirectPaymentInfoStore()

    private let key = "redirect_payment_info"

    private init() {}

    func load() -> RedirectPaymentInfo? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let info = try? JSONDecoder().decode(RedirectPaymentInfo.self, from: data) else {
            return nil
        }
        return info
    }

    func save(_ info: RedirectPaymentInfo) {
        guard let data = try? JSONEncoder().encode(info) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
