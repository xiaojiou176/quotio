//
//  DashboardScreen.swift
//  Quotio
//

import SwiftUI
import UniformTypeIdentifiers

struct DashboardScreen: View {
    @Environment(QuotaViewModel.self) var viewModel
    @AppStorage("hideGettingStarted") private var hideGettingStarted: Bool = false
    @State var modeManager = OperatingModeManager.shared

    @State private var selectedProvider: AIProvider?
    @State private var projectId: String = ""
    @State private var isImporterPresented = false
    @State private var selectedAgentForConfig: CLIAgent?
    @State private var sheetPresentationID = UUID()
    @State private var showTunnelSheet = false
    @State private var feedbackMessage: String?
    @State private var feedbackIsError = false
    @State private var feedbackDismissTask: Task<Void, Never>?
    
    private var tunnelManager: TunnelManager { TunnelManager.shared }
    
    private var showGettingStarted: Bool {
        guard !hideGettingStarted else { return false }
        guard modeManager.isLocalProxyMode else { return false }
        return !isSetupComplete
    }
    
    private var isSetupComplete: Bool {
        viewModel.proxyManager.isBinaryInstalled &&
        viewModel.proxyManager.proxyStatus.running &&
        !viewModel.authFiles.isEmpty &&
        viewModel.agentSetupViewModel.agentStatuses.contains(where: { $0.configured })
    }
    
    /// Check if we should show main content
    private var shouldShowContent: Bool {
        if modeManager.isMonitorMode {
            return true // Always show content in quota-only mode
        }
        return viewModel.proxyManager.proxyStatus.running
    }
    
    // MARK: - Precomputed Properties (performance optimization)
    
    /// Unique provider count from direct auth files
    private var directProvidersCount: Int {
        Set(viewModel.directAuthFiles.map { $0.provider }).count
    }
    
    /// Lowest quota percentage across all providers using total usage logic
    private var lowestQuotaPercentage: Double {
        let settings = MenuBarSettingsManager.shared
        var allTotals: [Double] = []
        
        for (_, accountQuotas) in viewModel.providerQuotas {
            for (_, quotaData) in accountQuotas {
                let models = quotaData.models.map { (name: $0.name, percentage: $0.percentage) }
                let total = settings.totalUsagePercent(models: models)
                if total >= 0 {
                    allTotals.append(total)
                }
            }
        }
        
        return allTotals.min() ?? 100
    }
    
    /// Grouped accounts by provider (cached computation)
    private var groupedDirectAuthFiles: [AIProvider: [DirectAuthFile]] {
        Dictionary(grouping: viewModel.directAuthFiles) { $0.provider }
    }

