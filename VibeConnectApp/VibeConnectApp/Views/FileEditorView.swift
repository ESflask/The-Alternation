import SwiftUI

// MARK: - FileEditorView
// ファイル 1 つを閲覧・編集する画面（CONTRACTS-FEATURES.md §D）。
//
// - `init(path:host:)`。host から APIClient を構築して readFile(path:) で内容を取得。
// - 等幅の編集可能 TextEditor（Theme.monospaced）で表示。
// - 変更を検知して「保存」ボタンを活性化し、writeFile(path:content:) で保存。
// - 保存の成否をトースト表示。
// - 読み取り専用トグル。truncated（2MB超/バイナリ）の場合は編集を無効化し警告表示。
// - TaskViewModel には依存しない。

struct FileEditorView: View {

    let path: String
    let host: String

    private let client: APIClient?

    @State private var content: String = ""
    /// 直近に読み込んだ／保存した内容。変更検知の基準。
    @State private var savedContent: String = ""
    @State private var truncated = false

    @State private var isLoading = true
    @State private var loadError: String?

    @State private var isReadOnly = false
    @State private var isSaving = false

    @State private var toast: Toast?
    @FocusState private var editorFocused: Bool

    init(path: String, host: String) {
        self.path = path
        self.host = host
        self.client = APIClient(host: host)
    }

    // MARK: 派生状態

    private var fileName: String {
        (path as NSString).lastPathComponent
    }

    /// 編集可能か（読み取り専用・truncated・ロード中・エラーで不可）。
    private var isEditable: Bool {
        !isReadOnly && !truncated && loadError == nil && !isLoading
    }

    private var hasChanges: Bool {
        content != savedContent
    }

    private var canSave: Bool {
        isEditable && hasChanges && !isSaving
    }

    var body: some View {
        bodyContent(for: client)
            .background(Theme.background)
            .navigationTitle(fileName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .overlay(alignment: .bottom) { toastView }
            .task { await load() }
    }

    @ViewBuilder
    private func bodyContent(for client: APIClient?) -> some View {
        if client == nil {
            invalidHostState
        } else if isLoading {
            loadingState
        } else if let loadError {
            errorState(loadError)
        } else {
            editor
        }
    }

    // MARK: エディタ本体

    private var editor: some View {
        VStack(spacing: 0) {
            if truncated {
                truncatedBanner
            } else if isReadOnly {
                readOnlyBanner
            }

            TextEditor(text: $content)
                .font(Theme.monospaced)
                .foregroundStyle(Theme.primaryText)
                .tint(Theme.accent)
                .scrollContentBackground(.hidden)
                .background(Theme.sunkenSurface)
                .disabled(!isEditable)
                .focused($editorFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(.horizontal, 4)
        }
    }

    private var truncatedBanner: some View {
        banner(icon: "exclamationmark.triangle.fill",
               tint: Theme.disconnected,
               text: "このファイルは大きすぎるか、バイナリの可能性があるため読み取り専用です。編集はできません。")
    }

    private var readOnlyBanner: some View {
        banner(icon: "lock.fill",
               tint: Theme.secondaryText,
               text: "読み取り専用モードです。編集するにはロックを解除してください。")
    }

    private func banner(icon: String, tint: Color, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(text)
                .font(.footnote)
                .foregroundStyle(Theme.primaryText)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.contentPadding)
        .padding(.vertical, 8)
        .background(tint.opacity(0.12))
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
            Text("ファイルを開けませんでした")
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

    private var invalidHostState: some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Theme.disconnected.opacity(0.8))
            Text("サーバーアドレスが不正です")
                .font(.headline)
                .foregroundStyle(Theme.primaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: ツールバー

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                editorFocused = false
                isReadOnly.toggle()
            } label: {
                Image(systemName: isReadOnly ? "lock.fill" : "lock.open")
            }
            .tint(Theme.accent)
            .disabled(truncated || isLoading || loadError != nil)
        }
        ToolbarItem(placement: .topBarTrailing) {
            saveButton
        }
    }

    @ViewBuilder
    private var saveButton: some View {
        if isSaving {
            ProgressView()
                .controlSize(.small)
        } else {
            Button {
                Task { await save() }
            } label: {
                Text("保存").fontWeight(.semibold)
            }
            .tint(Theme.accent)
            .disabled(!canSave)
        }
    }

    // MARK: トースト

    @ViewBuilder
    private var toastView: some View {
        if let toast {
            HStack(spacing: 8) {
                Image(systemName: toast.isSuccess ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .foregroundStyle(toast.isSuccess ? Theme.connected : Theme.disconnected)
                Text(toast.message)
                    .font(.footnote)
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(2)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(toastBackground)
            .padding(.bottom, 24)
            .padding(.horizontal, Theme.contentPadding)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var toastBackground: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
        if #available(iOS 26.0, *) {
            shape.fill(.clear).glassEffect(in: shape)
        } else {
            shape.fill(.ultraThinMaterial)
                .overlay(shape.stroke(Theme.secondaryText.opacity(0.15)))
        }
    }

    // MARK: 通信

    private func load() async {
        guard let client else { return }
        isLoading = true
        loadError = nil
        do {
            let response = try await client.readFile(path: path)
            content = response.content
            savedContent = response.content
            truncated = response.truncated
            if truncated { isReadOnly = true }
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    private func save() async {
        guard let client, canSave else { return }
        editorFocused = false
        isSaving = true
        let attempt = content
        do {
            let response = try await client.writeFile(path: path, content: attempt)
            if response.success {
                savedContent = attempt
                showToast(response.message.isEmpty ? "保存しました" : response.message, success: true)
            } else {
                showToast(response.message.isEmpty ? "保存に失敗しました" : response.message, success: false)
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            showToast(message, success: false)
        }
        isSaving = false
    }

    private func showToast(_ message: String, success: Bool) {
        let toast = Toast(message: message, isSuccess: success)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            self.toast = toast
        }
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.25)) {
                    if self.toast?.id == toast.id { self.toast = nil }
                }
            }
        }
    }
}

// MARK: - Toast モデル

private struct Toast: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let isSuccess: Bool
}

// MARK: - Preview
#Preview("Editor") {
    NavigationStack {
        FileEditorView(path: "src/index.ts", host: "192.168.11.34:3000")
    }
}
