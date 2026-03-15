import Foundation

enum RoomActorError: Error, Equatable, LocalizedError {
    case roomMismatch
    case unknownProfileID(String)
    case surfaceAlreadyExists(TerminalSurfaceID)
    case surfaceNotFound(TerminalSurfaceID)
    case sessionAlreadyAttached(TerminalSurfaceID)
    case noSessionAttached(TerminalSurfaceID)
    case duplicateOpID(RoomOpID)

    var errorDescription: String? {
        switch self {
        case .roomMismatch:
            return "room_id does not match actor room"
        case .unknownProfileID(let profileID):
            return "profile \(profileID) is not registered for the room"
        case .surfaceAlreadyExists(let surfaceID):
            return "surface \(surfaceID.rawValue) already exists"
        case .surfaceNotFound(let surfaceID):
            return "surface \(surfaceID.rawValue) not found"
        case .sessionAlreadyAttached(let surfaceID):
            return "surface \(surfaceID.rawValue) already has a session"
        case .noSessionAttached(let surfaceID):
            return "surface \(surfaceID.rawValue) has no session"
        case .duplicateOpID(let opID):
            return "op \(opID.rawValue) already applied"
        }
    }
}

enum RoomActorSideEffect: Equatable {
    case sessionAttached(surfaceID: TerminalSurfaceID, sessionID: SessionID)
    case sessionDetached(surfaceID: TerminalSurfaceID, sessionID: SessionID)
    case controlAcquired(sessionID: SessionID, holderUserID: UserID)
    case controlReleased(sessionID: SessionID)
}

struct AppliedRoomOp: Equatable {
    let record: RoomOpRecord
    let snapshot: DurableRoomSnapshot
    let sideEffects: [RoomActorSideEffect]
    let wasDuplicate: Bool
}

protocol RoomJournalStore {
    func append(_ record: RoomOpRecord) throws
    func records(for roomID: RoomID, after roomSeq: UInt64) throws -> [RoomOpRecord]
    func record(roomID: RoomID, opID: RoomOpID) throws -> RoomOpRecord?
}

protocol RoomSnapshotStore {
    func latestSnapshot(for roomID: RoomID) throws -> RoomSnapshotRecord?
    func write(_ record: RoomSnapshotRecord) throws
}

final class InMemoryRoomJournalStore: RoomJournalStore {
    private var recordsByRoomID: [RoomID: [RoomOpRecord]] = [:]

    func append(_ record: RoomOpRecord) throws {
        recordsByRoomID[record.roomID, default: []].append(record)
    }

    func records(for roomID: RoomID, after roomSeq: UInt64) throws -> [RoomOpRecord] {
        recordsByRoomID[roomID, default: []]
            .filter { ($0.roomSeq ?? 0) > roomSeq }
            .sorted { ($0.roomSeq ?? 0) < ($1.roomSeq ?? 0) }
    }

    func record(roomID: RoomID, opID: RoomOpID) throws -> RoomOpRecord? {
        recordsByRoomID[roomID, default: []].first { $0.opID == opID }
    }
}

final class InMemoryRoomSnapshotStore: RoomSnapshotStore {
    private var snapshotsByRoomID: [RoomID: [RoomSnapshotRecord]] = [:]

    func latestSnapshot(for roomID: RoomID) throws -> RoomSnapshotRecord? {
        snapshotsByRoomID[roomID, default: []].max { $0.roomSeq < $1.roomSeq }
    }

    func write(_ record: RoomSnapshotRecord) throws {
        snapshotsByRoomID[record.roomID, default: []].append(record)
    }
}

final class RoomActor {
    private(set) var snapshot: DurableRoomSnapshot
    private let journalStore: RoomJournalStore
    private let snapshotStore: RoomSnapshotStore
    private let snapshotInterval: UInt64
    private var leaseBySessionID: [SessionID: ControlLeaseRecord] = [:]
    private var lastLeaseEpochBySessionID: [SessionID: UInt64] = [:]

    init(
        snapshot: DurableRoomSnapshot,
        journalStore: RoomJournalStore,
        snapshotStore: RoomSnapshotStore,
        snapshotInterval: UInt64 = 10
    ) {
        self.snapshot = snapshot
        self.journalStore = journalStore
        self.snapshotStore = snapshotStore
        self.snapshotInterval = max(snapshotInterval, 1)
        self.leaseBySessionID = Dictionary(
            uniqueKeysWithValues: snapshot.controlLeases.map { ($0.sessionID, $0) }
        )
        self.lastLeaseEpochBySessionID = Dictionary(
            uniqueKeysWithValues: snapshot.controlLeases.map { ($0.sessionID, $0.leaseEpoch) }
        )
    }

