import Foundation

// MARK: - APIError
// 通信レイヤで発生しうるエラー。上位（TaskViewModel）が catch してハンドリングする。
// CONTRACTS.md §2 の各エンドポイントに対応する。

enum APIError: Error, LocalizedError, Equatable {
    /// serverHost からベースURLを構築できない（未設定 / 不正なホスト）。
    case invalidHost
    /// HTTPURLResponse 以外の応答が返ってきた。
    case invalidResponse
    /// 2xx 以外のステータスコード。body はサーバーの生レスポンス（可能なら）。
    case httpError(statusCode: Int, body: String?)
    /// レスポンス JSON のデコード失敗。
    case decodingFailed(String)
    /// リクエスト body のエンコード失敗。
    case encodingFailed(String)
    /// URLSession の通信失敗（オフライン・タイムアウト等）。
    case transportFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidHost:
            return "サーバーアドレスが不正です。ホスト（例: 100.101.102.103）を確認してください。"
        case .invalidResponse:
            return "サーバーから不正な応答を受信しました。"
        case .httpError(let code, let body):
            if let body, !body.isEmpty {
                return "サーバーエラー (HTTP \(code)): \(body)"
            }
            return "サーバーエラー (HTTP \(code))"
        case .decodingFailed(let detail):
            return "応答の解析に失敗しました: \(detail)"
        case .encodingFailed(let detail):
            return "リクエストの生成に失敗しました: \(detail)"
        case .transportFailed(let detail):
            return "通信に失敗しました: \(detail)"
        }
    }

    static func == (lhs: APIError, rhs: APIError) -> Bool {
        lhs.errorDescription == rhs.errorDescription
    }
}

// MARK: - APIClient
// async/await + URLSession ベースの薄い API クライアント（ステートレスな値型）。
// CONTRACTS.md §2 の全エンドポイントに対応する。

struct APIClient {

    /// 例: http://100.101.102.103:3000
    var baseURL: URL

    /// 差し替え可能（テスト用）。デフォルトは共有セッション。
    var session: URLSession

    /// 通常リクエストのタイムアウト（秒）。
    var requestTimeout: TimeInterval

    /// health 用の短めタイムアウト（秒）。疎通確認は素早く失敗させたい。
    var healthTimeout: TimeInterval

    init(baseURL: URL,
         session: URLSession = .shared,
         requestTimeout: TimeInterval = 30,
         healthTimeout: TimeInterval = 5) {
        self.baseURL = baseURL
        self.session = session
        self.requestTimeout = requestTimeout
        self.healthTimeout = healthTimeout
    }

    /// ホスト文字列（例: "100.101.102.103" / "100.101.102.103:3000" /
    /// "http://100.101.102.103:3000"）から APIClient を組み立てる。
    /// スキーム省略時は http://、ポート省略時は :3000 を補う。
    /// 不正な場合は nil。
    init?(host: String,
          session: URLSession = .shared,
          requestTimeout: TimeInterval = 30,
          healthTimeout: TimeInterval = 5) {
        guard let url = APIClient.makeBaseURL(from: host) else { return nil }
        self.init(baseURL: url,
                  session: session,
                  requestTimeout: requestTimeout,
                  healthTimeout: healthTimeout)
    }

    /// ホスト文字列を正規化して baseURL を生成する。
    static func makeBaseURL(from host: String) -> URL? {
        var trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // スキーム省略時は http:// を補う。
        if !trimmed.contains("://") {
            trimmed = "http://" + trimmed
        }

        guard var components = URLComponents(string: trimmed) else { return nil }
        if components.scheme == nil || components.scheme?.isEmpty == true {
            components.scheme = "http"
        }
        // ポート省略時は 3000 を補う。
        if components.port == nil {
            components.port = 3000
        }
        // ホストが取れないものは不正扱い。
        guard let h = components.host, !h.isEmpty else { return nil }

        return components.url
    }

    // MARK: - エンドポイント

