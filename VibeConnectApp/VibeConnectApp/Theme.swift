import SwiftUI

// MARK: - Theme
// 配色・フォント・レイアウト定数の集約。
// モダンで落ち着いた（Vibe Coding にふさわしい）カラースキーム。ダークモード対応。
// システムのセマンティックカラーを基調にし、自動でライト/ダークへ追従する。

enum Theme {

    // MARK: 背景・サーフェス
    /// 画面全体の背景
    static let background = Color(.systemGroupedBackground)
    /// カード・入力欄などのサーフェス
    static let surface = Color(.secondarySystemBackground)
    /// さらに一段沈んだサーフェス（コンソールログ領域など）
    static let sunkenSurface = Color(.tertiarySystemBackground)

    // MARK: アクセント（落ち着いたインディゴ〜バイオレット）
    static let accent = Color(
        light: Color(hex: 0x5B6CFF),
        dark: Color(hex: 0x8A97FF)
    )

    // MARK: テキスト
    static let primaryText = Color(.label)
    static let secondaryText = Color(.secondaryLabel)
    static let tertiaryText = Color(.tertiaryLabel)

    // MARK: チャット吹き出し
    /// ユーザー（右側）吹き出し。アクセント基調。
    static let userBubble = accent
    static let userBubbleText = Color.white
    /// アシスタント（左側・コンソールログ）吹き出し。
    static let assistantBubble = Color(.secondarySystemBackground)
    static let assistantBubbleText = Color(.label)

    // MARK: 接続インジケータ
    static let connected = Color.green
    static let disconnected = Color.red

    // MARK: Diff 配色（IMPLEMENTATION_PLAN §4.2 B 準拠）
    /// 追加行: 薄緑背景 + 緑文字
    static let diffAddedBackground = Color.green.opacity(0.15)
    static let diffAddedText = Color(
        light: Color(hex: 0x1B7A3D),
        dark: Color(hex: 0x4ADE80)
    )
    /// 削除行: 薄赤背景 + 赤文字
    static let diffRemovedBackground = Color.red.opacity(0.15)
    static let diffRemovedText = Color(
        light: Color(hex: 0xB4232A),
        dark: Color(hex: 0xF87171)
    )
    /// ヘッダ行（@@, diff --git, +++/--- 等）
    static let diffHeaderBackground = accent.opacity(0.10)
    static let diffHeaderText = accent
    /// コンテキスト行
    static let diffContextText = Color(.label)

    // MARK: フォント
    /// コンソールログ・Diff 用の等幅フォント
    static let monospaced = Font.system(.body, design: .monospaced)
    /// Diff 行用の少し小さめ等幅
    static let monospacedSmall = Font.system(.callout, design: .monospaced)
    /// ヘッダのホスト名など
    static let hostFont = Font.system(.subheadline, design: .monospaced).weight(.semibold)

    // MARK: レイアウト定数
    static let cornerRadius: CGFloat = 16
    static let bubbleCornerRadius: CGFloat = 18
    static let contentPadding: CGFloat = 16
    static let bubbleSpacing: CGFloat = 10
}

// MARK: - Color ユーティリティ

extension Color {
    /// 16進数リテラルから Color を生成（例: 0x5B6CFF）
    init(hex: UInt, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }

    /// ライト/ダークで色を出し分ける動的カラー
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(dark)
                : UIColor(light)
        })
    }
}
