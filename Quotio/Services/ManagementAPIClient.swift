//
//  ManagementAPIClient.swift
//  Quotio - CLIProxyAPI GUI Wrapper
//

import Foundation

actor ManagementAPIClient {
    private let baseURL: String
    private let authKey: String
    private let session: URLSession
    private let sessionDelegate: SessionDelegate
    private let clientId: String
    
    /// Whether this client is connected to a remote server (vs localhost)
    let isRemote: Bool
    
    /// Timeout configuration used for this client
    let timeoutConfig: TimeoutConfig
    
    // MARK: - Timeout Configuration
    
    /// Timeout settings for API requests
    struct TimeoutConfig: Sendable {
        let requestTimeout: TimeInterval
        let resourceTimeout: TimeInterval
        let maxRetries: Int

        /// Default timeouts for local connections (faster, more reliable)
        /// Increased maxRetries to handle proxy restart scenarios (graceful shutdown can take 1-2s)
        static let local = TimeoutConfig(
            requestTimeout: 15,
            resourceTimeout: 45,
            maxRetries: 4  // Was: 1. Now: 4 retries with exponential backoff = ~6.5s total wait
        )

        /// Timeouts for remote connections (slower, needs more patience)
        static let remote = TimeoutConfig(
            requestTimeout: 30,
            resourceTimeout: 90,
            maxRetries: 5  // Was: 2. Remote connections may need more retries
        )
        
        /// Custom timeout configuration
        static func custom(requestTimeout: TimeInterval, resourceTimeout: TimeInterval, maxRetries: Int = 1) -> TimeoutConfig {
            TimeoutConfig(requestTimeout: requestTimeout, resourceTimeout: resourceTimeout, maxRetries: maxRetries)
        }
    }
    
    // MARK: - Diagnostic Logging
    
    static let enableDiagnosticLogging = false
    nonisolated(unsafe) private static var activeRequests: Int = 0
    private static let requestLock = NSLock()
    
    private static func log(_ message: String) {
        guard enableDiagnosticLogging else { return }
        Log.api("\(message)")
    }
    
    private static func incrementActiveRequests() -> Int {
        requestLock.lock()
        defer { requestLock.unlock() }
        activeRequests += 1
        return activeRequests
    }
    
    private static func decrementActiveRequests() -> Int {
        requestLock.lock()
        defer { requestLock.unlock() }
        activeRequests -= 1
        return activeRequests
    }

    private nonisolated func endpointWithQuery(_ path: String, items: [URLQueryItem]) -> String {
        guard !items.isEmpty else { return path }
        var components = URLComponents()
        components.path = path
        components.queryItems = items
        guard let encodedQuery = components.percentEncodedQuery, !encodedQuery.isEmpty else {
            return path
        }
        return "\(path)?\(encodedQuery)"
    }
    
    // MARK: - Initialization
    
    /// Initialize for local connection (localhost)
    init(baseURL: String, authKey: String) {
        self.baseURL = baseURL
        self.authKey = authKey
        self.clientId = String(UUID().uuidString.prefix(6))
        self.isRemote = false
        self.timeoutConfig = .local
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeoutConfig.requestTimeout
        config.timeoutIntervalForResource = timeoutConfig.resourceTimeout
        config.httpMaximumConnectionsPerHost = 4
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        
        self.sessionDelegate = SessionDelegate(clientId: clientId)
        self.session = URLSession(configuration: config, delegate: sessionDelegate, delegateQueue: nil)
        
        Self.log("[\(clientId)] Local client created, timeout=\(Int(timeoutConfig.requestTimeout))/\(Int(timeoutConfig.resourceTimeout))s")
    }
    
    /// Initialize for remote connection with custom timeout
    /// - Warning: Setting `verifySSL: false` disables certificate validation, making the connection
    ///   vulnerable to man-in-the-middle attacks. Only use for self-signed certificates in trusted networks.
    init(baseURL: String, authKey: String, timeoutConfig: TimeoutConfig, verifySSL: Bool = true) {
        self.baseURL = baseURL
        self.authKey = authKey
        self.clientId = String(UUID().uuidString.prefix(6))
        self.isRemote = true
        self.timeoutConfig = timeoutConfig
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeoutConfig.requestTimeout
        config.timeoutIntervalForResource = timeoutConfig.resourceTimeout
        config.httpMaximumConnectionsPerHost = 4
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        
        self.sessionDelegate = SessionDelegate(clientId: clientId, verifySSL: verifySSL)
        self.session = URLSession(configuration: config, delegate: sessionDelegate, delegateQueue: nil)
        
        Self.log("[\(clientId)] Remote client created, timeout=\(Int(timeoutConfig.requestTimeout))/\(Int(timeoutConfig.resourceTimeout))s, verifySSL=\(verifySSL)")
        
        if !verifySSL {
            Log.warning("SSL verification disabled for \(baseURL). Connection is vulnerable to MITM attacks.")
        }
    }
    
    /// Convenience initializer for remote connection with RemoteConnectionConfig
    init(config: RemoteConnectionConfig, managementKey: String) {
        let timeout = TimeoutConfig.custom(
            requestTimeout: TimeInterval(config.timeoutSeconds),
            resourceTimeout: TimeInterval(config.timeoutSeconds * 3),
            maxRetries: 2
        )
        self.init(
            baseURL: config.managementBaseURL,
            authKey: managementKey,
            timeoutConfig: timeout,
            verifySSL: config.verifySSL
        )
    }
    
    func invalidate() {
        Self.log("[\(clientId)] Session invalidating...")
        session.invalidateAndCancel()
    }
    
    private func makeRequest(_ endpoint: String, method: String = "GET", body: Data? = nil, retryCount: Int = 0) async throws -> Data {
        let requestId = String(UUID().uuidString.prefix(6))
        let activeCount = Self.incrementActiveRequests()
        let startTime = Date()
        
        Self.log("[\(clientId)][\(requestId)] START \(method) \(endpoint) (active=\(activeCount), retry=\(retryCount))")
        
        defer {
            let endCount = Self.decrementActiveRequests()
            let duration = Date().timeIntervalSince(startTime)
            Self.log("[\(clientId)][\(requestId)] END \(method) \(endpoint) duration=\(String(format: "%.3f", duration))s (active=\(endCount))")
        }
        
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.addValue("Bearer \(authKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        // Force new connection to avoid stale connection issues after idle periods
        request.addValue("close", forHTTPHeaderField: "Connection")
        
        if let body = body {
            request.httpBody = body
        }
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            
            guard 200...299 ~= httpResponse.statusCode else {
                Self.log("[\(clientId)][\(requestId)] HTTP ERROR \(httpResponse.statusCode)")
                throw APIError.httpError(httpResponse.statusCode)
            }
            
            return data
        } catch let error as URLError {
            Self.log("[\(clientId)][\(requestId)] URL ERROR: \(error.code.rawValue) - \(error.localizedDescription)")
            
            // Retry on timeout or connection errors (handles proxy restart scenarios)
            // Exponential backoff: 0.5s, 1s, 2s, 3s (total ~6.5s wait for proxy restart)
            if retryCount < timeoutConfig.maxRetries && (error.code == .timedOut || error.code == .networkConnectionLost || error.code == .cannotConnectToHost) {
                let backoffSeconds = min(pow(2.0, Double(retryCount)) * 0.5, 3.0)  // Cap at 3 seconds
                let backoffStr = String(format: "%.1f", backoffSeconds)
                Self.log("[\(clientId)][\(requestId)] RETRYING after \(backoffStr)s (attempt \(retryCount + 1)/\(timeoutConfig.maxRetries))...")
                
                // Exponential backoff delay
                try? await Task.sleep(nanoseconds: UInt64(backoffSeconds * 1_000_000_000))
                return try await makeRequest(endpoint, method: method, body: body, retryCount: retryCount + 1)
            }
            throw APIError.connectionError(error.localizedDescription)
        } catch {
            Self.log("[\(clientId)][\(requestId)] UNEXPECTED ERROR: \(error.localizedDescription)")
            throw error
        }
    }
    
    func fetchAuthFiles() async throws -> [AuthFile] {
        let data = try await makeRequest("/auth-files")
        let response = try JSONDecoder().decode(AuthFilesResponse.self, from: data)
        return response.files
    }
    
    func fetchAuthFileModels(name: String) async throws -> [AuthFileModelInfo] {
        let endpoint = endpointWithQuery("/auth-files/models", items: [
            URLQueryItem(name: "name", value: name)
        ])
        let data = try await makeRequest(endpoint)
        let response = try JSONDecoder().decode(AuthFileModelsResponse.self, from: data)
        return response.models
    }
    
    func apiCall(_ request: APICallRequest) async throws -> APICallResponse {
        let body = try JSONEncoder().encode(request)
        let data = try await makeRequest("/api-call", method: "POST", body: body)
        return try JSONDecoder().decode(APICallResponse.self, from: data)
    }
    
    func deleteAuthFile(name: String) async throws {
        let endpoint = endpointWithQuery("/auth-files", items: [
            URLQueryItem(name: "name", value: name)
        ])
        _ = try await makeRequest(endpoint, method: "DELETE")
    }
    
    func deleteAllAuthFiles() async throws {
        _ = try await makeRequest("/auth-files?all=true", method: "DELETE")
    }

    func setAuthFileDisabled(name: String, disabled: Bool) async throws {
        struct Request: Encodable {
            let name: String
            let disabled: Bool
        }
        let body = try JSONEncoder().encode(Request(name: name, disabled: disabled))
        _ = try await makeRequest("/auth-files/status", method: "PATCH", body: body)
    }
    
    func fetchUsageStats() async throws -> UsageStats {
        let data = try await makeRequest("/usage")
        return try JSONDecoder().decode(UsageStats.self, from: data)
    }
    
    /// Fetch request history with pagination and filters
    func fetchRequestHistory(
        limit: Int = 100,
        offset: Int = 0,
        model: String? = nil,
        provider: String? = nil,
        success: Bool? = nil,
        requestId: String? = nil,
        account: String? = nil,
        source: String? = nil
    ) async throws -> RequestHistoryResponse {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset))
        ]
        if let model = model {
            queryItems.append(URLQueryItem(name: "model", value: model))
        }
        if let provider = provider {
            queryItems.append(URLQueryItem(name: "provider", value: provider))
        }
        if let success = success {
            queryItems.append(URLQueryItem(name: "success", value: String(success)))
        }
        if let requestId = requestId, !requestId.isEmpty {
            queryItems.append(URLQueryItem(name: "request_id", value: requestId))
        }
        if let account = account, !account.isEmpty {
            queryItems.append(URLQueryItem(name: "auth_index", value: account))
        }
        if let source = source, !source.isEmpty {
            queryItems.append(URLQueryItem(name: "source", value: source))
        }
        
        let endpoint = endpointWithQuery("/usage/history", items: queryItems)
        let data = try await makeRequest(endpoint)
        return try JSONDecoder().decode(RequestHistoryResponse.self, from: data)
    }
    
    /// Create SSE stream URL for real-time usage events.
    /// When `sinceSeq` is provided, server attempts replay before live streaming.
    func getSSEStreamURL(sinceSeq: Int64? = nil) -> URL? {
        if let sinceSeq, sinceSeq > 0 {
            let endpoint = endpointWithQuery("/usage/stream", items: [
                URLQueryItem(name: "since_seq", value: String(sinceSeq))
            ])
            return URL(string: "\(baseURL)\(endpoint)")
        }
        return URL(string: "\(baseURL)/usage/stream")
    }

    func fetchUsageEvents(sinceSeq: Int64 = 0, limit: Int = 500) async throws -> [SSERequestEvent] {
        let endpoint = endpointWithQuery("/usage/events", items: [
            URLQueryItem(name: "since_seq", value: String(max(0, sinceSeq))),
            URLQueryItem(name: "limit", value: String(max(1, limit)))
        ])
        let data = try await makeRequest(endpoint)
        let response = try JSONDecoder().decode(UsageEventsResponse.self, from: data)
        return response.events
    }
    
    /// Export usage statistics for backup
    func exportUsageStats() async throws -> Data {
        return try await makeRequest("/usage/export")
    }
    
    /// Import usage statistics from backup
    func importUsageStats(data: Data) async throws {
        _ = try await makeRequest("/usage/import", method: "POST", body: data)
    }
    
    func getOAuthURL(
        for provider: AIProvider,
        projectId: String? = nil,
        isWebUI: Bool = true
    ) async throws -> OAuthURLResponse {
        var endpoint = provider.oauthEndpoint
        var queryItems: [URLQueryItem] = []
        
        if let projectId = projectId, provider == .gemini {
            queryItems.append(URLQueryItem(name: "project_id", value: projectId))
        }
        
        let webUIProviders: [AIProvider] = [.antigravity, .claude, .codex, .gemini, .iflow, .kiro]
        if isWebUI && webUIProviders.contains(provider) {
            queryItems.append(URLQueryItem(name: "is_webui", value: "true"))
        }
        
        endpoint = endpointWithQuery(endpoint, items: queryItems)
        let data = try await makeRequest(endpoint)
        return try JSONDecoder().decode(OAuthURLResponse.self, from: data)
    }
    
    func pollOAuthStatus(state: String) async throws -> OAuthStatusResponse {
        let endpoint = endpointWithQuery("/get-auth-status", items: [
            URLQueryItem(name: "state", value: state)
        ])
        let data = try await makeRequest(endpoint)
        return try JSONDecoder().decode(OAuthStatusResponse.self, from: data)
    }
    
    func fetchLogs(after: Int? = nil) async throws -> LogsResponse {
        var endpoint = "/logs"
        if let after = after {
            endpoint += "?after=\(after)"
        }
        let data = try await makeRequest(endpoint)
        return try JSONDecoder().decode(LogsResponse.self, from: data)
    }
    
    func clearLogs() async throws {
        _ = try await makeRequest("/logs", method: "DELETE")
    }
    
    func setDebug(_ enabled: Bool) async throws {
        let body = try JSONEncoder().encode(["value": enabled])
        _ = try await makeRequest("/debug", method: "PUT", body: body)
    }
    
    func setRoutingStrategy(_ strategy: String) async throws {
        let body = try JSONEncoder().encode(["value": strategy])

        // Try new endpoint first (CLIProxyAPIPlus v6.6.92+)
        do {
            _ = try await makeRequest("/routing/strategy", method: "PUT", body: body)
            return
        } catch APIError.httpError(404) {
            // Fall back to legacy endpoint for older CLIProxyAPI versions
            let legacyBody = try JSONEncoder().encode(["strategy": strategy])
            _ = try await makeRequest("/routing", method: "PUT", body: legacyBody)
        }
    }
    
    /// Get routing strategy
    func getRoutingStrategy() async throws -> String {
        // Try new endpoint first (CLIProxyAPIPlus v6.6.92+)
        do {
            let data = try await makeRequest("/routing/strategy")
            let response = try JSONDecoder().decode(RoutingStrategyResponse.self, from: data)
            return response.strategy
        } catch APIError.httpError(404) {
            // Fall back to legacy endpoint for older CLIProxyAPI versions
            let data = try await makeRequest("/routing")
            let response = try JSONDecoder().decode(RoutingStrategyResponse.self, from: data)
            return response.strategy
        }
    }
    
    func setQuotaExceededSwitchProject(_ enabled: Bool) async throws {
        let body = try JSONEncoder().encode(["value": enabled])
        _ = try await makeRequest("/quota-exceeded/switch-project", method: "PATCH", body: body)
    }
    
    func setQuotaExceededSwitchPreviewModel(_ enabled: Bool) async throws {
        let body = try JSONEncoder().encode(["value": enabled])
        _ = try await makeRequest("/quota-exceeded/switch-preview-model", method: "PATCH", body: body)
    }
    
    func setRequestRetry(_ count: Int) async throws {
        let body = try JSONEncoder().encode(["value": count])
        _ = try await makeRequest("/request-retry", method: "PUT", body: body)
    }
    
    // MARK: - Remote Configuration Getters
    
    /// Fetch the full configuration from the remote server
    func fetchConfig() async throws -> RemoteProxyConfig {
        let data = try await makeRequest("/config")
        return try JSONDecoder().decode(RemoteProxyConfig.self, from: data)
    }
    
    /// Get debug mode status
    func getDebug() async throws -> Bool {
        let data = try await makeRequest("/debug")
        let response = try JSONDecoder().decode(DebugResponse.self, from: data)
        return response.debug
    }
    
    /// Get proxy URL (upstream proxy)
    func getProxyURL() async throws -> String {
        let data = try await makeRequest("/proxy-url")
        let response = try JSONDecoder().decode(ProxyURLResponse.self, from: data)
        return response.proxyURL
    }
    
    /// Set proxy URL (upstream proxy)
    func setProxyURL(_ url: String) async throws {
        let body = try JSONEncoder().encode(["value": url])
        _ = try await makeRequest("/proxy-url", method: "PUT", body: body)
    }
    
    /// Delete/clear proxy URL
    func deleteProxyURL() async throws {
        _ = try await makeRequest("/proxy-url", method: "DELETE")
    }
    
    /// Get logging to file status
    func getLoggingToFile() async throws -> Bool {
        let data = try await makeRequest("/logging-to-file")
        let response = try JSONDecoder().decode(LoggingToFileResponse.self, from: data)
        return response.loggingToFile
    }
    
    /// Set logging to file
    func setLoggingToFile(_ enabled: Bool) async throws {
        let body = try JSONEncoder().encode(["value": enabled])
        _ = try await makeRequest("/logging-to-file", method: "PUT", body: body)
    }
    
    /// Get request log status
    func getRequestLog() async throws -> Bool {
        let data = try await makeRequest("/request-log")
        let response = try JSONDecoder().decode(RequestLogResponse.self, from: data)
        return response.requestLog
    }
    
    /// Set request log
    func setRequestLog(_ enabled: Bool) async throws {
        let body = try JSONEncoder().encode(["value": enabled])
        _ = try await makeRequest("/request-log", method: "PUT", body: body)
    }
    
    /// Get request retry count
    func getRequestRetry() async throws -> Int {
        let data = try await makeRequest("/request-retry")
        let response = try JSONDecoder().decode(RequestRetryResponse.self, from: data)
        return response.requestRetry
    }
    
    /// Get max retry interval
    func getMaxRetryInterval() async throws -> Int {
        let data = try await makeRequest("/max-retry-interval")
        let response = try JSONDecoder().decode(MaxRetryIntervalResponse.self, from: data)
        return response.maxRetryInterval
    }
    
    /// Set max retry interval
    func setMaxRetryInterval(_ seconds: Int) async throws {
        let body = try JSONEncoder().encode(["value": seconds])
        _ = try await makeRequest("/max-retry-interval", method: "PUT", body: body)
    }
    
    /// Get quota exceeded switch project status
    func getQuotaExceededSwitchProject() async throws -> Bool {
        let data = try await makeRequest("/quota-exceeded/switch-project")
        let response = try JSONDecoder().decode(SwitchProjectResponse.self, from: data)
        return response.switchProject
    }
    
    /// Get quota exceeded switch preview model status
    func getQuotaExceededSwitchPreviewModel() async throws -> Bool {
        let data = try await makeRequest("/quota-exceeded/switch-preview-model")
        let response = try JSONDecoder().decode(SwitchPreviewModelResponse.self, from: data)
        return response.switchPreviewModel
    }

    /// Get model visibility config (BaseURL/namespace/model-set control plane).
    func getModelVisibility() async throws -> ModelVisibilityConfigPayload {
        let data = try await makeRequest("/model-visibility")
        let response = try JSONDecoder().decode(ModelVisibilityEnvelope.self, from: data)
        return response.modelVisibility
    }

    /// Replace model visibility config.
    func putModelVisibility(_ config: ModelVisibilityConfigPayload) async throws {
        let body = try JSONEncoder().encode(ModelVisibilityEnvelope(modelVisibility: config))
        _ = try await makeRequest("/model-visibility", method: "PUT", body: body)
    }

    /// Patch model visibility config.
    func patchModelVisibility(
        enabled: Bool? = nil,
        namespaces: [String: [String]]? = nil,
        hostNamespaces: [String: String]? = nil
    ) async throws {
        guard enabled != nil || namespaces != nil || hostNamespaces != nil else {
            return
        }

        let body = try JSONEncoder().encode(
            ModelVisibilityPatchRequest(
                enabled: enabled,
                namespaces: namespaces,
                hostNamespaces: hostNamespaces
            )
        )
        _ = try await makeRequest("/model-visibility", method: "PATCH", body: body)
    }
    
    func uploadVertexServiceAccount(jsonPath: String) async throws {
        let url = URL(fileURLWithPath: jsonPath)
        let fileData = try Data(contentsOf: url)
        try await uploadVertexServiceAccount(data: fileData)
    }

    func uploadVertexServiceAccount(data: Data) async throws {
        _ = try await makeRequest("/vertex/import", method: "POST", body: data)
    }
    
    func fetchAPIKeys() async throws -> [String] {
        let data = try await makeRequest("/api-keys")
        let response = try JSONDecoder().decode(APIKeysResponse.self, from: data)
        return response.apiKeys
    }

    /// Fetch account-level egress mapping snapshot from management API.
    func fetchEgressMapping() async throws -> EgressMappingResponse {
        let data = try await makeRequest("/egress-mapping")
        return try JSONDecoder().decode(EgressMappingResponse.self, from: data)
    }
    
    func addAPIKey(_ key: String) async throws {
        let currentKeys = try await fetchAPIKeys()
        var newKeys = currentKeys
        newKeys.append(key)
        try await replaceAPIKeys(newKeys)
    }
    
    func replaceAPIKeys(_ keys: [String]) async throws {
        let body = try JSONEncoder().encode(keys)
        _ = try await makeRequest("/api-keys", method: "PUT", body: body)
    }
    
    func updateAPIKey(old: String, new: String) async throws {
        let body = try JSONEncoder().encode(["old": old, "new": new])
        _ = try await makeRequest("/api-keys", method: "PATCH", body: body)
    }
    
    func deleteAPIKey(value: String) async throws {
        let endpoint = endpointWithQuery("/api-keys", items: [
            URLQueryItem(name: "value", value: value)
        ])
        _ = try await makeRequest(endpoint, method: "DELETE")
    }
    
    func deleteAPIKeyByIndex(_ index: Int) async throws {
        _ = try await makeRequest("/api-keys?index=\(index)", method: "DELETE")
    }
    
    // MARK: - Proxy Version & Health
    
    /// Fetch the latest proxy version available from the running proxy.
    /// The proxy fetches this from GitHub releases.
    func fetchLatestVersion() async throws -> LatestVersionResponse {
        let data = try await makeRequest("/latest-version")
        return try JSONDecoder().decode(LatestVersionResponse.self, from: data)
    }
    
    /// Check if proxy is responding by calling the debug endpoint.
    /// This is simpler than /health which may not exist.
    func checkProxyResponding() async -> Bool {
        do {
            _ = try await makeRequest("/debug")
            return true
        } catch {
            return false
        }
    }
}

