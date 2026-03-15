import Foundation

struct RoomID: RawRepresentable, Hashable, Codable, CustomStringConvertible {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    var description: String { rawValue }
}

struct RoomOpID: RawRepresentable, Hashable, Codable, CustomStringConvertible {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    var description: String { rawValue }
}

struct SessionID: RawRepresentable, Hashable, Codable, CustomStringConvertible {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    var description: String { rawValue }
}

struct UserID: RawRepresentable, Hashable, Codable, CustomStringConvertible {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    var description: String { rawValue }
}

struct ClientID: RawRepresentable, Hashable, Codable, CustomStringConvertible {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    var description: String { rawValue }
}

enum RoomSchemaVersion: Int, Codable {
    case v1 = 1
}

enum DurableSurfaceState: String, Codable {
    case provisioning
    case attached
    case disconnected
    case error
    case closing
}

enum RoomSessionStatus: String, Codable {
    case provisioning
    case running
    case exited
    case failed
}

enum TerminalBootstrapPolicy: String, Codable {
    case redraw
}

enum RoomSchemaValidationError: Error, Equatable, LocalizedError {
    case emptyField(String)
    case nonPositiveDimension(String)
    case negativeStackRank
    case duplicateSurfaceID(TerminalSurfaceID)
    case duplicateStackRank(Int)
    case nonDenseStackRank(expected: Int, actual: Int)
    case duplicateSessionAttachment(SessionID)
    case missingSessionForAttachedSurface(TerminalSurfaceID)
    case leaseMissingHolder
    case leaseExpirationNotAfterAcquired

    var errorDescription: String? {
        switch self {
        case .emptyField(let field):
            return "\(field) must not be empty"
        case .nonPositiveDimension(let field):
            return "\(field) must be positive"
        case .negativeStackRank:
            return "stack_rank must be non-negative"
        case .duplicateSurfaceID(let surfaceID):
            return "duplicate surface_id \(surfaceID.rawValue)"
        case .duplicateStackRank(let rank):
            return "duplicate stack_rank \(rank)"
        case .nonDenseStackRank(let expected, let actual):
            return "expected dense stack_rank \(expected) but found \(actual)"
        case .duplicateSessionAttachment(let sessionID):
            return "session_id \(sessionID.rawValue) is attached more than once"
        case .missingSessionForAttachedSurface(let surfaceID):
            return "attached surface \(surfaceID.rawValue) requires session_id"
        case .leaseMissingHolder:
            return "lease requires holder_user_id"
        case .leaseExpirationNotAfterAcquired:
            return "lease expires_at must be after acquired_at"
        }
    }
}

struct DurableRoomSurface: Codable, Equatable, Identifiable {
    let id: TerminalSurfaceID
    var sessionID: SessionID?
    var xWorld: Double
    var yWorld: Double
    var cols: Int
    var rows: Int
    var stackRank: Int
    var profileID: String
    var title: String?
    var state: DurableSurfaceState
    var createdBy: UserID
    var createdAtMillis: UInt64

    func validate() throws {
        guard !id.rawValue.isEmpty else {
            throw RoomSchemaValidationError.emptyField("surface_id")
        }
        guard cols > 0 else {
            throw RoomSchemaValidationError.nonPositiveDimension("cols")
        }
        guard rows > 0 else {
            throw RoomSchemaValidationError.nonPositiveDimension("rows")
        }
        guard stackRank >= 0 else {
            throw RoomSchemaValidationError.negativeStackRank
        }
        guard !profileID.isEmpty else {
            throw RoomSchemaValidationError.emptyField("profile_id")
        }
        guard !createdBy.rawValue.isEmpty else {
            throw RoomSchemaValidationError.emptyField("created_by")
        }
        if state == .attached, sessionID == nil {
            throw RoomSchemaValidationError.missingSessionForAttachedSurface(id)
        }
    }
}

