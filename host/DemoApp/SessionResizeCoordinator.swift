import Foundation

final class SessionResizeCoordinator {
    private let directory: SessionDirectory
    private let automaticallyAcknowledgeResizes: Bool
    private var logLinesBySessionID: [SessionID: [String]] = [:]

    init(
        directory: SessionDirectory,
        automaticallyAcknowledgeResizes: Bool = true
    ) {
        self.directory = directory
        self.automaticallyAcknowledgeResizes = automaticallyAcknowledgeResizes
    }

    func apply(_ applied: AppliedRoomOp) {
        guard let revision = applied.record.roomSeq else { return }
        for sideEffect in applied.sideEffects {
            guard case .sessionResizeCommitted(_, let sessionID, let size) = sideEffect else {
                continue
            }
            applyAuthoritativeResize(
                sessionID: sessionID,
                size: size,
                revision: revision,
                reason: "room_commit"
            )
        }
    }

    func reconcile(snapshot: DurableRoomSnapshot) {
        for surface in snapshot.surfaces {
            guard let sessionID = surface.sessionID else { continue }
            applyAuthoritativeResize(
                sessionID: sessionID,
                size: TerminalSessionSize(cols: surface.cols, rows: surface.rows),
                revision: snapshot.roomSeq,
                reason: "reconnect"
            )
        }
    }

    func acknowledge(sessionID: SessionID) {
        guard let session = directory.session(for: sessionID) else { return }
        let reconciliation = session.acknowledgePendingResize(revision: session.state().resizeReconciliation.revision)
        appendLog(
            sessionID: sessionID,
            line: "session_id=\(sessionID.rawValue) action=acknowledge revision=\(reconciliation.revision) phase=\(reconciliation.phase.rawValue)"
        )
    }

    func retry(sessionID: SessionID) {
        guard let session = directory.session(for: sessionID) else { return }
        let reconciliation = session.state().resizeReconciliation
        applyAuthoritativeResize(
            sessionID: sessionID,
            size: reconciliation.desiredSize,
            revision: reconciliation.revision,
            reason: "retry"
        )
    }

    func logLines(for sessionID: SessionID) -> [String] {
        logLinesBySessionID[sessionID, default: []]
    }

    private func applyAuthoritativeResize(
        sessionID: SessionID,
        size: TerminalSessionSize,
        revision: UInt64,
        reason: String
    ) {
        guard let session = directory.session(for: sessionID) else {
            appendLog(
                sessionID: sessionID,
                line: "session_id=\(sessionID.rawValue) action=missing_session revision=\(revision) desired=\(size.cols)x\(size.rows) reason=\(reason)"
            )
            return
        }

        do {
            let began = try session.beginAuthoritativeResize(to: size, revision: revision)
            appendLog(
                sessionID: sessionID,
                line: "session_id=\(sessionID.rawValue) action=room_commit revision=\(revision) desired=\(size.cols)x\(size.rows) actual=\(began.actualSize.cols)x\(began.actualSize.rows) phase=\(began.phase.rawValue) reason=\(reason)"
            )

            guard began.phase == .desired else {
                appendLog(
                    sessionID: sessionID,
                    line: "session_id=\(sessionID.rawValue) action=idempotent revision=\(revision) phase=\(began.phase.rawValue)"
                )
                return
            }

            let applied = try session.applyPendingResize(revision: revision)
            appendLog(
                sessionID: sessionID,
                line: "session_id=\(sessionID.rawValue) action=apply revision=\(revision) actual=\(applied.actualSize.cols)x\(applied.actualSize.rows) phase=\(applied.phase.rawValue)"
            )

            guard automaticallyAcknowledgeResizes else {
                appendLog(
                    sessionID: sessionID,
                    line: "session_id=\(sessionID.rawValue) action=ui_lag revision=\(revision) desired=\(applied.desiredSize.cols)x\(applied.desiredSize.rows) actual=\(applied.actualSize.cols)x\(applied.actualSize.rows) phase=\(applied.phase.rawValue)"
                )
                return
            }

            let acknowledged = session.acknowledgePendingResize(revision: revision)
            appendLog(
                sessionID: sessionID,
                line: "session_id=\(sessionID.rawValue) action=ack revision=\(revision) desired=\(acknowledged.desiredSize.cols)x\(acknowledged.desiredSize.rows) actual=\(acknowledged.actualSize.cols)x\(acknowledged.actualSize.rows) phase=\(acknowledged.phase.rawValue)"
            )
        } catch {
            let current = session.state().resizeReconciliation
            appendLog(
                sessionID: sessionID,
                line: "session_id=\(sessionID.rawValue) action=failed revision=\(revision) desired=\(current.desiredSize.cols)x\(current.desiredSize.rows) actual=\(current.actualSize.cols)x\(current.actualSize.rows) phase=\(current.phase.rawValue) error=\(error.localizedDescription)"
            )
        }
    }

    private func appendLog(sessionID: SessionID, line: String) {
        logLinesBySessionID[sessionID, default: []].append(line)
    }
}
