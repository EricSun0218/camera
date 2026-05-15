// app/Cue/LLM/BackendClient.swift
import Foundation

public enum BackendError: Error {
    case badResponse(Int)
    case decodeFailed(Error)
    case rateLimited(retryAfter: TimeInterval)
}

private struct BackendRequestBody: Encodable {
    let image_b64: String
    let client_version: String
}

public final class BackendClient {
    /// Vercel production URL. Next.js routes live under `/api/*`.
    public static var baseURL = URL(string: "https://camera-ivory-psi.vercel.app")!

    public init() {}

    /// AI guidance call: returns suggested pose/scene target + zoom for current viewfinder.
    /// Backend can take up to 60 s.
    public func guidance(imageB64: String) async throws -> AIGuidance {
        try await post(path: "/api/guidance", imageB64: imageB64, timeout: 60.0, as: AIGuidance.self)
    }

    public func grade(imageB64: String) async throws -> SceneAnalysis {
        try await post(path: "/api/grade", imageB64: imageB64, timeout: 4.0, as: SceneAnalysis.self)
    }

    private func post<T: Decodable>(path: String, imageB64: String, timeout: TimeInterval, as: T.Type) async throws -> T {
        var req = URLRequest(url: Self.baseURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0",
                     forHTTPHeaderField: "X-Client-Version")
        req.timeoutInterval = timeout

        let body = BackendRequestBody(
            image_b64: imageB64,
            client_version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        )
        req.httpBody = try JSONEncoder().encode(body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw BackendError.badResponse(-1) }
        if http.statusCode == 429 {
            let retry = TimeInterval(http.value(forHTTPHeaderField: "Retry-After") ?? "60") ?? 60
            throw BackendError.rateLimited(retryAfter: retry)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw BackendError.badResponse(http.statusCode)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw BackendError.decodeFailed(error)
        }
    }
}
