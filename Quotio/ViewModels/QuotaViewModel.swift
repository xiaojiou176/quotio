//
//  QuotaViewModel.swift
//  Quotio - CLIProxyAPI GUI Wrapper
//

import Foundation
import SwiftUI
import AppKit
import Observation

@MainActor
@Observable
final class QuotaViewModel {
    let proxyManager: CLIProxyManager
    @ObservationIgnored var _apiClient: ManagementAPIClient?
    
    var apiClient: ManagementAPIClient? { _apiClient }
    @ObservationIgnored let antigravityFetcher = AntigravityQuotaFetcher()
    @ObservationIgnored let openAIFetcher = OpenAIQuotaFetcher()
    @ObservationIgnored let copilotFetcher = CopilotQuotaFetcher()
    @ObservationIgnored let glmFetcher = GLMQuotaFetcher()
    @ObservationIgnored let warpFetcher = WarpQuotaFetcher()
    @ObservationIgnored let directAuthService = DirectAuthFileService()
    @ObservationIgnored let notificationManager = NotificationManager.shared
    @ObservationIgnored let modeManager = OperatingModeManager.shared
    @ObservationIgnored let refreshSettings = RefreshSettingsManager.shared
    @ObservationIgnored let warmupSettings = WarmupSettingsManager.shared
    @ObservationIgnored let warmupService = WarmupService()
    var warmupNextRun: [WarmupAccountKey: Date] = [:]
    var warmupStatuses: [WarmupAccountKey: WarmupStatus] = [:]
    @ObservationIgnored var warmupModelCache: [WarmupAccountKey: (models: [WarmupModelInfo], fetchedAt: Date)] = [:]
    @ObservationIgnored let warmupModelCacheTTL: TimeInterval = 28800
    @ObservationIgnored var lastProxyURL: String?
    @ObservationIgnored static let baseURLNamespaceModelSetsKey = "persisted.hybrid.baseURLNamespaceModelSets"
    
    /// Request tracker for monitoring API requests through ProxyBridge
    let requestTracker = RequestTracker.shared
    
    /// Tunnel manager for Cloudflare Tunnel integration
    let tunnelManager = TunnelManager.shared
    
    // Quota-Only Mode Fetchers (CLI-based)
    @ObservationIgnored let claudeCodeFetcher = ClaudeCodeQuotaFetcher()
    @ObservationIgnored let cursorFetcher = CursorQuotaFetcher()
    @ObservationIgnored let codexCLIFetcher = CodexCLIQuotaFetcher()
    @ObservationIgnored let geminiCLIFetcher = GeminiCLIQuotaFetcher()
    @ObservationIgnored let traeFetcher = TraeQuotaFetcher()
    @ObservationIgnored let kiroFetcher = KiroQuotaFetcher()
    
    @ObservationIgnored var lastKnownAccountStatuses: [String: String] = [:]
    
    var currentPage: NavigationPage = .dashboard
    var observabilityFocusFilter: ObservabilityFocusFilter?
    var authFiles: [AuthFile] = []
    var usageStats: UsageStats?
    var apiKeys: [String] = []
    var isLoading = false
    var isLoadingQuotas = false
    var errorMessage: String?
    var oauthState: OAuthState?

    /// Notification name for quota data updates (used for menu bar refresh)
    static let quotaDataDidChangeNotification = Notification.Name("QuotaViewModel.quotaDataDidChange")

    func setObservabilityFocus(_ filter: ObservabilityFocusFilter?) {
        observabilityFocusFilter = filter
    }
    
    /// Direct auth files for quota-only mode
    var directAuthFiles: [DirectAuthFile] = []
    
    /// Last quota refresh time (for quota-only mode display)
    var lastQuotaRefreshTime: Date?
    
    /// Hybrid control plane persistence: Base URL namespace -> model set mapping.
    var baseURLNamespaceModelSets: [BaseURLNamespaceModelSet] = []
    
    /// IDE Scan state
    var showIDEScanSheet = false
    @ObservationIgnored let ideScanSettings = IDEScanSettingsManager.shared
    
    @ObservationIgnored var _agentSetupViewModel: AgentSetupViewModel?
    var agentSetupViewModel: AgentSetupViewModel {
        if let vm = _agentSetupViewModel {
            return vm
        }
        let vm = AgentSetupViewModel()
        vm.setup(proxyManager: proxyManager, quotaViewModel: self)
        _agentSetupViewModel = vm
        return vm
    }