    private var riskAccounts: [AuthFile] {
        let scored: [(AuthFile, Int)] = viewModel.authFiles.map { file in
            var score = 0
            if file.disabledByPolicy == true { score += 100 }
            if file.status == "error" { score += 60 }
            if file.status == "cooling" { score += 30 }
            if file.isNetworkError { score += 20 }
            if file.isQuotaLimited7d { score += 15 }
            if file.isQuotaLimited5h { score += 10 }
            return (file, score)
        }
        return scored
            .filter { $0.1 > 0 }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return lhs.0.name < rhs.0.name
            }
            .prefix(5)
            .map(\.0)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if modeManager.isRemoteProxyMode {
                    // Remote Mode: Show remote connection status and data
                    remoteModeContent
                } else if modeManager.isLocalProxyMode {
                    // Full Mode: Check binary and proxy status
                    if !viewModel.proxyManager.isBinaryInstalled {
                        installBinarySection
                    } else if !viewModel.proxyManager.proxyStatus.running {
                        startProxySection
                    } else {
                        fullModeContent
                    }
                } else {
                    // Quota-Only Mode: Show quota dashboard
                    quotaOnlyModeContent
                }
            }
            .padding(24)
        }
        .navigationTitle("nav.dashboard".localized())
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        let previousError = normalizedErrorMessage(viewModel.errorMessage)
                        if modeManager.isLocalProxyMode && viewModel.proxyManager.proxyStatus.running {
                            await viewModel.refreshData()
                        } else {
                            await viewModel.refreshQuotasUnified()
                        }
                        if let actionError = latestActionError(previousError: previousError) {
                            showFeedback(
                                "dashboard.feedback.refreshFailed".localized(fallback: "刷新失败") + ": " + actionError,
                                isError: true
                            )
                        } else {
                            showFeedback("dashboard.feedback.refreshed".localized(fallback: "仪表盘已刷新"))
                        }
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(viewModel.isLoadingQuotas)
                .accessibilityLabel("action.refresh".localized())
                .help("action.refresh".localized())
            }
        }
        .sheet(item: $selectedProvider) { provider in
            OAuthSheet(provider: provider, projectId: $projectId) {
                selectedProvider = nil
                projectId = ""
                viewModel.oauthState = nil
                Task { await viewModel.refreshData() }
            }
            .environment(viewModel)
        }
        .sheet(item: $selectedAgentForConfig) { (agent: CLIAgent) in
            AgentConfigSheet(viewModel: viewModel.agentSetupViewModel, agent: agent)
                .id(sheetPresentationID)
                .onDisappear {
                    viewModel.agentSetupViewModel.dismissConfiguration()
                    Task { await viewModel.agentSetupViewModel.refreshAgentStatuses() }
                }
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                Task {
                    let previousError = normalizedErrorMessage(viewModel.errorMessage)
                    await viewModel.importVertexServiceAccount(url: url)
                    await viewModel.refreshData()
                    if let actionError = latestActionError(previousError: previousError) {
                        showFeedback(
                            "dashboard.feedback.importFailed".localized(fallback: "导入失败") + ": " + actionError,
                            isError: true
                        )
                    } else {
                        showFeedback("dashboard.feedback.imported".localized(fallback: "账号导入已完成"))
                    }
                }
            } else if case .failure(let error) = result {
                showFeedback(
                    "dashboard.feedback.importFailed".localized(fallback: "导入失败") + ": " + error.localizedDescription,
                    isError: true
                )
            }
        }
        .task {
            if modeManager.isLocalProxyMode {
                await viewModel.agentSetupViewModel.refreshAgentStatuses()
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
        .onDisappear {
            feedbackDismissTask?.cancel()
        }
    }
    
    // MARK: - Full Mode Content
    
    private var fullModeContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            if showGettingStarted {
                gettingStartedSection
            }
            
            kpiSection
            operationsCenterSection
            providerSection
            endpointSection
            tunnelSection
        }
    }
    
    // MARK: - Quota-Only Mode Content
    
    private var quotaOnlyModeContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Quota Overview KPIs
            quotaOnlyKPISection
            
            // Quick Quota Status
            quotaStatusSection
            
            // Tracked Accounts
            trackedAccountsSection
        }
    }
    
    private var quotaOnlyKPISection: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 16)], spacing: 16) {
            KPICard(
                title: "dashboard.trackedAccounts".localized(),
                value: "\(viewModel.directAuthFiles.count)",
                subtitle: "dashboard.accounts".localized(),
                icon: "person.2.fill",
                color: Color.semanticInfo
            )
            
            KPICard(
                title: "dashboard.providers".localized(),
                value: "\(directProvidersCount)",
                subtitle: "dashboard.connected".localized(),
                icon: "cpu",
                color: Color.semanticSuccess
            )
            
            // Show lowest quota percentage (precomputed)
            KPICard(
                title: "dashboard.lowestQuota".localized(),
                value: String(format: "%.0f%%", lowestQuotaPercentage),
                subtitle: "dashboard.remaining".localized(),
                icon: "chart.bar.fill",
                color: lowestQuotaPercentage > 50 ? Color.semanticSuccess : (lowestQuotaPercentage > 20 ? Color.semanticWarning : Color.semanticDanger)
            )
            
            if let lastRefresh = viewModel.lastQuotaRefreshTime {
                KPICard(
                    title: "dashboard.lastRefresh".localized(),
                    value: lastRefresh.formatted(date: .omitted, time: .shortened),
                    subtitle: "dashboard.updated".localized(),
                    icon: "clock.fill",
                    color: Color.semanticAccentSecondary
                )
            }
        }
    }
    
    private var quotaStatusSection: some View {
        GroupBox {
            if viewModel.providerQuotas.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    
                    Text("dashboard.noQuotaData".localized())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Button {
                        Task { await viewModel.refreshQuotasDirectly() }
                    } label: {
                        Label("action.refresh".localized(), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isLoadingQuotas)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    // Sort providers for stable iteration order (ForEach performance fix)
                    ForEach(viewModel.providerQuotas.keys.sorted { $0.displayName < $1.displayName }) { provider in
                        if let accounts = viewModel.providerQuotas[provider], !accounts.isEmpty {
                            QuotaProviderRow(provider: provider, accounts: accounts)
                        }
                    }
                }
            }
        } label: {
            HStack {
                Label("dashboard.quotaOverview".localized(), systemImage: "chart.bar.fill")
                
                Spacer()
                
                if viewModel.isLoadingQuotas {
                    SmallProgressView()
                }
            }
        }
    }
    
    private var trackedAccountsSection: some View {
        GroupBox {
            if viewModel.directAuthFiles.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    
                    Text("dashboard.noAccountsTracked".localized())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Text("dashboard.addAccountsHint".localized())
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    // Use precomputed groupedDirectAuthFiles instead of inline Dictionary(grouping:)
                    ForEach(AIProvider.allCases.filter { groupedDirectAuthFiles[$0] != nil }) { provider in
                        if let accounts = groupedDirectAuthFiles[provider] {
                            HStack(spacing: 12) {
                                ProviderIcon(provider: provider, size: 20)
                                
                                Text(provider.displayName)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                Spacer()
                                
                                Text("\(accounts.count)")
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(provider.color.opacity(0.15))
                                    .foregroundStyle(provider.color)
                                    .clipShape(Capsule())
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        } label: {
            Label("dashboard.trackedAccounts".localized(), systemImage: "person.2.badge.key")
        }
    }
    
    // MARK: - Install Binary
    
    private var installBinarySection: some View {
        ContentUnavailableView {
            Label("dashboard.cliNotInstalled".localized(), systemImage: "arrow.down.circle")
        } description: {
            Text("dashboard.clickToInstall".localized())
        } actions: {
            if viewModel.proxyManager.isDownloading {
                ProgressView(value: viewModel.proxyManager.downloadProgress)
                    .progressViewStyle(.linear)
                    .frame(width: 200)
            } else {
                Button("dashboard.installCLI".localized()) {
                    Task {
                        do {
                            try await viewModel.proxyManager.downloadAndInstallBinary()
                            showFeedback("dashboard.feedback.installed".localized(fallback: "CLIProxyAPI 已安装"))
                        } catch {
                            viewModel.errorMessage = error.localizedDescription
                            showFeedback(
                                "dashboard.feedback.installFailed".localized(fallback: "安装失败") + ": " + error.localizedDescription,
                                isError: true
                            )
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            
            if let error = viewModel.proxyManager.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Color.semanticDanger)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 300)
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
    
    // MARK: - Start Proxy
    
    private var startProxySection: some View {
        ProxyRequiredView(
            description: "dashboard.startToBegin".localized()
        ) {
            await viewModel.startProxy()
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }
    
    // MARK: - Getting Started Section
    
    private var gettingStartedSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(gettingStartedSteps) { step in
                    GettingStartedStepRow(
                        step: step,
                        onAction: { handleStepAction(step) }
                    )
                    
                    if step.id != gettingStartedSteps.last?.id {
                        Divider()
                    }
                }
            }
        } label: {
            HStack {
                Label("dashboard.gettingStarted".localized(), systemImage: "sparkles")
                
                Spacer()
                
                Button {
                    withAnimation { hideGettingStarted = true }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("action.dismiss".localized())
                .accessibilityLabel("action.dismiss".localized())
            }
        }
    }
    
    private var gettingStartedSteps: [GettingStartedStep] {
        [
            GettingStartedStep(
                id: "provider",
                icon: "person.2.badge.key",
                title: "onboarding.addProvider".localized(),
                description: "onboarding.addProviderDesc".localized(),
                isCompleted: !viewModel.authFiles.isEmpty,
                actionLabel: viewModel.authFiles.isEmpty ? "providers.addProvider".localized() : nil
            ),
            GettingStartedStep(
                id: "agent",
                icon: "terminal",
                title: "onboarding.configureAgent".localized(),
                description: "onboarding.configureAgentDesc".localized(),
                isCompleted: viewModel.agentSetupViewModel.agentStatuses.contains(where: { $0.configured }),
                actionLabel: viewModel.agentSetupViewModel.agentStatuses.contains(where: { $0.configured }) ? nil : "agents.configure".localized()
            )
        ]
    }
    
    private func handleStepAction(_ step: GettingStartedStep) {
        switch step.id {
        case "provider":
            showProviderPicker()
        case "agent":
            showAgentPicker()
        default:
            break
        }
    }
    
    private func showProviderPicker() {
        let alert = NSAlert()
        alert.messageText = "providers.addProvider".localized()
        alert.informativeText = "onboarding.addProviderDesc".localized()
        
        for provider in AIProvider.allCases {
            alert.addButton(withTitle: provider.displayName)
        }
        alert.addButton(withTitle: "action.cancel".localized())
        
        let response = alert.runModal()
        let index = response.rawValue - 1000
        
        if index >= 0 && index < AIProvider.allCases.count {
            let provider = AIProvider.allCases[index]
            if provider == .vertex {
                isImporterPresented = true
            } else {
                viewModel.oauthState = nil
                selectedProvider = provider
            }
        }
    }
    
    private func showAgentPicker() {
        let installedAgents = viewModel.agentSetupViewModel.agentStatuses.filter { $0.installed }
        guard let firstAgent = installedAgents.first else { return }
        
        let apiKey = viewModel.apiKeys.first ?? viewModel.proxyManager.managementKey
        viewModel.agentSetupViewModel.startConfiguration(for: firstAgent.agent, apiKey: apiKey)
        sheetPresentationID = UUID()
        selectedAgentForConfig = firstAgent.agent
    }
    
    // MARK: - KPI Section
    
    var kpiSection: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 16)], spacing: 16) {
            KPICard(
                title: "dashboard.accounts".localized(),
                value: "\(viewModel.totalAccounts)",
                subtitle: "\(viewModel.readyAccounts) " + "dashboard.ready".localized(),
                icon: "person.2.fill",
                color: Color.semanticInfo
            )
            
            KPICard(
                title: "dashboard.requests".localized(),
                value: "\(viewModel.usageStats?.usage?.totalRequests ?? 0)",
                subtitle: "dashboard.total".localized(),
                icon: "arrow.up.arrow.down",
                color: Color.semanticSuccess
            )
            
            KPICard(
                title: "dashboard.tokens".localized(),
                value: (viewModel.usageStats?.usage?.totalTokens ?? 0).formattedCompact,
                subtitle: "dashboard.processed".localized(),
                icon: "text.word.spacing",
                color: Color.semanticAccentSecondary
            )
            
            KPICard(
                title: "dashboard.successRate".localized(),
                value: String(format: "%.0f%%", viewModel.usageStats?.usage?.successRate ?? 0.0),
                subtitle: "\(viewModel.usageStats?.usage?.failureCount ?? 0) " + "dashboard.failed".localized(),
                icon: "checkmark.circle.fill",
                color: Color.semanticWarning
            )
        }
    }

    var operationsCenterSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("dashboard.operationsCenter.title".localized(fallback: "指挥中心"), systemImage: "dot.radiowaves.up.forward")
                        .font(.headline)
                    Spacer()
                    Text("\("dashboard.operationsCenter.riskCount".localized(fallback: "风险账号")) \(riskAccounts.count)")
                        .font(.caption)
                        .foregroundStyle(riskAccounts.isEmpty ? Color.secondary : Color.semanticWarning)
                }

                if riskAccounts.isEmpty {
                    Label("dashboard.operationsCenter.noRisk".localized(fallback: "当前无高风险账号"), systemImage: "checkmark.seal")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(riskAccounts, id: \.id) { account in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(account.isFatalDisabled ? Color.semanticDanger : (account.status == "error" ? Color.semanticWarning : Color.semanticInfo))
                                .frame(width: 6, height: 6)
                            Text(account.name.masked(if: MenuBarSettingsManager.shared.hideSensitiveInfo))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text(account.errorKind ?? account.status)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    }
                }

                HStack(spacing: 8) {
                    Button("dashboard.operationsCenter.inspectQuota".localized(fallback: "查看配额异常")) {
                        viewModel.currentPage = .quota
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    if modeManager.isProxyMode {
                        Button("dashboard.operationsCenter.inspectLogs".localized(fallback: "打开日志排查")) {
                            viewModel.currentPage = .logs
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    // MARK: - Provider Section
    
    var providerSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                FlowLayout(spacing: 8) {
                    // Connected providers - clickable to add more accounts
                    ForEach(viewModel.connectedProviders) { provider in
                        if provider.supportsManualAuth {
                            Button {
                                if provider == .vertex {
                                    isImporterPresented = true
                                } else {
                                    viewModel.oauthState = nil
                                    selectedProvider = provider
                                }
                            } label: {
                                ProviderChipWithAdd(provider: provider, count: viewModel.authFilesByProvider[provider]?.count ?? 0)
                            }
                            .buttonStyle(.plain)
                            .help("dashboard.addMoreAccounts".localized(fallback: "点击添加更多账号"))
                        } else {
                            ProviderChip(provider: provider, count: viewModel.authFilesByProvider[provider]?.count ?? 0)
                        }
                    }
                    
                    // Disconnected providers - show add button
                    ForEach(viewModel.disconnectedProviders.filter { $0.supportsManualAuth }) { provider in
                        Button {
                            if provider == .vertex {
                                isImporterPresented = true
                            } else {
                                viewModel.oauthState = nil
                                selectedProvider = provider
                            }
                        } label: {
                            Label(provider.displayName, systemImage: "plus.circle")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .tint(.secondary)
                    }
                }
            }
        } label: {
            Label("dashboard.providers".localized(), systemImage: "cpu")
        }
    }
    
    // MARK: - Endpoint Section

    /// The display endpoint for clients to connect to
    private var displayEndpoint: String {
        // Always use client endpoint - all traffic should go through Quotio's proxy
        return viewModel.proxyManager.clientEndpoint + "/v1"
    }

    private var endpointSection: some View {
        DashboardEndpointSection(endpoint: displayEndpoint)
    }
    
    // MARK: - Tunnel Section
    
    private var tunnelSection: some View {
        DashboardTunnelSection(
            tunnelManager: tunnelManager,
            showTunnelSheet: $showTunnelSheet
        )
        .sheet(isPresented: $showTunnelSheet) {
            TunnelSheet()
                .environment(viewModel)
        }
    }
}
