import SwiftUI

// MARK: - DiffInspectorView
// コード差分ビュー（IMPLEMENTATION_PLAN §4.2 B）。
// viewModel.diffLines を行ごとに色分けレンダリング（+緑 / -赤 / ヘッダ / 通常）。
// 横スクロール可・等幅。フッターに Commit ボタン、変更なし時は空状態。
//
// 依存する TaskViewModel（CONTRACTS.md §5）:
//   - viewModel.diffLines        … 描画対象
//   - viewModel.hasChanges       … 空状態 / Commit活性
//   - viewModel.isProcessing     … Commit中の抑止
//   - viewModel.loadDiff()       … 表示時に最新diffを取得
//   - viewModel.commit(message:) … コミット実行

struct DiffInspectorView: View {
    @EnvironmentObject private var viewModel: TaskViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showCommitSheet = false
    @State private var commitMessage = ""
    @State private var isCommitting = false

    var body: some View {
        Group {
            if viewModel.hasChanges && !viewModel.diffLines.isEmpty {
                diffContent
            } else {
                emptyState
            }
        }
        .background(Theme.background)
        .navigationTitle("変更差分")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if viewModel.hasChanges {
                commitFooter
            }
        }
        .task {
            await viewModel.loadDiff()
        }
        .sheet(isPresented: $showCommitSheet) {
            commitSheet
        }
    }

    // MARK: Diff本体
    private var diffContent: some View {
        GeometryReader { geo in
            ScrollView([.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(viewModel.diffLines) { line in
                        DiffLineRow(line: line, minWidth: geo.size.width)
                    }
                }
            }
            .background(Theme.sunkenSurface)
        }
    }

    // MARK: 空状態
    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Theme.connected.opacity(0.8))
            Text("変更はありません")
                .font(.headline)
                .foregroundStyle(Theme.primaryText)
            Text("Claude Code による差分が生成されると、\nここに色分けで表示されます。")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: フッター（Commitボタン）
    private var commitFooter: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                commitMessage = ""
                showCommitSheet = true
            } label: {
                HStack(spacing: 8) {
                    if isCommitting {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                    }
                    Text(isCommitting ? "適用中…" : "この変更を適用（Commit）")
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            }
            .disabled(isCommitting || viewModel.isProcessing)
            .padding(Theme.contentPadding)
        }
        .background(.bar)
    }

    // MARK: コミットメッセージ入力シート
    private var commitSheet: some View {
        NavigationStack {
            Form {
                Section("コミットメッセージ") {
                    TextField("例: style: update button color to blue", text: $commitMessage, axis: .vertical)
                        .lineLimit(2...5)
                        .font(Theme.monospacedSmall)
                }
                Section {
                    Text("このメッセージで Mac 側の git リポジトリにコミットします。")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .navigationTitle("変更を確定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { showCommitSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Commit") { performCommit() }
                        .disabled(commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: アクション
    private func performCommit() {
        let message = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        showCommitSheet = false
        Task {
            isCommitting = true
            await viewModel.commit(message: message)
            isCommitting = false
            // コミット後は変更が無くなる想定。前画面へ戻る。
            if !viewModel.hasChanges {
                dismiss()
            }
        }
    }
}

// MARK: - Preview
#Preview("With changes") {
    NavigationStack {
        DiffInspectorView()
            .environmentObject(TaskViewModel.preview)
    }
}