// MARK: - Latest Version Response

nonisolated struct LatestVersionResponse: Codable, Sendable {
    let latestVersion: String
    
    enum CodingKeys: String, CodingKey {
        case latestVersion = "latest-version"
    }
}

// MARK: - URLSession Delegate

private final class SessionDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, Sendable {
    private let clientId: String
    private let verifySSL: Bool
    
    init(clientId: String, verifySSL: Bool = true) {
        self.clientId = clientId
        self.verifySSL = verifySSL
        super.init()
    }
    
    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        let errorMsg = error?.localizedDescription ?? "none"
        Log.api("[\(clientId)] Session invalidated, error=\(errorMsg)")
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        guard ManagementAPIClient.enableDiagnosticLogging else { return }
        
        for metric in metrics.transactionMetrics {
            let connectionType = metric.isReusedConnection ? "reused" : "new"
            let durationSec = metric.responseEndDate?.timeIntervalSince(metric.requestStartDate ?? Date()) ?? 0
            let durationStr = String(format: "%.3f", durationSec)
            Log.api("[\(clientId)] Connection: \(connectionType), duration=\(durationStr)s")
        }
    }
    
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if !verifySSL && challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            if let serverTrust = challenge.protectionSpace.serverTrust {
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
                return
            }
        }
        completionHandler(.performDefaultHandling, nil)
    }
}

