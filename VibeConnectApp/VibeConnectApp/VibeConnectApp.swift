import SwiftUI

// MARK: - VibeConnectApp
// @main エントリ。TaskViewModel（Agent 5 実装, CONTRACTS.md §5）を単一のソースとして生成し、
// ConsoleChatView をルートに .environmentObject で注入する。
// 起動 / フォアグラウンド復帰時に viewModel.resumeIfNeeded() を呼び、
// 未完了タスクのポーリングを再開する（IMPLEMENTATION_PLAN §4.3）。

@main
struct VibeConnectApp: App {
    @StateObject private var viewModel = TaskViewModel()
    @StateObject private var sessionStore = SessionStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ConsoleChatView()
                .environmentObject(viewModel)
                .environmentObject(sessionStore)
                .onAppear {
                    viewModel.resumeIfNeeded()
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // フォアグラウンド復帰時に未完了タスクを再開
            if newPhase == .active {
                viewModel.resumeIfNeeded()
            }
        }
    }
}
