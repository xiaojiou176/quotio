import Foundation
import SwiftUI
import AppKit
import Observation

@MainActor
extension QuotaViewModel {
    // MARK: - Notification Helpers
    
    func checkAccountStatusChanges() {
        for file in authFiles {
            let accountKey = "\(file.provider)_\(file.email ?? file.name)"
            let previousStatus = lastKnownAccountStatuses[accountKey]
            
            if file.status == "cooling" && previousStatus != "cooling" {
                notificationManager.notifyAccountCooling(
                    provider: file.providerType?.displayName ?? file.provider,
                    account: file.email ?? file.name
                )
            } else if file.status == "ready" && previousStatus == "cooling" {
                notificationManager.clearCoolingNotification(
                    provider: file.provider,
                    account: file.email ?? file.name
                )
            }
            
            lastKnownAccountStatuses[accountKey] = file.status
        }
    }
    
    func checkQuotaNotifications() {
        for (provider, accountQuotas) in providerQuotas {
            for (account, quotaData) in accountQuotas {
                guard !quotaData.models.isEmpty else { continue }
                
                // Filter out models with unknown percentage (-1 means unavailable/unknown)
                let validPercentages = quotaData.models.map(\.percentage).filter { $0 >= 0 }
                guard !validPercentages.isEmpty else { continue }
                
                let minRemainingPercent = validPercentages.min() ?? 100.0
                
                if minRemainingPercent <= notificationManager.quotaAlertThreshold {
                    notificationManager.notifyQuotaLow(
                        provider: provider.displayName,
                        account: account,
                        remainingPercent: minRemainingPercent
                    )
                } else {
                    notificationManager.clearQuotaNotification(
                        provider: provider.rawValue,
                        account: account
                    )
                }
            }
        }
    }
    
    // MARK: - IDE Scan with Consent
    
    /// Scan IDEs with explicit user consent - addresses issue #29
    /// Only scans what the user has opted into
    func scanIDEsWithConsent(options: IDEScanOptions) async {
        ideScanSettings.setScanningState(true)
        
        var cursorFound = false
        var cursorEmail: String?
        var traeFound = false
        var traeEmail: String?
        var cliToolsFound: [String] = []
        
        // Scan Cursor if opted in
        if options.scanCursor {
            let quotas = await cursorFetcher.fetchAsProviderQuota()
            if !quotas.isEmpty {
                cursorFound = true
                cursorEmail = quotas.keys.first
                providerQuotas[.cursor] = quotas
            } else {
                // Clear stale data when not found (consistent with refreshCursorQuotasInternal)
                providerQuotas.removeValue(forKey: .cursor)
            }
        }
        
        // Scan Trae if opted in
        if options.scanTrae {
            let quotas = await traeFetcher.fetchAsProviderQuota()
            if !quotas.isEmpty {
                traeFound = true
                traeEmail = quotas.keys.first
                providerQuotas[.trae] = quotas
            } else {
                // Clear stale data when not found (consistent with refreshTraeQuotasInternal)
                providerQuotas.removeValue(forKey: .trae)
            }
        }
        
        // Scan CLI tools if opted in
        if options.scanCLITools {
            let cliNames = ["claude", "codex", "gemini", "gh"]
            for name in cliNames {
                if await CLIExecutor.shared.isCLIInstalled(name: name) {
                    cliToolsFound.append(name)
                }
            }
        }
        
        let result = IDEScanResult(
            cursorFound: cursorFound,
            cursorEmail: cursorEmail,
            traeFound: traeFound,
            traeEmail: traeEmail,
            cliToolsFound: cliToolsFound,
            timestamp: Date()
        )
        
        ideScanSettings.updateScanResult(result)
        ideScanSettings.setScanningState(false)
        
        // Persist IDE quota data for Cursor and Trae
        savePersistedIDEQuotas()

        // Update menu bar items
        pruneMenuBarItems()
        autoSelectMenuBarItems()

        notifyQuotaDataChanged()
    }

    // MARK: - Hybrid Namespace Model Set Persistence

    /// Upsert a Base URL namespace -> model set mapping for Hybrid control plane.
    func upsertBaseURLNamespaceModelSet(namespace: String, baseURL: String, modelSet: [String], notes: String? = nil) {
        let item = BaseURLNamespaceModelSet(
            namespace: namespace,
            baseURL: baseURL,
            modelSet: modelSet,
            notes: notes
        )
        
        guard !item.namespace.isEmpty else { return }
        
        if let existingIndex = baseURLNamespaceModelSets.firstIndex(where: { $0.namespace == item.namespace }) {
            baseURLNamespaceModelSets[existingIndex] = item
        } else {
            baseURLNamespaceModelSets.append(item)
            baseURLNamespaceModelSets.sort { $0.namespace.localizedCaseInsensitiveCompare($1.namespace) == .orderedAscending }
        }
        
        saveBaseURLNamespaceModelSets()
    }

