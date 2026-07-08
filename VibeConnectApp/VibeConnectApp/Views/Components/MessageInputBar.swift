import SwiftUI
import PhotosUI

// MARK: - MessageInputBar
// 丸みのある浮遊「アイランド」型の入力欄。
// - タップ反応つき Liquid Glass 背景（iOS 26+）/ フォールバック .ultraThinMaterial。
// - 写真ボタン（デバイスから画像を添付）/ モデルピル / "/" コマンドボタン / 送信ボタン。
// - "/" 入力でコマンドメニュー（/model・/clear・/files）を上部に表示。
// - 上下スワイプでキーボード開閉。
// 送信・モデル・コマンドのハンドラは親（ConsoleChatView）が注入。

struct MessageInputBar: View {
    @Binding var text: String
    var isProcessing: Bool
    var modelLabel: String
    var onSend: () -> Void
    var onModelTap: () -> Void
    var onCommand: (String) -> Void

    @FocusState private var isFocused: Bool
    @State private var photoItem: PhotosPickerItem?
    @State private var attachedImage: UIImage?

    private var canSend: Bool {
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return (hasText || attachedImage != nil) && !isProcessing
    }

    // "/" で始まり、まだ空白を含まない間はコマンド入力中とみなす
    private var isTypingCommand: Bool {
        text.hasPrefix("/") && !text.dropFirst().contains(" ")
    }
    private var commandQuery: String { String(text.dropFirst()) }

    var body: some View {
        VStack(spacing: 8) {
            if isTypingCommand {
                CommandMenuView(query: commandQuery, onSelect: handleCommand)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            island
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .animation(.easeOut(duration: 0.18), value: isTypingCommand)
        .simultaneousGesture(
            DragGesture(minimumDistance: 24).onEnded { value in
                if value.translation.height > 24 { isFocused = false }
                else if value.translation.height < -24 { isFocused = true }
            }
        )
    }

    // MARK: アイランド本体
    private var island: some View {
        VStack(spacing: 10) {
            if let img = attachedImage {
                attachmentChip(img)
            }

            TextField("Chat with Claude…", text: $text, axis: .vertical)
                .lineLimit(1...6)
                .font(.body)
                .foregroundStyle(Theme.primaryText)
                .focused($isFocused)
                .padding(.horizontal, 6)
                .padding(.top, 2)

            HStack(spacing: 10) {
                photoButton
                modelPill
                slashButton
                Spacer(minLength: 8)
                sendButton
            }
        }
        .padding(14)
        .modifier(IslandGlass())
    }

    // MARK: 添付プレビュー
    private func attachmentChip(_ img: UIImage) -> some View {
        HStack(spacing: 10) {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text("画像を添付")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
            Spacer()
            Button {
                attachedImage = nil
                photoItem = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
        .padding(8)
        .interactiveGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 写真（デバイスから添付）
    private var photoButton: some View {
        PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
            Image(systemName: "photo")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.primaryText)
                .frame(width: 34, height: 34)
                .contentShape(Circle())
                .interactiveGlass(in: Circle())
        }
        .onChange(of: photoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let ui = UIImage(data: data) {
                    await MainActor.run { attachedImage = ui }
                }
            }
        }
    }

    // MARK: "/" コマンド起動（モデルの右側）
    private var slashButton: some View {
        Button {
            if !text.hasPrefix("/") { text = "/" }
            isFocused = true
        } label: {
            Text("/")
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.primaryText)
                .frame(width: 34, height: 34)
                .contentShape(Circle())
                .interactiveGlass(in: Circle())
        }
        .buttonStyle(.plain)
    }

    private var modelPill: some View {
        Button(action: onModelTap) {
            HStack(spacing: 6) {
                Text(modelLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.secondaryText)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Capsule())
            .interactiveGlass(in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var sendButton: some View {
        Button(action: sendAction) {
            Image(systemName: isProcessing ? "hourglass" : "arrow.up")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(canSend ? Theme.accent : Theme.accent.opacity(0.35), in: Circle())
        }
        .disabled(!canSend)
        .animation(.easeInOut(duration: 0.15), value: canSend)
    }

    // MARK: アクション
    private func sendAction() {
        guard canSend else { return }
        onSend()
        attachedImage = nil
        photoItem = nil
        isFocused = false
    }

    private func handleCommand(_ name: String) {
        text = ""
        isFocused = false
        onCommand(name)
    }
}

// MARK: - アイランドの Liquid Glass 背景（タップ反応 ON）
private struct IslandGlass: ViewModifier {
    func body(content: Content) -> some View {
        content
            .interactiveGlass(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Theme.accent.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
    }
}

#Preview("Idle") {
    StatefulPreviewWrapper("") { binding in
        MessageInputBar(text: binding, isProcessing: false, modelLabel: "Opus 4.8 High",
                        onSend: {}, onModelTap: {}, onCommand: { _ in })
    }
}

#Preview("Command") {
    StatefulPreviewWrapper("/mo") { binding in
        MessageInputBar(text: binding, isProcessing: false, modelLabel: "Opus 4.8 High",
                        onSend: {}, onModelTap: {}, onCommand: { _ in })
    }
}

// プレビューで @Binding を扱うための小さなラッパー
struct StatefulPreviewWrapper<Value, Content: View>: View {
    @State private var value: Value
    private let content: (Binding<Value>) -> Content

    init(_ initialValue: Value, @ViewBuilder content: @escaping (Binding<Value>) -> Content) {
        _value = State(initialValue: initialValue)
        self.content = content
    }

    var body: some View { content($value) }
}
