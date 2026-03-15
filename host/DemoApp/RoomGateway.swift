import Foundation

enum RoomGatewayCatchUpMode: String, Equatable {
    case coldJoin
    case tailOnly
    case snapshotAndTail
    case upToDate
}

struct RoomGatewayCatchUp: Equatable {
    let roomID: RoomID
    let knownRoomSeq: UInt64?
    let currentRoomSeq: UInt64
    let mode: RoomGatewayCatchUpMode
    let baseSnapshot: DurableRoomSnapshot?
    let tailRecords: [RoomOpRecord]

    func reconstructReplica(existingSnapshot: DurableRoomSnapshot?) throws -> DurableRoomSnapshot {
        let base: DurableRoomSnapshot
        if let baseSnapshot {
            base = baseSnapshot
        } else if let existingSnapshot {
            base = existingSnapshot
        } else {
            throw RoomGatewayError.missingBaseSnapshot
        }
        return try RoomStateReducer.replay(snapshot: base, records: tailRecords)
    }
}

struct RoomGatewayReject: Error, Equatable, LocalizedError {
    let roomID: RoomID
    let clientID: ClientID
    let opID: RoomOpID
    let reason: String

    var errorDescription: String? { reason }
}

enum RoomGatewayDelivery: Equatable {
    case accepted(RoomOpRecord)
    case rejected(RoomGatewayReject)
    case duplicate(RoomOpRecord)
}

enum RoomGatewayEphemeralDelivery: Equatable {
    case presence(String)
    case session(String)
    case leaseUpdated(SessionID, ControlLeaseRecord?)
}

enum RoomGatewayError: Error, Equatable, LocalizedError {
    case missingBaseSnapshot

    var errorDescription: String? {
        switch self {
        case .missingBaseSnapshot:
            return "reconnect replay requires a base snapshot when no gateway snapshot is provided"
        }
    }
}

final class RoomGateway {
    private let actor: RoomActor
    private let journalStore: RoomJournalStore
    private let snapshotStore: RoomSnapshotStore
    private var connectedClientIDs: Set<ClientID> = []
    private var deliveriesByClientID: [ClientID: [RoomGatewayDelivery]] = [:]
    private var ephemeralByClientID: [ClientID: [RoomGatewayEphemeralDelivery]] = [:]

    init(
        actor: RoomActor,
        journalStore: RoomJournalStore,
        snapshotStore: RoomSnapshotStore
    ) {
        self.actor = actor
        self.journalStore = journalStore
        self.snapshotStore = snapshotStore
    }

    func connect(clientID: ClientID, knownRoomSeq: UInt64?) throws -> RoomGatewayCatchUp {
        connectedClientIDs.insert(clientID)

        let currentSnapshot = actor.snapshot
        let currentRoomSeq = currentSnapshot.roomSeq
        let normalizedKnownRoomSeq = knownRoomSeq ?? 0

        let catchUp: RoomGatewayCatchUp
        if knownRoomSeq == nil || normalizedKnownRoomSeq == 0 {
            catchUp = RoomGatewayCatchUp(
                roomID: currentSnapshot.roomID,
                knownRoomSeq: knownRoomSeq,
                currentRoomSeq: currentRoomSeq,
                mode: .coldJoin,
                baseSnapshot: currentSnapshot,
                tailRecords: []
            )
        } else if normalizedKnownRoomSeq >= currentRoomSeq {
            catchUp = RoomGatewayCatchUp(
                roomID: currentSnapshot.roomID,
                knownRoomSeq: knownRoomSeq,
                currentRoomSeq: currentRoomSeq,
                mode: .upToDate,
                baseSnapshot: nil,
                tailRecords: []
            )
        } else if let persistedSnapshot = try snapshotStore.latestSnapshot(for: currentSnapshot.roomID)?.snapshot,
                  persistedSnapshot.roomSeq > normalizedKnownRoomSeq
        {
            catchUp = RoomGatewayCatchUp(
                roomID: currentSnapshot.roomID,
                knownRoomSeq: knownRoomSeq,
                currentRoomSeq: currentRoomSeq,
                mode: .snapshotAndTail,
                baseSnapshot: persistedSnapshot,
                tailRecords: try journalStore.records(for: currentSnapshot.roomID, after: persistedSnapshot.roomSeq)
            )
        } else {
            catchUp = RoomGatewayCatchUp(
                roomID: currentSnapshot.roomID,
                knownRoomSeq: knownRoomSeq,
                currentRoomSeq: currentRoomSeq,
                mode: .tailOnly,
                baseSnapshot: nil,
                tailRecords: try journalStore.records(for: currentSnapshot.roomID, after: normalizedKnownRoomSeq)
            )
        }

        Observability.metric(
            "room.connect_total",
            value: 1,
            unit: "count",
            dimensions: [
                "room_id": currentSnapshot.roomID.rawValue,
                "client_id": clientID.rawValue,
                "mode": catchUp.mode.rawValue,
            ]
        )
        Observability.log(
            domain: "room",
            component: "room-gateway",
            event: "client_connected",
            fields: [
                "room_id": currentSnapshot.roomID.rawValue,
                "client_id": clientID.rawValue,
                "known_room_seq": knownRoomSeq.map(String.init) ?? "none",
                "current_room_seq": String(currentRoomSeq),
                "mode": catchUp.mode.rawValue,
            ]
        )
        return catchUp
    }

