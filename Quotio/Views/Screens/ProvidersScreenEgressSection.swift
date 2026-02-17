//
//  ProvidersScreenEgressSection.swift
//  Quotio
//

import SwiftUI
import AppKit

extension ProvidersScreen {
    // MARK: - Egress Mapping Section
    @ViewBuilder
    var egressMappingSection: some View {
        Section {
            if let message = egressMappingError, !message.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("status.error".localized(), systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.semanticWarning)
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
                .foregroundStyle(snapshot.enabled == true ? Color.semanticSuccess : .secondary)
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
            HStack(spacing: 12) {
                egressSummaryChip(title: "providers.egress.chip.accounts".localized(), value: snapshot.totalAccounts)
                egressSummaryChip(title: "providers.egress.chip.drifted".localized(), value: snapshot.driftedAccounts)
                egressSummaryChip(title: "providers.egress.chip.alerted".localized(), value: snapshot.alertedAccounts)
                egressSummaryChip(title: "providers.egress.chip.inconsistent".localized(), value: snapshot.inconsistentAccounts)
                egressSummaryChip(title: "logs.all".localized(), value: visibleCount)
            }
        }
        .padding(.vertical, 4)
    }
    @ViewBuilder
    private func egressControlsView(snapshot: EgressMappingResponse, visibleCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
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
        .padding(.vertical, 4)
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
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }
                Spacer()
                if let driftCount = account.driftCount {
                    Text(String(format: "providers.egress.drift".localized(), driftCount))
                        .font(.caption)
                        .foregroundStyle(driftCount > 0 ? Color.semanticWarning : .secondary)
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
                .foregroundStyle(hasIssues ? Color.semanticWarning : Color.semanticSuccess)
                if account.driftAlerted == true {
                    Label("providers.egress.alerted".localized(), systemImage: "bell.badge.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.semanticWarning)
                }
                if let status = account.consistencyStatus, !status.isEmpty {
                    Text(String(format: "providers.egress.status".localized(), localizedConsistencyStatus(status)))
                        .font(.caption2)
                        .foregroundStyle(status.lowercased() == "ok" ? Color.secondary : Color.semanticWarning)
                }
            }
            if !account.consistencyIssues.isEmpty {
                Text(account.consistencyIssues.joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
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
    func refreshEgressMapping() async {
        guard let client = viewModel.apiClient else {
            egressMapping = nil
            egressMappingError = nil
            return
        }
        uiMetrics.begin("providers.egress.refresh")
        isRefreshingEgressMapping = true
        defer {
            isRefreshingEgressMapping = false
            uiMetrics.end(
                "providers.egress.refresh",
                metadata: egressMappingError == nil ? "ok" : "error"
            )
        }
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
}
