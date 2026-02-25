//
//  SettingsAuditTrail.swift
//  Quotio
//
//  Tracks important setting mutations for local auditability.
//

import Foundation
import Observation

nonisolated enum PrivacyRedactor {
    private static let sensitiveKeyNeedles: [String] = [
        "authorization",
        "cookie",
        "x-api-key",
        "api-key",
        "api_key",
        "apikey",
        "token",
        "password",
        "secret",
        "bearer",
        "access_token",
        "refresh_token",
    ]

    private static let urlKeyNeedles: [String] = [
        "url",
        "endpoint",
        "host",
        "proxy",
    ]

    static func isSensitiveKey(_ key: String) -> Bool {
        let normalized = key.lowercased()
        return sensitiveKeyNeedles.contains { normalized.contains($0) }
    }

    static func isURLKey(_ key: String) -> Bool {
        let normalized = key.lowercased()
        return urlKeyNeedles.contains { normalized.contains($0) }
    }

    static func maskValue(_ value: String) -> String {
        guard !value.isEmpty else { return value }
        let chars = Array(value)
        let count = chars.count
        if count <= 4 {
            return "[masked len=\(count) ***]"
        }
        let prefix = String(chars.prefix(2))
        let suffix = String(chars.suffix(2))
        return "[masked len=\(count) \(prefix)...\(suffix)]"
    }

    static func redactEndpointQuery(_ endpoint: String) -> String {
        guard endpoint.contains("?") else { return endpoint }
        let placeholder = "https://quotio.local"
        let normalizedPath = endpoint.hasPrefix("/") ? endpoint : "/" + endpoint
        guard var components = URLComponents(string: placeholder + normalizedPath),
              let queryItems = components.queryItems else {
            return endpoint
        }
        components.queryItems = queryItems.map { item in
            guard item.value != nil else { return item }
            return URLQueryItem(name: item.name, value: "[redacted]")
        }
        let pathPart = components.percentEncodedPath
        guard let encodedQuery = components.percentEncodedQuery else {
            return endpoint.hasPrefix("/") ? pathPart : String(pathPart.dropFirst())
        }
        let sanitized = "\(pathPart)?\(encodedQuery)"
        return endpoint.hasPrefix("/") ? sanitized : String(sanitized.dropFirst())
    }

    static func redactURLLikeString(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return value }

        guard var components = URLComponents(string: trimmed),
              components.scheme != nil || components.host != nil else {
            return value
        }

        if components.user != nil { components.user = nil }
        if components.password != nil { components.password = nil }
        if let queryItems = components.queryItems {
            components.queryItems = queryItems.map { item in
                guard item.value != nil else { return item }
                return URLQueryItem(name: item.name, value: "[redacted]")
            }
        }
        components.fragment = nil
        return components.string ?? value
    }

    static func redactStructuredText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }
        guard let data = trimmed.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data) else {
            return redactLooseText(trimmed)
        }
        let redacted = redactJSONValue(jsonObject, parentKey: nil)
        guard JSONSerialization.isValidJSONObject(redacted),
              let redactedData = try? JSONSerialization.data(withJSONObject: redacted, options: [.sortedKeys]),
              let result = String(data: redactedData, encoding: .utf8) else {
            return maskValue(trimmed)
        }
        return result
    }

    private static func redactJSONValue(_ value: Any, parentKey: String?) -> Any {
        if let dict = value as? [String: Any] {
            var copy: [String: Any] = [:]
            for (key, nestedValue) in dict {
                if isSensitiveKey(key) {
                    copy[key] = maskValue(String(describing: nestedValue))
                } else if isURLKey(key), let stringValue = nestedValue as? String {
                    copy[key] = redactURLLikeString(stringValue)
                } else {
                    copy[key] = redactJSONValue(nestedValue, parentKey: key)
                }
            }
            return copy
        }
        if let array = value as? [Any] {
            return array.map { redactJSONValue($0, parentKey: parentKey) }
        }
        if let stringValue = value as? String {
            if let parentKey, isSensitiveKey(parentKey) {
                return maskValue(stringValue)
            }
            if let parentKey, isURLKey(parentKey) {
                return redactURLLikeString(stringValue)
            }
            return redactURLLikeString(stringValue)
        }
        return value
    }

    private static func redactLooseText(_ text: String) -> String {
        let queryRedacted = redactEndpointQuery(text)
        guard queryRedacted == text else { return queryRedacted }

        var output = text
        let patterns: [String] = [
            #"(?i)(\b(?:authorization|cookie|x-api-key|api[-_]?key|access_token|refresh_token|token|password|secret|bearer)\b\s*[=:]\s*)(["']?)([^\s"'&;]+)"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            let range = NSRange(output.startIndex..<output.endIndex, in: output)
            output = regex.stringByReplacingMatches(
                in: output,
                options: [],
                range: range,
                withTemplate: "$1$2[redacted]"
            )
        }

        return redactURLLikeString(output)
    }
}

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

    private static func auditValue(for key: String, value: String) -> String {
        if PrivacyRedactor.isSensitiveKey(key) {
            return PrivacyRedactor.maskValue(value)
        }
        if PrivacyRedactor.isURLKey(key) {
            return PrivacyRedactor.redactURLLikeString(value)
        }
        return value
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
        guard oldValue != newValue else { return }
        let rawOld = Self.auditValue(for: key, value: oldValue)
        let rawNew = Self.auditValue(for: key, value: newValue)
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
        let sanitizedEvents = events.map {
            SettingsAuditEvent(
                id: $0.id,
                timestamp: $0.timestamp,
                key: $0.key,
                oldValue: Self.auditValue(for: $0.key, value: $0.oldValue),
                newValue: Self.auditValue(for: $0.key, value: $0.newValue),
                source: $0.source
            )
        }
        let store = SettingsAuditStore(version: SettingsAuditStore.currentVersion, events: sanitizedEvents)
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
