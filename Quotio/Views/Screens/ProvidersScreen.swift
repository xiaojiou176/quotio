//
//  ProvidersScreen.swift
//  Quotio
//
//  Redesigned ProvidersScreen with improved UI/UX:
//  - Consolidated from 5-6 sections to 2 main sections
//  - Accounts grouped by provider using DisclosureGroup
//  - Add Provider moved to toolbar popover
//  - IDE Scan integrated into toolbar and empty state
//
import SwiftUI
import AppKit
import UniformTypeIdentifiers
struct ProvidersScreen: View {
    @Environment(QuotaViewModel.self) var viewModel
    @State private var isImporterPresented = false
    @State private var selectedProvider: AIProvider?
    @State private var projectId: String = ""
    @State private var showProxyRequiredAlert = false
    @State private var showIDEScanSheet = false
    @State private var customProviderSheetMode: CustomProviderSheetMode?
    @State private var showWarpConnectionSheet = false
    @State private var editingWarpToken: WarpService.WarpToken?
    @State private var showAddProviderPopover = false
    @State private var switchingAccount: AccountRowData?
    @State private var modeManager = OperatingModeManager.shared
    @State private var uiExperience = UIExperienceSettingsManager.shared
    @State private var featureFlags = FeatureFlagManager.shared
    @State var uiMetrics = UIBaselineMetricsTracker.shared
    @State var egressMapping: EgressMappingResponse?
    @State var egressMappingError: String?
    @State var isRefreshingEgressMapping = false
    @State var showOnlyEgressIssues = false
    @State var selectedEgressProviderFilter = "__all__"
    @State var egressSortMode: EgressSortMode = .issuesFirst
    @State private var prioritizeAnomalies = true
    @State private var compactAccountsView = false
    @State private var feedbackMessage: String?
    @State private var feedbackIsError = false
    @State private var feedbackDismissTask: Task<Void, Never>?
    let customProviderService = CustomProviderService.shared
    let warpService = WarpService.shared
    let egressAllProviderFilter = "__all__"
    let egressUnknownProviderFilter = "__unknown__"
    enum EgressSortMode: String, CaseIterable, Identifiable {
        case issuesFirst
        case driftHighToLow
        case account
        var id: String { rawValue }
        var localizedTitle: String {
            switch self {
            case .issuesFirst:
                return "providers.egress.alerted".localized()
            case .driftHighToLow:
                return "providers.egress.chip.drifted".localized()
            case .account:
                return "providers.egress.chip.accounts".localized()
            }
        }
        var systemImage: String {
            switch self {
            case .issuesFirst:
                return "exclamationmark.triangle.fill"
            case .driftHighToLow:
                return "arrow.up.arrow.down"
            case .account:
                return "person.text.rectangle"
            }
        }
    }
    // MARK: - Computed Properties
    /// Providers that can be added manually
    private var addableProviders: [AIProvider] {
        if modeManager.isLocalProxyMode {
            return AIProvider.allCases.filter { $0.supportsManualAuth }
        } else {
            return AIProvider.allCases.filter { $0.supportsQuotaOnlyMode && $0.supportsManualAuth }
        }
    }
    /// All accounts grouped by provider
    private var groupedAccounts: [AIProvider: [AccountRowData]] {
        var groups: [AIProvider: [AccountRowData]] = [:]
        if modeManager.isLocalProxyMode && viewModel.proxyManager.proxyStatus.running {
            // From proxy auth files (proxy running)
            for file in viewModel.authFiles {
                guard let provider = file.providerType else { continue }
                let data = AccountRowData.from(authFile: file)
                groups[provider, default: []].append(data)
            }
        } else {
            // From direct auth files (proxy not running or quota-only mode)
            for file in viewModel.directAuthFiles {
                let data = AccountRowData.from(directAuthFile: file)
                groups[file.provider, default: []].append(data)
            }
        }
        // Add auto-detected accounts (Cursor, Trae)
        // Note: GLM uses API key auth via CustomProviderService, so skip it here
        for (provider, quotas) in viewModel.providerQuotas {
            if !provider.supportsManualAuth && provider != .glm {
                for (accountKey, _) in quotas {
                    let data = AccountRowData.from(provider: provider, accountKey: accountKey)
                    groups[provider, default: []].append(data)
                }
            }
        }
        // Add GLM providers from CustomProviderService
        for glmProvider in customProviderService.providers.filter({ $0.type == .glmCompatibility && $0.isEnabled }) {
            // Use provider name as display name (store provider ID for editing)
            let data = AccountRowData(
                id: glmProvider.id.uuidString,
                provider: .glm,
                displayName: glmProvider.name.isEmpty ? "GLM" : glmProvider.name,
                menuBarAccountKey: glmProvider.name,
                source: .direct,
                status: "ready",
                statusMessage: nil,
                isDisabled: false,
                canDelete: true,
                canEdit: true
            )
            groups[.glm, default: []].append(data)
        }
        // Add Warp providers from WarpService
        for warpToken in warpService.tokens.filter({ $0.isEnabled }) {
            let data = AccountRowData(
                id: warpToken.id.uuidString,
                provider: .warp,
                displayName: warpToken.name.isEmpty ? "Warp" : warpToken.name,
                menuBarAccountKey: warpToken.name,
                source: .direct,
                status: "ready",
                statusMessage: nil,
                isDisabled: false,
                canDelete: true,
                canEdit: true
            )
            groups[.warp, default: []].append(data)
        }
        return groups
    }
    /// Sorted providers for consistent display order
    private var sortedProviders: [AIProvider] {
        let sorted = groupedAccounts.keys.sorted { $0.displayName < $1.displayName }
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
    /// Total account count across all providers
    private var totalAccountCount: Int {
        groupedAccounts.values.reduce(0) { $0 + $1.count }
    }
    private var accountHealthCounts: (error: Int, cooling: Int, disabled: Int, fatalDisabled: Int, networkError: Int) {
        let all = groupedAccounts.values.flatMap { $0 }
        let error = all.filter { ($0.status ?? "").lowercased() == "error" }.count
        let cooling = all.filter { ($0.status ?? "").lowercased() == "cooling" }.count
        let disabled = all.filter(\.isDisabled).count
        let fatalDisabled = all.filter { $0.disabledByPolicy || ($0.errorKind == "account_deactivated") || ($0.errorKind == "workspace_deactivated") }.count
        let networkError = all.filter { $0.errorKind == "network_error" }.count
        return (error, cooling, disabled, fatalDisabled, networkError)
    }
    private func providerSeverity(_ provider: AIProvider) -> Int {
        let accounts = groupedAccounts[provider] ?? []
        let errorCount = accounts.filter { ($0.status ?? "").lowercased() == "error" }.count
        let coolingCount = accounts.filter { ($0.status ?? "").lowercased() == "cooling" }.count
        let disabledCount = accounts.filter { $0.isDisabled }.count
        let fatalDisabledCount = accounts.filter { $0.disabledByPolicy || ($0.errorKind == "account_deactivated") || ($0.errorKind == "workspace_deactivated") }.count
        return errorCount * 5 + coolingCount * 2 + disabledCount + fatalDisabledCount * 8
    }
    /// Account count per provider (for AddProviderPopover badge display)
    private var providerAccountCounts: [AIProvider: Int] {
        groupedAccounts.mapValues { $0.count }
    }
    // MARK: - Body
    var body: some View {
        List {
            // Section 1: Your Accounts (grouped by provider)
            accountsSection
            // Section 2: Egress Mapping (read-only observability)
            egressMappingSection
            // Section 3: Custom Providers (Local Proxy Mode only)
            if modeManager.isLocalProxyMode {
                customProvidersSection
            }
        }
        .environment(\.defaultMinListRowHeight, uiExperience.recommendedMinimumRowHeight)
        .navigationTitle(modeManager.isMonitorMode ? "nav.accounts".localized() : "nav.providers".localized())
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
        .sheet(item: $selectedProvider) { provider in
            OAuthSheet(provider: provider, projectId: $projectId) {
                selectedProvider = nil
                projectId = ""
                viewModel.oauthState = nil
            }
            .environment(viewModel)
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
                    await MainActor.run {
                        if let actionError = latestActionError(previousError: previousError) {
                            showFeedback(
                                "providers.feedback.importFailed".localized(fallback: "账号导入失败") + ": " + actionError,
                                isError: true
                            )
                        } else {
                            showFeedback("providers.feedback.imported".localized(fallback: "账号导入已完成"))
                        }
                    }
                }
            } else if case .failure(let error) = result {
                showFeedback(
                    "providers.feedback.importFailed".localized(fallback: "账号导入失败") + ": " + error.localizedDescription,
                    isError: true
                )
            }
        }
        .task {
            uiMetrics.begin("providers.screen.initial_load")
            await viewModel.loadDirectAuthFiles()
            await refreshEgressMapping()
            uiMetrics.end(
                "providers.screen.initial_load",
                metadata: "providers=\(groupedAccounts.count),accounts=\(totalAccountCount)"
            )
        }
        .alert("providers.proxyRequired.title".localized(), isPresented: $showProxyRequiredAlert) {
            Button("action.startProxy".localized()) {
                Task { await viewModel.startProxy() }
            }
            Button("action.cancel".localized(), role: .cancel) {}
        } message: {
            Text("providers.proxyRequired.message".localized())
        }
        .sheet(isPresented: $showIDEScanSheet) {
            IDEScanSheet {}
            .environment(viewModel)
        }
        .sheet(item: $customProviderSheetMode) { mode in
            CustomProviderSheet(provider: mode.provider) { provider in
                // Check if provider already exists by ID to determine if we're updating or adding
                if customProviderService.providers.contains(where: { $0.id == provider.id }) {
                    customProviderService.updateProvider(provider)
                } else {
                    customProviderService.addProvider(provider)
                }
                syncCustomProvidersToConfig()
            }
        }
        .sheet(isPresented: $showWarpConnectionSheet) {
            WarpConnectionSheet(token: editingWarpToken) { name, token in
                if let existing = editingWarpToken {
                    var updated = existing
                    updated.name = name
                    updated.token = token
                    warpService.updateToken(updated)
                } else {
                    warpService.addToken(name: name, token: token)
                }
                editingWarpToken = nil
                Task { await viewModel.refreshAutoDetectedProviders() }
            }
        }
        .sheet(isPresented: $showAddProviderPopover) {
            AddProviderPopover(
                providers: addableProviders,
                existingCounts: providerAccountCounts,
                onSelectProvider: { provider in
                    handleAddProvider(provider)
                },
                onScanIDEs: {
                    showIDEScanSheet = true
                },
                onAddCustomProvider: {
                    customProviderSheetMode = .add
                },
                onDismiss: {
                    showAddProviderPopover = false
                }
            )
        }
        .sheet(item: $switchingAccount) { account in
            SwitchAccountSheet(
                accountEmail: account.displayName,
                onDismiss: {
                    switchingAccount = nil
                }
            )
            .environment(viewModel)
        }
        .onDisappear {
            feedbackDismissTask?.cancel()
        }
    }
    // MARK: - Toolbar
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                showAddProviderPopover = true
            } label: {
                Image(systemName: "plus")
            }
            .help("providers.addAccount".localized())
            .accessibilityLabel("providers.addAccount".localized())
        }
        ToolbarItem(placement: .automatic) {
            Picker("providers.viewMode".localized(fallback: "视图模式"), selection: $compactAccountsView) {
                Text("providers.viewMode.card".localized(fallback: "卡片")).tag(false)
                Text("providers.viewMode.compact".localized(fallback: "紧凑")).tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 120)
            .help("providers.viewDensity.help".localized(fallback: "切换账号展示密度"))
        }
        ToolbarItem(placement: .automatic) {
            Button {
                Task {
                    let previousError = normalizedErrorMessage(viewModel.errorMessage)
                    if modeManager.isLocalProxyMode && viewModel.proxyManager.proxyStatus.running {
                        await viewModel.refreshData()
                    } else {
                        await viewModel.loadDirectAuthFiles()
                    }
                    await viewModel.refreshAutoDetectedProviders()
                    await refreshEgressMapping()
                    await MainActor.run {
                        if let actionError = latestActionError(previousError: previousError) {
                            showFeedback(
                                "providers.feedback.refreshFailed".localized(fallback: "刷新失败") + ": " + actionError,
                                isError: true
                            )
                        } else {
                            showFeedback("providers.feedback.refreshed".localized(fallback: "账号列表已刷新"))
                        }
                    }
                }
            } label: {
                if viewModel.isLoadingQuotas {
                    SmallProgressView()
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .disabled(viewModel.isLoadingQuotas)
            .help("action.refresh".localized())
            .accessibilityLabel("action.refresh".localized())
        }
    }
    // MARK: - Accounts Section
    @ViewBuilder
    private var accountsSection: some View {
        Section {
            if featureFlags.enhancedUILayout && !groupedAccounts.isEmpty {
                Toggle("providers.prioritizeAnomalies".localized(fallback: "异常优先"), isOn: $prioritizeAnomalies)
                    .toggleStyle(.switch)
                    .font(.caption)
                Picker("providers.viewMode".localized(fallback: "视图模式"), selection: $compactAccountsView) {
                    Text("providers.viewMode.card".localized(fallback: "卡片")).tag(false)
                    Text("providers.viewMode.compact".localized(fallback: "紧凑")).tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
                .controlSize(.small)
                HStack(spacing: 8) {
                    providerIssueChip(title: "quota.health.error".localized(fallback: "错误"), value: accountHealthCounts.error, color: Color.semanticDanger)
                    providerIssueChip(title: "quota.health.cooling".localized(fallback: "冷却中"), value: accountHealthCounts.cooling, color: Color.semanticWarning)
                    providerIssueChip(title: "quota.status.disabled".localized(fallback: "禁用"), value: accountHealthCounts.disabled, color: .secondary)
                    providerIssueChip(title: "quota.status.fatalDisabled".localized(fallback: "致命禁用"), value: accountHealthCounts.fatalDisabled, color: Color.semanticDanger)
                    providerIssueChip(title: "quota.status.networkError".localized(fallback: "网络抖动"), value: accountHealthCounts.networkError, color: Color.semanticInfo)
                }
            }
            if groupedAccounts.isEmpty {
                // Empty state
                AccountsEmptyState(
                    onScanIDEs: {
                        showIDEScanSheet = true
                    },
                    onAddProvider: {
                        showAddProviderPopover = true
                    }
                )
            } else {
                // Grouped accounts by provider
                ForEach(Array(sortedProviders.enumerated()), id: \.element) { index, provider in
                    VStack(spacing: 0) {
                        ProviderDisclosureGroup(
                            provider: provider,
                            accounts: groupedAccounts[provider] ?? [],
                            onDeleteAccount: { account in
                                Task { await deleteAccount(account) }
                            },
                            onEditAccount: { account in
                                if provider == .glm {
                                    handleEditGlmAccount(account)
                                } else if provider == .warp {
                                    handleEditWarpAccount(account)
                                }
                            },
                            onSwitchAccount: provider == .antigravity ? { account in
                                switchingAccount = account
                            } : nil,
                            onToggleDisabled: { account in
                                Task { await toggleAccountDisabled(account) }
                            },
                            isAccountActive: provider == .antigravity ? { account in
                                viewModel.isAntigravityAccountActive(email: account.displayName)
                            } : nil,
                            compactMode: compactAccountsView
                        )
                        if index < sortedProviders.count - 1 {
                            Divider()
                                .padding(.leading, 32)
                        }
                    }
                    .listRowSeparator(.hidden)
                }
            }
        } header: {
            HStack {
                Label("providers.yourAccounts".localized(), systemImage: "person.2.badge.key")
                if totalAccountCount > 0 {
                    Spacer()
                    Text("\(totalAccountCount)")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.2))
                        .clipShape(Capsule())
                }
            }
        } footer: {
            if !groupedAccounts.isEmpty {
                MenuBarHintView()
            }
        }
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

    private func providerIssueChip(title: String, value: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title)
            Text("\(value)")
                .fontWeight(.semibold)
        }
        .font(.caption2)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.12))
        .foregroundStyle(value > 0 ? color : .secondary)
        .clipShape(Capsule())
    }
    // MARK: - Custom Providers Section
    @ViewBuilder
    private var customProvidersSection: some View {
        // Filter out GLM providers (they're shown in Your Accounts section)
        let nonGlmProviders = customProviderService.providers.filter { $0.type != .glmCompatibility }
        Section {
            // List existing custom providers
            ForEach(nonGlmProviders) { provider in
                CustomProviderRow(
                    provider: provider,
                    onEdit: {
                        customProviderSheetMode = .edit(provider)
                    },
                    onDelete: {
                        customProviderService.deleteProvider(id: provider.id)
                        if syncCustomProvidersToConfig() {
                            showFeedback("providers.feedback.deleted".localized(fallback: "自定义 Provider 已删除"))
                        }
                    },
                    onToggle: {
                        customProviderService.toggleProvider(id: provider.id)
                        if syncCustomProvidersToConfig() {
                            showFeedback("providers.feedback.updated".localized(fallback: "自定义 Provider 已更新"))
                        }
                    }
                )
            }
        } header: {
            HStack {
                Label("customProviders.title".localized(), systemImage: "puzzlepiece.extension.fill")
                if !nonGlmProviders.isEmpty {
                    Spacer()
                    Text("\(nonGlmProviders.count)")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.2))
                        .clipShape(Capsule())
                }
            }
        } footer: {
            Text("customProviders.footer".localized())
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
    private func handleAddProvider(_ provider: AIProvider) {
        // In Local Proxy Mode, require proxy to be running for OAuth
        if modeManager.isLocalProxyMode && !viewModel.proxyManager.proxyStatus.running {
            showProxyRequiredAlert = true
            return
        }
        if provider == .vertex {
            isImporterPresented = true
        } else if provider == .warp {
            editingWarpToken = nil
            showWarpConnectionSheet = true
        } else {
            viewModel.oauthState = nil
            selectedProvider = provider
        }
    }
    private func deleteAccount(_ account: AccountRowData) async {
        // Only proxy accounts can be deleted via API
        guard account.canDelete else { return }
        // Handle GLM accounts (stored in CustomProviderService)
        if account.provider == .glm {
            // GLM accounts are stored as custom providers
            // Find the GLM provider by ID and delete it
            if let glmProvider = customProviderService.providers.first(where: { $0.id.uuidString == account.id }) {
                customProviderService.deleteProvider(id: glmProvider.id)
                if syncCustomProvidersToConfig() {
                    showFeedback("providers.feedback.deleted".localized(fallback: "账号已删除"))
                }
            }
            return
        }
        // Handle Warp accounts (stored in WarpService)
        if account.provider == .warp {
            if let uuid = UUID(uuidString: account.id) {
                warpService.deleteToken(id: uuid)
                await viewModel.refreshQuotaForProvider(.warp)
                await MainActor.run {
                    showFeedback("providers.feedback.deleted".localized(fallback: "账号已删除"))
                }
            }
            return
        }
        // Find the original AuthFile to delete
        if let authFile = viewModel.authFiles.first(where: { $0.id == account.id }) {
            await viewModel.deleteAuthFile(authFile)
            await MainActor.run {
                showFeedback("providers.feedback.deleted".localized(fallback: "账号已删除"))
            }
        }
    }
    private func toggleAccountDisabled(_ account: AccountRowData) async {
        // Only proxy accounts can be disabled via API
        guard account.source == .proxy else { return }
        // Find the original AuthFile to toggle
        if let authFile = viewModel.authFiles.first(where: { $0.id == account.id }) {
            await viewModel.toggleAuthFileDisabled(authFile)
            await MainActor.run {
                showFeedback("providers.feedback.stateChanged".localized(fallback: "账号状态已更新"))
            }
        }
    }
    private func handleEditGlmAccount(_ account: AccountRowData) {
        // Find the GLM provider by ID and open edit sheet using CustomProviderSheet
        if let glmProvider = customProviderService.providers.first(where: { $0.id.uuidString == account.id }) {
            customProviderSheetMode = .edit(glmProvider)
        }
    }
    private func handleEditWarpAccount(_ account: AccountRowData) {
        // Find the Warp token by ID and open edit sheet
        if let token = warpService.tokens.first(where: { $0.id.uuidString == account.id }) {
            editingWarpToken = token
            showWarpConnectionSheet = true
        }
    }
    @discardableResult
    private func syncCustomProvidersToConfig() -> Bool {
        do {
            try customProviderService.syncToConfigFile(configPath: viewModel.proxyManager.configPath)
            return true
        } catch {
            showFeedback(
                "providers.feedback.syncFailed".localized(fallback: "配置同步失败") + ": " + error.localizedDescription,
                isError: true
            )
            return false
        }
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
