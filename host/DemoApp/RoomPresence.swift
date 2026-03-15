import Foundation

struct RoomPresencePayload: Equatable {
    var cameraOriginX: Double
    var cameraOriginY: Double
    var zoom: Double
    var viewportWidth: Double
    var viewportHeight: Double
    var cursorWorldX: Double?
    var cursorWorldY: Double?
    var selectedSurfaceID: TerminalSurfaceID?
    var controlSessionID: SessionID?
}

struct RoomPresenceState: Equatable {
    let roomID: RoomID
    let clientID: ClientID
    let userID: UserID?
    let payload: RoomPresencePayload
    let updatedAtMillis: UInt64
    let expiresAtMillis: UInt64
}

enum RoomPresenceDelivery: Equatable {
    case snapshot([RoomPresenceState])
    case updated(RoomPresenceState)
    case expired(ClientID)
}

final class RoomPresenceHub {
    private let roomID: RoomID
    private let ttlMillis: UInt64
    private var connectedClientIDs: Set<ClientID> = []
    private var presenceByClientID: [ClientID: RoomPresenceState] = [:]
    private var deliveriesByClientID: [ClientID: [RoomPresenceDelivery]] = [:]

    init(roomID: RoomID, ttlMillis: UInt64 = 15_000) {
        self.roomID = roomID
        self.ttlMillis = ttlMillis
    }

    @discardableResult
    func connect(clientID: ClientID, nowMillis: UInt64) -> [RoomPresenceState] {
        expire(nowMillis: nowMillis)
        connectedClientIDs.insert(clientID)
        let snapshot = presenceByClientID.values
            .filter { $0.clientID != clientID }
            .sorted { $0.clientID.rawValue < $1.clientID.rawValue }
        deliveriesByClientID[clientID, default: []].append(.snapshot(snapshot))
        return snapshot
    }

    @discardableResult
    func update(
        clientID: ClientID,
        userID: UserID?,
        payload: RoomPresencePayload,
        nowMillis: UInt64
    ) -> RoomPresenceState {
        connectedClientIDs.insert(clientID)
        let state = RoomPresenceState(
            roomID: roomID,
            clientID: clientID,
            userID: userID,
            payload: payload,
            updatedAtMillis: nowMillis,
            expiresAtMillis: nowMillis + ttlMillis
        )
        presenceByClientID[clientID] = state
        broadcast(.updated(state), excluding: nil)
        return state
    }

    @discardableResult
    func expire(nowMillis: UInt64) -> [ClientID] {
        let expiredClientIDs = presenceByClientID.values
            .filter { $0.expiresAtMillis <= nowMillis }
            .map(\.clientID)
            .sorted { $0.rawValue < $1.rawValue }
        for clientID in expiredClientIDs {
            presenceByClientID.removeValue(forKey: clientID)
            broadcast(.expired(clientID), excluding: nil)
        }
        return expiredClientIDs
    }

    func disconnect(clientID: ClientID) {
        connectedClientIDs.remove(clientID)
    }

    func activePresence(nowMillis: UInt64) -> [RoomPresenceState] {
        _ = expire(nowMillis: nowMillis)
        return presenceByClientID.values.sorted { $0.clientID.rawValue < $1.clientID.rawValue }
    }

    func deliveries(for clientID: ClientID) -> [RoomPresenceDelivery] {
        deliveriesByClientID[clientID, default: []]
    }

    private func broadcast(_ delivery: RoomPresenceDelivery, excluding excludedClientID: ClientID?) {
        for clientID in connectedClientIDs where clientID != excludedClientID {
            deliveriesByClientID[clientID, default: []].append(delivery)
        }
    }
}
