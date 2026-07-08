import Foundation
import Combine

// MARK: - TaskViewModel
// CONTRACTS.md §5 の public インターフェースを完全一致で実装する。
// 状態を一元管理し、APIClient を用いた通信・2秒ポーリング・自動復旧を担う。
// すべての @Published 更新はメインアクター上で行う（@MainActor）。

@MainActor
final class TaskViewModel: ObservableObject {

    // MARK: 接続・状態
    /// 例: "100.101.102.103"。変更時は UserDefaults に永続化する。
    @Published var serverHost: String {
        didSet { defaults.set(serverHost, forKey: Keys.serverHost) }
    }
    @Published var isConnected: Bool = false        // ヘッダの Green/Red
    @Published var isProcessing: Bool = false       // スピナー表示
    @Published var currentStatus: TaskStatus?       // 現在タスクの状態

    /// 選択中のモデル / effort（claude --model / --effort）。変更時に永続化。
    @Published var selectedModel: String {
        didSet { defaults.set(selectedModel, forKey: Keys.model) }
    }
    @Published var selectedEffort: String {
        didSet { defaults.set(selectedEffort, forKey: Keys.effort) }
    }

    // MARK: データ
    @Published var messages: [ChatMessage] = []     // チャットタイムライン
    @Published var diffLines: [DiffLine] = []       // パース済み diff
    @Published var hasChanges: Bool = false         // diff 有無 → Commit ボタン活性
    @Published var errorMessage: String?            // 汎用エラー表示

    // MARK: - 内部状態

    private enum Keys {
        static let serverHost = "vibe.serverHost"
        static let activeTaskId = "vibe.activeTaskId"
        static let model = "vibe.model"
        static let effort = "vibe.effort"
    }

    private let defaults: UserDefaults

    /// ポーリング用の単一 Task。重複起動を防ぐため常にこの1本を管理する。
    private var pollingTask: Task<Void, Never>?

    /// ポーリング中に逐次更新する assistant メッセージの id（左側ログ表示用）。
    private var streamingMessageID: UUID?

    /// ポーリング間隔（2秒）。CONTRACTS.md §5。
    private let pollIntervalNanos: UInt64 = 2_000_000_000

