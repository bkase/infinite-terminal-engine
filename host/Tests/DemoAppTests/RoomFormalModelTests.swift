import XCTest
@testable import DemoApp

final class RoomFormalModelTests: XCTestCase {
    func testSmallStateModelMatchesImplementation() throws {
        for sequence in generatedSequences(depth: 4) {
            let modelResult = try runModel(sequence)
            let implementationResult = try runImplementation(sequence)

            XCTAssertEqual(
                implementationResult.outcomes,
                modelResult.outcomes,
                "sequence: \(describe(sequence))"
            )
            XCTAssertEqual(
                implementationResult.snapshot,
                modelResult.snapshot,
                "sequence: \(describe(sequence))"
            )
        }
    }

    func testSnapshotReplayEquivalenceAcrossModelSequences() throws {
        for sequence in generatedSequences(depth: 4) {
            let acceptedRecords = try acceptedImplementationRecords(sequence)
            guard acceptedRecords.count >= 2 else { continue }

            let splitIndex = acceptedRecords.count / 2
            let prefix = Array(acceptedRecords.prefix(splitIndex))
            let suffix = Array(acceptedRecords.dropFirst(splitIndex))
            let baseSnapshot = try RoomStateReducer.replay(snapshot: emptySnapshot(), records: prefix)
            let replayed = try RoomStateReducer.replay(snapshot: baseSnapshot, records: suffix)
            let uninterrupted = try RoomStateReducer.replay(snapshot: emptySnapshot(), records: acceptedRecords)

            XCTAssertEqual(replayed, uninterrupted, "sequence: \(describe(sequence))")
        }
    }

    private func runModel(_ sequence: [ModelStep]) throws -> ModelRunResult {
        var model = FormalRoomModel(snapshot: emptySnapshot())
        var outcomes: [ModelOutcome] = []
        for step in sequence {
            outcomes.append(try model.apply(step.record))
        }
        return ModelRunResult(snapshot: model.snapshot, outcomes: outcomes)
    }

    private func runImplementation(_ sequence: [ModelStep]) throws -> ModelRunResult {
        let actor = makeActor()
        var outcomes: [ModelOutcome] = []
        for step in sequence {
            do {
                let applied = try actor.apply(step.record)
                outcomes.append(applied.wasDuplicate ? .duplicate(applied.record.opID.rawValue) : .accepted)
            } catch {
                outcomes.append(.rejected(error.localizedDescription))
            }
        }
        return ModelRunResult(snapshot: actor.snapshot, outcomes: outcomes)
    }

    private func acceptedImplementationRecords(_ sequence: [ModelStep]) throws -> [RoomOpRecord] {
        let actor = makeActor()
        var accepted: [RoomOpRecord] = []
        for step in sequence {
            if let applied = try? actor.apply(step.record), !applied.wasDuplicate {
                accepted.append(applied.record)
            }
        }
        return accepted
    }

    private func generatedSequences(depth: Int) -> [[ModelStep]] {
        let catalog = modelCatalog()
        var sequences: [[ModelStep]] = [[]]
        guard depth > 0 else { return sequences }

        for _ in 0..<depth {
            var next: [[ModelStep]] = []
            for sequence in sequences {
                for step in catalog {
                    next.append(sequence + [step])
                }
            }
            sequences += next
        }

        return sequences
    }

