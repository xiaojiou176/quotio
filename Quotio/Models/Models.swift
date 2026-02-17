//
//  Models.swift
//  Quotio - CLIProxyAPI GUI Wrapper
//

import Foundation
import SwiftUI

// MARK: - Provider Types

nonisolated enum AIProvider: String, CaseIterable, Codable, Identifiable {
    case gemini = "gemini-cli"
    case claude = "claude"
    case codex = "codex"
    case qwen = "qwen"
    case iflow = "iflow"
    case antigravity = "antigravity"
    case vertex = "vertex"
    case kiro = "kiro"
    case copilot = "github-copilot"
    case cursor = "cursor"
    case trae = "trae"
    case glm = "glm"
    case warp = "warp"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .gemini: return "Gemini CLI"
        case .claude: return "Claude Code"
        case .codex: return "Codex (OpenAI)"
        case .qwen: return "Qwen Code"
        case .iflow: return "iFlow"
        case .antigravity: return "Antigravity"
        case .vertex: return "Vertex AI"
        case .kiro: return "Kiro (CodeWhisperer)"
        case .copilot: return "GitHub Copilot"
        case .cursor: return "Cursor"
        case .trae: return "Trae"
        case .glm: return "GLM"
        case .warp: return "Warp"
        }
    }
    
    var iconName: String {
        switch self {
        case .gemini: return "sparkles"
        case .claude: return "brain.head.profile"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        case .qwen: return "cloud"
        case .iflow: return "arrow.triangle.branch"
        case .antigravity: return "wand.and.stars"
        case .vertex: return "cube"
        case .kiro: return "cloud.fill"
        case .copilot: return "chevron.left.forwardslash.chevron.right"
        case .cursor: return "cursorarrow.rays"
        case .trae: return "cursorarrow.rays"
        case .glm: return "brain"
        case .warp: return "terminal.fill"
        }
    }
    
    /// Logo file name in ProviderIcons asset catalog
    var logoAssetName: String {
        switch self {
        case .gemini: return "gemini"
        case .claude: return "claude"
        case .codex: return "openai"
        case .qwen: return "qwen"
        case .iflow: return "iflow"
        case .antigravity: return "antigravity"
        case .vertex: return "vertex"
        case .kiro: return "kiro"
        case .copilot: return "copilot"
        case .cursor: return "cursor"
        case .trae: return "trae"
        case .glm: return "glm"
        case .warp: return "warp"
        }
    }
    
    var color: Color {
        switch self {
        case .gemini: return Color(hex: "4285F4") ?? .blue
        case .claude: return Color(hex: "D97706") ?? .orange
        case .codex: return Color(hex: "10A37F") ?? .green
        case .qwen: return Color(hex: "7C3AED") ?? .purple
        case .iflow: return Color(hex: "06B6D4") ?? .cyan
        case .antigravity: return Color(hex: "EC4899") ?? .pink
        case .vertex: return Color(hex: "EA4335") ?? .red
        case .kiro: return Color(hex: "9046FF") ?? .purple
        case .copilot: return Color(hex: "238636") ?? .green
        case .cursor: return Color(hex: "00D4AA") ?? .teal
        case .trae: return Color(hex: "00B4D8") ?? .cyan
        case .glm: return Color(hex: "3B82F6") ?? .blue
        case .warp: return Color(hex: "01E5FF") ?? .cyan
        }
    }
    
    var oauthEndpoint: String {
        switch self {
        case .gemini: return "/gemini-cli-auth-url"
        case .claude: return "/anthropic-auth-url"
        case .codex: return "/codex-auth-url"
        case .qwen: return "/qwen-auth-url"
        case .iflow: return "/iflow-auth-url"
        case .antigravity: return "/antigravity-auth-url"
        case .vertex: return ""
        case .kiro: return ""  // Uses CLI-based auth like Copilot
        case .copilot: return ""
        case .cursor: return ""  // Uses browser session
        case .trae: return ""  // Uses browser session
        case .glm: return ""
        case .warp: return ""
        }
    }
    
    /// Short symbol for menu bar display
    var menuBarSymbol: String {
        switch self {
        case .gemini: return "G"
        case .claude: return "C"
        case .codex: return "O"
        case .qwen: return "Q"
        case .iflow: return "F"
        case .antigravity: return "A"
        case .vertex: return "V"
        case .kiro: return "K"
        case .copilot: return "CP"
        case .cursor: return "CR"
        case .trae: return "TR"
        case .glm: return "G"
        case .warp: return "W"
        }
    }
    
    /// Menu bar icon asset name (nil if should use SF Symbol fallback)
    var menuBarIconAsset: String? {
        switch self {
        case .gemini: return "gemini-menubar"
        case .claude: return "claude-menubar"
        case .codex: return "openai-menubar"
        case .qwen: return "qwen-menubar"
        case .copilot: return "copilot-menubar"
        // These don't have custom icons, use SF Symbols
        case .antigravity: return "antigravity-menubar"
        case .kiro: return "kiro-menubar"
        case .iflow: return "iflow-menubar"
        case .vertex: return "vertex-menubar"
        case .cursor: return "cursor-menubar"
        case .trae: return "trae-menubar"
        case .glm: return "glm-menubar"
        case .warp: return "warp-menubar"
        }
    }
    
    /// Whether this provider supports quota tracking in quota-only mode
    var supportsQuotaOnlyMode: Bool {
        switch self {
        case .claude, .codex, .cursor, .gemini, .antigravity, .copilot, .trae, .glm, .warp:
            return true
        case .qwen, .iflow, .vertex, .kiro:
            return false
        }
    }
    
    /// Whether this provider uses browser cookies for auth
    var usesBrowserAuth: Bool {
        switch self {
        case .cursor, .trae:
            return true
        default:
            return false
        }
    }
    
    /// Whether this provider uses CLI commands for quota
    var usesCLIQuota: Bool {
        switch self {
        case .claude, .codex, .gemini:
            return true
        default:
            return false
        }
    }
    
    /// Map provider to CLI agent (if applicable)
    var cliAgent: CLIAgent? {
        switch self {
        case .claude: return .claudeCode
        case .codex: return .codexCLI
        case .gemini: return .geminiCLI
        default: return nil
        }
    }
    
    /// Whether this provider can be added manually (via OAuth, CLI login, or file import)
    /// Cursor, Trae, Windsurf are excluded because they only read from local app databases
    /// GLM is excluded because it should only be added via Custom Providers
    var supportsManualAuth: Bool {
        switch self {
        case .cursor, .trae, .glm:
            return false  // GLM: only via Custom Providers; Cursor/Trae: only reads from local app database
        default:
            return true
        }
    }

    /// Whether this provider uses API key authentication (stored in CustomProviderService)
    var usesAPIKeyAuth: Bool {
        switch self {
        case .glm, .warp:
            return true
        default:
            return false
        }
    }
    
    /// Whether this provider is quota-tracking only (not a real provider that can route requests)
    var isQuotaTrackingOnly: Bool {
        switch self {
        case .cursor, .trae, .warp:
            return true  // Only for tracking usage, not a provider
        default:
            return false
        }
    }
}

