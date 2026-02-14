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
    @Environment(QuotaViewModel.self) private var viewModel
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
    @State private var egressMapping: EgressMappingResponse?
    @State private var egressMappingError: String?
    @State private var isRefreshingEgressMapping = false
    @State private var showOnlyEgressIssues = false
    @State private var selectedEgressProviderFilter = "__all__"
    @State private var egressSortMode: EgressSortMode = .issuesFirst

    private let customProviderService = CustomProviderService.shared
    private let warpService = WarpService.shared
    private let egressAllProviderFilter = "__all__"
    private let egressUnknownProviderFilter = "__unknown__"

    private enum EgressSortMode: String, CaseIterable, Identifiable {
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
        groupedAccounts.keys.sorted { $0.displayName < $1.displayName }
    }
    
    /// Total account count across all providers
    private var totalAccountCount: Int {
        groupedAccounts.values.reduce(0) { $0 + $1.count }
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
        .navigationTitle(modeManager.isMonitorMode ? "nav.accounts".localized() : "nav.providers".localized())
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
                Task { await viewModel.importVertexServiceAccount(url: url) }
            }
            // Failure case is silently ignored - user can retry via UI
        }
        .task {
            await viewModel.loadDirectAuthFiles()
            await refreshEgressMapping()
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
        }
        
        ToolbarItem(placement: .automatic) {
            Button {
                Task {
                    if modeManager.isLocalProxyMode && viewModel.proxyManager.proxyStatus.running {
                        await viewModel.refreshData()
                    } else {
                        await viewModel.loadDirectAuthFiles()
                    }
                    await viewModel.refreshAutoDetectedProviders()
                    await refreshEgressMapping()
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
        }
    }

    // MARK: - Egress Mapping Section

    @ViewBuilder
    private var egressMappingSection: some View {
        Section {
            if let message = egressMappingError, !message.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("status.error".localized(), systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("action.retry".localized()) {
                        Task { await refreshEgressMapping() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            if let snapshot = egressMapping {
                let visibleAccounts = filteredEgressAccounts(snapshot)
                egressMappingSummaryView(snapshot, visibleCount: visibleAccounts.count)

                if isRefreshingEgressMapping {
                    HStack(spacing: 8) {
                        SmallProgressView()
                        Text("providers.egress.loading".localized())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !snapshot.accounts.isEmpty {
                    egressControlsView(snapshot: snapshot, visibleCount: visibleAccounts.count)
                }

                if visibleAccounts.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(
                            showOnlyEgressIssues
                                ? "providers.egress.onlyIssuesEmpty".localized()
                                : "providers.egress.empty".localized(),
                            systemImage: "line.3.horizontal.decrease.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        if hasActiveEgressFilter(snapshot) {
                            Button("logs.all".localized()) {
                                showOnlyEgressIssues = false
                                selectedEgressProviderFilter = egressAllProviderFilter
                            }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                        }
                    }
                } else {
                    ForEach(Array(visibleAccounts.enumerated()), id: \.offset) { index, account in
                        egressMappingAccountRow(account, index: index)
                    }
                }
            } else if isRefreshingEgressMapping {
                VStack(alignment: .leading, spacing: 8) {
                    Label("providers.egress.loading".localized(), systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SmallProgressView()
                }
            } else if viewModel.apiClient == nil {
                VStack(alignment: .leading, spacing: 8) {
                    Label("providers.egress.unavailable".localized(), systemImage: "wifi.slash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("action.refresh".localized()) {
                        Task { await refreshEgressMapping() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isRefreshingEgressMapping)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Label("providers.egress.notLoaded".localized(), systemImage: "tray")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("action.refresh".localized()) {
                        Task { await refreshEgressMapping() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isRefreshingEgressMapping)
                }
            }
        } header: {
            HStack {
                Label("providers.egress.title".localized(), systemImage: "network")
                Spacer()
                Button {
                    Task { await refreshEgressMapping() }
                } label: {
                    if isRefreshingEgressMapping {
                        SmallProgressView()
                    } else {
                        Label("action.refresh".localized(), systemImage: "arrow.clockwise")
                            .labelStyle(.iconOnly)
                    }
                }
                .buttonStyle(.borderless)
                .disabled(isRefreshingEgressMapping)
                .help("providers.egress.refresh".localized())
            }
        } footer: {
            Text("providers.egress.footer".localized())
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
    
    // MARK: - Accounts Section
    
    @ViewBuilder
    private var accountsSection: some View {
        Section {
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
                ForEach(sortedProviders, id: \.self) { provider in
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
                        } : nil
                    )
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
                        .padding(.vertical, 2)
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
                        syncCustomProvidersToConfig()
                    },
                    onToggle: {
                        customProviderService.toggleProvider(id: provider.id)
                        syncCustomProvidersToConfig()
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
                        .padding(.vertical, 2)
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
    
    // MARK: - Helper Functions

    @ViewBuilder
    private func egressMappingSummaryView(_ snapshot: EgressMappingResponse, visibleCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Label(
                    snapshot.enabled == true
                        ? "providers.egress.status.enabled".localized()
                        : "providers.egress.status.disabled".localized(),
                    systemImage: snapshot.enabled == true ? "checkmark.circle.fill" : "xmark.circle"
                )
                .font(.caption)
                .foregroundStyle(snapshot.enabled == true ? .green : .secondary)

                if let redaction = snapshot.sensitiveRedaction, !redaction.isEmpty {
                    Text(String(format: "providers.egress.redaction".localized(), redaction))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                if let generatedAt = formattedEgressTimestamp(snapshot.generatedAtUTC), !generatedAt.isEmpty {
                    Text("dashboard.updated".localized() + " " + generatedAt)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            HStack(spacing: 10) {
                egressSummaryChip(title: "providers.egress.chip.accounts".localized(), value: snapshot.totalAccounts)
                egressSummaryChip(title: "providers.egress.chip.drifted".localized(), value: snapshot.driftedAccounts)
                egressSummaryChip(title: "providers.egress.chip.alerted".localized(), value: snapshot.alertedAccounts)
                egressSummaryChip(title: "providers.egress.chip.inconsistent".localized(), value: snapshot.inconsistentAccounts)
                egressSummaryChip(title: "logs.all".localized(), value: visibleCount)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func egressControlsView(snapshot: EgressMappingResponse, visibleCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Toggle("providers.egress.onlyIssues".localized(), isOn: $showOnlyEgressIssues)
                    .toggleStyle(.switch)
                Spacer()
                egressSummaryChip(title: "providers.egress.chip.accounts".localized(), value: visibleCount)
            }

            HStack(spacing: 8) {
                Picker("providers.egress.chip.accounts".localized(), selection: $selectedEgressProviderFilter) {
                    Text("logs.all".localized()).tag(egressAllProviderFilter)
                    ForEach(egressProviderOptions(snapshot), id: \.self) { provider in
                        Text(egressProviderDisplayName(provider)).tag(provider)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .help("providers.egress.chip.accounts".localized())

                Picker("providers.egress.chip.drifted".localized(), selection: $egressSortMode) {
                    ForEach(EgressSortMode.allCases) { mode in
                        Label(mode.localizedTitle, systemImage: mode.systemImage).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .help("providers.egress.chip.drifted".localized())
            }
        }
    }

    private func egressSummaryChip(title: String, value: Int?) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value.map(String.init) ?? "—")
                .font(.caption2.bold())
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.secondary.opacity(0.12))
        .clipShape(Capsule())
    }

    @ViewBuilder
    private func egressMappingAccountRow(_ account: EgressMappingAccount, index: Int) -> some View {
        let hasIssues = isEgressIssue(account)

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                let fallbackID = String(format: "providers.egress.account.fallback".localized(), index + 1)
                Text(account.authID ?? account.authIndex ?? fallbackID)
                    .font(.subheadline.weight(.medium))
                if let provider = account.provider, !provider.isEmpty {
                    Text(provider.uppercased())
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }
                Spacer()
                if let driftCount = account.driftCount {
                    Text(String(format: "providers.egress.drift".localized(), driftCount))
                        .font(.caption)
                        .foregroundStyle(driftCount > 0 ? .orange : .secondary)
                } else {
                    Text("providers.egress.driftUnknown".localized())
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Text(account.proxyIdentity ?? "providers.egress.proxyUnknown".localized())
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 8) {
                Label(
                    hasIssues ? "status.error".localized() : "status.connected".localized(),
                    systemImage: hasIssues ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                )
                .font(.caption2)
                .foregroundStyle(hasIssues ? .orange : .green)

                if account.driftAlerted == true {
                    Label("providers.egress.alerted".localized(), systemImage: "bell.badge.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }

                if let status = account.consistencyStatus, !status.isEmpty {
                    Text(String(format: "providers.egress.status".localized(), localizedConsistencyStatus(status)))
                        .font(.caption2)
                        .foregroundStyle(status.lowercased() == "ok" ? Color.secondary : Color.orange)
                }
            }

            if !account.consistencyIssues.isEmpty {
                Text(account.consistencyIssues.joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    private func filteredEgressAccounts(_ snapshot: EgressMappingResponse) -> [EgressMappingAccount] {
        var accounts = snapshot.accounts
        let hasMatchingProvider = snapshot.accounts.contains {
            normalizedEgressProvider($0.provider) == selectedEgressProviderFilter
        }

        if selectedEgressProviderFilter != egressAllProviderFilter && hasMatchingProvider {
            accounts = accounts.filter { normalizedEgressProvider($0.provider) == selectedEgressProviderFilter }
        }

        if showOnlyEgressIssues {
            accounts = accounts.filter(isEgressIssue)
        }

        return accounts.sorted(by: compareEgressAccounts)
    }

    private func refreshEgressMapping() async {
        guard let client = viewModel.apiClient else {
            egressMapping = nil
            egressMappingError = nil
            return
        }

        isRefreshingEgressMapping = true
        defer { isRefreshingEgressMapping = false }
        let previousSnapshot = egressMapping
        egressMappingError = nil

        do {
            let snapshot = try await client.fetchEgressMapping()
            egressMapping = snapshot
            egressMappingError = nil
        } catch APIError.httpError(404) {
            egressMapping = previousSnapshot
            egressMappingError = "providers.egress.unavailable".localized()
        } catch {
            egressMapping = previousSnapshot
            egressMappingError = error.localizedDescription
        }
    }

    private func hasActiveEgressFilter(_ snapshot: EgressMappingResponse) -> Bool {
        let hasProviderFilter =
            selectedEgressProviderFilter != egressAllProviderFilter &&
            snapshot.accounts.contains { normalizedEgressProvider($0.provider) == selectedEgressProviderFilter }
        return showOnlyEgressIssues || hasProviderFilter
    }

    private func egressProviderOptions(_ snapshot: EgressMappingResponse) -> [String] {
        let providers = Set(snapshot.accounts.map { normalizedEgressProvider($0.provider) })
        return providers.sorted()
    }

    private func egressProviderDisplayName(_ provider: String) -> String {
        if provider == egressUnknownProviderFilter {
            return "providers.egress.proxyUnknown".localized()
        }
        return provider.uppercased()
    }

    private func normalizedEgressProvider(_ provider: String?) -> String {
        guard let provider, !provider.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return egressUnknownProviderFilter
        }
        return provider.lowercased()
    }

    private func isEgressIssue(_ account: EgressMappingAccount) -> Bool {
        account.driftAlerted == true || !(account.consistencyIssues.isEmpty) || (account.driftCount ?? 0) > 0
    }

    private func compareEgressAccounts(_ left: EgressMappingAccount, _ right: EgressMappingAccount) -> Bool {
        switch egressSortMode {
        case .issuesFirst:
            let leftSeverity = egressIssueSeverity(left)
            let rightSeverity = egressIssueSeverity(right)
            if leftSeverity != rightSeverity {
                return leftSeverity > rightSeverity
            }

            let leftDrift = left.driftCount ?? 0
            let rightDrift = right.driftCount ?? 0
            if leftDrift != rightDrift {
                return leftDrift > rightDrift
            }
        case .driftHighToLow:
            let leftDrift = left.driftCount ?? 0
            let rightDrift = right.driftCount ?? 0
            if leftDrift != rightDrift {
                return leftDrift > rightDrift
            }
        case .account:
            break
        }

        let leftProvider = normalizedEgressProvider(left.provider)
        let rightProvider = normalizedEgressProvider(right.provider)
        if leftProvider != rightProvider {
            return leftProvider < rightProvider
        }

        return egressAccountSortLabel(left).localizedCaseInsensitiveCompare(egressAccountSortLabel(right)) == .orderedAscending
    }

    private func egressIssueSeverity(_ account: EgressMappingAccount) -> Int {
        var severity = 0
        if account.driftAlerted == true {
            severity += 3
        }
        if !account.consistencyIssues.isEmpty {
            severity += 2
        }
        if let status = account.consistencyStatus, !status.isEmpty, status.lowercased() != "ok" {
            severity += 1
        }
        severity += min(account.driftCount ?? 0, 99)
        return severity
    }

    private func egressAccountSortLabel(_ account: EgressMappingAccount) -> String {
        account.authID ?? account.authIndex ?? account.proxyIdentity ?? ""
    }

    private func localizedConsistencyStatus(_ status: String) -> String {
        switch status.lowercased() {
        case "ok":
            return "status.connected".localized()
        case "error", "warn", "warning", "inconsistent":
            return "status.error".localized()
        default:
            return status
        }
    }

    private func formattedEgressTimestamp(_ timestamp: String?) -> String? {
        guard let timestamp, !timestamp.isEmpty else {
            return nil
        }

        let formatterWithFractional = ISO8601DateFormatter()
        formatterWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let formatterStandard = ISO8601DateFormatter()
        formatterStandard.formatOptions = [.withInternetDateTime]

        guard
            let date = formatterWithFractional.date(from: timestamp) ?? formatterStandard.date(from: timestamp)
        else {
            return timestamp
        }

        return date.formatted(date: .omitted, time: .shortened)
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
                syncCustomProvidersToConfig()
            }
            return
        }
        
        // Handle Warp accounts (stored in WarpService)
        if account.provider == .warp {
            if let uuid = UUID(uuidString: account.id) {
                warpService.deleteToken(id: uuid)
                await viewModel.refreshQuotaForProvider(.warp)
            }
            return
        }

        // Find the original AuthFile to delete
        if let authFile = viewModel.authFiles.first(where: { $0.id == account.id }) {
            await viewModel.deleteAuthFile(authFile)
        }
    }

    private func toggleAccountDisabled(_ account: AccountRowData) async {
        // Only proxy accounts can be disabled via API
        guard account.source == .proxy else { return }

        // Find the original AuthFile to toggle
        if let authFile = viewModel.authFiles.first(where: { $0.id == account.id }) {
            await viewModel.toggleAuthFileDisabled(authFile)
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

    private func syncCustomProvidersToConfig() {
        // Silent failure - custom provider sync is non-critical
        // Config will be synced on next proxy start
        try? customProviderService.syncToConfigFile(configPath: viewModel.proxyManager.configPath)
    }
}

// MARK: - Custom Provider Row

struct CustomProviderRow: View {
    let provider: CustomProvider
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onToggle: () -> Void
    
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Provider type icon
            ZStack {
                Circle()
                    .fill(provider.type.color.opacity(0.1))
                    .frame(width: 32, height: 32)
                
                Image(provider.type.providerIconName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)
            }
            
            // Provider info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(provider.name)
                        .fontWeight(.medium)
                    
                    if !provider.isEnabled {
                        Text("customProviders.disabled".localized())
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.2))
                            .foregroundStyle(.secondary)
                            .clipShape(Capsule())
                    }
                }
                
                HStack(spacing: 6) {
                    Text(provider.type.localizedDisplayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    
                    let keyCount = provider.apiKeys.count
                    Text("\(keyCount) \(keyCount == 1 ? "customProviders.key".localized() : "customProviders.keys".localized())")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            
            Spacer()
            
            // Toggle button
            Button {
                onToggle()
            } label: {
                Image(systemName: provider.isEnabled ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(provider.isEnabled ? .green : .secondary)
            }
            .buttonStyle(.subtle)
            .help(provider.isEnabled ? "customProviders.disable".localized() : "customProviders.enable".localized())
        }
        .contextMenu {
            Button {
                onEdit()
            } label: {
                Label("action.edit".localized(), systemImage: "pencil")
            }
            
            Button {
                onToggle()
            } label: {
                Label(provider.isEnabled ? "customProviders.disable".localized() : "customProviders.enable".localized(), systemImage: provider.isEnabled ? "xmark.circle" : "checkmark.circle")
            }
            
            Divider()
            
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("action.delete".localized(), systemImage: "trash")
            }
        }
        .confirmationDialog("customProviders.deleteConfirm".localized(), isPresented: $showDeleteConfirmation) {
            Button("action.delete".localized(), role: .destructive) {
                onDelete()
            }
            Button("action.cancel".localized(), role: .cancel) {}
        } message: {
            Text("customProviders.deleteMessage".localized())
        }
    }
}

// MARK: - Menu Bar Badge Component

struct MenuBarBadge: View {
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.blue.opacity(0.1) : Color.clear)
                    .frame(width: 28, height: 28)

                Image(systemName: isSelected ? "chart.bar.fill" : "chart.bar")
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? .blue : .secondary)
            }
        }
        .buttonStyle(.plain)
        .nativeTooltip(isSelected ? "menubar.hideFromMenuBar".localized() : "menubar.showOnMenuBar".localized())
    }
}

// MARK: - Native Tooltip Support

private class TooltipWindow: NSWindow {
    static let shared = TooltipWindow()

    private let label: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .labelColor
        label.backgroundColor = .clear
        label.isBezeled = false
        label.isEditable = false
        return label
    }()

    private init() {
        super.init(
            contentRect: .zero,
            styleMask: .borderless,
            backing: .buffered,
            defer: true
        )
        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .floating
        self.ignoresMouseEvents = true

        let visualEffect = NSVisualEffectView()
        visualEffect.material = .toolTip
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 4

        label.translatesAutoresizingMaskIntoConstraints = false
        visualEffect.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: visualEffect.topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor, constant: -4)
        ])

        self.contentView = visualEffect
    }

    func show(text: String, near view: NSView) {
        label.stringValue = text
        label.sizeToFit()

        let labelSize = label.fittingSize
        let windowSize = NSSize(width: labelSize.width + 16, height: labelSize.height + 8)

        guard let screen = view.window?.screen ?? NSScreen.main else { return }
        let viewFrameInScreen = view.window?.convertToScreen(view.convert(view.bounds, to: nil)) ?? .zero
        var origin = NSPoint(
            x: viewFrameInScreen.midX - windowSize.width / 2,
            y: viewFrameInScreen.minY - windowSize.height - 4
        )

        // Keep tooltip on screen
        if origin.x < screen.visibleFrame.minX {
            origin.x = screen.visibleFrame.minX
        }
        if origin.x + windowSize.width > screen.visibleFrame.maxX {
            origin.x = screen.visibleFrame.maxX - windowSize.width
        }
        if origin.y < screen.visibleFrame.minY {
            origin.y = viewFrameInScreen.maxY + 4
        }

        setFrame(NSRect(origin: origin, size: windowSize), display: true)
        orderFront(nil)
    }

    func hide() {
        orderOut(nil)
    }
}

private class TooltipTrackingView: NSView {
    var text: String = ""

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        TooltipWindow.shared.show(text: text, near: self)
    }

    override func mouseExited(with event: NSEvent) {
        TooltipWindow.shared.hide()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
}

private struct NativeTooltipView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> TooltipTrackingView {
        let view = TooltipTrackingView()
        view.text = text
        return view
    }

    func updateNSView(_ nsView: TooltipTrackingView, context: Context) {
        nsView.text = text
    }
}

private extension View {
    func nativeTooltip(_ text: String) -> some View {
        self.overlay(NativeTooltipView(text: text))
    }
}

// MARK: - Menu Bar Hint View

struct MenuBarHintView: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "chart.bar.fill")
                .foregroundStyle(.blue)
                .font(.caption2)
            Text("menubar.hint".localized())
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - OAuth Sheet

struct OAuthSheet: View {
    @Environment(QuotaViewModel.self) private var viewModel
    let provider: AIProvider
    @Binding var projectId: String
    let onDismiss: () -> Void
    
    @State private var hasStartedAuth = false
    @State private var selectedKiroMethod: AuthCommand = .kiroImport
    
    private var isPolling: Bool {
        viewModel.oauthState?.status == .polling || viewModel.oauthState?.status == .waiting
    }
    
    private var isSuccess: Bool {
        viewModel.oauthState?.status == .success
    }
    
    private var isError: Bool {
        viewModel.oauthState?.status == .error
    }
    
    private var kiroAuthMethods: [AuthCommand] {
        [.kiroImport, .kiroGoogleLogin, .kiroAWSAuthCode, .kiroAWSLogin]
    }

    private var normalizedProjectId: String {
        projectId.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var geminiExistingEmailsForProject: [String] {
        guard provider == .gemini, !normalizedProjectId.isEmpty else { return [] }

        var matchedEmails = Set<String>()

        for file in viewModel.authFiles where file.providerType == .gemini {
            let parsed = Self.parseGeminiAuthIdentity(fileName: file.name, account: file.account)
            guard Self.isGeminiProjectPotentialMatch(existingProject: parsed?.projectId, targetProject: normalizedProjectId) else {
                continue
            }

            let candidate = file.email?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? parsed?.email?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? file.account?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? file.name
            if !candidate.isEmpty {
                matchedEmails.insert(candidate)
            }
        }

        for file in viewModel.directAuthFiles where file.provider == .gemini {
            let parsed = Self.parseGeminiAuthIdentity(fileName: file.filename, account: nil)
            guard Self.isGeminiProjectPotentialMatch(existingProject: parsed?.projectId, targetProject: normalizedProjectId) else {
                continue
            }

            let candidate = file.email?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? parsed?.email?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? file.filename
            if !candidate.isEmpty {
                matchedEmails.insert(candidate)
            }
        }

        return matchedEmails.sorted()
    }

    private var geminiOverwriteNotice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("providers.gemini.tip.identity".localized(), systemImage: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if !geminiExistingEmailsForProject.isEmpty {
                Text(
                    String(
                        format: "providers.gemini.tip.potentialDuplicate".localized(),
                        normalizedProjectId,
                        geminiExistingEmailsForProject.joined(separator: ", ")
                    )
                )
                    .font(.caption2)
                    .foregroundStyle(.orange)
                Text("providers.gemini.tip.keepBoth".localized())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.08))
        )
    }

    private static func parseGeminiAuthIdentity(fileName: String, account: String?) -> (email: String?, projectId: String?)? {
        let accountParsed = parseGeminiAccountField(account)
        let fileParsed = parseGeminiAuthFileName(fileName)

        let email = accountParsed?.email ?? fileParsed?.email
        let projectId = accountParsed?.projectId ?? fileParsed?.projectId

        if email == nil && projectId == nil {
            return nil
        }
        return (email: email, projectId: projectId)
    }

    private static func parseGeminiAccountField(_ account: String?) -> (email: String?, projectId: String?)? {
        guard let rawAccount = account?.trimmingCharacters(in: .whitespacesAndNewlines), !rawAccount.isEmpty else {
            return nil
        }

        if let openParen = rawAccount.lastIndex(of: "("),
           let closeParen = rawAccount.lastIndex(of: ")"),
           openParen < closeParen {
            let emailPart = String(rawAccount[..<openParen]).trimmingCharacters(in: .whitespacesAndNewlines)
            let projectPart = normalizeGeminiProjectIdentifier(
                String(rawAccount[rawAccount.index(after: openParen)..<closeParen])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            )
            if !emailPart.isEmpty || !projectPart.isEmpty {
                return (
                    email: emailPart.isEmpty ? nil : emailPart,
                    projectId: projectPart.isEmpty ? nil : projectPart
                )
            }
        }

        if rawAccount.contains("@") {
            return (email: rawAccount, projectId: nil)
        }

        return nil
    }

    private static func parseGeminiAuthFileName(_ fileName: String) -> (email: String?, projectId: String?)? {
        var normalized = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasSuffix(".json") {
            normalized = String(normalized.dropLast(".json".count))
        }

        if normalized.hasPrefix("gemini-cli-") {
            normalized = String(normalized.dropFirst("gemini-cli-".count))
        } else if normalized.hasPrefix("gemini-") {
            normalized = String(normalized.dropFirst("gemini-".count))
        } else {
            return nil
        }

        guard !normalized.isEmpty else { return nil }

        let emailProjectPattern = #"^(.+@[A-Za-z0-9.-]+\.[A-Za-z]{2,})(?:-(.+))?$"#
        if let regex = try? NSRegularExpression(pattern: emailProjectPattern) {
            let fullRange = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
            if let match = regex.firstMatch(in: normalized, options: [], range: fullRange) {
                let emailValue: String? = {
                    guard match.range(at: 1).location != NSNotFound,
                          let range = Range(match.range(at: 1), in: normalized) else {
                        return nil
                    }
                    return String(normalized[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                }()
                let projectValue: String? = {
                    guard match.range(at: 2).location != NSNotFound,
                          let range = Range(match.range(at: 2), in: normalized) else {
                        return nil
                    }
                    return normalizeGeminiProjectIdentifier(
                        String(normalized[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                }()
                return (
                    email: emailValue?.isEmpty == false ? emailValue : nil,
                    projectId: projectValue?.isEmpty == false ? projectValue : nil
                )
            }
        }

        guard let separator = normalized.lastIndex(of: "-") else {
            if normalized.contains("@") {
                return (email: normalized, projectId: nil)
            }
            return nil
        }

        let emailPart = String(normalized[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
        let projectPart = normalizeGeminiProjectIdentifier(
            String(normalized[normalized.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        )

        if !emailPart.contains("@") {
            return nil
        }

        return (
            email: emailPart.isEmpty ? nil : emailPart,
            projectId: projectPart.isEmpty ? nil : projectPart
        )
    }

    private static func normalizeGeminiProjectIdentifier(_ raw: String) -> String {
        var project = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !project.isEmpty else { return "" }
        if let separator = project.range(of: "--", options: .backwards) {
            let suffix = project[separator.upperBound...]
            let isCredentialSuffix = !suffix.isEmpty && suffix.allSatisfy { $0.isNumber || $0.isLetter }
            if isCredentialSuffix {
                project = String(project[..<separator.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return project
    }

    private static func isGeminiProjectPotentialMatch(existingProject: String?, targetProject: String) -> Bool {
        let normalizedTarget = targetProject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTarget.isEmpty else { return false }

        guard let rawExisting = existingProject?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawExisting.isEmpty else {
            return false
        }

        if rawExisting.caseInsensitiveCompare(normalizedTarget) == .orderedSame {
            return true
        }

        let targetLowercased = normalizedTarget.lowercased()
        let existingLowercased = rawExisting.lowercased()
        if targetLowercased == "all" || existingLowercased == "all" {
            return true
        }

        if rawExisting.contains(",") {
            let projectTokens = rawExisting
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
            if projectTokens.contains("all") || projectTokens.contains(targetLowercased) {
                return true
            }
        }

        return false
    }
    
    var body: some View {
        VStack(spacing: 28) {
            ProviderIcon(provider: provider, size: 64)
            
            VStack(spacing: 8) {
                Text("oauth.connect".localized() + " " + provider.displayName)
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("oauth.authenticateWith".localized() + " " + provider.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            if provider == .gemini {
                VStack(alignment: .leading, spacing: 6) {
                    Text("oauth.projectId".localized())
                        .font(.subheadline)
                        .fontWeight(.medium)
                    TextField("oauth.projectIdPlaceholder".localized(), text: $projectId)
                        .textFieldStyle(.roundedBorder)

                    geminiOverwriteNotice
                }
                .frame(maxWidth: 320)
            }
            
            if provider == .kiro {
                VStack(alignment: .leading, spacing: 6) {
                    Text("oauth.authMethod".localized())
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Picker("", selection: $selectedKiroMethod) {
                        ForEach(kiroAuthMethods, id: \.self) { method in
                            Text(method.displayName).tag(method)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    

                }
                .frame(maxWidth: 320)
            }
            
            if let state = viewModel.oauthState, state.provider == provider {
                OAuthStatusView(status: state.status, error: state.error, state: state.state, authURL: state.authURL, provider: provider)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
            
            HStack(spacing: 16) {
                Button("action.cancel".localized(), role: .cancel) {
                    viewModel.cancelOAuth()
                    onDismiss()
                }
                .buttonStyle(.bordered)
                
                if isError {
                    Button {
                        hasStartedAuth = false
                        Task {
                            await viewModel.startOAuth(for: provider, projectId: projectId.isEmpty ? nil : projectId, authMethod: provider == .kiro ? selectedKiroMethod : nil)
                        }
                    } label: {
                        Label("oauth.retry".localized(), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                } else if !isSuccess {
                    Button {
                        hasStartedAuth = true
                        Task {
                            await viewModel.startOAuth(for: provider, projectId: projectId.isEmpty ? nil : projectId, authMethod: provider == .kiro ? selectedKiroMethod : nil)
                        }
                    } label: {
                        if isPolling {
                            SmallProgressView()
                        } else {
                            Label("oauth.authenticate".localized(), systemImage: "key.fill")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(provider.color)
                    .disabled(isPolling)
                }
            }
        }
        .padding(40)
        .frame(width: 480)
        .frame(minHeight: 350)
        .fixedSize(horizontal: false, vertical: true)
        .animation(.easeInOut(duration: 0.2), value: viewModel.oauthState?.status)
        .onChange(of: viewModel.oauthState?.status) { _, newStatus in
            if newStatus == .success {
                Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    onDismiss()
                }
            }
        }
    }
}

private struct OAuthStatusView: View {
    let status: OAuthState.OAuthStatus
    let error: String?
    let state: String?
    let authURL: String?
    let provider: AIProvider
    
    /// Stable rotation angle for spinner animation (fixes UUID() infinite re-render)
    @State private var rotationAngle: Double = 0
    
    /// Visual feedback for copy action
    @State private var copied = false
    
    var body: some View {
        Group {
            switch status {
            case .waiting:
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("oauth.openingBrowser".localized())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 16)
                
            case .polling:
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .stroke(provider.color.opacity(0.2), lineWidth: 4)
                            .frame(width: 60, height: 60)
                        
                        Circle()
                            .trim(from: 0, to: 0.7)
                            .stroke(provider.color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .frame(width: 60, height: 60)
                            .rotationEffect(.degrees(rotationAngle - 90))
                            .onAppear {
                                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                                    rotationAngle = 360
                                }
                            }
                        
                        Image(systemName: "person.badge.key.fill")
                            .font(.title2)
                            .foregroundStyle(provider.color)
                    }
                    
                    // For Copilot Device Code flow, show device code with copy button
                    if provider == .copilot, let deviceCode = state, !deviceCode.isEmpty {
                        VStack(spacing: 8) {
                            Text("oauth.enterCodeInBrowser".localized())
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            
                            HStack(spacing: 12) {
                                Text(deviceCode)
                                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                                    .foregroundStyle(provider.color)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(provider.color.opacity(0.1))
                                    .cornerRadius(8)
                                
                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(deviceCode, forType: .string)
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                        .font(.title3)
                                }
                                .buttonStyle(.subtle)
                                .help("action.copyCode".localized())
                            }
                            
                            Text("oauth.waitingForAuth".localized())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if provider == .copilot, let message = error {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 350)
                    } else {
                        Text("oauth.waitingForAuth".localized())
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        // Show auth URL with copy/open buttons
                        if let urlString = authURL, let url = URL(string: urlString) {
                            VStack(spacing: 12) {
                                Text("oauth.copyLinkOrOpen".localized())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
                                HStack(spacing: 12) {
                                    Button {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(urlString, forType: .string)
                                        copied = true
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                            copied = false
                                        }
                                    } label: {
                                        Label(copied ? "oauth.copied".localized() : "oauth.copyLink".localized(), systemImage: copied ? "checkmark" : "doc.on.doc")
                                    }
                                    .buttonStyle(.bordered)
                                    
                                    Button {
                                        NSWorkspace.shared.open(url)
                                    } label: {
                                        Label("oauth.openLink".localized(), systemImage: "safari")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(provider.color)
                                }
                            }
                        } else {
                            Text("oauth.completeBrowser".localized())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 16)
                
            case .success:
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.green)
                    
                    Text("oauth.success".localized())
                        .font(.headline)
                        .foregroundStyle(.green)
                    
                    Text("oauth.closingSheet".localized())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 16)
                
            case .error:
                VStack(spacing: 12) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.red)
                    
                    Text("oauth.failed".localized())
                        .font(.headline)
                        .foregroundStyle(.red)
                    
                    if let error = error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 300)
                    }
                }
                .padding(.vertical, 16)
            }
        }
        .frame(minHeight: 100)
    }
}

// MARK: - Custom Provider Sheet Mode

enum CustomProviderSheetMode: Identifiable {
    case add
    case edit(CustomProvider)

    var id: String {
        switch self {
        case .add:
            return "add"
        case .edit(let provider):
            return provider.id.uuidString
        }
    }

    var provider: CustomProvider? {
        switch self {
        case .add:
            return nil
        case .edit(let provider):
            return provider
        }
    }
}