// MARK: - Response Types

nonisolated struct LogsResponse: Codable, Sendable {
    let lines: [String]?
    let lineCount: Int?
    let latestTimestamp: Int?
    
    enum CodingKeys: String, CodingKey {
        case lines
        case lineCount = "line-count"
        case latestTimestamp = "latest-timestamp"
    }
}

nonisolated struct UsageEventsResponse: Codable, Sendable {
    let events: [SSERequestEvent]
}

nonisolated struct AuthFileModelsResponse: Codable, Sendable {
    let models: [AuthFileModelInfo]
}

nonisolated struct AuthFileModelInfo: Codable, Sendable {
    let id: String
    let ownedBy: String?
    let type: String?
    
    enum CodingKeys: String, CodingKey {
        case id, type
        case ownedBy = "owned_by"
    }
}

nonisolated struct APICallRequest: Codable, Sendable {
    let authIndex: String?
    let method: String
    let url: String
    let header: [String: String]?
    let data: String?
    
    enum CodingKeys: String, CodingKey {
        case method, url, header, data
        case authIndex = "auth_index"
    }
}

nonisolated struct APICallResponse: Codable, Sendable {
    let statusCode: Int
    let header: [String: [String]]?
    let body: String?
    
    enum CodingKeys: String, CodingKey {
        case header, body
        case statusCode = "status_code"
    }
}

