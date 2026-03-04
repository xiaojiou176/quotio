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
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @AppStorage(QuotioMotionProfileStorage.key) private var motionProfileRaw = QuotioMotionProfile.default.rawValue
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
    @State var feedback: TopFeedbackItem?
    @State private var refreshFeedbackState: ToolbarActionFeedbackState = .idle
    @State private var realtimeClearFeedbackState: ToolbarActionFeedbackState = .idle
    @State private var statsEntrancePhase = 0
    
    private var motionProfile: QuotioMotionProfile {
        QuotioMotionProfile(rawValue: motionProfileRaw) ?? .default
    }

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
                    .opacity(layerOpacity(1))
                    .offset(y: layerOffset(1))
                    
                    Divider()
                    
                    // Content
                    Group {
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
                                    Task { await runManualRefreshWithFeedback() }
                                }
                                .disabled(refreshFeedbackState == .busy)
                                .buttonStyle(.borderedProminent)
                                .motionAwareAnimation(feedbackPulseAnimation, value: refreshFeedbackState)
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
                    .id(usageContentStateID)
                    .transition(statsContentTransition)
                    .motionAwareAnimation(QuotioMotion.contentSwap, value: usageContentStateID)
                }
                .id(selectedTab)
                .transition(statsTabTransition)
                .opacity(layerOpacity(3))
                .offset(y: layerOffset(3))
            }
        }
        .navigationTitle("nav.usageStats".localized(fallback: "使用统计"))
        .overlay(alignment: .top) {
            TopFeedbackBanner(item: $feedback)
        }
        .toolbar {
            toolbarContent
        }
        .motionAwareAnimation(QuotioMotion.pageExit, value: selectedTab)
        .motionAwareAnimation(QuotioMotion.contentSwap, value: selectedTimeRange)
        .motionAwareAnimation(QuotioMotion.contentSwap, value: historySuccessFilter == nil ? "__all__" : (historySuccessFilter == true ? "__success__" : "__failed__"))
        .motionAwareAnimation(QuotioMotion.contentSwap, value: realtimeAutoScroll)
        .motionAwareAnimation(QuotioMotion.contentSwap, value: isRealtimePaused)
        .onAppear {
            runStatsEntrance()
        }
        .onChange(of: selectedTab) { _, _ in
            runStatsEntrance()
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
                    .opacity(layerOpacity(1))
                    .offset(y: layerOffset(1))
                
                // Time Distribution Chart
                if let usage = usageStats?.usage {
                    timeDistributionSection(usage: usage)
                        .opacity(layerOpacity(2))
                        .offset(y: layerOffset(2))
                }
                
                // Recent Requests
                recentRequestsSection
                    .opacity(layerOpacity(3))
                    .offset(y: layerOffset(3))
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
            .transition(statsRowTransition)
            .motionAwareAnimation(statsSummaryCardAnimation(index: 0), value: usageContentStateID)
            
            SummaryCard(
                title: "stats.successRate".localized(fallback: "成功率"),
                value: String(format: "%.1f%%", usageStats?.usage?.successRate ?? 0),
                icon: "checkmark.circle.fill",
                color: Color.semanticSuccess
            )
            .transition(statsRowTransition)
            .motionAwareAnimation(statsSummaryCardAnimation(index: 1), value: usageContentStateID)
            
            SummaryCard(
                title: "stats.totalTokens".localized(fallback: "总 Token"),
                value: (usageStats?.usage?.totalTokens ?? 0).formattedTokenCount,
                icon: "text.word.spacing",
                color: Color.semanticAccentSecondary
            )
            .transition(statsRowTransition)
            .motionAwareAnimation(statsSummaryCardAnimation(index: 2), value: usageContentStateID)
            
            SummaryCard(
                title: "stats.failedRequests".localized(fallback: "失败请求"),
                value: "\(usageStats?.usage?.failureCount ?? 0)",
                icon: "xmark.circle.fill",
                color: Color.semanticDanger
            )
            .transition(statsRowTransition)
            .motionAwareAnimation(statsSummaryCardAnimation(index: 3), value: usageContentStateID)
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
                
                if filteredRequestHistory.isEmpty {
                    Text(historyFilterIsActive
                         ? "stats.noFilteredRequests".localized(fallback: "筛选后暂无请求记录")
                         : "stats.noRequests".localized(fallback: "暂无请求记录"))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    requestHistoryHeader
                    ForEach(Array(filteredRequestHistory.prefix(20).enumerated()), id: \.element.id) { index, item in
                        RequestHistoryRow(item: item) {
                            focusOnRequestHistory(item)
                        }
                        .transition(statsRowTransition)
                        .motionAwareAnimation(statsRowAnimation(index: index), value: requestHistoryTransitionKey)
                        if item.id != filteredRequestHistory.prefix(20).last?.id {
                            Divider()
                        }
                    }
                }
            }
            .padding(.vertical, 8)
            .motionAwareAnimation(QuotioMotion.contentSwap, value: requestHistoryTransitionKey)
        }
    }
    
    // MARK: - By Account Tab
    
    private var byAccountTab: some View {
        let accountStats = extractAccountStats()
        return ScrollView {
            LazyVStack(spacing: 16) {
                if !accountStats.isEmpty {
                    ForEach(Array(accountStats.enumerated()), id: \.element.account) { index, item in
                        AccountStatsCard(account: item.account, stats: item.stats)
                            .transition(statsRowTransition)
                            .motionAwareAnimation(statsRowAnimation(index: index), value: selectedTab)
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
                    ForEach(Array(modelStats.sorted(by: { $0.requests > $1.requests }).enumerated()), id: \.element.model) { index, stat in
                        ModelStatsCard(stat: stat)
                            .transition(statsRowTransition)
                            .motionAwareAnimation(statsRowAnimation(index: index), value: selectedTab)
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
                    .motionAwareAnimation(QuotioMotion.contentSwap, value: isSSEConnected)
                Text(isSSEConnected ? "stats.connected".localized(fallback: "已连接") : "stats.disconnected".localized(fallback: "未连接"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(sseEvents.count) "+"stats.events".localized(fallback: "事件"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if lastSeenSSESeq > 0 {
                    Text(
                        "stats.realtime.seq".localizedFormat(
                            fallback: "序列号 %@",
                            String(lastSeenSSESeq)
                        )
                    )
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
                    Task { await runRealtimeClearWithFeedback() }
                }
                .buttonStyle(.borderless)
                .disabled(realtimeClearFeedbackState == .busy)
                .motionAwareAnimation(feedbackPulseAnimation, value: realtimeClearFeedbackState)
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
                List(Array(realtimeDisplayEvents.enumerated()), id: \.element.dedupeKey) { index, event in
                    SSEEventRow(event: event) {
                        focusOnRealtimeEvent(event)
                    }
                    .transition(statsRowTransition)
                    .motionAwareAnimation(statsRowAnimation(index: index), value: sseEvents.count)
                }
            }
        }
        .id(realtimeContentStateID)
        .transition(statsContentTransition)
        .motionAwareAnimation(QuotioMotion.contentSwap, value: realtimeContentStateID)
        .task {
            await connectSSE()
        }
    }
    
    // MARK: - Toolbar
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                Task { await runManualRefreshWithFeedback() }
            } label: {
                toolbarActionFeedbackGlyph(
                    state: refreshFeedbackState,
                    idleIcon: "arrow.clockwise"
                )
                .motionAwareAnimation(feedbackPulseAnimation, value: refreshFeedbackState)
            }
            .accessibilityLabel("action.refresh".localized())
            .help("action.refresh".localized())
            .disabled(isLoading || refreshFeedbackState == .busy)
            
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

    private var requestHistoryTransitionKey: String {
        [
            historySearchText,
            String(describing: historySuccessFilter),
            String(requestHistory.count)
        ].joined(separator: "|")
    }

    private var statsTabTransition: AnyTransition {
        guard !reduceMotion else { return .identity }
        let insertionOffset: CGFloat = motionProfile == .crisp ? 8 : 12
        let removalOffset: CGFloat = motionProfile == .crisp ? 6 : 10
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: insertionOffset)),
            removal: .opacity.combined(with: .offset(x: -removalOffset))
        )
    }

    private var statsContentTransition: AnyTransition {
        guard !reduceMotion else { return .identity }
        let insertionOffset: CGFloat = motionProfile == .crisp ? 8 : 12
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: insertionOffset)),
            removal: .opacity
        )
    }

    private var usageContentStateID: String {
        if isLoading && usageStats == nil {
            return "loading"
        }
        if errorMessage != nil {
            return "error"
        }
        if selectedTab == .overview {
            return "success-overview-\(selectedTimeRange.rawValue)"
        }
        return "success-\(selectedTab.rawValue)"
    }

    private var statsRowTransition: AnyTransition {
        guard !reduceMotion else { return .identity }
        let insertionOffset: CGFloat = motionProfile == .crisp ? 7 : 10
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: insertionOffset)),
            removal: .opacity
        )
    }

    private func runStatsEntrance() {
        let contentSwapDelay: Double = motionProfile == .crisp ? 0.06 : 0.08
        let springDelay: Double = motionProfile == .crisp ? 0.12 : 0.16
        guard !reduceMotion else {
            statsEntrancePhase = 3
            return
        }
        statsEntrancePhase = 0
        withMotionAwareAnimation(QuotioMotion.pageEnter, reduceMotion: reduceMotion) {
            statsEntrancePhase = 1
        }
        withMotionAwareAnimation(QuotioMotion.contentSwap.delay(contentSwapDelay), reduceMotion: reduceMotion) {
            statsEntrancePhase = 2
        }
        withMotionAwareAnimation(QuotioMotion.gentleSpring.delay(springDelay), reduceMotion: reduceMotion) {
            statsEntrancePhase = 3
        }
    }

    private func layerOpacity(_ phase: Int) -> Double {
        reduceMotion || statsEntrancePhase >= phase ? 1 : 0
    }

    private func layerOffset(_ phase: Int) -> CGFloat {
        guard !reduceMotion, statsEntrancePhase < phase else { return 0 }
        let base: CGFloat = motionProfile == .crisp ? 7 : 9
        let step: CGFloat = motionProfile == .crisp ? 1.5 : 2
        return base + CGFloat(phase) * step
    }

    private func statsRowAnimation(index: Int) -> Animation? {
        guard !reduceMotion else { return nil }
        let step = motionProfile == .crisp ? 0.016 : 0.024
        return QuotioMotion.contentSwap.delay(Double(min(index, 10)) * step)
    }

    private func statsSummaryCardAnimation(index: Int) -> Animation? {
        guard !reduceMotion else { return nil }
        let step = motionProfile == .crisp ? 0.02 : 0.03
        return QuotioMotion.contentSwap.delay(Double(min(index, 3)) * step)
    }

    private var realtimeContentStateID: String {
        sseEvents.isEmpty ? "realtime-empty" : "realtime-content"
    }

    @ViewBuilder
    private func toolbarActionFeedbackGlyph(
        state: ToolbarActionFeedbackState,
        idleIcon: String
    ) -> some View {
        ZStack {
            SmallProgressView()
                .opacity(state == .busy ? 1 : 0)
            Image(systemName: "checkmark")
                .foregroundStyle(Color.semanticSuccess)
                .opacity(state == .success ? 1 : 0)
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.semanticDanger)
                .opacity(state == .failure ? 1 : 0)
            Image(systemName: idleIcon)
                .opacity(state == .idle ? 1 : 0)
        }
        .frame(width: 16, height: 16)
    }

    private func runRealtimeClearWithFeedback() async {
        await MainActor.run {
            realtimeClearFeedbackState = .busy
        }
        await MainActor.run {
            sseEvents.removeAll()
            sseEventKeys.removeAll()
            lastSeenSSESeq = 0
            realtimeClearFeedbackState = .success
        }
        let resetDelay = max(1, feedbackPulseMilliseconds / 2)
        try? await Task.sleep(for: .milliseconds(resetDelay))
        await MainActor.run {
            if realtimeClearFeedbackState != .busy {
                realtimeClearFeedbackState = .idle
            }
        }
    }

    private func runManualRefreshWithFeedback() async {
        await MainActor.run {
            refreshFeedbackState = .busy
        }
        await manualRefreshStats()
        await MainActor.run {
            let hasError = !(errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            refreshFeedbackState = hasError ? .failure : .success
        }
        try? await Task.sleep(for: .milliseconds(feedbackPulseMilliseconds))
        await MainActor.run {
            if refreshFeedbackState == .success || refreshFeedbackState == .failure {
                refreshFeedbackState = .idle
            }
        }
    }
    
}