    private func modelCatalog() -> [ModelStep] {
        [
            ModelStep(
                label: "create-s1",
                record: record(opID: "create-s1", payload: .createSurface(CreateSurfaceOp(
                    surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
                    xWorld: 0,
                    yWorld: 0,
                    cols: 80,
                    rows: 24,
                    profileID: "profile",
                    terminalTemplate: nil
                )))
            ),
            ModelStep(
                label: "create-s2",
                record: record(opID: "create-s2", payload: .createSurface(CreateSurfaceOp(
                    surfaceID: TerminalSurfaceID(rawValue: "surface-2"),
                    xWorld: 20,
                    yWorld: 20,
                    cols: 100,
                    rows: 30,
                    profileID: "profile",
                    terminalTemplate: nil
                )))
            ),
            ModelStep(
                label: "move-s1",
                record: record(opID: "move-s1", payload: .moveSurface(MoveSurfaceOp(
                    surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
                    xWorld: 24,
                    yWorld: 40
                )))
            ),
            ModelStep(
                label: "resize-s1",
                record: record(opID: "resize-s1", payload: .resizeSurface(ResizeSurfaceOp(
                    surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
                    cols: 120,
                    rows: 40
                )))
            ),
            ModelStep(
                label: "rank-s2-front",
                record: record(opID: "rank-s2-front", payload: .setStackRank(SetStackRankOp(
                    surfaceID: TerminalSurfaceID(rawValue: "surface-2"),
                    targetRank: 0
                )))
            ),
            ModelStep(
                label: "attach-s1-session-1",
                record: record(opID: "attach-s1", payload: .attachSession(AttachSessionOp(
                    surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
                    sessionID: SessionID(rawValue: "session-1")
                )))
            ),
            ModelStep(
                label: "attach-s2-session-1",
                record: record(opID: "attach-s2", payload: .attachSession(AttachSessionOp(
                    surfaceID: TerminalSurfaceID(rawValue: "surface-2"),
                    sessionID: SessionID(rawValue: "session-1")
                )))
            ),
            ModelStep(
                label: "acquire-session-1",
                record: record(opID: "lease-acquire", payload: .acquireControl(AcquireControlOp(
                    sessionID: SessionID(rawValue: "session-1"),
                    holderUserID: UserID(rawValue: "user-1")
                )))
            ),
            ModelStep(
                label: "release-session-1",
                record: record(opID: "lease-release", payload: .releaseControl(ReleaseControlOp(
                    sessionID: SessionID(rawValue: "session-1")
                )))
            ),
            ModelStep(
                label: "duplicate-create-s1",
                record: record(opID: "create-s1", payload: .moveSurface(MoveSurfaceOp(
                    surfaceID: TerminalSurfaceID(rawValue: "surface-2"),
                    xWorld: 99,
                    yWorld: 99
                )))
            ),
        ]
    }

    private func describe(_ sequence: [ModelStep]) -> String {
        sequence.map(\.label).joined(separator: " -> ")
    }

    private func makeActor() -> RoomActor {
        RoomActor(
            snapshot: emptySnapshot(),
            journalStore: InMemoryRoomJournalStore(),
            snapshotStore: InMemoryRoomSnapshotStore(),
            snapshotInterval: 2
        )
    }

    private func emptySnapshot() -> DurableRoomSnapshot {
        DurableRoomSnapshot(
            schemaVersion: .v1,
            roomID: RoomID(rawValue: "room-1"),
            roomSeq: 0,
            renderProfileIDs: ["profile"],
            surfaces: [],
            controlLeases: []
        )
    }

    private func record(opID: String, payload: RoomOperationPayload) -> RoomOpRecord {
        RoomOpRecord(
            schemaVersion: .v1,
            roomID: RoomID(rawValue: "room-1"),
            roomSeq: nil,
            opID: RoomOpID(rawValue: opID),
            clientID: ClientID(rawValue: "client-1"),
            submittedAtMillis: 100,
            payload: payload
        )
    }
}

private struct ModelStep {
    let label: String
    let record: RoomOpRecord
}

private struct ModelRunResult {
    let snapshot: DurableRoomSnapshot
    let outcomes: [ModelOutcome]
}

private enum ModelOutcome: Equatable {
    case accepted
    case duplicate(String)
    case rejected(String)
}

private struct FormalRoomModel {
    private(set) var snapshot: DurableRoomSnapshot
    private var seenOpIDs: Set<RoomOpID> = []
    private var leaseBySessionID: [SessionID: ControlLeaseRecord]
    private var lastLeaseEpochBySessionID: [SessionID: UInt64]

