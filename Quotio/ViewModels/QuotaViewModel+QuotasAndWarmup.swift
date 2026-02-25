import Foundation
import SwiftUI
import AppKit
import Observation

@MainActor
extension QuotaViewModel {
    // MARK: - Direct Auth File Management (Quota-Only Mode)
    
    /// Load auth files directly from filesystem
    func loadDirectAuthFiles() async {
        directAuthFiles = await directAuthService.scanAllAuthFiles()
    }
    
    /// Refresh quotas directly without proxy (for Quota-Only Mode)
    /// Note: Cursor and Trae are NOT auto-refreshed - user must use "Scan for IDEs" (issue #29)
    func refreshQuotasDirectly() async {
        guard !isLoadingQuotas else { return }
        
        isLoadingQuotas = true
        lastQuotaRefreshTime = Date()
        
        // Fetch from available fetchers in parallel
        // Note: Cursor and Trae removed from auto-refresh to address privacy concerns (issue #29)
        // User must explicitly scan for IDEs to detect Cursor/Trae quotas
        async let antigravity: () = refreshAntigravityQuotasInternal()
        async let openai: () = refreshOpenAIQuotasInternal()
        async let copilot: () = refreshCopilotQuotasInternal()
        async let claudeCode: () = refreshClaudeCodeQuotasInternal()
        async let codexCLI: () = refreshCodexCLIQuotasInternal()
        async let geminiCLI: () = refreshGeminiCLIQuotasInternal()
        async let glm: () = refreshGlmQuotasInternal()
        async let warp: () = refreshWarpQuotasInternal()
        async let kiro: () = refreshKiroQuotasInternal()

        _ = await (antigravity, openai, copilot, claudeCode, codexCLI, geminiCLI, glm, warp, kiro)
        
        checkQuotaNotifications()
        pruneMenuBarItems()
        autoSelectMenuBarItems()

        isLoadingQuotas = false
        notifyQuotaDataChanged()
    }

    func autoSelectMenuBarItems() {
        var availableItems: [MenuBarQuotaItem] = []
        var seen = Set<String>()
        
        for (provider, accountQuotas) in providerQuotas {
            for (accountKey, _) in accountQuotas {
                let item = MenuBarQuotaItem(provider: provider.rawValue, accountKey: accountKey)
                if !seen.contains(item.id) {
                    seen.insert(item.id)
                    availableItems.append(item)
                }
            }
        }
        
        for file in authFiles {
            guard let provider = file.providerType else { continue }
            let item = MenuBarQuotaItem(provider: provider.rawValue, accountKey: file.menuBarAccountKey)
            if !seen.contains(item.id) {
                seen.insert(item.id)
                availableItems.append(item)
            }
        }
        
        for file in directAuthFiles {
            let item = MenuBarQuotaItem(provider: file.provider.rawValue, accountKey: file.menuBarAccountKey)
            if !seen.contains(item.id) {
                seen.insert(item.id)
                availableItems.append(item)
            }
        }
        
        menuBarSettings.autoSelectNewAccounts(availableItems: availableItems)
    }
    
    func syncMenuBarSelection() {
        pruneMenuBarItems()
        autoSelectMenuBarItems()
    }
    
    /// Refresh Claude Code quota using CLI
    func refreshClaudeCodeQuotasInternal() async {
        let quotas = await claudeCodeFetcher.fetchAsProviderQuota()
        if quotas.isEmpty {
            // Only remove if no other source has Claude data
            if providerQuotas[.claude]?.isEmpty ?? true {
                providerQuotas.removeValue(forKey: .claude)
            }
        } else {
            // Merge with existing data (don't overwrite proxy data)
            if var existing = providerQuotas[.claude] {
                for (email, quota) in quotas {
                    existing[email] = quota
                }
                providerQuotas[.claude] = existing
            } else {
                providerQuotas[.claude] = quotas
            }
        }
    }
    
    /// Refresh Cursor quota using browser cookies
    func refreshCursorQuotasInternal() async {
        let quotas = await cursorFetcher.fetchAsProviderQuota()
        if quotas.isEmpty {
            // No Cursor auth found - remove from providerQuotas
            providerQuotas.removeValue(forKey: .cursor)
        } else {
            providerQuotas[.cursor] = quotas
        }
    }
    
    /// Refresh Codex quota using CLI auth file (~/.codex/auth.json)
    func refreshCodexCLIQuotasInternal() async {
        await refreshCodexCLIQuotasFallback(allowAllModes: false)
    }

