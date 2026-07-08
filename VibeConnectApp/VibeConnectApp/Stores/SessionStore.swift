import Foundation
import SwiftUI

// MARK: - SessionStore
// 複数チャット（セッション）の一覧・アクティブ管理。
// 親（ConsoleChatView / App）が TaskViewModel と結線する。
// メッセージ本文の永続化はしない（メモリ保持）。任意でメタ情報のみ UserDefaults 保存。

@MainActor
final class SessionStore: ObservableObject {
    @Published var sessions: [ChatSession] = []
    @Published var activeID: UUID?

    /// 起動時に読み込む Claude Code の既存履歴（サンドボックス分・メタのみ）。ドロワーの Recents 下に表示する。
    @Published var claudeHistory: [HistorySessionDTO] = []

    init(restore: Bool = true) {
        if restore { restoreSessions() }
        if sessions.isEmpty {
            let first = ChatSession()
            sessions = [first]
            activeID = first.id
        }
        if activeID == nil { activeID = sessions.first?.id }
    }

    var activeSession: ChatSession? {
        sessions.first { $0.id == activeID }
    }

    /// アクティブセッションの messages を差し替える（親が同期に使う）。会話本文も永続化する。
    func updateActiveMessages(_ messages: [ChatMessage]) {
        guard let id = activeID, let i = sessions.firstIndex(where: { $0.id == id }) else { return }
        // 変化がなければ保存もスキップ（ストリーミング中の無駄書き込みを抑える）。
        guard sessions[i].messages != messages else { return }
        sessions[i].messages = messages
        saveSessions()
    }

    @discardableResult
    func newSession() -> ChatSession {
        let s = ChatSession()
        sessions.insert(s, at: 0)
        activeID = s.id
        saveSessions()
        return s
    }

    func select(_ id: UUID) {
        activeID = id
    }

    /// 起動時に取得した Claude Code 履歴一覧をセットする。
    func setClaudeHistory(_ list: [HistorySessionDTO]) {
        claudeHistory = list
    }

    /// Claude Code の既存履歴から作った会話を取り込み、アクティブにする。
    @discardableResult
    func addImported(title: String, messages: [ChatMessage]) -> ChatSession {
        let s = ChatSession(title: title, messages: messages)
        sessions.insert(s, at: 0)
        activeID = s.id
        saveSessions()
        return s
    }

    func rename(_ id: UUID, title: String) {
        guard let i = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[i].title = title
        saveSessions()
    }

    func delete(_ id: UUID) {
        sessions.removeAll { $0.id == id }
        if activeID == id { activeID = sessions.first?.id }
        if sessions.isEmpty {
            let s = ChatSession()
            sessions = [s]
            activeID = s.id
        }
        saveSessions()
    }

    // MARK: - 永続化（会話全体: id / title / createdAt / messages をファイル保存）
    // UserDefaults だと長い CC ログで肥大化しうるため Documents に JSON ファイルで保存する。
    private struct Persisted: Codable {
        let id: UUID
        let title: String
        let createdAt: Date
        let messages: [ChatMessage]
    }

    private static var storeURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("sessions.json")
    }

    private func saveSessions() {
        let items = sessions.map {
            Persisted(id: $0.id, title: $0.title, createdAt: $0.createdAt, messages: $0.messages)
        }
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: Self.storeURL, options: .atomic)
    }

    private func restoreSessions() {
        guard let data = try? Data(contentsOf: Self.storeURL),
              let items = try? JSONDecoder().decode([Persisted].self, from: data),
              !items.isEmpty else { return }
        sessions = items.map {
            ChatSession(id: $0.id, title: $0.title, createdAt: $0.createdAt, messages: $0.messages)
        }
        activeID = sessions.first?.id
    }

    // MARK: - Preview
    static var preview: SessionStore {
        let store = SessionStore(restore: false)
        store.sessions = [
            ChatSession(title: "ボタンの色を変更", createdAt: Date(), messages: MockData.messages),
            ChatSession(title: "認証をリファクタ", createdAt: Date().addingTimeInterval(-3600), messages: []),
            ChatSession(title: "", createdAt: Date().addingTimeInterval(-7200), messages: [])
        ]
        store.activeID = store.sessions.first?.id
        return store
    }
}
