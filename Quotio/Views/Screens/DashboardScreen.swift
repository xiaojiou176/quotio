//
//  DashboardScreen.swift
//  Quotio
//

import SwiftUI
import UniformTypeIdentifiers

struct DashboardScreen: View {
    @Environment(QuotaViewModel.self) var viewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("hideGettingStarted") private var hideGettingStarted: Bool = false
    @AppStorage(QuotioMotionProfileStorage.key) private var motionProfileRaw = QuotioMotionProfile.default.rawValue
    @State var modeManager = OperatingModeManager.shared

    @State private var selectedProvider: AIProvider?
    @State private var projectId: String = ""
    @State private var isImporterPresented = false
    @State private var selectedAgentForConfig: CLIAgent?
    @State private var sheetPresentationID = UUID()
    @State private var showTunnelSheet = false
    @State private var feedback: TopFeedbackItem?
    @State private var dashboardEntrancePhase = 0
    @State private var toolbarRefreshFeedbackState: ToolbarActionFeedbackState = .idle
    @State private var quotaRefreshFeedbackState: ToolbarActionFeedbackState = .idle
    @State private var installFeedbackState: ToolbarActionFeedbackState = .idle
    
    private var tunnelManager: TunnelManager { TunnelManager.shared }
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

    private var dashboardContentStateID: String {
        if modeManager.isRemoteProxyMode { return "remote" }
        if modeManager.isMonitorMode { return "monitor" }
        if !viewModel.proxyManager.isBinaryInstalled { return "install" }
        if !viewModel.proxyManager.proxyStatus.running { return "start" }
        return "full"
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
                        .id("remote")
                        .transition(dashboardStateTransition)
                        .opacity(layerOpacity(2))
                        .offset(y: layerOffset(2))
                } else if modeManager.isLocalProxyMode {
                    // Full Mode: Check binary and proxy status
                    if !viewModel.proxyManager.isBinaryInstalled {
                        installBinarySection
                            .id("install")
                            .transition(dashboardStateTransition)
                    } else if !viewModel.proxyManager.proxyStatus.running {
                        startProxySection
                            .id("start")
                            .transition(dashboardStateTransition)
                    } else {
                        fullModeContent
                            .id("full")
                            .transition(dashboardStateTransition)
                    }
                } else {
                    // Quota-Only Mode: Show quota dashboard
                    quotaOnlyModeContent
                        .id("monitor")
                        .transition(dashboardStateTransition)
                }
            }
            .id(dashboardContentStateID)
            .padding(24)
        }
        .motionAwareAnimation(QuotioMotion.pageEnter, value: dashboardContentStateID)
        .motionAwareAnimation(QuotioMotion.pageExit, value: dashboardContentStateID)
        .motionAwareAnimation(QuotioMotion.contentSwap, value: viewModel.providerQuotas.isEmpty)
        .navigationTitle("nav.dashboard".localized())
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await runDashboardRefreshWithFeedback() }
                } label: {
                    actionFeedbackGlyph(
                        state: toolbarRefreshFeedbackState,
                        idleIcon: "arrow.clockwise"
                    )
                    .motionAwareAnimation(feedbackPulseAnimation, value: toolbarRefreshFeedbackState)
                }
                .buttonStyle(.toolbarIcon)
                .disabled(viewModel.isLoadingQuotas || toolbarRefreshFeedbackState == .busy)
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
        .task(id: dashboardContentStateID) {
            runDashboardEntrance()
        }
        .overlay(alignment: .top) {
            TopFeedbackBanner(item: $feedback)
        }
    }
    
    // MARK: - Full Mode Content
    
    private var fullModeContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            if showGettingStarted {
                gettingStartedSection
                    .opacity(layerOpacity(1))
                    .offset(y: layerOffset(1))
            }
            
            kpiSection
                .opacity(layerOpacity(1))
                .offset(y: layerOffset(1))
            operationsCenterSection
                .opacity(layerOpacity(2))
                .offset(y: layerOffset(2))
            providerSection
                .opacity(layerOpacity(2))
                .offset(y: layerOffset(2))
            endpointSection
                .opacity(layerOpacity(3))
                .offset(y: layerOffset(3))
            tunnelSection
                .opacity(layerOpacity(3))
                .offset(y: layerOffset(3))
        }
    }
    
    // MARK: - Quota-Only Mode Content
    
    private var quotaOnlyModeContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Quota Overview KPIs
            quotaOnlyKPISection
                .opacity(layerOpacity(1))
                .offset(y: layerOffset(1))
            
            // Quick Quota Status
            quotaStatusSection
                .opacity(layerOpacity(2))
                .offset(y: layerOffset(2))
            
            // Tracked Accounts
            trackedAccountsSection
                .opacity(layerOpacity(3))
                .offset(y: layerOffset(3))
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
                        Task { await runQuotaRefreshWithFeedback() }
                    } label: {
                        HStack(spacing: 6) {
                            actionFeedbackGlyph(
                                state: quotaRefreshFeedbackState,
                                idleIcon: "arrow.clockwise"
                            )
                            Text("action.refresh".localized())
                        }
                    }
                    .buttonStyle(.bordered)
                    .motionAwareAnimation(feedbackPulseAnimation, value: quotaRefreshFeedbackState)
                    .disabled(viewModel.isLoadingQuotas || quotaRefreshFeedbackState == .busy)
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
            }

            if !viewModel.proxyManager.isDownloading {
                Button {
                    Task { await runInstallBinaryWithFeedback() }
                } label: {
                    HStack(spacing: 8) {
                        actionFeedbackGlyph(
                            state: installFeedbackState,
                            idleIcon: "arrow.down.circle"
                        )
                        Text("dashboard.installCLI".localized())
                    }
                }
                .buttonStyle(.borderedProminent)
                .motionAwareAnimation(feedbackPulseAnimation, value: installFeedbackState)
                .disabled(installFeedbackState == .busy)
            }
            
            if let error = viewModel.proxyManager.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Color.semanticDanger)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 300)
        .opacity(layerOpacity(2))
        .offset(y: layerOffset(2))
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
        let item = isError ? TopFeedbackItem.error(message) : TopFeedbackItem.success(message)
        withMotionAwareAnimation(QuotioMotion.successEmphasis, reduceMotion: reduceMotion) {
            feedback = item
        }
    }

    @ViewBuilder
    private func actionFeedbackGlyph(
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

    private func runDashboardRefreshWithFeedback() async {
        await MainActor.run {
            toolbarRefreshFeedbackState = .busy
        }
        let previousError = normalizedErrorMessage(viewModel.errorMessage)
        if modeManager.isLocalProxyMode && viewModel.proxyManager.proxyStatus.running {
            await viewModel.refreshData()
        } else {
            await viewModel.refreshQuotasUnified()
        }
        let actionError = latestActionError(previousError: previousError)
        await MainActor.run {
            if let actionError {
                toolbarRefreshFeedbackState = .failure
                showFeedback(
                    "dashboard.feedback.refreshFailed".localized(fallback: "刷新失败") + ": " + actionError,
                    isError: true
                )
            } else {
                toolbarRefreshFeedbackState = .success
                showFeedback("dashboard.feedback.refreshed".localized(fallback: "仪表盘已刷新"))
            }
        }
        try? await Task.sleep(for: .milliseconds(feedbackPulseMilliseconds))
        await MainActor.run {
            if toolbarRefreshFeedbackState != .busy {
                toolbarRefreshFeedbackState = .idle
            }
        }
    }

    private func runQuotaRefreshWithFeedback() async {
        await MainActor.run {
            quotaRefreshFeedbackState = .busy
        }
        let previousError = normalizedErrorMessage(viewModel.errorMessage)
        await viewModel.refreshQuotasDirectly()
        let actionError = latestActionError(previousError: previousError)
        await MainActor.run {
            if let actionError {
                quotaRefreshFeedbackState = .failure
                showFeedback(
                    "dashboard.feedback.refreshFailed".localized(fallback: "刷新失败") + ": " + actionError,
                    isError: true
                )
            } else {
                quotaRefreshFeedbackState = .success
                showFeedback("dashboard.feedback.refreshed".localized(fallback: "配额已刷新"))
            }
        }
        try? await Task.sleep(for: .milliseconds(feedbackPulseMilliseconds))
        await MainActor.run {
            if quotaRefreshFeedbackState != .busy {
                quotaRefreshFeedbackState = .idle
            }
        }
    }

    private func runInstallBinaryWithFeedback() async {
        await MainActor.run {
            installFeedbackState = .busy
        }
        do {
            try await viewModel.proxyManager.downloadAndInstallBinary()
            await MainActor.run {
                installFeedbackState = .success
                showFeedback("dashboard.feedback.installed".localized(fallback: "CLIProxyAPI 已安装"))
            }
        } catch {
            await MainActor.run {
                viewModel.errorMessage = error.localizedDescription
                installFeedbackState = .failure
                showFeedback(
                    "dashboard.feedback.installFailed".localized(fallback: "安装失败") + ": " + error.localizedDescription,
                    isError: true
                )
            }
        }
        try? await Task.sleep(for: .milliseconds(feedbackPulseMilliseconds))
        await MainActor.run {
            if installFeedbackState != .busy {
                installFeedbackState = .idle
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
        .opacity(layerOpacity(2))
        .offset(y: layerOffset(2))
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
                    withMotionAwareAnimation(QuotioMotion.dismiss, reduceMotion: reduceMotion) {
                        hideGettingStarted = true
                    }
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
                    ForEach(Array(riskAccounts.enumerated()), id: \.element.id) { index, account in
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
                        .opacity(riskRowOpacity)
                        .offset(y: riskRowOffset(index: index))
                        .motionAwareAnimation(riskRowAnimation(index: index), value: dashboardEntrancePhase)
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

    private func runDashboardEntrance() {
        let contentSwapDelay: Double = motionProfile == .crisp ? 0.06 : 0.08
        let springDelay: Double = motionProfile == .crisp ? 0.12 : 0.16
        guard !reduceMotion else {
            dashboardEntrancePhase = 3
            return
        }
        dashboardEntrancePhase = 0
        withMotionAwareAnimation(QuotioMotion.pageEnter, reduceMotion: reduceMotion) {
            dashboardEntrancePhase = 1
        }
        withMotionAwareAnimation(QuotioMotion.contentSwap.delay(contentSwapDelay), reduceMotion: reduceMotion) {
            dashboardEntrancePhase = 2
        }
        withMotionAwareAnimation(QuotioMotion.gentleSpring.delay(springDelay), reduceMotion: reduceMotion) {
            dashboardEntrancePhase = 3
        }
    }

    private func layerOpacity(_ phase: Int) -> Double {
        reduceMotion || dashboardEntrancePhase >= phase ? 1 : 0
    }

    private func layerOffset(_ phase: Int) -> CGFloat {
        guard !reduceMotion, dashboardEntrancePhase < phase else { return 0 }
        let base: CGFloat = motionProfile == .crisp ? 7 : 9
        let step: CGFloat = motionProfile == .crisp ? 1.5 : 2
        return base + CGFloat(phase) * step
    }

    private var riskRowOpacity: Double {
        reduceMotion || dashboardEntrancePhase >= 2 ? 1 : 0
    }

    private func riskRowOffset(index: Int) -> CGFloat {
        guard !reduceMotion, dashboardEntrancePhase < 2 else { return 0 }
        return CGFloat(4 + min(index, 5) * 2)
    }

    private func riskRowAnimation(index: Int) -> Animation? {
        guard !reduceMotion else { return nil }
        let step = motionProfile == .crisp ? 0.016 : 0.024
        return QuotioMotion.contentSwap.delay(Double(min(index, 5)) * step)
    }

    private var dashboardStateTransition: AnyTransition {
        guard !reduceMotion else { return .identity }
        let insertionOffset: CGFloat = motionProfile == .crisp ? 8 : 12
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: insertionOffset)),
            removal: .opacity
        )
    }
}