// MARK: - Proxy Status

nonisolated struct ProxyStatus: Codable {
    var running: Bool = false
    var port: UInt16 = 8317
    
    var endpoint: String {
        "http://localhost:\(port)/v1"
    }
}

// MARK: - Auth File (from Management API)

nonisolated struct AuthFile: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let provider: String
    let label: String?
    let status: String
    let statusMessage: String?
    let disabled: Bool
    let unavailable: Bool
    let runtimeOnly: Bool?
    let source: String?
    let path: String?
    let email: String?
    let accountType: String?
    let account: String?
    let authIndex: String?
    let createdAt: String?
    let updatedAt: String?
    let lastRefresh: String?
    let nextRetryAfter: String?
    let nextRecoverAt: String?
    let errorKind: String?
    let errorReason: String?
    let errorCode: Int?
    let frozenUntil: String?
    let freezeScope: String?
    let disabledByPolicy: Bool?
    
    enum CodingKeys: String, CodingKey {
        case id, name, provider, label, status, disabled, unavailable, source, path, email, account
        case authIndex = "auth_index"
        case statusMessage = "status_message"
        case runtimeOnly = "runtime_only"
        case accountType = "account_type"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case lastRefresh = "last_refresh"
        case nextRetryAfter = "next_retry_after"
        case nextRecoverAt = "next_recover_at"
        case errorKind = "error_kind"
        case errorReason = "error_reason"
        case errorCode = "error_code"
        case frozenUntil = "frozen_until"
        case freezeScope = "freeze_scope"
        case disabledByPolicy = "disabled_by_policy"
    }

    init(
        id: String,
        name: String,
        provider: String,
        label: String?,
        status: String,
        statusMessage: String?,
        disabled: Bool,
        unavailable: Bool,
        runtimeOnly: Bool? = nil,
        source: String? = nil,
        path: String? = nil,
        email: String? = nil,
        accountType: String? = nil,
        account: String? = nil,
        authIndex: String? = nil,
        createdAt: String? = nil,
        updatedAt: String? = nil,
        lastRefresh: String? = nil,
        nextRetryAfter: String? = nil,
        nextRecoverAt: String? = nil,
        errorKind: String? = nil,
        errorReason: String? = nil,
        errorCode: Int? = nil,
        frozenUntil: String? = nil,
        freezeScope: String? = nil,
        disabledByPolicy: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.provider = provider
        self.label = label
        self.status = status
        self.statusMessage = statusMessage
        self.disabled = disabled
        self.unavailable = unavailable
        self.runtimeOnly = runtimeOnly
        self.source = source
        self.path = path
        self.email = email
        self.accountType = accountType
        self.account = account
        self.authIndex = authIndex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastRefresh = lastRefresh
        self.nextRetryAfter = nextRetryAfter
        self.nextRecoverAt = nextRecoverAt
        self.errorKind = errorKind
        self.errorReason = errorReason
        self.errorCode = errorCode
        self.frozenUntil = frozenUntil
        self.freezeScope = freezeScope
        self.disabledByPolicy = disabledByPolicy
    }
    
    var providerType: AIProvider? {
        // Handle "copilot" alias for "github-copilot"
        if provider == "copilot" {
            return .copilot
        }
        return AIProvider(rawValue: provider)
    }
    
    var quotaLookupKey: String {
        if let email = email, !email.isEmpty {
            return email
        }
        if let account = account, !account.isEmpty {
            return account
        }
        var key = name
        if key.hasPrefix("github-copilot-") {
            key = String(key.dropFirst("github-copilot-".count))
        }
        if key.hasSuffix(".json") {
            key = String(key.dropLast(".json".count))
        }
        return key
    }

    var menuBarAccountKey: String {
        let key = quotaLookupKey
        return key.isEmpty ? name : key
    }
    
    var isReady: Bool {
        status == "ready" && !disabled && !unavailable
    }

    var normalizedErrorKind: String? {
        let raw = errorKind?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let canonical = raw.replacingOccurrences(of: "-", with: "_")
        return canonical.isEmpty ? nil : canonical
    }

    private var normalizedErrorContext: String {
        let candidates: [String?] = [
            normalizedErrorKind,
            errorReason?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: "-", with: "_"),
            statusMessage?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: "-", with: "_")
        ]
        let parts = candidates.compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        return parts.joined(separator: " ")
    }

    var frozenUntilDate: Date? {
        parseISODate(frozenUntil) ?? parseISODate(nextRecoverAt) ?? parseISODate(nextRetryAfter)
    }

    var isQuotaLimited5h: Bool {
        let context = normalizedErrorContext
        return context.contains("quota_limited_5h")
            || context.contains("quota_limited5h")
    }

    var isQuotaLimited7d: Bool {
        let context = normalizedErrorContext
        return context.contains("quota_limited_7d")
            || context.contains("quota_limited_7days")
            || context.contains("quota_limited7days")
    }

    var isNetworkError: Bool {
        normalizedErrorContext.contains("network_error")
    }

    var isFatalDisabled: Bool {
        let context = normalizedErrorContext
        if context.contains("workspace_deactivated") && (disabledByPolicy == true || disabled) {
            return true
        }
        if context.contains("account_deactivated") {
            return true
        }
        return false
    }
    
    var statusColor: Color {
        switch status {
        case "ready": return disabled ? .gray : .green
        case "cooling": return .orange
        case "error": return .red
        default: return .gray
        }
    }

    /// Extracts a human-readable message from the status_message field.
    /// The field may contain raw JSON error blobs from providers (e.g., Antigravity/Google).
    var humanReadableStatus: String? {
        guard let msg = statusMessage, !msg.isEmpty else { return nil }

        // If it looks like JSON, try to parse it
        let trimmed = msg.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{"),
           let data = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }

        // Already a plain string
        return msg
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(disabled)
        hasher.combine(status)
    }

    static func == (lhs: AuthFile, rhs: AuthFile) -> Bool {
        lhs.id == rhs.id &&
        lhs.disabled == rhs.disabled &&
        lhs.status == rhs.status
    }

    private func parseISODate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let formatterWithFractional = ISO8601DateFormatter()
        formatterWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let formatterDefault = ISO8601DateFormatter()
        formatterDefault.formatOptions = [.withInternetDateTime]
        return formatterWithFractional.date(from: value) ?? formatterDefault.date(from: value)
    }
}

