//
//  AppTheme.swift
//  bbb
//
//  Design tokens from 效果图/stitch_recharge_screen_design (Neon Sovereign)
//

import SwiftUI

enum AppTheme {
    static let background = Color(red: 13 / 255, green: 13 / 255, blue: 25 / 255)
    static let surfaceDim = Color(red: 13 / 255, green: 13 / 255, blue: 25 / 255)
    static let surfaceContainer = Color(red: 24 / 255, green: 24 / 255, blue: 39 / 255)
    static let surfaceContainerLow = Color(red: 18 / 255, green: 18 / 255, blue: 31 / 255)
    static let surfaceContainerHigh = Color(red: 30 / 255, green: 30 / 255, blue: 46 / 255)
    static let surfaceContainerHighest = Color(red: 36 / 255, green: 36 / 255, blue: 54 / 255)
    static let surfaceVariant = Color(red: 36 / 255, green: 36 / 255, blue: 54 / 255)

    static let primary = Color(red: 197 / 255, green: 154 / 255, blue: 255 / 255)
    static let primaryDim = Color(red: 149 / 255, green: 71 / 255, blue: 247 / 255)
    static let secondary = Color(red: 255 / 255, green: 215 / 255, blue: 9 / 255)
    static let onSurface = Color(red: 230 / 255, green: 227 / 255, blue: 245 / 255)
    static let onSurfaceVariant = Color(red: 171 / 255, green: 169 / 255, blue: 186 / 255)
    static let outlineVariant = Color(red: 71 / 255, green: 71 / 255, blue: 85 / 255)

    static let neonPink = Color(red: 255 / 255, green: 45 / 255, blue: 120 / 255)
    static let tabBarBackground = Color(red: 24 / 255, green: 24 / 255, blue: 39 / 255).opacity(0.85)

    static let primaryGradient = LinearGradient(
        colors: [primaryDim, primary],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let premiumButtonGradient = LinearGradient(
        colors: [
            Color(red: 186 / 255, green: 136 / 255, blue: 255 / 255),
            primaryDim,
            Color(red: 126 / 255, green: 41 / 255, blue: 223 / 255)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
