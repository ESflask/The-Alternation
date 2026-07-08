import Foundation

// MARK: - FileAPI
// APIClient のファイル操作拡張（CONTRACTS-FEATURES.md §C）。
//
// APIClient は `struct APIClient { var baseURL: URL; var session: URLSession; ... }`（既存）。
// その private ヘルパ（url()/get()/post()/perform()）は使えないため、
// ここでは baseURL から自前で URLRequest を組み立て URLSession で通信する。
//
// クエリは URLComponents で安全にエンコードし、body/応答は JSONEncoder/JSONDecoder。
// エラーは既存 APIError（Networking/APIClient.swift）を流用して投げる。
//
// 対応エンドポイント（CONTRACTS-FEATURES.md §A）:
//   GET  /api/files/tree?path=<rel>   → FileTreeResponse
//   GET  /api/files/read?path=<rel>   → FileReadResponse
//   PUT  /api/files/write             → FileWriteResponse

extension APIClient {

    // MARK: - Public エンドポイント

    /// GET /api/files/tree?path=<rel>
    /// `path` を省略（nil / 空）するとサーバのルートを返す。
    func fileTree(path: String?) async throws -> FileTreeResponse {
        let normalized = path.flatMap { $0.isEmpty ? nil : $0 }
        let query = normalized.map { [URLQueryItem(name: "path", value: $0)] } ?? []
        let request = try makeGETRequest(pathComponents: ["api", "files", "tree"],
                                         queryItems: query)
        return try await performFileRequest(request)
    }

    /// GET /api/files/read?path=<rel>
    func readFile(path: String) async throws -> FileReadResponse {
        let request = try makeGETRequest(pathComponents: ["api", "files", "read"],
                                         queryItems: [URLQueryItem(name: "path", value: path)])
        return try await performFileRequest(request)
    }

    /// PUT /api/files/write  body: { "path": string, "content": string }
    func writeFile(path: String, content: String) async throws -> FileWriteResponse {
        var request = try makeBaseRequest(pathComponents: ["api", "files", "write"],
                                          queryItems: [])
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONEncoder().encode(FileWriteRequest(path: path, content: content))
        } catch {
            throw APIError.encodingFailed(error.localizedDescription)
        }

        // 失敗時 サーバは 400|500 で {success:false, message:string} を返す契約。
        // これはエラーではなくレスポンスとして尊重する。
        do {
            return try await performFileRequest(request)
        } catch {
            if case let APIError.httpError(_, body) = error,
               let data = body?.data(using: .utf8),
               let decoded = try? JSONDecoder().decode(FileWriteResponse.self, from: data) {
                return decoded
            }
            throw error
        }
    }

    // MARK: - 内部ヘルパ（APIClient の private ヘルパは使えないので自前で組む）

    /// baseURL にパスコンポーネントとクエリを載せた URLRequest を作る（メソッド未設定）。
    private func makeBaseRequest(pathComponents: [String],
                                queryItems: [URLQueryItem]) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidHost
        }
        // baseURL のパス（通常は "" か "/"）にコンポーネントを連結する。
        var path = components.path
        if path.hasSuffix("/") { path.removeLast() }
        for component in pathComponents {
            path += "/" + component
        }
        components.path = path
        components.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components.url else {
            throw APIError.invalidHost
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    /// GET 用の URLRequest を作る。
    private func makeGETRequest(pathComponents: [String],
                              queryItems: [URLQueryItem]) throws -> URLRequest {
        var request = try makeBaseRequest(pathComponents: pathComponents, queryItems: queryItems)
        request.httpMethod = "GET"
        return request
    }

    /// 実行 + ステータス検証 + JSON デコードの共通処理。
    private func performFileRequest<T: Decodable>(_ request: URLRequest) async throws -> T {
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

// MARK: - リクエスト DTO
// 契約に含まれないリクエスト body のみ定義（応答型は FileModels.swift）。

private struct FileWriteRequest: Encodable {
    let path: String
    let content: String
}