    /// GET /health → status == "ok" なら true。
    func health() async throws -> Bool {
        let response: HealthResponse = try await get(url("health"), timeout: healthTimeout)
        return response.status == "ok"
    }

    /// POST /api/tasks（model / effort は任意。nil はJSONから省略され後方互換）
    func createTask(instruction: String,
                    model: String? = nil,
                    effort: String? = nil) async throws -> CreateTaskResponse {
        try await post(url("api", "tasks"),
                       body: CreateTaskRequest(instruction: instruction, model: model, effort: effort),
                       timeout: requestTimeout)
    }

    /// GET /api/tasks/:id
    func fetchTask(id: String) async throws -> TaskStatusResponse {
        try await get(url("api", "tasks", id), timeout: requestTimeout)
    }

    /// POST /api/title → Claude が付けた短いチャットタイトル（生成不可なら ""）。
    func generateTitle(from text: String) async throws -> String {
        let response: TitleResponse = try await post(url("api", "title"),
                                                     body: TitleRequest(text: text),
                                                     timeout: requestTimeout)
        return response.title
    }

    /// GET /api/git/diff
    func fetchDiff() async throws -> DiffResponse {
        try await get(url("api", "git", "diff"), timeout: requestTimeout)
    }

    /// GET /api/usage?scope=all|sandbox
    func fetchUsage(scope: String) async throws -> UsageResponse {
        guard var comps = URLComponents(url: url("api", "usage"), resolvingAgainstBaseURL: false) else {
            throw APIError.invalidHost
        }
        comps.queryItems = [URLQueryItem(name: "scope", value: scope)]
        guard let u = comps.url else { throw APIError.invalidHost }
        return try await get(u, timeout: requestTimeout)
    }

    /// POST /api/git/commit
    func commit(message: String) async throws -> CommitResponse {
        do {
            return try await post(url("api", "git", "commit"),
                                  body: CommitRequest(message: message),
                                  timeout: requestTimeout)
        } catch {
            // サーバーが 400 で {success:false, message:"..."} を返すケースは
            // エラーではなくレスポンスとして尊重する（CONTRACTS.md §2）。
            if case let APIError.httpError(_, body) = error,
               let data = body?.data(using: .utf8),
               let decoded = try? JSONDecoder().decode(CommitResponse.self, from: data) {
                return decoded
            }
            throw error
        }
    }

    // MARK: - 内部ヘルパ

    /// baseURL に path コンポーネントを連結する。
    private func url(_ components: String...) -> URL {
        components.reduce(baseURL) { $0.appendingPathComponent($1) }
    }

    private func get<T: Decodable>(_ url: URL, timeout: TimeInterval) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await perform(request)
    }

    private func post<T: Decodable, B: Encodable>(_ url: URL,
                                                  body: B,
                                                  timeout: TimeInterval) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw APIError.encodingFailed(error.localizedDescription)
        }
        return try await perform(request)
    }

    /// 実行 + ステータス検証 + JSON デコードの共通処理。
    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transportFailed(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.httpError(statusCode: http.statusCode,
                                     body: String(data: data, encoding: .utf8))
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decodingFailed(error.localizedDescription)
        }
    }
}

// MARK: - リクエスト / 内部レスポンス DTO
// CONTRACTS.md §4 のモデル型（Models.swift）は再定義しない。
// ここで定義するのは、契約に含まれない「リクエストbody」と「/health応答」のみ。

private struct CreateTaskRequest: Encodable {
    let instruction: String
    // nil の場合は synthesized Encodable が encodeIfPresent で省略する（後方互換）。
    let model: String?
    let effort: String?
}

private struct CommitRequest: Encodable {
    let message: String
}

/// POST /api/title のリクエスト / 応答。
private struct TitleRequest: Encodable {
    let text: String
}
private struct TitleResponse: Decodable {
    let title: String
}

/// GET /health の応答。{ "status": "ok", "uptime": 123.45 }
private struct HealthResponse: Decodable {
    let status: String
}
