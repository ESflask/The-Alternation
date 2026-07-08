import SwiftUI

// MARK: - GlassKit
// Liquid Glass（iOS 26+）の共通ヘルパー。
// - interactiveGlass(in:): タップ反応（.interactive）を ON にした Liquid Glass 背景。
//   iOS 26 未満は .ultraThinMaterial にフォールバック。
// - GlassIconButton: 単体の円形ガラスアイコンボタン。
// - GlassSegmentedButtons: 近接するボタンを 1 本の横長ガラスバーに区切って収めた分割ボタン。

extension View {
    /// タップ反応つき Liquid Glass 背景を任意 shape で適用する。
    @ViewBuilder
    func interactiveGlass<S: Shape>(in shape: S, tint: Color? = nil) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive().tint(tint), in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }
}

// MARK: - 単体ガラスアイコンボタン
struct GlassIconButton: View {
    let icon: String
    var size: CGFloat = 36
    var weight: Font.Weight = .semibold
    var tint: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: weight))
                .foregroundStyle(tint ?? Theme.primaryText)
                .frame(width: size, height: size)
                .contentShape(Circle())
                .interactiveGlass(in: Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 分割ガラスボタン（横長 1 本を区切る）
struct GlassSegment: Identifiable {
    let id = UUID()
    let icon: String
    var tint: Color? = nil
    let action: () -> Void
}

struct GlassSegmentedButtons: View {
    let segments: [GlassSegment]
    var height: CGFloat = 38
    var segmentWidth: CGFloat = 44

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(segments.enumerated()), id: \.element.id) { index, seg in
                Button(action: seg.action) {
                    Image(systemName: seg.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(seg.tint ?? Theme.secondaryText)
                        .frame(width: segmentWidth, height: height)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if index < segments.count - 1 {
                    Divider()
                        .frame(height: height * 0.5)
                        .overlay(Theme.primaryText.opacity(0.14))
                }
            }
        }
        .frame(height: height)
        .interactiveGlass(in: Capsule())
    }
}
