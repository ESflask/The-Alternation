import SwiftUI

// MARK: - ConsoleChatView
// メイン画面。ヘッダの接続インジケータ / チャットタイムライン / 処理中スピナー /
// 浮遊アイランド入力欄 / 左ドロワー(履歴+検索) / モデル選択 / コマンド を持つ。
//
// 左ドロワーは「プッシュ式」＋「指追従」:
//   ・画面左端からの右スワイプで開く。ドロワーは指の移動に同期して出てくる。
//   ・開くと右のチャット面が同じ幅だけ右へ押し出される（上下にはずれない）。
//   ・開いている時に左へ引いて指を離すと、閾値を超えていれば即座に完全に閉じる。
//   ・左端の横ホバー中は上下スクロールを無効化。開き始めにキーボードは自動で畳む。

struct ConsoleChatView: View {
    @EnvironmentObject private var viewModel: TaskViewModel
    @EnvironmentObject private var sessionStore: SessionStore

    @State private var inputText = ""
    @State private var showDiff = false
    @State private var showSettings = false
    @State private var showFiles = false
    @State private var showModelPicker = false
    @State private var showUsage = false

    // ドロワー状態（プッシュ式・指追従）
    @State private var drawerOpen = false
    @State private var dragProgress: CGFloat? = nil   // ドラッグ中のみ 0...1
    @State private var edgeDragActive = false         // 左端横ドラッグ中はスクロール無効

    private let bottomAnchor = "chat.bottom.anchor"
    private let drawerFraction: CGFloat = 1.0   // 展開時は画面右端まで＝全幅
    private let edgeWidth: CGFloat = 40

    private var canShowDiff: Bool {
        viewModel.hasChanges || viewModel.currentStatus == .completed
    }

    private var modelLabel: String {
        modelPillLabel(model: viewModel.selectedModel, effort: viewModel.selectedEffort)
    }

    var body: some View {
        GeometryReader { geo in
            let drawerWidth = geo.size.width * drawerFraction
            let progress = dragProgress ?? (drawerOpen ? 1 : 0)

            ZStack(alignment: .leading) {
                // 左：ドロワー（progress に応じて左からスライドイン。上下には動かさない）
                ChatDrawerView(
                    store: sessionStore,
                    onClose: closeDrawer,
                    onSelect: { id in sessionStore.select(id); closeDrawer() },
                    onSettings: { closeDrawer(); showSettings = true },
                    onSelectClaude: { dto in Task { await importAndOpen(dto) } }
                )
                .frame(width: drawerWidth)
                .offset(x: -drawerWidth * (1 - progress))
                .zIndex(0)

                // 右：メイン（progress に同期して右へ押し出される）
                // ※ 暗幕は .offset の前に重ねる。後だと暗幕だけ動かず画面全体
                //   （＝ドロワーの上）を覆い、ボタンのタップを奪って閉じてしまう。
                mainStack
                    .overlay {
                        if progress > 0.01 {
                            Color.black.opacity(0.35 * progress)
                                .ignoresSafeArea()
                                .allowsHitTesting(drawerOpen && dragProgress == nil)
                                .onTapGesture { closeDrawer() }
                        }
                    }
                    .offset(x: drawerWidth * progress)
                    .zIndex(1)
            }
            .simultaneousGesture(drawerDrag(drawerWidth: drawerWidth))
        }
        .tint(Theme.accent)
        .task {
            await viewModel.checkConnection()
            await loadClaudeHistory()   // 起動時に Claude Code 履歴を Recents 下へ読み込む
        }
        .onChange(of: viewModel.messages) { _, newMessages in
            sessionStore.updateActiveMessages(newMessages)
        }
        .onChange(of: sessionStore.activeID) { _, _ in
            viewModel.messages = sessionStore.activeSession?.messages ?? []
        }
        .onChange(of: viewModel.currentStatus) { _, status in
            // やり取り完了時、タイトル未設定なら Claude に自動命名させる。
            guard status == .completed else { return }
            Task { await maybeAutoTitle() }
        }
        .sheet(isPresented: $showModelPicker) {
            ModelPickerView(selectedModel: $viewModel.selectedModel,
                            selectedEffort: $viewModel.selectedEffort)
        }
        .sheet(isPresented: $showUsage) {
            UsageView(
                modelName: AIModel.named(viewModel.selectedModel).name,
                effortLabel: EffortLevel(rawValue: viewModel.selectedEffort)?.label
                    ?? viewModel.selectedEffort,
                host: viewModel.serverHost,
                isConnected: viewModel.isConnected,
                sessionCount: sessionStore.sessions.count,
                messageCount: sessionStore.sessions.reduce(0) { $0 + $1.messages.count }
            )
        }
    }

