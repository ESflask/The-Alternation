import SwiftUI

// MARK: - ModelPickerView
// モデル（Opus/Sonnet/Haiku/Fable）と effort（Low〜Max）を選ぶシート。
// 選択は TaskViewModel の @Published にバインドされ、次回送信時に claude へ渡る。

struct ModelPickerView: View {
    @Binding var selectedModel: String
    @Binding var selectedEffort: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("モデル") {
                    ForEach(AIModel.all) { model in
                        Button { selectedModel = model.id } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model.name)
                                        .foregroundStyle(Theme.primaryText)
                                    Text(model.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(Theme.secondaryText)
                                }
                                Spacer()
                                if selectedModel == model.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Theme.accent)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                    }
                }
                Section("思考の深さ (effort)") {
                    ForEach(EffortLevel.allCases) { level in
                        Button { selectedEffort = level.rawValue } label: {
                            HStack {
                                Text(level.label).foregroundStyle(Theme.primaryText)
                                Spacer()
                                if selectedEffort == level.rawValue {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Theme.accent)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                    }
                }
            }
            .navigationTitle("モデル選択")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    ModelPickerView(selectedModel: .constant("opus"), selectedEffort: .constant("high"))
}