    /// Remove a namespace mapping from Hybrid control plane persistence.
    func removeBaseURLNamespaceModelSet(namespace: String) {
        let normalizedNamespace = namespace.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedNamespace.isEmpty else { return }

        let originalCount = baseURLNamespaceModelSets.count
        baseURLNamespaceModelSets.removeAll { $0.namespace == normalizedNamespace }
        guard baseURLNamespaceModelSets.count != originalCount else { return }

        saveBaseURLNamespaceModelSets()
    }
    
    /// Reset Hybrid namespace mapping to deterministic defaults for local + remote proxy modes.
    func resetBaseURLNamespaceModelSetsToDefaults() {
        baseURLNamespaceModelSets = defaultBaseURLNamespaceModelSets()
        saveBaseURLNamespaceModelSets()
    }
    
    /// Seed Hybrid namespace mapping with current runtime/shadow endpoints.
    func seedBaseURLNamespaceModelSetsForCurrentTopology() {
        let runtimeBaseURL = "http://localhost:" + String(proxyManager.port) + "/v1"
        let shadowBaseURL = modeManager.remoteConfig?.endpointURL ?? "https://remote-host.example/v1"
        
        upsertBaseURLNamespaceModelSet(
            namespace: "equilibrium.runtime",
            baseURL: runtimeBaseURL,
            modelSet: ["gpt-5.3-codex", "claude-opus-4.5", "gemini-2.5-pro"],
            notes: "Hybrid control plane: seeded from current runtime endpoint"
        )
        
        upsertBaseURLNamespaceModelSet(
            namespace: "equilibrium.shadow",
            baseURL: shadowBaseURL,
            modelSet: ["gpt-5.3-codex", "claude-sonnet-4.5"],
            notes: "Hybrid control plane: seeded from current shadow endpoint"
        )
    }

    /// Sync current local Hybrid namespace mappings to Management API model-visibility config.
    ///
    /// Local cache remains source-of-truth fallback. Callers should keep local data on sync failure.
    func syncBaseURLNamespaceModelSetsToManagementAPI() async throws {
        guard let client = apiClient else {
            throw APIError.connectionError("Management API unavailable")
        }

        let payload = buildModelVisibilityPayloadFromLocalMappings()
        try await client.putModelVisibility(payload)
    }

    func buildModelVisibilityPayloadFromLocalMappings() -> ModelVisibilityConfigPayload {
        var namespaces: [String: [String]] = [:]
        var hostNamespaces: [String: String] = [:]

        for mapping in baseURLNamespaceModelSets {
            let namespace = mapping.namespace.trimmingCharacters(in: .whitespacesAndNewlines)
            let baseURL = mapping.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !namespace.isEmpty, !baseURL.isEmpty else { continue }

            namespaces[namespace] = mapping.modelSet
            hostNamespaces[baseURL] = namespace
        }

        return ModelVisibilityConfigPayload(
            enabled: !namespaces.isEmpty,
            namespaces: namespaces,
            hostNamespaces: hostNamespaces
        )
    }
    
    func loadBaseURLNamespaceModelSets() {
        guard let data = UserDefaults.standard.data(forKey: Self.baseURLNamespaceModelSetsKey) else {
            resetBaseURLNamespaceModelSetsToDefaults()
            return
        }
        
        do {
            let decoded = try JSONDecoder().decode([BaseURLNamespaceModelSet].self, from: data)
            if decoded.isEmpty {
                resetBaseURLNamespaceModelSetsToDefaults()
            } else {
                baseURLNamespaceModelSets = decoded.sorted {
                    $0.namespace.localizedCaseInsensitiveCompare($1.namespace) == .orderedAscending
                }
            }
        } catch {
            Log.error("Failed to load Base URL namespace model sets: \(error)")
            UserDefaults.standard.removeObject(forKey: Self.baseURLNamespaceModelSetsKey)
            resetBaseURLNamespaceModelSetsToDefaults()
        }
    }
    
    func saveBaseURLNamespaceModelSets() {
        do {
            let encoded = try JSONEncoder().encode(baseURLNamespaceModelSets)
            UserDefaults.standard.set(encoded, forKey: Self.baseURLNamespaceModelSetsKey)
        } catch {
            Log.error("Failed to save Base URL namespace model sets: \(error)")
        }
    }
    
