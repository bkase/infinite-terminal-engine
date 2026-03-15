import CoreGraphics
import Foundation

struct TerminalSurfaceID: Hashable, Codable, RawRepresentable, CustomStringConvertible {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    var description: String { rawValue }
}

struct TerminalSurfaceFlags: OptionSet, Codable, Equatable {
    let rawValue: UInt8

    static let focused = TerminalSurfaceFlags(rawValue: 1 << 0)
    static let hidden = TerminalSurfaceFlags(rawValue: 1 << 1)
    static let acceptsInput = TerminalSurfaceFlags(rawValue: 1 << 2)

    init(rawValue: UInt8) {
        self.rawValue = rawValue
    }
}

struct TerminalSurface: Equatable, Codable, Identifiable {
    let id: TerminalSurfaceID
    var sessionID: String
    var origin: CGPoint
    var cols: Int
    var rows: Int
    var profileID: String
    var stackRank: Int
    var flags: TerminalSurfaceFlags
}

struct TerminalSurfaceGeometry: Equatable {
    let frame: CGRect
    let contentFrame: CGRect
    let titlebarFrame: CGRect
    let pixelSize: CGSize
}

struct SurfaceStore {
    private var ids: [TerminalSurfaceID] = []
    private var sessionIDs: [String] = []
    private var origins: [CGPoint] = []
    private var cols: [Int] = []
    private var rows: [Int] = []
    private var profileIDs: [String] = []
    private var stackRanks: [Int] = []
    private var flags: [TerminalSurfaceFlags] = []
    private var indexByID: [TerminalSurfaceID: Int] = [:]

    var count: Int { ids.count }
    var isEmpty: Bool { ids.isEmpty }

    func surface(id: TerminalSurfaceID) -> TerminalSurface? {
        guard let index = indexByID[id] else { return nil }
        return surface(at: index)
    }

    func contains(_ id: TerminalSurfaceID) -> Bool {
        indexByID[id] != nil
    }

    func orderedSurfaceIDs() -> [TerminalSurfaceID] {
        ids.indices.sorted(by: compareForOrdering).map { ids[$0] }
    }

    func orderedSurfaces() -> [TerminalSurface] {
        orderedSurfaceIDs().compactMap(surface(id:))
    }

    mutating func upsert(_ surface: TerminalSurface) {
        if let index = indexByID[surface.id] {
            sessionIDs[index] = surface.sessionID
            origins[index] = surface.origin
            cols[index] = surface.cols
            rows[index] = surface.rows
            profileIDs[index] = surface.profileID
            stackRanks[index] = surface.stackRank
            flags[index] = surface.flags
            return
        }

        let newIndex = ids.count
        ids.append(surface.id)
        sessionIDs.append(surface.sessionID)
        origins.append(surface.origin)
        cols.append(surface.cols)
        rows.append(surface.rows)
        profileIDs.append(surface.profileID)
        stackRanks.append(surface.stackRank)
        flags.append(surface.flags)
        indexByID[surface.id] = newIndex
    }

    @discardableResult
    mutating func remove(_ id: TerminalSurfaceID) -> TerminalSurface? {
        guard let index = indexByID.removeValue(forKey: id) else { return nil }
        let removed = surface(at: index)

        ids.remove(at: index)
        sessionIDs.remove(at: index)
        origins.remove(at: index)
        cols.remove(at: index)
        rows.remove(at: index)
        profileIDs.remove(at: index)
        stackRanks.remove(at: index)
        flags.remove(at: index)

        for shiftedIndex in index..<ids.count {
            indexByID[ids[shiftedIndex]] = shiftedIndex
        }

        return removed
    }

    mutating func replaceAll(with surfaces: [TerminalSurface]) {
        self = SurfaceStore()
        reserveCapacity(surfaces.count)
        for surface in surfaces {
            upsert(surface)
        }
    }

    mutating func reserveCapacity(_ minimumCapacity: Int) {
        ids.reserveCapacity(minimumCapacity)
        sessionIDs.reserveCapacity(minimumCapacity)
        origins.reserveCapacity(minimumCapacity)
        cols.reserveCapacity(minimumCapacity)
        rows.reserveCapacity(minimumCapacity)
        profileIDs.reserveCapacity(minimumCapacity)
        stackRanks.reserveCapacity(minimumCapacity)
        flags.reserveCapacity(minimumCapacity)
        indexByID.reserveCapacity(minimumCapacity)
    }

    func geometry(
        for id: TerminalSurfaceID,
        profilesByID: [String: RenderProfile],
        backingScale: CGFloat
    ) -> TerminalSurfaceGeometry? {
        guard let surface = surface(id: id) else { return nil }
        return Self.geometry(for: surface, profilesByID: profilesByID, backingScale: backingScale)
    }

    static func geometry(
        for surface: TerminalSurface,
        profilesByID: [String: RenderProfile],
        backingScale: CGFloat
    ) -> TerminalSurfaceGeometry? {
        guard let profile = profilesByID[surface.profileID] else { return nil }
        let logicalSize = profile.surfaceLogicalSize(cols: surface.cols, rows: surface.rows)
        let frame = CGRect(origin: surface.origin, size: logicalSize)
        let contentOrigin = CGPoint(
            x: frame.minX + profile.paddingX,
            y: frame.minY + profile.titlebarHeight + profile.paddingY
        )
        let contentSize = CGSize(
            width: CGFloat(surface.cols) * profile.cellWidth,
            height: CGFloat(surface.rows) * profile.lineHeight
        )
        let contentFrame = CGRect(origin: contentOrigin, size: contentSize)
        let titlebarFrame = CGRect(
            x: frame.minX,
            y: frame.minY,
            width: frame.width,
            height: profile.titlebarHeight
        )
        return TerminalSurfaceGeometry(
            frame: frame,
            contentFrame: contentFrame,
            titlebarFrame: titlebarFrame,
            pixelSize: profile.surfacePixelSize(
                cols: surface.cols,
                rows: surface.rows,
                backingScale: backingScale
            )
        )
    }

    private func surface(at index: Int) -> TerminalSurface {
        TerminalSurface(
            id: ids[index],
            sessionID: sessionIDs[index],
            origin: origins[index],
            cols: cols[index],
            rows: rows[index],
            profileID: profileIDs[index],
            stackRank: stackRanks[index],
            flags: flags[index]
        )
    }

    private func compareForOrdering(lhs: Int, rhs: Int) -> Bool {
        if stackRanks[lhs] != stackRanks[rhs] {
            return stackRanks[lhs] < stackRanks[rhs]
        }
        return ids[lhs].rawValue < ids[rhs].rawValue
    }
}
