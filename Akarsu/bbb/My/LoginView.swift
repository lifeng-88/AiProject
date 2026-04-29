//
//  LoginView.swift
//  bbb
//

import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var appLanguage: AppLanguageStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let _ = appLanguage.preference
        ZStack {
            LinearGradient(
                colors: [
                    AppTheme.background,
                    AppTheme.surfaceContainerLow.opacity(0.95),
                    AppTheme.background
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer(minLength: 40)

                VStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 44))
                        .foregroundStyle(AppTheme.primaryGradient)
                    Text(AppLanguageStore.localized("login.title"))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.onSurface)
                    Text(AppLanguageStore.localized("login.subtitle"))
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.onSurfaceVariant)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Spacer(minLength: 20)

                VStack(spacing: 14) {
                    if let err = auth.lastError, !err.isEmpty {
                        Text(err)
                            .font(.footnote)
                            .foregroundStyle(Color.red.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    Button {
                        Task { await auth.loginWithDevice() }
                    } label: {
                        HStack(spacing: 10) {
                            if auth.isLoading {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(auth.isLoading ? AppLanguageStore.localized("login.signing_in") : AppLanguageStore.localized("login.sign_in_device"))
                                .font(.system(size: 17, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(AppTheme.premiumButtonGradient)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                        .shadow(color: AppTheme.primaryDim.opacity(0.45), radius: 18, y: 8)
                    }
                    .buttonStyle(.plain)
                    .disabled(auth.isLoading)

                    Text(AppLanguageStore.localized("login.hint"))
                        .font(.caption2)
                        .foregroundStyle(AppTheme.outlineVariant)
                }
                .padding(.horizontal, 28)

                Spacer()
                Text(String(format: AppLanguageStore.localized("login.api_format"), LoginAPIConfig.baseURL))
                    .font(.system(size: 9))
                    .foregroundStyle(AppTheme.outlineVariant.opacity(0.6))
                    .padding(.bottom, 24)
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: auth.isAuthenticated) { isAuthed in
            if isAuthed { dismiss() }
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthSessionStore())
        .environmentObject(AppLanguageStore())
}
