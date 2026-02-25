//
//  RequestTracker.swift
//  Quotio - Request History Tracking Service
//
//  This service tracks API requests through ProxyBridge callbacks.
//  Request history is persisted to disk for session continuity.
//

import Foundation
import AppKit

/// Service for tracking API request history with persistence
@MainActor
@Observable
final class RequestTracker {
    
    // MARK: - Singleton
    
    static let shared = RequestTracker()
    
    // MARK: - Properties
    
    /// Current request history (newest first)
    private(set) var requestHistory: [RequestLog] = []
    
    /// Aggregate statistics
    private(set) var stats: RequestStats = .empty
    
    /// Whether the tracker is active
    private(set) var isActive = false
    
    /// Last error message
    private(set) var lastError: String?
    
    // MARK: - Private Properties
    
    /// Storage container
    private var store: RequestHistoryStore = .empty
    
    /// Queue for file operations
    private let fileQueue = DispatchQueue(label: "dev.quotio.desktop.request-tracker-file")

    /// In-memory hot window for UI rendering
    private let memoryWindowSize = 200
    
    /// Storage file URL
    private var storageURL: URL {
        let baseURL: URL
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            baseURL = appSupport
        } else {
            baseURL = FileManager.default.temporaryDirectory
            Log.warning("Application Support directory unavailable, request tracker falling back to temporary directory")
        }
        let quotioDir = baseURL.appendingPathComponent("Quotio")
        do {
            try FileManager.default.createDirectory(at: quotioDir, withIntermediateDirectories: true)
        } catch {
            Log.warning("[RequestTracker] Failed to create storage directory: \(error.localizedDescription)")
        }
        return quotioDir.appendingPathComponent("request-history.json")
    }
    
    // MARK: - Initialization
    
    private init() {
        loadFromDisk()
        setupMemoryWarningObserver()
    }
    
    private func setupMemoryWarningObserver() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.trimHistoryForBackground()
            }
        }
    }
    
    private func trimHistoryForBackground() {
        let reducedLimit = 10
        if requestHistory.count > reducedLimit {
            requestHistory = Array(requestHistory.prefix(reducedLimit))
            Log.debug("[RequestTracker] Trimmed to \(reducedLimit) entries for background")
        }
    }
    
    // MARK: - Public Methods
    
    /// Start tracking (called when proxy starts)
    func start() {
        isActive = true
        Log.debug("[RequestTracker] Started tracking")
    }
    
    /// Stop tracking (called when proxy stops)
    func stop() {
        isActive = false
        Log.debug("[RequestTracker] Stopped tracking")
    }
    
    /// Add a request from ProxyBridge callback
    func addRequest(from metadata: ProxyBridge.RequestMetadata) {
        let attempts = metadata.fallbackAttempts.isEmpty ? nil : metadata.fallbackAttempts
        let sanitizedEndpoint = PrivacyRedactor.redactEndpointQuery(metadata.path)
        let sanitizedPayload = metadata.requestPayloadSnippet.map { PrivacyRedactor.redactStructuredText($0) }
        let sanitizedResponseSnippet = metadata.responseSnippet.map { PrivacyRedactor.redactStructuredText($0) }
        let entry = RequestLog(
            timestamp: metadata.timestamp,
            requestId: metadata.requestId,
            method: metadata.method,
            endpoint: sanitizedEndpoint,
            provider: metadata.provider,
            model: metadata.model,
            source: metadata.source,
            sourceRaw: metadata.sourceRaw,
            accountHint: metadata.accountHint,
            requestPayloadSnippet: sanitizedPayload,
            resolvedModel: metadata.resolvedModel,
            resolvedProvider: metadata.resolvedProvider,
            inputTokens: nil,
            outputTokens: nil,
            durationMs: metadata.durationMs,
            statusCode: metadata.statusCode,
            requestSize: metadata.requestSize,
            responseSize: metadata.responseSize,
            errorMessage: sanitizedResponseSnippet,
            fallbackAttempts: attempts,
            fallbackStartedFromCache: metadata.fallbackStartedFromCache
        )

        addEntry(entry)
    }
    
    /// Add a request entry directly
    func addEntry(_ entry: RequestLog) {
        store.addEntry(entry)
        requestHistory = Array(store.entries.prefix(memoryWindowSize))
        stats = store.calculateStats()
        saveToDisk()
    }
    
    /// Clear all history
    func clearHistory() {
        store = .empty
        requestHistory = []
        stats = .empty
        saveToDisk()
    }
    
    /// Get requests filtered by provider
    func requests(for provider: String) -> [RequestLog] {
        requestHistory.filter { $0.provider == provider }
    }
    
    /// Get requests from last N minutes
    func recentRequests(minutes: Int) -> [RequestLog] {
        let cutoff = Date().addingTimeInterval(-Double(minutes * 60))
        return requestHistory.filter { $0.timestamp >= cutoff }
    }
    
    // MARK: - Persistence
    
    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            Log.debug("[RequestTracker] No history file found, starting fresh")
            return
        }

        do {
            let data = try Data(contentsOf: storageURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601  // Match the encoding strategy
            store = try decoder.decode(RequestHistoryStore.self, from: data)
            requestHistory = Array(store.entries.prefix(memoryWindowSize))
            stats = store.calculateStats()
            Log.debug("[RequestTracker] Loaded \(store.entries.count) entries from disk")
        } catch {
            Log.warning("[RequestTracker] Failed to load history: \(error.localizedDescription)")
            lastError = error.localizedDescription
            // If decoding fails due to format mismatch, clear the corrupt file
            try? FileManager.default.removeItem(at: storageURL)
            Log.warning("[RequestTracker] Removed corrupt history file, starting fresh")
        }
    }
    
    private func saveToDisk() {
        // Capture store snapshot on MainActor to avoid data race
        let storeSnapshot = self.store
        let storageURLSnapshot = self.storageURL

        fileQueue.async {
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = .prettyPrinted

                let data = try encoder.encode(storeSnapshot)
                try data.write(to: storageURLSnapshot)
            } catch {
                Log.warning("[RequestTracker] Failed to save history: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Audit Package

    nonisolated struct RequestAuditPackage: Codable, Sendable {
        nonisolated struct AuthEvidence: Codable, Sendable {
            let id: String
            let provider: String
            let account: String?
            let authIndex: String?
            let status: String
            let disabled: Bool
            let unavailable: Bool
            let errorKind: String?
            let errorReason: String?
            let frozenUntil: String?
            let disabledByPolicy: Bool?
        }

        let exportedAt: Date
        let requestCountInMemory: Int
        let requestCountOnDisk: Int
        let stats: RequestStats
        let recentErrors: [RequestLog]
        let recentRequests: [RequestLog]
        let settingsSnapshot: [String: String]
        let authEvidence: [AuthEvidence]
    }

    func exportAuditPackageData(authFiles: [AuthFile] = []) throws -> Data {
        let rawSettingsSnapshot: [String: String] = [
            "operatingMode": UserDefaults.standard.string(forKey: "operatingMode") ?? "unknown",
            "loggingToFile": String(UserDefaults.standard.bool(forKey: "loggingToFile")),
            "requestLog": String(UserDefaults.standard.bool(forKey: "requestLog")),
            "refreshCadence": UserDefaults.standard.string(forKey: "refreshCadence") ?? "unknown",
            "quotaDisplayMode": UserDefaults.standard.string(forKey: "quotaDisplayMode") ?? "unknown",
            "feature.enhancedUILayout": String(UserDefaults.standard.bool(forKey: "feature.enhancedUILayout")),
            "feature.enhancedObservability": String(UserDefaults.standard.bool(forKey: "feature.enhancedObservability")),
            "feature.accessibilityHardening": String(UserDefaults.standard.bool(forKey: "feature.accessibilityHardening"))
        ]
        let settingsSnapshot = rawSettingsSnapshot.mapValues { value in
            PrivacyRedactor.redactURLLikeString(value)
        }

        let authEvidence = authFiles.map { file in
            RequestAuditPackage.AuthEvidence(
                id: file.id,
                provider: file.provider,
                account: file.account ?? file.email,
                authIndex: file.authIndex,
                status: file.status,
                disabled: file.disabled,
                unavailable: file.unavailable,
                errorKind: file.normalizedErrorKind,
                errorReason: file.errorReason ?? file.humanReadableStatus,
                frozenUntil: file.frozenUntil,
                disabledByPolicy: file.disabledByPolicy
            )
        }

        let sanitizedRecentErrors = Array(store.entries.filter { !$0.isSuccess }.prefix(200)).map(sanitizeRequestLogForExport)
        let sanitizedRecentRequests = Array(requestHistory.prefix(300)).map(sanitizeRequestLogForExport)

        let package = RequestAuditPackage(
            exportedAt: Date(),
            requestCountInMemory: requestHistory.count,
            requestCountOnDisk: store.entries.count,
            stats: stats,
            recentErrors: sanitizedRecentErrors,
            recentRequests: sanitizedRecentRequests,
            settingsSnapshot: settingsSnapshot,
            authEvidence: authEvidence
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(package)
    }

    private func sanitizeRequestLogForExport(_ log: RequestLog) -> RequestLog {
        RequestLog(
            id: log.id,
            timestamp: log.timestamp,
            requestId: log.requestId,
            method: log.method,
            endpoint: PrivacyRedactor.redactEndpointQuery(log.endpoint),
            provider: log.provider,
            model: log.model,
            source: log.source,
            sourceRaw: log.sourceRaw,
            accountHint: log.accountHint,
            requestPayloadSnippet: log.requestPayloadSnippet.map { PrivacyRedactor.redactStructuredText($0) },
            resolvedModel: log.resolvedModel,
            resolvedProvider: log.resolvedProvider,
            inputTokens: log.inputTokens,
            outputTokens: log.outputTokens,
            durationMs: log.durationMs,
            statusCode: log.statusCode,
            requestSize: log.requestSize,
            responseSize: log.responseSize,
            errorMessage: log.errorMessage.map { PrivacyRedactor.redactStructuredText($0) },
            fallbackAttempts: log.fallbackAttempts,
            fallbackStartedFromCache: log.fallbackStartedFromCache
        )
    }
}
