import Foundation

// MARK: - ChatSession
// 1つのチャット（会話）を表す。複数セッションを SessionStore が保持する。
// ChatMessage は既存 Models.swift のもの（Codable でないため永続化はメタのみ）。

struct ChatSession: Identifiable, Equatable {
    let id: UUID
    var title: String
    var createdAt: Date
    var messages: [ChatMessage]

    init(id: UUID = UUID(),
         title: String = "",
         createdAt: Date = Date(),
         messages: [ChatMessage] = []) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.messages = messages
    }

    /// タイトル未設定なら既定名。最初のユーザー発言から自動命名にも使える。
    var displayTitle: String {
        if !title.isEmpty { return title }
        if let firstUser = messages.first(where: { $0.role == .user })?.text,
           !firstUser.isEmpty {
            return String(firstUser.prefix(24))
        }
        return "新しいチャット"
    }
}
