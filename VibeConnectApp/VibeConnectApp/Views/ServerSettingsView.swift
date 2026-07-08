import SwiftUI

// MARK: - ServerSettingsView
// Mac サーバー（Tailscale IP / 同一Wi-Fi の LAN IP）のアドレスを入力・保存する設定シート。
// 入力値は TaskViewModel.serverHost に反映され、UserDefaults(vibe.serverHost) に永続化される。
// ここが無いと serverHost が空のまま「未設定 / サーバーアドレスが不正」になる。

struct ServerSettingsView: View {
    @EnvironmentObject private var viewModel: TaskViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var draftHost = ""
    @State private var checking = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("例: 192.168.11.34", text: $draftHost)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .font(Theme.hostFont)
                        .submitLabel(.done)
                        .onSubmit(test)
                } header: {
                    Text("Mac サーバーのアドレス")
                } footer: {
                    Text("Tailscale IP か、同一Wi-Fi の LAN IP を入力してください。スキーム(http://)とポートは省略可（既定 :3000）。例: 192.168.11.34")
                }

                Section {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(viewModel.isConnected ? Theme.connected : Theme.disconnected)
                            .frame(width: 10, height: 10)
                        Text(viewModel.isConnected ? "接続OK" : "未接続")
                            .foregroundStyle(Theme.secondaryText)
                        Spacer()
                        Button(action: test) {
                            if checking {
                                ProgressView()
                            } else {
                                Text("接続テスト")
                            }
                        }
                        .disabled(trimmed.isEmpty || checking)
                    }
                    if let error = viewModel.errorMessage, !error.isEmpty {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(Theme.disconnected)
                    }
                }
            }
            .navigationTitle("サーバー設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        viewModel.serverHost = trimmed
                        dismiss()
                    }
                    .disabled(trimmed.isEmpty)
                }
            }
            .onAppear { draftHost = viewModel.serverHost }
        }
    }

    private var trimmed: String {
        draftHost.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 入力ホストを保存して疎通確認する。
    private func test() {
        viewModel.serverHost = trimmed
        guard !trimmed.isEmpty else { return }
        checking = true
        Task {
            await viewModel.checkConnection()
            checking = false
        }
    }
}

#Preview {
    ServerSettingsView()
        .environmentObject(TaskViewModel.preview)
}
