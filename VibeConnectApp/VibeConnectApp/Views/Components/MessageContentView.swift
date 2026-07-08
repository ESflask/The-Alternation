import SwiftUI
import UIKit

// MARK: - MessageSegment
// assistant のメッセージ本文を「地の文(prose)」と「コードブロック」に分割した単位。
// フェンス ``` … ``` で囲まれた部分だけが .code、それ以外はすべて .text。
enum MessageSegment: Equatable {
    case text(String)
    case code(String, lang: String?)
}

// MARK: - MessageParser
// message.text をフェンス ``` 区切りでセグメント分割する。
//  - 開きフェンス直後の残り文字列を言語名として拾う（空なら nil）。
//  - 閉じフェンスが無いまま終端した場合は、残りをコードとして扱う。
//  - 地の文は前後の空行のみ落とし、内部の改行は保持する。
enum MessageParser {
    static func parse(_ raw: String) -> [MessageSegment] {
        var segments: [MessageSegment] = []
        let lines = raw.components(separatedBy: "\n")

        var textBuffer: [String] = []
        var codeBuffer: [String] = []
        var codeLang: String?
        var inCode = false

        func flushText() {
            defer { textBuffer.removeAll() }
            let joined = textBuffer.joined(separator: "\n")
            let trimmed = joined.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            segments.append(.text(trimmed))
        }

        func flushCode() {
            let joined = codeBuffer.joined(separator: "\n")
            segments.append(.code(joined, lang: codeLang))
            codeBuffer.removeAll()
            codeLang = nil
        }

        for line in lines {
            let leading = line.trimmingCharacters(in: .whitespaces)
            if leading.hasPrefix("```") {
                if inCode {
                    // 閉じフェンス
                    flushCode()
                    inCode = false
                } else {
                    // 開きフェンス
                    flushText()
                    let lang = String(leading.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    codeLang = lang.isEmpty ? nil : lang
                    inCode = true
                }
            } else if inCode {
                codeBuffer.append(line)
            } else {
                textBuffer.append(line)
            }
        }

        // 終端処理（閉じフェンス無しのコードは残りを code として救済）
        if inCode {
            flushCode()
        } else {
            flushText()
        }

        return segments
    }
}

// MARK: - MessageContentView
// assistant の本文を「地の文＝枠なし通常テキスト」「コード＝ターミナル枠」で縦積み描画する。
struct MessageContentView: View {
    let text: String

    private var segments: [MessageSegment] { MessageParser.parse(text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            let parsed = segments
            if parsed.isEmpty {
                // 空 or 空白のみ → プレースホルダの素テキスト
                ProseView(text: text.isEmpty ? "…" : text)
            } else {
                ForEach(Array(parsed.enumerated()), id: \.offset) { _, segment in
                    switch segment {
                    case .text(let value):
                        ProseView(text: value)
                    case .code(let code, let lang):
                        CodeBlockView(code: code, lang: lang)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - ProseView（地の文：枠なしの通常テキスト）
// 見出し/箇条書き/インライン `code`/太字を軽く整形。パース失敗時はプレーン文字列。
private struct ProseView: View {
    let text: String

    var body: some View {
        Text(attributed)
            .font(.body)
            .foregroundStyle(Theme.primaryText)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var attributed: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: false,
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        if let value = try? AttributedString(markdown: text, options: options) {
            return value
        }
        return AttributedString(text)
    }
}

// MARK: - CodeBlockView（コード：ターミナル枠）
// 既存 ChatBubble のコンソールカード意匠を流用。ヘッダ（⌘ terminal ＋ 言語名/"code" ＋ コピー）＋
// 横スクロールの等幅本文。背景は sunkenSurface、角丸＋細い枠。
private struct CodeBlockView: View {
    let code: String
    let lang: String?

    @State private var copied = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.bubbleCornerRadius, style: .continuous)
    }

    private var displayLang: String {
        if let lang, !lang.isEmpty { return lang }
        return "code"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Theme.accent.opacity(0.12))
            codeBody
        }
        .background(Theme.sunkenSurface, in: shape)
        .overlay(shape.stroke(Theme.accent.opacity(0.12), lineWidth: 1))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "terminal.fill")
                .font(.caption2)
            Text(displayLang)
                .font(.caption.weight(.semibold))
                .tracking(0.3)
            Spacer()
            copyButton
        }
        .foregroundStyle(Theme.secondaryText)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var copyButton: some View {
        Button {
            UIPasteboard.general.string = code
            copied = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                copied = false
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.caption2.weight(.medium))
                .foregroundStyle(copied ? Theme.connected : Theme.secondaryText)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(copied ? "コピーしました" : "コードをコピー")
    }

    // 横スクロール対応の等幅本文（長い行を折り返さず読める）
    private var codeBody: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(code.isEmpty ? "…" : code)
                .font(Theme.monospacedSmall)
                .foregroundStyle(Theme.assistantBubbleText)
                .lineSpacing(3)
                .textSelection(.enabled)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
    }
}

// MARK: - Preview

private let mixedSample = """
`src/Views/MainView.swift` のボタンを更新しました。**変更点**は以下の通りです。

- 背景色を `Color.red` → `Color.blue` に変更
- ラベルを「Click Me」→「実行」に変更

```swift
Button("実行") { runTask() }
    .background(Color.blue)
    .foregroundColor(.white)
```

続けてテストを実行しています。

```bash
swift test
# Test Suite 'All tests' passed (12 tests, 0 failures)
```

差分を確認してください。
"""

#Preview("MessageContent – Mixed") {
    ScrollView {
        MessageContentView(text: mixedSample)
            .padding()
    }
    .background(Theme.background)
}

#Preview("MessageContent – Prose only") {
    MessageContentView(text: "# 見出し\n\nこれは **太字** と `inline code` を含む地の文です。")
        .padding()
        .background(Theme.background)
}