    func defaultBaseURLNamespaceModelSets() -> [BaseURLNamespaceModelSet] {
        let localBaseURL = "http://localhost:" + String(proxyManager.port) + "/v1"
        let remoteBaseURL = modeManager.remoteConfig?.endpointURL ?? "https://remote-host.example/v1"
        
        return [
            BaseURLNamespaceModelSet(
                namespace: "equilibrium.runtime",
                baseURL: localBaseURL,
                modelSet: ["gpt-5.3-codex", "claude-opus-4.5", "gemini-2.5-pro"],
                notes: "Hybrid control plane: default runtime namespace"
            ),
            BaseURLNamespaceModelSet(
                namespace: "equilibrium.shadow",
                baseURL: remoteBaseURL,
                modelSet: ["gpt-5.3-codex", "claude-sonnet-4.5"],
                notes: "Hybrid control plane: default shadow namespace"
            )
        ]
    }

    // MARK: - IDE Quota Persistence
    
    /// Save Cursor and Trae quota data to UserDefaults for persistence across app restarts
    func savePersistedIDEQuotas() {
        var dataToSave: [String: [String: ProviderQuotaData]] = [:]
        
        for provider in Self.ideProvidersToSave {
            if let quotas = providerQuotas[provider], !quotas.isEmpty {
                dataToSave[provider.rawValue] = quotas
            }
        }
        
        if dataToSave.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.ideQuotasKey)
            return
        }
        
        do {
            let encoded = try JSONEncoder().encode(dataToSave)
            UserDefaults.standard.set(encoded, forKey: Self.ideQuotasKey)
        } catch {
            Log.error("Failed to save IDE quotas: \(error)")
        }
    }
    
    /// Load persisted Cursor and Trae quota data from UserDefaults
    func loadPersistedIDEQuotas() {
        guard let data = UserDefaults.standard.data(forKey: Self.ideQuotasKey) else { return }
        
        do {
            let decoded = try JSONDecoder().decode([String: [String: ProviderQuotaData]].self, from: data)
            
            for (providerRaw, quotas) in decoded {
                if let provider = AIProvider(rawValue: providerRaw),
                   Self.ideProvidersToSave.contains(provider) {
                    providerQuotas[provider] = quotas
                }
            }
        } catch {
            Log.error("Failed to load IDE quotas: \(error)")
            // Clear corrupted data
            UserDefaults.standard.removeObject(forKey: Self.ideQuotasKey)
        }
    }
    
    // MARK: - Menu Bar Quota Items
    
    var menuBarSettings: MenuBarSettingsManager {
        MenuBarSettingsManager.shared
    }
    
    var menuBarQuotaItems: [MenuBarQuotaDisplayItem] {
        let settings = menuBarSettings
        guard settings.showQuotaInMenuBar else { return [] }
        
        var items: [MenuBarQuotaDisplayItem] = []
        
        for selectedItem in settings.selectedItems {
            guard let provider = selectedItem.aiProvider else { continue }
            
            let shortAccount = shortenAccountKey(selectedItem.accountKey)
            
            if let accountQuotas = providerQuotas[provider],
               let quotaData = accountQuotas[selectedItem.accountKey],
               !quotaData.models.isEmpty {
                // Filter out -1 (unknown) percentages when calculating lowest
                let validPercentages = quotaData.models.map(\.percentage).filter { $0 >= 0 }
                let lowestPercent = validPercentages.min() ?? (quotaData.models.first?.percentage ?? -1)
                items.append(MenuBarQuotaDisplayItem(
                    id: selectedItem.id,
                    providerSymbol: provider.menuBarSymbol,
                    accountShort: shortAccount,
                    percentage: lowestPercent,
                    provider: provider
                ))
            } else {
                items.append(MenuBarQuotaDisplayItem(
                    id: selectedItem.id,
                    providerSymbol: provider.menuBarSymbol,
                    accountShort: shortAccount,
                    percentage: -1,
                    provider: provider
                ))
            }
        }
        
        return items
    }
    
    func shortenAccountKey(_ key: String) -> String {
        if let atIndex = key.firstIndex(of: "@") {
            let user = String(key[..<atIndex].prefix(4))
            let domainStart = key.index(after: atIndex)
            let domain = String(key[domainStart...].prefix(1))
            return "\(user)@\(domain)"
        }
        return String(key.prefix(6))
    }
}
