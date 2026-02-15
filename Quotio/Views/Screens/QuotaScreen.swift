//
//  QuotaScreen.swift
//  Quotio
//

import SwiftUI

// MARK: - Sort Option

enum AccountSortOption: String, CaseIterable, Identifiable {
    case name = "name"
    case status = "status"
    case quotaLow = "quotaLow"
    case quotaHigh = "quotaHigh"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .name: return "quota.sort.name".localized(fallback: "按名称")
        case .status: return "quota.sort.status".localized(fallback: "按状态")
        case .quotaLow: return "quota.sort.quotaLow".localized(fallback: "额度低→高")
        case .quotaHigh: return "quota.sort.quotaHigh".localized(fallback: "额度高→低")
        }
    }
    
    var icon: String {
        switch self {
        case .name: return "textformat.abc"
        case .status: return "circle.grid.2x1"
        case .quotaLow: return "arrow.up.right"
        case .quotaHigh: return "arrow.down.right"
        }
    }
}

enum AccountStatusFilter: String, CaseIterable, Identifiable {
    case all = "all"
    case ready = "ready"
    case cooling = "cooling"
    case error = "error"
    case disabled = "disabled"
    case quota5h = "quota5h"
    case quota7d = "quota7d"
    case fatalDisabled = "fatalDisabled"
    case networkError = "networkError"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "logs.all".localized(fallback: "全部")
        case .ready: return "quota.status.ready".localized(fallback: "可用")
        case .cooling: return "quota.status.cooling".localized(fallback: "冷却中")
        case .error: return "quota.status.error".localized(fallback: "错误")
        case .disabled: return "quota.status.disabled".localized(fallback: "禁用")
        case .quota5h: return "quota.status.quota5h".localized(fallback: "5h 冷却")
        case .quota7d: return "quota.status.quota7d".localized(fallback: "7d 冷却")
        case .fatalDisabled: return "quota.status.fatalDisabled".localized(fallback: "致命禁用")
        case .networkError: return "quota.status.networkError".localized(fallback: "网络抖动")
        }
    }

    var icon: String {
        switch self {
        case .all: return "line.3.horizontal.decrease.circle"
        case .ready: return "checkmark.circle.fill"
        case .cooling: return "clock.badge.exclamationmark"
        case .error: return "xmark.circle.fill"
        case .disabled: return "minus.circle.fill"
        case .quota5h: return "clock.arrow.circlepath"
        case .quota7d: return "calendar.badge.clock"
        case .fatalDisabled: return "exclamationmark.octagon.fill"
        case .networkError: return "wifi.exclamationmark"
        }
    }
}

private enum CodexRoutingBucket: String, CaseIterable, Identifiable {
    case main
    case tokenInvalidated
    case quota5h
    case quota7d

    var id: String { rawValue }

    var label: String {
        switch self {
        case .main:
            return "codex.bucket.main".localized(fallback: "可用")
        case .tokenInvalidated:
            return "codex.bucket.tokenInvalidated".localized(fallback: "需重登")
        case .quota5h:
            return "codex.bucket.quota5h".localized(fallback: "5h 冷却")
        case .quota7d:
            return "codex.bucket.quota7d".localized(fallback: "7d 冷却")
        }
    }

    var color: Color {
        switch self {
        case .main: return Color.semanticSuccess
        case .tokenInvalidated: return Color.semanticDanger
        case .quota5h: return Color.semanticWarning
        case .quota7d: return Color.semanticAccentSecondary
        }
    }
}

struct QuotaScreen: View {
    @Environment(QuotaViewModel.self) private var viewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var modeManager = OperatingModeManager.shared

    @State private var selectedProvider: AIProvider?
    @State private var settings = MenuBarSettingsManager.shared
    @State private var uiExperience = UIExperienceSettingsManager.shared
    @State private var featureFlags = FeatureFlagManager.shared
    @State private var uiMetrics = UIBaselineMetricsTracker.shared
    @State private var searchText: String = ""
    @State private var sortOption: AccountSortOption = .name
    @State private var prioritizeAnomalies = true
    @State private var accountStatusFilter: AccountStatusFilter = .all
    @State private var compactAccountView = false
    
    // MARK: - Data Sources
    
    /// All providers with quota data (unified from both proxy and direct sources)
    private var availableProviders: [AIProvider] {
        var providers = Set<AIProvider>()
        
        // From proxy auth files
        for file in viewModel.authFiles {
            if let provider = file.providerType {
                providers.insert(provider)
            }
        }
        
        // From direct quota data
        for provider in viewModel.providerQuotas.keys {
            providers.insert(provider)
        }
        
        let sorted = providers.sorted { $0.displayName < $1.displayName }
        guard featureFlags.enhancedUILayout, prioritizeAnomalies else { return sorted }
        return sorted.sorted { lhs, rhs in
            let lhsSeverity = providerSeverity(lhs)
            let rhsSeverity = providerSeverity(rhs)
            if lhsSeverity != rhsSeverity {
                return lhsSeverity > rhsSeverity
            }
            return lhs.displayName < rhs.displayName
        }
    }

    private func providerSeverity(_ provider: AIProvider) -> Int {
        let accountQuotas = viewModel.providerQuotas[provider] ?? [:]
        let errorCount = accountQuotas.values.filter { $0.isForbidden }.count
        let lowQuotaCount = accountQuotas.values.filter { quota in
            let models = quota.models.map { (name: $0.name, percentage: $0.percentage) }
            let percent = settings.totalUsagePercent(models: models)
            return percent >= 0 && percent < 20
        }.count
        return errorCount * 5 + lowQuotaCount * 2 + max(0, accountCount(for: provider) / 10)
    }
    
    /// Get account count for a provider
    private func accountCount(for provider: AIProvider) -> Int {
        var accounts = Set<String>()
        
        // From auth files
        for file in viewModel.authFiles where file.providerType == provider {
            accounts.insert(file.quotaLookupKey)
        }
        
        // From quota data
        if let quotaAccounts = viewModel.providerQuotas[provider] {
            for key in quotaAccounts.keys {
                accounts.insert(key)
            }
        }
        
        return accounts.count
    }
    
    private func lowestQuotaPercent(for provider: AIProvider) -> Double? {
        guard let accounts = viewModel.providerQuotas[provider] else { return nil }
        
        var allTotals: [Double] = []
        for (_, quotaData) in accounts {
            let models = quotaData.models.map { (name: $0.name, percentage: $0.percentage) }
            let total = settings.totalUsagePercent(models: models)
            if total >= 0 {
                allTotals.append(total)
            }
        }
        
        return allTotals.min()
    }
    
    /// Check if we have any data to show
    private var hasAnyData: Bool {
        if modeManager.isMonitorMode {
            return !viewModel.providerQuotas.isEmpty || !viewModel.directAuthFiles.isEmpty
        }
        return !viewModel.authFiles.isEmpty || !viewModel.providerQuotas.isEmpty
    }
    
