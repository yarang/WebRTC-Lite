// MARK: - AppContainer
// TRUST 5 Compliance: Unified, Secured

import Foundation

/// Dependency Injection Container for WebRTCKit
/// Provides singleton instances of dependencies
final class AppContainer {

    // MARK: - Singleton

    static let shared = AppContainer()

    // MARK: - Dependencies

    private(set) lazy var signalingRepository: SignalingRepositoryProtocol = SignalingRepository()

    private(set) lazy var turnCredentialService: TurnCredentialServiceProtocol = CachedTurnCredentialService(
        service: TurnCredentialService()
    )

    private(set) lazy var peerConnectionManager: PeerConnectionManager = PeerConnectionManager()

    // MARK: - Use Cases

    private(set) lazy var createOfferUseCase: CreateOfferUseCase = CreateOfferUseCase(
        signalingRepository: signalingRepository,
        turnCredentialService: turnCredentialService,
        peerConnectionManager: peerConnectionManager
    )

    private(set) lazy var answerCallUseCase: AnswerCallUseCase = AnswerCallUseCase(
        signalingRepository: signalingRepository,
        turnCredentialService: turnCredentialService,
        peerConnectionManager: peerConnectionManager
    )

    private(set) lazy var addIceCandidateUseCase: AddIceCandidateUseCase = AddIceCandidateUseCase(
        signalingRepository: signalingRepository,
        peerConnectionManager: peerConnectionManager
    )

    private(set) lazy var endCallUseCase: EndCallUseCase = EndCallUseCase(
        signalingRepository: signalingRepository,
        peerConnectionManager: peerConnectionManager
    )

    // MARK: - ViewModels

    func makeCallViewModel() -> CallViewModel {
        return CallViewModel(
            createOfferUseCase: createOfferUseCase,
            answerCallUseCase: answerCallUseCase,
            addIceCandidateUseCase: addIceCandidateUseCase,
            endCallUseCase: endCallUseCase,
            peerConnectionManager: peerConnectionManager
        )
    }

    // MARK: - Reset

    /// Reset all dependencies (for testing)
    func reset() {
        // Clean up resources
    }

    // MARK: - Initialization

    private init() {}
}

// MARK: - Factory Extension

extension AppContainer {
    /// Create configured CallViewModel
    static func createCallViewModel() -> CallViewModel {
        return shared.makeCallViewModel()
    }
}