    @ObservationIgnored var _reviewQueueViewModel: ReviewQueueViewModel?
    var reviewQueueViewModel: ReviewQueueViewModel {
        if let vm = _reviewQueueViewModel {
            return vm
        }
        let vm = ReviewQueueViewModel()
        _reviewQueueViewModel = vm
        return vm
    }
    
    /// Quota data per provider per account (email -> QuotaData)
    var providerQuotas: [AIProvider: [String: ProviderQuotaData]] = [:]
    
    /// Last fetch failure reason per provider/account key.
    /// Used by quota cards to explain why an account currently has no quota data.
    var providerQuotaFailures: [AIProvider: [String: String]] = [:]
    
    /// Subscription info per provider per account (provider -> email -> SubscriptionInfo)
    var subscriptionInfos: [AIProvider: [String: SubscriptionInfo]] = [:]
    
    /// Antigravity account switcher (for IDE token injection)
    let antigravitySwitcher = AntigravityAccountSwitcher.shared
    
    @ObservationIgnored var refreshTask: Task<Void, Never>?
    @ObservationIgnored var codexAutoRefreshTask: Task<Void, Never>?
    @ObservationIgnored var warmupTask: Task<Void, Never>?
    @ObservationIgnored var isStartingProxyFlow = false
    @ObservationIgnored var lastLogTimestamp: Int?
    @ObservationIgnored var isWarmupRunning = false
    @ObservationIgnored var warmupRunningAccounts: Set<WarmupAccountKey> = []
    @ObservationIgnored let codexAutoRefreshIntervalNs: UInt64 = 60_000_000_000

    struct WarmupStatus: Sendable {
        var isRunning: Bool = false
        var lastRun: Date?
        var nextRun: Date?
        var lastError: String?
        var progressCompleted: Int = 0
        var progressTotal: Int = 0
        var currentModel: String?
        var modelStates: [String: WarmupModelState] = [:]
    }

    enum WarmupModelState: String, Sendable {
        case pending
        case running
        case succeeded
        case failed
    }
    
    // MARK: - IDE Quota Persistence Keys

    static let ideQuotasKey = "persisted.ideQuotas"
    static let ideProvidersToSave: Set<AIProvider> = [.cursor, .trae]

    /// Key for tracking when auth files last changed (for model cache invalidation)
    static let authFilesChangedKey = "quotio.authFiles.lastChanged"

    // MARK: - Disabled Auth Files Persistence

    static let disabledAuthFilesKey = "persisted.disabledAuthFiles"

    /// Load disabled auth file names from UserDefaults
    func loadDisabledAuthFiles() -> Set<String> {
        let array = UserDefaults.standard.stringArray(forKey: Self.disabledAuthFilesKey) ?? []
        return Set(array)
    }

    /// Save disabled auth file names to UserDefaults
    func saveDisabledAuthFiles(_ names: Set<String>) {
        UserDefaults.standard.set(Array(names), forKey: Self.disabledAuthFilesKey)
    }

    /// Sync local disabled state to backend after proxy starts
    func syncDisabledStatesToBackend() async {
        guard let client = apiClient else { return }

        let localDisabled = loadDisabledAuthFiles()
        guard !localDisabled.isEmpty else { return }

        for name in localDisabled {
            // Only sync if this auth file exists
            guard authFiles.contains(where: { $0.name == name }) else { continue }

            do {
                try await client.setAuthFileDisabled(name: name, disabled: true)
            } catch {
                Log.error("syncDisabledStatesToBackend: Failed for \(name) - \(error.localizedDescription)")
            }
        }
    }

    /// Post notification to trigger UI updates (works even when window is closed)
    func notifyQuotaDataChanged() {
        NotificationCenter.default.post(name: Self.quotaDataDidChangeNotification, object: nil)
    }

    init() {
        self.proxyManager = CLIProxyManager.shared
        loadPersistedIDEQuotas()
        loadBaseURLNamespaceModelSets()
        setupRefreshCadenceCallback()
        setupWarmupCallback()
        restartWarmupScheduler()
        lastProxyURL = normalizedProxyURL(UserDefaults.standard.string(forKey: "proxyURL"))
        setupProxyURLObserver()
    }

