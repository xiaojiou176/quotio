import Foundation
import SwiftUI
import AppKit
import Observation

@MainActor
extension QuotaViewModel {
    func refreshData() async {
        guard let client = apiClient else { return }
        
        do {
            // Serialize requests to avoid connection contention (issue #37)
            // This reduces pressure on the connection pool
            let newAuthFiles = try await client.fetchAuthFiles()

            // Only update timestamp if auth files actually changed (account added/removed)
            let oldNames = Set(self.authFiles.map { $0.name })
            let newNames = Set(newAuthFiles.map { $0.name })
            if oldNames != newNames {
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.authFilesChangedKey)
            }

            self.authFiles = newAuthFiles

            self.usageStats = try await client.fetchUsageStats()
            self.apiKeys = try await client.fetchAPIKeys()
            
            // Clear any previous error on success
            errorMessage = nil
            
            checkAccountStatusChanges()
            
            // Prune menu bar items for accounts that no longer exist
            pruneMenuBarItems()
            
            let shouldRefreshQuotas: Bool
            if let lastRefresh = lastQuotaRefresh {
                shouldRefreshQuotas = Date().timeIntervalSince(lastRefresh) >= quotaRefreshInterval
            } else {
                shouldRefreshQuotas = true
            }
            
            if shouldRefreshQuotas && !isLoadingQuotas {
                Task {
                    await refreshAllQuotas()
                }
            }
        } catch is CancellationError {
            // Task was cancelled (e.g. stopProxy / app teardown) — not a user-visible error.
            // Explicitly catching CancellationError avoids a race between Task.isCancelled
            // being observed before the flag is set, which could surface a spurious error message.
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func manualRefresh() async {
        if modeManager.isMonitorMode {
            await refreshQuotasDirectly()
        } else if proxyManager.proxyStatus.running {
            await refreshData()
        } else {
            await refreshQuotasUnified()
        }
        lastQuotaRefreshTime = Date()
    }
    
    func refreshAllQuotas() async {
        guard !isLoadingQuotas else { return }

        isLoadingQuotas = true
        lastQuotaRefresh = Date()

        // In remote mode, skip local filesystem fetchers — only show data from the remote proxy
        // (auth files, usage stats, API keys are already fetched by refreshData())
        if !modeManager.isRemoteProxyMode {
            // Note: Cursor and Trae removed from auto-refresh (issue #29)
            // User must use "Scan for IDEs" to detect these
            async let antigravity: () = refreshAntigravityQuotasInternal()
            async let openai: () = refreshOpenAIQuotasInternal()
            async let copilot: () = refreshCopilotQuotasInternal()
            async let claudeCode: () = refreshClaudeCodeQuotasInternal()
            async let glm: () = refreshGlmQuotasInternal()
            async let warp: () = refreshWarpQuotasInternal()
            async let kiro: () = refreshKiroQuotasInternal()

            _ = await (antigravity, openai, copilot, claudeCode, glm, warp, kiro)
        }

        checkQuotaNotifications()
        pruneMenuBarItems()
        autoSelectMenuBarItems()

        isLoadingQuotas = false
        notifyQuotaDataChanged()
    }

    /// Unified quota refresh - works in both Full Mode and Quota-Only Mode
    /// In Full Mode: uses direct fetchers (works without proxy)
    /// In Quota-Only Mode: uses direct fetchers + CLI fetchers
    /// In Remote Mode: skips local fetchers (data comes from remote proxy)
    /// Note: Cursor and Trae require explicit user scan (issue #29)
    func refreshQuotasUnified() async {
        guard !isLoadingQuotas else { return }
        guard !modeManager.isRemoteProxyMode else { return }

        isLoadingQuotas = true
        lastQuotaRefreshTime = Date()
        lastQuotaRefresh = Date()

        // Refresh direct fetchers (these don't need proxy)
        // Note: Cursor and Trae removed - require explicit scan (issue #29)
        async let antigravity: () = refreshAntigravityQuotasInternal()
        async let openai: () = refreshOpenAIQuotasInternal()
        async let copilot: () = refreshCopilotQuotasInternal()
        async let claudeCode: () = refreshClaudeCodeQuotasInternal()
        async let glm: () = refreshGlmQuotasInternal()
        async let warp: () = refreshWarpQuotasInternal()
        async let kiro: () = refreshKiroQuotasInternal()

        // In Quota-Only Mode, also include CLI fetchers
        if modeManager.isMonitorMode {
            async let codexCLI: () = refreshCodexCLIQuotasInternal()
            async let geminiCLI: () = refreshGeminiCLIQuotasInternal()
            _ = await (antigravity, openai, copilot, claudeCode, glm, warp, kiro, codexCLI, geminiCLI)
        } else {
            _ = await (antigravity, openai, copilot, claudeCode, glm, warp, kiro)
        }

        checkQuotaNotifications()
        pruneMenuBarItems()
        autoSelectMenuBarItems()

        isLoadingQuotas = false
        notifyQuotaDataChanged()
    }

    func refreshAntigravityQuotasInternal() async {
        // Fetch both quotas and subscriptions in one call (avoids duplicate API calls)
        let (quotas, subscriptions) = await antigravityFetcher.fetchAllAntigravityData(authDir: proxyManager.authDir)
        
        providerQuotas[.antigravity] = quotas
        
        // Merge instead of replace to preserve data if API fails
        var providerInfos = subscriptionInfos[.antigravity] ?? [:]
        for (email, info) in subscriptions {
            providerInfos[email] = info
        }
        subscriptionInfos[.antigravity] = providerInfos
        
        // Detect active account in IDE (reads email directly from database)
        await antigravitySwitcher.detectActiveAccount()
    }
    
    /// Refresh Antigravity quotas without re-detecting active account
    /// Used after switching accounts (active account already set by switch operation)
    func refreshAntigravityQuotasWithoutDetect() async {
        let (quotas, subscriptions) = await antigravityFetcher.fetchAllAntigravityData()
        
        providerQuotas[.antigravity] = quotas
        
        var providerInfos = subscriptionInfos[.antigravity] ?? [:]
        for (email, info) in subscriptions {
            providerInfos[email] = info
        }
        subscriptionInfos[.antigravity] = providerInfos
        // Note: Don't call detectActiveAccount() here - already set by switch operation
    }
    
    // MARK: - Antigravity Account Switching
    
    /// Check if an Antigravity account is currently active in the IDE
    /// Simply compares email from database with the given email
    func isAntigravityAccountActive(email: String) -> Bool {
        return antigravitySwitcher.isActiveAccount(email: email)
    }
    
    /// Switch Antigravity account in the IDE
    func switchAntigravityAccount(email: String) async {
        await antigravitySwitcher.executeSwitchForEmail(email)

        // Refresh to update active account
        if case .success = antigravitySwitcher.switchState {
            await refreshAntigravityQuotasWithoutDetect()
        }
    }
    
    /// Begin the switch confirmation flow
    func beginAntigravitySwitch(accountId: String, email: String) {
        antigravitySwitcher.beginSwitch(accountId: accountId, accountEmail: email)
    }
    
    /// Cancel the switch operation
    func cancelAntigravitySwitch() {
        antigravitySwitcher.cancelSwitch()
    }
    
    /// Dismiss switch result
    func dismissAntigravitySwitchResult() {
        antigravitySwitcher.dismissResult()
    }
    
    func refreshOpenAIQuotasInternal() async {
        // Use proxyManager's authDir (which points to ~/.cli-proxy-api)
        let report = await openAIFetcher.fetchAllCodexQuotas(authDir: proxyManager.authDir)
        providerQuotas[.codex] = report.quotas
        if report.failures.isEmpty {
            providerQuotaFailures.removeValue(forKey: .codex)
        } else {
            providerQuotaFailures[.codex] = report.failures
        }
    }
    
    func refreshCopilotQuotasInternal() async {
        let quotas = await copilotFetcher.fetchAllCopilotQuotas(authDir: proxyManager.authDir)
        providerQuotas[.copilot] = quotas
    }
    
    func refreshQuotaForProvider(_ provider: AIProvider) async {
        switch provider {
        case .antigravity:
            await refreshAntigravityQuotasInternal()
        case .codex:
            await refreshOpenAIQuotasInternal()
            await refreshCodexCLIQuotasFallback(allowAllModes: true)
        case .copilot:
            await refreshCopilotQuotasInternal()
        case .claude:
            await refreshClaudeCodeQuotasInternal()
        case .cursor:
            await refreshCursorQuotasInternal()
        case .gemini:
            await refreshGeminiCLIQuotasInternal()
        case .trae:
            await refreshTraeQuotasInternal()
        case .glm:
            await refreshGlmQuotasInternal()
        case .warp:
            await refreshWarpQuotasInternal()
        case .kiro:
            await refreshKiroQuotasInternal()
        default:
            break
        }

        // Prune menu bar items after refresh to remove deleted accounts
        pruneMenuBarItems()

        notifyQuotaDataChanged()
    }

    /// Refresh all auto-detected providers (those that don't support manual auth)
    func refreshAutoDetectedProviders() async {
        let autoDetectedProviders = AIProvider.allCases.filter { !$0.supportsManualAuth }
        
        for provider in autoDetectedProviders {
            await refreshQuotaForProvider(provider)
        }
    }
    
    func startOAuth(for provider: AIProvider, projectId: String? = nil, authMethod: AuthCommand? = nil) async {
        // GitHub Copilot uses Device Code Flow via CLI binary, not Management API
        if provider == .copilot {
            await startCopilotAuth()
            return
        }
        
        // Kiro uses CLI-based auth with multiple options
        if provider == .kiro {
            await startKiroAuth(method: authMethod ?? .kiroGoogleLogin)
            return
        }

        guard let client = apiClient else {
            oauthState = OAuthState(provider: provider, status: .error, error: "Proxy not running. Please start the proxy first.")
            return
        }

        oauthState = OAuthState(provider: provider, status: .waiting)
        
        do {
            // OAuth browser callbacks for Codex/Gemini/Antigravity/Claude rely on
            // callback forwarders in CLIProxyAPI (`is_webui=true`).
            // Using non-web UI flow in Quotio local mode can leave callback ports
            // without listeners (e.g. localhost:51121/oauth-callback), causing
            // ERR_CONNECTION_REFUSED in browser after consent.
            let useWebUIFlow = true
            let response = try await client.getOAuthURL(
                for: provider,
                projectId: projectId,
                isWebUI: useWebUIFlow
            )
            
            guard response.status == "ok", let urlString = response.url, let state = response.state else {
                oauthState = OAuthState(provider: provider, status: .error, error: response.error)
                return
            }
            
            // Auto-open browser AND store URL for copy/open buttons
            if let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
            
            oauthState = OAuthState(provider: provider, status: .polling, state: state, authURL: urlString)
            await pollOAuthStatus(state: state, provider: provider)
            
        } catch {
            oauthState = OAuthState(provider: provider, status: .error, error: error.localizedDescription)
        }
    }
    
    /// Start GitHub Copilot authentication using Device Code Flow
    func startCopilotAuth() async {
        oauthState = OAuthState(provider: .copilot, status: .waiting)
        
        let result = await proxyManager.runAuthCommand(.copilotLogin)
        
        if result.success {
            if let deviceCode = result.deviceCode {
                oauthState = OAuthState(provider: .copilot, status: .polling, state: deviceCode, error: result.message)
            } else {
                oauthState = OAuthState(provider: .copilot, status: .polling, error: result.message)
            }
            
            await pollCopilotAuthCompletion()
        } else {
            oauthState = OAuthState(provider: .copilot, status: .error, error: result.message)
        }
    }
    
    func startKiroAuth(method: AuthCommand) async {
        oauthState = OAuthState(provider: .kiro, status: .waiting)
        
        let result = await proxyManager.runAuthCommand(method)
        
        if result.success {
            // Check if it's an import - simply wait and refresh, don't poll for new files (files might already exist)
            if method == .kiroImport {
                oauthState = OAuthState(provider: .kiro, status: .polling, error: "Importing quotas...")
                
                // Allow some time for file operations
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await refreshData()
                
                // For import, we assume success if the command succeeded
                oauthState = OAuthState(provider: .kiro, status: .success)
                return
            }
            
            // For other methods (login), poll for new auth files
            if let deviceCode = result.deviceCode {
                oauthState = OAuthState(provider: .kiro, status: .polling, state: deviceCode, error: result.message)
            } else {
                oauthState = OAuthState(provider: .kiro, status: .polling, error: result.message)
            }
            
            await pollKiroAuthCompletion()
        } else {
            oauthState = OAuthState(provider: .kiro, status: .error, error: result.message)
        }
    }
    
    /// Poll for Copilot auth completion by monitoring auth files
    func pollCopilotAuthCompletion() async {
        let startFileCount = authFiles.filter { $0.provider == "github-copilot" || $0.provider == "copilot" }.count
        
        for _ in 0..<90 {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            
            await refreshData()
            
            let currentFileCount = authFiles.filter { $0.provider == "github-copilot" || $0.provider == "copilot" }.count
            if currentFileCount > startFileCount {
                oauthState = OAuthState(provider: .copilot, status: .success)
                return
            }
        }
        
        oauthState = OAuthState(provider: .copilot, status: .error, error: "Authentication timeout")
    }
    
    func pollKiroAuthCompletion() async {
        let startFileCount = authFiles.filter { $0.provider == "kiro" }.count
        
        for _ in 0..<90 {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            
            await refreshData()
            
            let currentFileCount = authFiles.filter { $0.provider == "kiro" }.count
            if currentFileCount > startFileCount {
                oauthState = OAuthState(provider: .kiro, status: .success)
                return
            }
        }
        
        oauthState = OAuthState(provider: .kiro, status: .error, error: "Authentication timeout")
    }
    
    func pollOAuthStatus(state: String, provider: AIProvider) async {
        guard let client = apiClient else { return }
        
        for _ in 0..<60 {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            
            do {
                let response = try await client.pollOAuthStatus(state: state)
                
                switch response.status {
                case "ok":
                    oauthState = OAuthState(provider: provider, status: .success)
                    await refreshData()
                    return
                case "error":
                    oauthState = OAuthState(provider: provider, status: .error, error: response.error)
                    return
                default:
                    continue
                }
            } catch {
                continue
            }
        }
        
        oauthState = OAuthState(provider: provider, status: .error, error: "OAuth timeout")
    }
    
    func cancelOAuth() {
        oauthState = nil
    }
    
    func deleteAuthFile(_ file: AuthFile) async {
        guard let client = apiClient else { return }

        do {
            try await client.deleteAuthFile(name: file.name)

            let accountKey = file.quotaLookupKey.isEmpty ? file.name : file.quotaLookupKey

            // Remove quota data for this account
            if let provider = file.providerType {
                providerQuotas[provider]?.removeValue(forKey: accountKey)

                // Also try with email if different
                if let email = file.email, email != accountKey {
                    providerQuotas[provider]?.removeValue(forKey: email)
                }
            }

            // Clear persisted disabled flags for this account
            var disabledSet = loadDisabledAuthFiles()
            disabledSet.remove(file.name)
            disabledSet.remove(accountKey)
            if let email = file.email, email != accountKey {
                disabledSet.remove(email)
            }
            saveDisabledAuthFiles(disabledSet)

            // Prune menu bar items that no longer exist
            pruneMenuBarItems()

            await refreshData()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleAuthFileDisabled(_ file: AuthFile) async {
        guard let client = apiClient else {
            Log.error("toggleAuthFileDisabled: No API client available")
            return
        }

        let newDisabled = !file.disabled

        do {
            Log.debug("toggleAuthFileDisabled: Setting \(file.name) disabled=\(newDisabled)")
            try await client.setAuthFileDisabled(name: file.name, disabled: newDisabled)

            // Update local persistence
            var disabledSet = loadDisabledAuthFiles()
            if newDisabled {
                disabledSet.insert(file.name)
            } else {
                disabledSet.remove(file.name)
            }
            saveDisabledAuthFiles(disabledSet)

            Log.debug("toggleAuthFileDisabled: Success, refreshing data")
            await refreshData()
        } catch {
            Log.error("toggleAuthFileDisabled: Failed - \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    /// Remove menu bar items that no longer have valid quota data
    func pruneMenuBarItems() {
        var validItems: [MenuBarQuotaItem] = []
        var seen = Set<String>()
        
        // Collect valid items from current quota data
        for (provider, accountQuotas) in providerQuotas {
            for (accountKey, _) in accountQuotas {
                let item = MenuBarQuotaItem(provider: provider.rawValue, accountKey: accountKey)
                if !seen.contains(item.id) {
                    seen.insert(item.id)
                    validItems.append(item)
                }
            }
        }
        
        // Add items from auth files
        for file in authFiles {
            guard let provider = file.providerType else { continue }
            let item = MenuBarQuotaItem(provider: provider.rawValue, accountKey: file.menuBarAccountKey)
            if !seen.contains(item.id) {
                seen.insert(item.id)
                validItems.append(item)
            }
        }
        
        // Add items from direct auth files (quota-only mode)
        for file in directAuthFiles {
            let item = MenuBarQuotaItem(provider: file.provider.rawValue, accountKey: file.menuBarAccountKey)
            if !seen.contains(item.id) {
                seen.insert(item.id)
                validItems.append(item)
            }
        }
        
        menuBarSettings.pruneInvalidItems(validItems: validItems)
    }

    func importVertexServiceAccount(url: URL) async {
        guard let client = apiClient else {
            errorMessage = "Proxy not running"
            return
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            guard url.startAccessingSecurityScopedResource() else {
                throw NSError(domain: "Quotio", code: 403, userInfo: [NSLocalizedDescriptionKey: "Permission denied"])
            }
            let data = try Data(contentsOf: url)
            url.stopAccessingSecurityScopedResource()
            
            try await client.uploadVertexServiceAccount(data: data)
            await refreshData()
            errorMessage = nil
        } catch {
            errorMessage = "Import failed: \(error.localizedDescription)"
        }
    }
    
    func fetchAPIKeys() async {
        guard let client = apiClient else { return }
        
        do {
            apiKeys = try await client.fetchAPIKeys()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func addAPIKey(_ key: String) async {
        guard let client = apiClient else { return }
        guard !key.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        
        do {
            try await client.addAPIKey(key)
            await fetchAPIKeys()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func updateAPIKey(old: String, new: String) async {
        guard let client = apiClient else { return }
        guard !new.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        
        do {
            try await client.updateAPIKey(old: old, new: new)
            await fetchAPIKeys()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func deleteAPIKey(_ key: String) async {
        guard let client = apiClient else { return }
        
        do {
            try await client.deleteAPIKey(value: key)
            await fetchAPIKeys()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
}
