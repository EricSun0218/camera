// app/Cue/LLM/BackendClient.swift
import Foundation
import os

public enum BackendError: Error {
    case badResponse(Int)
    case decodeFailed(Error)
    case rateLimited(retryAfter: TimeInterval)
    case encodeFailed
}

private struct BackendRequestBody: Encodable {
    let image_b64: String
    let client_version: String
}

public final class BackendClient {
    /// Vercel production URL. Next.js routes live under `/api/*`.
    public static var baseURL = URL(string: "https://camera-ivory-psi.vercel.app")!

    private static let log = Logger(subsystem: "com.ericsun.cue", category: "backend")

    /// Dedicated session with a hard resource cap so a stalled connection can't spin forever.
    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 65
        cfg.timeoutIntervalForResource = 75
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }()

    public init() {}

    /// AI guidance call: returns suggested pose/scene target + zoom for current viewfinder.
    public func guidance(imageB64: String) async throws -> AIGuidance {
        try await post(path: "/api/guidance", imageB64: imageB64, timeout: 65.0, as: AIGuidance.self)
    }

    public func grade(imageB64: String) async throws -> SceneAnalysis {
        // Gemini vision grade routinely takes 5-13s — 4s was a bug that always timed out.
        try await post(path: "/api/grade", imageB64: imageB64, timeout: 65.0, as: SceneAnalysis.self)
    }

    private func post<T: Decodable>(path: String, imageB64: String, timeout: TimeInterval, as: T.Type) async throws -> T {
        let url = Self.baseURL.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        req.setValue(version, forHTTPHeaderField: "X-Client-Version")
        req.timeoutInterval = timeout

        let body = BackendRequestBody(image_b64: imageB64, client_version: version)
        req.httpBody = try JSONEncoder().encode(body)

        let bytes = req.httpBody?.count ?? 0
        Self.log.info("POST \(path, privacy: .public) — \(bytes) bytes, timeout \(timeout)s")
        let started = Date()

        do {
            let collector = MetricsCollector(path: path)
            let (data, resp) = try await session.data(for: req, delegate: collector)
            let elapsed = Date().timeIntervalSince(started)
            guard let http = resp as? HTTPURLResponse else {
                Self.log.error("POST \(path, privacy: .public) — non-HTTP response after \(elapsed)s")
                throw BackendError.badResponse(-1)
            }
            Self.log.info("POST \(path, privacy: .public) — HTTP \(http.statusCode) in \(String(format: "%.1f", elapsed))s, \(data.count) bytes")
            if http.statusCode == 429 {
                let retry = TimeInterval(http.value(forHTTPHeaderField: "Retry-After") ?? "60") ?? 60
                throw BackendError.rateLimited(retryAfter: retry)
            }
            guard (200..<300).contains(http.statusCode) else {
                Self.log.error("POST \(path, privacy: .public) — bad status \(http.statusCode): \(String(decoding: data.prefix(200), as: UTF8.self), privacy: .public)")
                throw BackendError.badResponse(http.statusCode)
            }
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                Self.log.error("POST \(path, privacy: .public) — decode failed: \(error.localizedDescription, privacy: .public) — body: \(String(decoding: data.prefix(300), as: UTF8.self), privacy: .public)")
                throw BackendError.decodeFailed(error)
            }
        } catch let e as BackendError {
            throw e
        } catch {
            let elapsed = Date().timeIntervalSince(started)
            Self.log.error("POST \(path, privacy: .public) — network error after \(String(format: "%.1f", elapsed))s: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
}

/// Per-task delegate that logs the connection timing breakdown. When a request
/// times out, the metrics still arrive — so the log pinpoints whether the stall
/// was DNS, TCP connect, TLS, the upload, the server, or the download.
private final class MetricsCollector: NSObject, URLSessionTaskDelegate {
    private let path: String
    init(path: String) { self.path = path }

    private static let log = Logger(subsystem: "com.ericsun.cue", category: "backend")

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didFinishCollecting metrics: URLSessionTaskMetrics) {
        guard let tx = metrics.transactionMetrics.last else {
            Self.log.error("metrics[\(self.path, privacy: .public)] — no transaction metrics")
            return
        }
        func span(_ a: Date?, _ b: Date?) -> String {
            guard let a, let b else { return "—" }
            return String(format: "%.0fms", b.timeIntervalSince(a) * 1000)
        }
        let dns     = span(tx.domainLookupStartDate, tx.domainLookupEndDate)
        let connect = span(tx.connectStartDate, tx.connectEndDate)
        let tls     = span(tx.secureConnectionStartDate, tx.secureConnectionEndDate)
        let send    = span(tx.requestStartDate, tx.requestEndDate)
        let wait    = span(tx.requestEndDate, tx.responseStartDate)   // server processing / TTFB
        let recv    = span(tx.responseStartDate, tx.responseEndDate)
        let reused  = tx.isReusedConnection
        Self.log.info("metrics[\(self.path, privacy: .public)] reused=\(reused) dns=\(dns, privacy: .public) connect=\(connect, privacy: .public) tls=\(tls, privacy: .public) send=\(send, privacy: .public) serverWait=\(wait, privacy: .public) recv=\(recv, privacy: .public)")

        // If the response never completed, name the stage that stalled.
        if tx.responseEndDate == nil {
            let stalled: String
            if !reused && tx.domainLookupEndDate == nil { stalled = "DNS lookup never finished — phone can't resolve the host" }
            else if !reused && tx.connectEndDate == nil  { stalled = "TCP connect never finished — host unreachable / firewall" }
            else if !reused && tx.secureConnectionEndDate == nil && tx.secureConnectionStartDate != nil { stalled = "TLS handshake never finished" }
            else if tx.requestEndDate == nil             { stalled = "request upload never finished — slow uplink" }
            else if tx.responseStartDate == nil          { stalled = "server never sent a byte (\(send) to upload, then silence) — server hang or dropped connection" }
            else                                         { stalled = "response body never finished downloading" }
            Self.log.error("metrics[\(self.path, privacy: .public)] — STALLED: \(stalled, privacy: .public)")
        }
    }
}
