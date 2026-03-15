import Foundation

struct FrameInvalidationReasons: OptionSet, Equatable {
    let rawValue: UInt8

    static let camera = FrameInvalidationReasons(rawValue: 1 << 0)
    static let surfaces = FrameInvalidationReasons(rawValue: 1 << 1)
    static let texture = FrameInvalidationReasons(rawValue: 1 << 2)
    static let timer = FrameInvalidationReasons(rawValue: 1 << 3)
    static let overlay = FrameInvalidationReasons(rawValue: 1 << 4)
}

struct FrameScheduler {
    private(set) var pendingReasons: FrameInvalidationReasons = []
    private(set) var scheduled = false

    mutating func invalidate(_ reasons: FrameInvalidationReasons) -> Bool {
        guard !reasons.isEmpty else { return false }
        pendingReasons.formUnion(reasons)
        let shouldSchedule = !scheduled
        scheduled = true
        return shouldSchedule
    }

    mutating func consumePendingDraw() -> FrameInvalidationReasons? {
        guard scheduled, !pendingReasons.isEmpty else { return nil }
        let reasons = pendingReasons
        pendingReasons = []
        scheduled = false
        return reasons
    }
}
