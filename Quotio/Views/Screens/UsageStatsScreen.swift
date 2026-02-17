//
//  UsageStatsScreen.swift
//  Quotio - Usage Statistics Dashboard
//
//  Comprehensive usage statistics with real-time updates,
//  historical data visualization, and per-account/model breakdown.
//

import SwiftUI
import Charts

struct UsageStatsScreen: View {
    @Environment(QuotaViewModel.self) var viewModel
    @State var featureFlags = FeatureFlagManager.shared
    @State var uiMetrics = UIBaselineMetricsTracker.shared
    @State var usageStats: UsageStats?
    @State var requestHistory: [RequestHistoryItem] = []
    @State var isLoading = false
    @State var errorMessage: String?
    @State var selectedTimeRange: TimeRange = .day
    @State var selectedTab: StatsTab = .overview
    @State var historySearchText = ""
    @State var historySuccessFilter: Bool? = nil
    @State var sseEvents: [SSERequestEvent] = []
    @State var sseEventKeys: Set<String> = []
    @State var lastSeenSSESeq: Int64 = 0
    @State var isSSEConnected = false
    @State var isRealtimePaused = false
    @State var realtimeAutoScroll = true
    @State var isSSEStreamActive = false
    @State var pollingTask: Task<Void, Never>?
    @State var feedbackMessage: String?
    @State var feedbackIsError = false
    @State var feedbackDismissTask: Task<Void, Never>?
    
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
        .overlay(alignment: .top) {
            if let feedbackMessage {
                HStack(spacing: 8) {
                    Image(systemName: feedbackIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(feedbackIsError ? Color.semanticDanger : Color.semanticSuccess)
                    Text(feedbackMessage)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(2)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.regularMaterial, in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder((feedbackIsError ? Color.semanticDanger : Color.semanticSuccess).opacity(0.2), lineWidth: 1)
                )
                .shadow(color: Color.primary.opacity(0.1), radius: 8, x: 0, y: 3)
                .padding(.top, 8)
                .padding(.horizontal, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .accessibilityElement(children: .combine)
                .accessibilityLabel(feedbackMessage)
            }
        }
        .toolbar {
            toolbarContent
        }
        .task {
            await loadStats()
            startPolling()
        }
        .onDisappear {
            stopPolling()
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
                if lastSeenSSESeq > 0 {
                    Text("seq \(lastSeenSSESeq)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
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
                    sseEventKeys.removeAll()
                    lastSeenSSESeq = 0
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
                List(realtimeDisplayEvents, id: \.dedupeKey) { event in
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
                Task { await manualRefreshStats() }
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
                    Task { await importStats() }
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel("stats.exportMenu".localized(fallback: "导出菜单"))
            .help("stats.exportMenu".localized(fallback: "打开导出/导入菜单"))
        }
    }
    
}
