import Foundation

enum NativeToneError: LocalizedError {
    case emptyInput
    case tooLong
    case badURL
    case offline
    case server(String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .emptyInput: return "교정할 문장을 입력하세요."
        case .tooLong: return "문장이 너무 길어요. \(AppConfig.maxInputLength)자 이내로 줄여주세요."
        case .badURL: return "서버 주소가 올바르지 않아요."
        case .offline: return "서버에 연결할 수 없어요. 네트워크를 확인하세요."
        case .server(let m): return m
        case .badResponse: return "응답을 읽지 못했어요. 잠시 후 다시 시도하세요."
        }
    }
}

/// Talks to the NativeTone proxy. The proxy owns the Claude API key and prompt.
final class NativeToneClient {
    static let shared = NativeToneClient()

    private struct Body: Encodable {
        let text: String
        let tone: String
        let context: String?
        let explainLanguage: String
    }

    private struct ErrorBody: Decodable { let error: String }

    func rewrite(
        text: String,
        tone: Tone,
        context: String? = nil,
        explainLanguage: ExplainLanguage
    ) async throws -> RewriteResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw NativeToneError.emptyInput }
        guard trimmed.count <= AppConfig.maxInputLength else { throw NativeToneError.tooLong }
        guard let base = URL(string: AppSettings.baseURL) else { throw NativeToneError.badURL }

        var req = URLRequest(url: base.appendingPathComponent("v1/rewrite"), timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let token = AppSettings.appToken
        if !token.isEmpty { req.setValue(token, forHTTPHeaderField: "X-App-Token") }

        let ctx = context?.trimmingCharacters(in: .whitespacesAndNewlines)
        req.httpBody = try JSONEncoder().encode(Body(
            text: trimmed,
            tone: tone.rawValue,
            context: (ctx?.isEmpty ?? true) ? nil : ctx,
            explainLanguage: explainLanguage.promptName
        ))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw NativeToneError.offline
        }

        guard let http = response as? HTTPURLResponse else { throw NativeToneError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            if let e = try? JSONDecoder().decode(ErrorBody.self, from: data) {
                throw NativeToneError.server(e.error)
            }
            throw NativeToneError.server("서버 오류 (\(http.statusCode))")
        }
        guard let result = try? JSONDecoder().decode(RewriteResult.self, from: data) else {
            throw NativeToneError.badResponse
        }
        return result
    }
}
