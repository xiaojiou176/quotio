//
//  SettingsUnifiedProxySettingsPersistence.swift
//  Quotio
//

import SwiftUI

extension UnifiedProxySettingsSection {
    func loadConfig() async {
        isLoading = true
        isLoadingConfig = true
        loadError = nil
        
        guard let apiClient = viewModel.apiClient else {
            loadError = modeManager.isLocalProxyMode
                ? "settings.proxy.startToConfigureAdvanced".localized()
                : "settings.remote.noConnection".localized()
            isLoading = false
            isLoadingConfig = false
            return
        }
        
        do {
            async let configTask = apiClient.fetchConfig()
            async let routingTask = apiClient.getRoutingStrategy()
            
            let (config, fetchedStrategy) = try await (configTask, routingTask)
            
            proxyURL = config.proxyURL ?? ""
            routingStrategy = fetchedStrategy
            requestRetry = config.requestRetry ?? 3
            maxRetryInterval = config.maxRetryInterval ?? 30
            loggingToFile = config.loggingToFile ?? true
            requestLog = config.requestLog ?? false
            debugMode = config.debug ?? false
            switchProject = config.quotaExceeded?.switchProject ?? true
            switchPreviewModel = config.quotaExceeded?.switchPreviewModel ?? true
            lastProxyURLValue = proxyURL
            lastRoutingStrategyValue = routingStrategy
            lastRequestRetryValue = requestRetry
            lastMaxRetryIntervalValue = maxRetryInterval
            lastLoggingToFileValue = loggingToFile
            lastRequestLogValue = requestLog
            lastDebugModeValue = debugMode
            lastSwitchProjectValue = switchProject
            lastSwitchPreviewModelValue = switchPreviewModel
            proxyURLValidation = ProxyURLValidator.validate(proxyURL)
            isLoading = false
            
            try? await Task.sleep(for: .milliseconds(100))
            isLoadingConfig = false
        } catch {
            loadError = error.localizedDescription
            isLoading = false
            isLoadingConfig = false
        }
    }
    
    /// Persists the upstream proxy URL to both UserDefaults and the running proxy instance.
    ///
    /// The URL is first saved to UserDefaults so it survives app restarts (used by
    /// `CLIProxyManager.syncProxyURLInConfig()` during proxy startup), then sent to the
    /// proxy API to take effect immediately. Only valid or empty URLs are saved.
    func saveProxyURL() async {
        let previousValue = lastProxyURLValue
        let sanitized = proxyURLValidation == .valid ? ProxyURLValidator.sanitize(proxyURL) : proxyURL

        if proxyURL.isEmpty {
            UserDefaults.standard.set("", forKey: "proxyURL")
        } else if proxyURLValidation == .valid {
            UserDefaults.standard.set(sanitized, forKey: "proxyURL")
        }

        guard let apiClient = viewModel.apiClient else {
            proxyURL = previousValue
            proxyURLValidation = ProxyURLValidator.validate(previousValue)
            showFeedback("settings.remote.noConnection".localized(fallback: "当前未连接远端，无法保存设置。"), isError: true)
            return
        }
        do {
            if proxyURL.isEmpty {
                try await apiClient.deleteProxyURL()
            } else if proxyURLValidation == .valid {
                try await apiClient.setProxyURL(sanitized)
            }
            settingsAudit.recordChange(
                key: "proxy_url",
                oldValue: previousValue,
                newValue: proxyURL.isEmpty ? "" : sanitized,
                source: "settings.unified_proxy"
            )
            lastProxyURLValue = proxyURL.isEmpty ? "" : sanitized
        } catch {
            proxyURL = previousValue
            proxyURLValidation = ProxyURLValidator.validate(previousValue)
            UserDefaults.standard.set(previousValue, forKey: "proxyURL")
            showFeedback(
                "settings.feedback.proxyURLSaveFailed".localized(fallback: "上游代理地址保存失败") + ": " + error.localizedDescription,
                isError: true
            )
            Log.error("[RemoteSettings] Failed to save proxy URL: \(error)")
        }
    }
    
    func saveRoutingStrategy(_ strategy: String) async {
        guard let apiClient = viewModel.apiClient else {
            routingStrategy = lastRoutingStrategyValue
            showFeedback("settings.remote.noConnection".localized(fallback: "当前未连接远端，无法保存设置。"), isError: true)
            return
        }
        do {
            try await apiClient.setRoutingStrategy(strategy)
            settingsAudit.recordChange(
                key: "routing_strategy",
                oldValue: lastRoutingStrategyValue,
                newValue: strategy,
                source: "settings.unified_proxy"
            )
            lastRoutingStrategyValue = strategy
        } catch {
            routingStrategy = lastRoutingStrategyValue
            showFeedback(
                "settings.feedback.routingStrategySaveFailed".localized(fallback: "路由策略保存失败") + ": " + error.localizedDescription,
                isError: true
            )
            Log.error("[RemoteSettings] Failed to save routing strategy: \(error)")
        }
    }
    