    init(snapshot: DurableRoomSnapshot) {
        self.snapshot = snapshot
        self.leaseBySessionID = Dictionary(uniqueKeysWithValues: snapshot.controlLeases.map { ($0.sessionID, $0) })
        self.lastLeaseEpochBySessionID = Dictionary(uniqueKeysWithValues: snapshot.controlLeases.map { ($0.sessionID, $0.leaseEpoch) })
    }

    mutating func apply(_ record: RoomOpRecord) throws -> ModelOutcome {
        if seenOpIDs.contains(record.opID) {
            return .duplicate(record.opID.rawValue)
        }
        do {
            let next = try reduce(record)
            seenOpIDs.insert(record.opID)
            snapshot = next
            return .accepted
        } catch {
            return .rejected(error.localizedDescription)
        }
    }

    private mutating func reduce(_ record: RoomOpRecord) throws -> DurableRoomSnapshot {
        var surfaces = snapshot.surfaces

        func surfaceIndex(for surfaceID: TerminalSurfaceID) throws -> Int {
            guard let index = surfaces.firstIndex(where: { $0.id == surfaceID }) else {
                throw RoomActorError.surfaceNotFound(surfaceID)
            }
            return index
        }

        switch record.payload {
        case .createSurface(let op):
            guard snapshot.renderProfileIDs.contains(op.profileID) else {
                throw RoomActorError.unknownProfileID(op.profileID)
            }
            guard !surfaces.contains(where: { $0.id == op.surfaceID }) else {
                throw RoomActorError.surfaceAlreadyExists(op.surfaceID)
            }
            surfaces.append(
                DurableRoomSurface(
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
                    createdAtMillis: record.submittedAtMillis
                )
            )
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
            guard !surfaces.contains(where: { $0.sessionID == op.sessionID }) else {
                throw RoomActorError.sessionAttachedElsewhere(op.sessionID)
            }
            surfaces[index].sessionID = op.sessionID
            surfaces[index].state = .attached
        case .detachSession(let op):
            let index = try surfaceIndex(for: op.surfaceID)
            guard surfaces[index].sessionID != nil else {
                throw RoomActorError.noSessionAttached(op.surfaceID)
            }
            surfaces[index].sessionID = nil
            surfaces[index].state = .disconnected
        case .acquireControl(let op):
            guard surfaces.contains(where: { $0.sessionID == op.sessionID }) else {
                throw RoomActorError.sessionNotAttached(op.sessionID)
            }
            if let existingLease = leaseBySessionID[op.sessionID] {
                guard existingLease.holderUserID == op.holderUserID else {
                    throw RoomActorError.controlLeaseHeldByAnotherUser(
                        op.sessionID,
                        holderUserID: existingLease.holderUserID ?? UserID(rawValue: "unknown")
                    )
                }
            } else {
                let nextEpoch = (lastLeaseEpochBySessionID[op.sessionID] ?? 0) + 1
                lastLeaseEpochBySessionID[op.sessionID] = nextEpoch
                leaseBySessionID[op.sessionID] = ControlLeaseRecord(
                    sessionID: op.sessionID,
                    holderUserID: op.holderUserID,
                    leaseEpoch: nextEpoch,
                    acquiredAtMillis: record.submittedAtMillis,
                    expiresAtMillis: record.submittedAtMillis + 30_000
                )
            }
        case .releaseControl(let op):
            guard surfaces.contains(where: { $0.sessionID == op.sessionID }) else {
                throw RoomActorError.sessionNotAttached(op.sessionID)
            }
            leaseBySessionID.removeValue(forKey: op.sessionID)
        }

        let nextSnapshot = DurableRoomSnapshot(
            schemaVersion: snapshot.schemaVersion,
            roomID: snapshot.roomID,
            roomSeq: snapshot.roomSeq + 1,
            renderProfileIDs: snapshot.renderProfileIDs,
            surfaces: surfaces,
            controlLeases: leaseBySessionID.values.sorted { $0.sessionID.rawValue < $1.sessionID.rawValue }
        )
        try nextSnapshot.validate()
        return nextSnapshot
    }
}