nonisolated struct EgressMappingResponse: Codable, Sendable {
    let available: Bool?
    let enabled: Bool?
    let driftAlertThreshold: Int?
    let totalAccounts: Int?
    let driftedAccounts: Int?
    let alertedAccounts: Int?
    let totalDriftEvents: Int?
    let inconsistentAccounts: Int?
    let totalConsistencyIssues: Int?
    let accounts: [EgressMappingAccount]
    let generatedAtUTC: String?
    let sensitiveRedaction: String?

    enum CodingKeys: String, CodingKey {
        case available
        case enabled
        case driftAlertThreshold = "drift_alert_threshold"
        case totalAccounts = "total_accounts"
        case driftedAccounts = "drifted_accounts"
        case alertedAccounts = "alerted_accounts"
        case totalDriftEvents = "total_drift_events"
        case inconsistentAccounts = "inconsistent_accounts"
        case totalConsistencyIssues = "total_consistency_issues"
        case accounts
        case generatedAtUTC = "generated_at_utc"
        case sensitiveRedaction = "sensitive_redaction"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        available = try container.decodeIfPresent(Bool.self, forKey: .available)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled)
        driftAlertThreshold = try container.decodeIfPresent(Int.self, forKey: .driftAlertThreshold)
        totalAccounts = try container.decodeIfPresent(Int.self, forKey: .totalAccounts)
        driftedAccounts = try container.decodeIfPresent(Int.self, forKey: .driftedAccounts)
        alertedAccounts = try container.decodeIfPresent(Int.self, forKey: .alertedAccounts)
        totalDriftEvents = try container.decodeIfPresent(Int.self, forKey: .totalDriftEvents)
        inconsistentAccounts = try container.decodeIfPresent(Int.self, forKey: .inconsistentAccounts)
        totalConsistencyIssues = try container.decodeIfPresent(Int.self, forKey: .totalConsistencyIssues)
        accounts = try container.decodeIfPresent([EgressMappingAccount].self, forKey: .accounts) ?? []
        generatedAtUTC = try container.decodeIfPresent(String.self, forKey: .generatedAtUTC)
        sensitiveRedaction = try container.decodeIfPresent(String.self, forKey: .sensitiveRedaction)
    }
}

