import SwiftUI

// MARK: - ConnectionIndicator
// ヘッダに置く接続状態インジケータ。Green(接続) / Red(未接続) のドット + ホスト名。

struct ConnectionIndicator: View {
    let isConnected: Bool
    let host: String

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isConnected ? Theme.connected : Theme.disconnected)
                .frame(width: 10, height: 10)
                .overlay(
                    Circle()
                        .stroke(isConnected ? Theme.connected : Theme.disconnected, lineWidth: 6)
                        .opacity(isConnected ? 0.25 : 0.0)
                        .scaleEffect(1.6)
                )
                .accessibilityLabel(isConnected ? "接続中" : "未接続")

            VStack(alignment: .leading, spacing: 1) {
                Text(host.isEmpty ? "未設定" : host)
                    .font(Theme.hostFont)
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                Text(isConnected ? "Connected" : "Disconnected")
                    .font(.caption2)
                    .foregroundStyle(isConnected ? Theme.connected : Theme.disconnected)
            }
        }
    }
}

#Preview("Connected") {
    ConnectionIndicator(isConnected: true, host: "100.101.102.103")
        .padding()
}

#Preview("Disconnected") {
    ConnectionIndicator(isConnected: false, host: "100.101.102.103")
        .padding()
}
