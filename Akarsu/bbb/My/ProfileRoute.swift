//
//  ProfileRoute.swift
//  bbb
//

import SwiftUI

enum ProfileRoute: Hashable {
    case creations
    case rechargeRecord
    case likes
    case settings
    case userAgreement
    case privacy
    case feedback
    /// 远程推送 `feedback_reply`：直达历史列表，可选滚动到 `feedback_id` 对应条目
    case feedbackHistory(focusFeedbackId: Int64?)
}

struct ProfileRouteDestination: View {
    let route: ProfileRoute
    @EnvironmentObject private var wallet: UserWalletStore

    var body: some View {
        switch route {
        case .creations:
            MyCreationsView()
        case .rechargeRecord:
            RechargeRecordListView()
        case .likes:
            MyLikesView()
        case .settings:
            ProfileSettingsView()
        case .userAgreement:
            LegalH5DocumentView(url: ResBaseURL.termsAndConditionsURL, titleLocalizationKey: "legal.user_agreement")
        case .privacy:
            LegalH5DocumentView(url: ResBaseURL.privacyPolicyURL, titleLocalizationKey: "legal.privacy")
        case .feedback:
            FeedbackCenterView()
        case .feedbackHistory(let focusId):
            FeedbackHistoryView(focusFeedbackId: focusId)
        }
    }
}
