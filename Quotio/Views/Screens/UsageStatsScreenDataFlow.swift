//
//  UsageStatsScreenDataFlow.swift
//  Quotio
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension UsageStatsScreen {
    // MARK: - Data Loading

    func manualRefreshStats() async {
        await loadStats()

        if let currentError = normalizedErrorMessage(errorMessage) {
            await MainActor.run {
                showFeedback(
                    "stats.feedback.refreshFailed".localized(fallback: "统计刷新失败") + ": " + currentError,
                    isError: true
                )
            }
            return
        }

        await MainActor.run {
            showFeedback("stats.feedback.refreshed".localized(fallback: "统计已刷新"))
        }
    }

    func loadStats() async {
        uiMetrics.begin("usage.load_stats")
        isLoading = true
        errorMessage = nil

        guard let apiClient = viewModel.apiClient else {
            await MainActor.run {
                self.errorMessage = "stats.error.apiClientUnavailable".localized(fallback: "API client not available")
                self.isLoading = false
            }
            return
        }

        do {
            async let statsTask = apiClient.fetchUsageStats()
            async let historyTask = apiClient.fetchRequestHistory(limit: 50)

            let (stats, history) = try await (statsTask, historyTask)
            await MainActor.run {
                self.usageStats = stats
                self.requestHistory = history.requests
                self.isLoading = false
            }
            uiMetrics.end("usage.load_stats", metadata: "requests=\(history.requests.count)")
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
            uiMetrics.end("usage.load_stats", metadata: "error")
        }
    }

    func startPolling() {
        stopPolling()
        pollingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                if selectedTab != .realtime {
                    await loadStats()
                }
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func connectSSE() async {
        guard !isSSEStreamActive else { return }
        guard let apiClient = viewModel.apiClient else { return }

        isSSEStreamActive = true
        defer {
            isSSEConnected = false
            isSSEStreamActive = false
        }

        while !Task.isCancelled && selectedTab == .realtime {
            do {
                guard let url = await apiClient.getSSEStreamURL(sinceSeq: lastSeenSSESeq > 0 ? lastSeenSSESeq : nil) else {
                    throw URLError(.badURL)
                }
                var request = URLRequest(url: url)
                let authKey = viewModel.proxyManager.managementKey
                if !authKey.isEmpty {
                    request.setValue("Bearer \(authKey)", forHTTPHeaderField: "Authorization")
                }
                request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
                if lastSeenSSESeq > 0 {
                    request.setValue(String(lastSeenSSESeq), forHTTPHeaderField: "Last-Event-ID")
                }

                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                guard let http = response as? HTTPURLResponse, 200...299 ~= http.statusCode else {
                    throw URLError(.badServerResponse)
                }

                isSSEConnected = true

                for try await line in bytes.lines {
                    if Task.isCancelled || selectedTab != .realtime {
                        break
                    }
                    if line.hasPrefix("data:") {
                        let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                        guard !payload.isEmpty,
                              let data = payload.data(using: .utf8),
                              let event = try? JSONDecoder().decode(SSERequestEvent.self, from: data) else {
                            continue
                        }
                        ingestRealtimeEvent(event)
                    }
                }
                isSSEConnected = false
            } catch {
                Log.warning("[UsageStatsScreen] SSE stream error: \(error)")
                isSSEConnected = false
                if let replay = try? await apiClient.fetchUsageEvents(sinceSeq: lastSeenSSESeq, limit: 1000) {
                    for event in replay {
                        ingestRealtimeEvent(event)
                    }
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func ingestRealtimeEvent(_ event: SSERequestEvent) {
        if let seq = event.seq, seq > lastSeenSSESeq {
            lastSeenSSESeq = seq
        }
        let key = event.dedupeKey
        guard !sseEventKeys.contains(key) else { return }
        sseEvents.append(event)
        sseEventKeys.insert(key)
    }

    func exportStats() async {
        guard let apiClient = viewModel.apiClient else {
            Log.warning("[UsageStatsScreen] API client not available for export")
            await MainActor.run {
                showFeedback("stats.feedback.exportFailed".localized(fallback: "导出失败：API 服务不可用"), isError: true)
            }
            return
        }

        do {
            let data = try await apiClient.exportUsageStats()

            let panel = NSSavePanel()
            panel.allowedContentTypes = [UTType.json]
            panel.nameFieldStringValue = "usage-statistics-\(Date().ISO8601Format()).json"

            if panel.runModal() == .OK, let url = panel.url {
                try data.write(to: url)
                await MainActor.run {
                    showFeedback(
                        "stats.feedback.exported".localized(fallback: "统计已导出") + ": " + url.lastPathComponent
                    )
                }
            }
        } catch {
            Log.warning("[UsageStatsScreen] Export failed: \(error)")
            await MainActor.run {
                showFeedback(
                    "stats.feedback.exportFailed".localized(fallback: "导出失败") + ": " + error.localizedDescription,
                    isError: true
                )
            }
        }
    }

    func importStats() async {
        guard let apiClient = viewModel.apiClient else {
            Log.warning("[UsageStatsScreen] API client not available for import")
            await MainActor.run {
                showFeedback("stats.feedback.importFailed".localized(fallback: "导入失败：API 服务不可用"), isError: true)
            }
            return
        }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.json]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try Data(contentsOf: url)
            try await apiClient.importUsageStats(data: data)
            await loadStats()
            uiMetrics.mark("usage.import.success", metadata: url.lastPathComponent)
            if let currentError = normalizedErrorMessage(errorMessage) {
                await MainActor.run {
                    showFeedback(
                        "stats.feedback.importPartial".localized(fallback: "导入完成，但刷新失败") + ": " + currentError,
                        isError: true
                    )
                }
            } else {
                await MainActor.run {
                    showFeedback(
                        "stats.feedback.imported".localized(fallback: "统计已导入") + ": " + url.lastPathComponent
                    )
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            Log.warning("[UsageStatsScreen] Import failed: \(error)")
            await MainActor.run {
                showFeedback(
                    "stats.feedback.importFailed".localized(fallback: "导入失败") + ": " + error.localizedDescription,
                    isError: true
                )
            }
        }
    }

    func extractModelStats() -> [ModelStatItem] {
        guard let apis = usageStats?.usage?.apis else { return [] }

        var modelData: [String: (requests: Int, tokens: Int)] = [:]

        for (_, apiStats) in apis {
            if let models = apiStats.models {
                for (modelName, modelStats) in models {
                    var existing = modelData[modelName] ?? (0, 0)
                    existing.requests += modelStats.totalRequests ?? 0
                    existing.tokens += modelStats.totalTokens ?? 0
                    modelData[modelName] = existing
                }
            }
        }

        return modelData.map { ModelStatItem(model: $0.key, requests: $0.value.requests, tokens: $0.value.tokens) }
    }

    func extractAccountStats() -> [(account: String, stats: APIUsageSnapshot)] {
        guard let apis = usageStats?.usage?.apis, !apis.isEmpty else { return [] }

        struct ModelBucket {
            var requests: Int = 0
            var tokens: Int = 0
        }

        struct AccountBucket {
            var totalRequests: Int = 0
            var totalTokens: Int = 0
            var models: [String: ModelBucket] = [:]
        }

        var buckets: [String: AccountBucket] = [:]

        func add(_ account: String, model: String, requests: Int, tokens: Int) {
            var accountBucket = buckets[account] ?? AccountBucket()
            accountBucket.totalRequests += requests
            accountBucket.totalTokens += tokens

            var modelBucket = accountBucket.models[model] ?? ModelBucket()
            modelBucket.requests += requests
            modelBucket.tokens += tokens
            accountBucket.models[model] = modelBucket

            buckets[account] = accountBucket
        }

        for (apiKey, apiStats) in apis {
            guard let models = apiStats.models, !models.isEmpty else { continue }

            for (modelName, modelStats) in models {
                if let details = modelStats.details, !details.isEmpty {
                    for detail in details {
                        let account = normalizedAccountIdentifier(
                            authIndex: detail.authIndex,
                            fallbackAPIKey: apiKey
                        )
                        add(
                            account,
                            model: modelName,
                            requests: 1,
                            tokens: detail.tokens?.totalTokens ?? 0
                        )
                    }
                    continue
                }

                // Fallback for snapshots without request-level details.
                let account = normalizedAccountIdentifier(authIndex: nil, fallbackAPIKey: apiKey)
                add(
                    account,
                    model: modelName,
                    requests: modelStats.totalRequests ?? 0,
                    tokens: modelStats.totalTokens ?? 0
                )
            }
        }

        let result: [(account: String, stats: APIUsageSnapshot)] = buckets.map { account, bucket in
            let models: [String: ModelUsageSnapshot] = bucket.models.mapValues { model in
                ModelUsageSnapshot(
                    totalRequests: model.requests,
                    totalTokens: model.tokens,
                    details: nil
                )
            }
            let stats = APIUsageSnapshot(
                totalRequests: bucket.totalRequests,
                totalTokens: bucket.totalTokens,
                models: models
            )
            return (account: account, stats: stats)
        }

        return result.sorted { ($0.stats.totalRequests ?? 0) > ($1.stats.totalRequests ?? 0) }
    }

    private func normalizedAccountIdentifier(authIndex: String?, fallbackAPIKey: String) -> String {
        let trimmed = authIndex?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            return trimmed
        }
        return fallbackAPIKey
    }

    var requestHistoryHeader: some View {
        HStack(spacing: 12) {
            Text("usage.stats.header.status".localized(fallback: "状态"))
                .frame(width: 20, alignment: .leading)
            Text("usage.stats.header.time".localized(fallback: "时间"))
                .frame(width: 60, alignment: .leading)
            Text("usage.stats.header.model".localized(fallback: "模型"))
                .frame(width: 150, alignment: .leading)
            Text("usage.stats.header.account".localized(fallback: "账号"))
                .frame(width: 120, alignment: .leading)
            Text("usage.stats.header.source".localized(fallback: "来源"))
                .frame(width: 90, alignment: .leading)
            Spacer()
            Text("usage.stats.header.tokens".localized(fallback: "Token"))
            Text("usage.stats.header.requestId".localized(fallback: "请求ID"))
                .frame(width: 100, alignment: .trailing)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.bottom, 4)
    }

    var realtimeDisplayEvents: [SSERequestEvent] {
        realtimeAutoScroll ? Array(sseEvents.reversed()) : sseEvents
    }

    var filteredRequestHistory: [RequestHistoryItem] {
        requestHistory.filter { item in
            if let success = historySuccessFilter, item.success != success {
                return false
            }

            if !historySearchText.isEmpty {
                let query = historySearchText.lowercased()
                let modelMatch = item.model?.lowercased().contains(query) ?? false
                let accountMatch = item.authIndex?.lowercased().contains(query) ?? false
                let sourceMatch = item.source?.lowercased().contains(query) ?? false
                let requestIdMatch = item.requestId?.lowercased().contains(query) ?? false
                if !(modelMatch || accountMatch || sourceMatch || requestIdMatch) {
                    return false
                }
            }

            return true
        }
    }

    func focusOnRequestHistory(_ item: RequestHistoryItem) {
        guard featureFlags.enhancedObservability else { return }
        viewModel.setObservabilityFocus(
            ObservabilityFocusFilter(
                requestId: item.requestId,
                model: item.model,
                account: item.authIndex,
                source: item.source,
                timestamp: item.date,
                origin: "usage.history"
            )
        )
        uiMetrics.mark("usage.focus_to_logs", metadata: item.requestId ?? item.model ?? "unknown")
        viewModel.currentPage = .logs
    }

    func focusOnRealtimeEvent(_ event: SSERequestEvent) {
        guard featureFlags.enhancedObservability else { return }
        viewModel.setObservabilityFocus(
            ObservabilityFocusFilter(
                requestId: event.requestId,
                model: event.model,
                account: event.authFile,
                source: event.source,
                timestamp: event.date,
                origin: "usage.realtime"
            )
        )
        uiMetrics.mark("usage.realtime_focus_to_logs", metadata: event.requestId ?? event.model ?? event.type)
        viewModel.currentPage = .logs
    }

    private func normalizedErrorMessage(_ message: String?) -> String? {
        guard let text = message?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        return text
    }

    private func showFeedback(_ message: String, isError: Bool = false) {
        feedbackDismissTask?.cancel()
        feedbackIsError = isError
        withAnimation(.easeOut(duration: 0.2)) {
            feedbackMessage = message
        }

        feedbackDismissTask = Task {
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeIn(duration: 0.2)) {
                    feedbackMessage = nil
                }
            }
        }
    }
}