    func setupProxyURLObserver() {
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let currentProxyURL = self.normalizedProxyURL(UserDefaults.standard.string(forKey: "proxyURL"))
                guard currentProxyURL != self.lastProxyURL else { return }
                self.lastProxyURL = currentProxyURL
                await self.updateProxyConfiguration()
            }
        }
    }

    func normalizedProxyURL(_ rawValue: String?) -> String? {
        guard let rawValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawValue.isEmpty else {
            return nil
        }

        let sanitized = ProxyURLValidator.sanitize(rawValue)
        return sanitized.isEmpty ? nil : sanitized
    }

    /// Update proxy configuration for all quota fetchers
    func updateProxyConfiguration() async {
        await antigravityFetcher.updateProxyConfiguration()
        await openAIFetcher.updateProxyConfiguration()
        await copilotFetcher.updateProxyConfiguration()
        await glmFetcher.updateProxyConfiguration()
        await claudeCodeFetcher.updateProxyConfiguration()
        await cursorFetcher.updateProxyConfiguration()
        await codexCLIFetcher.updateProxyConfiguration()
        await geminiCLIFetcher.updateProxyConfiguration()
        await warpFetcher.updateProxyConfiguration()
        await traeFetcher.updateProxyConfiguration()
        await kiroFetcher.updateProxyConfiguration()
    }

    func setupRefreshCadenceCallback() {
        refreshSettings.onRefreshCadenceChanged = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.restartAutoRefresh()
            }
        }
    }
    
    func setupWarmupCallback() {
        warmupSettings.onEnabledAccountsChanged = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.restartWarmupScheduler()
            }
        }
        warmupSettings.onWarmupCadenceChanged = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.restartWarmupScheduler()
            }
        }
        warmupSettings.onWarmupScheduleChanged = { [weak self] in
            Task { @MainActor [weak self] in
                self?.restartWarmupScheduler()
            }
        }
    }
    
    func restartAutoRefresh() {
        if modeManager.isMonitorMode {
            startQuotaOnlyAutoRefresh()
        } else if proxyManager.proxyStatus.running {
            startAutoRefresh()
        } else {
            startQuotaAutoRefreshWithoutProxy()
        }
        restartCodexAutoRefresh()
    }
    
    // MARK: - Mode-Aware Initialization
    
    func initialize() async {
        if modeManager.isRemoteProxyMode {
            await initializeRemoteMode()
        } else if modeManager.isMonitorMode {
            await initializeQuotaOnlyMode()
        } else {
            await initializeFullMode()
        }
    }
    
    func initializeFullMode() async {
        // Always refresh quotas directly first (works without proxy)
        await refreshQuotasUnified()
        restartCodexAutoRefresh()
        
        let autoStartProxy = UserDefaults.standard.bool(forKey: "autoStartProxy")
        if autoStartProxy && proxyManager.isBinaryInstalled {
            await startProxy()
            // Note: checkForProxyUpgrade() is now called inside startProxy()
        } else {
            // If not auto-starting proxy, start quota auto-refresh
            startQuotaAutoRefreshWithoutProxy()
        }
    }
    
    /// Check for proxy upgrade (non-blocking)
    func checkForProxyUpgrade() async {
        await proxyManager.checkForUpgrade()
    }
    
    /// Initialize for Quota-Only Mode (no proxy)
    func initializeQuotaOnlyMode() async {
        // Load auth files directly from filesystem
        await loadDirectAuthFiles()
        
        // Fetch quotas directly
        await refreshQuotasDirectly()
        
        // Start auto-refresh for quota-only mode
        startQuotaOnlyAutoRefresh()
        restartCodexAutoRefresh()
    }
    
    func initializeRemoteMode() async {
        stopCodexAutoRefresh()
        guard modeManager.hasValidRemoteConfig,
              let config = modeManager.remoteConfig,
              let managementKey = modeManager.remoteManagementKey else {
            modeManager.setConnectionStatus(.error("No valid remote configuration"))
            return
        }
        
        modeManager.setConnectionStatus(.connecting)
        
        await setupRemoteAPIClient(config: config, managementKey: managementKey)
        
        guard let client = apiClient else {
            modeManager.setConnectionStatus(.error("Failed to create API client"))
            return
        }
        
        let isConnected = await client.checkProxyResponding()
        
        if isConnected {
            modeManager.markConnected()
            await refreshData()
            startAutoRefresh()
        } else {
            modeManager.setConnectionStatus(.error("Could not connect to remote server"))
        }
    }
    
    func setupRemoteAPIClient(config: RemoteConnectionConfig, managementKey: String) async {
        if let existingClient = _apiClient {
            await existingClient.invalidate()
        }
        
        _apiClient = ManagementAPIClient(config: config, managementKey: managementKey)
    }
    
    func reconnectRemote() async {
        guard modeManager.isRemoteProxyMode else { return }
        await initializeRemoteMode()
    }
    
    func startProxy() async {
        guard !isStartingProxyFlow else { return }
        isStartingProxyFlow = true

        defer {
            isStartingProxyFlow = false
        }

        do {
            // Wire up ProxyBridge callback to RequestTracker before starting
            proxyManager.proxyBridge.onRequestCompleted = { [weak self] metadata in
                self?.requestTracker.addRequest(from: metadata)
            }
            
            try await proxyManager.start()
            setupAPIClient()
            startAutoRefresh()
            restartCodexAutoRefresh()
            restartWarmupScheduler()

            // Start RequestTracker
            requestTracker.start()

            await refreshData()

            // Sync local disabled states to backend after data is loaded
            await syncDisabledStatesToBackend()
            await refreshData()

            await runWarmupCycle()

            // Check for proxy upgrade (non-blocking, fire-and-forget)
            Task {
                guard !AppLifecycleState.isTerminating else { return }
                await checkForProxyUpgrade()
            }

            let autoStartTunnel = UserDefaults.standard.bool(forKey: "autoStartTunnel")
            if autoStartTunnel && tunnelManager.installation.isInstalled {
                await tunnelManager.startTunnel(port: proxyManager.port)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func stopProxy() {
        refreshTask?.cancel()
        refreshTask = nil
        restartCodexAutoRefresh()

        if tunnelManager.tunnelState.isActive || tunnelManager.tunnelState.status == .starting {
            Task { @MainActor in
                await tunnelManager.stopTunnel()
            }
        }
        
        // Stop RequestTracker
        requestTracker.stop()
        
        proxyManager.stop()
        restartWarmupScheduler()
        
        // Invalidate URLSession to close all connections
        // Capture client reference before setting to nil to avoid race condition
        let clientToInvalidate = _apiClient
        _apiClient = nil
        
        if let client = clientToInvalidate {
            Task {
                await client.invalidate()
            }
        }
    }
    
    func toggleProxy() async {
        if proxyManager.proxyStatus.running {
            stopProxy()
        } else {
            await startProxy()
        }
    }
    
    func setupAPIClient() {
        _apiClient = ManagementAPIClient(
            baseURL: proxyManager.managementURL,
            authKey: proxyManager.managementKey
        )
    }
    
    func startAutoRefresh() {
        refreshTask?.cancel()
        
        guard let intervalNs = refreshSettings.refreshCadence.intervalNanoseconds else {
            return
        }
        
        refreshTask = Task {
            var consecutiveFailures = 0
            let maxFailuresBeforeRecovery = max(3, Int(180_000_000_000 / intervalNs))
            
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: intervalNs)
                
                await refreshData()
                
                if errorMessage != nil {
                    consecutiveFailures += 1
                    Log.quota("Refresh failed, consecutive failures: \(consecutiveFailures)")
                    
                    if consecutiveFailures >= maxFailuresBeforeRecovery {
                        Log.quota("Attempting proxy recovery...")
                        await attemptProxyRecovery()
                        consecutiveFailures = 0
                    }
                } else {
                    if consecutiveFailures > 0 {
                        Log.quota("Refresh succeeded, resetting failure count")
                    }
                    consecutiveFailures = 0
                }
            }
        }
    }
    
    /// Attempt to recover an unresponsive proxy
    func attemptProxyRecovery() async {
        // Check if process is still running
        if proxyManager.proxyStatus.running {
            // Proxy process is running but not responding - likely hung
            // Stop and restart
            stopProxy()
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
            await startProxy()
        }
    }
    
    @ObservationIgnored var lastQuotaRefresh: Date?
    
    var quotaRefreshInterval: TimeInterval {
        refreshSettings.refreshCadence.intervalSeconds ?? 60
    }
    
}

struct OAuthState {
    let provider: AIProvider
    var status: OAuthStatus
    var state: String?
    var error: String?
    var authURL: String?
    
    enum OAuthStatus {
        case waiting, polling, success, error
    }
}