struct DurableRoomSnapshot: Codable, Equatable {
    let schemaVersion: RoomSchemaVersion
    let roomID: RoomID
    let roomSeq: UInt64
    let renderProfileIDs: [String]
    let surfaces: [DurableRoomSurface]
    let controlLeases: [ControlLeaseRecord]

    func validate() throws {
        guard !roomID.rawValue.isEmpty else {
            throw RoomSchemaValidationError.emptyField("room_id")
        }

        var surfaceIDs = Set<TerminalSurfaceID>()
        var stackRanks = Set<Int>()
        var attachedSessionIDs = Set<SessionID>()
        for surface in surfaces {
            try surface.validate()
            if !surfaceIDs.insert(surface.id).inserted {
                throw RoomSchemaValidationError.duplicateSurfaceID(surface.id)
            }
            if !stackRanks.insert(surface.stackRank).inserted {
                throw RoomSchemaValidationError.duplicateStackRank(surface.stackRank)
            }
            if let sessionID = surface.sessionID,
               !attachedSessionIDs.insert(sessionID).inserted
            {
                throw RoomSchemaValidationError.duplicateSessionAttachment(sessionID)
            }
        }
        for (index, surface) in surfaces.enumerated() {
            if surface.stackRank != index {
                throw RoomSchemaValidationError.nonDenseStackRank(
                    expected: index,
                    actual: surface.stackRank
                )
            }
        }
        for lease in controlLeases {
            try lease.validate()
        }
    }
}

struct CreateSurfaceOp: Codable, Equatable {
    var surfaceID: TerminalSurfaceID
    var xWorld: Double
    var yWorld: Double
    var cols: Int
    var rows: Int
    var profileID: String
    var terminalTemplate: String?
}

struct MoveSurfaceOp: Codable, Equatable {
    var surfaceID: TerminalSurfaceID
    var xWorld: Double
    var yWorld: Double
}

struct ResizeSurfaceOp: Codable, Equatable {
    var surfaceID: TerminalSurfaceID
    var cols: Int
    var rows: Int
}

struct SetStackRankOp: Codable, Equatable {
    var surfaceID: TerminalSurfaceID
    var targetRank: Int
}

struct CloseSurfaceOp: Codable, Equatable {
    var surfaceID: TerminalSurfaceID
}

struct SetSurfaceTitleOp: Codable, Equatable {
    var surfaceID: TerminalSurfaceID
    var title: String?
}

struct AttachSessionOp: Codable, Equatable {
    var surfaceID: TerminalSurfaceID
    var sessionID: SessionID
}

struct DetachSessionOp: Codable, Equatable {
    var surfaceID: TerminalSurfaceID
}

struct AcquireControlOp: Codable, Equatable {
    var sessionID: SessionID
    var holderUserID: UserID
}

struct ReleaseControlOp: Codable, Equatable {
    var sessionID: SessionID
}

enum RoomOperationPayload: Equatable {
    case createSurface(CreateSurfaceOp)
    case moveSurface(MoveSurfaceOp)
    case resizeSurface(ResizeSurfaceOp)
    case setStackRank(SetStackRankOp)
    case closeSurface(CloseSurfaceOp)
    case setSurfaceTitle(SetSurfaceTitleOp)
    case attachSession(AttachSessionOp)
    case detachSession(DetachSessionOp)
    case acquireControl(AcquireControlOp)
    case releaseControl(ReleaseControlOp)
}

