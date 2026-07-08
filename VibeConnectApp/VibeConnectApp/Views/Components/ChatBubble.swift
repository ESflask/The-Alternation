import SwiftUI
import UIKit

// MARK: - ChatBubble
// チャットタイムラインの1メッセージ。
// user      → 右側・アクセント吹き出し（通常フォント・角丸）
// assistant → 左側・アバターなし ＋ MessageContentView
//             （地の文は枠なしの通常テキスト、コードブロックだけターミナル枠で描画）

struct ChatBubble: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if isUser { Spacer(minLength: 40) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                if isUser {
                    userBubble
                } else {
                    // 全文を1枠で囲まず、セグメント分割して描画する
                    MessageContentView(text: message.text)
                }
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(Theme.tertiaryText)
                    .padding(.horizontal, 4)
            }

            if !isUser { Spacer(minLength: 40) }
        }
    }

    // MARK: ユーザー吹き出し（現状維持）
    private var userBubble: some View {
        Text(message.text)
            .font(.body)
            .foregroundStyle(Theme.userBubbleText)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.userBubble, in: bubbleShape)
            .textSelection(.enabled)
    }

    private var bubbleShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.bubbleCornerRadius, style: .continuous)
    }
}

#Preview("User") {
    ChatBubble(message: MockData.messages[0])
        .padding()
        .background(Theme.background)
}

#Preview("Assistant") {
    ChatBubble(message: MockData.messages[1])
        .padding()
        .background(Theme.background)
}

#Preview("Assistant – Mixed code") {
    ScrollView {
        ChatBubble(
            message: ChatMessage(
                role: .assistant,
                text: """
                `MainView.swift` を更新しました。**変更点**は以下です。

                - 背景色を `Color.red` → `Color.blue`
                - ラベルを「Click Me」→「実行」

                ```swift
                Button("実行") { runTask() }
                    .background(Color.blue)
                    .foregroundColor(.white)
                ```

                テストも通っています。
                """
            )
        )
        .padding()
    }
    .background(Theme.background)
}
