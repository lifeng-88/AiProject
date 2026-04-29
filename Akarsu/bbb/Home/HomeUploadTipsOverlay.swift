//
//  HomeUploadTipsOverlay.swift
//  bbb
//
//  生成前「Upload Tips」示例弹窗（GOOD / BAD 对照）
//

import SwiftUI

struct HomeUploadTipsOverlay: View {
    @Binding var dontShowAgain: Bool
    var onClose: () -> Void
    var onConfirm: () -> Void

    /// `Assets.xcassets` 中与示例稿一致的 GOOD / BAD 贴图
    private enum Asset {
        static let good = "UploadTipsGood"
        static let bad = "UploadTipsBad"
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.52)
                .background(.ultraThinMaterial.opacity(0.3))
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    Text(AppLanguageStore.localized("home.upload.title"))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(AppTheme.onSurface)
                    Spacer(minLength: 8)
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppTheme.onSurfaceVariant)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 18)

                HStack(alignment: .top, spacing: 10) {
                    tipColumn(
                        assetName: Asset.good,
                        title: AppLanguageStore.localized("home.upload.good"),
                        caption: AppLanguageStore.localized("home.upload.good_caption")
                    )
                    tipColumn(
                        assetName: Asset.bad,
                        title: AppLanguageStore.localized("home.upload.bad"),
                        caption: AppLanguageStore.localized("home.upload.bad_caption")
                    )
                }

                Button {
                    dontShowAgain.toggle()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: dontShowAgain ? "checkmark.square.fill" : "square")
                            .font(.system(size: 20))
                            .foregroundStyle(dontShowAgain ? AppTheme.primary : AppTheme.onSurfaceVariant)
                        Text(AppLanguageStore.localized("home.upload.dont_show"))
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.onSurfaceVariant)
                    }
                }
                .buttonStyle(.plain)
                .padding(.top, 18)

                Button(action: onConfirm) {
                    Text(AppLanguageStore.localized("home.upload.confirm"))
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.88))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .fill(AppTheme.primary.opacity(0.92))
                        )
                }
                .buttonStyle(.plain)
                .padding(.top, 16)
            }
            .padding(22)
            .frame(maxWidth: 400)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(AppTheme.surfaceContainer)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(AppTheme.outlineVariant.opacity(0.35), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.45), radius: 28, y: 14)
            .padding(.horizontal, 22)
        }
    }

    private func tipColumn(assetName: String, title: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(assetName)
                .resizable()
                .scaledToFill()
                .frame(height: 148)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text(title)
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(AppTheme.primary)
                .textCase(.uppercase)

            Text(caption)
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    ZStack {
        AppTheme.background.ignoresSafeArea()
        HomeUploadTipsOverlay(
            dontShowAgain: .constant(false),
            onClose: {},
            onConfirm: {}
        )
    }
}
