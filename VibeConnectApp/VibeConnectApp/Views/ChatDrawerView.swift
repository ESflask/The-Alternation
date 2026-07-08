import SwiftUI

// MARK: - ChatDrawerView
// 左からスライドインするチャット履歴サイドバー（検索欄つき、画像#12 参考）。
// スワイプ開閉・幅・オーバーレイ配置は親（ConsoleChatView）が担当。ここは中身のみ。

struct ChatDrawerView: View {
    @ObservedObject var store: SessionStore
    var onClose: () -> Void
    var onSelect: (UUID) -> Void
    var onSettings: () -> Void

    @State private var searchText = ""

    private var filtered: [ChatSession] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        let base = store.sessions.sorted { $0.createdAt > $1.createdAt }
        guard !q.isEmpty else { return base }
        return base.filter { $0.displayTitle.lowercased().contains(q) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            searchField
            Divider().overlay(Theme.accent.opacity(0.08))
            list
            newChatButton
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(drawerBackground.ignoresSafeArea())
    }

    // MARK: ヘッダ
    private var header: some View {
        HStack {
            Text("The Alternation")
                .font(.system(.title2, design: .serif).weight(.semibold))
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 8)
            // 近接する 歯車 と 三本線 は 1 本の分割ガラスバーに集約
            GlassSegmentedButtons(segments: [
                GlassSegment(icon: "gearshape", action: onSettings),
                GlassSegment(icon: "line.3.horizontal", action: onClose)
            ])
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: 検索
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.secondaryText)
            TextField("チャットを検索", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(Theme.primaryText)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.tertiaryText)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .interactiveGlass(in: Capsule())
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: 一覧
    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                Text("Recents")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                ForEach(filtered) { session in
                    drawerRow(session)
                }
            }
            .padding(.bottom, 12)
        }
    }

    private func drawerRow(_ session: ChatSession) -> some View {
        let isActive = session.id == store.activeID
        return Button {
            onSelect(session.id)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "bubble.left")
                    .font(.system(size: 13))
                    .foregroundStyle(isActive ? Theme.accent : Theme.secondaryText)
                Text(session.displayTitle)
                    .font(.subheadline)
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
            .background(isActive ? Theme.accent.opacity(0.14) : Color.clear)
            .contentShape(Rectangle())
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { store.delete(session.id) } label: {
                Label("削除", systemImage: "trash")
            }
        }
    }

    // MARK: 新規チャット
    private var newChatButton: some View {
        Button {
            let s = store.newSession()
            onSelect(s.id)
        } label: {
            HStack {
                Image(systemName: "plus")
                Text("New chat").fontWeight(.semibold)
            }
            .foregroundStyle(Theme.primaryText)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .contentShape(Capsule())
            .interactiveGlass(in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private var drawerBackground: some View {
        if #available(iOS 26.0, *) {
            Theme.background.glassEffect(in: Rectangle())
        } else {
            Theme.background
        }
    }
}

#Preview {
    ChatDrawerView(store: .preview, onClose: {}, onSelect: { _ in }, onSettings: {})
}
