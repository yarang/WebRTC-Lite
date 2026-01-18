// MARK: - TurnCredentialService
// TRUST 5 Compliance: Secured, Trackable

import Foundation
import Combine

// MARK: - Turn Credential Model

/// TURN server credential response
struct TurnCredential: Codable, Equatable {
    let username: String
    let password: String
    let ttl: Int
    let uris: [String]

    private enum CodingKeys: String, CodingKey {
        case username
        case password
        case ttl
        case uris
    }

    /// Convert to signaling message format
    func toSignalingMessage(sessionId: String) -> SignalingMessage.TurnCredential {
        return SignalingMessage.TurnCredential(
            sessionId: sessionId,
            username: username,
            password: password,
            ttl: ttl,
            urls: uris
        )
    }
}

// MARK: - Service Protocol

/// Service for fetching TURN server credentials
protocol TurnCredentialServiceProtocol {
    /// Get TURN credentials for a session
    func getCredentials(sessionId: String) async throws -> TurnCredential
}

// MARK: - Service Implementation

/// HTTP-based TURN credential service
final class TurnCredentialService: TurnCredentialServiceProtocol {

    // MARK: - Properties

    private let session: URLSession
    private let baseURL: String

    // MARK: - Turn API Configuration

    struct TurnAPIConfig {
        let baseURL: String
        let timeout: TimeInterval
        let retryCount: Int

        static let `default` = TurnAPIConfig(
            baseURL: Self.turnAPIURL,
            timeout: 10.0,
            retryCount: 3
        )

        /// Get TURN API URL from environment variable or Info.plist
        private static var turnAPIURL: String {
            // Try environment variable first
            if let envURL = ProcessInfo.processInfo.environment["TURN_API_URL"], !envURL.isEmpty {
                return envURL
            }

            // Try Info.plist
            if let plistURL = Bundle.main.object(forInfoDictionaryKey: "TurnAPIURL") as? String, !plistURL.isEmpty {
                return plistURL
            }

            // Fallback to localhost for development
            return "http://localhost:8080/api"
        }
    }

    // MARK: - Initialization

    init(
        session: URLSession = .shared,
        config: TurnAPIConfig = .default
    ) {
        self.session = session
        self.baseURL = config.baseURL
    }

    // MARK: - Public Methods

    func getCredentials(sessionId: String) async throws -> TurnCredential {
        var retries = 0
        var lastError: Error?

        while retries < TurnAPIConfig.default.retryCount {
            do {
                return try await fetchCredentials(sessionId: sessionId)
            } catch {
                lastError = error
                retries += 1

                // Exponential backoff
                let delay = TimeInterval(exactly: pow(2.0, Double(retries))) ?? 1.0
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        throw lastError ?? TurnCredentialError.fetchFailed("Max retries exceeded")
    }

    // MARK: - Private Methods

    private func fetchCredentials(sessionId: String) async throws -> TurnCredential {
        guard var urlComponents = URLComponents(string: "\(baseURL)/turn/credentials") else {
            throw TurnCredentialError.invalidURL
        }

        var queryItems = [URLQueryItem]()
        queryItems.append(URLQueryItem(name: "session", value: sessionId))
        queryItems.append(URLQueryItem(name: "service", value: "turn"))
        urlComponents.queryItems = queryItems

        guard let url = urlComponents.url else {
            throw TurnCredentialError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = TurnAPIConfig.default.timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TurnCredentialError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            let decoder = JSONDecoder()
            return try decoder.decode(TurnCredential.self, from: data)
        case 401:
            throw TurnCredentialError.unauthorized
        case 404:
            throw TurnCredentialError.notFound
        case 500...599:
            throw TurnCredentialError.serverError(httpResponse.statusCode)
        default:
            throw TurnCredentialError.fetchFailed("HTTP \(httpResponse.statusCode)")
        }
    }
}

// MARK: - Errors

enum TurnCredentialError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case notFound
    case serverError(Int)
    case fetchFailed(String)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid TURN API URL"
        case .invalidResponse:
            return "Invalid response from TURN server"
        case .unauthorized:
            return "Unauthorized to access TURN server"
        case .notFound:
            return "TURN credentials not found"
        case .serverError(let code):
            return "TURN server error: HTTP \(code)"
        case .fetchFailed(let message):
            return "Failed to fetch TURN credentials: \(message)"
        case .decodingError(let error):
            return "Failed to decode TURN credentials: \(error.localizedDescription)"
        }
    }
}

