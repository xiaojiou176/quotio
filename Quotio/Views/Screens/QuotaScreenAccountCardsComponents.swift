//
//  QuotaScreenAccountCardsComponents.swift
//  Quotio
//

import SwiftUI

struct AccountQuotaCardV2: View {
    @Environment(QuotaViewModel.self) private var viewModel
    
    private var settings: MenuBarSettingsManager { MenuBarSettingsManager.shared }
    let provider: AIProvider
    let account: AccountInfo
    let isLoading: Bool
    
    @State private var isRefreshing = false
    @State private var isDeleting = false
    @State private var showSwitchSheet = false
    @State private var showModelsDetailSheet = false
    @State private var showDeleteConfirmation = false

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
    private var antigravityDisplayGroups: [QuotaAntigravityDisplayGroup] {
        guard let data = account.quotaData, provider == .antigravity else { return [] }
        
        var groups: [QuotaAntigravityDisplayGroup] = []
        
        let gemini3ProModels = data.models.filter { 
            $0.name.contains("gemini-3-pro") && !$0.name.contains("image") 
        }
        if !gemini3ProModels.isEmpty {
            let aggregatedQuota = settings.aggregateModelPercentages(gemini3ProModels.map(\.percentage))
            if aggregatedQuota >= 0 {
                groups.append(QuotaAntigravityDisplayGroup(name: "Gemini 3 Pro", percentage: aggregatedQuota, models: gemini3ProModels))
            }
        }
        
        let gemini3FlashModels = data.models.filter { $0.name.contains("gemini-3-flash") }
        if !gemini3FlashModels.isEmpty {
            let aggregatedQuota = settings.aggregateModelPercentages(gemini3FlashModels.map(\.percentage))
            if aggregatedQuota >= 0 {
                groups.append(QuotaAntigravityDisplayGroup(name: "Gemini 3 Flash", percentage: aggregatedQuota, models: gemini3FlashModels))
            }
        }
        
        let geminiImageModels = data.models.filter { $0.name.contains("image") }
        if !geminiImageModels.isEmpty {
            let aggregatedQuota = settings.aggregateModelPercentages(geminiImageModels.map(\.percentage))
            if aggregatedQuota >= 0 {
                groups.append(QuotaAntigravityDisplayGroup(name: "Gemini 3 Image", percentage: aggregatedQuota, models: geminiImageModels))
            }
        }
        
        let claudeModels = data.models.filter { $0.name.contains("claude") }
        if !claudeModels.isEmpty {
            let aggregatedQuota = settings.aggregateModelPercentages(claudeModels.map(\.percentage))
            if aggregatedQuota >= 0 {
                groups.append(QuotaAntigravityDisplayGroup(name: "Claude", percentage: aggregatedQuota, models: claudeModels))
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

            if let failure = latestFetchFailure {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.semanticDanger)
                    Text("quota.lastFetchFailure".localized(fallback: "最近刷新失败") + ": " + failure)
                        .font(.caption)
                        .foregroundStyle(Color.semanticDanger)
                        .multilineTextAlignment(.leading)
                }
                .padding(.top, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
    }

    private var latestFetchFailure: String? {
        guard !hasQuotaData else { return nil }
        guard let failures = viewModel.providerQuotaFailures[provider], !failures.isEmpty else {
            return nil
        }

        for key in failureLookupKeys() {
            if let failure = failures[key], !failure.isEmpty {
                return failure
            }
            let normalized = key.lowercased()
            if let failure = failures[normalized], !failure.isEmpty {
                return failure
            }
        }
        return nil
    }

    private func failureLookupKeys() -> [String] {
        var keys = Set<String>()

        func add(_ value: String?) {
            guard let value else { return }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            keys.insert(trimmed)
        }

        add(account.key)
        add(account.email)
        add(account.authFile?.email)
        add(account.authFile?.quotaLookupKey)
        add(account.authFile?.name)

        if let fileName = account.authFile?.name,
           fileName.hasPrefix("codex-"),
           fileName.hasSuffix(".json") {
            let stripped = fileName
                .replacingOccurrences(of: "codex-", with: "")
                .replacingOccurrences(of: ".json", with: "")
            add(stripped)
            if stripped.hasSuffix("-team") {
                add(String(stripped.dropLast("-team".count)))
            }
        }

        // Keep deterministic order for easier debugging.
        return Array(keys).sorted()
    }
    
    // MARK: - Account Header

    private var accountHeader: some View {
        HStack(spacing: 12) {
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
                            .foregroundStyle(Color.semanticOnAccent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
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

                if account.authFile?.isFatalDisabled == true, account.authFile != nil {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        if isDeleting {
                            ProgressView()
                                .controlSize(.mini)
                                .frame(width: 28, height: 28)
                        } else {
                            Image(systemName: "trash.fill")
                                .font(.caption)
                                .foregroundStyle(Color.semanticDanger)
                                .frame(width: 28, height: 28)
                                .background(Color.semanticDanger.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isDeleting || isLoading)
                    .help("action.delete".localized(fallback: "删除"))
                    .accessibilityLabel("action.delete".localized(fallback: "删除"))
                }
                
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
                        .accessibilityLabel("quota.reauthenticate".localized())
                    } else {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.semanticDanger)
                            .frame(width: 28, height: 28)
                            .background(Color.semanticDanger.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .help("limit.reached".localized(fallback: "额度已达上限"))
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
        .confirmationDialog("providers.deleteConfirm".localized(fallback: "确认删除该账号？"), isPresented: $showDeleteConfirmation) {
            Button("action.delete".localized(fallback: "删除"), role: .destructive) {
                guard let authFile = account.authFile else { return }
                Task {
                    isDeleting = true
                    await viewModel.deleteAuthFile(authFile)
                    isDeleting = false
                }
            }
            Button("action.cancel".localized(fallback: "取消"), role: .cancel) {}
        } message: {
            Text("providers.deleteMessage".localized(fallback: "删除后将无法继续使用该账号，请确认。"))
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
