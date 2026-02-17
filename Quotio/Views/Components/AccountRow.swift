//
//  AccountRow.swift
//  Quotio
//
//  Unified account row component for ProvidersScreen.
//  Replaces: AuthFileRow, DirectAuthFileRow, AutoDetectedAccountRow
//

import SwiftUI

// MARK: - AccountRow View

struct AccountRow: View {
    let account: AccountRowData
    var onDelete: (() -> Void)?
    var onEdit: (() -> Void)?
    var onSwitch: (() -> Void)?
    var onToggleDisabled: (() -> Void)?
    var isActiveInIDE: Bool = false
    var compactMode: Bool = false
    
    @State private var settings = MenuBarSettingsManager.shared
    @State private var featureFlags = FeatureFlagManager.shared
    @State private var uiExperience = UIExperienceSettingsManager.shared
    @State private var showWarning = false
    @State private var showMaxItemsAlert = false
    @State private var showDeleteConfirmation = false
    
    private var isMenuBarSelected: Bool {
        settings.isSelected(account.menuBarItem)
    }
    
    private var maskedDisplayName: String {
        account.displayName.masked(if: settings.hideSensitiveInfo)
    }
    
    private var statusColor: Color {
        switch account.status {
        case "ready", "active": return account.isDisabled ? .secondary : .semanticSuccess
        case "cooling": return .semanticWarning
        case "error": return .semanticDanger
        default: return .secondary
        }
    }

    private var statusSymbol: String {
        switch account.status {
        case "ready", "active": return account.isDisabled ? "pause.circle.fill" : "checkmark.circle.fill"
        case "cooling": return "clock.badge.exclamationmark"
        case "error": return "xmark.circle.fill"
        default: return "questionmark.circle"
        }
    }

    private var statusDisplayText: String? {
        guard let status = account.status else { return nil }
        switch status {
        case "ready", "active":
            return "quota.status.ready".localized(fallback: "可用")
        case "cooling":
            return "quota.status.cooling".localized(fallback: "冷却中")
        case "error":
            return "quota.status.error".localized(fallback: "错误")
        default:
            return status.localizedCapitalized
        }
    }

    private var normalizedErrorKind: String {
        account.errorKind?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }

    private var normalizedErrorReason: String {
        account.errorReason?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }

    private var requiresRelogin: Bool {
        if normalizedErrorKind == "unauthorized" || normalizedErrorKind == "account_deactivated" {
            return true
        }
        if normalizedErrorReason.contains("token_invalidated") ||
            normalizedErrorReason.contains("token has been invalidated") ||
            normalizedErrorReason.contains("authentication token has been invalidated") {
            return true
        }
        return false
    }

    private var permanentlyInvalid: Bool {
        if normalizedErrorKind == "workspace_deactivated" {
            return true
        }
        if account.disabledByPolicy && (normalizedErrorKind == "workspace_deactivated" || normalizedErrorKind == "account_deactivated") {
            return true
        }
        return false
    }

    private var errorKindDisplayText: String? {
        guard !normalizedErrorKind.isEmpty else { return nil }
        switch normalizedErrorKind {
        case "quota_limited_5h":
            return "account.errorKind.quota5h".localized(fallback: "5h 冷却")
        case "quota_limited_7d":
            return "account.errorKind.quota7d".localized(fallback: "7d 冷却")
        case "quota_limited":
            return "account.errorKind.rateLimited".localized(fallback: "限流")
        case "network_error":
            return "account.errorKind.networkError".localized(fallback: "网络抖动")
        case "workspace_deactivated":
            return "account.errorKind.workspaceDeactivated".localized(fallback: "工作区停用")
        case "account_deactivated":
            return "account.errorKind.accountDeactivated".localized(fallback: "账号停用")
        case "unauthorized":
            return "account.errorKind.unauthorized".localized(fallback: "鉴权失败")
        default:
            return normalizedErrorKind
        }
    }
    