nonisolated struct AuthFilesResponse: Codable, Sendable {
    let files: [AuthFile]
}

// MARK: - API Keys (Proxy Service Auth)

nonisolated struct APIKeysResponse: Codable, Sendable {
    let apiKeys: [String]
    
    enum CodingKeys: String, CodingKey {
        case apiKeys = "api-keys"
    }
}

// MARK: - Usage Statistics

nonisolated struct UsageStats: Codable, Sendable {
    let usage: UsageData?
    let failedRequests: Int?
    
    enum CodingKeys: String, CodingKey {
        case usage
        case failedRequests = "failed_requests"
    }
}

nonisolated struct UsageData: Codable, Sendable {
    let totalRequests: Int?
    let successCount: Int?
    let failureCount: Int?
    let totalTokens: Int?
    let inputTokens: Int?
    let outputTokens: Int?
    let apis: [String: APIUsageSnapshot]?
    let requestsByDay: [String: Int]?
    let requestsByHour: [String: Int]?
    let tokensByDay: [String: Int]?
    let tokensByHour: [String: Int]?
    
    enum CodingKeys: String, CodingKey {
        case totalRequests = "total_requests"
        case successCount = "success_count"
        case failureCount = "failure_count"
        case totalTokens = "total_tokens"
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case apis
        case requestsByDay = "requests_by_day"
        case requestsByHour = "requests_by_hour"
        case tokensByDay = "tokens_by_day"
        case tokensByHour = "tokens_by_hour"
    }
    
    var successRate: Double {
        guard let total = totalRequests, total > 0, let success = successCount else { return 0 }
        return Double(success) / Double(total) * 100
    }
}