    static func recover(
        roomID: RoomID,
        journalStore: RoomJournalStore,
        snapshotStore: RoomSnapshotStore,
        snapshotInterval: UInt64 = 10
    ) throws -> RoomActor {
        let baseSnapshot = try snapshotStore.latestSnapshot(for: roomID)?.snapshot
            ?? DurableRoomSnapshot(
                schemaVersion: .v1,
                roomID: roomID,
                roomSeq: 0,
                renderProfileIDs: [],
                surfaces: [],
                controlLeases: []
            )
        let actor = RoomActor(
            snapshot: baseSnapshot,
            journalStore: journalStore,
            snapshotStore: snapshotStore,
            snapshotInterval: snapshotInterval
        )
        let replayRecords = try journalStore.records(for: roomID, after: baseSnapshot.roomSeq)
        for record in replayRecords {
            let applied = try actor.applyRecord(record, to: actor.snapshot)
            actor.snapshot = applied.snapshot
            actor.applySideEffects(applied.sideEffects, submittedAtMillis: record.submittedAtMillis)
            try actor.refreshSnapshotControlLeases()
        }
        return actor
    }

    func apply(_ op: RoomOpRecord) throws -> AppliedRoomOp {
        if let existing = try journalStore.record(roomID: snapshot.roomID, opID: op.opID) {
            return AppliedRoomOp(record: existing, snapshot: snapshot, sideEffects: [], wasDuplicate: true)
        }
        guard op.roomID == snapshot.roomID else {
            throw RoomActorError.roomMismatch
        }

        var sequenced = op
        sequenced = RoomOpRecord(
            schemaVersion: op.schemaVersion,
            roomID: op.roomID,
            roomSeq: snapshot.roomSeq + 1,
            opID: op.opID,
            clientID: op.clientID,
            submittedAtMillis: op.submittedAtMillis,
            payload: op.payload
        )
        try sequenced.validate()

        let applied = try applyRecord(sequenced, to: snapshot)
        try journalStore.append(sequenced)
        snapshot = applied.snapshot
        applySideEffects(applied.sideEffects, submittedAtMillis: sequenced.submittedAtMillis)
        try refreshSnapshotControlLeases()

        if snapshot.roomSeq.isMultiple(of: snapshotInterval) {
            try snapshotStore.write(
                RoomSnapshotRecord(
                    roomID: snapshot.roomID,
                    roomSeq: snapshot.roomSeq,
                    schemaVersion: snapshot.schemaVersion,
                    checksum: Self.checksum(for: snapshot),
                    snapshot: snapshot,
                    writtenAtMillis: sequenced.submittedAtMillis
                )
            )
        }

        return AppliedRoomOp(
            record: sequenced,
            snapshot: snapshot,
            sideEffects: applied.sideEffects,
            wasDuplicate: false
        )
    }

    private func applyRecord(_ record: RoomOpRecord, to snapshot: DurableRoomSnapshot) throws -> AppliedRoomOp {
        let nextSnapshot = try Self.apply(record.payload, to: snapshot, submittedAtMillis: record.submittedAtMillis)
        let sequencedSnapshot = DurableRoomSnapshot(
            schemaVersion: snapshot.schemaVersion,
            roomID: snapshot.roomID,
            roomSeq: record.roomSeq ?? snapshot.roomSeq,
            renderProfileIDs: nextSnapshot.snapshot.renderProfileIDs,
            surfaces: nextSnapshot.snapshot.surfaces,
            controlLeases: nextSnapshot.snapshot.controlLeases
        )
        try sequencedSnapshot.validate()
        return AppliedRoomOp(
            record: record,
            snapshot: sequencedSnapshot,
            sideEffects: nextSnapshot.sideEffects,
            wasDuplicate: false
        )
    }

    private func applySideEffects(_ sideEffects: [RoomActorSideEffect], submittedAtMillis: UInt64) {
        for leaseEffect in sideEffects {
            switch leaseEffect {
            case .controlAcquired(let sessionID, let holderUserID):
                let nextEpoch = (lastLeaseEpochBySessionID[sessionID] ?? 0) + 1
                lastLeaseEpochBySessionID[sessionID] = nextEpoch
                leaseBySessionID[sessionID] = ControlLeaseRecord(
                    sessionID: sessionID,
                    holderUserID: holderUserID,
                    leaseEpoch: nextEpoch,
                    acquiredAtMillis: submittedAtMillis,
                    expiresAtMillis: submittedAtMillis + 30_000
                )
            case .controlReleased(let sessionID):
                leaseBySessionID.removeValue(forKey: sessionID)
            case .sessionAttached, .sessionDetached:
                break
            }
        }
    }

