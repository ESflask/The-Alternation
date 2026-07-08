import SwiftUI

// MARK: - UsageView
// "/usage" コマンドで開くシート。
// 接続/モデル/チャット統計に加え、Claude Code のローカルログ由来の使用量（トークン・推定コスト）を表示する。
// 集計範囲は 全体 / vibe-sandbox を切替可能（GET /api/usage?scope=）。

struct UsageView: View {
    let modelName: String
    let effortLabel: String
    let host: String
    let isConnected: Bool
    let sessionCount: Int
    let messageCount: Int

    @Environment(\.dismiss) private var dismiss

    @State private var scope = "all"           // "all" | "sandbox"
    @State private var usage: UsageResponse?
    @State private var loading = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            List {
                scopePicker

                usageSection

                if let usage, !usage.byModel.isEmpty {
                    byModelSection(usage)
                }

                Section("接続 / 設定") {
                    row("サーバー", host.isEmpty ? "未設定" : host)
                    HStack {
                        Text("状態").foregroundStyle(Theme.primaryText)
                        Spacer()
                        HStack(spacing: 6) {
                            Circle().fill(isConnected ? Theme.connected : Theme.disconnected)
                                .frame(width: 9, height: 9)
                            Text(isConnected ? "接続中" : "切断").foregroundStyle(Theme.secondaryText)
                        }
                    }
                    row("モデル", "\(modelName) / \(effortLabel)")
                    row("チャット数", "\(sessionCount)")
                    row("メッセージ総数", "\(messageCount)")
                }

                if let note = usage?.note {
                    Section {
                        Text(note)
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
            }
            .navigationTitle("使用状況")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
            }
            .task(id: scope) { await load() }
        }
        .presentationDetents([.large])
    }

    // MARK: 範囲切替
    private var scopePicker: some View {
        Section {
            Picker("集計範囲", selection: $scope) {
                Text("全体").tag("all")
                Text("vibe-sandbox").tag("sandbox")
            }
            .pickerStyle(.segmented)
        } footer: {
            Text("「全体」= このMacの全 Claude Code 使用量／「vibe-sandbox」= このアプリ経由分。")
        }
    }

    // MARK: 使用量（期間別）
    @ViewBuilder
    private var usageSection: some View {
        Section("使用量（推定）") {
            if loading {
                HStack { ProgressView().controlSize(.small); Text("集計中…").foregroundStyle(Theme.secondaryText) }
            } else if let e = errorText {
                Text(e).font(.footnote).foregroundStyle(Theme.disconnected)
            } else if let p = usage?.periods {
                periodRow("今日", p.today)
                periodRow("直近7日", p.last7d)
                periodRow("今月", p.thisMonth)
                periodRow("合計（保存ログ）", p.allTime)
            } else {
                Text("データがありません。").foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private func periodRow(_ label: String, _ b: UsageResponse.Bucket) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).foregroundStyle(Theme.primaryText)
                Spacer()
                Text(cost(b.costUSD))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
            Text("\(b.requests) req ・ out \(fmt(b.outputTokens)) ・ in \(fmt(b.inputTokens)) ・ cache \(fmt(b.cacheReadTokens))")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    // MARK: モデル別
    private func byModelSection(_ u: UsageResponse) -> some View {
        Section("モデル別（合計）") {
            ForEach(u.byModel) { m in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(m.model.capitalized).foregroundStyle(Theme.primaryText)
                        Spacer()
                        Text(cost(m.costUSD))
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    Text("\(m.requests) req ・ out \(fmt(m.outputTokens)) ・ in \(fmt(m.inputTokens))")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
    }

    // MARK: - Helpers
    private func load() async {
        guard let client = APIClient(host: host) else { errorText = "サーバー未設定"; return }
        loading = true; errorText = nil
        do { usage = try await client.fetchUsage(scope: scope) }
        catch { errorText = (error as? APIError)?.errorDescription ?? error.localizedDescription }
        loading = false
    }

    private func fmt(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }
    private func cost(_ c: Double) -> String {
        c > 0 ? String(format: "≈ $%.2f", c) : "$0.00"
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.primaryText)
            Spacer()
            Text(value).foregroundStyle(Theme.secondaryText).multilineTextAlignment(.trailing)
        }
    }
}

#Preview {
    UsageView(modelName: "Opus 4.8", effortLabel: "High",
              host: "192.168.11.34", isConnected: true,
              sessionCount: 5, messageCount: 12)
}
