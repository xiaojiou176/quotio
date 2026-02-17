//
//  QuotaScreen.swift
//  Quotio
//

import SwiftUI

struct QuotaScreen: View {
    @Environment(QuotaViewModel.self) var viewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State var modeManager = OperatingModeManager.shared

    @State private var selectedProvider: AIProvider?
    @State var settings = MenuBarSettingsManager.shared
    @State private var uiExperience = UIExperienceSettingsManager.shared
    @State var featureFlags = FeatureFlagManager.shared
    @State private var uiMetrics = UIBaselineMetricsTracker.shared
    @State private var searchText: String = ""
    @State private var sortOption: AccountSortOption = .name
    @State var prioritizeAnomalies = true
    @State private var accountStatusFilter: AccountStatusFilter = .all
    @State private var compactAccountView = false
    @State private var feedbackMessage: String?
    @State private var feedbackIsError = false
    @State private var feedbackDismissTask: Task<Void, Never>?
    
    var body: some View {
        Group {
            if !hasAnyData {
                if let error = normalizedErrorMessage(viewModel.errorMessage) {
                    ContentUnavailableView {
                        Label("quota.error.loadFailed".localized(fallback: "额度加载失败"), systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("action.retry".localized(fallback: "重试")) {
                            Task {
                                await refreshQuotasWithFeedback(
                                    successMessage: "quota.feedback.refreshed".localized(fallback: "额度已刷新")
                                )
                            }
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "empty.noAccounts".localized(),
                        systemImage: "person.crop.circle.badge.questionmark",
                        description: Text("empty.addProviderAccounts".localized())
                    )
                }
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
                        await refreshQuotasWithFeedback(
                            successMessage: "quota.feedback.refreshed".localized(fallback: "额度已刷新")
                        )
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
    }
    
    // MARK: - Health Statistics

    private enum HealthCategory {
        case ready
        case cooling
        case error
    }

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

    private func matchedQuota(for file: AuthFile) -> ProviderQuotaData? {
        guard let provider = file.providerType,
              let providerData = viewModel.providerQuotas[provider] else {
            return nil
        }
        let possibleKeys = Array(Set(
            [file.quotaLookupKey, file.email ?? "", file.name] + codexDerivedLookupKeys(from: file.name)
        ))
        for key in possibleKeys where !key.isEmpty {
            if let quota = providerData[key] {
                return quota
            }
        }
        return nil
    }

    private func codexRemainingPercent(for quota: ProviderQuotaData?, modelName: String) -> Double {
        quota?.models.first(where: { $0.name == modelName })?.percentage ?? 100
    }

    private func healthCategory(for file: AuthFile) -> HealthCategory {
        let quota = matchedQuota(for: file)

        if file.providerType == .codex {
            if file.isFatalDisabled {
                return .error
            }

            let weeklyRemaining = codexRemainingPercent(for: quota, modelName: "codex-weekly")
            let sessionRemaining = codexRemainingPercent(for: quota, modelName: "codex-session")
            let is7dCooling = file.isQuotaLimited7d || weeklyRemaining <= 0.1
            if is7dCooling {
                return .cooling
            }

            let is5hCooling = file.isQuotaLimited5h || sessionRemaining <= 0.1
            if is5hCooling {
                return .cooling
            }

            if file.disabled || file.unavailable || file.isNetworkError || file.status == "error" || file.status == "expired" {
                return .error
            }
            return .ready
        }

        if file.isFatalDisabled {
            return .error
        }
        if file.isQuotaLimited7d || file.isQuotaLimited5h || file.status == "cooling" {
            return .cooling
        }
        if file.disabled || file.unavailable || file.status == "error" || file.status == "expired" {
            return .error
        }
        if file.status == "ready" {
            return .ready
        }

        if let quota {
            if quota.isForbidden {
                return .error
            }
            if quota.models.allSatisfy({ $0.percentage <= 5 }) {
                return .cooling
            }
        }
        return .ready
    }

    private var anomalyCounts: (disabled: Int, quota5h: Int, quota7d: Int, fatal: Int, network: Int) {
        let fatal = viewModel.authFiles.filter { $0.isFatalDisabled }.count
        let quota7d = viewModel.authFiles.filter { !$0.isFatalDisabled && $0.isQuotaLimited7d }.count
        let quota5h = viewModel.authFiles.filter { !$0.isFatalDisabled && !$0.isQuotaLimited7d && $0.isQuotaLimited5h }.count
        return (
            disabled: viewModel.authFiles.filter { $0.disabled }.count,
            quota5h: quota5h,
            quota7d: quota7d,
            fatal: fatal,
            network: viewModel.authFiles.filter { $0.isNetworkError }.count
        )
    }
    
    private var healthStats: (total: Int, ready: Int, cooling: Int, error: Int) {
        var total = 0
        var ready = 0
        var cooling = 0
        var error = 0
        
        // First, try to use authFiles if available (from management API)
        if !viewModel.authFiles.isEmpty {
            for file in viewModel.authFiles {
                total += 1
                switch healthCategory(for: file) {
                case .ready:
                    ready += 1
                case .cooling:
                    cooling += 1
                case .error:
                    error += 1
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
                    .padding(.top, 12)
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private var anomalyQuickSection: some View {
        let stats = healthStats
        let anomalies = anomalyCounts
        return HStack(spacing: 8) {
            anomalyChip(title: "quota.health.error".localized(fallback: "错误"), value: stats.error, color: Color.semanticDanger, filter: .error)
            anomalyChip(title: "quota.health.cooling".localized(fallback: "冷却中"), value: stats.cooling, color: Color.semanticWarning, filter: .cooling)
            anomalyChip(title: "quota.status.disabled".localized(fallback: "禁用"), value: anomalies.disabled, color: .secondary, filter: .disabled)
            anomalyChip(title: "quota.status.quota5h.short".localized(fallback: "5h"), value: anomalies.quota5h, color: Color.semanticWarning, filter: .quota5h)
            anomalyChip(title: "quota.status.quota7d.short".localized(fallback: "7d"), value: anomalies.quota7d, color: Color.semanticAccentSecondary, filter: .quota7d)
            anomalyChip(title: "quota.status.fatal.short".localized(fallback: "致命"), value: anomalies.fatal, color: Color.semanticDanger, filter: .fatalDisabled)
            anomalyChip(title: "quota.status.network.short".localized(fallback: "网络"), value: anomalies.network, color: Color.semanticInfo, filter: .networkError)
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
            .padding(.horizontal, 12)
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
                    .padding(.horizontal, 12)
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
                        .padding(.horizontal, 12)
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
                            await refreshQuotasWithFeedback(
                                successMessage: "quota.feedback.providerRefreshed".localized(fallback: "当前 Provider 已刷新")
                            )
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
                    .padding(.horizontal, 12)
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
                    .padding(.horizontal, 12)
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
                        await refreshQuotasWithFeedback(
                            successMessage: "quota.feedback.refreshedAll".localized(fallback: "全部额度已刷新")
                        )
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
                    .padding(.horizontal, 12)
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
            RoundedRectangle(cornerRadius: 8, style: .continuous)
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
        guard !targets.isEmpty else {
            showFeedback("quota.feedback.noAbnormalAccounts".localized(fallback: "当前 Provider 没有可批量禁用的异常账号"))
            return
        }

        let previousError = normalizedErrorMessage(viewModel.errorMessage)
        for file in targets {
            await viewModel.toggleAuthFileDisabled(file)
        }
        await viewModel.refreshQuotasUnified()

        if let actionError = latestActionError(previousError: previousError) {
            showFeedback(
                "quota.feedback.bulkDisableFailed".localized(fallback: "批量禁用失败") + ": " + actionError,
                isError: true
            )
            return
        }

        showFeedback(
            "quota.feedback.bulkDisabled".localized(fallback: "已批量禁用异常账号") + " (\(targets.count))"
        )
    }

    private func bulkEnableDisabledAccounts() async {
        guard !isRunningBulkAction else { return }
        isRunningBulkAction = true
        defer { isRunningBulkAction = false }

        let targets = currentProviderAuthFiles.filter { $0.disabled }
        guard !targets.isEmpty else {
            showFeedback("quota.feedback.noDisabledAccounts".localized(fallback: "当前 Provider 没有已禁用账号"))
            return
        }

        let previousError = normalizedErrorMessage(viewModel.errorMessage)
        for file in targets {
            await viewModel.toggleAuthFileDisabled(file)
        }
        await viewModel.refreshQuotasUnified()

        if let actionError = latestActionError(previousError: previousError) {
            showFeedback(
                "quota.feedback.bulkEnableFailed".localized(fallback: "批量启用失败") + ": " + actionError,
                isError: true
            )
            return
        }

        showFeedback(
            "quota.feedback.bulkEnabled".localized(fallback: "已批量启用账号") + " (\(targets.count))"
        )
    }

    private func refreshQuotasWithFeedback(successMessage: String) async {
        let previousError = normalizedErrorMessage(viewModel.errorMessage)
        await viewModel.refreshQuotasUnified()

        if let actionError = latestActionError(previousError: previousError) {
            showFeedback(
                "quota.feedback.refreshFailed".localized(fallback: "额度刷新失败") + ": " + actionError,
                isError: true
            )
            return
        }

        showFeedback(successMessage)
    }

    private func latestActionError(previousError: String?) -> String? {
        guard let currentError = normalizedErrorMessage(viewModel.errorMessage) else {
            return nil
        }
        if currentError == previousError {
            return nil
        }
        return currentError
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
            HStack(spacing: 12) {
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
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
        .scrollClipDisabled()
    }
}
