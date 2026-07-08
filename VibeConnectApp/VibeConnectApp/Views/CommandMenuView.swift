import SwiftUI

// MARK: - CommandMenuView
// 入力欄で "/" を打つと入力欄の上に出るコマンドメニュー（画像#11 参考）。
// query は "/" 以降の文字列。選択でコマンド名（"model"/"clear"/"files"）を親へ返す。

struct SlashCommand: Identifiable {
    let id = UUID()
    let name: String     // 例: "model"
    let hint: String     // 説明
    let icon: String     // SF Symbol
}

struct CommandMenuView: View {
    let query: String
    var onSelect: (String) -> Void

    private static let all: [SlashCommand] = [
        SlashCommand(name: "model", hint: "モデル / effort を選択", icon: "cpu"),
        SlashCommand(name: "usage", hint: "使用状況・接続情報を表示", icon: "chart.bar"),
        SlashCommand(name: "diff", hint: "変更差分を表示", icon: "plus.forwardslash.minus"),
        SlashCommand(name: "files", hint: "ファイルを開く", icon: "folder"),
        SlashCommand(name: "settings", hint: "サーバー設定を開く", icon: "gearshape"),
        SlashCommand(name: "clear", hint: "新しいチャットを開始", icon: "square.and.pencil")
    ]

    private var filtered: [SlashCommand] {
        let q = query.lowercased()
        return q.isEmpty ? Self.all : Self.all.filter { $0.name.hasPrefix(q) }
    }

    var body: some View {
        if filtered.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(filtered.enumerated()), id: \.element.id) { index, cmd in
                    Button { onSelect(cmd.name) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: cmd.icon)
                                .foregroundStyle(Theme.accent)
                                .frame(width: 22)
                            Text("/\(cmd.name)")
                                .fontWeight(.semibold)
                                .foregroundStyle(Theme.primaryText)
                            Text(cmd.hint)
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    if index < filtered.count - 1 {
                        Divider().overlay(Theme.accent.opacity(0.08))
                    }
                }
            }
            .background(commandBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Theme.accent.opacity(0.12), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private var commandBackground: some View {
        Color.clear
            .interactiveGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

#Preview {
    CommandMenuView(query: "", onSelect: { _ in })
        .padding()
        .background(Theme.background)
}
