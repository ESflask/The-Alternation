import Foundation

// MARK: - MockData
// プレビュー用のダミーデータ。実通信は行わず、各 View の #Preview が
// 単体で「きれいに」表示されることを担保するためのもの（IMPLEMENTATION_PLAN §6 ステップ4）。

enum MockData {

    // MARK: サンプルの生 git diff 文字列
    /// git diff の生出力を模した文字列。DiffParser.parse に通して使う。
    static let rawDiff: String = """
    diff --git a/src/Views/MainView.swift b/src/Views/MainView.swift
    index 3f8a1c2..9b2d4e7 100644
    --- a/src/Views/MainView.swift
    +++ b/src/Views/MainView.swift
    @@ -8,10 +8,10 @@ struct MainView: View {
         var body: some View {
             VStack(spacing: 16) {
                 Text("VibeConnect")
    -                .font(.title)
    -                .foregroundColor(.gray)
    +                .font(.largeTitle.bold())
    +                .foregroundColor(.primary)

    -            Button("Click Me") {}
    -                .background(Color.red)
    +            Button("実行") { runTask() }
    +                .background(Color.blue)
    +                .foregroundColor(.white)
             }
             .padding()
         }
    @@ -30,4 +30,8 @@ struct MainView: View {
         func runTask() {
             print("task started")
         }
    +
    +    func reset() {
    +        state = .idle
    +    }
     }
    """

    // MARK: パース済み diff 行
    static let diffLines: [DiffLine] = DiffParser.parse(rawDiff)

    // MARK: 空の diff（変更なし状態のプレビュー用）
    static let emptyDiffLines: [DiffLine] = []

    // MARK: サンプルのチャットタイムライン
    /// ユーザー指示（右）と Claude Code 処理ログ風（左）の混在タイムライン。
    static let messages: [ChatMessage] = [
        ChatMessage(
            role: .user,
            text: "src/Views/MainView.swift のボタンの色をシステムブルーに変更して、ラベルを『実行』にしてテストを走らせて。",
            timestamp: date(minutesAgo: 6)
        ),
        ChatMessage(
            role: .assistant,
            text: """
            ● Reading src/Views/MainView.swift
            ● Editing button style (Color.red → Color.blue)
            ● Updating label "Click Me" → "実行"
            ● Running: swift test
              Compiling VibeConnectApp ... ok
              Test Suite 'All tests' passed (12 tests, 0 failures)
            ✔ 変更が完了しました。差分を確認してください。
            """,
            timestamp: date(minutesAgo: 5)
        ),
        ChatMessage(
            role: .user,
            text: "reset() ヘルパーも追加しておいて。",
            timestamp: date(minutesAgo: 2)
        ),
        ChatMessage(
            role: .assistant,
            text: """
            ● Adding func reset() to MainView
            ● Running: swift build
              Build complete! (3.42s)
            ✔ reset() を追加しました。
            """,
            timestamp: date(minutesAgo: 1)
        ),
    ]

    // MARK: 処理中プレビュー用（末尾にログが流れている途中を模す）
    static let messagesWhileProcessing: [ChatMessage] = [
        ChatMessage(
            role: .user,
            text: "認証まわりをリファクタして、ユニットテストも追加して。",
            timestamp: date(minutesAgo: 1)
        ),
        ChatMessage(
            role: .assistant,
            text: """
            ● Scanning src/Auth/ ...
            ● Refactoring AuthManager.login()
            ● Generating AuthManagerTests.swift
              Compiling ...
            """,
            timestamp: date(minutesAgo: 0)
        ),
    ]

    // MARK: サーバーホスト（Tailscale IP 例）
    static let serverHost = "100.101.102.103"

    // MARK: - Helpers
    private static func date(minutesAgo: Int) -> Date {
        Calendar.current.date(byAdding: .minute, value: -minutesAgo, to: Date()) ?? Date()
    }
}
