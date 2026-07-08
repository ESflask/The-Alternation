# VibeConnect – iOS アプリ

Mac 上の **Claude Code CLI** を iPhone からリモート操作する「Vibe Coding」クライアント（SwiftUI）。
Mac 側の中継 API サーバー（`../vibe-connect-server/`）へ Tailscale 経由で HTTP/JSON 接続します。

---

## 必要環境

| 項目 | 要件 |
| --- | --- |
| Xcode | 15 以上（開発・検証は Xcode 26 で実施） |
| iOS デプロイターゲット | 17.0 以上 |
| 実機 / シミュレータ | iOS 17+ |
| ネットワーク | Mac と iPhone の双方に Tailscale を導入し、同一 Tainet 内であること |
| （プロジェクト再生成時のみ）XcodeGen | `brew install xcodegen` |

---

## プロジェクト構成

```
VibeConnectApp/
├── project.yml                 # XcodeGen 仕様（唯一のプロジェクト定義）
├── Info.plist                  # XcodeGen が生成（手動編集しない）
├── VibeConnectApp.xcodeproj/   # 生成物（project.yml から再生成可能）
└── VibeConnectApp/
    ├── VibeConnectApp.swift    # @main App エントリ
    ├── Models.swift            # 共有データモデル + DiffParser
    ├── Theme.swift             # 配色・フォント定数（ダークモード対応）
    ├── MockData.swift          # プレビュー用ダミーデータ
    ├── Views/
    │   ├── ConsoleChatView.swift    # メイン：チャット兼コンソール
    │   ├── DiffInspectorView.swift  # 差分確認・Commit
    │   └── Components/              # ChatBubble / ConnectionIndicator / MessageInputBar / DiffLineRow
    ├── Networking/
    │   └── APIClient.swift     # URLSession 通信層（Agent 5）
    └── ViewModels/
        └── TaskViewModel.swift # 状態管理・2秒ポーリング・自動復旧（Agent 5）
```

`Views` / `Models` / `Theme` / `MockData`（UI 層）と `Networking` / `ViewModels`（通信層）は
`CONTRACTS.md §4/§5` のインターフェース契約を介して結合します。View は `TaskViewModel` の
public API にのみ依存します。

---

## ビルド方法

### 1. Xcode で開く

```sh
open VibeConnectApp.xcodeproj
```

スキーム `VibeConnectApp` を選び、iOS 17+ シミュレータまたは実機を指定して実行（⌘R）。

### 2. コマンドラインでビルド（動作確認済み）

```sh
xcodebuild \
  -project VibeConnectApp.xcodeproj \
  -scheme VibeConnectApp \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO build
```

### 3. プロジェクトを再生成したいとき（XcodeGen）

`project.yml` を編集した場合や、ファイルを追加した場合は再生成します。

```sh
brew install xcodegen   # 未インストールなら
cd VibeConnectApp
xcodegen generate       # → VibeConnectApp.xcodeproj を再生成
```

`sources` はフォルダ単位で glob しているため、`VibeConnectApp/` 配下に追加した
Swift ファイルは再生成で自動的にビルド対象へ含まれます。

---

## サーバー IP（Tailscale）の設定方法

接続先の Mac の Tailscale IP（例: `100.x.y.z`）はアプリ内の状態
`TaskViewModel.serverHost` として保持され、`UserDefaults`（キー `"vibe.serverHost"`）に
永続化されます。ベース URL は `http://<serverHost>:3000` になります。

初期値を投入する方法（いずれか）:

- アプリ内の設定 UI から入力する（通信層 UI の実装に準拠）。
- 手早く試すなら起動前に `UserDefaults` へ直接セット:

```sh
# シミュレータで一度起動した後、アプリの Bundle ID 配下に書き込む例
xcrun simctl spawn booted defaults write com.vibeconnect.app vibe.serverHost 100.101.102.103
```

> HTTP（非 TLS）で Tailscale IP へ接続するため、`Info.plist` に
> `NSAppTransportSecurity > NSAllowsArbitraryLoads = true` の例外を含めています。
> WAN ポート開放は不要・禁止で、通信は Tailscale の暗号化 P2P 経由です。

---

## プレビュー

各 View には `#Preview` を用意しており、`TaskViewModel.preview`（+ `MockData`）で
実通信なしに表示を確認できます。

- `ConsoleChatView` … チャットタイムライン / 接続インジケータ / 入力欄 / Diff 導線
- `DiffInspectorView` … 差分の色分け（+緑 / -赤）と Commit フッター
- `Components/*` … 個別コンポーネントのプレビュー

---

## 画面仕様（要約）

- **ConsoleChatView**: 上部に接続インジケータ（Green/Red）とホスト名。指示は右側のユーザー吹き出し、
  Claude Code のログは左側（等幅フォント）。処理中はスピナー表示と最下部への自動スクロール。
  変更あり／タスク完了時に差分画面への導線を表示。
- **DiffInspectorView**: `git diff` を行ごとに色分け（`+`=薄緑背景+緑文字 / `-`=薄赤背景+赤文字）。
  横スクロール可・等幅。フッターの「この変更を適用（Commit）」からコミットメッセージを入力して確定。
  変更が無いときは空状態を表示。