    var body: some View {
        Group {
            if !hasAnyData {
                ContentUnavailableView(
                    "empty.noAccounts".localized(),
                    systemImage: "person.crop.circle.badge.questionmark",
                    description: Text("empty.addProviderAccounts".localized())
                )
            } else {
                mainContent
            }
        }
        .navigationTitle("nav.quota".localized())
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                    Menu {
                        // Display Style
                        Picker(selection: Binding(
                            get: { settings.quotaDisplayStyle },
                            set: { settings.quotaDisplayStyle = $0 }
                        )) {
                            ForEach(QuotaDisplayStyle.allCases) { style in
                                Label(style.localizationKey.localized(), systemImage: style.iconName)
                                    .tag(style)
                            }
                        } label: {
                            Text("settings.quota.displayStyle".localized())
                        }
                        .pickerStyle(.inline)
                        
                        Divider()
                        
                        // Display Mode (Used vs Remaining)
                        Picker(selection: Binding(
                            get: { settings.quotaDisplayMode },
                            set: { settings.quotaDisplayMode = $0 }
                        )) {
                            ForEach(QuotaDisplayMode.allCases) { mode in
                                Text(mode.localizationKey.localized())
                                    .tag(mode)
                            }
                        } label: {
                            Text("display_mode".localized())
                        }
                        .pickerStyle(.inline)
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel("quota.displayMode".localized(fallback: "显示模式"))
                    .help("quota.displayMode".localized(fallback: "切换显示模式"))
                }
                
                ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        await viewModel.refreshQuotasUnified()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("action.refresh".localized())
                .help("action.refresh".localized())
                .disabled(viewModel.isLoadingQuotas)
            }
        }
        .onAppear {
            if selectedProvider == nil, let first = availableProviders.first {
                selectedProvider = first
            }
        }
        .onChange(of: availableProviders) { _, newProviders in
            if selectedProvider == nil || !newProviders.contains(selectedProvider!) {
                selectedProvider = newProviders.first
            }
        }
    }
    
    // MARK: - Health Statistics
    
    private var healthStats: (total: Int, ready: Int, cooling: Int, error: Int) {
        var total = 0
        var ready = 0
        var cooling = 0
        var error = 0
        
        // First, try to use authFiles if available (from management API)
        if !viewModel.authFiles.isEmpty {
            for file in viewModel.authFiles {
                total += 1
                switch file.status {
                case "ready":
                    if !file.disabled { ready += 1 }
                case "cooling":
                    cooling += 1
                case "error", "expired":
                    error += 1
                default:
                    // For unknown status, check quota data to infer status
                    if let providerType = file.providerType,
                       let quotas = viewModel.providerQuotas[providerType],
                       let quota = quotas[file.quotaLookupKey] {
                        if quota.isForbidden {
                            error += 1
                        } else if quota.models.allSatisfy({ $0.percentage <= 5 }) {
                            cooling += 1
                        } else {
                            ready += 1
                        }
                    } else {
                        ready += 1 // Assume ready if no data
                    }
                }
            }
        } else {
            // Fallback: count accounts from providerQuotas when authFiles is empty
            for (_, accountQuotas) in viewModel.providerQuotas {
                for (_, quota) in accountQuotas {
                    total += 1
                    if quota.isForbidden {
                        error += 1
                    } else if quota.models.allSatisfy({ $0.percentage <= 5 }) {
                        cooling += 1
                    } else {
                        ready += 1
                    }
                }
            }
        }
        
        return (total, ready, cooling, error)
    }
    
    private var healthScore: Int {
        let stats = healthStats
        guard stats.total > 0 else { return 0 }
        
        // Calculate health score: ready accounts contribute positively, cooling/error negatively
        let readyRatio = Double(stats.ready) / Double(stats.total)
        let coolingPenalty = Double(stats.cooling) / Double(stats.total) * 0.3
        let errorPenalty = Double(stats.error) / Double(stats.total) * 0.5
        
        let score = Int((readyRatio - coolingPenalty - errorPenalty) * 100)
        return max(0, min(100, score))
    }
    
    // MARK: - Main Content
    
    private var mainContent: some View {
        VStack(spacing: 0) {
            // Health Dashboard
            if viewModel.authFiles.count > 0 {
                healthDashboard
                    .padding(.horizontal, uiExperience.informationDensity.horizontalPadding)
                    .padding(.top, uiExperience.informationDensity.verticalSpacing)
            }

            if featureFlags.enhancedUILayout && viewModel.authFiles.count > 0 {
                anomalyQuickSection
                    .padding(.horizontal, uiExperience.informationDensity.horizontalPadding)
                    .padding(.top, 10)
            }
            
            // Search Bar (only show if there are multiple accounts)
            if viewModel.authFiles.count > 3 {
                searchBar
                    .padding(.horizontal, uiExperience.informationDensity.horizontalPadding)
                    .padding(.top, 12)
            }
            
            // Provider Segmented Control
            if availableProviders.count > 1 {
                providerSegmentedControl
                    .padding(.horizontal, uiExperience.informationDensity.horizontalPadding)
                    .padding(.top, 12)
                    .padding(.bottom, 12)
            }
            
            // Selected Provider Content
            ScrollView {
                if let provider = selectedProvider ?? availableProviders.first {
                    ProviderQuotaView(
                        provider: provider,
                        authFiles: viewModel.authFiles.filter { $0.providerType == provider },
                        quotaData: viewModel.providerQuotas[provider] ?? [:],
                        subscriptionInfos: viewModel.subscriptionInfos[provider] ?? [:],
                        isLoading: viewModel.isLoadingQuotas,
                        searchFilter: searchText,
                        sortOption: sortOption,
                        statusFilter: accountStatusFilter,
                        compactMode: compactAccountView
                    )
                    .padding(.horizontal, uiExperience.informationDensity.horizontalPadding)
                    .padding(.vertical, 16)
                } else {
                    ContentUnavailableView(
                        "empty.noQuotaData".localized(),
                        systemImage: "chart.bar.xaxis",
                        description: Text("empty.refreshToLoad".localized())
                    )
                    .padding(24)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .onAppear {
            uiMetrics.mark(
                "quota.screen.appear",
                metadata: "providers=\(availableProviders.count),accounts=\(viewModel.authFiles.count)"
            )
        }
    }
    
    // MARK: - Search Bar
    
    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.caption)
            
            TextField("quota.search.placeholder".localized(fallback: "搜索账号..."), text: $searchText)
                .textFieldStyle(.plain)
                .font(.subheadline)
            
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("action.clear".localized(fallback: "清空搜索"))
                .help("action.clear".localized(fallback: "清空搜索"))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private var anomalyQuickSection: some View {
        let stats = healthStats
        return HStack(spacing: 8) {
            anomalyChip(title: "quota.health.error".localized(fallback: "错误"), value: stats.error, color: Color.semanticDanger, filter: .error)
            anomalyChip(title: "quota.health.cooling".localized(fallback: "冷却中"), value: stats.cooling, color: Color.semanticWarning, filter: .cooling)
            anomalyChip(title: "quota.status.disabled".localized(fallback: "禁用"), value: viewModel.authFiles.filter { $0.disabled }.count, color: .secondary, filter: .disabled)
            anomalyChip(title: "quota.status.quota5h.short".localized(fallback: "5h"), value: viewModel.authFiles.filter { $0.isQuotaLimited5h }.count, color: Color.semanticWarning, filter: .quota5h)
            anomalyChip(title: "quota.status.quota7d.short".localized(fallback: "7d"), value: viewModel.authFiles.filter { $0.isQuotaLimited7d }.count, color: Color.semanticAccentSecondary, filter: .quota7d)
            anomalyChip(title: "quota.status.fatal.short".localized(fallback: "致命"), value: viewModel.authFiles.filter { $0.isFatalDisabled }.count, color: Color.semanticDanger, filter: .fatalDisabled)
            anomalyChip(title: "quota.status.network.short".localized(fallback: "网络"), value: viewModel.authFiles.filter { $0.isNetworkError }.count, color: Color.semanticInfo, filter: .networkError)
            Spacer()
            Button("logs.all".localized(fallback: "查看全部")) {
                accountStatusFilter = .all
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
    }

    private func anomalyChip(title: String, value: Int, color: Color, filter: AccountStatusFilter) -> some View {
        Button {
            accountStatusFilter = filter
        } label: {
            HStack(spacing: 6) {
                Image(systemName: filter.icon)
                Text(title)
                Text("\(value)")
                    .fontWeight(.semibold)
            }
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.12))
            .foregroundStyle(value > 0 ? color : .secondary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue("\(value)")
    }
    
    // MARK: - Health Dashboard
    
    @State private var isRefreshingAll = false
    @State private var isRunningBulkAction = false
    
    private var healthDashboard: some View {
        let stats = healthStats
        let score = healthScore
        
        return HStack(spacing: 12) {
            // Health Score
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .stroke(Color.primary.opacity(0.1), lineWidth: 3)
                        Circle()
                            .trim(from: 0, to: Double(score) / 100)
                            .stroke(healthScoreTint(score), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .frame(width: 24, height: 24)
                    
                    Text("\(score)%")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(healthScoreTint(score))
                }
                Text("quota.health.score".localized(fallback: "健康度"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 80)
            
            Divider()
                .frame(height: 32)
            
            // Stats Grid
            HStack(spacing: 16) {
                statItem(
                    value: stats.ready,
                    label: "quota.health.ready".localized(fallback: "可用"),
                    color: Color.semanticSuccess
                )
                
                statItem(
                    value: stats.cooling,
                    label: "quota.health.cooling".localized(fallback: "冷却中"),
                    color: Color.semanticWarning
                )
                
                statItem(
                    value: stats.error,
                    label: "quota.health.error".localized(fallback: "错误"),
                    color: Color.semanticDanger
                )
                
                statItem(
                    value: stats.total,
                    label: "quota.health.total".localized(fallback: "总计"),
                    color: .secondary
                )
            }
            
            Spacer()
            
            // Sort & Batch Actions
            HStack(spacing: 8) {
                if featureFlags.enhancedUILayout {
                    Toggle("quota.prioritizeAnomalies".localized(fallback: "异常优先"), isOn: $prioritizeAnomalies)
                        .toggleStyle(.switch)
                        .font(.caption)
                        .help("quota.prioritizeAnomalies.help".localized(fallback: "优先展示异常 Provider"))
                }

                // Sort Menu
                Menu {
                    ForEach(AccountSortOption.allCases) { option in
                        Button {
                            sortOption = option
                        } label: {
                            HStack {
                                Image(systemName: option.icon)
                                Text(option.displayName)
                                if sortOption == option {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.caption)
                        Text(sortOption.displayName)
                            .font(.caption)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.1))
                    .foregroundStyle(.secondary)
                    .clipShape(Capsule())
                }
                .menuStyle(.borderlessButton)

                if featureFlags.enhancedUILayout {
                    Menu {
                        ForEach(AccountStatusFilter.allCases) { option in
                            Button {
                                accountStatusFilter = option
                            } label: {
                                HStack {
                                    Image(systemName: option.icon)
                                    Text(option.label)
                                    if accountStatusFilter == option {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: accountStatusFilter.icon)
                                .font(.caption)
                            Text(accountStatusFilter.label)
                                .font(.caption)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.1))
                        .foregroundStyle(.secondary)
                        .clipShape(Capsule())
                    }
                    .menuStyle(.borderlessButton)
                }

                Picker("providers.viewMode".localized(fallback: "视图模式"), selection: $compactAccountView) {
                    Text("quota.view.card".localized(fallback: "卡片")).tag(false)
                    Text("quota.view.compact".localized(fallback: "紧凑")).tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)

                Menu {
                    Button("quota.bulk.disableAbnormal".localized(fallback: "批量禁用异常账号")) {
                        Task { await bulkDisableAbnormalAccounts() }
                    }
                    .disabled(isRunningBulkAction)

                    Button("quota.bulk.enableDisabled".localized(fallback: "批量启用已禁用账号")) {
                        Task { await bulkEnableDisabledAccounts() }
                    }
                    .disabled(isRunningBulkAction)

                    Button("quota.bulk.refreshCurrentProvider".localized(fallback: "批量刷新当前 Provider")) {
                        Task {
                            isRunningBulkAction = true
                            await viewModel.refreshQuotasUnified()
                            isRunningBulkAction = false
                        }
                    }
                    .disabled(isRunningBulkAction)
                } label: {
                    HStack(spacing: 4) {
                        if isRunningBulkAction {
                            ProgressView()
                                .scaleEffect(0.65)
                                .frame(width: 10, height: 10)
                        } else {
                            Image(systemName: "checklist")
                                .font(.caption)
                        }
                        Text("quota.bulk.actions".localized(fallback: "批量操作"))
                            .font(.caption)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.semanticWarningFill)
                    .foregroundStyle(Color.semanticWarning)
                    .clipShape(Capsule())
                }
                .menuStyle(.borderlessButton)

                Button {
                    viewModel.currentPage = .providers
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "person.2")
                            .font(.caption)
                        Text("quota.manageAccounts".localized(fallback: "管理账号"))
                            .font(.caption)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.12))
                    .foregroundStyle(.secondary)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                
                // Refresh All Button
                Button {
                    Task {
                        uiMetrics.begin("quota.refresh_all")
                        isRefreshingAll = true
                        await viewModel.refreshQuotasUnified()
                        isRefreshingAll = false
                        uiMetrics.end(
                            "quota.refresh_all",
                            metadata: "providers=\(availableProviders.count)"
                        )
                    }
                } label: {
                    HStack(spacing: 4) {
                        if isRefreshingAll {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption)
                        }
                        Text("quota.action.refreshAll".localized(fallback: "全部刷新"))
                            .font(.caption)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.semanticSelectionFill)
                    .foregroundStyle(Color.semanticInfo)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isRefreshingAll || viewModel.isLoadingQuotas)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
    }
    
    private func healthScoreTint(_ score: Int) -> Color {
        if score >= 80 { return Color.semanticSuccess }
        if score >= 50 { return Color.semanticWarning }
        return Color.semanticDanger
    }

    private var currentProvider: AIProvider? {
        selectedProvider ?? availableProviders.first
    }

    private var currentProviderAuthFiles: [AuthFile] {
        guard let provider = currentProvider else { return [] }
        return viewModel.authFiles.filter { $0.providerType == provider }
    }

    private func bulkDisableAbnormalAccounts() async {
        guard !isRunningBulkAction else { return }
        isRunningBulkAction = true
        defer { isRunningBulkAction = false }

        let targets = currentProviderAuthFiles.filter { file in
            !file.disabled && (file.status == "error" || file.status == "cooling")
        }
        for file in targets {
            await viewModel.toggleAuthFileDisabled(file)
        }
        await viewModel.refreshQuotasUnified()
    }

    private func bulkEnableDisabledAccounts() async {
        guard !isRunningBulkAction else { return }
        isRunningBulkAction = true
        defer { isRunningBulkAction = false }

        let targets = currentProviderAuthFiles.filter { $0.disabled }
        for file in targets {
            await viewModel.toggleAuthFileDisabled(file)
        }
        await viewModel.refreshQuotasUnified()
    }
    
    private func statItem(value: Int, label: String, color: Color) -> some View {
        VStack(alignment: .center, spacing: 2) {
            Text("\(value)")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(value > 0 ? color : .secondary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 45)
    }
    
    // MARK: - Segmented Control
    
    private var providerSegmentedControl: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(availableProviders) { provider in
                    ProviderSegmentButton(
                        provider: provider,
                        quotaPercent: lowestQuotaPercent(for: provider),
                        accountCount: accountCount(for: provider),
                        isSelected: selectedProvider == provider
                    ) {
                        withMotionAwareAnimation(.easeOut(duration: 0.2), reduceMotion: reduceMotion) {
                            selectedProvider = provider
                        }
                    }
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }
}

fileprivate struct QuotaDisplayHelper {
    let displayMode: QuotaDisplayMode
    
    func statusTint(remainingPercent: Double) -> Color {
        let clamped = max(0, min(100, remainingPercent))
        let usedPercent = 100 - clamped
        let checkValue = displayMode == .used ? usedPercent : clamped
        
        if displayMode == .used {
            if checkValue < 70 { return Color.semanticSuccess }
            if checkValue < 90 { return Color.semanticWarning }
            return Color.semanticDanger
        }
        
        if checkValue > 50 { return Color.semanticSuccess }
        if checkValue > 20 { return Color.semanticWarning }
        return Color.semanticDanger
    }
    
    func displayPercent(remainingPercent: Double) -> Double {
        let clamped = max(0, min(100, remainingPercent))
        return displayMode == .used ? (100 - clamped) : clamped
    }
}

// MARK: - Provider Segment Button

private struct ProviderSegmentButton: View {
    let provider: AIProvider
    let quotaPercent: Double?
    let accountCount: Int
    let isSelected: Bool
    let action: () -> Void

    private var settings: MenuBarSettingsManager { MenuBarSettingsManager.shared }

    private var displayHelper: QuotaDisplayHelper {
        QuotaDisplayHelper(displayMode: settings.quotaDisplayMode)
    }
    
    private var statusColor: Color {
        guard let percent = quotaPercent else { return .secondary }
        return displayHelper.statusTint(remainingPercent: percent)
    }
    
    private var remainingPercent: Double {
        max(0, min(100, quotaPercent ?? 0))
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ProviderIcon(provider: provider, size: 20)
                
                Text(provider.displayName)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .medium)
                
                if accountCount > 1 {
                    Text(String(accountCount))
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(isSelected ? .white : .secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(isSelected ? statusColor : Color.primary.opacity(0.08))
                        .clipShape(Capsule())
                }
                
                if quotaPercent != nil {
                    ZStack {
                        Circle()
                            .stroke(Color.primary.opacity(0.1), lineWidth: 2)
                        Circle()
                            .trim(from: 0, to: remainingPercent / 100)
                            .stroke(statusColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .frame(width: 12, height: 12)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(statusColor.opacity(0.3), lineWidth: 1)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                }
            }
            .foregroundStyle(isSelected ? .primary : .secondary)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .motionAwareAnimation(.easeOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - Quota Status Dot

private struct QuotaStatusDot: View {
    let usedPercent: Double
    let size: CGFloat
    
    private var color: Color {
        if usedPercent < 70 { return Color.semanticSuccess }   // <70% used = healthy
        if usedPercent < 90 { return Color.semanticWarning }  // 70-90% used = warning
        return Color.semanticDanger                             // >90% used = critical
    }
    
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
    }
}

// MARK: - Provider Quota View

private struct ProviderQuotaView: View {
    let provider: AIProvider
    let authFiles: [AuthFile]
    let quotaData: [String: ProviderQuotaData]
    let subscriptionInfos: [String: SubscriptionInfo]
    let isLoading: Bool
    var searchFilter: String = ""
    var sortOption: AccountSortOption = .name
    var statusFilter: AccountStatusFilter = .all
    var compactMode: Bool = false
    
    private var settings: MenuBarSettingsManager { MenuBarSettingsManager.shared }

    private func codexDerivedLookupKeys(from fileName: String) -> [String] {
        guard fileName.hasPrefix("codex-"), fileName.hasSuffix(".json") else {
            return []
        }
        var keys: [String] = []
        let stripped = fileName
            .replacingOccurrences(of: "codex-", with: "")
            .replacingOccurrences(of: ".json", with: "")
        if !stripped.isEmpty {
            keys.append(stripped)
            if stripped.hasSuffix("-team") {
                keys.append(String(stripped.dropLast("-team".count)))
            }
            if let atIndex = stripped.firstIndex(of: "@"),
               let hyphenBeforeAt = stripped[..<atIndex].lastIndex(of: "-") {
                let emailCandidate = String(stripped[stripped.index(after: hyphenBeforeAt)...])
                if !emailCandidate.isEmpty {
                    keys.append(emailCandidate)
                    if emailCandidate.hasSuffix("-team") {
                        keys.append(String(emailCandidate.dropLast("-team".count)))
                    }
                }
            }
        }
        return Array(Set(keys))
    }
    
    /// Get all accounts (from auth files or quota data keys)
    private var allAccounts: [AccountInfo] {
        var accounts: [AccountInfo] = []
        var seenDisplayNames = Set<String>() // Track by displayName to avoid duplicates
        
        // From auth files (primary source)
        for file in authFiles {
            let key = file.quotaLookupKey
            let rawEmail = file.email ?? file.name
            let (cleanName, isTeam) = AccountInfo.extractCleanDisplayName(from: rawEmail, email: file.email)
            
            // Skip if we already have this display name (avoid duplicates)
            let normalizedName = cleanName.lowercased()
            guard !seenDisplayNames.contains(normalizedName) else { continue }
            seenDisplayNames.insert(normalizedName)
            
            // Try to find quota data with various possible keys
            let possibleKeys = [key, cleanName, rawEmail, file.name] + codexDerivedLookupKeys(from: file.name)
            let matchedQuota = possibleKeys.compactMap { quotaData[$0] }.first
            let matchedSubscription = possibleKeys.compactMap { subscriptionInfos[$0] }.first
            
            accounts.append(AccountInfo(
                key: key,
                email: rawEmail,
                displayName: cleanName,
                isTeamAccount: isTeam,
                status: file.status,
                statusColor: file.statusColor,
                authFile: file,
                quotaData: matchedQuota,
                subscriptionInfo: matchedSubscription
            ))
        }
        
        // From quota data (only if not already added by displayName)
        for (key, data) in quotaData {
            let (cleanName, isTeam) = AccountInfo.extractCleanDisplayName(from: key, email: nil)
            let normalizedName = cleanName.lowercased()
            
            // Skip if we already have this display name
            guard !seenDisplayNames.contains(normalizedName) else { continue }
            seenDisplayNames.insert(normalizedName)
            
            accounts.append(AccountInfo(
                key: key,
                email: key,
                displayName: cleanName,
                isTeamAccount: isTeam,
                status: "active",
                statusColor: Color.semanticSuccess,
                authFile: nil,
                quotaData: data,
                subscriptionInfo: subscriptionInfos[key]
            ))
        }
        
        // Apply search filter
        var filtered = accounts
        if !searchFilter.isEmpty {
            let query = searchFilter.lowercased()
            filtered = accounts.filter { account in
                account.displayName.lowercased().contains(query) ||
                account.email.lowercased().contains(query) ||
                account.key.lowercased().contains(query)
            }
        }

        if statusFilter != .all {
            filtered = filtered.filter { account in
                matchesStatusFilter(account: account)
            }
        }
        
        // Apply sorting
        return filtered.sorted { lhs, rhs in
            switch sortOption {
            case .name:
                return lhs.displayName.lowercased() < rhs.displayName.lowercased()
            case .status:
                // Sort order: ready/active first, then cooling, then error, then other
                let statusOrder = ["ready": 0, "active": 0, "cooling": 1, "error": 2]
                let lhsOrder = statusOrder[lhs.status] ?? 3
                let rhsOrder = statusOrder[rhs.status] ?? 3
                if lhsOrder != rhsOrder {
                    return lhsOrder < rhsOrder
                }
                return lhs.displayName.lowercased() < rhs.displayName.lowercased()
            case .quotaLow:
                // Sort by lowest quota percentage first
                let lhsQuota = getLowestQuotaPercent(for: lhs)
                let rhsQuota = getLowestQuotaPercent(for: rhs)
                if lhsQuota != rhsQuota {
                    return lhsQuota < rhsQuota
                }
                return lhs.displayName.lowercased() < rhs.displayName.lowercased()
            case .quotaHigh:
                // Sort by highest quota percentage first
                let lhsQuota = getLowestQuotaPercent(for: lhs)
                let rhsQuota = getLowestQuotaPercent(for: rhs)
                if lhsQuota != rhsQuota {
                    return lhsQuota > rhsQuota
                }
                return lhs.displayName.lowercased() < rhs.displayName.lowercased()
            }
        }
    }
    
    /// Get the lowest quota percentage for an account
    private func getLowestQuotaPercent(for account: AccountInfo) -> Double {
        guard let data = account.quotaData else { return 100 }
        let models = data.models.map { (name: $0.name, percentage: $0.percentage) }
        let total = settings.totalUsagePercent(models: models)
        return total >= 0 ? total : 100
    }

    private func matchesStatusFilter(account: AccountInfo) -> Bool {
        if provider == .codex {
            let bucket = codexBucket(for: account)
            switch statusFilter {
            case .all:
                return true
            case .ready:
                return bucket == .main
            case .cooling:
                return bucket == .quota5h || bucket == .quota7d
            case .error:
                return bucket == .tokenInvalidated
            case .disabled:
                return account.authFile?.disabled == true
            case .quota5h:
                return bucket == .quota5h
            case .quota7d:
                return bucket == .quota7d
            case .fatalDisabled:
                return account.authFile?.isFatalDisabled == true
            case .networkError:
                return account.authFile?.isNetworkError == true
            }
        }

        switch statusFilter {
        case .all:
            return true
        case .ready:
            return account.status == "ready" || account.status == "active"
        case .cooling:
            return account.status == "cooling"
        case .error:
            return account.status == "error"
        case .disabled:
            return account.authFile?.disabled == true
        case .quota5h:
            return account.authFile?.isQuotaLimited5h == true
        case .quota7d:
            return account.authFile?.isQuotaLimited7d == true
        case .fatalDisabled:
            return account.authFile?.isFatalDisabled == true
        case .networkError:
            return account.authFile?.isNetworkError == true
        }
    }

    private func codexBucket(for account: AccountInfo) -> CodexRoutingBucket {
        if account.authFile?.isQuotaLimited7d == true {
            return .quota7d
        }
        if account.authFile?.isQuotaLimited5h == true {
            return .quota5h
        }
        let statusText = account.status.lowercased()
        let statusMessage = account.authFile?.statusMessage?.lowercased() ?? ""
        if statusText == "error" ||
            statusText == "invalid" ||
            statusMessage.contains("invalid") ||
            statusMessage.contains("unauthorized") ||
            statusMessage.contains("token") {
            return .tokenInvalidated
        }

        let sessionRemaining = codexRemainingPercent(for: account, modelName: "codex-session")
        let weeklyRemaining = codexRemainingPercent(for: account, modelName: "codex-weekly")

        if weeklyRemaining <= 0.1 {
            return .quota7d
        }
        if sessionRemaining <= 0.1 {
            return .quota5h
        }
        return .main
    }

    private func codexRemainingPercent(for account: AccountInfo, modelName: String) -> Double {
        account.quotaData?.models.first(where: { $0.name == modelName })?.percentage ?? 100
    }

    private func codexResetDate(for account: AccountInfo, modelName: String) -> Date? {
        guard let resetString = account.quotaData?.models.first(where: { $0.name == modelName })?.resetTime,
              !resetString.isEmpty else {
            return nil
        }
        let formatterWithFractional = ISO8601DateFormatter()
        formatterWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let formatterDefault = ISO8601DateFormatter()
        formatterDefault.formatOptions = [.withInternetDateTime]
        return formatterWithFractional.date(from: resetString) ?? formatterDefault.date(from: resetString)
    }

    private func codexSorted(_ accounts: [AccountInfo], in bucket: CodexRoutingBucket) -> [AccountInfo] {
        accounts.sorted { lhs, rhs in
            switch sortOption {
            case .name:
                return lhs.displayName.lowercased() < rhs.displayName.lowercased()
            case .quotaLow:
                let lhsQuota = getLowestQuotaPercent(for: lhs)
                let rhsQuota = getLowestQuotaPercent(for: rhs)
                if lhsQuota != rhsQuota { return lhsQuota < rhsQuota }
                return lhs.displayName.lowercased() < rhs.displayName.lowercased()
            case .quotaHigh:
                let lhsQuota = getLowestQuotaPercent(for: lhs)
                let rhsQuota = getLowestQuotaPercent(for: rhs)
                if lhsQuota != rhsQuota { return lhsQuota > rhsQuota }
                return lhs.displayName.lowercased() < rhs.displayName.lowercased()
            case .status:
                break
            }

            switch bucket {
            case .main:
                let lhsWeekly = codexRemainingPercent(for: lhs, modelName: "codex-weekly")
                let rhsWeekly = codexRemainingPercent(for: rhs, modelName: "codex-weekly")
                if lhsWeekly != rhsWeekly { return lhsWeekly > rhsWeekly }

                let lhsSession = codexRemainingPercent(for: lhs, modelName: "codex-session")
                let rhsSession = codexRemainingPercent(for: rhs, modelName: "codex-session")
                if lhsSession != rhsSession { return lhsSession > rhsSession }

            case .quota5h:
                let lhsReset = codexResetDate(for: lhs, modelName: "codex-session") ?? .distantFuture
                let rhsReset = codexResetDate(for: rhs, modelName: "codex-session") ?? .distantFuture
                if lhsReset != rhsReset { return lhsReset < rhsReset }

            case .quota7d:
                let lhsReset = codexResetDate(for: lhs, modelName: "codex-weekly") ?? .distantFuture
                let rhsReset = codexResetDate(for: rhs, modelName: "codex-weekly") ?? .distantFuture
                if lhsReset != rhsReset { return lhsReset < rhsReset }

            case .tokenInvalidated:
                let lhsStatus = lhs.authFile?.statusMessage ?? lhs.status
                let rhsStatus = rhs.authFile?.statusMessage ?? rhs.status
                if lhsStatus != rhsStatus { return lhsStatus < rhsStatus }
            }

            return lhs.displayName.lowercased() < rhs.displayName.lowercased()
        }
    }
    
    /// Group accounts by status for organized display
    private var accountsByStatus: [(status: String, label: String, color: Color, accounts: [AccountInfo])] {
        let all = allAccounts
        
        var ready: [AccountInfo] = []
        var cooling: [AccountInfo] = []
        var error: [AccountInfo] = []
        var other: [AccountInfo] = []
        
        for account in all {
            switch account.status {
            case "ready", "active":
                ready.append(account)
            case "cooling":
                cooling.append(account)
            case "error":
                error.append(account)
            default:
                other.append(account)
            }
        }
        
        var groups: [(status: String, label: String, color: Color, accounts: [AccountInfo])] = []
        
        if !ready.isEmpty {
            groups.append(("ready", "quota.status.ready".localized(fallback: "可用"), Color.semanticSuccess, ready))
        }
        if !cooling.isEmpty {
            groups.append(("cooling", "quota.status.cooling".localized(fallback: "冷却中"), Color.semanticWarning, cooling))
        }
        if !error.isEmpty {
            groups.append(("error", "quota.status.error".localized(fallback: "错误"), Color.semanticDanger, error))
        }
        if !other.isEmpty {
            groups.append(("other", "quota.status.other".localized(fallback: "其他"), .secondary, other))
        }
        
        return groups
    }

    private var codexAccountsByBucket: [(bucket: CodexRoutingBucket, accounts: [AccountInfo])] {
        let accounts = allAccounts
        var grouped: [CodexRoutingBucket: [AccountInfo]] = [
            .main: [],
            .tokenInvalidated: [],
            .quota5h: [],
            .quota7d: []
        ]

        for account in accounts {
            grouped[codexBucket(for: account), default: []].append(account)
        }

        let orderedBuckets: [CodexRoutingBucket] = [.main, .tokenInvalidated, .quota5h, .quota7d]
        return orderedBuckets.compactMap { bucket in
            let list = grouped[bucket] ?? []
            guard !list.isEmpty else { return nil }
            return (bucket, codexSorted(list, in: bucket))
        }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            if allAccounts.isEmpty && isLoading {
                QuotaLoadingView()
            } else if allAccounts.isEmpty {
                emptyState
            } else if provider == .codex {
                ForEach(codexAccountsByBucket, id: \.bucket.rawValue) { group in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(group.bucket.color)
                                .frame(width: 8, height: 8)
                            Text(group.bucket.label)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                            Text("(\(group.accounts.count))")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Spacer()
                        }
                        .padding(.top, group.bucket == .main ? 0 : 8)

                        ForEach(group.accounts, id: \.key) { account in
                            accountView(account)
                        }
                    }
                }
            } else if allAccounts.count <= 3 {
                // For small number of accounts, show flat list
                ForEach(allAccounts, id: \.key) { account in
                    accountView(account)
                }
            } else {
                // For larger number of accounts, group by status
                ForEach(accountsByStatus, id: \.status) { group in
                    VStack(alignment: .leading, spacing: 12) {
                        // Group header
                        HStack(spacing: 6) {
                            Circle()
                                .fill(group.color)
                                .frame(width: 8, height: 8)
                            Text(group.label)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                            Text("(\(group.accounts.count))")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Spacer()
                        }
                        .padding(.top, group.status == "ready" ? 0 : 8)
                        
                        // Account cards
                        ForEach(group.accounts, id: \.key) { account in
                            accountView(account)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func accountView(_ account: AccountInfo) -> some View {
        if compactMode {
            CompactAccountQuotaRow(provider: provider, account: account)
        } else {
            AccountQuotaCardV2(
                provider: provider,
                account: account,
                isLoading: isLoading && account.quotaData == nil
            )
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.tertiary)
            Text("quota.noDataYet".localized())
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
    }
}

private struct CompactAccountQuotaRow: View {
    let provider: AIProvider
    let account: AccountInfo

    private var lowestQuotaPercent: Double {
        guard let quota = account.quotaData else { return -1 }
        let models = quota.models.map { (name: $0.name, percentage: $0.percentage) }
        return MenuBarSettingsManager.shared.totalUsagePercent(models: models)
    }

    private var quotaText: String {
        if lowestQuotaPercent < 0 {
            return "—"
        }
        return "\(Int(lowestQuotaPercent))%"
    }

    private var quotaColor: Color {
        switch lowestQuotaPercent {
        case ..<0:
            return .secondary
        case ..<10:
            return Color.semanticDanger
        case ..<30:
            return Color.semanticWarning
        case ..<50:
            return Color.semanticWarning
        default:
            return Color.semanticSuccess
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            ProviderIcon(provider: provider, size: 14)

            Text(account.displayName)
                .font(.subheadline)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            if let status = account.authFile?.status {
                Text(status.localizedCapitalized)
                    .font(.caption2)
                    .foregroundStyle(account.statusColor)
            }

            Text(quotaText)
                .font(.system(.caption, design: .monospaced, weight: .semibold))
                .foregroundStyle(quotaColor)
                .frame(width: 44, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Account Info

private struct AccountInfo {
    let key: String
    let email: String           // Original email/name for technical operations
    let displayName: String     // Clean display name (extracted email)
    let isTeamAccount: Bool     // Whether this is a team account
    let status: String
    let statusColor: Color
    let authFile: AuthFile?
    let quotaData: ProviderQuotaData?
    
    /// Extract a clean display name from technical account identifiers
    static func extractCleanDisplayName(from rawName: String, email: String?) -> (displayName: String, isTeam: Bool) {
        // If we have a clean email, use it
        if let email = email, !email.isEmpty, !email.contains("-team"), !email.hasSuffix(".json") {
            return (email, rawName.lowercased().contains("-team"))
        }
        
        var name = rawName
        let isTeam = name.lowercased().contains("-team")
        
        // Remove .json suffix
        if name.hasSuffix(".json") {
            name = String(name.dropLast(5))
        }
        
        // Remove -team suffix
        if name.lowercased().hasSuffix("-team") {
            name = String(name.dropLast(5))
        }
        
        // Find email pattern (something with @ in it)
        if let atRange = name.range(of: "@") {
            // Find the start of the email (after the last hyphen before @)
            let beforeAt = name[..<atRange.lowerBound]
            var emailStart = beforeAt.startIndex
            if let lastHyphen = beforeAt.lastIndex(of: "-") {
                emailStart = beforeAt.index(after: lastHyphen)
            }
            
            // Find the end of the email domain
            let afterAt = name[atRange.upperBound...]
            var emailEnd = afterAt.endIndex
            
            // Check for common patterns that indicate end of domain
            for pattern in ["-gmail", "-manager", "-project", "-cli"] {
                if let patternRange = afterAt.range(of: pattern, options: .caseInsensitive) {
                    emailEnd = patternRange.lowerBound
                    break
                }
            }
            
            let extractedEmail = name[emailStart..<emailEnd]
            if extractedEmail.contains("@") && extractedEmail.count > 3 {
                return (String(extractedEmail), isTeam)
            }
        }
        
        return (name, isTeam)
    }
    
    let subscriptionInfo: SubscriptionInfo?
}

// MARK: - Account Quota Card V2

private struct AccountQuotaCardV2: View {
    @Environment(QuotaViewModel.self) private var viewModel
    
    private var settings: MenuBarSettingsManager { MenuBarSettingsManager.shared }
    let provider: AIProvider
    let account: AccountInfo
    let isLoading: Bool
    
    @State private var isRefreshing = false
    @State private var showSwitchSheet = false
    @State private var showModelsDetailSheet = false

    /// Check if OAuth is in progress for this provider
    private var isReauthenticating: Bool {
        guard let oauthState = viewModel.oauthState else { return false }
        return oauthState.provider == provider &&
               (oauthState.status == .waiting || oauthState.status == .polling)
    }
    @State private var showWarmupSheet = false
    
    private var hasQuotaData: Bool {
        guard let data = account.quotaData else { return false }
        return !data.models.isEmpty
    }
    
    private var displayEmail: String {
        account.displayName.masked(if: settings.hideSensitiveInfo)
    }
    
    private var isWarmupEnabled: Bool {
        viewModel.isWarmupEnabled(for: provider, accountKey: account.key)
    }
    
    /// Check if this Antigravity account is active in IDE
    private var isActiveInIDE: Bool {
        provider == .antigravity && viewModel.isAntigravityAccountActive(email: account.email)
    }
    
    /// Build 4-group display for Antigravity: Gemini 3 Pro, Gemini 3 Flash, Gemini 3 Image, Claude 4.5
    private var antigravityDisplayGroups: [AntigravityDisplayGroup] {
        guard let data = account.quotaData, provider == .antigravity else { return [] }
        
        var groups: [AntigravityDisplayGroup] = []
        
        let gemini3ProModels = data.models.filter { 
            $0.name.contains("gemini-3-pro") && !$0.name.contains("image") 
        }
        if !gemini3ProModels.isEmpty {
            let aggregatedQuota = settings.aggregateModelPercentages(gemini3ProModels.map(\.percentage))
            if aggregatedQuota >= 0 {
                groups.append(AntigravityDisplayGroup(name: "Gemini 3 Pro", percentage: aggregatedQuota, models: gemini3ProModels))
            }
        }
        
        let gemini3FlashModels = data.models.filter { $0.name.contains("gemini-3-flash") }
        if !gemini3FlashModels.isEmpty {
            let aggregatedQuota = settings.aggregateModelPercentages(gemini3FlashModels.map(\.percentage))
            if aggregatedQuota >= 0 {
                groups.append(AntigravityDisplayGroup(name: "Gemini 3 Flash", percentage: aggregatedQuota, models: gemini3FlashModels))
            }
        }
        
        let geminiImageModels = data.models.filter { $0.name.contains("image") }
        if !geminiImageModels.isEmpty {
            let aggregatedQuota = settings.aggregateModelPercentages(geminiImageModels.map(\.percentage))
            if aggregatedQuota >= 0 {
                groups.append(AntigravityDisplayGroup(name: "Gemini 3 Image", percentage: aggregatedQuota, models: geminiImageModels))
            }
        }
        
        let claudeModels = data.models.filter { $0.name.contains("claude") }
        if !claudeModels.isEmpty {
            let aggregatedQuota = settings.aggregateModelPercentages(claudeModels.map(\.percentage))
            if aggregatedQuota >= 0 {
                groups.append(AntigravityDisplayGroup(name: "Claude", percentage: aggregatedQuota, models: claudeModels))
            }
        }
        
        return groups.sorted { $0.percentage < $1.percentage }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            accountHeader
            
            if isLoading {
                QuotaLoadingView()
            } else if hasQuotaData {
                usageSection
            } else if let message = account.authFile?.humanReadableStatus {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                // No quota data available - show helpful prompt
                noQuotaDataView
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.background)
                .shadow(color: .primary.opacity(0.06), radius: 8, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }
    
    /// View shown when no quota data is available
    private var noQuotaDataView: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                Text("quota.noDataYet".localized(fallback: "尚未获取额度数据"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Text("quota.clickRefresh".localized(fallback: "点击刷新按钮获取最新额度"))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
    }
    
    // MARK: - Account Header

    private var accountHeader: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    if let info = account.subscriptionInfo {
                        SubscriptionBadgeV2(info: info)
                    } else if let planName = account.quotaData?.planDisplayName {
                        PlanBadgeV2Compact(planName: planName)
                    }

                    Text(displayEmail)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    
                    // Team badge
                    if account.isTeamAccount {
                        Text("quota.account.team".localized(fallback: "Team"))
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.semanticInfo)
                            .clipShape(Capsule())
                    }
                }

                // Show token expiry for Kiro accounts
                if let quotaData = account.quotaData, let tokenExpiry = quotaData.formattedTokenExpiry {
                    HStack(spacing: 4) {
                        Image(systemName: "key")
                            .font(.caption2)
                        Text(tokenExpiry)
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }

                if account.status != "ready" && account.status != "active" {
                    Text(account.status.capitalized)
                        .font(.caption)
                        .foregroundStyle(account.statusColor)
                }

                if let kind = account.authFile?.normalizedErrorKind {
                    Text("quota.errorKind".localized(fallback: "error_kind") + ": \(kind)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let frozenUntil = account.authFile?.frozenUntilDate, frozenUntil > Date() {
                    Text("quota.frozenUntil".localized(fallback: "frozen_until") + ": \(frozenUntil.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(Color.semanticWarning)
                }

                if account.authFile?.isFatalDisabled == true {
                    Text("quota.disabledByPolicy".localized(fallback: "disabled by policy"))
                        .font(.caption2)
                        .foregroundStyle(Color.semanticDanger)
                }
            }
            
            Spacer()
            
            HStack(spacing: 6) {
                if provider == .antigravity {
                    Button {
                        showWarmupSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: isWarmupEnabled ? "bolt.fill" : "bolt")
                                .font(.caption)
                            Text("quota.warmup".localized(fallback: "Warm Up"))
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                            .foregroundStyle(isWarmupEnabled ? provider.color : .secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(isWarmupEnabled ? provider.color.opacity(0.12) : Color.primary.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("action.warmup".localized())
                }
                
                if isActiveInIDE {
                    Text("antigravity.active".localized())
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.semanticSuccess)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.semanticSuccess.opacity(0.1))
                        .clipShape(Capsule())
                }
                
                if provider == .antigravity && !isActiveInIDE {
                    Button {
                        showSwitchSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.right.square")
                                .font(.caption)
                            Text("quota.useInIDE".localized(fallback: "Use in IDE"))
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                            .foregroundStyle(Color.semanticInfo)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.semanticSelectionFill)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("antigravity.useInIDE".localized())
                }
                
                Button {
                    Task {
                        isRefreshing = true
                        await viewModel.refreshQuotaForProvider(provider)
                        isRefreshing = false
                    }
                } label: {
                    if isRefreshing || isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption)
                            Text("action.refresh".localized(fallback: "Refresh"))
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.primary.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }
                .buttonStyle(.plain)
                .disabled(isRefreshing || isLoading)
                
                if let data = account.quotaData, data.isForbidden {
                    if provider == .claude {
                        Button {
                            Task {
                                await viewModel.startOAuth(for: .claude)
                            }
                        } label: {
                            if isReauthenticating {
                                ProgressView()
                                    .controlSize(.mini)
                                    .frame(width: 28, height: 28)
                            } else {
                                Image(systemName: "arrow.clockwise.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(Color.semanticWarning)
                                    .frame(width: 28, height: 28)
                                    .background(Color.semanticWarning.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isReauthenticating)
                        .help("quota.reauthenticate".localized())
                    } else {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.semanticDanger)
                            .frame(width: 28, height: 28)
                            .background(Color.semanticDanger.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .help("limit.reached".localized())
                    }
                }
            }
        }
        .sheet(isPresented: $showSwitchSheet) {
            SwitchAccountSheet(
                accountEmail: account.email,
                onDismiss: {
                    showSwitchSheet = false
                }
            )
            .environment(viewModel)
        }
        .sheet(isPresented: $showWarmupSheet) {
            WarmupSheet(
                provider: provider,
                accountKey: account.key,
                accountEmail: account.email,
                onDismiss: {
                    showWarmupSheet = false
                }
            )
            .environment(viewModel)
        }
    }
    
    // MARK: - Usage Section

    private var isQuotaUnavailable: Bool {
        guard let data = account.quotaData else { return false }
        return data.models.allSatisfy { $0.percentage < 0 }
    }
    
    private var displayStyle: QuotaDisplayStyle { settings.quotaDisplayStyle }

    @ViewBuilder
    private var usageSection: some View {
        if let data = account.quotaData {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("quota.usage".localized(fallback: "Usage"))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)
                        .tracking(0.5)

                    Spacer()

                    if provider == .antigravity && data.models.count > 4 {
                        Button {
                            showModelsDetailSheet = true
                        } label: {
                            HStack(spacing: 4) {
                                Text("quota.details".localized())
                                    .font(.caption)
                                Image(systemName: "list.bullet.rectangle")
                                    .font(.caption)
                            }
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Divider()
                    .opacity(0.5)

                // Display based on quotaDisplayStyle setting
                if isQuotaUnavailable {
                    quotaUnavailableView
                } else {
                    quotaContentByStyle
                }
            }
            .padding(.top, 4)
            .sheet(isPresented: $showModelsDetailSheet) {
                AntigravityModelsDetailSheet(
                    email: account.email,
                    models: data.models
                )
            }
        }
    }
    
    private var quotaUnavailableView: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
            Text("quota.notAvailable".localized())
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
    
    @ViewBuilder
    private var quotaContentByStyle: some View {
        if provider == .antigravity && !antigravityDisplayGroups.isEmpty {
            // Antigravity uses grouped display
            antigravityContentByStyle
        } else if let data = account.quotaData {
            // Standard providers
            standardContentByStyle(data: data)
        }
    }
    
    @ViewBuilder
    private var antigravityContentByStyle: some View {
        switch displayStyle {
        case .lowestBar:
            AntigravityLowestBarLayout(groups: antigravityDisplayGroups)
        case .ring:
            AntigravityRingLayout(groups: antigravityDisplayGroups)
        case .card:
            VStack(spacing: 12) {
                ForEach(antigravityDisplayGroups) { group in
                    AntigravityGroupRow(group: group)
                }
            }
        }
    }
    
    @ViewBuilder
    private func standardContentByStyle(data: ProviderQuotaData) -> some View {
        switch displayStyle {
        case .lowestBar:
            StandardLowestBarLayout(models: data.models)
        case .ring:
            StandardRingLayout(models: data.models)
        case .card:
            VStack(spacing: 12) {
                ForEach(data.models) { model in
                    UsageRowV2(
                        name: model.displayName,
                        icon: nil,
                        usedPercent: model.usedPercentage,
                        used: model.used,
                        limit: model.limit,
                        resetTime: model.formattedResetTime,
                        tooltip: model.tooltip
                    )
                }
            }
        }
    }
}

// MARK: - Plan Badge V2 Compact (for header inline display)

private struct PlanBadgeV2Compact: View {
    let planName: String
    
    private var tierConfig: (name: String, color: Color) {
        let lowercased = planName.lowercased()
        
        // Check for Pro variants
        if lowercased.contains("pro") {
            return ("Pro", Color.semanticAccentSecondary)
        }
        
        // Check for Plus
        if lowercased.contains("plus") {
            return ("Plus", Color.semanticInfo)
        }
        
        // Check for Team
        if lowercased.contains("team") {
            return ("Team", Color.semanticWarning)
        }
        
        // Check for Enterprise
        if lowercased.contains("enterprise") {
            return ("Enterprise", Color.semanticDanger)
        }
        
        // Free/Standard
        if lowercased.contains("free") || lowercased.contains("standard") {
            return ("Free", .secondary)
        }
        
        // Default: use display name
        let displayName = planName
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
        return (displayName, .secondary)
    }
    
    var body: some View {
        Text(tierConfig.name)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(tierConfig.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tierConfig.color.opacity(0.12))
            .clipShape(Capsule())
    }
}

// MARK: - Plan Badge V2

private struct PlanBadgeV2: View {
    let planName: String
    
    private var planConfig: (color: Color, icon: String) {
        let lowercased = planName.lowercased()
        
        // Handle compound names like "Pro Student"
        if lowercased.contains("pro") && lowercased.contains("student") {
            return (Color.semanticAccentSecondary, "graduationcap.fill")
        }
        
        switch lowercased {
        case "pro":
            return (Color.semanticAccentSecondary, "crown.fill")
        case "plus":
            return (Color.semanticInfo, "plus.circle.fill")
        case "team":
            return (Color.semanticWarning, "person.3.fill")
        case "enterprise":
            return (Color.semanticDanger, "building.2.fill")
        case "free":
            return (.secondary, "person.fill")
        case "student":
            return (Color.semanticSuccess, "graduationcap.fill")
        default:
            return (.secondary, "person.fill")
        }
    }
    
    private var displayName: String {
        planName
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: planConfig.icon)
                .font(.caption)
            Text(displayName)
                .font(.caption)
                .fontWeight(.medium)
        }
        .foregroundStyle(planConfig.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(planConfig.color.opacity(0.1))
        .clipShape(Capsule())
    }
}

// MARK: - Subscription Badge V2

private struct SubscriptionBadgeV2: View {
    let info: SubscriptionInfo
    
    private var tierConfig: (name: String, color: Color) {
        let tierId = info.tierId.lowercased()
        let tierName = info.tierDisplayName.lowercased()
        
        // Check for Ultra tier (highest priority)
        if tierId.contains("ultra") || tierName.contains("ultra") {
            return ("Ultra", Color.semanticWarning)
        }
        
        // Check for Pro tier
        if tierId.contains("pro") || tierName.contains("pro") {
            return ("Pro", Color.semanticAccentSecondary)
        }
        
        // Check for Free/Standard tier
        if tierId.contains("standard") || tierId.contains("free") || 
           tierName.contains("standard") || tierName.contains("free") {
            return ("Free", .secondary)
        }
        
        // Fallback: use the display name from API
        return (info.tierDisplayName, .secondary)
    }
    
    var body: some View {
        Text(tierConfig.name)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(tierConfig.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tierConfig.color.opacity(0.12))
            .clipShape(Capsule())
    }
}

// MARK: - Antigravity Display Group

private struct AntigravityDisplayGroup: Identifiable {
    let name: String
    let percentage: Double
    let models: [ModelQuota]
    
    var id: String { name }
}

// MARK: - Antigravity Group Row

private struct AntigravityGroupRow: View {
    let group: AntigravityDisplayGroup
    
    private var settings: MenuBarSettingsManager { MenuBarSettingsManager.shared }

    private var displayHelper: QuotaDisplayHelper {
        QuotaDisplayHelper(displayMode: settings.quotaDisplayMode)
    }
    
    private var remainingPercent: Double {
        max(0, min(100, group.percentage))
    }
    
    private var groupIcon: String {
        if group.name.contains("Claude") { return "brain.head.profile" }
        if group.name.contains("Image") { return "photo" }
        if group.name.contains("Flash") { return "bolt.fill" }
        return "sparkles"
    }
    
    var body: some View {
        let displayPercent = displayHelper.displayPercent(remainingPercent: remainingPercent)
        let statusColor = displayHelper.statusTint(remainingPercent: remainingPercent)
        
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: groupIcon)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(width: 16)
                
                Text(group.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                if group.models.count > 1 {
                    Text(String(group.models.count))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.primary.opacity(0.05))
                        .clipShape(Capsule())
                }
                
                Spacer()
                
                Text(String(format: "%.0f%%", displayPercent))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(statusColor)
                    .monospacedDigit()
                
                if let firstModel = group.models.first,
                   firstModel.formattedResetTime != "—" && !firstModel.formattedResetTime.isEmpty {
                    Text(firstModel.formattedResetTime)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.06))
                    Capsule()
                        .fill(statusColor.gradient)
                        .frame(width: proxy.size.width * (displayPercent / 100))
                }
            }
            .frame(height: 6)
        }
    }
}

// MARK: - Antigravity Lowest Bar Layout

private struct AntigravityLowestBarLayout: View {
    let groups: [AntigravityDisplayGroup]
    
    private var settings: MenuBarSettingsManager { MenuBarSettingsManager.shared }
    private var displayHelper: QuotaDisplayHelper {
        QuotaDisplayHelper(displayMode: settings.quotaDisplayMode)
    }
    
    private var sorted: [AntigravityDisplayGroup] {
        groups.sorted { $0.percentage < $1.percentage }
    }
    
    private var lowest: AntigravityDisplayGroup? {
        sorted.first
    }
    
    private var others: [AntigravityDisplayGroup] {
        Array(sorted.dropFirst())
    }
    
    private func displayPercent(for remainingPercent: Double) -> Double {
        displayHelper.displayPercent(remainingPercent: remainingPercent)
    }
    
    var body: some View {
        VStack(spacing: 10) {
            if let lowest = lowest {
                // Hero row for bottleneck
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(lowest.name)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Spacer()
                        Text(String(format: "%.0f%%", displayPercent(for: lowest.percentage)))
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundStyle(displayHelper.statusTint(remainingPercent: lowest.percentage))
                            .monospacedDigit()
                    }
                    
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.primary.opacity(0.06))
                            Capsule()
                                .fill(displayHelper.statusTint(remainingPercent: lowest.percentage).gradient)
                                .frame(width: proxy.size.width * (displayPercent(for: lowest.percentage) / 100))
                        }
                    }
                    .frame(height: 8)
                }
                .padding(10)
                .background(displayHelper.statusTint(remainingPercent: lowest.percentage).opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            
            // Others as compact text rows
            if !others.isEmpty {
                VStack(spacing: 4) {
                    ForEach(others) { group in
                        HStack {
                            Text(group.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "%.0f%%", displayPercent(for: group.percentage)))
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(displayHelper.statusTint(remainingPercent: group.percentage))
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Antigravity Ring Layout

private struct AntigravityRingLayout: View {
    let groups: [AntigravityDisplayGroup]
    
    private var settings: MenuBarSettingsManager { MenuBarSettingsManager.shared }
    private var displayHelper: QuotaDisplayHelper {
        QuotaDisplayHelper(displayMode: settings.quotaDisplayMode)
    }
    
    private var columns: [GridItem] {
        let count = min(max(groups.count, 1), 4)
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: count)
    }
    
    private func displayPercent(for remainingPercent: Double) -> Double {
        displayHelper.displayPercent(remainingPercent: remainingPercent)
    }
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(groups) { group in
                VStack(spacing: 6) {
                    RingProgressView(
                        percent: displayPercent(for: group.percentage),
                        size: 44,
                        lineWidth: 5,
                        tint: displayHelper.statusTint(remainingPercent: group.percentage),
                        showLabel: true
                    )
                    
                    Text(group.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

// MARK: - Standard Lowest Bar Layout

private struct StandardLowestBarLayout: View {
    let models: [ModelQuota]
    
    private var settings: MenuBarSettingsManager { MenuBarSettingsManager.shared }
    private var displayHelper: QuotaDisplayHelper {
        QuotaDisplayHelper(displayMode: settings.quotaDisplayMode)
    }
    
    private var sorted: [ModelQuota] {
        models.sorted { $0.percentage < $1.percentage }
    }
    
    private var lowest: ModelQuota? {
        sorted.first
    }
    
    private var others: [ModelQuota] {
        Array(sorted.dropFirst())
    }
    
    private func displayPercent(for remainingPercent: Double) -> Double {
        displayHelper.displayPercent(remainingPercent: remainingPercent)
    }
    
    var body: some View {
        VStack(spacing: 10) {
            if let lowest = lowest {
                // Hero row for bottleneck
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(lowest.displayName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Spacer()
                        Text(String(format: "%.0f%%", displayPercent(for: lowest.percentage)))
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundStyle(displayHelper.statusTint(remainingPercent: lowest.percentage))
                            .monospacedDigit()
                    }
                    
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.primary.opacity(0.06))
                            Capsule()
                                .fill(displayHelper.statusTint(remainingPercent: lowest.percentage).gradient)
                                .frame(width: proxy.size.width * (displayPercent(for: lowest.percentage) / 100))
                        }
                    }
                    .frame(height: 8)
                    
                    if lowest.formattedResetTime != "—" && !lowest.formattedResetTime.isEmpty {
                        Text(lowest.formattedResetTime)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(10)
                .background(displayHelper.statusTint(remainingPercent: lowest.percentage).opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            
            // Others as compact text rows
            if !others.isEmpty {
                VStack(spacing: 4) {
                    ForEach(others) { model in
                        HStack {
                            Text(model.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if model.formattedResetTime != "—" && !model.formattedResetTime.isEmpty {
                                Text(model.formattedResetTime)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Text(String(format: "%.0f%%", displayPercent(for: model.percentage)))
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(displayHelper.statusTint(remainingPercent: model.percentage))
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Standard Ring Layout

private struct StandardRingLayout: View {
    let models: [ModelQuota]
    
    private var settings: MenuBarSettingsManager { MenuBarSettingsManager.shared }
    private var displayHelper: QuotaDisplayHelper {
        QuotaDisplayHelper(displayMode: settings.quotaDisplayMode)
    }
    
    private var columns: [GridItem] {
        let count = min(max(models.count, 1), 4)
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: count)
    }
    
    private func displayPercent(for remainingPercent: Double) -> Double {
        displayHelper.displayPercent(remainingPercent: remainingPercent)
    }
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(models) { model in
                VStack(spacing: 6) {
                    RingProgressView(
                        percent: displayPercent(for: model.percentage),
                        size: 44,
                        lineWidth: 5,
                        tint: displayHelper.statusTint(remainingPercent: model.percentage),
                        showLabel: true
                    )
                    
                    Text(model.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    
                    if model.formattedResetTime != "—" && !model.formattedResetTime.isEmpty {
                        Text(model.formattedResetTime)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }
}

// MARK: - Antigravity Models Detail Sheet

private struct AntigravityModelsDetailSheet: View {
    let email: String
    let models: [ModelQuota]
    
    @Environment(\.dismiss) private var dismiss
    
    private var settings: MenuBarSettingsManager { MenuBarSettingsManager.shared }
    
    private var sortedModels: [ModelQuota] {
        models.sorted { $0.name < $1.name }
    }
    
    private var columns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("quota.allModels".localized())
                        .font(.headline)
                    Text(email.masked(if: settings.hideSensitiveInfo))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("action.close".localized())
            }
            .padding()
            
            Divider()
                .opacity(0.5)
            
            // Models Grid
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(sortedModels) { model in
                        ModelDetailCard(model: model)
                    }
                }
                .padding()
            }
            .scrollContentBackground(.hidden)
        }
        .frame(minWidth: 480, minHeight: 360)
        .background(.background)
    }
}

// MARK: - Model Detail Card (for sheet)

private struct ModelDetailCard: View {
    let model: ModelQuota
    
    private var settings: MenuBarSettingsManager { MenuBarSettingsManager.shared }
    private var displayHelper: QuotaDisplayHelper {
        QuotaDisplayHelper(displayMode: settings.quotaDisplayMode)
    }
    
    private var remainingPercent: Double {
        max(0, min(100, model.percentage))
    }
    
    var body: some View {
        let displayPercent = displayHelper.displayPercent(remainingPercent: remainingPercent)
        let statusColor = displayHelper.statusTint(remainingPercent: remainingPercent)
        
        VStack(alignment: .leading, spacing: 8) {
            // Model name (raw name)
            Text(model.name)
                .font(.caption)
                .fontDesign(.monospaced)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            
            // Progress bar
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.06))
                    Capsule()
                        .fill(statusColor.gradient)
                        .frame(width: proxy.size.width * (displayPercent / 100))
                }
            }
            .frame(height: 6)
            
            // Footer: Percentage + Reset time
            HStack {
                Text(String(format: "%.0f%%", displayPercent))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(statusColor)
                    .monospacedDigit()
                
                Spacer()
                
                if model.formattedResetTime != "—" && !model.formattedResetTime.isEmpty {
                    Text(model.formattedResetTime)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Usage Row V2

private struct UsageRowV2: View {
    let name: String
    let icon: String?
    let usedPercent: Double
    let used: Int?
    let limit: Int?
    let resetTime: String
    let tooltip: String?
    
    private var settings: MenuBarSettingsManager { MenuBarSettingsManager.shared }
    private var displayHelper: QuotaDisplayHelper {
        QuotaDisplayHelper(displayMode: settings.quotaDisplayMode)
    }
    
    private var isUnknown: Bool {
        usedPercent < 0 || usedPercent > 100
    }
    
    private var remainingPercent: Double {
        max(0, min(100, 100 - usedPercent))
    }
    
    var body: some View {
        let displayPercent = displayHelper.displayPercent(remainingPercent: remainingPercent)
        let statusColor = displayHelper.statusTint(remainingPercent: remainingPercent)
        
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(width: 16)
                }
                
                Text(name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .help(tooltip ?? "")
                
                Spacer()
                
                if let used = used {
                    if let limit = limit, limit > 0 {
                        Text(String(used) + "/" + String(limit))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                    }
                }
                
                if !isUnknown {
                    Text(String(format: "%.0f%%", displayPercent))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(statusColor)
                        .monospacedDigit()
                } else {
                    Text("—")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
                
                if resetTime != "—" && !resetTime.isEmpty {
                    Text(resetTime)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            
            if !isUnknown {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.06))
                        Capsule()
                            .fill(statusColor.gradient)
                            .frame(width: proxy.size.width * (displayPercent / 100))
                    }
                }
                .frame(height: 6)
            }
        }
    }
}

// MARK: - Loading View

private struct QuotaLoadingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimating = false
    
    private var skeletonOpacity: Double {
        reduceMotion ? 1.0 : (isAnimating ? 0.4 : 1.0)
    }

    var body: some View {
        VStack(spacing: 16) {
            ForEach(0..<2, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                            .frame(width: 100, height: 12)
                        Spacer()
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                            .frame(width: 48, height: 12)
                    }
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                        .frame(height: 6)
                }
            }
        }
        .opacity(skeletonOpacity)
        .motionAwareAnimation(.easeOut(duration: 0.8).repeatForever(autoreverses: true), value: isAnimating)
        .onAppear { isAnimating = !reduceMotion }
        .onChange(of: reduceMotion) { _, newValue in
            isAnimating = !newValue
        }
    }
}

// MARK: - Preview

#Preview {
    QuotaScreen()
        .environment(QuotaViewModel())
        .frame(width: 600, height: 500)
}
