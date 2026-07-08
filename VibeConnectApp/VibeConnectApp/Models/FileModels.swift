import Foundation

// MARK: - FileModels
// Mac サーバー上のワークスペースをブラウズ／編集するためのモデル群。
// CONTRACTS-FEATURES.md §B に完全一致で定義する（型名・プロパティ名・JSON形状を変えない）。
//
// 対応エンドポイント（CONTRACTS-FEATURES.md §A）:
//   GET  /api/files/tree?path=<rel>   → FileTreeResponse
//   GET  /api/files/read?path=<rel>   → FileReadResponse
//   PUT  /api/files/write             → FileWriteResponse

/// ファイルツリーのノード種別。JSON では "file" / "dir"。
enum FileNodeType: String, Codable {
    case file
    case dir
}

/// ツリー内の 1 エントリ。`path` はルート相対（ルートは ""）。
struct FileEntry: Codable, Identifiable, Hashable {
    /// Identifiable 準拠。パスは一意なので id に流用する。
    var id: String { path }
    let name: String
    let path: String
    let type: FileNodeType
    /// ディレクトリ等でサイズ不明の場合は null。
    let size: Int?
}

/// GET /api/files/tree の応答。ディレクトリ優先→名前昇順（サーバ側で整列済み）。
struct FileTreeResponse: Codable {
    let path: String
    let entries: [FileEntry]
}

/// GET /api/files/read の応答。
/// テキストのみ。2MB超やバイナリ判定時は `content` が空/先頭のみで `truncated == true`。
struct FileReadResponse: Codable {
    let path: String
    let content: String
    let truncated: Bool
}

/// PUT /api/files/write の応答。
struct FileWriteResponse: Codable {
    let success: Bool
    let message: String
}