    func saveSwitchProject(_ enabled: Bool) async {
        guard let apiClient = viewModel.apiClient else {
            switchProject = lastSwitchProjectValue
            showFeedback("settings.remote.noConnection".localized(fallback: "当前未连接远端，无法保存设置。"), isError: true)
            return
        }
        do {
            try await apiClient.setQuotaExceededSwitchProject(enabled)
            settingsAudit.recordChange(
                key: "quota_exceeded.switch_project",
                oldValue: String(lastSwitchProjectValue),
                newValue: String(enabled),
                source: "settings.unified_proxy"
            )
            lastSwitchProjectValue = enabled
        } catch {
            switchProject = lastSwitchProjectValue
            showFeedback(
                "settings.feedback.switchProjectSaveFailed".localized(fallback: "自动切换账号设置保存失败") + ": " + error.localizedDescription,
                isError: true
            )
            Log.error("[RemoteSettings] Failed to save switch project: \(error)")
        }
    }
    
    func saveSwitchPreviewModel(_ enabled: Bool) async {
        guard let apiClient = viewModel.apiClient else {
            switchPreviewModel = lastSwitchPreviewModelValue
            showFeedback("settings.remote.noConnection".localized(fallback: "当前未连接远端，无法保存设置。"), isError: true)
            return
        }
        do {
            try await apiClient.setQuotaExceededSwitchPreviewModel(enabled)
            settingsAudit.recordChange(
                key: "quota_exceeded.switch_preview_model",
                oldValue: String(lastSwitchPreviewModelValue),
                newValue: String(enabled),
                source: "settings.unified_proxy"
            )
            lastSwitchPreviewModelValue = enabled
        } catch {
            switchPreviewModel = lastSwitchPreviewModelValue
            showFeedback(
                "settings.feedback.switchPreviewSaveFailed".localized(fallback: "自动切换预览模型设置保存失败") + ": " + error.localizedDescription,
                isError: true
            )
            Log.error("[RemoteSettings] Failed to save switch preview model: \(error)")
        }
    }
    
    func saveRequestRetry(_ count: Int) async {
        guard let apiClient = viewModel.apiClient else {
            requestRetry = lastRequestRetryValue
            showFeedback("settings.remote.noConnection".localized(fallback: "当前未连接远端，无法保存设置。"), isError: true)
            return
        }
        do {
            try await apiClient.setRequestRetry(count)
            settingsAudit.recordChange(
                key: "request_retry",
                oldValue: String(lastRequestRetryValue),
                newValue: String(count),
                source: "settings.unified_proxy"
            )
            lastRequestRetryValue = count
        } catch {
            requestRetry = lastRequestRetryValue
            showFeedback(
                "settings.feedback.requestRetrySaveFailed".localized(fallback: "重试次数保存失败") + ": " + error.localizedDescription,
                isError: true
            )
            Log.error("[RemoteSettings] Failed to save request retry: \(error)")
        }
    }
    
    func saveMaxRetryInterval(_ seconds: Int) async {
        guard let apiClient = viewModel.apiClient else {
            maxRetryInterval = lastMaxRetryIntervalValue
            showFeedback("settings.remote.noConnection".localized(fallback: "当前未连接远端，无法保存设置。"), isError: true)
            return
        }
        do {
            try await apiClient.setMaxRetryInterval(seconds)
            settingsAudit.recordChange(
                key: "max_retry_interval",
                oldValue: String(lastMaxRetryIntervalValue),
                newValue: String(seconds),
                source: "settings.unified_proxy"
            )
            lastMaxRetryIntervalValue = seconds
        } catch {
            maxRetryInterval = lastMaxRetryIntervalValue
            showFeedback(
                "settings.feedback.maxRetryIntervalSaveFailed".localized(fallback: "最大重试间隔保存失败") + ": " + error.localizedDescription,
                isError: true
            )
            Log.error("[RemoteSettings] Failed to save max retry interval: \(error)")
        }
    }
    
    func saveLoggingToFile(_ enabled: Bool) async {
        guard let apiClient = viewModel.apiClient else {
            loggingToFile = lastLoggingToFileValue
            showFeedback("settings.remote.noConnection".localized(fallback: "当前未连接远端，无法保存设置。"), isError: true)
            return
        }
        do {
            try await apiClient.setLoggingToFile(enabled)
            settingsAudit.recordChange(
                key: "logging_to_file",
                oldValue: String(lastLoggingToFileValue),
                newValue: String(enabled),
                source: "settings.unified_proxy"
            )
            lastLoggingToFileValue = enabled
        } catch {
            loggingToFile = lastLoggingToFileValue
            showFeedback(
                "settings.feedback.loggingToFileSaveFailed".localized(fallback: "日志落盘设置保存失败") + ": " + error.localizedDescription,
                isError: true
            )
            Log.error("[RemoteSettings] Failed to save logging to file: \(error)")
        }
    }
    
