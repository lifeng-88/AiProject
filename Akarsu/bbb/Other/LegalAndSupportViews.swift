//
//  LegalAndSupportViews.swift
//  bbb
//
//  参考: unified_user_agreement, unified_privacy_policy, refined_feedback_center_no_upload
//

import SwiftUI
import WebKit

// MARK: - H5（我的页 Push：用户协议 / 隐私政策）

/// 使用 `ResBaseURL` 配置的 H5 地址，在导航栈内全屏展示（`WKWebView`）。
struct LegalH5DocumentView: View {
    let url: URL
    let titleLocalizationKey: String
    @State private var isLoading = true

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            LegalDocumentWebViewRepresentable(url: url, isLoading: $isLoading)
            if isLoading {
                ProgressView()
                    .tint(AppTheme.primary)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(AppLanguageStore.localized(titleLocalizationKey))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(AppTheme.primary)
            }
        }
        .bbbNavigationBarBackground(AppTheme.background)
        .bbbRefreshOnAppLanguage()
    }
}

private struct LegalDocumentWebViewRepresentable: UIViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isLoading: $isLoading)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.allowsBackForwardNavigationGestures = true
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.loadedURL != url {
            context.coordinator.loadedURL = url
            isLoading = true
            webView.load(URLRequest(url: url))
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var isLoading: Binding<Bool>
        var loadedURL: URL?

        init(isLoading: Binding<Bool>) {
            self.isLoading = isLoading
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            isLoading.wrappedValue = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoading.wrappedValue = false
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            isLoading.wrappedValue = false
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            isLoading.wrappedValue = false
        }
    }
}

/// 设计稿：Legal Center — 顶栏标题、版本胶囊、分节条款（紫标 + 正文）
struct UserAgreementView: View {
    private var versionBadgeText: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        return String(format: AppLanguageStore.localized("legal.version_format"), v)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                versionPill
                    .padding(.top, 8)

                Text(AppLanguageStore.localized("legal.user_agreement"))
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color.white)
                    .padding(.top, 20)

                Text(AppLanguageStore.localized("legal.ua.lead"))
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.onSurfaceVariant)
                .lineSpacing(5)
                .padding(.top, 12)

                VStack(alignment: .leading, spacing: 28) {
                    legalSection(
                        number: "1",
                        title: "ACCEPTANCE OF TERMS",
                        body: """
                        By accessing or using services provided by Sovereign AI Systems, you agree to be bound by these terms. \
                        If you do not agree, do not use the service. We may modify these terms at any time; continued use after \
                        changes constitutes acceptance of the updated terms.
                        """
                    )

                    legalSection(
                        number: "2",
                        title: "SERVICE DESCRIPTION",
                        body: """
                        The service provides access to generative AI tools for data analysis, creative synthesis, and predictive modeling. \
                        Output means any content generated through the service. AI-generated content may be inaccurate, incomplete, \
                        or biased; you are responsible for how you use outputs.
                        """
                    )

                    conductSection

                    legalSection(
                        number: "4",
                        title: "INTELLECTUAL PROPERTY",
                        body: """
                        You retain ownership of your inputs. Subject to your compliance with these terms, Sovereign AI assigns rights \
                        in the Output to you as permitted by applicable law. We may use inputs and outputs in de-identified form to \
                        improve safety, quality, and the service.
                        """
                    )

                    legalSection(
                        number: "5",
                        title: "LIMITATION OF LIABILITY",
                        body: """
                        To the maximum extent permitted by law, Sovereign AI shall not be liable for any indirect, incidental, special, \
                        consequential, or punitive damages, or any loss of data, profits, or goodwill arising from your use of the service.
                        """
                    )
                }
                .padding(.top, 28)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.bottom, 36)
        }
        .bbbScrollIndicatorsHidden()
        .background(legalCenterBackground.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(AppLanguageStore.localized("legal.center"))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(AppTheme.primary)
            }
        }
        .bbbNavigationBarBackground(AppTheme.background)
        .bbbRefreshOnAppLanguage()
    }

    private var legalCenterBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 11 / 255, green: 11 / 255, blue: 21 / 255),
                AppTheme.background,
                Color(red: 18 / 255, green: 12 / 255, blue: 32 / 255)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var versionPill: some View {
        BBBTrackedText.text(versionBadgeText, size: 10, weight: .heavy, tracking: 1.0, color: AppTheme.onSurfaceVariant)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(AppTheme.surfaceContainerHigh.opacity(0.95))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(AppTheme.outlineVariant.opacity(0.25), lineWidth: 1)
            )
    }

    private func legalSection(number: String, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(AppTheme.primary)
                    .frame(width: 32, height: 3)
                BBBTrackedText.text("\(number). \(title)", size: 12, weight: .heavy, tracking: 0.6, color: AppTheme.primary)
            }
            Text(body.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.onSurfaceVariant)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var conductSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(AppTheme.primary)
                    .frame(width: 32, height: 3)
                BBBTrackedText.text("3. USER CONDUCT", size: 12, weight: .heavy, tracking: 0.6, color: AppTheme.primary)
            }

            VStack(alignment: .leading, spacing: 14) {
                conductRow(
                    icon: "square.grid.2x2.fill",
                    text: "Reverse-engineering the models or extracting training data without authorization."
                )
                conductRow(
                    icon: "slash.circle.fill",
                    text: "Generating content that promotes illegal acts, hate speech, harassment, or non-consensual deepfakes."
                )
                conductRow(
                    icon: "key.fill",
                    text: "Circumventing safety filters, abuse detection, or rate limits."
                )
            }
        }
    }

    private func conductRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(AppTheme.primary.opacity(0.95))
                .frame(width: 22, alignment: .center)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.onSurfaceVariant)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// 设计稿：Legal Center — Privacy Policy（LAST UPDATED 胶囊、SECTION 分节、勾选列表、咨询邮箱）
