import SwiftUI

// MARK: - SessionListView
// 複数チャット（セッション）の一覧。新規作成・切替・削除・リネーム。
// シート/ドロワーとして提示される想定。親は store.activeID の変化に反応する。

struct SessionListView: View {
    @ObservedObject var store: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var renamingID: UUID?
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.sessions) { session in
                    sessionRow(session)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("チャット")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .alert("チャット名を変更", isPresented: renamingBinding) {
                TextField("名前", text: $renameText)
                Button("保存", action: commitRename)
                Button("キャンセル", role: .cancel) { renamingID = nil }
            }
        }
    }

    // MARK: 行
    @ViewBuilder
    private func sessionRow(_ session: ChatSession) -> some View {
        let isActive = session.id == store.activeID
        Button {
            store.select(session.id)
            dismiss()
        } label: {
            rowLabel(session, isActive: isActive)
        }
        .listRowBackground(isActive ? Theme.accent.opacity(0.12) : Color.clear)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                store.delete(session.id)
            } label: {
                Label("削除", systemImage: "trash")
            }
            Button {
                renamingID = session.id
                renameText = session.title
            } label: {
                Label("名前", systemImage: "pencil")
            }
            .tint(Theme.accent)
        }
    }

    private func rowLabel(_ session: ChatSession, isActive: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 16))
                .foregroundStyle(Theme.accent)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.displayTitle)
                    .font(.body)
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                Text(session.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    // MARK: ツールバー
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("閉じる") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                store.newSession()
                dismiss()
            } label: {
                Label("新規チャット", systemImage: "square.and.pencil")
            }
            .tint(Theme.accent)
        }
    }

    // MARK: リネーム
    private var renamingBinding: Binding<Bool> {
        Binding(
            get: { renamingID != nil },
            set: { if !$0 { renamingID = nil } }
        )
    }

    private func commitRename() {
        if let id = renamingID {
            store.rename(id, title: renameText)
        }
        renamingID = nil
    }
}

#Preview {
    SessionListView(store: .preview)
}
