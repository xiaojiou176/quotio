//
//  LogsScreen.swift
//  Quotio
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct LogsScreen: View {
    @Environment(QuotaViewModel.self) private var viewModel
    @Environment(LogsViewModel.self) private var logsViewModel
    @State private var featureFlags = FeatureFlagManager.shared
    @State private var uiMetrics = UIBaselineMetricsTracker.shared
    @State private var selectedTab: LogsTab = .requests
    @State private var autoScroll = true
    @State private var filterLevel: LogEntry.LogLevel? = nil
    @State private var proxyLogViewMode: ProxyLogViewMode = .structured
    @State private var searchText = ""
    @State private var requestFilterProvider: String? = nil
    @State private var requestSourceFilter: String? = nil
    @State private var requestStatusFilter: RequestStatusFilter = .all
    @State private var fallbackOnly = false
    @State private var expandedTraces: Set<UUID> = []
    @State private var expandedPayloads: Set<UUID> = []
    @State private var usageHistoryEvidenceByRequestId: [String: RequestHistoryItem] = [:]
    @State private var usageHistoryEvidenceList: [RequestHistoryItem] = []
    @State private var lastEvidenceRefreshAt: Date = .distantPast
    
    enum LogsTab: String, CaseIterable {
        case requests = "requests"
        case proxyLogs = "proxyLogs"
        
        var title: String {
            switch self {
            case .requests: return "logs.tab.requests".localizedStatic()
            case .proxyLogs: return "logs.tab.proxyLogs".localizedStatic()
            }
        }
        
        var icon: String {
            switch self {
            case .requests: return "arrow.up.arrow.down"
            case .proxyLogs: return "doc.text"
            }
        }
    }

    enum RequestStatusFilter: String, CaseIterable, Identifiable {
        case all
        case success
        case clientError
        case serverError

        var id: String { rawValue }

        var label: String {
            switch self {
            case .all: return "logs.all".localized(fallback: "全部")
            case .success: return "status.connected".localized(fallback: "成功")
            case .clientError: return "logs.clientError".localized(fallback: "客户端错误")
            case .serverError: return "logs.serverError".localized(fallback: "服务端错误")
            }
        }
    }

    enum ProxyLogViewMode: String, CaseIterable, Identifiable {
        case structured
        case raw

        var id: String { rawValue }

        var title: String {
            switch self {
            case .structured:
                return "logs.proxyView.structured".localized(fallback: "结构化")
            case .raw:
                return "logs.proxyView.raw".localized(fallback: "原始")
            }
        }
    }

    private enum ProxyLogsContentState {
        case loading
        case error(String)
        case empty
        case success
    }
    
    var body: some View {
        Group {
            if !viewModel.proxyManager.proxyStatus.running {
                ProxyRequiredView(
                    description: "logs.startProxy".localized()
                ) {
                    await viewModel.startProxy()
                }
            } else {
                VStack(spacing: 0) {
                    // Tab Picker
                    Picker("logs.picker.tab".localized(fallback: "标签"), selection: $selectedTab) {
                        ForEach(LogsTab.allCases, id: \.self) { tab in
                            Label(tab.title, systemImage: tab.icon)
                                .tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding()
                    
                    Divider()
                    
                    // Tab Content
                    switch selectedTab {
                    case .requests:
                        requestHistoryView
                    case .proxyLogs:
                        proxyLogsView
                    }
                }
            }
        }
        .navigationTitle("nav.logs".localized())
        .searchable(text: $searchText, prompt: searchPrompt)
        .toolbar {
            toolbarContent
        }
        .task {
            uiMetrics.mark("logs.screen.appear")
            // Configure LogsViewModel with proxy connection when screen appears
            if !logsViewModel.isConfigured {
                logsViewModel.configure(
                    baseURL: viewModel.proxyManager.managementURL,
                    authKey: viewModel.proxyManager.managementKey
                )
            }
            
            while !Task.isCancelled {
                if selectedTab == .proxyLogs {
                    await logsViewModel.refreshLogs()
                } else if featureFlags.enhancedObservability {
                    let now = Date()
                    if now.timeIntervalSince(lastEvidenceRefreshAt) > 5 {
                        await refreshUsageHistoryEvidence()
                        lastEvidenceRefreshAt = now
                    }
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }
    
    private var searchPrompt: String {
        switch selectedTab {
        case .requests:
            return "logs.searchRequests".localized()
        case .proxyLogs:
            return "logs.searchLogs".localized()
        }
    }
    
    // MARK: - Request History View
    
    private var requestHistoryView: some View {
        Group {
            if viewModel.requestTracker.requestHistory.isEmpty {
                ContentUnavailableView {
                    Label("logs.noRequests".localized(), systemImage: "arrow.up.arrow.down")
                } description: {
                    Text("logs.requestsWillAppear".localized())
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                VStack(spacing: 0) {
                    if featureFlags.enhancedObservability, selectedTab == .requests, let focus = viewModel.observabilityFocusFilter {
                        focusFilterBanner(focus)
                        Divider()
                    }

                    // Stats Header
                    requestStatsHeader
                    
                    Divider()
                    
                    // Request List
                    requestList
                }
            }
        }
    }
    
    private var requestStatsHeader: some View {
        let stats = viewModel.requestTracker.stats
        
        return HStack(spacing: 24) {
            StatItem(
                title: "logs.stats.totalRequests".localized(),
                value: "\(stats.totalRequests)"
            )
            
            StatItem(
                title: "logs.stats.successRate".localized(),
                value: String(format: "%.0f%%", stats.successRate)
            )
            
            StatItem(
                title: "logs.stats.totalTokens".localized(),
                value: stats.totalTokens.formattedTokenCount
            )
            
            StatItem(
                title: "logs.stats.avgDuration".localized(),
                value: "\(stats.averageDurationMs)ms"
            )
            
            Spacer()
            
            // Provider Filter
            Picker("logs.picker.provider".localized(fallback: "提供商"), selection: $requestFilterProvider) {
                Text("logs.filter.allProviders".localized()).tag(nil as String?)
                Divider()
                ForEach(Array(stats.byProvider.keys.sorted()), id: \.self) { provider in
                    Text(provider.capitalized).tag(provider as String?)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 140)

            Picker("logs.source".localized(fallback: "来源"), selection: $requestSourceFilter) {
                Text("logs.all".localized(fallback: "全部")).tag(nil as String?)
                Divider()
                ForEach(availableRequestSources, id: \.self) { source in
                    Text(source).tag(source as String?)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 130)

            Picker("logs.status".localized(fallback: "状态"), selection: $requestStatusFilter) {
                ForEach(RequestStatusFilter.allCases) { filter in
                    Text(filter.label).tag(filter)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 120)

            Toggle("logs.fallbackOnly".localized(fallback: "仅看回退"), isOn: $fallbackOnly)
                .toggleStyle(.switch)
        }
        .padding()
        .background(.regularMaterial)
    }
    
    private var filteredRequests: [RequestLog] {
        var requests = viewModel.requestTracker.requestHistory
        
        if let provider = requestFilterProvider {
            requests = requests.filter { $0.provider == provider }
        }

        if let source = requestSourceFilter {
            requests = requests.filter { request in
                let observed = request.source ?? usageEvidence(for: request)?.source
                return observed == source
            }
        }

        switch requestStatusFilter {
        case .all:
            break
        case .success:
            requests = requests.filter { ($0.statusCode ?? 0) >= 200 && ($0.statusCode ?? 0) < 300 }
        case .clientError:
            requests = requests.filter { ($0.statusCode ?? 0) >= 400 && ($0.statusCode ?? 0) < 500 }
        case .serverError:
            requests = requests.filter { ($0.statusCode ?? 0) >= 500 && ($0.statusCode ?? 0) < 600 }
        }

        if fallbackOnly {
            requests = requests.filter { $0.hasFallbackRoute || ($0.fallbackAttempts?.isEmpty == false) }
        }
        
        if !searchText.isEmpty {
            requests = requests.filter { request in
                let evidence = usageEvidence(for: request)
                let authState = authEvidence(for: request, usageEvidence: evidence)
                return (request.provider?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                (request.model?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                (request.endpoint.localizedCaseInsensitiveContains(searchText)) ||
                (request.source?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                (request.accountHint?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                (request.requestId?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                (request.requestPayloadSnippet?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                (authState?.normalizedErrorKind?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                (authState?.errorReason?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }

        if featureFlags.enhancedObservability, let focus = viewModel.observabilityFocusFilter {
            let strictMatches = applyFocusFilter(to: requests, focus: focus)
            requests = strictMatches.isEmpty ? applyRelaxedFocusFilter(to: requests, focus: focus) : strictMatches
        }
        
        return requests
    }

    private var availableRequestSources: [String] {
        let direct = Set(viewModel.requestTracker.requestHistory.compactMap(\.source))
        let evidence = Set(usageHistoryEvidenceList.compactMap(\.source))
        return Array(direct.union(evidence)).sorted()
    }
    
    private var requestList: some View {
        Group {
            if filteredRequests.isEmpty {
                ContentUnavailableView {
                    Label("logs.noRequests".localized(fallback: "没有匹配的请求"), systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("logs.focusNoMatch".localized(fallback: "当前聚焦条件未命中，请清除聚焦或放宽筛选条件。"))
                } actions: {
                    if viewModel.observabilityFocusFilter != nil {
                        Button("action.clear".localized(fallback: "清除")) {
                            viewModel.setObservabilityFocus(nil)
                            uiMetrics.mark("logs.focus_filter_cleared_no_match")
                        }
                    }
                }
            } else {
                ScrollViewReader { proxy in
                    List(filteredRequests) { request in
                        let evidence = usageEvidence(for: request)
                        let authState = authEvidence(for: request, usageEvidence: evidence)
                        RequestRow(
                            request: request,
                            evidence: evidence,
                            authEvidence: authState,
                            isTraceExpanded: expandedTraces.contains(request.id),
                            isPayloadExpanded: expandedPayloads.contains(request.id),
                            onToggleTrace: {
                                if expandedTraces.contains(request.id) {
                                    expandedTraces.remove(request.id)
                                } else {
                                    expandedTraces.insert(request.id)
                                }
                            },
                            onTogglePayload: {
                                if expandedPayloads.contains(request.id) {
                                    expandedPayloads.remove(request.id)
                                } else {
                                    expandedPayloads.insert(request.id)
                                }
                            }
                        )
                        .id("\(request.id)-\(expandedTraces.contains(request.id))-\(expandedPayloads.contains(request.id))")
                    }
                    .onChange(of: viewModel.requestTracker.requestHistory.count) { _, _ in
                        if autoScroll, let first = filteredRequests.first {
                            withAnimation {
                                proxy.scrollTo(first.id, anchor: .top)
                            }
                        }
                    }
                }
            }
        }
    }

    private func refreshUsageHistoryEvidence() async {
        guard let client = viewModel.apiClient else { return }
        do {
            let history = try await client.fetchRequestHistory(limit: 300)
            usageHistoryEvidenceList = history.requests
            usageHistoryEvidenceByRequestId = history.requests.reduce(into: [:]) { result, item in
                if let requestId = item.requestId, !requestId.isEmpty {
                    result[requestId] = item
                }
            }
        } catch {
            NSLog("[LogsScreen] Failed to refresh usage evidence: \(error.localizedDescription)")
        }
    }

    private func usageEvidence(for request: RequestLog) -> RequestHistoryItem? {
        if let requestId = request.requestId,
           let direct = usageHistoryEvidenceByRequestId[requestId] {
            return direct
        }

        return usageHistoryEvidenceList.first { item in
            guard let requestDate = item.date else { return false }
            let sameModel = (item.model ?? "") == (request.model ?? "")
            let closeInTime = abs(requestDate.timeIntervalSince(request.timestamp)) <= 3
            let successMatches = item.success == request.isSuccess
            return sameModel && closeInTime && successMatches
        }
    }

    private func authEvidence(for request: RequestLog, usageEvidence: RequestHistoryItem?) -> AuthFile? {
        var candidates = viewModel.authFiles
        if let provider = request.provider?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !provider.isEmpty {
            candidates = candidates.filter { $0.provider.lowercased() == provider }
        }
        let authHint = (request.accountHint ?? usageEvidence?.authIndex ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !authHint.isEmpty {
            if let exact = candidates.first(where: { ($0.authIndex ?? "").caseInsensitiveCompare(authHint) == .orderedSame }) {
                return exact
            }
            if let exact = candidates.first(where: { ($0.account ?? "").caseInsensitiveCompare(authHint) == .orderedSame }) {
                return exact
            }
            if let fuzzy = candidates.first(where: {
                ($0.authIndex ?? "").localizedCaseInsensitiveContains(authHint) ||
                ($0.account ?? "").localizedCaseInsensitiveContains(authHint) ||
                ($0.email ?? "").localizedCaseInsensitiveContains(authHint)
            }) {
                return fuzzy
            }
        }
        return candidates.first
    }

    private func applyFocusFilter(to requests: [RequestLog], focus: ObservabilityFocusFilter) -> [RequestLog] {
        if let requestId = focus.requestId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !requestId.isEmpty {
            return requests.filter { request in
                if let observed = request.requestId,
                   observed.caseInsensitiveCompare(requestId) == .orderedSame {
                    return true
                }
                if let observed = usageEvidence(for: request)?.requestId,
                   observed.caseInsensitiveCompare(requestId) == .orderedSame {
                    return true
                }
                return false
            }
        }

        return requests.filter { request in
            let evidence = usageEvidence(for: request)

            if let model = focus.model?.trimmingCharacters(in: .whitespacesAndNewlines),
               !model.isEmpty {
                let observedModel = request.model ?? evidence?.model ?? ""
                if !observedModel.localizedCaseInsensitiveContains(model) {
                    return false
                }
            }

            if let account = focus.account?.trimmingCharacters(in: .whitespacesAndNewlines),
               !account.isEmpty {
                let observedAccount = request.accountHint ?? evidence?.authIndex ?? ""
                if !observedAccount.isEmpty && !observedAccount.localizedCaseInsensitiveContains(account) {
                    return false
                }
            }

            if let source = focus.source?.trimmingCharacters(in: .whitespacesAndNewlines),
               !source.isEmpty,
               !isGenericFocusSource(source) {
                let observedSource = request.source ?? evidence?.source ?? request.provider ?? ""
                if !observedSource.isEmpty &&
                    !observedSource.localizedCaseInsensitiveContains(source) &&
                    !request.endpoint.localizedCaseInsensitiveContains(source) {
                    return false
                }
            }

            return true
        }
    }

    private func applyRelaxedFocusFilter(to requests: [RequestLog], focus: ObservabilityFocusFilter) -> [RequestLog] {
        // When strict focus yields zero rows, keep logs discoverable by applying
        // model/account/time heuristics instead of returning an empty list.
        requests.filter { request in
            let evidence = usageEvidence(for: request)
            var matched = false

            if let model = focus.model?.trimmingCharacters(in: .whitespacesAndNewlines),
               !model.isEmpty {
                let observedModel = request.model ?? evidence?.model ?? ""
                if observedModel.localizedCaseInsensitiveContains(model) {
                    matched = true
                }
            }

            if let account = focus.account?.trimmingCharacters(in: .whitespacesAndNewlines),
               !account.isEmpty {
                let observedAccount = request.accountHint ?? evidence?.authIndex ?? ""
                if !observedAccount.isEmpty && observedAccount.localizedCaseInsensitiveContains(account) {
                    matched = true
                }
            }

            if let timestamp = focus.timestamp {
                let requestDelta = abs(request.timestamp.timeIntervalSince(timestamp))
                let evidenceDelta = evidence?.date.map { abs($0.timeIntervalSince(timestamp)) } ?? .greatestFiniteMagnitude
                if min(requestDelta, evidenceDelta) <= 6 * 3600 {
                    matched = true
                }
            }

            if let source = focus.source?.trimmingCharacters(in: .whitespacesAndNewlines),
               !source.isEmpty,
               !isGenericFocusSource(source) {
                let observedSource = request.source ?? evidence?.source ?? request.provider ?? ""
                if observedSource.localizedCaseInsensitiveContains(source) ||
                    request.endpoint.localizedCaseInsensitiveContains(source) {
                    matched = true
                }
            }

            return matched
        }
    }

    private func isGenericFocusSource(_ source: String) -> Bool {
        let normalized = source.lowercased()
        return normalized == "realtime" ||
            normalized == "request" ||
            normalized == "event" ||
            normalized == "usage.realtime"
    }

    private func focusFilterBanner(_ focus: ObservabilityFocusFilter) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "scope")
                .foregroundStyle(Color.semanticInfo)

            VStack(alignment: .leading, spacing: 2) {
                Text("logs.focusMode".localized(fallback: "聚焦模式"))
                    .font(.caption.bold())
                Text(
                    "logs.focusMode.detail".localized(
                        fallback: "来源: \(focus.origin) | 模型: \(focus.model ?? "-") | 账号: \(focus.account ?? "-")"
                    )
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer()

            Button("action.clear".localized(fallback: "清除")) {
                viewModel.setObservabilityFocus(nil)
                uiMetrics.mark("logs.focus_filter_cleared")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.semanticSelectionFill)
    }
    
    // MARK: - Proxy Logs View
    
    var filteredLogs: [LogEntry] {
        var logs = logsViewModel.logs
        
        if let level = filterLevel {
            logs = logs.filter { $0.level == level }
        }
        
        if !searchText.isEmpty {
            logs = logs.filter { $0.message.localizedCaseInsensitiveContains(searchText) }
        }
        
        return logs
    }

    private var proxyLogsContentState: ProxyLogsContentState {
        if logsViewModel.isRefreshing && logsViewModel.logs.isEmpty {
            return .loading
        }
        if let error = logsViewModel.refreshError, logsViewModel.logs.isEmpty {
            return .error(error)
        }
        if filteredLogs.isEmpty {
            return .empty
        }
        return .success
    }
    
    private var proxyLogsView: some View {
        Group {
            switch proxyLogsContentState {
            case .loading:
                ContentUnavailableView {
                    Label("logs.loading".localized(fallback: "加载日志中"), systemImage: "clock.arrow.circlepath")
                } description: {
                    Text("logs.loading.description".localized(fallback: "正在从代理服务拉取最新日志。"))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            case .error(let message):
                ContentUnavailableView {
                    Label("logs.error".localized(fallback: "日志加载失败"), systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("action.retry".localized(fallback: "重试")) {
                        Task { await logsViewModel.refreshLogs() }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            case .empty:
                ContentUnavailableView {
                    Label("logs.noLogs".localized(), systemImage: "doc.text")
                } description: {
                    Text("logs.logsWillAppear".localized())
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            case .success:
                logList
            }
        }
    }
    
    private var logList: some View {
        ScrollViewReader { proxy in
            List(filteredLogs) { entry in
                if proxyLogViewMode == .structured {
                    StructuredLogRow(entry: entry)
                } else {
                    LogRow(entry: entry)
                }
            }
            .onChange(of: logsViewModel.logs.count) { _, _ in
                if autoScroll, let last = filteredLogs.last {
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    // MARK: - Toolbar
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            if selectedTab == .proxyLogs {
                Picker("logs.picker.view".localized(fallback: "视图"), selection: $proxyLogViewMode) {
                    ForEach(ProxyLogViewMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 160)

                Picker("logs.picker.filter".localized(fallback: "筛选"), selection: $filterLevel) {
                    Text("logs.all".localized()).tag(nil as LogEntry.LogLevel?)
                    Divider()
                    Text("logs.info".localized()).tag(LogEntry.LogLevel.info as LogEntry.LogLevel?)
                    Text("logs.warn".localized()).tag(LogEntry.LogLevel.warn as LogEntry.LogLevel?)
                    Text("logs.error".localized()).tag(LogEntry.LogLevel.error as LogEntry.LogLevel?)
                }
                .pickerStyle(.menu)
            }
            
            Toggle(isOn: $autoScroll) {
                Label("logs.autoScroll".localized(), systemImage: "arrow.down.to.line")
            }
            
            Button {
                if selectedTab == .requests {
                    // Refresh handled by RequestTracker automatically
                } else {
                    Task { await logsViewModel.refreshLogs() }
                }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .accessibilityLabel("action.refresh".localized())
            .help("action.refresh".localized())
            
            Button(role: .destructive) {
                if selectedTab == .requests {
                    viewModel.requestTracker.clearHistory()
                } else {
                    Task { await logsViewModel.clearLogs() }
                }
            } label: {
                Image(systemName: "trash")
            }
            .accessibilityLabel("action.delete".localized())
            .help("action.delete".localized())

            if selectedTab == .requests {
                Button {
                    exportRequestAuditPackage()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .help("logs.exportAudit".localized(fallback: "导出审计包"))
                .accessibilityLabel("logs.exportAudit".localized(fallback: "导出审计包"))
            }
        }
    }

    private func exportRequestAuditPackage() {
        do {
            let data = try viewModel.requestTracker.exportAuditPackageData(authFiles: viewModel.authFiles)
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "quotio-request-audit-\(Date().ISO8601Format()).json"
            panel.allowedContentTypes = [.json]
            if panel.runModal() == .OK, let url = panel.url {
                try data.write(to: url, options: .atomic)
                uiMetrics.mark("logs.audit_exported")
            }
        } catch {
            NSLog("[LogsScreen] Failed to export request audit package: \(error.localizedDescription)")
            uiMetrics.mark("logs.audit_export_failed", metadata: error.localizedDescription)
        }
    }
}

// MARK: - Request Row

struct RequestRow: View {
    let request: RequestLog
    let evidence: RequestHistoryItem?
    let authEvidence: AuthFile?
    let isTraceExpanded: Bool
    let isPayloadExpanded: Bool
    let onToggleTrace: () -> Void
    let onTogglePayload: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                // Timestamp
                Text(request.formattedTimestamp)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 120, alignment: .leading)

                // Status Badge
                statusBadge

                // Provider & Model with Fallback Route
                VStack(alignment: .leading, spacing: 2) {
                    if request.hasFallbackRoute {
                        // Show fallback route: virtual model → resolved model
                        HStack(spacing: 4) {
                            Text(request.model ?? "logs.status.unknown".localized(fallback: "未知"))
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(Color.semanticWarning)
                            Image(systemName: "arrow.right")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(request.resolvedProvider?.capitalized ?? "")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(Color.semanticInfo)
                        }
                        Text(request.resolvedModel ?? "")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        // Normal display
                        if let provider = request.provider {
                            Text(provider.capitalized)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        if let model = request.model {
                            Text(model)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    HStack(spacing: 6) {
                        if let source = request.source ?? evidence?.source {
                            Label(source, systemImage: "app.badge")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        if let account = request.accountHint ?? evidence?.authIndex {
                            Label(account, systemImage: "person.text.rectangle")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        if let kind = authEvidence?.normalizedErrorKind, !kind.isEmpty {
                            Label(kind, systemImage: "exclamationmark.bubble")
                                .font(.caption2)
                                .foregroundStyle(Color.semanticWarning)
                                .lineLimit(1)
                        }
                    }

                    if let frozenUntil = authEvidence?.frozenUntilDate, frozenUntil > Date() {
                        Label(
                            String(
                                format: "logs.auth.frozenUntil".localized(fallback: "冻结至 %@"),
                                frozenUntil.formatted(date: .omitted, time: .shortened)
                            ),
                            systemImage: "clock.badge.exclamationmark"
                        )
                            .font(.caption2)
                            .foregroundStyle(Color.semanticWarning)
                    }

                    if authEvidence?.isFatalDisabled == true {
                        Label("logs.auth.fatalDisabled".localized(fallback: "致命禁用"), systemImage: "exclamationmark.octagon.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.semanticDanger)
                    }
                }
                .frame(width: 180, alignment: .leading)

                // Tokens
                if let tokens = request.formattedTokens {
                    HStack(spacing: 4) {
                        Image(systemName: "text.word.spacing")
                            .font(.caption2)
                        Text(tokens)
                            .font(.system(.caption, design: .monospaced))
                    }
                    .foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .trailing)
                } else {
                    Text("-")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(width: 70, alignment: .trailing)
                }

                // Duration
                Text(request.formattedDuration)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .trailing)

                Spacer()

                // Size
                HStack(spacing: 4) {
                    Text("\(request.requestSize.formatted())B")
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text("\(request.responseSize.formatted())B")
                        .foregroundStyle(.secondary)
                }
                .font(.system(.caption2, design: .monospaced))

                if let rid = request.shortRequestId ?? evidence?.requestId.map({ String($0.prefix(8)) }) {
                    Text("#" + rid)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(width: 60, alignment: .trailing)
                }
            }

            if let attempts = request.fallbackAttempts, !attempts.isEmpty {
                Button {
                    onToggleTrace()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isTraceExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                        Text("logs.fallbackTrace".localized())
                            .font(.caption2)
                        Spacer()
                    }
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isTraceExpanded {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(attempts.enumerated()), id: \.offset) { index, attempt in
                            HStack(spacing: 6) {
                                Text("\(index + 1).")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 18, alignment: .trailing)

                                Text("\(attempt.provider) → \(attempt.modelId)")
                                    .font(.caption2)
                                    .lineLimit(1)

                                Text(attemptOutcomeLabel(attempt.outcome))
                                    .font(.caption2)
                                    .foregroundStyle(attemptOutcomeTint(attempt.outcome))

                                if let reason = attempt.reason {
                                    Text(reason.displayValue)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        if let errorMessage = request.errorMessage, !errorMessage.isEmpty {
                            HStack(spacing: 6) {
                                Text("logs.fallbackBackendResponse".localized())
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(errorMessage)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .padding(.leading, 24)
                    .padding(.top, 4)
                }
            }

            if request.requestPayloadSnippet != nil || request.sourceRaw != nil {
                Button {
                    onTogglePayload()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isPayloadExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                        Text("logs.payloadEvidence".localized(fallback: "请求证据"))
                            .font(.caption2)
                        Spacer()
                    }
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isPayloadExpanded {
                    VStack(alignment: .leading, spacing: 6) {
                        if let sourceRaw = request.sourceRaw {
                            HStack(alignment: .top, spacing: 6) {
                                Text("logs.sourceRaw".localized(fallback: "原始来源:"))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(sourceRaw)
                                    .font(.system(.caption2, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                        }

                        if let payload = request.requestPayloadSnippet {
                            Text(payload)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .lineLimit(nil)
                                .padding(8)
                                .background(Color.primary.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            Text("logs.payloadRedactedNote".localized(fallback: "已自动脱敏并截断，完整请求体不默认长期保留。"))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.leading, 24)
                    .padding(.top, 4)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("logs.requestRow".localized(fallback: "请求日志行"))
    }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: statusSymbol)
                .font(.caption2)
            Text(request.statusBadge)
                .font(.system(.caption2, design: .monospaced, weight: .bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(statusColor)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .accessibilityLabel("logs.status".localized(fallback: "状态"))
        .accessibilityValue(statusDescription + " \(request.statusBadge)")
    }

    private var statusColor: Color {
        guard let code = request.statusCode else { return .gray }
        switch code {
        case 200..<300: return Color.semanticSuccess
        case 400..<500: return Color.semanticWarning
        case 500..<600: return Color.semanticDanger
        default: return .gray
        }
    }

    private var statusSymbol: String {
        guard let code = request.statusCode else { return "questionmark.circle" }
        switch code {
        case 200..<300: return "checkmark.circle.fill"
        case 400..<500: return "exclamationmark.triangle.fill"
        case 500..<600: return "xmark.octagon.fill"
        default: return "questionmark.circle"
        }
    }

    private var statusDescription: String {
        guard let code = request.statusCode else { return "logs.status.unknown".localized(fallback: "未知") }
        switch code {
        case 200..<300: return "logs.status.success".localized(fallback: "成功")
        case 400..<500: return "logs.status.clientError".localized(fallback: "客户端错误")
        case 500..<600: return "logs.status.serverError".localized(fallback: "服务端错误")
        default: return "logs.status.unknown".localized(fallback: "未知")
        }
    }

    private func attemptOutcomeLabel(_ outcome: FallbackAttemptOutcome) -> String {
        switch outcome {
        case .failed:
            return "logs.fallbackAttempt.failed".localized()
        case .success:
            return "logs.fallbackAttempt.success".localized()
        case .skipped:
            return "logs.fallbackAttempt.skipped".localized()
        }
    }

    private func attemptOutcomeTint(_ outcome: FallbackAttemptOutcome) -> Color {
        switch outcome {
        case .failed:
            return Color.semanticWarning
        case .success:
            return Color.semanticSuccess
        case .skipped:
            return .secondary
        }
    }
}

// MARK: - Stat Item

struct StatItem: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.body, design: .rounded, weight: .semibold))
        }
    }
}

// MARK: - Log Row

struct LogRow: View {
    let entry: LogEntry
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(entry.timestamp, style: .time)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            
            Text(entry.level.rawValue.uppercased())
                .font(.system(.caption2, design: .monospaced, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(entry.level.color)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            
            Text(entry.message)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("logs.proxyLogRow".localized(fallback: "代理日志行"))
        .accessibilityValue("\(entry.level.rawValue) \(entry.message)")
    }
}

private struct StructuredLogRow: View {
    let entry: LogEntry

    private var parsed: ParsedProxyLogEntry {
        ParsedProxyLogEntry.parse(entry)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                Text(entry.timestamp, format: .dateTime.month(.twoDigits).day(.twoDigits).hour().minute().second())
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 120, alignment: .leading)

                Text(entry.level.rawValue.uppercased())
                    .font(.system(.caption2, design: .monospaced, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(entry.level.color)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                Text(parsed.source)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: 135, alignment: .leading)

                if let method = parsed.method {
                    Text(method)
                        .font(.system(.caption2, design: .monospaced, weight: .bold))
                        .foregroundStyle(method == "GET" ? Color.semanticInfo : Color.semanticAccentSecondary)
                        .frame(width: 44, alignment: .leading)
                }

                Text(parsed.path)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 8)

                if let status = parsed.statusCode {
                    Text(String(status))
                        .font(.system(.caption2, design: .monospaced, weight: .bold))
                        .foregroundStyle(status >= 500 ? Color.semanticDanger : (status >= 400 ? Color.semanticWarning : Color.semanticSuccess))
                        .frame(width: 38, alignment: .trailing)
                }

                if let duration = parsed.duration {
                    Text(duration)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 58, alignment: .trailing)
                }
            }

            if let detail = parsed.detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .padding(.leading, 132)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ParsedProxyLogEntry {
    let source: String
    let method: String?
    let path: String
    let statusCode: Int?
    let duration: String?
    let detail: String?

    static func parse(_ entry: LogEntry) -> ParsedProxyLogEntry {
        let message = entry.message
        let source = extractSource(from: message) ?? "runtime"
        let core = message.components(separatedBy: " - ").last ?? message

        // Example: GET /v1/chat/completions 200 1.3ms
        let pattern = #"(GET|POST|PUT|PATCH|DELETE)\s+(\S+)\s+(\d{3})\s+([0-9]+(?:\.[0-9]+)?(?:ms|s))"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: core, range: NSRange(core.startIndex..., in: core)),
           let methodRange = Range(match.range(at: 1), in: core),
           let pathRange = Range(match.range(at: 2), in: core),
           let statusRange = Range(match.range(at: 3), in: core),
           let durationRange = Range(match.range(at: 4), in: core) {
            let method = String(core[methodRange])
            let path = String(core[pathRange])
            let status = Int(core[statusRange])
            let duration = String(core[durationRange])
            return ParsedProxyLogEntry(
                source: source,
                method: method,
                path: path,
                statusCode: status,
                duration: duration,
                detail: core
            )
        }

        return ParsedProxyLogEntry(
            source: source,
            method: nil,
            path: core,
            statusCode: nil,
            duration: nil,
            detail: nil
        )
    }

    private static func extractSource(from message: String) -> String? {
        // Example: gin_logger.go:93
        let pattern = #"([A-Za-z0-9_\-\.]+\.go:\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)),
              let range = Range(match.range(at: 1), in: message) else {
            return nil
        }
        return String(message[range])
    }
}