struct PrivacyPolicyView: View {
    private var lastUpdatedBadge: String {
        AppLanguageStore.localized("legal.privacy.last_updated")
    }

    private let privacyEmail = "privacy@ai-sovereign.io"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                lastUpdatedPill
                    .padding(.top, 8)

                Text(AppLanguageStore.localized("legal.privacy"))
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color.white)
                    .padding(.top, 20)

                Text(AppLanguageStore.localized("legal.privacy.lead"))
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.onSurfaceVariant)
                .lineSpacing(5)
                .padding(.top, 12)

                VStack(alignment: .leading, spacing: 28) {
                    privacySection(
                        section: "01",
                        heading: "Information Collection",
                        content: .paragraphs([
                            """
                            We collect information you provide directly—such as account details, uploaded content, \
                            and communications with support—as well as technical data generated when you use our services, \
                            including device identifiers, log data, and usage analytics.
                            """,
                            """
                            Where permitted by law, we may combine this information to operate, secure, and improve the \
                            Sovereign AI platform and to personalize your experience.
                            """
                        ])
                    )

                    privacySection(
                        section: "02",
                        heading: "Use of Information",
                        content: .bullets(intro: """
                            We use personal information for the following purposes, consistent with applicable law and \
                            the choices you have made:
                            """,
                            items: [
                                "Tailoring AI responses and recommendations to your preferences and context.",
                                "Detecting and preventing fraudulent activity, abuse, and security incidents.",
                                "Communicating critical security updates, service changes, and optional product news."
                            ])
                    )

                    privacySection(
                        section: "03",
                        heading: "Data Security",
                        content: .paragraphs([
                            """
                            We implement administrative, technical, and organizational safeguards designed to protect your data. \
                            Sensitive data is encrypted at rest using industry-standard algorithms such as AES-256, and data in \
                            transit is protected with TLS 1.3 where supported by your client and our infrastructure.
                            """,
                            """
                            No method of transmission or storage is completely secure; we continuously review and update our \
                            practices as threats evolve.
                            """
                        ])
                    )

                    privacySection(
                        section: "04",
                        heading: "Third-Party Disclosure",
                        content: .paragraphs([
                            """
                            We do not sell your personal information. We may share data with vetted service providers who \
                            assist us in hosting, analytics, payment processing, or customer support, subject to contractual \
                            obligations to use data only as instructed and to protect it appropriately.
                            """
                        ])
                    )

                    privacySection(
                        section: "05",
                        heading: "User Rights",
                        content: .paragraphs([
                            """
                            Depending on your jurisdiction, you may have the right to access, correct, delete, or export your \
                            personal data, and to object to or restrict certain processing. You may exercise these rights by \
                            contacting us using the inquiries channel below.
                            """
                        ])
                    )

                    inquiriesFooter
                }
                .padding(.top, 28)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .bbbScrollIndicatorsHidden()
        .background(privacyPolicyBackground.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(AppLanguageStore.localized("legal.center"))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(AppTheme.primary)
            }
        }
        .bbbNavigationBarBackground(AppTheme.background)
        .bbbRefreshOnAppLanguage()
    }

    private var privacyPolicyBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 11 / 255, green: 11 / 255, blue: 21 / 255),
                AppTheme.background,
                Color(red: 18 / 255, green: 12 / 255, blue: 32 / 255)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var lastUpdatedPill: some View {
        BBBTrackedText.text(lastUpdatedBadge, size: 9, weight: .heavy, tracking: 0.8, color: AppTheme.onSurface.opacity(0.88))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(AppTheme.surfaceContainerHigh.opacity(0.95))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(AppTheme.outlineVariant.opacity(0.25), lineWidth: 1)
            )
    }

    private enum PrivacySectionContent {
        case paragraphs([String])
        case bullets(intro: String, items: [String])
    }

    private func privacySection(section: String, heading: String, content: PrivacySectionContent) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            BBBTrackedText.text(String(format: AppLanguageStore.localized("legal.section_prefix"), section), size: 10, weight: .heavy, tracking: 1.0, color: AppTheme.primary)

            Text(heading)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.white)

            switch content {
            case .paragraphs(let paras):
                ForEach(Array(paras.enumerated()), id: \.offset) { _, p in
                    Text(p.trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.onSurfaceVariant)
                        .lineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)
                }
            case .bullets(let intro, let items):
                Text(intro.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.onSurfaceVariant)
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        privacyCheckBullet(text: item)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private func privacyCheckBullet(text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(AppTheme.primary)
                    .frame(width: 22, height: 22)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.onSurfaceVariant)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var inquiriesFooter: some View {
        VStack(alignment: .leading, spacing: 10) {
            BBBTrackedText.text(AppLanguageStore.localized("legal.inquiries"), size: 10, weight: .heavy, tracking: 1.2, color: AppTheme.onSurfaceVariant.opacity(0.85))

            if let url = URL(string: "mailto:\(privacyEmail)") {
                Link(destination: url) {
                    Text(privacyEmail)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.primary)
                }
            } else {
                Text(privacyEmail)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.primary)
            }
        }
        .padding(.top, 8)
    }
}

private struct FeedbackScrollDismissesKeyboardModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.scrollDismissesKeyboard(.immediately)
        } else {
            content
        }
    }
}

/// 设计稿：Refined Feedback Center (No Upload) — 金标分区、3+2 分类芯片、字数统计、渐变胶囊提交、历史入口。
struct FeedbackCenterView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var selectedCategory: FeedbackCategory = .aiGenerationQuality
    @State private var message = ""
    @State private var isSubmitting = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var dismissAfterConfirm = false
    @FocusState private var isDescriptionFocused: Bool

    private static let maxDetailLength = 500

    private var trimmedContent: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        !trimmedContent.isEmpty && !isSubmitting
    }

    /// 设计图首行 3 个、次行 2 个芯片。
    private var categoryRowLeading: [FeedbackCategory] {
        [.appBug, .poorGenerationResult, .paymentIssue]
    }

    private var categoryRowSecond: [FeedbackCategory] {
        [.aiGenerationQuality, .other]
    }

    private var submitBarGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 120 / 255, green: 72 / 255, blue: 200 / 255),
                Color(red: 170 / 255, green: 130 / 255, blue: 245 / 255)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    /// 按钮上深色紫字（设计稿：深紫 sans-serif on 浅紫渐变条）。
    private var submitTitleColor: Color {
        Color(red: 42 / 255, green: 18 / 255, blue: 72 / 255)
    }

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(AppLanguageStore.localized("feedback.subtitle"))
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(Color.white)
                        Text(AppLanguageStore.localized("feedback.body"))
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(AppTheme.onSurfaceVariant)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismissFeedbackKeyboard()
                    }

                    goldSectionTitle(AppLanguageStore.localized("feedback.section.category"))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            dismissFeedbackKeyboard()
                        }
                    VStack(spacing: 10) {
                        HStack(spacing: 10) {
                            ForEach(categoryRowLeading, id: \.rawValue) { cat in
                                categoryChip(cat)
                            }
                        }
                        HStack(spacing: 10) {
                            ForEach(categoryRowSecond, id: \.rawValue) { cat in
                                categoryChip(cat)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismissFeedbackKeyboard()
                    }

                    goldSectionTitle(AppLanguageStore.localized("feedback.section.description"))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            dismissFeedbackKeyboard()
                        }
                    issueDescriptionBlock

                    submitButton

                    NavigationLink {
                        FeedbackHistoryView(focusFeedbackId: nil)
                    } label: {
                        BBBTrackedText.text(AppLanguageStore.localized("feedback.view_history"), size: 11, weight: .semibold, tracking: 1.2, color: Color.white.opacity(0.92), serif: true)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)

                    Color.clear
                        .frame(minHeight: 160)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            dismissFeedbackKeyboard()
                        }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .modifier(FeedbackScrollDismissesKeyboardModifier())
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(AppLanguageStore.localized("feedback.nav_title"))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(AppTheme.primary)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(AppLanguageStore.localized("common.ok")) {
                    dismissFeedbackKeyboard()
                }
                .font(.system(size: 17, weight: .semibold))
            }
        }
        .bbbNavigationBarBackground(AppTheme.background)
        .tint(AppTheme.primary)
        .onChange(of: message) { newValue in
            if newValue.count > Self.maxDetailLength {
                message = String(newValue.prefix(Self.maxDetailLength))
            }
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button(AppLanguageStore.localized("common.ok"), role: .cancel) {
                if dismissAfterConfirm {
                    dismiss()
                }
            }
        } message: {
            Text(alertMessage)
        }
        .bbbRefreshOnAppLanguage()
    }

    private func goldSectionTitle(_ text: String) -> some View {
        BBBTrackedText.text(text.uppercased(), size: 11, weight: .semibold, tracking: 1.6, color: AppTheme.secondary, serif: true)
    }

    private func categoryChip(_ cat: FeedbackCategory) -> some View {
        let selected = selectedCategory == cat
        let chipShape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return Button {
            selectedCategory = cat
        } label: {
            Text(Self.designChipLabel(cat))
                .font(.system(size: 12, weight: .medium))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.75)
                .lineLimit(2)
                .foregroundStyle(selected ? AppTheme.primary : AppTheme.onSurfaceVariant.opacity(0.72))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 14)
                .padding(.horizontal, 6)
                .background(
                    ZStack {
                        chipShape.fill(Color.clear)
                        chipShape.stroke(selected ? AppTheme.primary.opacity(0.9) : AppTheme.outlineVariant.opacity(0.5), lineWidth: 1)
                    }
                )
                .contentShape(chipShape)
        }
        .buttonStyle(.plain)
        .disabled(isSubmitting)
    }

    private var issueDescriptionBlock: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $message)
                    .bbbListScrollContentHidden()
                    .focused($isDescriptionFocused)
                    .padding(12)
                    .padding(.bottom, 28)
                    .frame(minHeight: 188)
                    .foregroundStyle(AppTheme.onSurface)
                    .disabled(isSubmitting)

                if message.isEmpty {
                    Text(AppLanguageStore.localized("feedback.placeholder"))
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.onSurfaceVariant.opacity(0.45))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }

            Text(String(format: AppLanguageStore.localized("feedback.char_count"), message.count, Self.maxDetailLength))
                .font(.system(size: 11, weight: .regular, design: .serif))
                .foregroundStyle(AppTheme.outlineVariant.opacity(0.85))
                .padding(12)
                .contentShape(Rectangle())
                .onTapGesture {
                    dismissFeedbackKeyboard()
                }
        }
        .background(AppTheme.surfaceContainerLow)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.outlineVariant.opacity(0.35), lineWidth: 1)
        )
    }

    private var submitButton: some View {
        Button {
            guard canSubmit else { return }
            submitFeedback()
        } label: {
            Text(isSubmitting ? AppLanguageStore.localized("feedback.submitting") : AppLanguageStore.localized("feedback.submit"))
                .font(.system(size: 16, weight: .bold))
                /// 勿用父级 `.tint(AppTheme.primary)` 作为字色：浅紫字叠在浅紫渐变上会几乎看不见；固定深紫字。
                .foregroundStyle(submitTitleColor.opacity(canSubmit ? 1.0 : 0.65))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    Capsule()
                        .fill(submitBarGradient.opacity(canSubmit ? 1.0 : 0.42))
                )
                .shadow(color: AppTheme.primary.opacity(canSubmit ? 0.5 : 0), radius: 18, y: 10)
        }
        .buttonStyle(.plain)
        /// 覆盖整页 `.tint(AppTheme.primary)`，避免 `Button` 标签被着成主色导致与背景融在一起。
        .tint(submitTitleColor)
    }

    private static func designChipLabel(_ cat: FeedbackCategory) -> String {
        cat.displayName
    }

    private func dismissFeedbackKeyboard() {
        isDescriptionFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func submitFeedback() {
        dismissFeedbackKeyboard()
        let content = trimmedContent
        guard !content.isEmpty else { return }

        Task {
            await MainActor.run { isSubmitting = true }
            let channelId = await AppConfig.shared.getChannel()
            let request = CreateFeedbackRequest(
                category: selectedCategory.rawValue,
                details: content,
                title: nil,
                taskId: nil,
                actualSpentAmount: nil,
                channelId: channelId
            )
            let result = await FeedbackAPI.submitFeedback(request: request)
            await MainActor.run {
                isSubmitting = false
                switch result {
                case .success:
                    message = ""
                    dismissAfterConfirm = true
                    alertTitle = AppLanguageStore.localized("feedback.alert.submitted_title")
                    alertMessage = AppLanguageStore.localized("feedback.alert.submitted_body")
                    showAlert = true
                case .failure(let err):
                    dismissAfterConfirm = false
                    alertTitle = AppLanguageStore.localized("feedback.alert.failed_title")
                    alertMessage = err.userMessage
                    showAlert = true
                }
            }
        }
    }
}