nonisolated struct EgressMappingAccount: Codable, Sendable {
    let authID: String?
    let authIndex: String?
    let provider: String?
    let proxyIdentity: String?
    let driftCount: Int?
    let driftAlerted: Bool?
    let consistencyStatus: String?
    let consistencyIssues: [String]

    enum CodingKeys: String, CodingKey {
        case authID = "auth_id"
        case authIndex = "auth_index"
        case provider
        case proxyIdentity = "proxy_identity"
        case driftCount = "drift_count"
        case driftAlerted = "drift_alerted"
        case consistencyStatus = "consistency_status"
        case consistencyIssues = "consistency_issues"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        authID = try container.decodeIfPresent(String.self, forKey: .authID)
        authIndex = try container.decodeIfPresent(String.self, forKey: .authIndex)
        provider = try container.decodeIfPresent(String.self, forKey: .provider)
        proxyIdentity = try container.decodeIfPresent(String.self, forKey: .proxyIdentity)
        driftCount = try container.decodeIfPresent(Int.self, forKey: .driftCount)
        driftAlerted = try container.decodeIfPresent(Bool.self, forKey: .driftAlerted)
        consistencyStatus = try container.decodeIfPresent(String.self, forKey: .consistencyStatus)
        consistencyIssues = try container.decodeIfPresent([String].self, forKey: .consistencyIssues) ?? []
    }
}

