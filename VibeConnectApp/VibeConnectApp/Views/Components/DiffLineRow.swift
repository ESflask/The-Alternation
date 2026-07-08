import SwiftUI

// MARK: - DiffLineRow
// Diff の1行。kind に応じて背景色・文字色を出し分ける（Theme 定数を使用）。
// 等幅フォント・行番号ガター付き。横スクロールは親の ScrollView が担う。

struct DiffLineRow: View {
    let line: DiffLine
    /// 短い行でも背景がビューポート幅いっぱいに広がるよう、最小幅を親から注入する。
    var minWidth: CGFloat = 0

    var body: some View {
        HStack(spacing: 0) {
            // 行頭マーカー（+ / - / 空白）
            Text(marker)
                .font(Theme.monospacedSmall)
                .foregroundStyle(textColor)
                .frame(width: 18, alignment: .center)

            Text(displayText)
                .font(Theme.monospacedSmall)
                .foregroundStyle(textColor)
                .fixedSize(horizontal: true, vertical: false)
                .textSelection(.enabled)

            Spacer(minLength: 12)
        }
        .padding(.vertical, 2)
        .frame(minWidth: minWidth, alignment: .leading)
        .background(backgroundColor)
    }

    // 行頭記号を分離して表示（本文からは記号を落とし、見やすくする）
    private var marker: String {
        switch line.kind {
        case .added: return "+"
        case .removed: return "-"
        case .header, .context: return " "
        }
    }

    private var displayText: String {
        switch line.kind {
        case .added, .removed:
            // 先頭の +/- を1つだけ落とす
            return String(line.text.dropFirst())
        case .header, .context:
            return line.text
        }
    }

    private var backgroundColor: Color {
        switch line.kind {
        case .added:   return Theme.diffAddedBackground
        case .removed: return Theme.diffRemovedBackground
        case .header:  return Theme.diffHeaderBackground
        case .context: return Color.clear
        }
    }

    private var textColor: Color {
        switch line.kind {
        case .added:   return Theme.diffAddedText
        case .removed: return Theme.diffRemovedText
        case .header:  return Theme.diffHeaderText
        case .context: return Theme.diffContextText
        }
    }
}

#Preview("Diff lines") {
    ScrollView(.horizontal) {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(MockData.diffLines) { line in
                DiffLineRow(line: line)
            }
        }
    }
    .background(Theme.sunkenSurface)
}