    @discardableResult
    func submit(_ op: RoomOpRecord, from clientID: ClientID) throws -> AppliedRoomOp {
        connectedClientIDs.insert(clientID)
        do {
            let applied = try actor.apply(op)
            if applied.wasDuplicate {
                deliveriesByClientID[clientID, default: []].append(.duplicate(applied.record))
            } else {
                broadcast(.accepted(applied.record))
                broadcastLeaseUpdates(for: applied.sideEffects)
                Observability.metric(
                    "room.apply_total",
                    value: 1,
                    unit: "count",
                    dimensions: [
                        "room_id": applied.record.roomID.rawValue,
                        "client_id": clientID.rawValue,
                    ]
                )
                Observability.log(
                    domain: "room",
                    component: "room-gateway",
                    event: "op_applied",
                    fields: [
                        "room_id": applied.record.roomID.rawValue,
                        "client_id": clientID.rawValue,
                        "op_id": applied.record.opID.rawValue,
                        "room_seq": String(applied.record.roomSeq ?? 0),
                    ]
                )
            }
            return applied
        } catch {
            let reject = RoomGatewayReject(
                roomID: actor.snapshot.roomID,
                clientID: clientID,
                opID: op.opID,
                reason: error.localizedDescription
            )
            deliveriesByClientID[clientID, default: []].append(.rejected(reject))
            Observability.metric(
                "room.reject_total",
                value: 1,
                unit: "count",
                dimensions: [
                    "room_id": actor.snapshot.roomID.rawValue,
                    "client_id": clientID.rawValue,
                ]
            )
            Observability.log(
                domain: "room",
                component: "room-gateway",
                event: "op_rejected",
                level: "error",
                fields: [
                    "room_id": actor.snapshot.roomID.rawValue,
                    "client_id": clientID.rawValue,
                    "op_id": op.opID.rawValue,
                    "reason": reject.reason,
                ]
            )
            throw reject
        }
    }

    func deliveries(for clientID: ClientID) -> [RoomGatewayDelivery] {
        deliveriesByClientID[clientID, default: []]
    }

    func ephemeralDeliveries(for clientID: ClientID) -> [RoomGatewayEphemeralDelivery] {
        ephemeralByClientID[clientID, default: []]
    }

    func publishPresence(_ payload: String) {
        broadcastEphemeral(.presence(payload))
    }

    func publishSession(_ payload: String) {
        broadcastEphemeral(.session(payload))
    }

    private func broadcastLeaseUpdates(for sideEffects: [RoomActorSideEffect]) {
        for sideEffect in sideEffects {
            switch sideEffect {
            case .controlAcquired(let sessionID, _), .controlReleased(let sessionID):
                broadcastEphemeral(.leaseUpdated(sessionID, actor.controlLease(for: sessionID)))
            case .sessionAttached, .sessionDetached, .sessionResizeCommitted:
                break
            }
        }
    }

    private func broadcast(_ delivery: RoomGatewayDelivery) {
        for clientID in connectedClientIDs {
            deliveriesByClientID[clientID, default: []].append(delivery)
        }
    }

    private func broadcastEphemeral(_ delivery: RoomGatewayEphemeralDelivery) {
        for clientID in connectedClientIDs {
            ephemeralByClientID[clientID, default: []].append(delivery)
        }
    }
}