nonisolated enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case decodingError(String)
    case connectionError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .invalidResponse: return "Invalid response"
        case .httpError(let code): return "HTTP error: \(code)"
        case .decodingError(let msg): return "Decoding error: \(msg)"
        case .connectionError(let msg): return "Connection error: \(msg)"
        }
    }
}

// MARK: - Remote Configuration Response Types

nonisolated struct RemoteProxyConfig: Codable, Sendable {
    let debug: Bool?
    let proxyURL: String?
    let routingStrategy: String?
    let requestRetry: Int?
    let maxRetryInterval: Int?
    let loggingToFile: Bool?
    let requestLog: Bool?
    let quotaExceeded: RemoteProxyQuotaExceededConfig?
    
    enum CodingKeys: String, CodingKey {
        case debug
        case proxyURL = "proxy-url"
        case routingStrategy = "routing-strategy"
        case requestRetry = "request-retry"
        case maxRetryInterval = "max-retry-interval"
        case loggingToFile = "logging-to-file"
        case requestLog = "request-log"
        case quotaExceeded = "quota-exceeded"
    }
}

nonisolated struct RemoteProxyQuotaExceededConfig: Codable, Sendable {
    let switchProject: Bool?
    let switchPreviewModel: Bool?
    
    enum CodingKeys: String, CodingKey {
        case switchProject = "switch-project"
        case switchPreviewModel = "switch-preview-model"
    }
}