    /// Use Codex CLI as fallback source when proxy auth-based data is absent.
    func refreshCodexCLIQuotasFallback(allowAllModes: Bool) async {
        if !allowAllModes && !modeManager.isMonitorMode {
            return
        }

        if let existing = providerQuotas[.codex], !existing.isEmpty {
            return
        }

        let quotas = await codexCLIFetcher.fetchAsProviderQuota()
        if !quotas.isEmpty {
            providerQuotas[.codex] = quotas
        }
    }
    
    /// Refresh Gemini quota using CLI auth file (~/.gemini/oauth_creds.json)
    func refreshGeminiCLIQuotasInternal() async {
        // Only use CLI fetcher in quota-only mode
        guard modeManager.isMonitorMode else { return }

        let quotas = await geminiCLIFetcher.fetchAsProviderQuota()
        if !quotas.isEmpty {
            if var existing = providerQuotas[.gemini] {
                for (email, quota) in quotas {
                    existing[email] = quota
                }
                providerQuotas[.gemini] = existing
            } else {
                providerQuotas[.gemini] = quotas
            }
        }
    }

    /// Refresh GLM quota using API keys from CustomProviderService
    func refreshGlmQuotasInternal() async {
        let quotas = await glmFetcher.fetchAllQuotas()
        if !quotas.isEmpty {
            providerQuotas[.glm] = quotas
        } else {
            providerQuotas.removeValue(forKey: .glm)
        }
    }
    
    /// Refresh Warp quota using API keys from WarpService
    func refreshWarpQuotasInternal() async {
        let warpTokens = await MainActor.run {
            WarpService.shared.tokens.filter { $0.isEnabled }
        }
        
        var results: [String: ProviderQuotaData] = [:]
        
        for entry in warpTokens {
            do {
                let quota = try await warpFetcher.fetchQuota(apiKey: entry.token)
                results[entry.name] = quota
            } catch {
                Log.quota("Failed to fetch Warp quota for \(entry.name): \(error)")
            }
        }
        
        if !results.isEmpty {
            providerQuotas[.warp] = results
        } else {
            providerQuotas.removeValue(forKey: .warp)
        }
    }
    
    /// Refresh Trae quota using SQLite database
    func refreshTraeQuotasInternal() async {
        let quotas = await traeFetcher.fetchAsProviderQuota()
        if quotas.isEmpty {
            providerQuotas.removeValue(forKey: .trae)
        } else {
            providerQuotas[.trae] = quotas
        }
    }
    
    /// Refresh Kiro quota using IDE JSON tokens
    func refreshKiroQuotasInternal() async {
        let rawQuotas = await kiroFetcher.fetchAllQuotas()
        
        var remappedQuotas: [String: ProviderQuotaData] = [:]
        
        // Helper: clean filename (remove .json)
        func cleanName(_ name: String) -> String {
            name.replacingOccurrences(of: ".json", with: "")
        }
        
        // 1. Remap for Proxy AuthFiles
        var consumedRawKeys = Set<String>()
        
        for file in authFiles where file.providerType == .kiro {
            // The fetcher returns data keyed by clean filename
            let filenameKey = cleanName(file.name)
            
            if let data = rawQuotas[filenameKey] {
                // Store under the key the UI expects (AuthFile.quotaLookupKey)
                let targetKey = file.quotaLookupKey.isEmpty ? file.name : file.quotaLookupKey
                remappedQuotas[targetKey] = data
                consumedRawKeys.insert(filenameKey)
            }
        }
        
        // 2. Remap for Direct AuthFiles (Monitor Mode)
        if modeManager.isMonitorMode {
            for file in directAuthFiles where file.provider == .kiro {
                let filenameKey = cleanName(file.filename)
                
                // Skip if already processed by Proxy loop
                if consumedRawKeys.contains(filenameKey) { continue }
                
                if let data = rawQuotas[filenameKey] {
                    let targetKey = file.email ?? file.filename
                    remappedQuotas[targetKey] = data
                    consumedRawKeys.insert(filenameKey)
                }
            }
        }
        
        // 3. Fallback: Include original keys ONLY if not mapped
        for (key, data) in rawQuotas {
            if !consumedRawKeys.contains(key) {
                remappedQuotas[key] = data
            }
        }

        if remappedQuotas.isEmpty {
            providerQuotas.removeValue(forKey: .kiro)
        } else {
            providerQuotas[.kiro] = remappedQuotas
        }
    }
    
