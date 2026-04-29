//
//  AppCoinIcon.swift
//  bbb
//
//  与首页右上角参考稿一致：金色圆币 + 中心字形（默认 “S”）
//

import SwiftUI

/// 应用内统一金币图标（矢量绘制，非 SF Symbol）
struct AppCoinIcon: View {
    /// 外接正方形边长
    var size: CGFloat = 17
    /// 中心符号，与产品稿右上角一致为 “S”
    var symbol: String = "S"

    var body: some View {
        let ring = max(0.5, size * 0.06)
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 1.0, green: 0.96, blue: 0.62),
                            Color(red: 1.0, green: 0.84, blue: 0.28),
                            Color(red: 0.88, green: 0.65, blue: 0.08)
                        ],
                        center: .init(x: 0.35, y: 0.3),
                        startRadius: 0,
                        endRadius: size * 0.75
                    )
                )
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.65),
                            Color.white.opacity(0.12),
                            Color.black.opacity(0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: ring
                )
            Text(symbol)
                .font(.system(size: size * 0.5, weight: .heavy, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 0.22, green: 0.16, blue: 0.06),
                            Color(red: 0.42, green: 0.3, blue: 0.08)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .frame(width: size, height: size)
        .shadow(color: Color.black.opacity(0.22), radius: size * 0.12, y: size * 0.06)
    }
}

#if DEBUG
struct AppCoinIcon_Previews: PreviewProvider {
    static var previews: some View {
        HStack(spacing: 16) {
            AppCoinIcon(size: 15)
            AppCoinIcon(size: 17)
            AppCoinIcon(size: 22)
        }
        .padding()
        .background(Color.black)
    }
}
#endif
