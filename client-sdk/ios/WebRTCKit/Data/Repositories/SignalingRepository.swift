// MARK: - SignalingRepository
// TRUST 5 Compliance: Unified, Secured

import Foundation
import Combine
import FirebaseCore
import FirebaseFirestore

// MARK: - Repository Protocol

/// Repository interface for WebRTC signaling operations
protocol SignalingRepositoryProtocol {
    /// Send SDP offer to Firestore
    func sendOffer(sessionId: String, offer: SignalingMessage.Offer) async throws

    /// Send SDP answer to Firestore
    func sendAnswer(sessionId: String, answer: SignalingMessage.Answer) async throws

    /// Send ICE candidate to Firestore
    func sendIceCandidate(sessionId: String, candidateId: String, candidate: SignalingMessage.IceCandidate) async throws

    /// Observe offers from Firestore
    func observeOffer(sessionId: String) -> AnyPublisher<SignalingMessage.Offer, Error>

    /// Observe answers from Firestore
    func observeAnswer(sessionId: String) -> AnyPublisher<SignalingMessage.Answer, Error>

    /// Observe ICE candidates from Firestore
    func observeIceCandidates(sessionId: String) -> AnyPublisher<SignalingMessage.IceCandidate, Error>

    /// Delete session from Firestore
    func deleteSession(sessionId: String) async throws
}

// MARK: - Repository Implementation

/// Firestore implementation of SignalingRepository
final class SignalingRepository: SignalingRepositoryProtocol {

    // MARK: - Properties

    private let database: Firestore
    private let collection = "sessions"

    // MARK: - Initialization

    init(database: Firestore = Firestore.firestore()) {
        self.database = database
    }

    // MARK: - Send Operations

    func sendOffer(sessionId: String, offer: SignalingMessage.Offer) async throws {
        let documentRef = database
            .collection(collection)
            .document(sessionId)

        let data: [String: Any] = [
            "type": offer.type,
            "sessionId": offer.sessionId,
            "sdp": offer.sdp,
            "callerId": offer.callerId,
            "timestamp": offer.timestamp
        ]

        try await documentRef.setData(data, merge: true)
    }

    func sendAnswer(sessionId: String, answer: SignalingMessage.Answer) async throws {
        let documentRef = database
            .collection(collection)
            .document(sessionId)

        let data: [String: Any] = [
            "type": answer.type,
            "sessionId": answer.sessionId,
            "sdp": answer.sdp,
            "calleeId": answer.calleeId,
            "timestamp": answer.timestamp
        ]

        try await documentRef.setData(data, merge: true)
    }

    func sendIceCandidate(
        sessionId: String,
        candidateId: String,
        candidate: SignalingMessage.IceCandidate
    ) async throws {
        let documentRef = database
            .collection(collection)
            .document(sessionId)
            .collection("iceCandidates")
            .document(candidateId)

        let data: [String: Any] = [
            "type": candidate.type,
            "sessionId": candidate.sessionId,
            "sdpMid": candidate.sdpMid,
            "sdpMLineIndex": candidate.sdpMLineIndex,
            "sdpCandidate": candidate.sdpCandidate,
            "timestamp": candidate.timestamp
        ]

        try await documentRef.setData(data)
    }

    // MARK: - Observe Operations

    func observeOffer(sessionId: String) -> AnyPublisher<SignalingMessage.Offer, Error> {
        let documentRef = database
            .collection(collection)
            .document(sessionId)

        let subject = PassthroughSubject<SignalingMessage.Offer, Error>()
        let listener = documentRef.addSnapshotListener { [weak subject] snapshot, error in
            guard let subject = subject else { return }

            if let error = error {
                subject.send(completion: .failure(error))
                return
            }

            guard let snapshot = snapshot,
                  snapshot.exists,
                  let data = snapshot.data() else {
                return
            }

            do {
                let jsonData = try JSONSerialization.data(withJSONObject: data)
                let offer = try JSONDecoder().decode(SignalingMessage.Offer.self, from: jsonData)
                subject.send(offer)
            } catch {
                subject.send(completion: .failure(error))
            }
        }

        return subject
            .handleEvents(receiveCancel: { listener.remove() })
            .eraseToAnyPublisher()
    }

    func observeAnswer(sessionId: String) -> AnyPublisher<SignalingMessage.Answer, Error> {
        let documentRef = database
            .collection(collection)
            .document(sessionId)

        let subject = PassthroughSubject<SignalingMessage.Answer, Error>()
        let listener = documentRef.addSnapshotListener { [weak subject] snapshot, error in
            guard let subject = subject else { return }

            if let error = error {
                subject.send(completion: .failure(error))
                return
            }

            guard let snapshot = snapshot,
                  snapshot.exists,
                  let data = snapshot.data() else {
                return
            }

            do {
                let jsonData = try JSONSerialization.data(withJSONObject: data)
                let answer = try JSONDecoder().decode(SignalingMessage.Answer.self, from: jsonData)
                subject.send(answer)
            } catch {
                subject.send(completion: .failure(error))
            }
        }

        return subject
            .handleEvents(receiveCancel: { listener.remove() })
            .eraseToAnyPublisher()
    }

    func observeIceCandidates(sessionId: String) -> AnyPublisher<SignalingMessage.IceCandidate, Error> {
        let collectionRef = database
            .collection(collection)
            .document(sessionId)
            .collection("iceCandidates")

        let subject = PassthroughSubject<SignalingMessage.IceCandidate, Error>()
        let listener = collectionRef.addSnapshotListener { [weak subject] snapshot, error in
            guard let subject = subject else { return }

            if let error = error {
                subject.send(completion: .failure(error))
                return
            }

            guard let snapshot = snapshot else { return }

            snapshot.documentChanges.forEach { change in
                guard change.type == .added || change.type == .modified else { return }

                do {
                    let data = change.document.data()
                    let jsonData = try JSONSerialization.data(withJSONObject: data ?? [:])
                    let candidate = try JSONDecoder().decode(SignalingMessage.IceCandidate.self, from: jsonData)
                    subject.send(candidate)
                } catch {
                    // Silently skip invalid candidates
                }
            }
        }

        return subject
            .handleEvents(receiveCancel: { listener.remove() })
            .eraseToAnyPublisher()
    }

    // MARK: - Delete Operations

    func deleteSession(sessionId: String) async throws {
        let documentRef = database
            .collection(collection)
            .document(sessionId)

        try await documentRef.delete()
    }
}

// MARK: - Firestore Listener Bridge

/// Helper class to bridge Firestore listeners to Combine
final class FirestoreListenerBridge<T: Decodable> {

    private var listener: ListenerRegistration?

    func listen(
        to query: Query,
        type: T.Type
    ) -> AnyPublisher<T, Error> {
        let subject = PassthroughSubject<T, Error>()

        listener = query.addSnapshotListener { snapshot, error in
            if let error = error {
                subject.send(completion: .failure(error))
                return
            }

            guard let snapshot = snapshot,
                  !snapshot.isEmpty,
                  let data = snapshot.data?.values.first as? [String: Any] else {
                return
            }

            do {
                let jsonData = try JSONSerialization.data(withJSONObject: data)
                let decoded = try JSONDecoder().decode(T.self, from: jsonData)
                subject.send(decoded)
            } catch {
                subject.send(completion: .failure(error))
            }
        }

        return subject.eraseToAnyPublisher()
    }

    deinit {
        listener?.remove()
    }
}