// MARK: - Detailed Usage Statistics

nonisolated struct APIUsageSnapshot: Codable, Sendable {
    let totalRequests: Int?
    let totalTokens: Int?
    let models: [String: ModelUsageSnapshot]?
    
    enum CodingKeys: String, CodingKey {
        case totalRequests = "total_requests"
        case totalTokens = "total_tokens"
        case models
    }
}

nonisolated struct ModelUsageSnapshot: Codable, Sendable {
    let totalRequests: Int?
    let totalTokens: Int?
    let details: [RequestDetailSnapshot]?
    
    enum CodingKeys: String, CodingKey {
        case totalRequests = "total_requests"
        case totalTokens = "total_tokens"
        case details
    }
}

nonisolated struct RequestDetailSnapshot: Codable, Sendable, Identifiable {
    let timestamp: String
    let source: String?
    let authIndex: String?
    let tokens: TokenStats?
    let failed: Bool?
    
    var id: String {
        "\(timestamp)-\(authIndex ?? "")-\(source ?? "")"
    }
    
    enum CodingKeys: String, CodingKey {
        case timestamp
        case source
        case authIndex = "auth_index"
        case tokens
        case failed
    }
    
    var date: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: timestamp) ?? ISO8601DateFormatter().date(from: timestamp)
    }
}

nonisolated struct TokenStats: Codable, Sendable {
    let inputTokens: Int?
    let outputTokens: Int?
    let reasoningTokens: Int?
    let cachedTokens: Int?
    let totalTokens: Int?
    
    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case reasoningTokens = "reasoning_tokens"
        case cachedTokens = "cached_tokens"
        case totalTokens = "total_tokens"
    }
}

// MARK: - Request History API Response

nonisolated struct RequestHistoryResponse: Codable, Sendable {
    let requests: [RequestHistoryItem]
    let total: Int
    let limit: Int
    let offset: Int
}

nonisolated struct RequestHistoryItem: Codable, Sendable, Identifiable {
    let timestamp: String
    let requestId: String?
    let apiKey: String?
    let model: String?
    let authIndex: String?
    let source: String?
    let success: Bool
    let tokens: Int?
    
    var id: String {
        if let requestId, !requestId.isEmpty {
            return requestId
        }
        return [
            timestamp,
            authIndex ?? "",
            model ?? "",
            source ?? "",
            apiKey ?? "",
            String(tokens ?? 0),
            String(success)
        ].joined(separator: "|")
    }
    
    enum CodingKeys: String, CodingKey {
        case timestamp
        case requestId = "request_id"
        case apiKey = "api_key"
        case model
        case authIndex = "auth_index"
        case source
        case success
        case tokens
    }
    
    var date: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: timestamp) ?? ISO8601DateFormatter().date(from: timestamp)
    }
}