    func saveRequestLog(_ enabled: Bool) async {
        guard let apiClient = viewModel.apiClient else {
            requestLog = lastRequestLogValue
            showFeedback("settings.remote.noConnection".localized(fallback: "当前未连接远端，无法保存设置。"), isError: true)
            return
        }
        do {
            try await apiClient.setRequestLog(enabled)
            settingsAudit.recordChange(
                key: "request_log",
                oldValue: String(lastRequestLogValue),
                newValue: String(enabled),
                source: "settings.unified_proxy"
            )
            lastRequestLogValue = enabled
        } catch {
            requestLog = lastRequestLogValue
            showFeedback(
                "settings.feedback.requestLogSaveFailed".localized(fallback: "请求日志设置保存失败") + ": " + error.localizedDescription,
                isError: true
            )
            Log.error("[RemoteSettings] Failed to save request log: \(error)")
        }
    }
    
    func saveDebugMode(_ enabled: Bool) async {
        guard let apiClient = viewModel.apiClient else {
            debugMode = lastDebugModeValue
            showFeedback("settings.remote.noConnection".localized(fallback: "当前未连接远端，无法保存设置。"), isError: true)
            return
        }
        do {
            try await apiClient.setDebug(enabled)
            settingsAudit.recordChange(
                key: "debug_mode",
                oldValue: String(lastDebugModeValue),
                newValue: String(enabled),
                source: "settings.unified_proxy"
            )
            lastDebugModeValue = enabled
        } catch {
            debugMode = lastDebugModeValue
            showFeedback(
                "settings.feedback.debugModeSaveFailed".localized(fallback: "调试模式设置保存失败") + ": " + error.localizedDescription,
                isError: true
            )
            Log.error("[RemoteSettings] Failed to save debug mode: \(error)")
        }
    }

    func presentCreateHybridMappingEditor() {
        guard !isHybridMappingMutating else { return }
        hybridMappingSyncError = nil
        editingHybridMappingNamespace = nil
        hybridMappingNamespace = ""
        hybridMappingBaseURL = ""
        hybridMappingModelSetText = ""
        hybridMappingNotes = ""
        showHybridMappingEditor = true
    }

    func presentEditHybridMappingEditor(_ mapping: BaseURLNamespaceModelSet) {
        guard !isHybridMappingMutating else { return }
        hybridMappingSyncError = nil
        editingHybridMappingNamespace = mapping.namespace
        hybridMappingNamespace = mapping.namespace
        hybridMappingBaseURL = mapping.baseURL
        hybridMappingModelSetText = mapping.modelSet.joined(separator: "\n")
        hybridMappingNotes = mapping.notes ?? ""
        showHybridMappingEditor = true
    }

    func persistHybridMappingEditorDraft() async {
        guard !isHybridMappingSaveInProgress else { return }
        guard hybridMappingDraftValidationMessages.isEmpty else { return }

        let namespace = hybridMappingNamespace.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseURL = hybridMappingBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = hybridMappingNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelSet = parsedHybridMappingModelSet
        guard !namespace.isEmpty, !baseURL.isEmpty, !modelSet.isEmpty else { return }

        await performHybridMappingMutation(.save) {
            if let originalNamespace = editingHybridMappingNamespace, originalNamespace != namespace {
                viewModel.removeBaseURLNamespaceModelSet(namespace: originalNamespace)
            }

            viewModel.upsertBaseURLNamespaceModelSet(
                namespace: namespace,
                baseURL: baseURL,
                modelSet: modelSet,
                notes: notes.isEmpty ? nil : notes
            )
        }

        if hybridMappingSyncError == nil {
            showHybridMappingEditor = false
            resetHybridMappingEditorDraft()
        }
    }

    func performHybridMappingMutation(_ action: HybridMappingAction, localMutation: () -> Void) async {
        guard !isHybridMappingMutating else { return }
        hybridMappingActiveAction = action
        hybridMappingSyncError = nil
        localMutation()
        await syncHybridMappingsToManagementAPI()
        if hybridMappingSyncError == nil {
            settingsAudit.recordChange(
                key: "hybrid_namespace_model_set",
                oldValue: "local_cache",
                newValue: String(describing: action),
                source: "settings.unified_proxy"
            )
        }
        hybridMappingActiveAction = nil
    }

    func retryHybridMappingsSync() async {
        await performHybridMappingMutation(.retrySync) {}
    }

    func syncHybridMappingsToManagementAPI() async {
        if isHybridMappingSyncing {
            return
        }
        isHybridMappingSyncing = true
        defer { isHybridMappingSyncing = false }
        do {
            try await viewModel.syncBaseURLNamespaceModelSetsToManagementAPI()
            hybridMappingSyncError = nil
            hybridMappingLastSyncedAt = Date()
        } catch {
            hybridMappingSyncError = error.localizedDescription
            Log.error("[RemoteSettings] Failed to sync model-visibility; local cache fallback kept: \(error)")
        }
    }

    func resetHybridMappingEditorDraft() {
        editingHybridMappingNamespace = nil
        hybridMappingNamespace = ""
        hybridMappingBaseURL = ""
        hybridMappingModelSetText = ""
        hybridMappingNotes = ""
    }

    func parseModelSetInput(_ input: String) -> [String] {
        Array(
            Set(
                input
                    .split(whereSeparator: { $0 == "," || $0.isNewline })
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        ).sorted()
    }
}
