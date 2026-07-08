import SwiftUI

// MARK: - FileBrowserView
// Mac サーバー上のワークスペースを iPhone からブラウズする画面（CONTRACTS-FEATURES.md §D）。
//
// - `init(host: String)` でサーバーホストを受け取り、内部で APIClient を構築する。
// - APIClient.fileTree(path:) でディレクトリの中身を取得しツリー表示する。
// - ディレクトリはタップで潜行（push）、ファイルはタップで FileEditorView へ遷移。
// - ローディング / エラー表示あり。
// - TaskViewModel には一切依存しない（serverHost だけで自己完結）。

struct FileBrowserView: View {

    let host: String

    /// host から組み立てた API クライアント。不正ホストなら nil。
    private let client: APIClient?

    init(host: String) {
        self.host = host
        self.client = APIClient(host: host)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let client {
                    FileDirectoryView(client: client,
                                      host: host,
                                      path: "",
                                      displayName: "ワークスペース")
                    .navigationDestination(for: FileEntry.self) { entry in
                        if entry.type == .dir {
                            FileDirectoryView(client: client,
                                              host: host,
                                              path: entry.path,
                                              displayName: entry.name)
                        } else {
                            FileEditorView(path: entry.path, host: host)
                        }
                    }
                } else {
                    invalidHostState
                }
            }
            .background(Theme.background)
        }
        .tint(Theme.accent)
    }

    private var invalidHostState: some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Theme.disconnected.opacity(0.8))
            Text("サーバーアドレスが不正です")
                .font(.headline)
                .foregroundStyle(Theme.primaryText)
            Text("設定でホスト（例: 192.168.11.34）を\n確認してください。")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - FileDirectoryView
// 1 つのディレクトリ（path）の中身を表示するリスト。
// FileBrowserView から NavigationStack の各階層として push される。

private struct FileDirectoryView: View {

    let client: APIClient
    let host: String
    /// ルート相対パス。ルートは ""。
    let path: String
    /// ナビゲーションタイトル。
    let displayName: String

    @State private var entries: [FileEntry] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        content
            .background(Theme.background)
            .navigationTitle(displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await load() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .tint(Theme.accent)
                    .disabled(isLoading)
                }
            }
            .task { await load() }
            .refreshable { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && entries.isEmpty {
            loadingState
        } else if let errorMessage {
            errorState(errorMessage)
        } else if entries.isEmpty {
            emptyState
        } else {
            fileList
        }
    }

    private var fileList: some View {
        List {
            ForEach(entries) { entry in
                NavigationLink(value: entry) {
                    FileRow(entry: entry)
                }
                .listRowBackground(Theme.surface)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
    }

    // MARK: 状態表示

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("読み込み中…")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Theme.disconnected.opacity(0.85))
            Text("読み込みに失敗しました")
                .font(.headline)
                .foregroundStyle(Theme.primaryText)
            Text(message)
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
            Button {
                Task { await load() }
            } label: {
                Text("再試行")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "folder")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Theme.accent.opacity(0.6))
            Text("空のフォルダです")
                .font(.headline)
                .foregroundStyle(Theme.primaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: 通信

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let response = try await client.fileTree(path: path.isEmpty ? nil : path)
            entries = response.entries
        } catch {
            entries = []
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - FileRow
// ディレクトリ / ファイルの 1 行。アイコン・名前・（ファイルは）サイズ。

private struct FileRow: View {
    let entry: FileEntry

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.type == .dir ? "folder.fill" : iconForFile(entry.name))
                .foregroundStyle(entry.type == .dir ? Theme.accent : Theme.secondaryText)
                .frame(width: 22)
            Text(entry.name)
                .font(entry.type == .dir ? .body.weight(.medium) : Theme.monospacedSmall)
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            if entry.type == .file, let size = entry.size {
                Text(formatSize(size))
                    .font(.caption2)
                    .foregroundStyle(Theme.tertiaryText)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 2)
    }

    /// 拡張子からそれらしい SF Symbol を選ぶ（見た目のヒントのみ）。
    private func iconForFile(_ name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift", "ts", "tsx", "js", "jsx", "py", "rb", "go", "rs", "java", "kt", "c", "cpp", "h":
            return "chevron.left.forwardslash.chevron.right"
        case "json", "yml", "yaml", "toml", "xml", "plist":
            return "curlybraces"
        case "md", "markdown", "txt", "rtf":
            return "doc.text"
        case "png", "jpg", "jpeg", "gif", "svg", "webp", "heic":
            return "photo"
        case "sh", "zsh", "bash":
            return "terminal"
        default:
            return "doc"
        }
    }

    private func formatSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

// MARK: - Preview
#Preview("Browser") {
    FileBrowserView(host: "192.168.11.34:3000")
}
