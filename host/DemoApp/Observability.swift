import Foundation

struct ObservabilityMetric: Codable, Equatable {
    let name: String
    let value: Double
    let unit: String
    let tsMillis: UInt64
    let dimensions: [String: String]
}

struct ObservabilityLogRecord: Codable, Equatable {
    let domain: String
    let component: String
    let event: String
    let level: String
    let tsMillis: UInt64
    let fields: [String: String]
}

protocol ObservabilitySink: AnyObject {
    func record(metric: ObservabilityMetric)
    func record(log: ObservabilityLogRecord)
}

final class ObservabilityRecorder: ObservabilitySink {
    private(set) var metrics: [ObservabilityMetric] = []
    private(set) var logs: [ObservabilityLogRecord] = []

    func record(metric: ObservabilityMetric) {
        metrics.append(metric)
    }

    func record(log: ObservabilityLogRecord) {
        logs.append(log)
    }
}

enum Observability {
    nonisolated(unsafe) static var sink: ObservabilitySink?
    nonisolated(unsafe) static var nowMillis: () -> UInt64 = {
        UInt64(Date().timeIntervalSince1970 * 1_000)
    }

    static func metric(
        _ name: String,
        value: Double,
        unit: String,
        dimensions: [String: String] = [:]
    ) {
        sink?.record(metric: ObservabilityMetric(
            name: name,
            value: value,
            unit: unit,
            tsMillis: nowMillis(),
            dimensions: dimensions
        ))
    }

    static func log(
        domain: String,
        component: String,
        event: String,
        level: String = "info",
        fields: [String: String] = [:]
    ) {
        sink?.record(log: ObservabilityLogRecord(
            domain: domain,
            component: component,
            event: event,
            level: level,
            tsMillis: nowMillis(),
            fields: fields
        ))
    }
}

enum GhosttyObservability {
    static func recordPasteAudit(
        surfaceID: String,
        textByteCount: Int,
        bracketed: Bool
    ) {
        let dimensions = [
            "surface_id": surfaceID,
            "bracketed": bracketed ? "true" : "false",
        ]
        Observability.metric("ghostty.paste_bytes", value: Double(textByteCount), unit: "bytes", dimensions: dimensions)
        Observability.log(
            domain: "ghostty",
            component: "ghostty-adapter",
            event: "paste_routed",
            fields: [
                "surface_id": surfaceID,
                "text_bytes": String(textByteCount),
                "bracketed": bracketed ? "true" : "false",
            ]
        )
    }

    static func recordResize(
        surfaceID: String,
        width: Int,
        height: Int,
        backingScale: Double
    ) {
        Observability.metric(
            "ghostty.resize_total",
            value: 1,
            unit: "count",
            dimensions: ["surface_id": surfaceID]
        )
        Observability.log(
            domain: "ghostty",
            component: "ghostty-adapter",
            event: "surface_resized",
            fields: [
                "surface_id": surfaceID,
                "pixel_width": String(width),
                "pixel_height": String(height),
                "backing_scale": String(format: "%.2f", backingScale),
            ]
        )
    }

    static func recordTexturePublishRequest(
        surfaceID: String,
        generation: UInt64
    ) {
        Observability.metric(
            "ghostty.texture_publish_total",
            value: 1,
            unit: "count",
            dimensions: [
                "surface_id": surfaceID,
                "generation": String(generation),
            ]
        )
        Observability.log(
            domain: "ghostty",
            component: "ghostty-adapter",
            event: "texture_publish_requested",
            fields: [
                "surface_id": surfaceID,
                "generation": String(generation),
            ]
        )
    }
}