nonisolated struct ModelVisibilityConfigPayload: Codable, Sendable {
    var enabled: Bool
    var namespaces: [String: [String]]
    var hostNamespaces: [String: String]

    init(
        enabled: Bool = false,
        namespaces: [String: [String]] = [:],
        hostNamespaces: [String: String] = [:]
    ) {
        self.enabled = enabled
        self.namespaces = namespaces
        self.hostNamespaces = hostNamespaces
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        namespaces = try container.decodeIfPresent([String: [String]].self, forKey: .namespaces) ?? [:]
        hostNamespaces = try container.decodeIfPresent([String: String].self, forKey: .hostNamespaces) ?? [:]
    }

    enum CodingKeys: String, CodingKey {
        case enabled
        case namespaces
        case hostNamespaces = "host-namespaces"
    }
}

nonisolated struct ModelVisibilityEnvelope: Codable, Sendable {
    let modelVisibility: ModelVisibilityConfigPayload

    enum CodingKeys: String, CodingKey {
        case modelVisibility = "model-visibility"
    }
}

nonisolated struct ModelVisibilityPatchRequest: Encodable, Sendable {
    let enabled: Bool?
    let namespaces: [String: [String]]?
    let hostNamespaces: [String: String]?

    enum CodingKeys: String, CodingKey {
        case enabled
        case namespaces
        case hostNamespaces = "host-namespaces"
    }
}