    var body: some View {
        HStack(spacing: compactMode ? 8 : 12) {
            // Provider icon
            ProviderIcon(provider: account.provider, size: compactMode ? 18 : 24)
            
            // Account info
            VStack(alignment: .leading, spacing: 2) {
                Text(maskedDisplayName)
                    .font(compactMode ? .subheadline : .body)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    // Provider name
                    Text(account.provider.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    // Status indicator (only for proxy accounts)
                    if let statusText = statusDisplayText {
                        Image(systemName: statusSymbol)
                            .font(.caption2)
                            .foregroundStyle(statusColor)
                            .accessibilityHidden(true)

                        Text(statusText)
                            .font(.caption)
                            .foregroundStyle(statusColor)
                    } else {
                        // Source indicator for non-proxy accounts
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        
                        Text(account.source.displayName)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                if !compactMode, let reason = account.errorReason, !reason.isEmpty {
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Team badge
            if !compactMode, account.isTeamAccount {
                Text("account.badge.team".localized(fallback: "团队"))
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.semanticOnAccent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.semanticAccentSecondary)
                    .clipShape(Capsule())
            }
            
            // Disabled badge
            if account.isDisabled {
                Text("providers.disabled".localized())
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(.secondary.opacity(0.2))
                    .clipShape(Capsule())
            }

            if !compactMode, permanentlyInvalid {
                Text("account.status.permanent".localized(fallback: "永久失效"))
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.semanticDanger)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.semanticDanger.opacity(0.15))
                    .clipShape(Capsule())
            } else if !compactMode, requiresRelogin {
                Text("account.status.relogin".localized(fallback: "需重登"))
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.semanticWarning)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.semanticWarning.opacity(0.15))
                    .clipShape(Capsule())
            }

            if !compactMode, account.disabledByPolicy {
                Text("account.badge.policy".localized(fallback: "策略禁用"))
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.semanticDanger)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.semanticDanger.opacity(0.12))
                    .clipShape(Capsule())
            }

            if !compactMode, let kind = errorKindDisplayText {
                Text(kind)
                    .font(.caption2)
                    .foregroundStyle(Color.semanticWarning)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.semanticWarning.opacity(0.12))
                    .clipShape(Capsule())
            }

            if !compactMode, let frozenUntil = account.frozenUntil, frozenUntil > Date() {
                Text("\("account.badge.until".localized(fallback: "截至")) \(frozenUntil.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            // Active in IDE badge (Antigravity only)
            if account.provider == .antigravity && isActiveInIDE {
                Text("antigravity.active".localized())
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.semanticSuccess)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.semanticSuccess.opacity(0.15))
                    .clipShape(Capsule())
            }
            
            // Switch button (Antigravity only, for proxy/direct accounts that are not active)
            if !compactMode, account.provider == .antigravity && !isActiveInIDE && account.source != .autoDetected {
                Button {
                    onSwitch?()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.caption2)
                        Text("antigravity.useInIDE".localized())
                            .font(.caption2)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.semanticSelectionFill)
                    .foregroundStyle(Color.semanticInfo)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("antigravity.switch.title".localized())
            }
            
            // Menu bar toggle
            if !compactMode {
                MenuBarBadge(
                    isSelected: isMenuBarSelected,
                    onTap: handleMenuBarToggle
                )
            }

            if featureFlags.enhancedUILayout {
                Menu {
                    if account.provider == .antigravity && !isActiveInIDE && account.source != .autoDetected {
                        Button {
                            onSwitch?()
                        } label: {
                            Label("antigravity.switch.title".localized(), systemImage: "arrow.triangle.2.circlepath")
                        }
                    }

                    if account.source == .proxy, let onToggleDisabled = onToggleDisabled {
                        Button {
                            onToggleDisabled()
                        } label: {
                            if account.isDisabled {
                                Label("providers.enable".localized(), systemImage: "checkmark.circle")
                            } else {
                                Label("providers.disable".localized(), systemImage: "minus.circle")
                            }
                        }
                    }

                    if account.canEdit, let onEdit = onEdit {
                        Button {
                            onEdit()
                        } label: {
                            Label("action.edit".localized(), systemImage: "pencil")
                        }
                    }

                    if account.canDelete, onDelete != nil {
                        Divider()
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label("action.delete".localized(), systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                }
                .menuStyle(.borderlessButton)
                .help("action.more".localized(fallback: "更多操作"))
                .accessibilityLabel("action.more".localized(fallback: "更多操作"))
            } else {
                // Disable/Enable toggle button (only for proxy accounts)
                if account.source == .proxy, let onToggleDisabled = onToggleDisabled {
                    Button {
                        onToggleDisabled()
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(account.isDisabled ? Color.semanticDanger.opacity(0.1) : Color.clear)
                                .frame(width: 28, height: 28)

                            Image(systemName: account.isDisabled ? "xmark.circle.fill" : "checkmark.circle")
                                .font(.system(size: 14))
                                .foregroundStyle(account.isDisabled ? Color.semanticDanger : .secondary)
                        }
                    }
                    .buttonStyle(.rowAction)
                    .help(account.isDisabled ? "providers.enable".localized() : "providers.disable".localized())
                    .accessibilityLabel(account.isDisabled ? "providers.enable".localized() : "providers.disable".localized())
                }

                // Edit button (GLM only)
                if account.canEdit, let onEdit = onEdit {
                    Button {
                        onEdit()
                    } label: {
                        Image(systemName: "pencil")
                            .foregroundStyle(Color.semanticInfo)
                    }
                    .buttonStyle(.rowAction)
                    .help("action.edit".localized())
                    .accessibilityLabel("action.edit".localized())
                }

                // Delete button (only for proxy accounts)
                if account.canDelete, onDelete != nil {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(Color.semanticDanger.opacity(0.8))
                    }
                    .buttonStyle(.rowActionDestructive)
                    .help("action.delete".localized())
                    .accessibilityLabel("action.delete".localized())
                }
            }
        }
        .frame(minHeight: uiExperience.recommendedMinimumRowHeight)
        .contentShape(Rectangle())
        .contextMenu {
            // Switch account option (Antigravity only)
            if account.provider == .antigravity && !isActiveInIDE && account.source != .autoDetected {
                Button {
                    onSwitch?()
                } label: {
                    Label("antigravity.switch.title".localized(), systemImage: "arrow.triangle.2.circlepath")
                }
                
                Divider()
            }
            
            // Menu bar toggle
            Button {
                handleMenuBarToggle()
            } label: {
                if isMenuBarSelected {
                    Label("menubar.hideFromMenuBar".localized(), systemImage: "chart.bar")
                } else {
                    Label("menubar.showOnMenuBar".localized(), systemImage: "chart.bar.fill")
                }
            }

            // Disable/Enable toggle (only for proxy accounts)
            if account.source == .proxy, let onToggleDisabled = onToggleDisabled {
                Button {
                    onToggleDisabled()
                } label: {
                    if account.isDisabled {
                        Label("providers.enable".localized(), systemImage: "checkmark.circle")
                    } else {
                        Label("providers.disable".localized(), systemImage: "minus.circle")
                    }
                }
            }

            // Delete option (only for proxy accounts)
            if account.canDelete, onDelete != nil {
                Divider()
                
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("action.delete".localized(), systemImage: "trash")
                }
            }
        }
        .confirmationDialog("providers.deleteConfirm".localized(), isPresented: $showDeleteConfirmation) {
            Button("action.delete".localized(), role: .destructive) {
                onDelete?()
            }
            Button("action.cancel".localized(), role: .cancel) {}
        } message: {
            Text("providers.deleteMessage".localized())
        }
        .alert("menubar.warning.title".localized(), isPresented: $showWarning) {
            Button("menubar.warning.confirm".localized()) {
                settings.toggleItem(account.menuBarItem)
            }
            Button("menubar.warning.cancel".localized(), role: .cancel) {}
        } message: {
            Text("menubar.warning.message".localized())
        }
        .alert("menubar.maxItems.title".localized(), isPresented: $showMaxItemsAlert) {
            Button("action.ok".localized(), role: .cancel) {}
        } message: {
            Text(String(
                format: "menubar.maxItems.message".localized(),
                settings.menuBarMaxItems
            ))
        }
    }
    
    private func handleMenuBarToggle() {
        if isMenuBarSelected {
            settings.toggleItem(account.menuBarItem)
        } else if settings.isAtMaxItems {
            showMaxItemsAlert = true
        } else if settings.shouldWarnOnAdd {
            showWarning = true
        } else {
            settings.toggleItem(account.menuBarItem)
        }
    }
}