// MARK: - Caching Layer with Auto-Refresh

/// Cached TURN credential service with automatic refresh
/// Implements TTL-based caching with auto-refresh 5 minutes before expiry
@available(iOS 13.0, *)
final class CachedTurnCredentialService: TurnCredentialServiceProtocol {

    // MARK: - Properties

    private let service: TurnCredentialService
    private var cache: [String: CachedCredential] = [:]
    private let cacheQueue = DispatchQueue(label: "com.webrtclite.turncache", attributes: .concurrent)
    private var refreshTask: Task<Void, Never>?

    private enum Constants {
        static let refreshBuffer: TimeInterval = 5 * 60 // 5 minutes before expiry
        static let minCheckInterval: TimeInterval = 60 // Check every minute
    }

    private struct CachedCredential {
        let credential: TurnCredential
        let expiry: Date
        let lastRefresh: Date

        /// Check if credential needs refresh (5 minutes before expiry)
        func needsRefresh() -> Bool {
            return Date().addingTimeInterval(Constants.refreshBuffer) >= expiry
        }

        /// Check if credential is expired
        func isExpired() -> Bool {
            return Date() >= expiry
        }
    }

    // MARK: - Initialization

    init(service: TurnCredentialService = TurnCredentialService()) {
        self.service = service
    }

    deinit {
        stopAutoRefresh()
    }

    // MARK: - Public Methods

    func getCredentials(sessionId: String) async throws -> TurnCredential {
        // Check cache first
        if let cached = getCached(sessionId: sessionId), !cached.isExpired() {
            return cached.credential
        }

        // Fetch fresh credentials
        let credential = try await service.getCredentials(sessionId: sessionId)
        let expiry = Date().addingTimeInterval(TimeInterval(credential.ttl))

        // Update cache
        cacheQueue.async(flags: .barrier) {
            self.cache[sessionId] = CachedCredential(
                credential: credential,
                expiry: expiry,
                lastRefresh: Date()
            )
        }

        return credential
    }

    /// Start auto-refresh for cached credentials
    /// Checks periodically and refreshes credentials before expiry
    func startAutoRefresh() {
        guard refreshTask == nil else { return }

        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Constants.minCheckInterval * 1_000_000_000))
                await self?.refreshExpiringCredentials()
            }
        }
    }

    /// Stop auto-refresh
    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    /// Get time until credential expires (in seconds)
    /// Returns 0 if credential not found or expired
    func getTimeToExpiry(sessionId: String) -> TimeInterval {
        guard let cached = getCached(sessionId: sessionId) else {
            return 0
        }
        return max(0, cached.expiry.timeIntervalSinceNow)
    }

    /// Check if credential for session is cached and valid
    func isCached(sessionId: String) -> Bool {
        guard let cached = getCached(sessionId: sessionId) else {
            return false
        }
        return !cached.isExpired()
    }

    /// Clear credential cache
    func clearCache() {
        cacheQueue.async(flags: .barrier) {
            self.cache.removeAll()
        }
    }

    /// Clear credential for specific session
    func clearCache(sessionId: String) {
        cacheQueue.async(flags: .barrier) {
            self.cache.removeValue(forKey: sessionId)
        }
    }

    // MARK: - Private Methods

    private func getCached(sessionId: String) -> CachedCredential? {
        cacheQueue.sync {
            cache[sessionId]
        }
    }

    @MainActor
    private func refreshExpiringCredentials() async {
        let sessionsToRefresh: [String]

        // Find credentials that need refresh
        cacheQueue.sync {
            sessionsToRefresh = cache.compactMap { (sessionId, cached) in
                cached.needsRefresh() && !cached.isExpired() ? sessionId : nil
            }
        }

        // Refresh each credential
        for sessionId in sessionsToRefresh {
            do {
                // Remove from cache to force refresh
                cacheQueue.async(flags: .barrier) {
                    self.cache.removeValue(forKey: sessionId)
                }

                // Get new credential (will be cached)
                _ = try await getCredentials(sessionId: sessionId)

            } catch {
                // Log error but continue using old credential until it expires
                // Note: In production, you'd want to log this error
                continue
            }
        }

        // Remove expired credentials
        cacheQueue.async(flags: .barrier) {
            self.cache = self.cache.filter { !$1.isExpired() }
        }
    }
}