extension RoomOperationPayload: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case payload
    }

    private enum Kind: String, Codable {
        case createSurface = "create_surface"
        case moveSurface = "move_surface"
        case resizeSurface = "resize_surface"
        case setStackRank = "set_stack_rank"
        case closeSurface = "close_surface"
        case setSurfaceTitle = "set_surface_title"
        case attachSession = "attach_session"
        case detachSession = "detach_session"
        case acquireControl = "acquire_control"
        case releaseControl = "release_control"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .createSurface:
            self = .createSurface(try container.decode(CreateSurfaceOp.self, forKey: .payload))
        case .moveSurface:
            self = .moveSurface(try container.decode(MoveSurfaceOp.self, forKey: .payload))
        case .resizeSurface:
            self = .resizeSurface(try container.decode(ResizeSurfaceOp.self, forKey: .payload))
        case .setStackRank:
            self = .setStackRank(try container.decode(SetStackRankOp.self, forKey: .payload))
        case .closeSurface:
            self = .closeSurface(try container.decode(CloseSurfaceOp.self, forKey: .payload))
        case .setSurfaceTitle:
            self = .setSurfaceTitle(try container.decode(SetSurfaceTitleOp.self, forKey: .payload))
        case .attachSession:
            self = .attachSession(try container.decode(AttachSessionOp.self, forKey: .payload))
        case .detachSession:
            self = .detachSession(try container.decode(DetachSessionOp.self, forKey: .payload))
        case .acquireControl:
            self = .acquireControl(try container.decode(AcquireControlOp.self, forKey: .payload))
        case .releaseControl:
            self = .releaseControl(try container.decode(ReleaseControlOp.self, forKey: .payload))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .createSurface(let payload):
            try container.encode(Kind.createSurface, forKey: .kind)
            try container.encode(payload, forKey: .payload)
        case .moveSurface(let payload):
            try container.encode(Kind.moveSurface, forKey: .kind)
            try container.encode(payload, forKey: .payload)
        case .resizeSurface(let payload):
            try container.encode(Kind.resizeSurface, forKey: .kind)
            try container.encode(payload, forKey: .payload)
        case .setStackRank(let payload):
            try container.encode(Kind.setStackRank, forKey: .kind)
            try container.encode(payload, forKey: .payload)
        case .closeSurface(let payload):
            try container.encode(Kind.closeSurface, forKey: .kind)
            try container.encode(payload, forKey: .payload)
        case .setSurfaceTitle(let payload):
            try container.encode(Kind.setSurfaceTitle, forKey: .kind)
            try container.encode(payload, forKey: .payload)
        case .attachSession(let payload):
            try container.encode(Kind.attachSession, forKey: .kind)
            try container.encode(payload, forKey: .payload)
        case .detachSession(let payload):
            try container.encode(Kind.detachSession, forKey: .kind)
            try container.encode(payload, forKey: .payload)
        case .acquireControl(let payload):
            try container.encode(Kind.acquireControl, forKey: .kind)
            try container.encode(payload, forKey: .payload)
        case .releaseControl(let payload):
            try container.encode(Kind.releaseControl, forKey: .kind)
            try container.encode(payload, forKey: .payload)
        }
    }
}

extension RoomOperationPayload {
    func validate() throws {
        switch self {
        case .createSurface(let op):
            guard !op.surfaceID.rawValue.isEmpty else {
                throw RoomSchemaValidationError.emptyField("surface_id")
            }
            guard op.cols > 0 else {
                throw RoomSchemaValidationError.nonPositiveDimension("cols")
            }
            guard op.rows > 0 else {
                throw RoomSchemaValidationError.nonPositiveDimension("rows")
            }
            guard !op.profileID.isEmpty else {
                throw RoomSchemaValidationError.emptyField("profile_id")
            }
        case .moveSurface(let op):
            guard !op.surfaceID.rawValue.isEmpty else {
                throw RoomSchemaValidationError.emptyField("surface_id")
            }
        case .resizeSurface(let op):
            guard !op.surfaceID.rawValue.isEmpty else {
                throw RoomSchemaValidationError.emptyField("surface_id")
            }
            guard op.cols > 0 else {
                throw RoomSchemaValidationError.nonPositiveDimension("cols")
            }
            guard op.rows > 0 else {
                throw RoomSchemaValidationError.nonPositiveDimension("rows")
            }
        case .setStackRank(let op):
            guard !op.surfaceID.rawValue.isEmpty else {
                throw RoomSchemaValidationError.emptyField("surface_id")
            }
            guard op.targetRank >= 0 else {
                throw RoomSchemaValidationError.negativeStackRank
            }
        case .closeSurface(let op):
            guard !op.surfaceID.rawValue.isEmpty else {
                throw RoomSchemaValidationError.emptyField("surface_id")
            }
        case .setSurfaceTitle(let op):
            guard !op.surfaceID.rawValue.isEmpty else {
                throw RoomSchemaValidationError.emptyField("surface_id")
            }
        case .attachSession(let op):
            guard !op.surfaceID.rawValue.isEmpty else {
                throw RoomSchemaValidationError.emptyField("surface_id")
            }
            guard !op.sessionID.rawValue.isEmpty else {
                throw RoomSchemaValidationError.emptyField("session_id")
            }
        case .detachSession(let op):
            guard !op.surfaceID.rawValue.isEmpty else {
                throw RoomSchemaValidationError.emptyField("surface_id")
            }
        case .acquireControl(let op):
            guard !op.sessionID.rawValue.isEmpty else {
                throw RoomSchemaValidationError.emptyField("session_id")
            }
            guard !op.holderUserID.rawValue.isEmpty else {
                throw RoomSchemaValidationError.emptyField("holder_user_id")
            }
        case .releaseControl(let op):
            guard !op.sessionID.rawValue.isEmpty else {
                throw RoomSchemaValidationError.emptyField("session_id")
            }
        }
    }
}

