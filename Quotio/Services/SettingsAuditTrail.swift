//
//  SettingsAuditTrail.swift
//  Quotio
//
//  Tracks important setting mutations for local auditability.
//

import Foundation
import Observation

nonisolated struct SettingsAuditEvent: Codable, Sendable, Identifiable {
    let id: UUID
    let timestamp: Date
    let key: String
    let oldValue: String
    let newValue: String
    let source: String

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        key: String,
        oldValue: String,
        newValue: String,
        source: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.key = key
        self.oldValue = oldValue
        self.newValue = newValue
        self.source = source
    }
}

nonisolated struct SettingsAuditStore: Codable, Sendable {
    let version: Int
    var events: [SettingsAuditEvent]

    static let currentVersion = 1
    static let maxEvents = 1000
}

@MainActor
@Observable
final class SettingsAuditTrail {
    static let shared = SettingsAuditTrail()

    private(set) var events: [SettingsAuditEvent] = []
    private let fileQueue = DispatchQueue(label: "dev.quotio.desktop.settings-audit-file")

    private static func baseDirectory() -> URL {
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return appSupport
        }
        Log.warning("Application Support directory unavailable, falling back to temporary directory")
        return FileManager.default.temporaryDirectory
    }

    private static func auditValue(_ value: String) -> String {
        value
    }

    private var storageURL: URL {
        let dir = Self.baseDirectory().appendingPathComponent("Quotio")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            Log.warning("Failed to create settings audit directory: \(error.localizedDescription)")
        }
        return dir.appendingPathComponent("settings-audit.json")
    }

    private init() {
        loadFromDisk()
    }

    func recordChange(key: String, oldValue: String, newValue: String, source: String) {
        let rawOld = Self.auditValue(oldValue)
        let rawNew = Self.auditValue(newValue)
        guard rawOld != rawNew else { return }
        let event = SettingsAuditEvent(key: key, oldValue: rawOld, newValue: rawNew, source: source)
        events.insert(event, at: 0)
        if events.count > SettingsAuditStore.maxEvents {
            events = Array(events.prefix(SettingsAuditStore.maxEvents))
        }
        Log.debug("[SettingsAudit] \(key) changed source=\(source)")
        saveToDisk()
    }

    func recent(limit: Int = 50) -> [SettingsAuditEvent] {
        Array(events.prefix(limit))
    }

    func clear() {
        events = []
        saveToDisk()
    }

    func exportData() throws -> Data {
        let store = SettingsAuditStore(version: SettingsAuditStore.currentVersion, events: events)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(store)
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let store = try decoder.decode(SettingsAuditStore.self, from: data)
            events = store.events
        } catch {
            Log.warning("[SettingsAudit] Failed to load audit log: \(error.localizedDescription)")
            events = []
        }
    }

    private func saveToDisk() {
        let snapshot = SettingsAuditStore(version: SettingsAuditStore.currentVersion, events: events)
        let targetURL = storageURL
        fileQueue.async {
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(snapshot)
                try data.write(to: targetURL, options: .atomic)
            } catch {
                Log.warning("[SettingsAudit] Failed to save audit log: \(error.localizedDescription)")
            }
        }
    }
}