    /// Start auto-refresh for quota-only mode
    func startQuotaOnlyAutoRefresh() {
        refreshTask?.cancel()
        
        guard let intervalNs = refreshSettings.refreshCadence.intervalNanoseconds else {
            // Manual mode - no auto-refresh
            return
        }
        
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: intervalNs)
                _ = await kiroFetcher.refreshAllTokensIfNeeded()
                await refreshQuotasDirectly()
            }
        }
    }
    
    /// Start auto-refresh for quota when proxy is not running (Full Mode)
    func startQuotaAutoRefreshWithoutProxy() {
        refreshTask?.cancel()
        
        guard let intervalNs = refreshSettings.refreshCadence.intervalNanoseconds else {
            return
        }
        
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: intervalNs)
                if !proxyManager.proxyStatus.running {
                    _ = await kiroFetcher.refreshAllTokensIfNeeded()
                    await refreshQuotasUnified()
                }
            }
        }
    }

    /// Codex quota evidence should refresh independently of generic refresh cadence.
    func restartCodexAutoRefresh() {
        codexAutoRefreshTask?.cancel()
        codexAutoRefreshTask = nil

        guard !modeManager.isRemoteProxyMode else { return }

        codexAutoRefreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: codexAutoRefreshIntervalNs)
                await refreshCodexQuotaEvidence()
            }
        }
    }

    func stopCodexAutoRefresh() {
        codexAutoRefreshTask?.cancel()
        codexAutoRefreshTask = nil
    }

    func refreshCodexQuotaEvidence() async {
        guard !modeManager.isRemoteProxyMode else { return }
        guard !isLoadingQuotas else { return }

        await refreshOpenAIQuotasInternal()
        await refreshCodexCLIQuotasFallback(allowAllModes: true)
        notifyQuotaDataChanged()
    }

    // MARK: - Warmup

    func isWarmupEnabled(for provider: AIProvider, accountKey: String) -> Bool {
        warmupSettings.isEnabled(provider: provider, accountKey: accountKey)
    }

    func warmupStatus(provider: AIProvider, accountKey: String) -> WarmupStatus {
        let key = WarmupAccountKey(provider: provider, accountKey: accountKey)
        return warmupStatuses[key] ?? WarmupStatus()
    }

    func warmupNextRunDate(provider: AIProvider, accountKey: String) -> Date? {
        let key = WarmupAccountKey(provider: provider, accountKey: accountKey)
        return warmupNextRun[key]
    }

    func toggleWarmup(for provider: AIProvider, accountKey: String) {
        guard provider == .antigravity else {
            // Warmup not supported for this provider; no log.
            return
        }
        warmupSettings.toggle(provider: provider, accountKey: accountKey)
        // Warmup toggle state changed; no log.
    }

    func setWarmupEnabled(_ enabled: Bool, provider: AIProvider, accountKey: String) {
        guard provider == .antigravity else {
            // Warmup not supported for this provider; no log.
            return
        }
        if warmupSettings.isEnabled(provider: provider, accountKey: accountKey) == enabled {
            return
        }
        warmupSettings.setEnabled(enabled, provider: provider, accountKey: accountKey)
        // Warmup toggle state changed; no log.
    }

    func nextDailyRunDate(minutes: Int, now: Date) -> Date {
        let calendar = Calendar.current
        let hour = minutes / 60
        let minute = minutes % 60
        let today = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) ?? now
        if today > now {
            return today
        }
        return calendar.date(byAdding: .day, value: 1, to: today) ?? today
    }

    func restartWarmupScheduler() {
        warmupTask?.cancel()
        
        guard !warmupSettings.enabledAccountIds.isEmpty else { return }
        
        let now = Date()
        warmupNextRun = [:]
        for target in warmupTargets() {
            let mode = warmupSettings.warmupScheduleMode(provider: target.provider, accountKey: target.accountKey)
            switch mode {
            case .interval:
                warmupNextRun[target] = now
            case .daily:
                let minutes = warmupSettings.warmupDailyMinutes(provider: target.provider, accountKey: target.accountKey)
                warmupNextRun[target] = nextDailyRunDate(minutes: minutes, now: now)
            }
            updateWarmupStatus(for: target) { status in
                status.nextRun = warmupNextRun[target]
            }
        }
        guard !warmupNextRun.isEmpty else { return }
        
        warmupTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                guard let next = warmupNextRun.values.min() else { return }
                let delay = max(next.timeIntervalSince(Date()), 1)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                await runWarmupCycle()
            }
        }
    }

    func runWarmupCycle() async {
        guard !isWarmupRunning else { return }
        let targets = warmupTargets()
        guard !targets.isEmpty else { return }
        
        guard proxyManager.proxyStatus.running else {
            let now = Date()
            for target in targets {
                let mode = warmupSettings.warmupScheduleMode(provider: target.provider, accountKey: target.accountKey)
                switch mode {
                case .interval:
                    let cadence = warmupSettings.warmupCadence(provider: target.provider, accountKey: target.accountKey)
                    warmupNextRun[target] = now.addingTimeInterval(cadence.intervalSeconds)
                case .daily:
                    let minutes = warmupSettings.warmupDailyMinutes(provider: target.provider, accountKey: target.accountKey)
                    warmupNextRun[target] = nextDailyRunDate(minutes: minutes, now: now)
                }
                updateWarmupStatus(for: target) { status in
                    status.nextRun = warmupNextRun[target]
                }
            }
            return
        }
        
        isWarmupRunning = true
        defer { isWarmupRunning = false }
        
        // Warmup cycle started; no log.
        
        let now = Date()
        let dueTargets = targets.filter { target in
            guard let next = warmupNextRun[target] else { return false }
            return next <= now
        }
        
        for target in dueTargets {
            if Task.isCancelled { break }
            await warmupAccount(
                provider: target.provider,
                accountKey: target.accountKey
            )
            let mode = warmupSettings.warmupScheduleMode(provider: target.provider, accountKey: target.accountKey)
            switch mode {
            case .interval:
                let cadence = warmupSettings.warmupCadence(provider: target.provider, accountKey: target.accountKey)
                warmupNextRun[target] = Date().addingTimeInterval(cadence.intervalSeconds)
            case .daily:
                let minutes = warmupSettings.warmupDailyMinutes(provider: target.provider, accountKey: target.accountKey)
                warmupNextRun[target] = nextDailyRunDate(minutes: minutes, now: Date())
            }
            updateWarmupStatus(for: target) { status in
                status.nextRun = warmupNextRun[target]
                status.lastError = nil
            }
        }

        for target in targets where !dueTargets.contains(target) {
            updateWarmupStatus(for: target) { status in
                status.lastError = nil
            }
        }
    }

    func warmupAccount(provider: AIProvider, accountKey: String) async {
        guard provider == .antigravity else {
            // Warmup not supported for this provider; no log.
            return
        }
        let account = WarmupAccountKey(provider: provider, accountKey: accountKey)
        guard warmupRunningAccounts.insert(account).inserted else {
            // Warmup already running for this account; no log.
            return
        }
        defer { warmupRunningAccounts.remove(account) }
        guard proxyManager.proxyStatus.running else {
            // Warmup skipped when proxy is not running; no log.
            return
        }
        
        guard let apiClient else {
            // Warmup skipped when management client is missing; no log.
            return
        }
        
        guard let authInfo = warmupAuthInfo(provider: provider, accountKey: accountKey) else {
            // Warmup skipped when auth index is missing; no log.
            return
        }
        
        let availableModels = await fetchWarmupModels(
            provider: provider,
            accountKey: accountKey,
            authFileName: authInfo.authFileName,
            apiClient: apiClient
        )
        guard !availableModels.isEmpty else {
            // Warmup skipped when no models are available; no log.
            return
        }
        await warmupAccount(
            provider: provider,
            accountKey: accountKey,
            availableModels: availableModels,
            authIndex: authInfo.authIndex,
            apiClient: apiClient
        )
    }

    func warmupAccount(
        provider: AIProvider,
        accountKey: String,
        availableModels: [WarmupModelInfo],
        authIndex: String,
        apiClient: ManagementAPIClient
    ) async {
        guard provider == .antigravity else {
            // Warmup not supported for this provider; no log.
            return
        }
        let availableIds = availableModels.map(\.id)
        let selectedModels = warmupSettings.selectedModels(provider: provider, accountKey: accountKey)
        let models = selectedModels.filter { availableIds.contains($0) }
        guard !models.isEmpty else {
            // Warmup skipped when no matching models; no log.
            return
        }
        let account = WarmupAccountKey(provider: provider, accountKey: accountKey)
        updateWarmupStatus(for: account) { status in
            status.isRunning = true
            status.lastError = nil
            status.progressTotal = models.count
            status.progressCompleted = 0
            status.currentModel = nil
            for model in models {
                status.modelStates[model] = .pending
            }
        }
        
        for model in models {
            if Task.isCancelled { break }
            do {
                updateWarmupStatus(for: account) { status in
                    status.currentModel = model
                    status.modelStates[model] = .running
                }
                try await warmupService.warmup(
                    managementClient: apiClient,
                    authIndex: authIndex,
                    model: model
                )
                updateWarmupStatus(for: account) { status in
                    status.progressCompleted += 1
                    status.modelStates[model] = .succeeded
                }
            } catch {
                updateWarmupStatus(for: account) { status in
                    status.progressCompleted += 1
                    status.modelStates[model] = .failed
                    status.lastError = error.localizedDescription
                }
            }
        }
        updateWarmupStatus(for: account) { status in
            status.isRunning = false
            status.currentModel = nil
            status.lastRun = Date()
        }
    }

    func fetchWarmupModels(
        provider: AIProvider,
        accountKey: String,
        authFileName: String,
        apiClient: ManagementAPIClient
    ) async -> [WarmupModelInfo] {
        do {
            let key = WarmupAccountKey(provider: provider, accountKey: accountKey)
            if let cached = warmupModelCache[key] {
                let age = Date().timeIntervalSince(cached.fetchedAt)
                if age <= warmupModelCacheTTL {
                    return cached.models
                }
            }
            let models = try await warmupService.fetchModels(managementClient: apiClient, authFileName: authFileName)
            warmupModelCache[key] = (models: models, fetchedAt: Date())
            // Warmup fetched models; no log.
            return models
        } catch {
            // Warmup fetch failed; no log.
            return []
        }
    }

    func warmupAvailableModels(provider: AIProvider, accountKey: String) async -> [String] {
        guard provider == .antigravity else { return [] }
        guard let apiClient else { return [] }
        guard let authInfo = warmupAuthInfo(provider: provider, accountKey: accountKey) else { return [] }
        let models = await fetchWarmupModels(
            provider: provider,
            accountKey: accountKey,
            authFileName: authInfo.authFileName,
            apiClient: apiClient
        )
        return models.map(\.id).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func warmupAuthInfo(provider: AIProvider, accountKey: String) -> (authIndex: String, authFileName: String)? {
        guard let authFile = authFiles.first(where: {
            $0.providerType == provider && $0.quotaLookupKey == accountKey
        }) else {
            // Warmup skipped when auth file is missing; no log.
            return nil
        }
        
        guard let authIndex = authFile.authIndex, !authIndex.isEmpty else {
            // Warmup skipped when auth index is missing; no log.
            return nil
        }
        
        let name = authFile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            // Warmup skipped when auth file name is missing; no log.
            return nil
        }
        
        return (authIndex: authIndex, authFileName: name)
    }

    func warmupTargets() -> [WarmupAccountKey] {
        let keys = warmupSettings.enabledAccountIds.compactMap { id in
            WarmupSettingsManager.parseAccountId(id)
        }
        return keys.filter { $0.provider == .antigravity }.sorted { lhs, rhs in
            if lhs.provider.displayName == rhs.provider.displayName {
                return lhs.accountKey < rhs.accountKey
            }
            return lhs.provider.displayName < rhs.provider.displayName
        }
    }

    // Warmup logging intentionally disabled.
    
    func updateWarmupStatus(for key: WarmupAccountKey, update: (inout WarmupStatus) -> Void) {
        var status = warmupStatuses[key] ?? WarmupStatus()
        update(&status)
        warmupStatuses[key] = status
    }
    
    var authFilesByProvider: [AIProvider: [AuthFile]] {
        var result: [AIProvider: [AuthFile]] = [:]
        for file in authFiles {
            if let provider = file.providerType {
                result[provider, default: []].append(file)
            }
        }
        return result
    }
    
    var connectedProviders: [AIProvider] {
        Array(Set(authFiles.compactMap { $0.providerType })).sorted { $0.displayName < $1.displayName }
    }
    
    var disconnectedProviders: [AIProvider] {
        AIProvider.allCases.filter { provider in
            !connectedProviders.contains(provider)
        }
    }
    
    var totalAccounts: Int { authFiles.count }
    var readyAccounts: Int { authFiles.filter { $0.isReady }.count }
    
}
