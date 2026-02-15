//
//  UsageStatsScreen.swift
//  Quotio - Usage Statistics Dashboard
//
//  Comprehensive usage statistics with real-time updates,
//  historical data visualization, and per-account/model breakdown.
//

import SwiftUI
import Charts
import UniformTypeIdentifiers

struct UsageStatsScreen: View {
    @Environment(QuotaViewModel.self) private var viewModel
    @State private var featureFlags = FeatureFlagManager.shared
    @State private var uiMetrics = UIBaselineMetricsTracker.shared
    @State private var usageStats: UsageStats?
    @State private var requestHistory: [RequestHistoryItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedTimeRange: TimeRange = .day
    @State private var selectedTab: StatsTab = .overview
    @State private var historySearchText = ""
    @State private var historySuccessFilter: Bool? = nil
    @State private var sseEvents: [SSERequestEvent] = []
    @State private var isSSEConnected = false
    @State private var isRealtimePaused = false
    @State private var realtimeAutoScroll = true
    
    enum TimeRange: String, CaseIterable {
        case hour = "1h"
        case day = "24h"
        case week = "7d"
        
        var title: String {
            switch self {
            case .hour: return "stats.range.hour".localized(fallback: "1 小时")
            case .day: return "stats.range.day".localized(fallback: "24 小时")
            case .week: return "stats.range.week".localized(fallback: "7 天")
            }
        }
    }
    
    enum StatsTab: String, CaseIterable {
        case overview = "overview"
        case byAccount = "byAccount"
        case byModel = "byModel"
        case realtime = "realtime"
        
        var title: String {
            switch self {
            case .overview: return "stats.tab.overview".localized(fallback: "概览")
            case .byAccount: return "stats.tab.byAccount".localized(fallback: "按账号")
            case .byModel: return "stats.tab.byModel".localized(fallback: "按模型")
            case .realtime: return "stats.tab.realtime".localized(fallback: "实时")
            }
        }
        
        var icon: String {
            switch self {
            case .overview: return "chart.bar.fill"
            case .byAccount: return "person.2.fill"
            case .byModel: return "cpu.fill"
            case .realtime: return "bolt.fill"
            }
        }
    }
    
    var body: some View {
        Group {
            if !viewModel.proxyManager.proxyStatus.running {
                ProxyRequiredView(
                    description: "stats.startProxy".localized(fallback: "启动代理以查看使用统计")
                ) {
                    await viewModel.startProxy()
                }
            } else {
                VStack(spacing: 0) {
                    // Tab Picker
                    Picker("stats.picker.tab".localized(fallback: "标签"), selection: $selectedTab) {
                        ForEach(StatsTab.allCases, id: \.self) { tab in
                            Label(tab.title, systemImage: tab.icon)
                                .tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding()
                    
                    Divider()
                    
                    // Content
                    if isLoading && usageStats == nil {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let error = errorMessage {
                        ContentUnavailableView {
                            Label("stats.error".localized(fallback: "加载错误"), systemImage: "exclamationmark.triangle")
                        } description: {
                            Text(error)
                        } actions: {
                            Button("stats.retry".localized(fallback: "重试")) {
                                Task { await loadStats() }
                            }
                        }
                    } else {
                        switch selectedTab {
                        case .overview:
                            overviewTab
                        case .byAccount:
                            byAccountTab
                        case .byModel:
                            byModelTab
                        case .realtime:
                            realtimeTab
                        }
                    }
                }
            }
        }
        .navigationTitle("nav.usageStats".localized(fallback: "使用统计"))
        .toolbar {
            toolbarContent
        }
        .task {
            await loadStats()
            startPolling()
        }
    }
    
    // MARK: - Overview Tab
    
    private var overviewTab: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                // Summary Cards
                summaryCardsSection
                
                // Time Distribution Chart
                if let usage = usageStats?.usage {
                    timeDistributionSection(usage: usage)
                }
                
                // Recent Requests
                recentRequestsSection
            }
            .padding()
        }
    }
    
    private var summaryCardsSection: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 12) {
            SummaryCard(
                title: "stats.totalRequests".localized(fallback: "总请求"),
                value: "\(usageStats?.usage?.totalRequests ?? 0)",
                icon: "arrow.up.arrow.down",
                color: Color.semanticInfo
            )
            
            SummaryCard(
                title: "stats.successRate".localized(fallback: "成功率"),
                value: String(format: "%.1f%%", usageStats?.usage?.successRate ?? 0),
                icon: "checkmark.circle.fill",
                color: Color.semanticSuccess
            )
            
            SummaryCard(
                title: "stats.totalTokens".localized(fallback: "总 Token"),
                value: (usageStats?.usage?.totalTokens ?? 0).formattedTokenCount,
                icon: "text.word.spacing",
                color: Color.semanticAccentSecondary
            )
            
            SummaryCard(
                title: "stats.failedRequests".localized(fallback: "失败请求"),
                value: "\(usageStats?.usage?.failureCount ?? 0)",
                icon: "xmark.circle.fill",
                color: Color.semanticDanger
            )
        }
    }
    
    @ViewBuilder
    private func timeDistributionSection(usage: UsageData) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("stats.requestsByTime".localized(fallback: "请求时间分布"))
                        .font(.headline)
                    Spacer()
                    Picker("stats.picker.range".localized(fallback: "范围"), selection: $selectedTimeRange) {
                        ForEach(TimeRange.allCases, id: \.self) { range in
                            Text(range.title).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
                
                if let requestsByHour = usage.requestsByHour, !requestsByHour.isEmpty {
                    Chart {
                        ForEach(requestsByHour.sorted(by: { $0.key < $1.key }), id: \.key) { hour, count in
                            BarMark(
                                x: .value("Hour", hour),
                                y: .value("Requests", count)
                            )
                            .foregroundStyle(Color.semanticInfo.gradient)
                        }
                    }
                    .frame(height: 150)
                } else {
                    Text("stats.noData".localized(fallback: "暂无数据"))
                        .foregroundStyle(.secondary)
                        .frame(height: 150)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    private var recentRequestsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("stats.recentRequests".localized(fallback: "最近请求"))
                        .font(.headline)
                    Spacer()
                    Text("\(requestHistory.count) "+"stats.requests".localized(fallback: "条"))
                        .foregroundStyle(.secondary)
                }

                if featureFlags.enhancedObservability {
                    HStack(spacing: 8) {
                        TextField("stats.filter.placeholder".localized(fallback: "按模型/账号/来源过滤"), text: $historySearchText)
                            .textFieldStyle(.roundedBorder)
                        Picker("stats.filter.success".localized(fallback: "结果"), selection: $historySuccessFilter) {
                            Text("logs.all".localized()).tag(nil as Bool?)
                            Text("status.connected".localized(fallback: "成功")).tag(true as Bool?)
                            Text("status.error".localized()).tag(false as Bool?)
                        }
                        .pickerStyle(.menu)
                        .frame(width: 110)
                    }
                }
                
                if requestHistory.isEmpty {
                    Text("stats.noRequests".localized(fallback: "暂无请求记录"))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    requestHistoryHeader
                    ForEach(filteredRequestHistory.prefix(20)) { item in
                        RequestHistoryRow(item: item) {
                            focusOnRequestHistory(item)
                        }
                        if item.id != filteredRequestHistory.prefix(20).last?.id {
                            Divider()
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - By Account Tab
    
    private var byAccountTab: some View {
        let accountStats = extractAccountStats()
        return ScrollView {
            LazyVStack(spacing: 16) {
                if !accountStats.isEmpty {
                    ForEach(accountStats, id: \.account) { item in
                        AccountStatsCard(account: item.account, stats: item.stats)
                    }
                } else {
                    ContentUnavailableView {
                        Label("stats.noAccountData".localized(fallback: "暂无账号数据"), systemImage: "person.2.slash")
                    }
                }
            }
            .padding()
        }
    }
    
    // MARK: - By Model Tab
    
    private var byModelTab: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                let modelStats = extractModelStats()
                if !modelStats.isEmpty {
                    ForEach(modelStats.sorted(by: { $0.requests > $1.requests }), id: \.model) { stat in
                        ModelStatsCard(stat: stat)
                    }
                } else {
                    ContentUnavailableView {
                        Label("stats.noModelData".localized(fallback: "暂无模型数据"), systemImage: "cpu")
                    }
                }
            }
            .padding()
        }
    }
    
    // MARK: - Realtime Tab
    
    private var realtimeTab: some View {
        VStack(spacing: 0) {
            // Connection Status
            HStack {
                Circle()
                    .fill(isSSEConnected ? Color.semanticSuccess : Color.semanticDanger)
                    .frame(width: 8, height: 8)
                Text(isSSEConnected ? "stats.connected".localized(fallback: "已连接") : "stats.disconnected".localized(fallback: "未连接"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(sseEvents.count) "+"stats.events".localized(fallback: "事件"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("stats.realtimeAutoScroll".localized(fallback: "实时滚动"), isOn: $realtimeAutoScroll)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .help("stats.realtimeAutoScroll.help".localized(fallback: "开启后自动显示最新事件"))
                Button(isRealtimePaused ? "action.resume".localized(fallback: "继续") : "action.pause".localized(fallback: "暂停")) {
                    isRealtimePaused.toggle()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Button("action.clear".localized(fallback: "清空")) {
                    sseEvents.removeAll()
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.regularMaterial)
            
            Divider()
            
            // Event List
            if sseEvents.isEmpty {
                ContentUnavailableView {
                    Label("stats.noEvents".localized(fallback: "等待事件"), systemImage: "bolt.slash")
                } description: {
                    Text("stats.eventsWillAppear".localized(fallback: "实时事件将在此显示"))
                }
            } else {
                List(realtimeDisplayEvents, id: \.timestamp) { event in
                    SSEEventRow(event: event) {
                        focusOnRealtimeEvent(event)
                    }
                }
            }
        }
        .task {
            await connectSSE()
        }
    }
    
    // MARK: - Toolbar
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                Task { await loadStats() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .accessibilityLabel("action.refresh".localized())
            .help("action.refresh".localized())
            .disabled(isLoading)
            
            Menu {
                Button("stats.export".localized(fallback: "导出统计")) {
                    Task { await exportStats() }
                }
                Button("stats.import".localized(fallback: "导入统计")) {
                    // TODO: Implement import
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel("stats.exportMenu".localized(fallback: "导出菜单"))
            .help("stats.exportMenu".localized(fallback: "打开导出/导入菜单"))
        }
    }
    
    // MARK: - Data Loading
    
    private func loadStats() async {
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
    
    private func startPolling() {
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                if selectedTab != .realtime {
                    await loadStats()
                }
            }
        }
    }
    
    private func connectSSE() async {
        guard let apiClient = viewModel.apiClient,
              let url = await apiClient.getSSEStreamURL() else { return }
        
        var request = URLRequest(url: url)
        let authKey = viewModel.proxyManager.managementKey
        if !authKey.isEmpty {
            request.setValue("Bearer \(authKey)", forHTTPHeaderField: "Authorization")
        }
        
        // Note: Full SSE implementation would require URLSession streaming
        // This is a simplified version that polls the history endpoint
        isSSEConnected = true
        
        while !Task.isCancelled && selectedTab == .realtime {
            do {
                let history = try await apiClient.fetchRequestHistory(limit: 10)
                await MainActor.run {
                    guard !isRealtimePaused else { return }
                    // Convert history items to SSE events for display
                    for item in history.requests {
                        let event = SSERequestEvent(
                            type: item.success ? "request" : "error",
                            timestamp: item.timestamp,
                            requestId: item.requestId,
                            provider: nil,
                            model: item.model,
                            authFile: item.authIndex,
                            source: item.source,
                            success: item.success,
                            tokens: item.tokens,
                            latencyMs: nil,
                            error: nil
                        )
                        if !sseEvents.contains(where: { $0.timestamp == event.timestamp }) {
                            sseEvents.append(event)
                        }
                    }
                    // Keep only last 100 events
                    if sseEvents.count > 100 {
                        sseEvents = Array(sseEvents.suffix(100))
                    }
                }
            } catch {
                NSLog("[UsageStatsScreen] SSE polling error: \(error)")
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        }
        
        isSSEConnected = false
    }
    
    private func exportStats() async {
        guard let apiClient = viewModel.apiClient else {
            NSLog("[UsageStatsScreen] API client not available for export")
            return
        }
        
        do {
            let data = try await apiClient.exportUsageStats()
            
            // Save to file
            let panel = NSSavePanel()
            panel.allowedContentTypes = [UTType.json]
            panel.nameFieldStringValue = "usage-statistics-\(Date().ISO8601Format()).json"
            
            if panel.runModal() == .OK, let url = panel.url {
                try data.write(to: url)
            }
        } catch {
            NSLog("[UsageStatsScreen] Export failed: \(error)")
        }
    }
    
    private func extractModelStats() -> [ModelStatItem] {
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

    private func extractAccountStats() -> [(account: String, stats: APIUsageSnapshot)] {
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

    private var requestHistoryHeader: some View {
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
        .padding(.bottom, 2)
    }

    private var realtimeDisplayEvents: [SSERequestEvent] {
        realtimeAutoScroll ? Array(sseEvents.reversed()) : sseEvents
    }

    private var filteredRequestHistory: [RequestHistoryItem] {
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

    private func focusOnRequestHistory(_ item: RequestHistoryItem) {
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

    private func focusOnRealtimeEvent(_ event: SSERequestEvent) {
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
}

// MARK: - Supporting Views

struct SummaryCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .foregroundStyle(color)
                    Spacer()
                }
                
                Text(value)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct RequestHistoryRow: View {
    let item: RequestHistoryItem
    var onFocus: (() -> Void)? = nil
    @State private var copied = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Image(systemName: item.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.caption)
                .foregroundStyle(item.success ? Color.semanticSuccess : Color.semanticDanger)
            
            // Time
            if let date = item.date {
                Text(date, style: .time)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .leading)
            }
            
            // Model
            Text(item.model ?? "logs.status.unknown".localized(fallback: "未知"))
                .font(.caption)
                .lineLimit(1)
                .frame(width: 150, alignment: .leading)
            
            // Account
            if let authIndex = item.authIndex {
                Text(authIndex)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 120, alignment: .leading)
            }

            // Source
            if let source = item.source {
                Text(source)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 90, alignment: .leading)
            }
            
            Spacer()
            
            // Tokens
            if let tokens = item.tokens {
                Text("\(tokens)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if item.requestId != nil {
                HStack(spacing: 4) {
                    Text("#" + String((item.requestId ?? "").prefix(8)))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(width: 76, alignment: .trailing)

                    Button {
                        guard let requestId = item.requestId else { return }
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(requestId, forType: .string)
                        copied = true
                        Task {
                            try? await Task.sleep(for: .seconds(1.2))
                            copied = false
                        }
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.caption2)
                            .foregroundStyle(copied ? Color.semanticSuccess : .secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("stats.requestId.copy.help".localized(fallback: "复制请求 ID"))
                    .accessibilityLabel("stats.requestId.copy".localized(fallback: "复制请求 ID"))
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            onFocus?()
        }
        .help("stats.focusLog".localized(fallback: "点击在日志中聚焦此请求"))
        .accessibilityLabel("stats.requestHistoryRow".localized(fallback: "请求历史行"))
        .accessibilityHint("stats.focusLog".localized(fallback: "点击在日志中聚焦此请求"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            onFocus?()
        }
    }
}

struct AccountStatsCard: View {
    let account: String
    let stats: APIUsageSnapshot
    
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "person.circle.fill")
                        .foregroundStyle(Color.semanticInfo)
                    Text(account)
                        .font(.headline)
                    Spacer()
                    Text("\(stats.totalRequests ?? 0) "+"stats.requests".localized(fallback: "请求"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Divider()
                
                if let models = stats.models, !models.isEmpty {
                    ForEach(models.sorted(by: { ($0.value.totalRequests ?? 0) > ($1.value.totalRequests ?? 0) }), id: \.key) { model, modelStats in
                        HStack {
                            Text(model)
                                .font(.caption)
                            Spacer()
                            Text("\(modelStats.totalRequests ?? 0) "+"stats.req".localized(fallback: "次"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\((modelStats.totalTokens ?? 0).formattedTokenCount)")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(Color.semanticAccentSecondary)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

struct ModelStatItem {
    let model: String
    let requests: Int
    let tokens: Int
}

struct ModelStatsCard: View {
    let stat: ModelStatItem
    
    var body: some View {
        GroupBox {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(stat.model)
                        .font(.headline)
                    Text("\(stat.requests) "+"stats.requests".localized(fallback: "请求"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(stat.tokens.formattedTokenCount)
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .foregroundStyle(Color.semanticAccentSecondary)
                    Text("usage.stats.tokens.unit".localized(fallback: "tokens"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

struct SSEEventRow: View {
    let event: SSERequestEvent
    var onFocus: (() -> Void)? = nil
    
    var body: some View {
        HStack(spacing: 12) {
            // Event type indicator
            Image(systemName: eventIcon)
                .foregroundStyle(eventColor)
            
            // Time
            if let date = event.date {
                Text(date, style: .time)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            
            // Model
            if let model = event.model {
                Text(model)
                    .font(.caption)
                    .lineLimit(1)
            }
            
            // Account
            if let authFile = event.authFile {
                Text(authFile)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let source = event.source {
                Text(source)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Status badge
            Text(event.type.uppercased())
                .font(.system(.caption2, design: .monospaced, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(eventColor)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onFocus?()
        }
        .help("stats.focusLog".localized(fallback: "点击在日志中聚焦此请求"))
        .accessibilityLabel("stats.realtimeEventRow".localized(fallback: "实时事件行"))
        .accessibilityHint("stats.focusLog".localized(fallback: "点击在日志中聚焦此请求"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            onFocus?()
        }
    }
    
    private var eventIcon: String {
        switch event.type {
        case "request": return "arrow.up.arrow.down"
        case "quota_exceeded": return "exclamationmark.triangle.fill"
        case "error": return "xmark.circle.fill"
        case "connected": return "checkmark.circle.fill"
        default: return "questionmark.circle"
        }
    }
    
    private var eventColor: Color {
        switch event.type {
        case "request": return event.success == true ? Color.semanticSuccess : Color.semanticWarning
        case "quota_exceeded": return Color.semanticWarning
        case "error": return Color.semanticDanger
        case "connected": return Color.semanticInfo
        default: return .gray
        }
    }
}

#Preview {
    UsageStatsScreen()
}
