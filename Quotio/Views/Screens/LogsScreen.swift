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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(QuotioMotionProfileStorage.key) private var motionProfileRaw = QuotioMotionProfile.default.rawValue
    @State private var featureFlags = FeatureFlagManager.shared
    @State private var uiMetrics = UIBaselineMetricsTracker.shared
    @State private var selectedTab: LogsTab = .requests
    @State private var autoScroll = false
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
    @State private var feedback: TopFeedbackItem?
    @State private var showClearConfirmation = false
    @State private var refreshFeedbackState: ToolbarActionFeedbackState = .idle
    @State private var clearFeedbackState: ToolbarActionFeedbackState = .idle
    @State private var logsEntrancePhase = 0

    private enum ToolbarActionFeedbackState: Equatable {
        case idle
        case busy
        case success
        case failure
    }

    private var feedbackPulseMilliseconds: Int {
        TopFeedbackRhythm.pulseMilliseconds(reduceMotion: reduceMotion, profile: motionProfile)
    }

    private var feedbackPulseAnimation: Animation {
        TopFeedbackRhythm.pulseAnimation(reduceMotion: reduceMotion, profile: motionProfile)
    }
    
    private var motionProfile: QuotioMotionProfile {
        QuotioMotionProfile(rawValue: motionProfileRaw) ?? .default
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
                    .opacity(layerOpacity(1))
                    .offset(y: layerOffset(1))
                    
                    Divider()
                    
                    // Tab Content
                    Group {
                        switch selectedTab {
                        case .requests:
                            requestHistoryView
                        case .proxyLogs:
                            proxyLogsView
                        }
                    }
                    .id(selectedTab)
                    .transition(logsTabTransition)
                    .opacity(layerOpacity(3))
                    .offset(y: layerOffset(3))
                }
                .motionAwareAnimation(QuotioMotion.pageEnter, value: selectedTab)
                .motionAwareAnimation(QuotioMotion.pageExit, value: selectedTab)
            }
        }
        .navigationTitle("nav.logs".localized())
        .overlay(alignment: .top) {
            TopFeedbackBanner(item: $feedback)
        }
        .searchable(text: $searchText, prompt: searchPrompt)
        .confirmationDialog(
            "logs.confirm.clear.title".localized(fallback: "确认清空日志"),
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("action.delete".localized(fallback: "删除"), role: .destructive) {
                Task { await clearCurrentTabWithFeedback() }
            }
            Button("action.cancel".localized(fallback: "取消"), role: .cancel) {}
        } message: {
            Text(
                selectedTab == .requests
                ? "logs.confirm.clear.requests".localized(fallback: "将清空全部请求日志，此操作无法撤销。")
                : "logs.confirm.clear.proxy".localized(fallback: "将清空全部代理日志，此操作无法撤销。")
            )
        }
        .toolbar {
            toolbarContent
        }
        .motionAwareAnimation(QuotioMotion.contentSwap, value: requestFilterProvider ?? "__all__")
        .motionAwareAnimation(QuotioMotion.contentSwap, value: requestSourceFilter ?? "__all__")
        .motionAwareAnimation(QuotioMotion.contentSwap, value: requestStatusFilter)
        .motionAwareAnimation(QuotioMotion.contentSwap, value: fallbackOnly)
        .motionAwareAnimation(QuotioMotion.contentSwap, value: proxyLogViewMode)
        .motionAwareAnimation(QuotioMotion.contentSwap, value: String(describing: filterLevel))
        .motionAwareAnimation(QuotioMotion.pageExit, value: requestFiltersTransitionKey)
        .onAppear {
            runLogsEntrance()
        }
        .onChange(of: selectedTab) { _, _ in
            runLogsEntrance()
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
        .id(requestHistoryContentStateID)
        .transition(logsContentTransition)
        .motionAwareAnimation(QuotioMotion.contentSwap, value: requestHistoryContentStateID)
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
            .frame(minWidth: 112, idealWidth: 140, maxWidth: 180)

            Picker("logs.source".localized(fallback: "来源"), selection: $requestSourceFilter) {
                Text("logs.all".localized(fallback: "全部")).tag(nil as String?)
                Divider()
                ForEach(availableRequestSources, id: \.self) { source in
                    Text(source).tag(source as String?)
                }
            }
            .pickerStyle(.menu)
            .frame(minWidth: 104, idealWidth: 130, maxWidth: 170)

            Picker("logs.status".localized(fallback: "状态"), selection: $requestStatusFilter) {
                ForEach(RequestStatusFilter.allCases) { filter in
                    Text(filter.label).tag(filter)
                }
            }
            .pickerStyle(.menu)
            .frame(minWidth: 96, idealWidth: 120, maxWidth: 160)

            Toggle("logs.fallbackOnly".localized(fallback: "仅看回退"), isOn: $fallbackOnly)
                .toggleStyle(.switch)
        }
        .padding()
        .background(.regularMaterial)
        .motionAwareAnimation(QuotioMotion.contentSwap, value: requestFiltersTransitionKey)
        .opacity(layerOpacity(2))
        .offset(y: layerOffset(2))
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
                    List(Array(filteredRequests.enumerated()), id: \.element.id) { index, request in
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
                        .transition(logsRowTransition)
                        .motionAwareAnimation(logsRowAnimation(index: index), value: requestFiltersTransitionKey)
                    }
                    .onChange(of: viewModel.requestTracker.requestHistory.count) { _, _ in
                        if autoScroll, let first = filteredRequests.first {
                            withMotionAwareAnimation(QuotioMotion.contentSwap, reduceMotion: reduceMotion) {
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
            Log.error("[LogsScreen] Failed to refresh usage evidence: \(error.localizedDescription)")
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
        .id(proxyLogsContentStateID)
        .transition(logsContentTransition)
        .motionAwareAnimation(QuotioMotion.contentSwap, value: proxyLogsContentStateID)
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
                    withMotionAwareAnimation(QuotioMotion.contentSwap, reduceMotion: reduceMotion) {
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
                .frame(minWidth: 120, idealWidth: 160, maxWidth: 220)

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
                Task { await refreshCurrentTabWithFeedback() }
            } label: {
                ZStack {
                    SmallProgressView()
                        .opacity(refreshFeedbackState == .busy ? 1 : 0)
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.semanticSuccess)
                        .scaleEffect((refreshFeedbackState == .success && !reduceMotion) ? 1.08 : 1)
                        .opacity(refreshFeedbackState == .success ? 1 : 0)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.semanticDanger)
                        .scaleEffect((refreshFeedbackState == .failure && !reduceMotion) ? 1.06 : 1)
                        .opacity(refreshFeedbackState == .failure ? 1 : 0)
                    Image(systemName: "arrow.clockwise")
                        .opacity(refreshFeedbackState == .idle ? 1 : 0)
                }
                .frame(width: 16, height: 16)
                .motionAwareAnimation(feedbackPulseAnimation, value: refreshFeedbackState)
            }
            .buttonStyle(.toolbarIcon)
            .accessibilityLabel("action.refresh".localized())
            .help("action.refresh".localized())
            .disabled(refreshFeedbackState == .busy || (selectedTab == .proxyLogs && logsViewModel.isRefreshing))
            
            Button(role: .destructive) {
                showClearConfirmation = true
            } label: {
                ZStack {
                    SmallProgressView()
                        .opacity(clearFeedbackState == .busy ? 1 : 0)
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.semanticSuccess)
                        .scaleEffect((clearFeedbackState == .success && !reduceMotion) ? 1.08 : 1)
                        .opacity(clearFeedbackState == .success ? 1 : 0)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.semanticDanger)
                        .scaleEffect((clearFeedbackState == .failure && !reduceMotion) ? 1.06 : 1)
                        .opacity(clearFeedbackState == .failure ? 1 : 0)
                    Image(systemName: "trash")
                        .opacity(clearFeedbackState == .idle ? 1 : 0)
                }
                .frame(width: 16, height: 16)
                .motionAwareAnimation(feedbackPulseAnimation, value: clearFeedbackState)
            }
            .buttonStyle(.toolbarIcon)
            .accessibilityLabel("action.delete".localized())
            .help("action.delete".localized())
            .disabled(
                clearFeedbackState == .busy ||
                (selectedTab == .requests && viewModel.requestTracker.requestHistory.isEmpty) ||
                (selectedTab == .proxyLogs && logsViewModel.logs.isEmpty)
            )

            if selectedTab == .requests {
                Button {
                    exportRequestAuditPackage()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.toolbarIcon)
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
                showFeedback(
                    "logs.feedback.auditExported".localized(fallback: "审计包已导出") + ": " + url.lastPathComponent
                )
            }
        } catch {
            Log.error("[LogsScreen] Failed to export request audit package: \(error.localizedDescription)")
            uiMetrics.mark("logs.audit_export_failed", metadata: error.localizedDescription)
            showFeedback(
                "logs.feedback.auditExportFailed".localized(fallback: "审计包导出失败") + ": " + error.localizedDescription,
                isError: true
            )
        }
    }

    private func refreshCurrentTabWithFeedback() async {
        await MainActor.run {
            refreshFeedbackState = .busy
        }
        if selectedTab == .requests {
            if featureFlags.enhancedObservability {
                await refreshUsageHistoryEvidence()
                await MainActor.run {
                    lastEvidenceRefreshAt = Date()
                    showFeedback("logs.feedback.requestsRefreshed".localized(fallback: "请求证据已刷新"))
                    refreshFeedbackState = .success
                }
            } else {
                await MainActor.run {
                    showFeedback("logs.feedback.requestsAuto".localized(fallback: "请求日志由代理实时采集，无需手动刷新"))
                    refreshFeedbackState = .success
                }
            }
            await clearToolbarFeedbackStateAfterDelay(for: .refresh)
            return
        }

        await logsViewModel.refreshLogs()
        await MainActor.run {
            if let error = normalizedErrorMessage(logsViewModel.refreshError), logsViewModel.logs.isEmpty {
                showFeedback(
                    "logs.feedback.refreshFailed".localized(fallback: "日志刷新失败") + ": " + error,
                    isError: true
                )
                refreshFeedbackState = .failure
                return
            }
            showFeedback("logs.feedback.refreshed".localized(fallback: "日志已刷新"))
            refreshFeedbackState = .success
        }
        await clearToolbarFeedbackStateAfterDelay(for: .refresh)
    }

    private func clearCurrentTabWithFeedback() async {
        await MainActor.run {
            clearFeedbackState = .busy
        }
        if selectedTab == .requests {
            let clearedCount = viewModel.requestTracker.requestHistory.count
            viewModel.requestTracker.clearHistory()
            await MainActor.run {
                let feedback = LogsClearFeedbackResolver.requestsFeedback(clearedCount: clearedCount)
                showFeedback(feedback.message, isError: feedback.isError)
                clearFeedbackState = feedback.isError ? .failure : .success
            }
            await clearToolbarFeedbackStateAfterDelay(for: .clear)
            return
        }

        await logsViewModel.clearLogs()
        await MainActor.run {
            let feedback = LogsClearFeedbackResolver.proxyFeedback(
                rawRefreshError: logsViewModel.refreshError
            )
            showFeedback(feedback.message, isError: feedback.isError)
            clearFeedbackState = feedback.isError ? .failure : .success
        }
        await clearToolbarFeedbackStateAfterDelay(for: .clear)
    }

    private enum ToolbarFeedbackTarget {
        case refresh
        case clear
    }

    private func clearToolbarFeedbackStateAfterDelay(for target: ToolbarFeedbackTarget) async {
        try? await Task.sleep(for: .milliseconds(feedbackPulseMilliseconds))
        await MainActor.run {
            switch target {
            case .refresh:
                if refreshFeedbackState == .success || refreshFeedbackState == .failure {
                    refreshFeedbackState = .idle
                }
            case .clear:
                if clearFeedbackState == .success || clearFeedbackState == .failure {
                    clearFeedbackState = .idle
                }
            }
        }
    }

    private func normalizedErrorMessage(_ message: String?) -> String? {
        guard let text = message?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        return text
    }

    private func showFeedback(_ message: String, isError: Bool = false) {
        let item = isError ? TopFeedbackItem.error(message) : TopFeedbackItem.success(message)
        withMotionAwareAnimation(
            TopFeedbackRhythm.pulseAnimation(reduceMotion: reduceMotion, profile: motionProfile),
            reduceMotion: reduceMotion
        ) {
            feedback = item
        }
    }

    private var requestFiltersTransitionKey: String {
        [
            requestFilterProvider ?? "__all__",
            requestSourceFilter ?? "__all__",
            String(describing: requestStatusFilter),
            fallbackOnly ? "fallback" : "all",
            searchText
        ].joined(separator: "|")
    }

    private var logsTabTransition: AnyTransition {
        guard !reduceMotion else { return .identity }
        let insertionOffset: CGFloat = motionProfile == .crisp ? 8 : 12
        let removalOffset: CGFloat = motionProfile == .crisp ? 6 : 10
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: insertionOffset)),
            removal: .opacity.combined(with: .offset(x: -removalOffset))
        )
    }

    private var logsContentTransition: AnyTransition {
        guard !reduceMotion else { return .identity }
        let insertionOffset: CGFloat = motionProfile == .crisp ? 8 : 12
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: insertionOffset)),
            removal: .opacity
        )
    }

    private var requestHistoryContentStateID: String {
        if viewModel.requestTracker.requestHistory.isEmpty {
            return "requests-empty"
        }
        if filteredRequests.isEmpty {
            return "requests-filtered-empty-\(requestFiltersTransitionKey)"
        }
        return "requests-success-\(requestFiltersTransitionKey)"
    }

    private var proxyLogsContentStateID: String {
        switch proxyLogsContentState {
        case .loading:
            return "proxy-loading"
        case .error:
            return "proxy-error"
        case .empty:
            return "proxy-empty-\(proxyLogsFilterTransitionKey)"
        case .success:
            return "proxy-success-\(proxyLogsFilterTransitionKey)"
        }
    }

    private var logsRowTransition: AnyTransition {
        guard !reduceMotion else { return .identity }
        let insertionOffset: CGFloat = motionProfile == .crisp ? 7 : 10
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: insertionOffset)),
            removal: .opacity
        )
    }

    private func runLogsEntrance() {
        let contentSwapDelay: Double = motionProfile == .crisp ? 0.06 : 0.08
        let springDelay: Double = motionProfile == .crisp ? 0.12 : 0.16
        guard !reduceMotion else {
            logsEntrancePhase = 3
            return
        }
        logsEntrancePhase = 0
        withMotionAwareAnimation(QuotioMotion.pageEnter, reduceMotion: reduceMotion) {
            logsEntrancePhase = 1
        }
        withMotionAwareAnimation(QuotioMotion.contentSwap.delay(contentSwapDelay), reduceMotion: reduceMotion) {
            logsEntrancePhase = 2
        }
        withMotionAwareAnimation(QuotioMotion.gentleSpring.delay(springDelay), reduceMotion: reduceMotion) {
            logsEntrancePhase = 3
        }
    }

    private func layerOpacity(_ phase: Int) -> Double {
        reduceMotion || logsEntrancePhase >= phase ? 1 : 0
    }

    private func layerOffset(_ phase: Int) -> CGFloat {
        guard !reduceMotion, logsEntrancePhase < phase else { return 0 }
        let base: CGFloat = motionProfile == .crisp ? 7 : 9
        let step: CGFloat = motionProfile == .crisp ? 1.5 : 2
        return base + CGFloat(phase) * step
    }

    private func logsRowAnimation(index: Int) -> Animation? {
        guard !reduceMotion else { return nil }
        let step = motionProfile == .crisp ? 0.016 : 0.024
        return QuotioMotion.contentSwap.delay(Double(min(index, 10)) * step)
    }

    private var proxyLogsFilterTransitionKey: String {
        [
            String(describing: filterLevel),
            proxyLogViewMode.rawValue,
            searchText
        ].joined(separator: "|")
    }
}

enum LogsClearFeedbackResolver {
    static func requestsFeedback(clearedCount: Int) -> (message: String, isError: Bool) {
        (
            "logs.feedback.requestsCleared".localized(fallback: "请求日志已清空") + " (\(clearedCount))",
            false
        )
    }

    static func proxyFeedback(rawRefreshError: String?) -> (message: String, isError: Bool) {
        if let error = normalizedErrorMessage(rawRefreshError) {
            return (
                "logs.feedback.clearFailed".localized(fallback: "日志清空失败") + ": " + error,
                true
            )
        }
        return ("logs.feedback.cleared".localized(fallback: "代理日志已清空"), false)
    }

    static func normalizedErrorMessage(_ message: String?) -> String? {
        guard let text = message?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        return text
    }
}

// MARK: - Request Row
