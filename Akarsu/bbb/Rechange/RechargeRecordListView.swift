//
//  RechargeRecordListView.swift
//  bbb
//
//  充值记录：数据来自 `/v1/users/{userId}/recharges`，支持下拉刷新与分页加载
//

import SwiftUI

struct RechargeRecordListView: View {
    @EnvironmentObject private var auth: AuthSessionStore

    @State private var rows: [RechargeRecordListRow] = []
    @State private var nextPageToken: String?
    @State private var loadError: String?
    @State private var isLoading = false
    @State private var isLoadingMore = false
    /// 避免首帧在已登录时误显示「空列表」；未登录时也会在一次拉取后置为 true
    @State private var hasFinishedInitialFetch = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            if !hasFinishedInitialFetch, loadError == nil, auth.userId != nil, !(auth.userId?.isEmpty ?? true) {
                ProgressView()
                    .tint(AppTheme.primary)
            } else if let err = loadError, rows.isEmpty {
                errorState(err)
            } else if rows.isEmpty {
                ScrollView {
                    emptyState
                        .frame(maxWidth: .infinity, minHeight: 400)
                }
                .refreshable { await loadFirstPage() }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            recordRow(row)
                            Divider()
                                .background(AppTheme.outlineVariant.opacity(0.15))
                                .padding(.leading, 16)
                            if index == rows.count - 1 {
                                loadMoreTrigger
                            }
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.bottom, 12)
                }
                .refreshable { await loadFirstPage() }
            }
        }
        .navigationTitle(AppLanguageStore.localized("recharge.record.title"))
        .navigationBarTitleDisplayMode(.inline)
        .bbbNavigationBarBackground(AppTheme.background)
        .task {
            await loadFirstPage()
            await MainActor.run { hasFinishedInitialFetch = true }
        }
        .bbbRefreshOnAppLanguage()
    }

    private var loadMoreTrigger: some View {
        Group {
            if nextPageToken != nil {
                HStack {
                    Spacer()
                    if isLoadingMore {
                        ProgressView()
                            .tint(AppTheme.primary)
                            .padding(.vertical, 16)
                    } else {
                        Color.clear
                            .frame(height: 1)
                            .onAppear {
                                Task { await loadMore() }
                            }
                    }
                    Spacer()
                }
            }
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(AppTheme.secondary.opacity(0.85))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(AppTheme.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button(AppLanguageStore.localized("common.retry")) {
                Task { await loadFirstPage() }
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 52))
                .foregroundStyle(AppTheme.secondary.opacity(0.55))
            Text(emptyHeadline)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppTheme.onSurface)
                .multilineTextAlignment(.center)
            Text(emptySubtitle)
                .font(.subheadline)
                .foregroundStyle(AppTheme.onSurfaceVariant)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }

    private var emptyHeadline: String {
        if auth.userId == nil || (auth.userId?.isEmpty == true) {
            return AppLanguageStore.localized("recharge.record.empty_guest")
        }
        return AppLanguageStore.localized("recharge.record.empty_logged_in")
    }

    private var emptySubtitle: String {
        if auth.userId == nil || (auth.userId?.isEmpty == true) {
            return AppLanguageStore.localized("recharge.record.empty_guest_sub")
        }
        return AppLanguageStore.localized("recharge.record.empty_logged_in_sub")
    }

    private func loadFirstPage() async {
        guard let uid = auth.userId, !uid.isEmpty else {
            await MainActor.run {
                rows = []
                nextPageToken = nil
                loadError = nil
                isLoading = false
            }
            return
        }
        await MainActor.run {
            loadError = nil
            isLoading = true
        }
        let result = await RechargeRepository.shared.getRechargeRecords(userId: uid, pageToken: nil)
        await MainActor.run {
            isLoading = false
            switch result {
            case .success(let tuple):
                rows = tuple.list.map { $0.toListRow() }
                nextPageToken = tuple.nextPageToken
            case .failure(let err):
                loadError = err.userMessage
            }
        }
    }

    private func loadMore() async {
        guard let token = nextPageToken, !token.isEmpty, !isLoadingMore else { return }
        guard let uid = auth.userId, !uid.isEmpty else { return }
        await MainActor.run { isLoadingMore = true }
        let result = await RechargeRepository.shared.getRechargeRecords(userId: uid, pageToken: token)
        await MainActor.run {
            isLoadingMore = false
            switch result {
            case .success(let tuple):
                let newRows = tuple.list.map { $0.toListRow() }
                let existing = Set(rows.map(\.id))
                let merged = newRows.filter { !existing.contains($0.id) }
                rows.append(contentsOf: merged)
                nextPageToken = tuple.nextPageToken
            case .failure:
                break
            }
        }
    }

    private func recordRow(_ item: RechargeRecordListRow) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.onSurface)
                Text(Self.dateFormatter.string(from: item.createdAt))
                    .font(.caption)
                    .foregroundStyle(AppTheme.onSurfaceVariant)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 6) {
                Text(item.amount)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                if let coins = item.coins {
                    HStack(spacing: 4) {
                        AppCoinIcon(size: 11)
                        Text("+\(coins)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.secondary)
                    }
                }
                statusBadge(item.status)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func statusBadge(_ status: RechargeRecordStatus) -> some View {
        BBBTrackedText.text(status.rawValue.capitalized, size: 10, weight: .bold, tracking: 0.8, color: foreground(for: status))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(background(for: status))
            .clipShape(Capsule())
    }

    private func foreground(for status: RechargeRecordStatus) -> Color {
        switch status {
        case .completed: return Color.green.opacity(0.95)
        case .pending: return AppTheme.secondary
        case .failed: return Color(red: 255 / 255, green: 110 / 255, blue: 132 / 255)
        }
    }

    private func background(for status: RechargeRecordStatus) -> Color {
        switch status {
        case .completed: return Color.green.opacity(0.15)
        case .pending: return AppTheme.secondary.opacity(0.12)
        case .failed: return Color.red.opacity(0.15)
        }
    }
}

#Preview {
    NavigationView {
        RechargeRecordListView()
            .environmentObject(AuthSessionStore())
    }
    .navigationViewStyle(StackNavigationViewStyle())
    .preferredColorScheme(.dark)
}