struct RoomOpRecord: Codable, Equatable {
    let schemaVersion: RoomSchemaVersion
    let roomID: RoomID
    let roomSeq: UInt64?
    let opID: RoomOpID
    let clientID: ClientID
    let submittedAtMillis: UInt64
    let payload: RoomOperationPayload

    func validate() throws {
        guard !roomID.rawValue.isEmpty else {
            throw RoomSchemaValidationError.emptyField("room_id")
        }
        guard !opID.rawValue.isEmpty else {
            throw RoomSchemaValidationError.emptyField("op_id")
        }
        guard !clientID.rawValue.isEmpty else {
            throw RoomSchemaValidationError.emptyField("client_id")
        }
        try payload.validate()
    }
}

struct RoomSnapshotRecord: Codable, Equatable {
    let roomID: RoomID
    let roomSeq: UInt64
    let schemaVersion: RoomSchemaVersion
    let checksum: String
    let snapshot: DurableRoomSnapshot
    let writtenAtMillis: UInt64

    func validate() throws {
        guard !checksum.isEmpty else {
            throw RoomSchemaValidationError.emptyField("checksum")
        }
        try snapshot.validate()
    }
}

struct SessionAttachmentRecord: Codable, Equatable {
    let sessionID: SessionID
    let roomID: RoomID
    let surfaceID: TerminalSurfaceID
    let cols: Int
    let rows: Int
    let bootstrapPolicy: TerminalBootstrapPolicy
    let status: RoomSessionStatus
    let updatedAtMillis: UInt64

    func validate() throws {
        guard !sessionID.rawValue.isEmpty else {
            throw RoomSchemaValidationError.emptyField("session_id")
        }
        guard !roomID.rawValue.isEmpty else {
            throw RoomSchemaValidationError.emptyField("room_id")
        }
        guard !surfaceID.rawValue.isEmpty else {
            throw RoomSchemaValidationError.emptyField("surface_id")
        }
        guard cols > 0 else {
            throw RoomSchemaValidationError.nonPositiveDimension("cols")
        }
        guard rows > 0 else {
            throw RoomSchemaValidationError.nonPositiveDimension("rows")
        }
    }
}

struct ControlLeaseRecord: Codable, Equatable {
    let sessionID: SessionID
    let holderUserID: UserID?
    let leaseEpoch: UInt64
    let acquiredAtMillis: UInt64
    let expiresAtMillis: UInt64

    func validate() throws {
        guard !sessionID.rawValue.isEmpty else {
            throw RoomSchemaValidationError.emptyField("session_id")
        }
        guard holderUserID != nil else {
            throw RoomSchemaValidationError.leaseMissingHolder
        }
        guard expiresAtMillis > acquiredAtMillis else {
            throw RoomSchemaValidationError.leaseExpirationNotAfterAcquired
        }
    }
}
