import SwiftUI

// フラッシュパネル共通の配色パレット。深紺背景(ダーク)/明るい背景(ライト)の2種を切り替えられる。
struct ThemePalette {
    let background: Color
    let backgroundBottom: Color
    let mint: Color
    let purple: Color
    let orange: Color
    let textPrimary: Color
    let textSecondary: Color
    let divider: Color
    let rowSelected: Color
    let badgeText: Color
    let borderOverlay: Color
    let materialOpacity: Double
    let colorScheme: ColorScheme
}

extension ThemePalette {
    static let dark = ThemePalette(
        background: Color(red: 0.055, green: 0.075, blue: 0.11),
        backgroundBottom: Color(red: 0.04, green: 0.05, blue: 0.075),
        mint: Color(red: 0.56, green: 0.90, blue: 0.78),
        purple: Color(red: 0.64, green: 0.56, blue: 0.98),
        orange: Color(red: 0.93, green: 0.70, blue: 0.36),
        textPrimary: Color(red: 0.92, green: 0.93, blue: 0.96),
        textSecondary: Color(red: 0.58, green: 0.63, blue: 0.74),
        divider: Color(red: 0.20, green: 0.24, blue: 0.32),
        rowSelected: Color(red: 0.64, green: 0.56, blue: 0.98).opacity(0.22),
        badgeText: Color.black.opacity(0.78),
        borderOverlay: Color.white.opacity(0.08),
        materialOpacity: 0.55,
        colorScheme: .dark
    )

    static let light = ThemePalette(
        background: Color(red: 0.96, green: 0.97, blue: 1.0),
        backgroundBottom: Color(red: 0.90, green: 0.92, blue: 0.97),
        mint: Color(red: 0.30, green: 0.75, blue: 0.62),
        purple: Color(red: 0.44, green: 0.36, blue: 0.86),
        orange: Color(red: 0.80, green: 0.47, blue: 0.10),
        textPrimary: Color(red: 0.12, green: 0.13, blue: 0.17),
        textSecondary: Color(red: 0.40, green: 0.44, blue: 0.52),
        divider: Color(red: 0.82, green: 0.84, blue: 0.89),
        rowSelected: Color(red: 0.44, green: 0.36, blue: 0.86).opacity(0.14),
        badgeText: Color.white.opacity(0.95),
        borderOverlay: Color.black.opacity(0.06),
        materialOpacity: 0.7,
        colorScheme: .light
    )
}

enum AutoFlashThemeStyle: String, CaseIterable, Identifiable {
    case dark, light
    var id: String { rawValue }
    var title: String { self == .dark ? "Dark" : "Light" }
    var palette: ThemePalette { self == .dark ? .dark : .light }
}

// ヘッダーに表示するタブ風のカプセルバッジ("~/dotfiles" のような見た目)。
struct ThemeBadge: View {
    let systemImage: String
    let text: String
    let palette: ThemePalette
    var tint: Color?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(text)
        }
        .font(.system(size: 13, weight: .semibold, design: .monospaced))
        .foregroundStyle(palette.badgeText)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(tint ?? palette.mint, in: Capsule())
    }
}

// フッターのショートカットヒント用の小さなカプセル。
struct ThemeHintPill: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.16), in: Capsule())
            .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 1))
    }
}

extension View {
    // ウィンドウ全体の背景(グラデーション + regularMaterial + 透過率)。
    func autoFlashPanelBackground(palette: ThemePalette, opacity: Double) -> some View {
        self.background(
            ZStack {
                LinearGradient(
                    colors: [palette.background, palette.backgroundBottom],
                    startPoint: .top, endPoint: .bottom)
                Rectangle().fill(.regularMaterial).opacity(palette.materialOpacity)
            }
            .opacity(opacity)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(palette.borderOverlay, lineWidth: 1))
        .environment(\.colorScheme, palette.colorScheme)
    }
}
