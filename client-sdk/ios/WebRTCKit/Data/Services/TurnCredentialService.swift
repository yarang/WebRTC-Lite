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

// MARK: - Caching Layer

/// Cached TURN credential service with automatic refresh
final class CachedTurnCredentialService: TurnCredentialServiceProtocol {

    private let service: TurnCredentialService
    private var cache: [String: (credential: TurnCredential, expiry: Date)] = [:]
    private let cacheQueue = DispatchQueue(label: "com.webrtclite.turncache", attributes: .concurrent)

    init(service: TurnCredentialService = TurnCredentialService()) {
        self.service = service
    }

    func getCredentials(sessionId: String) async throws -> TurnCredential {
        // Check cache
        if let cached = getCached(sessionId: sessionId), cached.expiry > Date() {
            return cached.credential
        }

        // Fetch fresh credentials
        let credential = try await service.getCredentials(sessionId: sessionId)
        let expiry = Date().addingTimeInterval(TimeInterval(credential.ttl))

        // Update cache
        cacheQueue.async(flags: .barrier) {
            self.cache[sessionId] = (credential, expiry)
        }

        return credential
    }

    private func getCached(sessionId: String) -> (credential: TurnCredential, expiry: Date)? {
        cacheQueue.sync {
            cache[sessionId]
        }
    }

    /// Clear credential cache
    func clearCache() {
        cacheQueue.async(flags: .barrier) {
            self.cache.removeAll()
        }
    }
}
