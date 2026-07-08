import Foundation

// MARK: - サーバーレスポンス / 共有データモデル
// CONTRACTS.md §4 の定義と完全一致させること（フィールド名/型は固定）。
// Agent 5 (Networking / TaskViewModel) も同一定義に依存する。

enum TaskStatus: String, Codable, Equatable {
    case processing, completed, failed
}

/// POST /api/tasks のレスポンス
struct CreateTaskResponse: Codable, Equatable {
    let task_id: String
    let status: String
    let message: String
}

/// GET /api/tasks/:id のレスポンス
struct TaskStatusResponse: Codable, Equatable {
    let task_id: String
    let status: TaskStatus
    let logs: String
    let error: String?
}

/// GET /api/git/diff
struct DiffResponse: Codable, Equatable {
    let has_changes: Bool
    let diff: String
}

/// POST /api/git/commit
struct CommitResponse: Codable, Equatable {
    let success: Bool
    let message: String
}

/// GET /api/usage のレスポンス（ローカルログ由来の使用量集計）
struct UsageResponse: Codable, Equatable {
    let scope: String
    let generatedAt: String
    let scannedFiles: Int
    let note: String
    let periods: Periods
    let byModel: [ModelUsage]

    struct Periods: Codable, Equatable {
        let today: Bucket
        let last7d: Bucket
        let thisMonth: Bucket
        let allTime: Bucket
    }
    struct Bucket: Codable, Equatable {
        let inputTokens: Int
        let outputTokens: Int
        let cacheReadTokens: Int
        let cacheCreationTokens: Int
        let totalTokens: Int
        let costUSD: Double
        let requests: Int
    }
    struct ModelUsage: Codable, Equatable, Identifiable {
        let model: String
        let inputTokens: Int
        let outputTokens: Int
        let costUSD: Double
        let requests: Int
        var id: String { model }
    }
}

/// GET /api/history/sessions のレスポンス（既存 Claude Code 履歴の一覧）
struct HistorySessionsResponse: Codable, Equatable {
    let scope: String
    let sessions: [HistorySessionDTO]
}
struct HistorySessionDTO: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let messageCount: Int
    let startedAt: String
    let lastAt: String
}

/// GET /api/history/:id のレスポンス（1セッションの本文）
struct HistoryMessagesResponse: Codable, Equatable {
    let id: String
    let count: Int
    let messages: [HistoryMessageDTO]
}
struct HistoryMessageDTO: Codable, Equatable {
    let role: String        // "user" | "assistant"
    let text: String
    let timestamp: String?
}

/// チャットタイムラインの1メッセージ
struct ChatMessage: Identifiable, Equatable, Codable {
    enum Role: String, Codable { case user, assistant }
    let id: UUID
    let role: Role
    var text: String
    let timestamp: Date

    init(id: UUID = UUID(), role: Role, text: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
    }
}

/// Diff表示の1行
struct DiffLine: Identifiable, Equatable {
    enum Kind { case added, removed, context, header }
    let id: UUID
    let kind: Kind
    let text: String

    init(id: UUID = UUID(), kind: Kind, text: String) {
        self.id = id
        self.kind = kind
        self.text = text
    }
}

// MARK: - Diff パーサ（共有ユーティリティ）
// Agent 4 の DiffInspectorView と Agent 5 の TaskViewModel.loadDiff() の双方から呼ばれる。

enum DiffParser {
    /// git diff の生文字列を行ごとに解析して [DiffLine] を返す。
    /// 行頭 '+' → .added, '-' → .removed,
    /// '@@' や 'diff --git' や '+++/---' → .header, それ以外 → .context
    ///
    /// 注意: '+++' / '---' は '+' / '-' で始まるため、ヘッダ判定を先に行う。
    static func parse(_ raw: String) -> [DiffLine] {
        guard !raw.isEmpty else { return [] }

        // 改行で分割。末尾の余分な空行（末尾が改行で終わる場合に生じる）は1つだけ落とす。
        var rows = raw.components(separatedBy: "\n")
        if rows.count > 1, rows.last == "" {
            rows.removeLast()
        }

        return rows.map { row in
            DiffLine(kind: classify(row), text: row)
        }
    }

    /// 1行のテキストから DiffLine.Kind を判定する。
    private static func classify(_ line: String) -> DiffLine.Kind {
        // ヘッダ系（'+++'/'---' は '+'/'-' 判定より優先）
        if line.hasPrefix("diff --git")
            || line.hasPrefix("+++")
            || line.hasPrefix("---")
            || line.hasPrefix("@@")
            || line.hasPrefix("index ")
            || line.hasPrefix("new file mode")
            || line.hasPrefix("deleted file mode")
            || line.hasPrefix("rename ")
            || line.hasPrefix("similarity index") {
            return .header
        }
        if line.hasPrefix("+") { return .added }
        if line.hasPrefix("-") { return .removed }
        return .context
    }
}