// MARK: - Feedback history (VIEW FEEDBACK HISTORY)

/// 设计稿：Feedback History — 活跃统计行、分类色标签、状态徽章、官方回复块、日期与 ID、END OF HISTORY。
struct FeedbackHistoryView: View {
    /// 远程推送 `feedback_reply`：加载完成后滚动到对应反馈卡片
    var focusFeedbackId: Int64?

    @State private var items: [FeedbackItem] = []
    @State private var loading = true
    @State private var errorText: String?
    @State private var didAttemptScrollToFocus = false

    private static let cardFill = Color(red: 26 / 255, green: 26 / 255, blue: 36 / 255)
    private static let replyBoxFill = Color(red: 22 / 255, green: 18 / 255, blue: 42 / 255)

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            if loading {
                ProgressView()
                    .tint(AppTheme.primary)
            } else if let errorText {
                Text(errorText)
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.onSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .padding(24)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            summaryRow

                            if items.isEmpty {
                                Text(AppLanguageStore.localized("feedback.history.empty"))
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(AppTheme.onSurfaceVariant)
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 48)
                            } else {
                                LazyVStack(spacing: 12) {
                                    ForEach(items) { item in
                                        feedbackCard(item)
                                            .id(item.id)
                                    }
                                }
                                .padding(.top, 8)

                                endOfHistoryFooter
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                    }
                    .onChange(of: items.map(\.id)) { _ in
                        scrollToFocusedFeedbackIfNeeded(proxy: proxy)
                    }
                    .onAppear {
                        scrollToFocusedFeedbackIfNeeded(proxy: proxy)
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(AppLanguageStore.localized("feedback.history.title"))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(AppTheme.primary)
            }
        }
        .bbbNavigationBarBackground(AppTheme.background)
        .bbbLocalizedNavigationBackButton()
        .tint(AppTheme.primary)
        .task {
            await load(isRefresh: false)
        }
        .refreshable {
            await load(isRefresh: true)
        }
        .bbbRefreshOnAppLanguage()
    }

    private func scrollToFocusedFeedbackIfNeeded(proxy: ScrollViewProxy) {
        guard !didAttemptScrollToFocus, let fid = focusFeedbackId else { return }
        guard items.contains(where: { $0.id == fid }) else { return }
        didAttemptScrollToFocus = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.easeOut(duration: 0.32)) {
                proxy.scrollTo(fid, anchor: .center)
            }
        }
    }

    private var summaryRow: some View {
        HStack {
            BBBTrackedText.text(AppLanguageStore.localized("feedback.active_submissions"), size: 10, weight: .semibold, tracking: 1.2, color: AppTheme.outlineVariant)
            Spacer()
            Text(String(format: AppLanguageStore.localized("feedback.history.total_format"), Int64(items.count)))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.primary)
        }
        .padding(.top, 4)
        .padding(.bottom, 4)
    }

    private func feedbackCard(_ item: FeedbackItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                BBBTrackedText.text(Self.categoryBannerLabel(item.category), size: 10, weight: .heavy, tracking: 0.8, color: Self.categoryAccentColor(item.category))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 8)
                statusBadge(status: item.status)
            }

            Text(item.details)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(AppTheme.onSurface.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)

            if let reply = item.supportResponse?.trimmingCharacters(in: .whitespacesAndNewlines), !reply.isEmpty {
                officialReplyBlock(text: reply)
            }

            HStack {
                Label {
                    Text(Self.formattedCardDate(createdAt: item.createdAt))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.onSurfaceVariant)
                } icon: {
                    Image(systemName: "calendar")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.outlineVariant)
                }
                Spacer(minLength: 8)
                Text(String(format: AppLanguageStore.localized("feedback.history.id_format"), String(item.id)))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.outlineVariant.opacity(0.9))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Self.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func officialReplyBlock(text: String) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle()
                .fill(AppTheme.primary)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.primary)
                    BBBTrackedText.text(AppLanguageStore.localized("feedback.official_reply"), size: 10, weight: .heavy, tracking: 1, color: AppTheme.primary.opacity(0.95))
                }
                Text(text)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(AppTheme.onSurface.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Self.replyBoxFill)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func statusBadge(status: String) -> some View {
        let s = Self.statusVisual(status)
        return BBBTrackedText.text(s.title, size: 9, weight: .heavy, tracking: 0.5, color: s.foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(s.background)
            )
    }

    private var endOfHistoryFooter: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 22))
                .foregroundStyle(AppTheme.outlineVariant.opacity(0.55))
            BBBTrackedText.text(AppLanguageStore.localized("feedback.end_history"), size: 10, weight: .bold, tracking: 2, color: AppTheme.outlineVariant.opacity(0.65))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 28)
        .padding(.bottom, 8)
    }

    private func load(isRefresh: Bool) async {
        if !isRefresh {
            await MainActor.run {
                loading = true
                errorText = nil
            }
        }
        let result = await FeedbackAPI.listFeedbacks(pageSize: 40)
        await MainActor.run {
            if !isRefresh {
                loading = false
            }
            switch result {
            case .success(let resp):
                items = resp.items
                errorText = nil
            case .failure(let err):
                if !isRefresh {
                    errorText = err.userMessage
                }
            }
        }
    }

    private static func formattedCardDate(createdAt: Int64) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let date = Date(timeIntervalSince1970: TimeInterval(createdAt))
        return formatter.string(from: date)
    }

    private static func categoryBannerLabel(_ raw: String) -> String {
        guard let cat = FeedbackCategory(rawValue: raw) else {
            return raw.replacingOccurrences(of: "_", with: " ").uppercased()
        }
        return cat.displayName.uppercased(with: .current)
    }

    private static func categoryAccentColor(_ raw: String) -> Color {
        guard let cat = FeedbackCategory(rawValue: raw) else {
            return AppTheme.neonPink
        }
        switch cat {
        case .aiGenerationQuality: return AppTheme.secondary
        case .paymentIssue: return AppTheme.primary
        case .appBug: return Color.orange.opacity(0.95)
        case .poorGenerationResult: return AppTheme.neonPink.opacity(0.9)
        case .other: return AppTheme.neonPink
        }
    }

    private struct StatusVisual {
        let title: String
        let background: Color
        let foreground: Color
    }

    private static func statusVisual(_ raw: String) -> StatusVisual {
        let lower = raw.lowercased()
        switch lower {
        case "resolved", "rewarded":
            return StatusVisual(
                title: AppLanguageStore.localized("feedback.status.resolved"),
                background: AppTheme.primary.opacity(0.22),
                foreground: AppTheme.primary.opacity(0.95)
            )
        case "in_progress":
            return StatusVisual(
                title: AppLanguageStore.localized("feedback.status.in_progress"),
                background: Color.white.opacity(0.08),
                foreground: AppTheme.onSurfaceVariant
            )
        default:
            return StatusVisual(
                title: AppLanguageStore.localized("feedback.status.pending"),
                background: Color.white.opacity(0.08),
                foreground: AppTheme.onSurfaceVariant.opacity(0.9)
            )
        }
    }
}

#Preview {
    NavigationView {
        UserAgreementView()
    }
    .navigationViewStyle(StackNavigationViewStyle())
    .environmentObject(AppLanguageStore())
    .tint(AppTheme.primary)
    .preferredColorScheme(.dark)
}