// MARK: - SSE Event

nonisolated struct SSERequestEvent: Codable, Sendable {
    let type: String  // "request" | "quota_exceeded" | "error" | "connected"
    let seq: Int64?
    let eventId: String?
    let timestamp: String
    let requestId: String?
    let provider: String?
    let model: String?
    let authFile: String?
    let source: String?
    let success: Bool?
    let tokens: Int?
    let latencyMs: Int?
    let error: String?
    
    enum CodingKeys: String, CodingKey {
        case type
        case seq
        case eventId = "event_id"
        case timestamp
        case requestId = "request_id"
        case provider
        case model
        case authFile = "auth_file"
        case source
        case success
        case tokens
        case latencyMs = "latency_ms"
        case error
    }
    
    var date: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: timestamp) ?? ISO8601DateFormatter().date(from: timestamp)
    }

    /// Stable client-side dedupe key for real-time event streams.
    var dedupeKey: String {
        if let seq, seq > 0 {
            return "seq:\(seq)"
        }
        if let eventId, !eventId.isEmpty {
            return "event:\(eventId)"
        }
        if let requestId, !requestId.isEmpty {
            return requestId
        }
        return [type, timestamp, provider ?? "", model ?? "", authFile ?? "", source ?? "", String(tokens ?? 0), String(success ?? false)]
            .joined(separator: "|")
    }
}

// MARK: - OAuth Flow

nonisolated struct OAuthURLResponse: Codable, Sendable {
    let status: String
    let url: String?
    let state: String?
    let error: String?
}

nonisolated struct OAuthStatusResponse: Codable, Sendable {
    let status: String
    let error: String?
}

// MARK: - App Config

nonisolated struct AppConfig: Codable {
    var host: String = ""
    var port: UInt16 = 8317
    var authDir: String = "~/.cli-proxy-api"
    var proxyURL: String = ""
    var apiKeys: [String] = []
    var debug: Bool = false
    var loggingToFile: Bool = false
    var usageStatisticsEnabled: Bool = true
    var requestRetry: Int = 3
    var maxRetryInterval: Int = 30
    var wsAuth: Bool = false
    var routing: RoutingConfig = RoutingConfig()
    var quotaExceeded: QuotaExceededConfig = QuotaExceededConfig()
    var remoteManagement: RemoteManagementConfig = RemoteManagementConfig()
    
    enum CodingKeys: String, CodingKey {
        case host, port, debug, routing
        case authDir = "auth-dir"
        case proxyURL = "proxy-url"
        case apiKeys = "api-keys"
        case loggingToFile = "logging-to-file"
        case usageStatisticsEnabled = "usage-statistics-enabled"
        case requestRetry = "request-retry"
        case maxRetryInterval = "max-retry-interval"
        case wsAuth = "ws-auth"
        case quotaExceeded = "quota-exceeded"
        case remoteManagement = "remote-management"
    }
}

nonisolated struct RoutingConfig: Codable {
    var strategy: String = "round-robin"
}

nonisolated struct QuotaExceededConfig: Codable {
    var switchProject: Bool = true
    var switchPreviewModel: Bool = true
    
    enum CodingKeys: String, CodingKey {
        case switchProject = "switch-project"
        case switchPreviewModel = "switch-preview-model"
    }
}

nonisolated struct RemoteManagementConfig: Codable {
    var allowRemote: Bool = false
    var secretKey: String = ""
    var disableControlPanel: Bool = false
    
    enum CodingKeys: String, CodingKey {
        case allowRemote = "allow-remote"
        case secretKey = "secret-key"
        case disableControlPanel = "disable-control-panel"
    }
}

// MARK: - Hybrid Base URL Namespace Mapping