nonisolated struct DebugResponse: Codable, Sendable {
    let debug: Bool
}

nonisolated struct ProxyURLResponse: Codable, Sendable {
    let proxyURL: String
    
    enum CodingKeys: String, CodingKey {
        case proxyURL = "proxy-url"
    }
}

nonisolated struct LoggingToFileResponse: Codable, Sendable {
    let loggingToFile: Bool
    
    enum CodingKeys: String, CodingKey {
        case loggingToFile = "logging-to-file"
    }
}

nonisolated struct RequestLogResponse: Codable, Sendable {
    let requestLog: Bool
    
    enum CodingKeys: String, CodingKey {
        case requestLog = "request-log"
    }
}

nonisolated struct RequestRetryResponse: Codable, Sendable {
    let requestRetry: Int
    
    enum CodingKeys: String, CodingKey {
        case requestRetry = "request-retry"
    }
}

nonisolated struct MaxRetryIntervalResponse: Codable, Sendable {
    let maxRetryInterval: Int
    
    enum CodingKeys: String, CodingKey {
        case maxRetryInterval = "max-retry-interval"
    }
}

nonisolated struct SwitchProjectResponse: Codable, Sendable {
    let switchProject: Bool
    
    enum CodingKeys: String, CodingKey {
        case switchProject = "switch-project"
    }
}

nonisolated struct SwitchPreviewModelResponse: Codable, Sendable {
    let switchPreviewModel: Bool
    
    enum CodingKeys: String, CodingKey {
        case switchPreviewModel = "switch-preview-model"
    }
}

nonisolated struct RoutingStrategyResponse: Codable, Sendable {
    let strategy: String
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let strategy = try container.decodeIfPresent(String.self, forKey: .strategy) {
            self.strategy = strategy
        } else if let strategy = try container.decodeIfPresent(String.self, forKey: .value) {
            self.strategy = strategy
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.strategy,
                .init(codingPath: decoder.codingPath, debugDescription: "Neither 'strategy' nor 'value' key found")
            )
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(strategy, forKey: .strategy)
    }
    
    private enum CodingKeys: String, CodingKey {
        case strategy
        case value
    }
}
