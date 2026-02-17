//
//  ProviderDisclosureGroup.swift
//  Quotio
//
//  Collapsible group for displaying accounts grouped by provider.
//  Part of ProvidersScreen UI/UX redesign.
//

import SwiftUI

// MARK: - Provider Disclosure Group

/// A collapsible disclosure group that displays all accounts for a specific provider
struct ProviderDisclosureGroup: View {
    let provider: AIProvider
    let accounts: [AccountRowData]
    var onDeleteAccount: ((AccountRowData) -> Void)?
    var onEditAccount: ((AccountRowData) -> Void)?
    var onSwitchAccount: ((AccountRowData) -> Void)?
    var onToggleDisabled: ((AccountRowData) -> Void)?
    var isAccountActive: ((AccountRowData) -> Bool)?
    var compactMode: Bool = false

    @State private var isExpanded: Bool = true
    @State private var uiExperience = UIExperienceSettingsManager.shared
    @State private var featureFlags = FeatureFlagManager.shared

    /// Check if all accounts in this group are auto-detected
    private var isAllAutoDetected: Bool {
        accounts.allSatisfy { $0.source == .autoDetected }
    }

    private var issueCount: Int {
        accounts.filter { account in
            let status = (account.status ?? "").lowercased()
            return status == "error" || status == "cooling" || account.isDisabled
        }.count
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(accounts) { account in
                AccountRow(
                    account: account,
                    onDelete: onDeleteAccount != nil ? { onDeleteAccount?(account) } : nil,
                    onEdit: onEditAccount != nil ? { onEditAccount?(account) } : nil,
                    onSwitch: onSwitchAccount != nil ? { onSwitchAccount?(account) } : nil,
                    onToggleDisabled: onToggleDisabled != nil ? { onToggleDisabled?(account) } : nil,
                    isActiveInIDE: isAccountActive?(account) ?? false,
                    compactMode: compactMode
                )
                .padding(.leading, 4)
                .frame(minHeight: uiExperience.recommendedMinimumRowHeight)
            }
        } label: {
            providerHeader
        }
    }
    
    // MARK: - Provider Header
    
    private var providerHeader: some View {
        HStack(spacing: 12) {
            // Provider icon
            ProviderIcon(provider: provider, size: 20)
            
            // Provider name
            Text(provider.displayName)
                .fontWeight(.medium)
            
            // Account count badge
            Text("\(accounts.count)")
                .font(.caption2)
                .fontWeight(.semibold)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.12))
                .foregroundStyle(.secondary)
                .clipShape(Capsule())

            if featureFlags.enhancedUILayout && issueCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                    Text("\(issueCount)")
                        .font(.caption2)
                        .fontWeight(.semibold)
                }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.semanticWarning.opacity(0.15))
                    .foregroundStyle(Color.semanticWarning)
                    .clipShape(Capsule())
                    .accessibilityLabel("providers.issues".localized(fallback: "异常数量"))
                    .accessibilityValue("\(issueCount)")
            }
            
            Spacer()
            
            // Auto-detected indicator (when all accounts are auto-detected)
            if isAllAutoDetected {
                Text("providers.autoDetected".localized())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Capsule())
            }
        }
    }
}

// MARK: - Preview

#Preview {
    List {
        ProviderDisclosureGroup(
            provider: .gemini,
            accounts: [
                AccountRowData(
                    id: "1",
                    provider: .gemini,
                    displayName: "user@gmail.com",
                    source: .proxy,
                    status: "ready",
                    statusMessage: nil,
                    isDisabled: false,
                    canDelete: true
                ),
                AccountRowData(
                    id: "2",
                    provider: .gemini,
                    displayName: "work@company.com",
                    source: .proxy,
                    status: "cooling",
                    statusMessage: "Rate limited",
                    isDisabled: false,
                    canDelete: true
                )
            ]
        )
        
        ProviderDisclosureGroup(
            provider: .cursor,
            accounts: [
                AccountRowData(
                    id: "3",
                    provider: .cursor,
                    displayName: "dev@example.com",
                    source: .autoDetected,
                    status: nil,
                    statusMessage: nil,
                    isDisabled: false,
                    canDelete: false
                )
            ]
        )
    }
}