nonisolated struct BaseURLNamespaceModelSet: Codable, Identifiable, Hashable, Sendable {
    let namespace: String
    var baseURL: String
    var modelSet: [String]
    var notes: String?
    
    var id: String { namespace }
    
    init(namespace: String, baseURL: String, modelSet: [String], notes: String? = nil) {
        self.namespace = namespace.trimmingCharacters(in: .whitespacesAndNewlines)
        self.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        self.modelSet = Array(
            Set(
                modelSet
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        ).sorted()
        self.notes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Log Entry

nonisolated struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let level: LogLevel
    let message: String
    
    enum LogLevel: String {
        case info, warn, error, debug
        
        var color: Color {
            switch self {
            case .info: return .primary
            case .warn: return .orange
            case .error: return .red
            case .debug: return .gray
            }
        }
    }
}

// MARK: - Navigation

nonisolated enum NavigationPage: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case quota = "Quota"
    case providers = "Providers"
    case fallback = "Fallback"
    case reviewQueue = "Review Queue"
    case agents = "Agents"
    case apiKeys = "API Keys"
    case usageStats = "Usage Stats"
    case logs = "Logs"
    case settings = "Settings"
    case about = "About"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.33percent"
        case .quota: return "chart.bar.fill"
        case .providers: return "person.2.badge.key"
        case .fallback: return "arrow.triangle.branch"
        case .reviewQueue: return "checklist"
        case .agents: return "terminal"
        case .apiKeys: return "key.horizontal"
        case .usageStats: return "chart.line.uptrend.xyaxis"
        case .logs: return "doc.text"
        case .settings: return "gearshape"
        case .about: return "info.circle"
        }
    }
}

// MARK: - Color Extension

nonisolated extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }
        
        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0
        
        self.init(red: r, green: g, blue: b)
    }

    // MARK: - Semantic UI Tokens

    static var semanticInfo: Color { .accentColor }
    static var semanticSuccess: Color { .green }
    static var semanticWarning: Color { .orange }
    static var semanticDanger: Color { .red }
    static var semanticAccentSecondary: Color { .purple }
    static var semanticSurfaceBase: Color { Color(nsColor: .windowBackgroundColor) }
    static var semanticSurfaceElevated: Color { Color(nsColor: .controlBackgroundColor) }
    static var semanticSurfaceMuted: Color { Color.semanticSurfaceElevated.opacity(0.5) }
    static var semanticSelectionFill: Color { Color.semanticInfo.opacity(0.1) }
    static var semanticWarningFill: Color { Color.semanticWarning.opacity(0.12) }
    static var semanticMutedFill: Color { Color.secondary.opacity(0.2) }
    static var semanticOnAccent: Color { .white }
}

// MARK: - Formatting Helpers

extension Int {
    var formattedCompact: String {
        if self >= 1_000_000 {
            return String(format: "%.1fM", Double(self) / 1_000_000)
        } else if self >= 1_000 {
            return String(format: "%.1fK", Double(self) / 1_000)
        }
        return "\(self)"
    }
}

// MARK: - Proxy URL Validation

nonisolated enum ProxyURLValidationResult: Equatable {
    case valid
    case empty
    case invalidScheme
    case invalidURL
    case missingHost
    case missingPort
    case invalidPort
    
    var isValid: Bool {
        self == .valid || self == .empty
    }
    
    var localizationKey: String? {
        switch self {
        case .valid, .empty:
            return nil
        case .invalidScheme:
            return "settings.proxy.error.invalidScheme"
        case .invalidURL:
            return "settings.proxy.error.invalidURL"
        case .missingHost:
            return "settings.proxy.error.missingHost"
        case .missingPort:
            return "settings.proxy.error.missingPort"
        case .invalidPort:
            return "settings.proxy.error.invalidPort"
        }
    }
}

nonisolated enum ProxyURLValidator {
    static let supportedSchemes = ["socks5", "http", "https"]
    
    static func validate(_ urlString: String) -> ProxyURLValidationResult {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmed.isEmpty else {
            return .empty
        }
        
        let hasValidScheme = supportedSchemes.contains { scheme in
            trimmed.lowercased().hasPrefix("\(scheme)://")
        }
        
        guard hasValidScheme else {
            return .invalidScheme
        }
        
        guard let url = URL(string: trimmed) else {
            return .invalidURL
        }
        
        guard let host = url.host, !host.isEmpty else {
            return .missingHost
        }
        
        // socks5 requires explicit port
        if url.scheme?.lowercased() == "socks5" {
            guard let port = url.port else {
                return .missingPort
            }
            guard port >= 1 && port <= 65535 else {
                return .invalidPort
            }
        } else if let port = url.port {
            guard port >= 1 && port <= 65535 else {
                return .invalidPort
            }
        }
        
        return .valid
    }
    
    static func sanitize(_ urlString: String) -> String {
        var trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)

        if var components = URLComponents(string: trimmed) {
            components.user = nil
            components.password = nil
            if let normalized = components.string {
                trimmed = normalized
            }
        }
        
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        
        return trimmed
    }
}