    // MARK: メイン（NavigationStack）
    private var mainStack: some View {
        NavigationStack {
            timeline
                .background(Theme.background)
                .safeAreaInset(edge: .bottom, spacing: 0) { bottomArea }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .navigationDestination(isPresented: $showDiff) { DiffInspectorView() }
                .navigationDestination(isPresented: $showFiles) {
                    FileBrowserView(host: viewModel.serverHost)
                }
                .sheet(isPresented: $showSettings) { ServerSettingsView() }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { openDrawer() } label: {
                Image(systemName: "line.3.horizontal")
            }
            .tint(Theme.accent)
        }
        ToolbarItem(placement: .principal) {
            ConnectionIndicator(isConnected: viewModel.isConnected, host: viewModel.serverHost)
        }
        // 📁ファイル と ±差分 を 1つの「ターミナル」メニューボタンに集約
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button { showFiles = true } label: {
                    Label("ファイルを開く", systemImage: "folder")
                }
                Button { showDiff = true } label: {
                    Label("変更差分を表示", systemImage: "plus.forwardslash.minus")
                }
                .disabled(!canShowDiff)
            } label: {
                Image(systemName: "terminal")
            }
            .tint(Theme.accent)
        }
    }

    // MARK: タイムライン
    private var timeline: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Theme.bubbleSpacing) {
                    if viewModel.messages.isEmpty {
                        emptyState
                    } else {
                        ForEach(viewModel.messages) { message in
                            ChatBubble(message: message).id(message.id)
                        }
                    }
                    if viewModel.isProcessing { processingRow }
                    Color.clear.frame(height: 1).id(bottomAnchor)
                }
                .padding(.horizontal, Theme.contentPadding)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollDisabled(edgeDragActive)   // 左端の横ホバー中は上下スクロールを止める
            .onChange(of: viewModel.messages) { _, _ in scrollToBottom(proxy) }
            .onChange(of: viewModel.isProcessing) { _, _ in scrollToBottom(proxy) }
            .onAppear { scrollToBottom(proxy, animated: false) }
        }
    }

    private var processingRow: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("Claude Code が処理中…")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.surface, in: Capsule())
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "terminal")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Theme.accent.opacity(0.7))
            Text("The Alternation を始めよう")
                .font(.headline)
                .foregroundStyle(Theme.primaryText)
            Text("下の入力欄に大雑把な指示を送ると、\nMac上の Claude Code が実行します。")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    // MARK: 下部（エラーバナー + 入力アイランド）※diffCTAは右上ボタンに集約
    private var bottomArea: some View {
        VStack(spacing: 0) {
            if let error = viewModel.errorMessage, !error.isEmpty {
                errorBanner(error)
            }
            MessageInputBar(
                text: $inputText,
                isProcessing: viewModel.isProcessing,
                modelLabel: modelLabel,
                onSend: send,
                onModelTap: { showModelPicker = true },
                onCommand: handleCommand
            )
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.disconnected)
            Text(message)
                .font(.footnote)
                .foregroundStyle(Theme.primaryText)
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, Theme.contentPadding)
        .padding(.vertical, 8)
        .background(Theme.disconnected.opacity(0.12))
    }

    // MARK: ドロワー開閉ジェスチャ（指追従・プッシュ式）
    private func drawerDrag(drawerWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                let dx = value.translation.width
                let dy = value.translation.height

                // まだ掴んでいない：横方向優位＆（閉→左端から / 開→どこでも）を満たしたら開始
                if dragProgress == nil {
                    let horizontal = abs(dx) > abs(dy) + 4
                    let fromEdge = value.startLocation.x < edgeWidth
                    guard horizontal, (drawerOpen || fromEdge) else { return }
                    edgeDragActive = true
                    if !drawerOpen { hideKeyboard() }   // 開き始めにキーボードを畳む
                }

                let base: CGFloat = drawerOpen ? 1 : 0
                dragProgress = min(max(base + dx / drawerWidth, 0), 1)
            }
            .onEnded { value in
                defer { edgeDragActive = false }
                guard let p = dragProgress else { return }
                let flick = value.predictedEndTranslation.width - value.translation.width

                withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                    if drawerOpen {
                        // 開→ 左へ一定引いた/速く左へ弾いたら即閉じる
                        drawerOpen = !(p < 0.85 || flick < -60)
                    } else {
                        // 閉→ 右へ一定出した/速く右へ弾いたら開く
                        drawerOpen = (p > 0.3 || flick > 60)
                    }
                    dragProgress = nil
                }
            }
    }

    // MARK: アクション
    private func send() {
        let instruction = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else { return }
        viewModel.send(instruction: instruction)
        inputText = ""
    }

    private func handleCommand(_ name: String) {
        switch name {
        case "model": showModelPicker = true
        case "clear": sessionStore.newSession()   // activeID変化→onChangeでメッセージ切替
        case "files": showFiles = true
        case "diff": showDiff = true
        case "settings": showSettings = true
        case "usage": showUsage = true
        default: break
        }
    }

    /// 起動時に Claude Code の既存履歴（sandbox）を取得し、ドロワーの Recents 下に表示する。
    private func loadClaudeHistory() async {
        guard let client = APIClient(host: viewModel.serverHost) else { return }
        if let list = try? await client.fetchHistorySessions(scope: "sandbox") {
            sessionStore.setClaudeHistory(list)
        }
    }

    /// 履歴行をタップ → 本文を取得してアプリのチャットに取り込み、開く。
    private func importAndOpen(_ dto: HistorySessionDTO) async {
        closeDrawer()
        guard let client = APIClient(host: viewModel.serverHost) else { return }
        guard let dtos = try? await client.fetchHistoryMessages(id: dto.id, scope: "sandbox") else { return }
        let msgs = dtos.map {
            ChatMessage(role: $0.role == "user" ? .user : .assistant,
                        text: $0.text,
                        timestamp: parseISO($0.timestamp))
        }
        sessionStore.addImported(title: dto.title, messages: msgs)
    }

    private func parseISO(_ iso: String?) -> Date {
        guard let iso else { return Date() }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) ?? Date()
    }

    /// 最初のやり取り完了時、タイトル未設定なら Claude(haiku) に短い題名を付けさせる。
    private func maybeAutoTitle() async {
        guard let session = sessionStore.activeSession,
              session.title.isEmpty,
              let firstUser = session.messages.first(where: { $0.role == .user })?.text,
              !firstUser.isEmpty,
              let client = APIClient(host: viewModel.serverHost) else { return }
        guard let title = try? await client.generateTitle(from: firstUser),
              !title.isEmpty else { return }
        sessionStore.rename(session.id, title: title)
    }

    private func openDrawer() {
        hideKeyboard()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { drawerOpen = true }
    }

    private func closeDrawer() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { drawerOpen = false }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        if animated {
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo(bottomAnchor, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(bottomAnchor, anchor: .bottom)
        }
    }
}

// MARK: - Preview
#Preview("Chat") {
    ConsoleChatView()
        .environmentObject(TaskViewModel.preview)
        .environmentObject(SessionStore.preview)
}