    // MARK: - 初期化

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // serverHost 初期値は UserDefaults から。無ければ空。
        // ※ init 内の代入では didSet は発火しない。
        self.serverHost = defaults.string(forKey: Keys.serverHost) ?? ""
        self.selectedModel = defaults.string(forKey: Keys.model) ?? "opus"
        self.selectedEffort = defaults.string(forKey: Keys.effort) ?? "high"
    }

    /// serverHost から APIClient を組み立てるヘルパ。未設定/不正なら nil。
    private var apiClient: APIClient? {
        APIClient(host: serverHost)
    }

    // MARK: - アクション（public / CONTRACTS.md §5）

    /// 指示送信 → タスク生成 → 2秒ポーリング開始。
    func send(instruction: String) {
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard apiClient != nil else {
            errorMessage = APIError.invalidHost.errorDescription
            return
        }

        // 1. ユーザー指示をタイムラインへ。
        messages.append(ChatMessage(role: .user, text: trimmed))
        isProcessing = true
        currentStatus = .processing
        errorMessage = nil

        // 2. createTask → task_id 取得 → 永続化 → ポーリング開始。
        Task { [weak self] in
            guard let self, let client = self.apiClient else { return }
            do {
                let response = try await client.createTask(instruction: trimmed,
                                                           model: self.selectedModel,
                                                           effort: self.selectedEffort)
                self.defaults.set(response.task_id, forKey: Keys.activeTaskId)
                self.startPolling(taskId: response.task_id)
            } catch {
                self.isProcessing = false
                self.currentStatus = .failed
                self.errorMessage = Self.describe(error)
            }
        }
    }

    /// /health で疎通確認し isConnected を更新。失敗時 false。
    func checkConnection() async {
        guard let client = apiClient else {
            isConnected = false
            return
        }
        do {
            isConnected = try await client.health()
        } catch {
            isConnected = false
        }
    }

    /// GET /api/git/diff → hasChanges 更新、diff を DiffParser で diffLines に変換。
    func loadDiff() async {
        guard let client = apiClient else {
            errorMessage = APIError.invalidHost.errorDescription
            return
        }
        do {
            let response = try await client.fetchDiff()
            hasChanges = response.has_changes
            diffLines = response.has_changes ? DiffParser.parse(response.diff) : []
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    /// POST /api/git/commit。成功なら diff をクリアし結果をタイムラインへ。失敗は errorMessage。
    func commit(message: String) async {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "コミットメッセージを入力してください。"
            return
        }
        guard let client = apiClient else {
            errorMessage = APIError.invalidHost.errorDescription
            return
        }
        do {
            let response = try await client.commit(message: trimmed)
            if response.success {
                diffLines = []
                hasChanges = false
                messages.append(ChatMessage(role: .assistant, text: response.message))
            } else {
                errorMessage = response.message
            }
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    /// 起動 / フォアグラウンド復帰時に呼ぶ。未完了 task があればポーリング再開し、
    /// あわせて疎通確認をトリガーする（IMPLEMENTATION_PLAN §4.3 自動復旧）。
    func resumeIfNeeded() {
        // 常に疎通確認を走らせる。
        Task { [weak self] in await self?.checkConnection() }

        // 既にポーリング中なら二重起動しない。
        guard pollingTask == nil else { return }
        guard let taskId = defaults.string(forKey: Keys.activeTaskId), !taskId.isEmpty else { return }
        guard apiClient != nil else { return }

        startPolling(taskId: taskId)
    }

    // MARK: - ポーリング（内部）

    /// 2秒間隔のポーリングを開始する。既存ポーリングは必ずキャンセルして重複を防ぐ。
    private func startPolling(taskId: String) {
        pollingTask?.cancel()

        // 逐次更新する assistant メッセージを用意（復帰時に既存があれば再利用）。
        let assistantID = ensureStreamingMessage()

        isProcessing = true
        currentStatus = .processing

        pollingTask = Task { [weak self] in
            await self?.pollLoop(taskId: taskId, assistantID: assistantID)
        }
    }

    /// ポーリング本体。@MainActor 上で回り、ネットワーク待ちの間だけ離脱する。
    private func pollLoop(taskId: String, assistantID: UUID) async {
        guard let client = apiClient else {
            finishTask(status: .failed, error: APIError.invalidHost.errorDescription)
            return
        }

        while !Task.isCancelled {
            do {
                let status = try await client.fetchTask(id: taskId)

                // assistant ログ（左側）と currentStatus を更新。
                updateAssistantMessage(id: assistantID, text: status.logs)
                currentStatus = status.status

                switch status.status {
                case .processing:
                    break   // 継続
                case .completed:
                    finishTask(status: .completed, error: nil)
                    await loadDiff()   // 完了時は自動で diff 取得
                    return
                case .failed:
                    finishTask(status: .failed, error: status.error)
                    return
                }
            } catch {
                // 未知の task_id は復旧不能 → 停止。
                if case let APIError.httpError(code, _) = error, code == 404 {
                    finishTask(status: .failed, error: "タスクが見つかりません（task not found）。")
                    return
                }
                // 一時的な通信エラーはメッセージだけ出して継続（自動復旧）。
                errorMessage = Self.describe(error)
            }

            try? await Task.sleep(nanoseconds: pollIntervalNanos)
        }
    }

    /// タスク終了処理。ポーリング参照を解放し、activeTaskId をクリアする。
    /// ※ 現在の pollLoop 自身からも呼ばれるため cancel はしない（completed 時の loadDiff を通すため）。
    private func finishTask(status: TaskStatus, error: String?) {
        isProcessing = false
        currentStatus = status
        streamingMessageID = nil
        pollingTask = nil
        defaults.removeObject(forKey: Keys.activeTaskId)
        if status == .failed {
            errorMessage = error ?? "タスクが失敗しました。"
        }
    }

    /// 逐次更新用の assistant メッセージを確保し、その id を返す。
    private func ensureStreamingMessage() -> UUID {
        if let existing = streamingMessageID,
           messages.contains(where: { $0.id == existing }) {
            return existing
        }
        let message = ChatMessage(role: .assistant, text: "")
        messages.append(message)
        streamingMessageID = message.id
        return message.id
    }

    /// assistant メッセージのテキストを最新ログで置き換える。
    private func updateAssistantMessage(id: UUID, text: String) {
        guard !text.isEmpty,
              let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].text = text
    }

    // MARK: - エラー整形

    private static func describe(_ error: Error) -> String {
        if let apiError = error as? APIError {
            return apiError.errorDescription ?? "通信エラーが発生しました。"
        }
        return error.localizedDescription
    }

    // MARK: - プレビュー用（Agent 4 の #Preview が使用）

    static var preview: TaskViewModel {
        // 実 UserDefaults を汚さないよう専用スイートを使う。
        let previewDefaults = UserDefaults(suiteName: "vibe.preview") ?? .standard
        let vm = TaskViewModel(defaults: previewDefaults)
        vm.serverHost = MockData.serverHost
        vm.isConnected = true
        vm.isProcessing = false
        vm.currentStatus = .completed
        vm.messages = MockData.messages
        vm.diffLines = MockData.diffLines
        vm.hasChanges = true
        return vm
    }
}
