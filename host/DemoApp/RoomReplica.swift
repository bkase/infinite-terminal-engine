import Foundation

struct PendingRoomOp: Equatable {
    let record: RoomOpRecord
}

final class RoomReplica {
    private let clientID: ClientID
    private(set) var authoritativeSnapshot: DurableRoomSnapshot
    private(set) var predictedSnapshot: DurableRoomSnapshot
    private(set) var pendingOps: [PendingRoomOp] = []
    private(set) var timeline: [String] = []
    private var bufferedAuthoritativeBySeq: [UInt64: RoomOpRecord] = [:]
    private var seenAuthoritativeOpIDs: Set<RoomOpID> = []
    private var nextLocalOpOrdinal: UInt64 = 1
    private var nextSubmittedAtMillis: UInt64 = 1

    init(clientID: ClientID, snapshot: DurableRoomSnapshot) {
        self.clientID = clientID
        self.authoritativeSnapshot = snapshot
        self.predictedSnapshot = snapshot
    }

    @discardableResult
    func submit(_ payload: RoomOperationPayload) throws -> RoomOpRecord {
        let record = RoomOpRecord(
            schemaVersion: authoritativeSnapshot.schemaVersion,
            roomID: authoritativeSnapshot.roomID,
            roomSeq: nil,
            opID: RoomOpID(rawValue: "\(clientID.rawValue)-op-\(nextLocalOpOrdinal)"),
            clientID: clientID,
            submittedAtMillis: nextSubmittedAtMillis,
            payload: payload
        )
        nextLocalOpOrdinal += 1
        nextSubmittedAtMillis += 1

        pendingOps.append(PendingRoomOp(record: record))
        do {
            try rebasePending()
            timeline.append("submit \(record.opID.rawValue) pending=\(pendingOps.count)")
            return record
        } catch {
            _ = pendingOps.popLast()
            throw error
        }
    }

    func receiveAccepted(_ record: RoomOpRecord) throws {
        if seenAuthoritativeOpIDs.contains(record.opID) || (record.roomSeq ?? 0) <= authoritativeSnapshot.roomSeq {
            timeline.append("duplicate-accept \(record.opID.rawValue)")
            return
        }
        guard let roomSeq = record.roomSeq else {
            return
        }
        bufferedAuthoritativeBySeq[roomSeq] = record
        try drainBufferedAuthoritative()
    }

    func receiveRejected(_ reject: RoomGatewayReject) throws {
        let originalCount = pendingOps.count
        pendingOps.removeAll { $0.record.opID == reject.opID }
        guard pendingOps.count != originalCount else {
            timeline.append("reject-ignored \(reject.opID.rawValue)")
            return
        }
        timeline.append("reject \(reject.opID.rawValue) reason=\(reject.reason)")
        try rebasePending()
    }

    func reconnect(_ catchUp: RoomGatewayCatchUp) throws {
        authoritativeSnapshot = try catchUp.reconstructReplica(existingSnapshot: authoritativeSnapshot)
        bufferedAuthoritativeBySeq = [:]
        seenAuthoritativeOpIDs = []
        timeline.append("reconnect mode=\(catchUp.mode.rawValue) room_seq=\(authoritativeSnapshot.roomSeq)")
        try rebasePending()
    }

    private func drainBufferedAuthoritative() throws {
        while let next = bufferedAuthoritativeBySeq[authoritativeSnapshot.roomSeq + 1] {
            bufferedAuthoritativeBySeq.removeValue(forKey: authoritativeSnapshot.roomSeq + 1)
            authoritativeSnapshot = try RoomStateReducer.replay(snapshot: authoritativeSnapshot, records: [next])
            seenAuthoritativeOpIDs.insert(next.opID)
            pendingOps.removeAll { $0.record.opID == next.opID }
            timeline.append("accept \(next.opID.rawValue) room_seq=\(next.roomSeq ?? 0)")
            try rebasePending()
        }
    }

    private func rebasePending() throws {
        predictedSnapshot = try RoomStateReducer.replay(
            snapshot: authoritativeSnapshot,
            records: pendingOps.map(\.record)
        )
        timeline.append("rebase authoritative=\(authoritativeSnapshot.roomSeq) pending=\(pendingOps.count)")
    }
}
