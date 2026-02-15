//
//  UIBaselineMetricsTracker.swift
//  Quotio
//
//  Lightweight UI metric tracker for baseline and regressions.
//

import Foundation
import Observation

nonisolated struct UIMetricEvent: Codable, Sendable, Identifiable {
    let id: UUID
    let name: String
    let timestamp: Date
    let durationMs: Int?
    let metadata: String?

    init(
        id: UUID = UUID(),
        name: String,
        timestamp: Date = Date(),
        durationMs: Int? = nil,
        metadata: String? = nil
    ) {
        self.id = id
        self.name = name
        self.timestamp = timestamp
        self.durationMs = durationMs
        self.metadata = metadata
    }
}

nonisolated struct UIMetricStore: Codable, Sendable {
    let version: Int
    var events: [UIMetricEvent]

    static let currentVersion = 1
    static let maxEvents = 500
}

@MainActor
@Observable
final class UIBaselineMetricsTracker {
    static let shared = UIBaselineMetricsTracker()

    private(set) var events: [UIMetricEvent] = []
    private var startTimes: [String: Date] = [:]

    private let fileQueue = DispatchQueue(label: "dev.quotio.desktop.ui-metrics-file")

    private var storageURL: URL {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Application Support directory not found")
        }
        let dir = appSupport.appendingPathComponent("Quotio")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("ui-metrics.json")
    }

    private init() {
        loadFromDisk()
    }

    func begin(_ name: String) {
        startTimes[name] = Date()
    }

    func end(_ name: String, metadata: String? = nil) {
        let now = Date()
        let started = startTimes.removeValue(forKey: name)
        let durationMs = started.map { Int(now.timeIntervalSince($0) * 1000) }
        append(name: name, durationMs: durationMs, metadata: metadata)
    }

    func mark(_ name: String, metadata: String? = nil) {
        append(name: name, durationMs: nil, metadata: metadata)
    }

    func recentEvents(limit: Int = 50) -> [UIMetricEvent] {
        Array(events.suffix(limit))
    }

    func exportData() throws -> Data {
        let store = UIMetricStore(version: UIMetricStore.currentVersion, events: events)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(store)
    }

    private func append(name: String, durationMs: Int?, metadata: String?) {
        let event = UIMetricEvent(name: name, durationMs: durationMs, metadata: metadata)
        events.append(event)
        if events.count > UIMetricStore.maxEvents {
            events = Array(events.suffix(UIMetricStore.maxEvents))
        }
        if let durationMs {
            NSLog("[UIMetrics] \(name) duration=\(durationMs)ms metadata=\(metadata ?? "-")")
        } else {
            NSLog("[UIMetrics] \(name) metadata=\(metadata ?? "-")")
        }
        saveToDisk()
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let store = try decoder.decode(UIMetricStore.self, from: data)
            events = store.events
        } catch {
            NSLog("[UIMetrics] Failed to load metrics: \(error.localizedDescription)")
            events = []
        }
    }

    private func saveToDisk() {
        let snapshot = UIMetricStore(version: UIMetricStore.currentVersion, events: events)
        let targetURL = storageURL
        fileQueue.async {
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(snapshot)
                try data.write(to: targetURL, options: .atomic)
            } catch {
                NSLog("[UIMetrics] Failed to save metrics: \(error.localizedDescription)")
            }
        }
    }
}