    private static func apply(
        _ payload: RoomOperationPayload,
        to snapshot: DurableRoomSnapshot,
        submittedAtMillis: UInt64
    ) throws -> (snapshot: DurableRoomSnapshot, sideEffects: [RoomActorSideEffect]) {
        var surfaces = snapshot.surfaces
        var sideEffects: [RoomActorSideEffect] = []

        func surfaceIndex(for surfaceID: TerminalSurfaceID) throws -> Int {
            guard let index = surfaces.firstIndex(where: { $0.id == surfaceID }) else {
                throw RoomActorError.surfaceNotFound(surfaceID)
            }
            return index
        }

        switch payload {
        case .createSurface(let op):
            guard snapshot.renderProfileIDs.contains(op.profileID) else {
                throw RoomActorError.unknownProfileID(op.profileID)
            }
            guard !surfaces.contains(where: { $0.id == op.surfaceID }) else {
                throw RoomActorError.surfaceAlreadyExists(op.surfaceID)
            }
            let surface = DurableRoomSurface(
                id: op.surfaceID,
                sessionID: nil,
                xWorld: op.xWorld,
                yWorld: op.yWorld,
                cols: op.cols,
                rows: op.rows,
                stackRank: surfaces.count,
                profileID: op.profileID,
                title: nil,
                state: .provisioning,
                createdBy: UserID(rawValue: "client-generated"),
                createdAtMillis: submittedAtMillis
            )
            surfaces.append(surface)
        case .moveSurface(let op):
            let index = try surfaceIndex(for: op.surfaceID)
            surfaces[index].xWorld = op.xWorld
            surfaces[index].yWorld = op.yWorld
        case .resizeSurface(let op):
            let index = try surfaceIndex(for: op.surfaceID)
            surfaces[index].cols = op.cols
            surfaces[index].rows = op.rows
        case .setStackRank(let op):
            let index = try surfaceIndex(for: op.surfaceID)
            let surface = surfaces.remove(at: index)
            let targetRank = min(max(op.targetRank, 0), surfaces.count)
            surfaces.insert(surface, at: targetRank)
            for rank in surfaces.indices {
                surfaces[rank].stackRank = rank
            }
        case .closeSurface(let op):
            let index = try surfaceIndex(for: op.surfaceID)
            surfaces.remove(at: index)
            for rank in surfaces.indices {
                surfaces[rank].stackRank = rank
            }
        case .setSurfaceTitle(let op):
            let index = try surfaceIndex(for: op.surfaceID)
            surfaces[index].title = op.title
        case .attachSession(let op):
            let index = try surfaceIndex(for: op.surfaceID)
            guard surfaces[index].sessionID == nil else {
                throw RoomActorError.sessionAlreadyAttached(op.surfaceID)
            }
            surfaces[index].sessionID = op.sessionID
            surfaces[index].state = .attached
            sideEffects.append(.sessionAttached(surfaceID: op.surfaceID, sessionID: op.sessionID))
        case .detachSession(let op):
            let index = try surfaceIndex(for: op.surfaceID)
            guard let sessionID = surfaces[index].sessionID else {
                throw RoomActorError.noSessionAttached(op.surfaceID)
            }
            surfaces[index].sessionID = nil
            surfaces[index].state = .disconnected
            sideEffects.append(.sessionDetached(surfaceID: op.surfaceID, sessionID: sessionID))
        case .acquireControl(let op):
            sideEffects.append(.controlAcquired(sessionID: op.sessionID, holderUserID: op.holderUserID))
        case .releaseControl(let op):
            sideEffects.append(.controlReleased(sessionID: op.sessionID))
        }

        let next = DurableRoomSnapshot(
            schemaVersion: snapshot.schemaVersion,
            roomID: snapshot.roomID,
            roomSeq: snapshot.roomSeq,
            renderProfileIDs: snapshot.renderProfileIDs,
            surfaces: surfaces,
            controlLeases: snapshot.controlLeases
        )
        try next.validate()
        return (snapshot: next, sideEffects: sideEffects)
    }

    private static func checksum(for snapshot: DurableRoomSnapshot) throws -> String {
        let data = try JSONEncoder().encode(snapshot)
        var hasher = Hasher()
        hasher.combine(data.count)
        for byte in data {
            hasher.combine(byte)
        }
        return String(hasher.finalize(), radix: 16)
    }

    func controlLease(for sessionID: SessionID) -> ControlLeaseRecord? {
        leaseBySessionID[sessionID]
    }

    private func refreshSnapshotControlLeases() throws {
        snapshot = DurableRoomSnapshot(
            schemaVersion: snapshot.schemaVersion,
            roomID: snapshot.roomID,
            roomSeq: snapshot.roomSeq,
            renderProfileIDs: snapshot.renderProfileIDs,
            surfaces: snapshot.surfaces,
            controlLeases: leaseBySessionID.values.sorted { lhs, rhs in
                lhs.sessionID.rawValue < rhs.sessionID.rawValue
            }
        )
        try snapshot.validate()
    }
}
